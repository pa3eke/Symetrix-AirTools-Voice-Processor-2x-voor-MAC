import SwiftUI
import VP2xCore

struct SkinImage: View {
    let name: String
    var body: some View {
        if let image = SkinLayout.shared.image(name) { Image(nsImage: image).resizable().interpolation(.high) }
    }
}
struct SkinControlView: View {
    let item: SkinControl
    @ObservedObject var device: DeviceStore
    let selectedPanel: Int
    let activate: (Int) -> Void
    @State private var draft: Double?
    @State private var entry = ""
    @State private var editingNumber = false
    var model: VPControl? { device.catalog.controls.first { $0.id == item.controller } }
    var raw: Int? { item.controller.flatMap { device.previews[$0] ?? device.pending[$0] ?? device.values[$0] } }
    var enabled: Bool { device.canEdit && raw != nil }
    var fraction: Double { min(1, max(0, Double(raw ?? 0) / 65535)) }
    var body: some View {
        Group {
            switch item.kind {
            case "PushButton": button
            case "Numeric": numeric
            case "Fader": fader
            case "BarGraph": SkinMeterView(item: item, meters: device.meters)
            default: EmptyView()
            }
        }
        .frame(width: item.width, height: item.height)
        .help((model?.label ?? item.name) + (item.kind == "Fader" ? " · Scroll boven de regelaar of klik en gebruik de pijltjestoetsen; Shift voor extra fijn." : ""))
    }
    private var isAction: Bool { item.target > 0 && !item.viewer.isEmpty }
    private var lit: Bool {
        if isAction { return item.target == selectedPanel }
        guard let raw else { return false }
        if let choice = item.selected {
            let id = item.controller ?? 0
            let count = id == 101 || id == 1101 ? 5 : (id == 537 || id == 543 || id == 1537 || id == 1543 ? 8 : 4)
            return abs(raw - choice) < max(2, 65535 / (count - 1) / 2)
        }
        return item.inverted ? raw < 32768 : raw >= 32768
    }
    private var button: some View {
        Button {
            if isAction { activate(item.target); return }
            guard let id = item.controller, let raw else { return }
            let value = item.selected ?? (raw < 32768 ? 65535 : 0)
            device.writeRaw(id, value: value)
        } label: {
            ZStack {
                SkinImage(name: lit && !item.on.isEmpty ? item.on : item.off)
                if item.off.isEmpty, item.controller == 8601 {
                    Text(raw == nil ? "—" : (fraction < 0.5 ? "INT" : "WORD"))
                        .font(.system(size: 14)).foregroundStyle(.yellow)
                }
            }
            .opacity(raw == nil && !isAction ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAction && !enabled)
        .accessibilityLabel(item.name)
        .accessibilityValue(lit ? "Aan" : "Uit")
    }
    private var numeric: some View {
        Text(displayText).lineLimit(1).minimumScaleFactor(0.65)
            .font(.custom("Arial", size: min(16, max(12, item.fontSize))).weight(.bold))
            .foregroundStyle(item.controller == 9605 ? Color.yellow : Color(red: 0.39, green: 0.86, blue: 0.96))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                NumberMouseSurface(enabled: enabled && model != nil) {
                    guard let model, let raw else { return }
                    entry = String(format: "%.5g", model.displayValue(raw: raw) * (isTime ? 1000 : 1))
                    editingNumber = true
                }
            }
            .popover(isPresented: $editingNumber) {
                VStack(alignment: .leading) {
                    Text(model?.label ?? item.name)
                    TextField(isTime ? "Waarde (ms)" : "Waarde", text: $entry).frame(width: 160).onSubmit { commitNumber() }
                    Button("Toepassen") { commitNumber() }.keyboardShortcut(.defaultAction)
                }.padding()
            }
            .accessibilityLabel(item.name)
    }
    private var isTime: Bool { item.name.contains("Attack") || item.name.contains("Release") }
    private func commitNumber() {
        guard let value = Double(entry.replacingOccurrences(of: ",", with: ".")), value.isFinite, let model else { return }
        device.write(model, value: model.rawValue(display: isTime ? value / 1000 : value)); editingNumber = false
    }
    private var displayText: String {
        let precise = device.focusedControl != nil && device.focusedControl == item.controller
        guard let raw else { return "—" }
        if item.controller == 9605 { return String(format: "%.1f", Double(raw) * 500 / 65535) }
        guard let model else {
            if item.name.contains("Freq") {
                let hz = 20 * pow(1000, Double(raw) / 65535)
                return hz >= 1000 ? String(format: "%.2f kHz", hz / 1000) : String(format: "%.1f Hz", hz)
            }
            return "—"
        }
        if model.name.contains("Ratio") { return String(format: precise ? "%.3f" : "%.2f", model.displayValue(raw: raw)) }
        if model.name.contains("Attack") || model.name.contains("Release") {
            let ms = model.displayValue(raw: raw) * 1000
            return String(format: precise ? "%.3f ms" : ms < 1 ? "%.1f ms" : "%.0f ms", ms)
        }
        let value = model.displayValue(raw: raw)
        if precise && model.name.contains("Freq") {
            return value >= 1000 ? String(format: "%.3f kHz", value / 1000) : String(format: "%.2f Hz", value)
        }
        if precise && (model.name.contains("QFader") || model.name.contains("Res")) { return String(format: "%.4f", value) }
        if model.name.contains("Freq"), value < 100 { return String(format: "%.2f Hz", value) }
        if !model.name.contains("Freq"), !model.name.contains("QFader"), !model.name.contains("Res") {
            return String(format: precise ? "%+.2f dB" : "%+.1f dB", value)
        }
        return model.formatted(raw: raw)
    }
    private var fader: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let image = SkinLayout.shared.image(item.handle)
            let knob = image?.size ?? CGSize(width: 12, height: 12)
            let position = (draft ?? Double(raw ?? 0)) / 65535
            let travel = item.horizontal ? max(1, size.width - knob.width) : max(1, size.height - knob.height)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle())
                SkinImage(name: item.handle).frame(width: knob.width, height: knob.height)
                    .offset(x: item.horizontal ? position * travel : (size.width - knob.width) / 2,
                            y: item.horizontal ? (size.height - knob.height) / 2 : (1 - position) * travel)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .overlay {
                FaderMouseSurface(enabled: enabled, horizontal: item.horizontal,
                    handleRect: CGRect(x: item.horizontal ? position * travel : (size.width - knob.width) / 2,
                                       y: item.horizontal ? (size.height - knob.height) / 2 : (1 - position) * travel,
                                       width: knob.width, height: knob.height), adjusted: { direction, fine in
                    guard let id = item.controller, let current = draft.map({ Int($0.rounded()) }) ?? raw else { return }
                    let value = FaderKeyboardStep.adjusted(raw: current, direction: direction, fine: fine, control: model)
                    draft = Double(value); device.previews[id] = value
                    device.writeLiveRaw(id, value: value)
                }, focusChanged: { focused in
                    if focused { device.focusedControl = item.controller }
                    else if device.focusedControl == item.controller { device.focusedControl = nil }
                }, changed: { point in
                    let value = item.horizontal ? (point.x - knob.width / 2) / travel : 1 - (point.y - knob.height / 2) / travel
                    draft = min(1, max(0, value)) * 65535
                    if let id = item.controller {
                        let value = Int(draft!.rounded())
                        device.previews[id] = value
                        device.writeLiveRaw(id, value: value)
                    }
                }, ended: {
                    if let draft, let id = item.controller, enabled { device.writeRaw(id, value: Int(draft.rounded())) }
                    if let id = item.controller { device.previews.removeValue(forKey: id) }
                    draft = nil
                })
            }
            .accessibilityElement().accessibilityLabel(item.name)
            .accessibilityValue(raw.map(String.init) ?? "Niet uitgelezen")
            .accessibilityAdjustableAction { direction in
                guard let raw, let id = item.controller else { return }
                device.writeRaw(id, value: FaderKeyboardStep.adjusted(raw: raw, direction: direction == .increment ? 1 : -1, fine: false, control: model))
            }
            .opacity(raw == nil ? 0.45 : 1)
        }
    }
}
