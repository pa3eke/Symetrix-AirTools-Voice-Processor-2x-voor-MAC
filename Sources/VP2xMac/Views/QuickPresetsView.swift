import SwiftUI
import VP2xCore

struct QuickPresetsView: View {
    @ObservedObject var device: DeviceStore
    @ObservedObject var shortcuts: QuickPresetStore
    @AppStorage("QuickPresetsAlwaysOnTop") private var onTop = true
    @State private var editing: QuickPreset?
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AirTools VP2x").font(.custom("Arial", size: 15).weight(.bold))
                    Text("Snelle presets").font(.custom("Arial", size: 11))
                }.foregroundStyle(Color(white: 0.27))
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(device.connected ? Color.green : Color.gray).frame(width: 6, height: 6)
                        Text(device.connected ? "ONLINE" : "OFFLINE").font(.custom("Arial Narrow", size: 10))
                    }
                    Text(device.host).font(.custom("Arial", size: 10))
                }.foregroundStyle(.black)
                if !device.connected {
                    Button(device.connecting ? "…" : "VERBIND") { device.connect() }.disabled(device.connecting)
                        .buttonStyle(PresetOperationStyle(exit: true)).frame(width: 62)
                }
            }.padding(.horizontal, 3).padding(.vertical, 2)
            VStack(spacing: 7) {
                ForEach(shortcuts.shortcuts) { shortcut in
                    HStack(spacing: 6) {
                        Button { device.activate(shortcut) } label: {
                            HStack(alignment: .center, spacing: 9) {
                                QuickPresetLamp(lit: active(shortcut))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(shortcut.name).font(.custom("Arial", size: 16).weight(.bold))
                                        .foregroundStyle(active(shortcut) ? Color.yellow : PresetChrome.cyan).lineLimit(1)
                                    Text(summary(shortcut)).font(.custom("Arial", size: 10))
                                        .foregroundStyle(Color(white: 0.8)).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(ClassicQuickPresetStyle()).disabled(!device.canActivate(shortcut))
                            .accessibilityLabel("Activeer \(shortcut.name)")
                            .accessibilityValue(active(shortcut) ? "Actief" : "Niet actief")
                            .help("Laadt de toegewezen VP2x-presets direct, zonder bevestigingsvenster.")
                        Button { editing = shortcut } label: { Image(systemName: "gearshape.fill") }
                            .buttonStyle(PresetOperationStyle(exit: true)).frame(width: 28)
                            .disabled(device.recallingPresets || device.presets.busy)
                            .accessibilityLabel("Stel snelknop \(shortcut.id + 1) in")
                    }
                }
            }.padding(7).modifier(PresetBevel(sunken: true))
            HStack(spacing: 7) {
                PresetChoice(title: "Boven andere vensters", selected: onTop) { onTop.toggle() }
                Spacer(minLength: 0)
                if device.recallingPresets { ProgressView().controlSize(.small) }
            }
            if device.recallingPresets { Text("Presets laden…").font(.custom("Arial", size: 11)).foregroundStyle(.black) }
        }.padding(10).frame(width: 320)
            .background(LinearGradient(colors: [Color(red: 0.62, green: 0.63, blue: 0.58), PresetChrome.panel], startPoint: .top, endPoint: .bottom))
            .modifier(PresetBevel()).padding(3).background(PresetChrome.panel)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.7), lineWidth: 1))
            .background(FloatingWindow(enabled: onTop)).preferredColorScheme(.light)
            .sheet(item: $editing) { shortcut in QuickPresetEditor(device: device, shortcuts: shortcuts, initial: shortcut) }
            .alert("Snelle presets", isPresented: Binding(get: { shortcuts.error != nil || device.quickRecallError != nil }, set: { if !$0 { shortcuts.error = nil; device.quickRecallError = nil } })) {
                Button("OK") { shortcuts.error = nil; device.quickRecallError = nil }
            } message: { Text(shortcuts.error ?? device.quickRecallError ?? "") }
    }
    private func summary(_ shortcut: QuickPreset) -> String {
        if shortcut.numbers.isEmpty { return "Nog niet ingesteld · tandwiel" }
        return shortcut.numbers.map { number in
            let channel = number > 100 ? 2 : 1, slot = number > 100 ? number - 100 : number
            let name = device.presets.hardware.first { $0.number == number }?.name
            return "K\(channel) · P\(String(format: "%02d", slot))\(name.map { " · " + $0 } ?? "")"
        }.joined(separator: "\n")
    }
    private func active(_ shortcut: QuickPreset) -> Bool {
        device.connected && !device.recallingPresets && !shortcut.numbers.isEmpty && shortcut.numbers.allSatisfy {
            let channelTwo = $0 > 100
            return device.values[channelTwo ? 1700 : 700] == (channelTwo ? $0 - 101 : $0 - 1) &&
                (device.values[channelTwo ? 1701 : 701] ?? 65535) < 32768
        }
    }
}

private struct QuickPresetEditor: View {
    @ObservedObject var device: DeviceStore
    @ObservedObject var shortcuts: QuickPresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var shortcut: QuickPreset
    init(device: DeviceStore, shortcuts: QuickPresetStore, initial: QuickPreset) {
        self.device = device; self.shortcuts = shortcuts; _shortcut = State(initialValue: initial)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snelknop \(shortcut.id + 1) instellen").font(.custom("Arial", size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text("Naam:").font(.custom("Arial", size: 12))
                TextField("Naam", text: $shortcut.name).textFieldStyle(.plain)
                    .font(.custom("Arial", size: 16).weight(.bold)).foregroundStyle(PresetChrome.cyan)
                    .padding(7).background(PresetChrome.dark).modifier(PresetBevel(sunken: true))
            }
            picker(channel: 1)
            picker(channel: 2)
            Text("‘Niet wijzigen’ laat dat kanaal met rust. Kies op beide kanalen een preset om een combinatie te laden.")
                .font(.caption).foregroundStyle(.secondary)
            Text("De snelknop laadt de apparaatpresets direct bij één klik.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Annuleren") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Bewaren") { shortcuts.save(shortcut); dismiss() }
                    .disabled((try? shortcut.validate()) == nil).keyboardShortcut(.defaultAction)
            }
        }.buttonStyle(PresetOperationStyle(exit: true)).padding(20).frame(width: 440)
            .foregroundStyle(.black).background(PresetChrome.panel).modifier(PresetBevel(sunken: true)).preferredColorScheme(.light)
    }
    private func picker(channel: Int) -> some View {
        Picker("Kanaal \(channel)", selection: Binding(get: { (channel == 1 ? shortcut.channelOne : shortcut.channelTwo) ?? 0 }, set: { number in
            if channel == 1 { shortcut.channelOne = number == 0 ? nil : number }
            else { shortcut.channelTwo = number == 0 ? nil : number }
        })) {
            Text("Niet wijzigen").tag(0)
            ForEach(device.presets.entries(at: .hardware, channel: channel)) { preset in
                Text("P\(String(format: "%02d", preset.slot)) · \(preset.name)").tag(preset.slot).disabled(preset.isEmpty)
            }
        }
    }
}
