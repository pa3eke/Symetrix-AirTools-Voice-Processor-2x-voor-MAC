import Foundation

public enum FaderKeyboardStep {
    /// Linear level controls use 0.1/0.01 display units; logarithmic faders
    /// advance by a small fraction of their travel. Always respect wire limits.
    public static func adjusted(raw: Int, direction: Int, fine: Bool, control: VPControl? = nil) -> Int {
        let current = min(65535, max(0, raw))
        guard direction != 0 else { return current }
        let sign = direction > 0 ? 1 : -1
        let next: Int
        if let control, !control.logarithmic, !control.inverted, control.kind == "slider" {
            let step = fine ? 0.01 : 0.1
            let mapped = control.rawValue(display: control.displayValue(raw: current) + Double(sign) * step)
            next = sign > 0 ? max(current + 1, mapped) : min(current - 1, mapped)
        } else { next = current + sign * (fine ? 4 : 64) }
        return min(65535, max(0, next))
    }
}
