import Foundation
import Combine
import VP2xCore

@MainActor final class MeterStore: ObservableObject {
    @Published private(set) var values: [Int: Int] = [:]
    private let stream = MeterStream()
    private var session = UUID()
    var diagnostics: ((String) -> Void)?
    func start(client: VPClient, ids: [Int]) {
        stop()
        let token = session
        var frames = 0
        var previousReplies = 0
        var previousSweeps = 0
        var started = ProcessInfo.processInfo.systemUptime
        client.attachMeters(stream, ids: ids) { [weak self] frame in
            Task { @MainActor in
                guard let self, self.session == token else { return }
                self.values = frame.values
                frames += 1
                let now = ProcessInfo.processInfo.systemUptime
                if now - started >= 5 {
                    let seconds = now - started
                    self.diagnostics?(String(format: "Meters: %.1f updates/s · %.1f complete uitlezingen/s · %.1f antwoorden/s · %d meters",
                        Double(frames) / seconds, Double(frame.completedSweeps - previousSweeps) / seconds,
                        Double(frame.receivedReplies - previousReplies) / seconds, frame.values.count))
                    frames = 0; previousReplies = frame.receivedReplies; previousSweeps = frame.completedSweeps; started = now
                }
            }
        }
    }
    func select(ids: [Int]) { stream.select(ids: ids) }
    func stop() { session = UUID(); stream.stop(); values.removeAll() }
}

@MainActor final class DeviceActivity: ObservableObject {
    @Published private(set) var entries: [String] = []
    func append(_ entry: String) {
        entries.append(entry)
        if entries.count > 250 { entries.removeFirst(entries.count - 250) }
    }
}
