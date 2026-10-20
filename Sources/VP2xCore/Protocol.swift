import Foundation

public enum VPProtocol {
    public static let port: UInt16 = 48630
    public static func get(_ controller: Int) -> String { "GS2 \(controller)\r" }
    public static func set(_ controller: Int, value: Int) -> String { "CS \(controller) \(min(65535, max(0, value)))\r" }
    public static func parse(_ data: Data) -> [Int: Int] {
        guard let text = String(data: data, encoding: .ascii) else { return [:] }
        var result: [Int: Int] = [:]
        for line in text.components(separatedBy: CharacterSet(charactersIn: "\r\n\0")) {
            let parts = line.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "=", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
            if parts.count == 2, let id = Int(parts[0]), (1...10000).contains(id),
               let value = Int(parts[1]), (0...65535).contains(value) { result[id] = value }
        }
        return result
    }
    public static func validIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) && (Int($0).map { (0...255).contains($0) } ?? false) }
    }
}
