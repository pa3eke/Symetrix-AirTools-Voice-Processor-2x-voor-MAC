import Foundation
import Network

/// One request at a time. Replies arrive on the same UDP socket/source port.
@MainActor public final class VPClient {
    public enum Failure: LocalizedError {
        case disconnected, timeout, rejected, invalidAddress
        public var errorDescription: String? {
            switch self {
            case .disconnected: return "Verbinding verbroken."
            case .timeout: return "Geen antwoord van de VP2x. Controleer het netwerk en het IP-adres."
            case .rejected: return "De VP2x heeft de opdracht geweigerd (NAK)."
            case .invalidAddress: return "Vul een geldig IPv4-adres in."
            }
        }
    }
    private var connection: NWConnection?
    private var waiting: CheckedContinuation<Data, Error>?
    private var expectedID: Int?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var meterStream: MeterStream?
    private var requestToken = UUID()
    public init() {}
    public var trace: ((String) -> Void)?

    public func connect(host: String) throws {
        disconnect()
        guard VPProtocol.validIPv4(host) else { throw Failure.invalidAddress }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: VPProtocol.port)!, using: .udp)
        connection = conn
        let token = generation
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.trace?("Netwerk: \(state)")
                if case .failed(let error) = state { self.finish(.failure(error)) }
            }
        }
        conn.start(queue: .main)
        receive(conn, token: token)
    }
    public func attachMeters(_ stream: MeterStream, ids: [Int], frame: @escaping @Sendable (MeterFrame) -> Void) {
        guard let connection else { return }
        meterStream = stream
        stream.start(sharedConnection: connection, ids: ids, frame: frame)
    }
    public func disconnect() {
        meterStream?.stop(); meterStream = nil
        generation = UUID()
        connection?.cancel(); connection = nil
        finish(.failure(Failure.disconnected))
    }
    private func receive(_ conn: NWConnection, token: UUID) {
        conn.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let data, let text = String(data: data, encoding: .ascii) {
                    let parsed = VPProtocol.parse(data)
                    self.meterStream?.ingest(data)
                    if parsed.isEmpty || parsed.keys.contains(where: { !MeterPlan.all.contains($0) }) {
                        self.trace?("← " + text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).contains("NAK") {
                        self.finish(.failure(Failure.rejected))
                    } else if let id = self.expectedID {
                        if VPProtocol.parse(data)[id] != nil { self.finish(.success(data)) }
                    } else if text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).contains("ACK") {
                        self.finish(.success(data))
                    }
                }
                if let error { self.finish(.failure(error)); return }
                self.receive(conn, token: token)
            }
        }
    }
    private func finish(_ result: Result<Data, Error>) {
        requestToken = UUID()
        timeout?.cancel(); timeout = nil
        meterStream?.setPaused(false)
        let continuation = waiting; waiting = nil
        continuation?.resume(with: result)
    }
    private func request(_ command: String, id: Int?) async throws -> Data {
        guard let conn = connection else { throw Failure.disconnected }
        // The store owns one serial worker; no second request may replace a waiter.
        precondition(waiting == nil)
        expectedID = id
        meterStream?.setPaused(true)
        let requestID = UUID(); requestToken = requestID
        trace?("→ " + command.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                self?.finish(.failure(Failure.timeout))
            }
            let token = generation
            conn.send(content: Data(command.utf8), completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self, self.generation == token, self.requestToken == requestID else { return }
                    if let error { self.finish(.failure(error)) }
                }
            })
        }
    }
    public func read(_ id: Int) async throws -> Int {
        // Reads are safe to retry. Never automatically replay writes or recalls.
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let result = try await request(VPProtocol.get(id), id: id)
                guard let value = VPProtocol.parse(result)[id] else { throw Failure.rejected }
                return value
            } catch Failure.timeout {
                if attempt == 2 { throw Failure.timeout }
                trace?("Leesantwoord gemist; nieuwe poging \(attempt + 2)/3 voor \(id)")
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw Failure.timeout
    }

    public func write(_ id: Int, value: Int) async throws -> Int {
        _ = try await request(VPProtocol.set(id, value: value), id: nil)
        return try await read(id) // Hardware can quantize a requested value.
    }
    public func recall(_ number: Int) async throws {
        guard (1...50).contains(number) || (101...150).contains(number) else { throw Failure.rejected }
        // The original 2x application sends controller 0, including the channel-2 bank.
        _ = try await request(VPProtocol.set(0, value: number), id: nil)
    }
}
