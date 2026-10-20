import Foundation

/// Converts trackpad pixels and mouse-wheel ticks into bounded precision steps.
public struct FaderWheelSteps {
    private var remainder = 0.0
    public init() {}
    public mutating func reset() { remainder = 0 }
    public mutating func consume(delta: Double, precise: Bool) -> Int {
        guard delta.isFinite, delta != 0 else { return 0 }
        if !precise { remainder = 0; return delta > 0 ? 1 : -1 }
        if remainder * delta < 0 { remainder = 0 }
        remainder += max(-64, min(64, delta))
        let steps = Int(remainder / 8)
        remainder -= Double(steps) * 8
        return steps
    }
}
