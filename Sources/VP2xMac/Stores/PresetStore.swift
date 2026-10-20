import Foundation
import Combine
import VP2xCore

enum PresetLocation: String, CaseIterable, Identifiable {
    case mac = "Mac", hardware = "VP2x"
    var id: Self { self }
}

@MainActor final class PresetStore: ObservableObject {
    @Published private(set) var hardware: [ChannelPreset] = []
    @Published private(set) var mac: [ChannelPreset] = []
    @Published var location = PresetLocation.hardware
    @Published var selectedSlots = [1: 1, 2: 1]
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    let hardwareWritesAvailable = true
    var failed: ((String) -> Void)?
    private var writer: Task<Void, Never>?
    @Published private(set) var message = "Presets nog niet uitgelezen"
    @Published private(set) var loadedHost: String?
    private var lastHardwareIndex: [Int: Int] = [:]
    private var token = UUID()
    private var task: Task<Void, Never>?
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VP2x Control/Presets", isDirectory: true)
    }
    private var libraryURL: URL { directory.appendingPathComponent("Mac-presets.json") }
    init() {
        do {
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                mac = try MacPresetLibrary.decode(Data(contentsOf: libraryURL)).presets
            }
        } catch { message = "Mac-presets konden niet worden geopend: \(error.localizedDescription)" }
    }
    func entries(at location: PresetLocation, channel: Int) -> [ChannelPreset] {
        let saved = location == .hardware ? hardware : mac
        return (1...50).map { slot in
            let number = slot + (channel == 2 ? 100 : 0)
            return saved.first { $0.number == number } ?? ChannelPreset(number: number, name: "Leeg", values: [:])
        }
    }
    func selected(channel: Int, at source: PresetLocation? = nil) -> ChannelPreset {
        entries(at: source ?? location, channel: channel)[min(49, max(0, (selectedSlots[channel] ?? 1) - 1))]
    }
    func step(channel: Int, by delta: Int) {
        selectedSlots[channel] = min(50, max(1, (selectedSlots[channel] ?? 1) + delta))
    }
    func observeIndicator(channel: Int, raw: Int) {
        guard (0...49).contains(raw), lastHardwareIndex[channel] != raw else { return }
        lastHardwareIndex[channel] = raw
        if location == .hardware { selectedSlots[channel] = raw + 1 }
    }
    func load(host: String) {
        guard !busy else { return }
        task?.cancel(); token = UUID()
        let current = token
        loading = true; message = "Presets van VP2x uitlezen…"
        task = Task {
            do {
                let data = try await Task.detached(priority: .utility) { try DevicePresetFiles.readSite(host: host) }.value
                guard current == token, !Task.isCancelled else { return }
                let archive = try PresetArchive.decode(data)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent("VP2x-\(host)-\(Int(Date().timeIntervalSince1970)).site"), options: .atomic)
                hardware = archive.presets; loadedHost = host
                message = "\(archive.presets.count) apparaatpresets · back-up op de Mac bewaard"
            } catch {
                guard current == token else { return }
                message = error.localizedDescription
            }
            if current == token { loading = false }
        }
    }
    func cancelLoad() { task?.cancel(); token = UUID(); loading = false }
    func save(_ preset: ChannelPreset) throws {
        let checked = try MacPresetLibrary.decode(JSONEncoder().encode(MacPresetLibrary(presets: [preset])))
        var updated = mac.filter { $0.number != preset.number }
        updated += checked.presets; updated.sort { $0.number < $1.number }
        try persist(updated)
        mac = updated; message = "Preset \(preset.slot) op de Mac opgeslagen"
    }
    func saveHardware(_ preset: ChannelPreset, host: String, renameOnly: Bool = false) {
        guard hardwareWritesAvailable, !busy, loadedHost == host else { return }
        busy = true; message = "Preset \(preset.slot) in VP2x opslaan…"
        let backup = directory
        writer = Task {
            do {
                let archive = try await Task.detached(priority: .utility) {
                    try HardwarePresetOperation.save(host: host, preset: preset, backupDirectory: backup, renameOnly: renameOnly)
                }.value
                hardware = archive.presets
                message = renameOnly ? "Preset \(preset.slot) op VP2x hernoemd" : "Preset \(preset.slot) op VP2x opgeslagen en bevestigd"
            } catch {
                message = error.localizedDescription; failed?(message)
            }
            busy = false; writer = nil
        }
    }
    func restoreHardware(data: Data, host: String) {
        guard hardwareWritesAvailable, !busy, !loading, loadedHost == host else { return }
        cancelLoad(); busy = true; message = "Complete presetback-up voorbereiden…"
        let backup = directory
        writer = Task {
            do {
                let archive = try await Task.detached(priority: .utility) {
                    try PresetBankRestore.restore(host: host, data: data, backupDirectory: backup) { update in
                        Task { @MainActor in self.message = update }
                    }
                }.value
                hardware = archive.presets; location = .hardware
                message = "Alle 100 presetlocaties op de VP2x hersteld en gecontroleerd"
            } catch {
                message = error.localizedDescription; failed?(message)
            }
            busy = false; writer = nil
        }
    }
    func rename(_ preset: ChannelPreset, to name: String) throws {
        var changed = preset; changed.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try save(changed)
    }
    func clear(_ preset: ChannelPreset) throws {
        let updated = mac.filter { $0.number != preset.number }
        try persist(updated); mac = updated; message = "Mac-preset \(preset.slot) gewist"
    }
    func importData(_ data: Data, destination: Int) throws {
        let imported: [ChannelPreset]
        if let library = try? MacPresetLibrary.decode(data) { imported = library.presets }
        else { imported = try PresetArchive.decode(data).presets }
        guard !imported.isEmpty else { throw PresetArchive.Failure.invalidFile }
        if imported.count == 1 {
            try save(imported[0].moved(to: destination))
        } else {
            // Import into the Mac library; no implicit hardware upload or recall.
            var result = mac
            for preset in imported {
                result.removeAll { $0.number == preset.number }; result.append(preset)
            }
            _ = try MacPresetLibrary.decode(JSONEncoder().encode(MacPresetLibrary(presets: result)))
            try persist(result.sorted { $0.number < $1.number }); mac = result
            message = "\(imported.count) presets geïmporteerd op de Mac"
        }
    }
    private func persist(_ values: [ChannelPreset]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Preserve the previous library before any overwrite/clear.
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let backup = directory.appendingPathComponent("Mac-presets-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: libraryURL, to: backup)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(MacPresetLibrary(presets: values)).write(to: libraryURL, options: .atomic)
    }
}
