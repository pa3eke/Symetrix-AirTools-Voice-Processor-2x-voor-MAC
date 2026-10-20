import SwiftUI
import UniformTypeIdentifiers
import VP2xCore

struct PresetManagerView: View {
    @ObservedObject var device: DeviceStore
    @ObservedObject var presets: PresetStore
    @Environment(\.dismiss) private var dismiss
    @State var channel: Int
    @State var storeOnOpen = false
    @State private var operation: String?
    @State private var operationSource: ChannelPreset?
    @State private var saveLocation = PresetLocation.mac
    @State private var name = ""
    @State private var destination = 1
    @State private var destinationChannel = 1
    @State private var confirmation = false
    @State private var importing = false
    @State private var importingSnapshot = false
    @State private var exportFilename = "VP2x-preset"
    @State private var imported: [ChannelPreset] = []
    @State private var importIndex = 0
    @State private var importFilename = ""
    @State private var exporting = false
    @State private var document: SnapshotDocument?
    @State private var tab = 0
    private var selected: ChannelPreset { presets.selected(channel: channel) }
    private var isMac: Bool { presets.location == .mac }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tab == 0 ? "Manage Presets" : "Snapshots").font(.custom("Arial", size: 13))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12)) }
                    .buttonStyle(.plain).accessibilityLabel("Sluiten").disabled(presets.busy)
            }.padding(.horizontal, 10).frame(height: 27).background(Color(white: 0.94))
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    if tab == 0 {
                        Text("Opslag:").font(.custom("Arial", size: 12))
                        ForEach(PresetLocation.allCases) { source in
                            PresetChoice(title: source.rawValue, selected: presets.location == source) { presets.location = source; operation = nil }
                        }
                        Spacer().frame(width: 20)
                        ForEach(1...2, id: \.self) { number in
                            PresetChoice(title: "Kanaal \(number)", selected: channel == number) { channel = number; operation = nil }
                        }
                    }
                    Spacer()
                    Button(tab == 0 ? "SNAPSHOTS…" : "PRESETBEHEER") { tab = tab == 0 ? 1 : 0 }
                        .buttonStyle(PresetOperationStyle()).frame(width: 145).disabled(presets.busy)
                }
                if tab == 0 { manager }
                else { PresetsView(device: device, onExport: exportSnapshot, onOpen: { importingSnapshot = true; importing = true }).padding(10).frame(maxHeight: .infinity) }
                HStack {
                    Spacer()
                    Button("EXIT") { dismiss() }.buttonStyle(PresetOperationStyle(exit: true))
                        .frame(width: 170).disabled(presets.busy).keyboardShortcut(.cancelAction).accessibilityLabel("Sluiten")
                    Spacer()
                }
            }.padding(16)
                .background(LinearGradient(colors: [Color(red: 0.62, green: 0.63, blue: 0.58), PresetChrome.panel], startPoint: .top, endPoint: .bottom))
                .modifier(PresetBevel(sunken: true)).padding(5)
        }.frame(width: 980, height: 620)
            .foregroundStyle(.black).background(PresetChrome.panel).preferredColorScheme(.light)
        .interactiveDismissDisabled(presets.busy)
        .onAppear {
            if storeOnOpen { begin("store") }
        }
        .confirmationDialog("Preset \(selected.slot) laden op kanaal \(channel)?", isPresented: $confirmation) {
            Button("Preset laden") { device.recallPreset(selected, from: presets.location) }
        } message: { Text("De audio-instellingen van kanaal \(channel) worden vervangen door ‘\(selected.name)’. Het andere kanaal blijft ongewijzigd.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if importingSnapshot { device.stageSnapshot(data); return }
                let entries: [ChannelPreset]
                if let library = try? MacPresetLibrary.decode(data) { entries = library.presets }
                else { entries = try PresetArchive.decode(data).presets }
                imported = entries.filter { !$0.isEmpty }
                guard !imported.isEmpty else { throw PresetArchive.Failure.invalidFile }
                importIndex = imported.firstIndex { $0.channel == channel } ?? 0
                importFilename = url.lastPathComponent
                name = imported[importIndex].name
                operation = "import"
            } catch {
                if (error as? CocoaError)?.code != .userCancelled { device.errorMessage = error.localizedDescription }
            }
        }
        .fileDialogDefaultDirectory(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VP2x Control/Presets"))
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result { device.errorMessage = error.localizedDescription }
        }
    }
    private var manager: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ClassicPresetList(title: "Select a Preset Location:", entries: presets.entries(at: presets.location, channel: channel),
                    selection: Binding(get: { presets.selectedSlots[channel] }, set: { if let slot = $0 { presets.selectedSlots[channel] = slot; operation = nil } }),
                    accessibilityName: "Bronpresetlijst")
                    .padding(10).frame(width: 365).modifier(PresetBevel(sunken: true)).disabled(presets.busy)
                operationButtons
                editor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .modifier(PresetBevel(sunken: true))
            }
            HStack(spacing: 8) {
                if presets.loading || presets.busy { ProgressView().controlSize(.small) }
                Text(presets.message).font(.custom("Arial", size: 12)).foregroundStyle(Color(white: 0.23))
            }.frame(height: 18)
        }
    }
    private var operationButtons: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Operation:").font(.custom("Arial", size: 20)).padding(.bottom, -8)
            operationButton("COPY SELECTED PRESET:", kind: "copy", accessible: "Kopieer geselecteerde preset")
                .disabled(selected.isEmpty || presets.busy)
            operationButton("RENAME SELECTED PRESET:", kind: "rename", accessible: "Hernoem geselecteerde preset")
                .disabled(!canChangeSelected)
            operationButton("CLEAR SELECTED PRESET:", kind: "clear", accessible: "Wis geselecteerde preset")
                .disabled(!canChangeSelected)
            operationButton("IMPORT…", kind: "import", accessible: "Importeer").disabled(presets.busy)
            Button("EXPORT…") { exportSelected() }.disabled(selected.isEmpty || presets.busy)
                .accessibilityLabel("Exporteer geselecteerde preset")
            Rectangle().fill(Color.black.opacity(0.20)).frame(height: 1).padding(.vertical, 3)
            Button("RECALL SELECTED PRESET…") { confirmation = true }
                .disabled(!device.canEdit || selected.isEmpty || (!isMac && presets.loadedHost != device.host))
                .accessibilityLabel("Recall — laden")
            operationButton("STORE CURRENT SETTINGS…", kind: "store", accessible: "Store — huidige instellingen").disabled(!device.canEdit)
            Spacer(minLength: 0)
            Button("REFRESH PRESETS") { presets.load(host: device.host) }
                .disabled(!device.connected || presets.loading || presets.busy).accessibilityLabel("Lees apparaatpresets opnieuw")
        }.buttonStyle(PresetOperationStyle()).frame(width: 172)
    }
    private var canChangeSelected: Bool {
        !selected.isEmpty && !presets.busy && (isMac || (presets.hardwareWritesAvailable && device.canEdit && presets.loadedHost == device.host))
    }
    private func operationButton(_ title: String, kind: String, accessible: String) -> some View {
        Button { begin(kind) } label: {
            Text(title).foregroundStyle(operation == kind ? Color.yellow : Color(white: 0.83))
        }.accessibilityLabel(accessible)
    }
    private func begin(_ kind: String) {
        operationSource = selected
        name = kind == "copy" ? String("Copy of \(selected.name)".prefix(64)) : selected.isEmpty ? "Preset \(selected.slot)" : selected.name
        destination = selected.slot; destinationChannel = channel
        saveLocation = presets.location
        operation = kind
        if kind == "import" { importingSnapshot = false; imported = []; importFilename = ""; importing = true }
    }
    private var source: ChannelPreset? {
        if operation == "import" { return imported.indices.contains(importIndex) ? imported[importIndex] : nil }
        return operationSource
    }
    private var canCommit: Bool {
        !presets.busy && (saveLocation == .mac || (presets.hardwareWritesAvailable && device.canEdit && presets.loadedHost == device.host)) &&
            (operation == "clear" || (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 64)) &&
            (operation != "import" || source != nil)
    }
    @ViewBuilder private var editor: some View {
        if operation == "clear", let source {
            VStack(spacing: 12) {
                VStack(spacing: 5) {
                    Text("Clear Preset:").font(.custom("Arial", size: 14))
                    HStack(spacing: 24) {
                        Button("YES") { commit() }.disabled(!canCommit).accessibilityLabel("Ja, geselecteerde preset wissen")
                        Button("NO") { operation = nil }.accessibilityLabel("Nee, wissen annuleren")
                    }.buttonStyle(PresetOperationStyle(exit: true))
                }.padding(10).modifier(PresetBevel(sunken: true))
                VStack(spacing: 14) {
                    Text("Weet je zeker dat je preset ‘\(source.name) (P\(String(format: "%02d", source.slot)))’ wilt wissen?")
                        .font(.custom("Arial", size: 16).weight(.bold)).multilineTextAlignment(.center)
                    Text("Opslag: \(saveLocation.rawValue) · Kanaal \(source.channel)")
                    Text("Er wordt eerst een veiligheidskopie op de Mac gemaakt.").font(.custom("Arial", size: 12))
                    Spacer()
                }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).modifier(PresetBevel(sunken: true))
            }.padding(10)
        } else if let operation {
            VStack(alignment: .leading, spacing: 7) {
                Text(editorTitle).font(.custom("Arial", size: 14).weight(.bold)).foregroundStyle(Color.yellow)
                    .lineLimit(2).padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(PresetChrome.dark).modifier(PresetBevel(sunken: true))
                if operation == "copy" || operation == "store" || operation == "import" {
                    destinationChoices
                    if operation == "import" {
                        Button("Kies bestand…") { importingSnapshot = false; importing = true }.buttonStyle(PresetOperationStyle(exit: true))
                        if imported.count > 1 {
                            Picker("Uit bestand", selection: $importIndex) {
                                ForEach(imported.indices, id: \.self) { i in
                                    Text("K\(imported[i].channel) · \(imported[i].name) (P\(imported[i].slot))").tag(i)
                                }
                            }.onChange(of: importIndex) { _, index in if imported.indices.contains(index) { name = imported[index].name } }
                        }
                    }
                    ClassicPresetList(title: "Preset:", entries: presets.entries(at: saveLocation, channel: destinationChannel),
                        selection: Binding(get: { destination }, set: { if let slot = $0 { destination = slot } }),
                        accessibilityName: "Bestemmingspresetlijst")
                    let existing = presets.entries(at: saveLocation, channel: destinationChannel)[destination - 1]
                    Text(existing.isEmpty ? "Lege locatie" : "Vervangt: \(existing.name)")
                        .font(.custom("Arial", size: 11)).lineLimit(1).help(existing.name)
                } else { Spacer().frame(height: 12) }
                Text("Name:").font(.custom("Arial", size: 14))
                TextField("Naam", text: $name).textFieldStyle(.plain)
                    .font(.custom("Arial", size: 15).weight(.bold)).foregroundStyle(.white)
                    .padding(5).background(PresetChrome.dark).modifier(PresetBevel(sunken: true))
                HStack {
                    Button("CANCEL") { self.operation = nil }.accessibilityLabel("Bewerking annuleren")
                    Button(operation == "copy" ? "COPY" : operation == "rename" ? "RENAME" : operation == "import" ? "IMPORT" : "STORE") { commit() }
                        .disabled(!canCommit).accessibilityLabel("Bewerking uitvoeren")
                }.buttonStyle(PresetOperationStyle(exit: true)).padding(.top, 2)
                if operation == "rename" { Spacer() }
            }.padding(12).disabled(presets.busy)
        } else { Color.clear }
    }
    private var editorTitle: String {
        switch operation {
        case "copy": return "COPY \(source?.name ?? "") (P\(source?.slot ?? 1)) to:"
        case "rename": return "RENAME \(source?.name ?? "") (P\(source?.slot ?? 1)):"
        case "import": return importFilename.isEmpty ? "IMPORT PRESET FROM FILE:" : "IMPORT: \(importFilename)"
        default: return "STORE CURRENT SETTINGS:"
        }
    }
    private var destinationChoices: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text("Naar:").font(.custom("Arial", size: 12)).frame(width: 44, alignment: .leading)
                ForEach(PresetLocation.allCases) { location in
                    PresetChoice(title: location.rawValue, selected: saveLocation == location) { saveLocation = location }
                }
            }
            HStack(spacing: 7) {
                Text("Kanaal:").font(.custom("Arial", size: 12)).frame(width: 44, alignment: .leading)
                ForEach(1...2, id: \.self) { number in
                    PresetChoice(title: String(number), selected: destinationChannel == number) { destinationChannel = number }
                        .disabled(operation == "store")
                }
            }
        }
    }
    private func commit() {
        guard canCommit else { return }
        do {
            switch operation {
            case "store": device.storePreset(channel: channel, slot: destination, name: name, location: saveLocation)
            case "copy", "import":
                guard let source else { return }
                var copy = try source.moved(to: PresetArchive.number(channel: destinationChannel, slot: destination))
                copy.name = name
                if saveLocation == .hardware { presets.saveHardware(copy, host: device.host) }
                else { try presets.save(copy) }
            case "rename":
                if saveLocation == .hardware {
                    guard var renamed = operationSource else { return }; renamed.name = name
                    presets.saveHardware(renamed, host: device.host, renameOnly: true)
                } else { guard let source = operationSource else { return }; try presets.rename(source, to: name) }
            case "clear":
                if saveLocation == .hardware {
                    guard var empty = operationSource else { return }; empty.name = "Empty"; empty.values = [:]
                    presets.saveHardware(empty, host: device.host)
                } else { guard let source = operationSource else { return }; try presets.clear(source) }
            default: return
            }
            if operation == "copy" || operation == "store" || operation == "import" {
                presets.location = saveLocation
                presets.selectedSlots[destinationChannel] = destination
                channel = destinationChannel
            }
            operation = nil
        } catch { device.errorMessage = error.localizedDescription }
    }
    private func exportSnapshot(_ snapshot: VPSnapshot) throws {
        document = try SnapshotDocument(snapshot: snapshot)
        exportFilename = "VP2x-snapshot"
        exporting = true
    }
    private func exportSelected() {
        do {
            exportFilename = "VP2x-preset-\(selected.slot)"
            document = SnapshotDocument(data: try JSONEncoder().encode(MacPresetLibrary(presets: [selected])))
            exporting = true
        } catch { device.errorMessage = error.localizedDescription }
    }
}
