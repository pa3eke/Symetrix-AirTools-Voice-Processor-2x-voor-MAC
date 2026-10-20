import Foundation

/// Bounds live drag traffic while keeping the newest value per controller.
/// Mouse-up bypasses the timer and removes any older deferred value.
@MainActor public final class LiveControlDispatcher {
    private let interval: TimeInterval
    private let deliver: (Int, Int) -> Void
    private var pending: [Int:Int] = [:]
    private var nextDelivery: TimeInterval = 0
    private var timer: Task<Void,Never>?
    public init(interval: TimeInterval = 0.06, deliver: @escaping (Int, Int) -> Void) {
        self.interval = max(0.01, interval); self.deliver = deliver
    }
    public func submit(_ id: Int, value: Int) {
        pending[id] = min(65535, max(0, value))
        let delay = nextDelivery - ProcessInfo.processInfo.systemUptime
        if delay <= 0 { timer?.cancel(); timer = nil; flush() }
        else if timer == nil {
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self else { return }
                self.timer = nil; self.flush()
            }
        }
    }
    public func finish(_ id: Int, value: Int) {
        pending.removeValue(forKey: id)
        if pending.isEmpty { timer?.cancel(); timer = nil }
        nextDelivery = ProcessInfo.processInfo.systemUptime + interval
        deliver(id, min(65535, max(0, value)))
    }
    public func cancelAll() {
        timer?.cancel(); timer = nil; pending.removeAll(); nextDelivery = 0
    }
    private func flush() {
        guard !pending.isEmpty else { return }
        let values = pending; pending.removeAll()
        nextDelivery = ProcessInfo.processInfo.systemUptime + interval
        for id in values.keys.sorted() { deliver(id, values[id]!) }
    }
}
