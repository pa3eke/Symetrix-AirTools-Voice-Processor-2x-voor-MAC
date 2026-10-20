import SwiftUI

struct ClassicContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var device: DeviceStore
    @State private var panels = [1: 20, 2: 21]
    @State private var system = false
    private struct PresetRequest: Identifiable {
        let id = UUID()
        let channel: Int
        let store: Bool
    }
    @State private var presetRequest: PresetRequest?
    @State private var logbook = false
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geometry in
                let scale = min(geometry.size.width / 1006, geometry.size.height / 684)
                surface
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: 1006 * scale, height: 684 * scale, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            HStack {
                Circle().fill(device.connected ? Color.green : .gray).frame(width: 7, height: 7)
                Text(device.status).lineLimit(1)
                Spacer()
                if !device.pending.isEmpty { Text("\(device.pending.count) wijzigingen") }
            }.font(.system(size: 10)).padding(.horizontal, 10).frame(height: 22)
                .background(Color(red: 0.70, green: 0.70, blue: 0.66))
        }
        .foregroundStyle(.black).background(Color(red: 0.67, green: 0.67, blue: 0.64))
        .preferredColorScheme(.light)
        .sheet(item: $presetRequest) { request in PresetManagerView(device: device, presets: device.presets, channel: request.channel, storeOnOpen: request.store) }
        .sheet(isPresented: $logbook) {
            VStack {
                DeviceLogView(activity: device.activity)
                Button("Sluiten") { logbook = false }.keyboardShortcut(.cancelAction)
            }.padding().frame(width: 650, height: 500)
        }
        .alert("VP2x", isPresented: Binding(get: { device.errorMessage != nil }, set: { if !$0 { device.errorMessage = nil } })) {
            Button("OK") { device.errorMessage = nil }
        } message: { Text(device.errorMessage ?? "") }
        .onChange(of: panels) { _, _ in syncVisiblePanels() }
        .onChange(of: system) { _, _ in syncVisiblePanels() }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { presetRequest = PresetRequest(channel: 1, store: false) } label: { Image(systemName: "folder") }.help("Presetbeheer en snapshots")
            Button { device.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(!device.connected)
            Divider().frame(height: 20)
            Image(systemName: device.connected ? "network" : "network.slash").foregroundStyle(device.connected ? .green : .gray)
            TextField("VP2x IP", text: $device.host).frame(width: 130).textFieldStyle(.roundedBorder).disabled(device.connected || device.connecting)
            Button(device.connected || device.connecting ? "Offline" : "Online") {
                if device.connected || device.connecting { device.disconnect() } else { device.connect() }
            }.disabled(device.presets.busy)
            Text(device.connected ? "Online – AirTools VP2x (\(device.host))" : "AirTools VP2x – Offline")
                .font(.system(size: 11)).lineLimit(1)
            Spacer()
            Button("Snelle presets") { openWindow(id: "quick-presets") }
            Button("Logboek") { logbook = true }
        }.buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 36)
            .background(.linearGradient(colors: [.white, Color(white: 0.87)], startPoint: .top, endPoint: .bottom))
    }
    private var surface: some View {
        ZStack(alignment: .topLeading) {
            ClassicPanelView(panelID: 1, device: device, selectedPanel: system ? 2 : 3, activate: activate)
            if system {
                ClassicPanelView(panelID: 2, device: device, selectedPanel: 2, activate: activate).offset(y: 230)
            } else {
                ClassicPanelView(panelID: 3, device: device, selectedPanel: 0, activate: activate).offset(y: 230)
                ForEach([1,2], id: \.self) { channel in
                    let panel = panels[channel] ?? (channel == 1 ? 20 : 21)
                    let x = channel == 1 ? 6.0 : 506.0
                    ClassicPanelView(panelID: panel, device: device, selectedPanel: panel, activate: activate).offset(x: x, y: 320)
                    let pre = (device.values[channel == 1 ? 330 : 1330] ?? 0) >= 32768
                    let badge = (pre ? 6 : 4) + channel - 1
                    ClassicPanelView(panelID: badge, device: device, selectedPanel: panel, activate: activate)
                        .offset(x: x + 248, y: 230)
                    // Input, filters, de-esser and output edit buttons each belong to this channel.
                    ForEach([8,10,12,18], id: \.self) { first in
                        let id = first + channel - 1
                        let col = [8:0,10:1,12:2,18:5][first] ?? 0
                        Button { activate(id) } label: {
                            SkinImage(name: panel == id ? "maineditlit.png" : "mainedit.png")
                        }.buttonStyle(.plain).frame(width: 71, height: 25)
                            .offset(x: x + 4 + Double(col) * 83, y: 286)
                            .accessibilityLabel("Edit \(SkinLayout.shared.panel(id)?.name ?? "module")")
                    }
                }
            }
            presetStrip(channel: 1).offset(x: 0, y: 141)
            presetStrip(channel: 2).offset(x: 500, y: 141)
        }.frame(width: 1006, height: 684, alignment: .topLeading).clipped()
    }
    private func presetStrip(channel: Int) -> some View {
        ClassicPresetStrip(device: device, presets: device.presets, channel: channel) { channel, store in
            presetRequest = PresetRequest(channel: channel, store: store)
        }
    }
    private func activate(_ id: Int) {
        if id == 2 { system.toggle(); return }
        if id == 3 { system = false; return }
        if (8...21).contains(id) {
            let channel = id % 2 == 0 ? 1 : 2
            panels[channel] = panels[channel] == id ? (channel == 1 ? 20 : 21) : id
            system = false
        }
    }
    private func syncVisiblePanels() {
        device.classicPanelNames = system ? ["System"] : Set(panels.values.compactMap { SkinLayout.shared.panel($0)?.name })
    }
}
