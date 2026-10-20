import Foundation

public protocol PresetMemory {
    func read(number: Int) throws -> [Int: Int]
    func write(_ preset: ChannelPreset) throws
}
extension NativePresetSession: PresetMemory {}

/// Restores both complete preset banks, without issuing any recall command.
public enum PresetBankRestore {
    public static func archive(_ data: Data) throws -> PresetArchive {
        let archive: PresetArchive
        if let library = try? MacPresetLibrary.decode(data) { archive = PresetArchive(presets: library.presets) }
        else { archive = try PresetArchive.decode(data) }
        let expected = Set(Array(1...50) + Array(101...150))
        guard Set(archive.presets.map(\.number)) == expected, archive.presets.count == 100 else {
            throw NSError(domain: "VP2xRestore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kies een complete back-up met alle 50 presetlocaties van beide kanalen (100 totaal). Een losse preset of snapshot is niet voldoende."])
        }
        _ = try MacPresetLibrary.decode(JSONEncoder().encode(MacPresetLibrary(presets: archive.presets)))
        return PresetArchive(presets: archive.presets.sorted { $0.number < $1.number })
    }
    public static func restore(host: String, data: Data, backupDirectory: URL, progress: @escaping (String) -> Void) throws -> PresetArchive {
        _ = try archive(data)
        progress("Huidige apparaatpresets voorbereiden…")
        let original = try DevicePresetFiles.readSite(host: host)
        let memory = try NativePresetSession(host: host)
        return try run(data: data, original: original, backupDirectory: backupDirectory, memory: memory,
                       commitSite: { try DevicePresetFiles.writeSite(host: host, data: $0) }, progress: progress)
    }
    public static func run(data: Data, original: Data, backupDirectory: URL, memory: PresetMemory,
                           commitSite: (Data) throws -> Void, progress: (String) -> Void) throws -> PresetArchive {
        let desired = try archive(data)
        let current = try archive(original)
        // Reject incompatible addresses before sending any write.
        let catalog = try ControlCatalog.load()
        for preset in desired.presets {
            let known = Set(catalog.controls.filter { $0.channel == preset.channel && $0.isWritable }.map(\.id))
                .union(preset.channel == 1 ? [195,196,197,700,701] : [1195,1196,1197,1700,1701])
            let allowed = known.union( current.presets.filter { $0.channel == preset.channel }.reduce(into: Set<Int>()) { $0.formUnion($1.values.keys) })
            guard Set(preset.values.keys).isSubset(of: allowed), preset.values.count <= 512 else { throw PresetArchive.Failure.invalidFile }
        }
        let folder = backupDirectory.appendingPathComponent("Voor-herstel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try original.write(to: folder.appendingPathComponent("original-project.site"), options: .atomic)
        try data.write(to: folder.appendingPathComponent("restore-source.backup"), options: .atomic)
        // Capture the actual memory, which may be newer than the project's XML.
        // Complete all 100 reads and persist recovery data before the first write.
        var previous: [ChannelPreset] = []
        for preset in current.presets {
            progress("Veiligheidskopie: \(previous.count + 1)/100")
            previous.append(ChannelPreset(number: preset.number, name: preset.name, values: try memory.read(number: preset.number)))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(MacPresetLibrary(presets: previous)).write(to: folder.appendingPathComponent("presets-before.json"), options: .atomic)
        let recovery = try PresetSiteDocument(data: original).replacing(previous)
        try recovery.write(to: folder.appendingPathComponent("presets-before.site"), options: .atomic)
        let updated = try PresetSiteDocument(data: original).replacing(desired.presets)
        var confirmed = 0
        var currentNumber: Int?
        do {
            for preset in desired.presets {
                currentNumber = preset.number
                progress("Presets terugzetten en controleren: \(confirmed + 1)/100")
                if previous.first(where: { $0.number == preset.number })?.values != preset.values {
                    // write() verifies the full slot and never retries a timed-out commit.
                    try memory.write(preset)
                }
                confirmed += 1
            }
            currentNumber = nil
            progress("Presetnamen en projectbestand bevestigen…")
            try commitSite(updated)
        } catch {
            let slot = currentNumber.map { " Preset \($0) is niet bevestigd." } ?? " Het projectbestand is niet bevestigd."
            throw NSError(domain: "VP2xRestore", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Herstel gestopt na \(confirmed)/100 bevestigde locaties.\(slot) Het apparaat kan gedeeltelijk zijn bijgewerkt. Er wordt niet automatisch opnieuw geschreven. Veiligheidskopie: \(folder.path). Oorzaak: \(error.localizedDescription)"])
        }
        progress("Alle 100 presetlocaties hersteld en gecontroleerd")
        return desired
    }
}
