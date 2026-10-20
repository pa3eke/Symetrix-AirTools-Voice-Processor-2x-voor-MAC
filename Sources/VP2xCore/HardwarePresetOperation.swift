import Foundation

public enum HardwarePresetOperation {
    /// Updates a single memory slot and its project metadata, preserving a local
    /// rollback copy. Live audio is never recalled by this operation.
    public static func save(host: String, preset: ChannelPreset, backupDirectory: URL, renameOnly: Bool = false) throws -> PresetArchive {
        let original = try DevicePresetFiles.readSite(host: host)
        let archive = try PresetArchive.decode(original)
        guard let previous = archive.presets.first(where: { $0.number == preset.number }),
              let template = archive.presets.first(where: { $0.channel == preset.channel && !$0.isEmpty }) else { throw PresetArchive.Failure.invalidFile }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backup = backupDirectory.appendingPathComponent("VP2x-\(host)-P\(preset.number)-\(UUID().uuidString)")
        try original.write(to: backup.appendingPathExtension("site"), options: .atomic)
        let session = try NativePresetSession(host: host)
        let previousValues = try session.read(number: preset.number)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(MacPresetLibrary(presets: [ChannelPreset(number: previous.number, name: previous.name, values: previousValues)]))
            .write(to: backup.appendingPathExtension("json"), options: .atomic)
        var stored = preset
        if renameOnly { stored.values = previousValues }
        if !stored.values.isEmpty {
            stored.values[stored.channel == 1 ? 700 : 1700] = stored.slot - 1
            stored.values[stored.channel == 1 ? 701 : 1701] = 0
        }
        guard Set(stored.values.keys).isSubset(of: Set(template.values.keys)) else { throw PresetArchive.Failure.invalidFile }
        let updated = try PresetSiteDocument(data: original).replacing(stored)
        if !renameOnly { try session.write(stored) }
        // A metadata failure is explicit; a confirmed preset write is not replayed.
        do { try DevicePresetFiles.writeSite(host: host, data: updated) }
        catch {
            throw NSError(domain: "VP2xPresets", code: 2, userInfo: [NSLocalizedDescriptionKey:
                renameOnly ? "De presetnaam kon niet worden opgeslagen. De back-up staat op je Mac." : "De presetwaarden zijn opgeslagen en teruggelezen, maar het bijwerken van het projectbestand is niet bevestigd. De back-up staat op je Mac."])
        }
        return try PresetArchive.decode(updated)
    }
}
