import Foundation
import Network

/// Meter scheduling shares the app's settings socket. Standalone read-only probes
/// can still own a socket. All mutable scheduler state belongs to `queue`.
public final class MeterStream: @unchecked Sendable {
    private let queue = DispatchQueue(label: "nl.rob.vp2x.meters", qos: .userInteractive)
    private var connection: NWConnection?
    private var ownsConnection = false
    private var timer: DispatchSourceTimer?
    private var requestTimer: DispatchSourceTimer?
    private var generation = UUID()
    private var ids: [Int] = []
    private var cursor = 0
    private var paused = false
    private var samples: [Int: (value: Int, time: Double)] = [:]
    private var outstanding: [Int: Double] = [:]
    private var lastSent: [Int: Double] = [:]
    private var sweepReplies: Set<Int> = []
    private var receivedReplies = 0
    private var completedSweeps = 0
    public init() {}

    public func start(host: String, ids: [Int], frame: @escaping @Sendable (MeterFrame) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            guard VPProtocol.validIPv4(host) else { return }
            self.ids = ids.filter { MeterPlan.all.contains($0) }
            let token = generation
            let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: VPProtocol.port)!, using: .udp)
            connection = conn; ownsConnection = true
            conn.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == token else { return }
                if case .ready = state { self.runTimers(conn, token: token, frame: frame) }
            }
            conn.start(queue: queue)
            receive(conn, token: token)
        }
    }
    /// The caller owns the connection and routes received datagrams through ingest.
    public func start(sharedConnection: NWConnection, ids: [Int], frame: @escaping @Sendable (MeterFrame) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            connection = sharedConnection
            self.ids = ids.filter { MeterPlan.all.contains($0) }
            runTimers(sharedConnection, token: generation, frame: frame)
        }
    }
    public func setPaused(_ paused: Bool) { queue.async { self.paused = paused } }
    public func ingest(_ data: Data) {
        queue.async { [self] in
            guard connection != nil else { return }
            accept(data)
        }
    }
    private func runTimers(_ conn: NWConnection, token: UUID, frame: @escaping @Sendable (MeterFrame) -> Void) {
        guard timer == nil else { return }
        let display = DispatchSource.makeTimerSource(queue: queue)
        display.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(1))
        display.setEventHandler { [weak self] in
            guard let self, self.generation == token else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let fresh = self.samples.filter { now - $0.value.time < 0.25 && self.ids.contains($0.key) }.mapValues(\.value)
            frame(MeterFrame(values: fresh, receivedReplies: self.receivedReplies, completedSweeps: self.completedSweeps))
        }
        timer = display; display.resume()
        // Spread queries instead of sending bursts of eight packets. The original
        // controller uses a 50 ms meter period. Settings requests take priority.
        let requests = DispatchSource.makeTimerSource(queue: queue)
        requests.schedule(deadline: .now(), repeating: .milliseconds(6), leeway: .milliseconds(1))
        requests.setEventHandler { [weak self] in
            guard let self, self.generation == token, !self.paused, !self.ids.isEmpty else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for _ in self.ids.indices {
                self.cursor %= self.ids.count
                let id = self.ids[self.cursor]; self.cursor += 1
                if let sent = self.lastSent[id], now - sent < 0.05 { continue }
                if let sent = self.outstanding[id], now - sent < 0.20 { continue }
                self.lastSent[id] = now; self.outstanding[id] = now
                conn.send(content: Data(VPProtocol.get(id).utf8), completion: .contentProcessed { _ in })
                break
            }
        }
        requestTimer = requests; requests.resume()
    }
    public func select(ids: [Int]) {
        queue.async { [self] in
            self.ids = ids.filter { MeterPlan.all.contains($0) }
            outstanding = outstanding.filter { self.ids.contains($0.key) }
            sweepReplies.removeAll()
        }
    }
    public func stop() { queue.async { [self] in stopOnQueue() } }
    private func stopOnQueue() {
        generation = UUID()
        timer?.cancel(); timer = nil
        requestTimer?.cancel(); requestTimer = nil
        if ownsConnection {
            connection?.stateUpdateHandler = nil
            connection?.cancel()
        }
        connection = nil; ownsConnection = false; paused = false; cursor = 0
        samples.removeAll(); outstanding.removeAll(); lastSent.removeAll(); sweepReplies.removeAll()
        receivedReplies = 0; completedSweeps = 0
    }
    private func accept(_ data: Data) {
        let now = ProcessInfo.processInfo.systemUptime
        for (id, value) in VPProtocol.parse(data) where ids.contains(id) {
            samples[id] = (value, now); outstanding.removeValue(forKey: id)
            receivedReplies += 1; sweepReplies.insert(id)
        }
        if !ids.isEmpty, Set(ids).isSubset(of: sweepReplies) {
            completedSweeps += 1; sweepReplies.removeAll()
        }
    }
    private func receive(_ conn: NWConnection, token: UUID) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.generation == token else { return }
            if let data { self.accept(data) }
            if error == nil { self.receive(conn, token: token) }
        }
    }
}
