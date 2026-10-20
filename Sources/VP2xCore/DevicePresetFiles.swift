import Foundation

/// Uses the factory FTP account from the original application's FtpControl.
public enum DevicePresetFiles {
    private static let sitePath = "/home/mars/site/SavedSiteFile.site"
    public static func readSite(host: String) throws -> Data { try download(host: host, path: sitePath) }
    public static func writeSite(host: String, data: Data) throws {
        _ = try PresetSiteDocument(data: data)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: local) }
        try data.write(to: local, options: .atomic)
        let remote = sitePath + ".mac-" + UUID().uuidString + ".tmp"
        try run(host: host, arguments: ["--upload-file", local.path, "ftp://\(host)/\(remote)"])
        guard try download(host: host, path: remote) == data else { throw NativePresetSession.Failure.verification }
        // Rename only a completely uploaded and verified temporary file.
        try run(host: host, arguments: ["--quote", "RNFR \(remote)", "--quote", "RNTO \(sitePath)", "--list-only", "ftp://\(host)//home/mars/site/"])
        guard try readSite(host: host) == data else { throw NativePresetSession.Failure.verification }
    }
    private static func download(host: String, path: String) throws -> Data {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        try run(host: host, arguments: ["--max-filesize", "16000000", "--output", output.path, "ftp://\(host)/\(path)"])
        return try Data(contentsOf: output)
    }
    private static func run(host: String, arguments: [String]) throws {
        guard VPProtocol.validIPv4(host) else { throw VPClient.Failure.invalidAddress }
        struct Login: Decodable { let user: String; let password: String }
        guard let resource = VPResources.url("DeviceFTP", withExtension: "json")
            ?? VPResources.url("DeviceFTPDefaults", withExtension: "json") else {
            throw NSError(domain: "VP2xPresets", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Een meegeleverd FTP-hulpbestand ontbreekt. Installeer de app opnieuw. De back-up op je Mac blijft beschikbaar."])
        }
        let login = try JSONDecoder().decode(Login.self, from: Data(contentsOf: resource))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--config", "-", "--fail", "--silent", "--show-error", "--connect-timeout", "4", "--max-time", "12"] + arguments
        let input = Pipe(), errors = Pipe()
        process.standardInput = input; process.standardError = errors; process.standardOutput = FileHandle.nullDevice
        func quote(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") }
        try process.run()
        input.fileHandleForWriting.write(Data("user = \"\(quote(login.user + ":" + login.password))\"\n".utf8))
        try? input.fileHandleForWriting.close()
        _ = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "VP2xPresets", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "De overdracht van het VP2x-projectbestand is niet gelukt. De back-up op je Mac blijft beschikbaar."])
        }
    }
}
