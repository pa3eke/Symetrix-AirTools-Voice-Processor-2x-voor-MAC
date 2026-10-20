import SwiftUI
import VP2xCore

struct ControlRow: View {
    let control: VPControl
    @ObservedObject var device: DeviceStore
    @State private var draft: Double?
    @State private var editing = false
    var raw: Int? { device.pending[control.id] ?? device.values[control.id] }
    var enabled: Bool { device.canEdit && raw != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(control.label).font(.headline)
                Spacer()
                if device.pending[control.id] != nil { ProgressView().controlSize(.mini) }
            }
            if control.kind == "slider" {
                HStack {
                    Text(raw.map { control.formatted(raw: editing ? Int(draft ?? Double($0)) : $0) } ?? "—")
                        .font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                    Spacer()
                }
                Slider(value: Binding(get: { sliderPosition }, set: { draft = control.inverted ? 65535 - $0 : $0 }), in: 0...65535,
                    onEditingChanged: { active in
                        editing = active
                        if !active, let draft { device.write(control, value: Int(draft.rounded())) }
                    })
                    .disabled(!enabled)
                    .accessibilityLabel(control.label)
            } else if control.kind == "choice" {
                Picker(control.label, selection: Binding(get: { nearestOption }, set: { device.write(control, value: $0) })) {
                    Text("—").tag(-1)
                    ForEach(control.options) { option in Text(option.label).tag(option.value) }
                }.labelsHidden().disabled(!enabled)
            } else {
                Toggle(isOn: Binding(get: {
                    guard let raw else { return false }
                    return control.inverted ? raw < 32768 : raw >= 32768
                }, set: { active in
                    device.write(control, value: (active != control.inverted) ? 65535 : 0)
                })) {
                    Text(raw == nil ? "Niet uitgelezen" : ((control.inverted ? raw! < 32768 : raw! >= 32768) ? "Aan" : "Uit"))
                        .font(.callout).foregroundStyle(.secondary)
                }.toggleStyle(.switch).disabled(!enabled)
            }
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
    private var sliderPosition: Double {
        let value = editing ? draft ?? Double(raw ?? 0) : Double(raw ?? 0)
        return control.inverted ? 65535 - value : value
    }
    private var nearestOption: Int {
        guard let raw else { return -1 }
        return control.options.min(by: { abs($0.value - raw) < abs($1.value - raw) })?.value ?? -1
    }
}
