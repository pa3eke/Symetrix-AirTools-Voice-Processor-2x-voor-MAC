import SwiftUI
import VP2xCore

/// A visual indication from the parameters; not an audio measurement.
struct ClassicResponseGraph: View {
    let panelID: Int
    @ObservedObject var device: DeviceStore
    private var channel: Int { panelID % 2 == 0 ? 1 : 2 }
    private var offset: Int { channel == 1 ? 0 : 1000 }
    private func value(_ id: Int, fallback: Double) -> Double {
        guard let c = device.catalog.controls.first(where: { $0.id == id + offset }),
              let raw = device.previews[c.id] ?? device.pending[c.id] ?? device.values[c.id] else { return fallback }
        return c.displayValue(raw: raw)
    }
    private func active(_ id: Int) -> Bool { (device.values[id + offset] ?? 65535) < 32768 }
    var body: some View {
        Canvas { context, size in
            guard device.connected else { return }
            let eq = panelID == 16 || panelID == 17
            var path = Path()
            for pixel in 0...Int(size.width) {
                let f = 20 * pow(1000, Double(pixel) / size.width)
                let gain = eq ? eqGain(f) : filterGain(f)
                let y = size.height * (eq ? (15 - gain) / 30 : (12 - gain) / 36)
                let point = CGPoint(x: Double(pixel), y: max(0, min(size.height, y)))
                if pixel == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            var area = path
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
            context.fill(area, with: .color(.cyan.opacity(0.16)))
            context.stroke(path, with: .color(.cyan), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
        .help("Indicatieve frequentierespons uit de actuele instellingen; geen gemeten audiosignaal")
    }
    private func eqGain(_ frequency: Double) -> Double {
        guard active(134) else { return 0 }
        var db = 0.0
        if active(114) { db += value(116, fallback: 0) / (1 + pow(frequency / value(115, fallback: 80), 2)) }
        if active(129) { db += value(131, fallback: 0) / (1 + pow(value(130, fallback: 8000) / frequency, 2)) }
        for (f, g, q, enable) in [(118,119,120,117),(126,127,128,125)] where active(enable) {
            let ratio = frequency / value(f, fallback: 1000)
            let quality = value(q, fallback: 1)
            // Magnitude of a peaking section, unity at DC and infinity.
            let a = pow(10, value(g, fallback: 0) / 40)
            let squared = pow(1 - ratio * ratio, 2)
            db += 10 * log10((squared + pow(ratio * a / quality, 2)) / max(1e-20, squared + pow(ratio / (a * quality), 2)))
        }
        return db
    }
    private func filterGain(_ frequency: Double) -> Double {
        guard active(548) else { return 0 }
        var db = 0.0
        for (freq, slope, enabled, hp) in [(533,537,536,true),(539,543,542,false)] where active(enabled) {
            let raw = device.values[slope + offset] ?? 9362
            let order = raw > 46810 ? 8.0 : raw > 18724 ? 4.0 : 2.0
            let cutoff = value(freq, fallback: hp ? 80 : 16000)
            let ratio = hp ? cutoff / frequency : frequency / cutoff
            db -= 10 * log10(1 + pow(ratio, 2 * order))
        }
        return db
    }
}
