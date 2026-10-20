import Foundation

public struct ControlOption: Codable, Identifiable, Hashable {
    public let label: String
    public let value: Int
    public var id: Int { value }
}
public struct VPControl: Codable, Identifiable {
    public let id: Int
    public let name, label, section, kind: String
    public let channel: Int
    public let minimum, maximum: Double
    public let logarithmic, inverted: Bool
    public let options: [ControlOption]
    public let sourcePanel: String
    public var isWritable: Bool { kind != "meter" }
    public func displayValue(raw: Int) -> Double {
        let fraction = Double(inverted ? 65535 - raw : raw) / 65535
        if logarithmic, minimum > 0 { return minimum * pow(maximum / minimum, fraction) }
        return minimum + (maximum - minimum) * fraction
    }
    public func rawValue(display: Double) -> Int {
        let bounded = min(maximum, max(minimum, display))
        let fraction = logarithmic && minimum > 0
            ? log(bounded / minimum) / log(maximum / minimum)
            : (bounded - minimum) / (maximum - minimum)
        let value = Int((min(1, max(0, fraction)) * 65535).rounded())
        return inverted ? 65535 - value : value
    }
    public func formatted(raw: Int) -> String {
        let value = displayValue(raw: raw)
        if name.contains("Attack") || name.contains("Release") { return String(format: "%.1f ms", value * 1000) }
        if name.contains("Freq") { return value >= 1000 ? String(format: "%.2f kHz", value / 1000) : String(format: "%.1f Hz", value) }
        if name.contains("Ratio") { return String(format: "%.2f : 1", value) }
        if name.contains("QFader") || name.contains("QDisplay") || name.contains("Res") { return String(format: "%.2f", value) }
        if kind == "meter" { return String(format: "%.1f dBu", 72 * Double(raw) / 65535 - 48) }
        return String(format: "%.1f dB", value)
    }
}
public struct ControlCatalog: Codable {
    public let sourceSHA256: String
    public let controls: [VPControl]
    public init(sourceSHA256: String, controls: [VPControl]) { self.sourceSHA256 = sourceSHA256; self.controls = controls }
    public static func load() throws -> Self {
        guard let url = VPResources.url("Controls", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
