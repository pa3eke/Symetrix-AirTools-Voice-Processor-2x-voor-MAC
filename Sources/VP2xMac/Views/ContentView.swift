import SwiftUI
import VP2xCore

struct ModernContentView: View {
    @ObservedObject var device: DeviceStore
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("VP2x").font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("VOICE PROCESSOR CONTROL").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }.padding(20)
                Picker("Kanaal", selection: $device.channel) {
                    Text("Kanaal 1").tag(1)
                    Text("Kanaal 2").tag(2)
                }.pickerStyle(.segmented).padding(.horizontal, 12).padding(.bottom, 16)
                List(device.sections, id: \.self, selection: $device.section) { name in
                    Label(name, systemImage: icon(name)).tag(name)
                }.listStyle(.sidebar)
                Label(device.connected ? "VP2x online" : "Offline", systemImage: device.connected ? "network" : "network.slash")
                    .font(.caption).foregroundStyle(device.connected ? Color.green : .secondary).padding(16)
            }.navigationSplitViewColumnWidth(225)
        } detail: {
            VStack(spacing: 0) {
                ConnectionBar(device: device)
                Divider()
                if let error = device.loadError {
                    ContentUnavailableView("Bediening kon niet worden geladen", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if device.section == "Presets" {
                    PresetsView(device: device)
                } else if device.section == "Logboek" {
                    ScrollView {
                        Text(device.log.isEmpty ? "Nog geen netwerkverkeer." : device.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.section).font(.largeTitle.bold())
                                    Text(device.section == "Systeem" ? "Globale apparaatinstellingen" : "Kanaal \(device.channel) · AirTools Voice Processor 2x")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if device.refreshing { ProgressView().controlSize(.small) }
                            }
                            if !device.connected {
                                Label("Verbind met je VP2x om de actuele waarden te bekijken en te wijzigen.", systemImage: "info.circle")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            if device.section == "Overzicht" { MeterStrip(device: device) }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                                ForEach(device.visibleControls.filter { $0.kind != "meter" }) { control in
                                    ControlRow(control: control, device: device)
                                }
                            }
                        }.padding(28)
                    }
                }
                Divider()
                HStack {
                    Circle().fill(device.connected ? Color.green : .secondary).frame(width: 7, height: 7)
                    Text(device.status).lineLimit(2)
                    Spacer()
                    if !device.pending.isEmpty { Text("\(device.pending.count) wijzigingen wachten op bevestiging") }
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .alert("VP2x", isPresented: Binding(get: { device.errorMessage != nil }, set: { if !$0 { device.errorMessage = nil } })) {
            Button("OK") { device.errorMessage = nil }
        } message: { Text(device.errorMessage ?? "") }
    }
    private func icon(_ name: String) -> String {
        ["Overzicht":"waveform.path", "Ingang":"mic", "Filters":"line.3.horizontal.decrease", "De-esser & expander":"waveform", "Compressor":"arrow.down.right.and.arrow.up.left", "Equalizer":"slider.horizontal.3", "Uitgang":"speaker.wave.2", "Systeem":"gearshape", "Presets":"square.stack", "Logboek":"terminal"][name] ?? "circle"
    }
}

private struct ConnectionBar: View {
    @ObservedObject var device: DeviceStore
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "network").foregroundStyle(.secondary)
            TextField("IP-adres VP2x", text: $device.host).textFieldStyle(.roundedBorder).frame(width: 165)
                .disabled(device.connected || device.connecting).onSubmit { if !device.connected { device.connect() } }
            Text("UDP 48630").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(device.connected || device.connecting ? "Verbreken" : "Verbinden") {
                if device.connected || device.connecting { device.disconnect() } else { device.connect() }
            }.buttonStyle(.borderedProminent)
            Button { device.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Instellingen opnieuw uitlezen").disabled(!device.connected || device.refreshing)
        }.padding(16)
    }
}

private struct MeterStrip: View {
    @ObservedObject var device: DeviceStore
    var body: some View {
        HStack(spacing: 24) {
            ForEach(device.catalog.controls.filter { $0.channel == device.channel && $0.kind == "meter" }) { control in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(control.label).font(.headline)
                        Spacer()
                        Text(device.values[control.id].map { control.formatted(raw: $0) } ?? "—").monospacedDigit()
                    }
                    ProgressView(value: Double(device.values[control.id] ?? 0), total: 65535).tint(.green)
                    Text("−48 dBu                         +24 dBu").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(20).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
