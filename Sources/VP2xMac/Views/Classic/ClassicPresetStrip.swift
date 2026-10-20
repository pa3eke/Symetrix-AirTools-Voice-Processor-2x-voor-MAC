import SwiftUI
import VP2xCore

struct ClassicPresetStrip: View {
    @ObservedObject var device: DeviceStore
    @ObservedObject var presets: PresetStore
    let channel: Int
    let open: (Int, Bool) -> Void
    @State private var confirmRecall = false
    private var selected: ChannelPreset { presets.selected(channel: channel) }
    private var dirty: Bool {
        presets.location == .hardware && (device.values[channel == 1 ? 700 : 1700] ?? -1) == selected.slot - 1 &&
            (device.values[channel == 1 ? 701 : 1701] ?? 0) >= 32768
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(dirty ? "*" : "")\(presets.location == .mac ? "Mac " : "")Preset \(selected.slot)")
                Text(presets.loading && presets.location == .hardware ? "Uitlezen…" : selected.name)
            }.font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 210, height: 42, alignment: .leading).lineLimit(1)
                .offset(x: 65, y: 23).accessibilityElement(children: .ignore).accessibilityLabel("Preset kanaal \(channel)").accessibilityValue("\(presets.location.rawValue) preset \(selected.slot): \(selected.name)\(dirty ? ", gewijzigd" : "")")
            ForEach([-1, 1], id: \.self) { delta in
                Button { presets.step(channel: channel, by: delta) } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).frame(width: 26, height: 26).offset(x: 9, y: delta < 0 ? 9 : 55)
                    .accessibilityLabel(delta < 0 ? "Vorige preset kanaal \(channel)" : "Volgende preset kanaal \(channel)")
            }
            ForEach([0,1,2], id: \.self) { index in
                Button {
                    if index == 0 { confirmRecall = true }
                    else { open(channel, index == 1) }
                } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).frame(width: index == 2 ? 171 : 82, height: 27)
                    .offset(x: index == 1 ? 410 : 320, y: index == 2 ? 54 : 22)
                    .disabled(index == 0 && (!device.canEdit || selected.isEmpty || (presets.location == .hardware && presets.loadedHost != device.host)))
                    .accessibilityLabel(index == 0 ? "Recall kanaal \(channel)" : index == 1 ? "Store kanaal \(channel)" : "Manage presets kanaal \(channel)")
            }
        }.frame(width: 500, height: 88, alignment: .topLeading)
        .confirmationDialog("Preset \(selected.slot) laden op kanaal \(channel)?", isPresented: $confirmRecall) {
            Button("Preset laden") { device.recallPreset(selected, from: presets.location) }
        } message: { Text("‘\(selected.name)’ wordt actief op kanaal \(channel).") }
    }
}
