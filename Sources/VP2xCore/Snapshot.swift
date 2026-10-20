import Foundation
public struct VPSnapshot: Codable {
    public let formatVersion: Int
    public let capturedAt: Date
    public let host: String
    public let catalogSHA256: String
    public let values: [Int: Int]
    public init(host: String, catalogSHA256: String, values: [Int: Int]) {
        self.formatVersion = 1; self.capturedAt = Date(); self.host = host
        self.catalogSHA256 = catalogSHA256; self.values = values
    }
    public func validated(for catalog: ControlCatalog) throws -> [Int: Int] {
        guard formatVersion == 1, catalogSHA256 == catalog.sourceSHA256 else { throw CocoaError(.fileReadCorruptFile) }
        let writable = Set(catalog.controls.filter(\.isWritable).map(\.id))
        guard !values.isEmpty, values.allSatisfy({ writable.contains($0.key) && (0...65535).contains($0.value) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return values
    }
}
