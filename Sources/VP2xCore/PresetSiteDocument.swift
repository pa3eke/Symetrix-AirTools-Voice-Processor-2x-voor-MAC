import Foundation
import CryptoKit
import zlib

/// Updates only the selected preset in the original full device project.
public struct PresetSiteDocument {
    public let data: Data
    public init(data: Data) throws {
        _ = try PresetArchive.decode(data)
        self.data = data
    }
    public func replacing(_ preset: ChannelPreset) throws -> Data {
        try replacing([preset])
    }
    public func replacing(_ presets: [ChannelPreset]) throws -> Data {
        guard !presets.isEmpty, Set(presets.map(\.number)).count == presets.count else { throw PresetArchive.Failure.invalidFile }
        let xml = try PresetArchive.unpack(data)
        let document = try XMLDocument(data: xml, options: .nodePreserveAll)
        guard let root = document.rootElement(), root.name == "SiteFile" else { throw PresetArchive.Failure.invalidFile }
        for preset in presets {
        _ = try MacPresetLibrary.decode(JSONEncoder().encode(MacPresetLibrary(presets: [preset])))
        guard let bank = root.elements(forName: preset.channel == 1 ? "presets" : "presets2").first,
              let entry = bank.elements(forName: "Preset").first(where: { $0.elements(forName: "Number").first?.stringValue == String(preset.number) }),
              let name = entry.elements(forName: "Name").first,
              let oldValues = entry.elements(forName: "presetData").first else { throw PresetArchive.Failure.invalidFile }
        name.stringValue = preset.name
        let values = XMLElement(name: "presetData")
        let pairs = preset.values.keys.sorted().flatMap { [$0, preset.values[$0]!] }
        for word in pairs.isEmpty ? [0] : pairs {
            values.addChild(XMLElement(name: "unsignedShort", stringValue: String(word)))
        }
        if let index = entry.children?.firstIndex(where: { $0 === oldValues }) { entry.replaceChild(at: index, with: values) }
        entry.elements(forName: "NeedsDownloading").first?.stringValue = "false"
        }
        root.elements(forName: "fileCRC").first?.stringValue = UUID().uuidString
        root.elements(forName: "fileLastSavedTime").first?.stringValue = ISO8601DateFormatter().string(from: Date())
        let encoded = document.xmlData(options: .nodePrettyPrint)
        let decoded = try PresetArchive.decode(encoded)
        guard presets.allSatisfy({ preset in decoded.presets.first(where: { $0.number == preset.number }) == preset }) else { throw PresetArchive.Failure.invalidFile }
        return try pack(xml: encoded)
    }
    private func pack(xml: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw PresetArchive.Failure.invalidFile }
        defer { deflateEnd(&stream) }
        var compressed = Data(count: Int(deflateBound(&stream, uLong(xml.count))))
        let capacity = compressed.count
        let result: Int32 = compressed.withUnsafeMutableBytes { destination in
            xml.withUnsafeBytes { source in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in = uInt(xml.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(capacity)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END else { throw PresetArchive.Failure.invalidFile }
        compressed.count = Int(stream.total_out)
        let filename: Data
        let dosDate: Data
        if data.count >= 33, data[0] == 1, data[1] == 0, data[2] == 6 {
            let length = Int(data[31]) | Int(data[32]) << 8
            filename = data.subdata(in: 33..<(33 + length)); dosDate = data.subdata(in: 27..<31)
        } else {
            filename = Data("VP2x-Mac.vp2x".utf8); dosDate = Data(repeating: 0, count: 4)
        }
        var packed = Data([1,0,6])
        func appendLE(_ number: Int, bytes: Int) { for i in 0..<bytes { packed.append(UInt8((number >> (8*i)) & 255)) } }
        appendLE(xml.count, bytes: 4); appendLE(compressed.count, bytes: 4)
        packed.append(Data(Insecure.MD5.hash(data: compressed))); packed.append(dosDate)
        appendLE(filename.count, bytes: 2); packed.append(filename); packed.append(compressed)
        return packed
    }
}
