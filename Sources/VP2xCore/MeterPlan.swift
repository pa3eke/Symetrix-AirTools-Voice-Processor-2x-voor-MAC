import Foundation

public enum MeterPlan {
    public static let main = [6113, 6808, 7113, 7808]
    public static let all = Set(main + [6220,6240,6300,6309,7220,7240,7300,7309])
    public static func visible(panels: Set<String>) -> [Int] {
        var result = main
        for (name, ids) in [("DsExp1",[6220,6240]),("DsExp2",[7220,7240]),
                            ("Compressor1",[6300,6309]),("Compressor2",[7300,7309])] {
            if panels.contains(name) { result += ids }
        }
        return result.sorted()
    }
}

public struct MeterFrame: Sendable {
    public let values: [Int: Int]
    public let receivedReplies: Int
    public let completedSweeps: Int
}
