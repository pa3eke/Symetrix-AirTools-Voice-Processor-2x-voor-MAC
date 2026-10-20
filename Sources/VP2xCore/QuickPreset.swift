import Foundation

public struct QuickPreset: Codable, Identifiable, Equatable {
    public let id: Int
    public var name: String
    public var channelOne: Int?
    public var channelTwo: Int?
    public init(id: Int, name: String, channelOne: Int? = nil, channelTwo: Int? = nil) {
        self.id = id; self.name = name; self.channelOne = channelOne; self.channelTwo = channelTwo
    }
    public var numbers: [Int] { [channelOne, channelTwo.map { $0 + 100 }].compactMap { $0 } }
    public func validate() throws {
        guard (0...3).contains(id), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
              [channelOne,channelTwo].compactMap({ $0 }).allSatisfy({ (1...50).contains($0) }) else { throw PresetArchive.Failure.invalidFile }
    }
}
public struct QuickPresetLibrary: Codable, Equatable {
    public var version = 1
    public var shortcuts: [QuickPreset]
    public init(shortcuts: [QuickPreset] = (0..<4).map { QuickPreset(id: $0, name: "Preset \($0 + 1)") }) { self.shortcuts = shortcuts }
    public static func decode(_ data: Data) throws -> QuickPresetLibrary {
        let library = try JSONDecoder().decode(Self.self, from: data)
        guard library.version == 1, library.shortcuts.count == 4, Set(library.shortcuts.map(\.id)) == Set(0..<4) else { throw PresetArchive.Failure.invalidFile }
        try library.shortcuts.forEach { try $0.validate() }
        return library
    }
}
