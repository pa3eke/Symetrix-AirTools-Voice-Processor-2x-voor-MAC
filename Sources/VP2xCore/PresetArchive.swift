import Foundation
import CryptoKit
import zlib

public struct ChannelPreset: Codable, Identifiable, Equatable, Sendable {
    public var number: Int
    public var name: String
    public var values: [Int: Int]
    public var id: Int { number }
    public var channel: Int { number > 100 ? 2 : 1 }
    public var slot: Int { number > 100 ? number - 100 : number }
    public var isEmpty: Bool { values.isEmpty }
    public init(number: Int, name: String, values: [Int: Int]) {
        self.number = number; self.name = name; self.values = values
    }
}

public struct PresetArchive: Codable, Equatable, Sendable {
    public var presets: [ChannelPreset]
    public init(presets: [ChannelPreset]) { self.presets = presets }
    public enum Failure: LocalizedError {
        case invalidFile
        public var errorDescription: String? { "Dit is geen geldig VP2x-presetbestand, of het bestand is beschadigd." }
    }
    public static func number(channel: Int, slot: Int) throws -> Int {
        guard (1...2).contains(channel), (1...50).contains(slot) else { throw Failure.invalidFile }
        return slot + (channel == 2 ? 100 : 0)
    }
    public static func decode(_ data: Data) throws -> PresetArchive {
        let xml = try unpack(data)
        guard xml.count <= 16_000_000, !String(decoding: xml, as: UTF8.self).uppercased().contains("<!DOCTYPE") else { throw Failure.invalidFile }
        let reader = PresetXMLReader()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), !reader.invalid, !reader.presets.isEmpty else { throw Failure.invalidFile }
        let entries = reader.presets.filter { (1...50).contains($0.number) || (101...150).contains($0.number) }
        guard !entries.isEmpty, Set(entries.map(\.number)).count == entries.count else { throw Failure.invalidFile }
        return PresetArchive(presets: entries.sorted { $0.number < $1.number })
    }
    /// Original SavedSiteFile.site: count, method, sizes, MD5, DOS date, filename, gzip.
    public static func unpack(_ data: Data) throws -> Data {
        guard data.count <= 16_000_000 else { throw Failure.invalidFile }
        if data.starts(with: Data("<?xml".utf8)) || data.starts(with: Data("<".utf8)) { return data }
        func uint(_ offset: Int, _ bytes: Int) -> Int {
            (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 33, uint(0, 2) == 1, data[2] == 6 else { throw Failure.invalidFile }
        let size = uint(3, 4), compressed = uint(7, 4), start = 33 + uint(31, 2)
        guard (1...16_000_000).contains(size), start <= data.count, compressed == data.count - start else { throw Failure.invalidFile }
        let payload = data.subdata(in: start..<data.count)
        guard Data(Insecure.MD5.hash(data: payload)) == data.subdata(in: 11..<27) else { throw Failure.invalidFile }
        var output = Data(count: size)
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.invalidFile }
        defer { inflateEnd(&stream) }
        let result: Int32 = output.withUnsafeMutableBytes { destination in
            payload.withUnsafeBytes { source in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in = uInt(payload.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(size)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END, stream.total_out == size, stream.avail_in == 0 else { throw Failure.invalidFile }
        return output
    }
}

private final class PresetXMLReader: NSObject, XMLParserDelegate {
    var presets: [ChannelPreset] = []
    var invalid = false
    private var inPreset = false
    private var text = ""
    private var name = ""
    private var number = 0
    private var words: [Int] = []
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
        if element == "Preset" {
            if inPreset { invalid = true; parser.abortParsing() }
            inPreset = true; name = ""; number = 0; words = []
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        guard inPreset else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "Name": name = content
        case "Number": number = Int(content) ?? -1
        case "unsignedShort":
            guard let value = Int(content), (0...65535).contains(value) else { invalid = true; parser.abortParsing(); return }
            words.append(value)
        case "Preset":
            inPreset = false
            if words == [0] { words = [] }
            guard name.count <= 256, words.count % 2 == 0, words.count <= 20000 else { invalid = true; parser.abortParsing(); return }
            var values: [Int: Int] = [:]
            for index in stride(from: 0, to: words.count, by: 2) {
                let id = words[index]
                guard (1...10000).contains(id), values[id] == nil else { invalid = true; parser.abortParsing(); return }
                values[id] = words[index + 1]
            }
            // The original file contains a final empty P151 placeholder, not a slot.
            guard number == 151 && values.isEmpty || (1...50).contains(number) || (101...150).contains(number) else {
                invalid = true; parser.abortParsing(); return
            }
            presets.append(ChannelPreset(number: number, name: name, values: values))
        default: break
        }
    }
}

public extension ChannelPreset {
    func moved(to number: Int) throws -> ChannelPreset {
        guard (1...50).contains(number) || (101...150).contains(number) else { throw PresetArchive.Failure.invalidFile }
        let destinationChannel = number > 100 ? 2 : 1
        let shift = (destinationChannel - channel) * 1000
        var mapped: [Int: Int] = [:]
        for (id, value) in values {
            let base = id - (channel == 2 ? 1000 : 0)
            guard (101...999).contains(base) else { throw PresetArchive.Failure.invalidFile }
            mapped[id + shift] = value
        }
        return ChannelPreset(number: number, name: name, values: mapped)
    }
}

public struct MacPresetLibrary: Codable, Equatable {
    public var version = 1
    public var presets: [ChannelPreset]
    public init(presets: [ChannelPreset] = []) { self.presets = presets }
    public static func decode(_ data: Data) throws -> MacPresetLibrary {
        guard data.count < 16_000_000 else { throw PresetArchive.Failure.invalidFile }
        let library = try JSONDecoder().decode(Self.self, from: data)
        guard library.version == 1, library.presets.count <= 100,
              Set(library.presets.map(\.number)).count == library.presets.count else { throw PresetArchive.Failure.invalidFile }
        for preset in library.presets {
            guard !preset.name.isEmpty, preset.name.count <= 64,
                  preset.values.values.allSatisfy({ (0...65535).contains($0) }) else { throw PresetArchive.Failure.invalidFile }
            _ = try preset.moved(to: preset.number)
        }
        return library
    }
}
