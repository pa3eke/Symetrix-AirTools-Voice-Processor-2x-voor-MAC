import SwiftUI
import UniformTypeIdentifiers
import VP2xCore

struct SnapshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(snapshot: VPSnapshot) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(snapshot)
    }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct PresetsView: View {
    @ObservedObject var device: DeviceStore
    var onExport: ((VPSnapshot) throws -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    @State private var confirmApply = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document: SnapshotDocument?
    var body: some View {
        if onExport != nil {
            snapshotForm
        } else {
            snapshotForm
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "VP2x-snapshot") { result in
                    if case .failure(let error) = result { device.errorMessage = error.localizedDescription }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        device.stageSnapshot(try Data(contentsOf: url))
                    } catch {
                        if (error as? CocoaError)?.code != .userCancelled { device.errorMessage = error.localizedDescription }
                    }
                }
        }
    }
    private var snapshotForm: some View {
        Form {
            Section("Instellingen bewaren op je Mac") {
                Text("Lees alle ondersteunde regelaars uit en bewaar ze als een snapshot. Hiermee kun je een eigen verzameling instellingen op je Mac opbouwen.")
                    .foregroundStyle(.secondary)
                Button(device.capturing ? "Snapshot uitlezen…" : "Lees uit en exporteer snapshot…") { device.capture() }
                    .disabled(!device.canEdit)
                if let snapshot = device.snapshot {
                    Text("\(snapshot.values.count) instellingen uitgelezen · \(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.secondary)
                    Button("Bewaar uitgelezen snapshot…") { export(snapshot) }.disabled(device.capturing)
                }
                Button("Open snapshot…") { if let onOpen { onOpen() } else { importing = true } }
                if let imported = device.importedSnapshot {
                    Text("\(imported.values.count) instellingen · bron: \(imported.host) · \(imported.capturedAt.formatted())")
                    Text("Toepassen wijzigt beide kanalen en de opgenomen systeeminstellingen, inclusief fantoomvoeding.")
                        .foregroundStyle(.secondary)
                    Button("Pas snapshot toe op VP2x…") { confirmApply = true }.disabled(!device.canEdit)
                }
            }

        }.formStyle(.grouped)
        .onChange(of: device.snapshot?.capturedAt) { _, _ in
            if let snapshot = device.snapshot { export(snapshot) }
        }
        .confirmationDialog("Snapshot toepassen op de VP2x?", isPresented: $confirmApply) {
            Button("Instellingen toepassen") { device.applySnapshot() }
        } message: { Text("Alle opgenomen waarden worden naar het apparaat gestuurd en per regelaar teruggelezen. Bij een fout stopt de overdracht; eerder bevestigde wijzigingen blijven actief.") }
    }
    private func export(_ snapshot: VPSnapshot) {
        do {
            if let onExport { try onExport(snapshot) }
            else { document = try SnapshotDocument(snapshot: snapshot); exporting = true }
        } catch { device.errorMessage = error.localizedDescription }
    }

}
