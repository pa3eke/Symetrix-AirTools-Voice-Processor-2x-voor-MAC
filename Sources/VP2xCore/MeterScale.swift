import Foundation

/// Fraction covered by the "on" artwork, which is dark for reduction meters.
public enum MeterScale {
    public static func overlayFraction(raw: Int?, controller: Int, invertedArtwork: Bool) -> Double {
        // No sample is not a zero reading. Reduction meters have a lit background:
        // cover it completely when offline/stale rather than showing maximum reduction.
        guard let sample = raw else { return invertedArtwork ? 1 : 0 }
        let raw = min(65535, max(0, sample))
        if MeterPlan.main.contains(controller) {
            if raw > 64807 { return 1 }
            if raw > 54613 { return (42804 + Double(raw - 54613) / 10427 * 18008) / 65535 }
            return Double(raw) / 54613 * 42804 / 65535
        }
        let normalized = Double(raw) / 65535
        if [6220,6240,6300,7220,7240,7300].contains(controller) {
            return max(0, 1 - (1 - normalized) * 1.25)
        }
        return normalized
    }
}
