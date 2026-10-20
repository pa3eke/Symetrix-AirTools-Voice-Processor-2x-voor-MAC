import Foundation
import Darwin

/// Original HostControl UDP host protocol. Kept separate from audio/controller
/// polling; only bounded preset buffer operations are exposed here.
public final class NativePresetSession {
    public enum Failure: LocalizedError {
        case transport, malformed, rejected, verification
        public var errorDescription: String? {
            switch self {
            case .transport: return "De VP2x antwoordde niet op de presetaanvraag."
            case .malformed: return "Onverwacht antwoord op de presetaanvraag; overdracht gestopt."
            case .rejected: return "De VP2x heeft de presetopdracht geweigerd."
            case .verification: return "De opgeslagen preset kon niet volledig worden bevestigd."
            }
        }
    }
    private let socketFD: Int32
    private var bufferAddress: UInt32?
    public init(host: String, port: UInt16 = 8000) throws {
        guard VPProtocol.validIPv4(host) else { throw VPClient.Failure.invalidAddress }
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw Failure.transport }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        _ = host.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { Darwin.close(fd); throw Failure.transport }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            Darwin.close(fd); throw Failure.transport
        }
        socketFD = fd
    }
    deinit { Darwin.close(socketFD) }
    public static func packet(command: UInt32, payload: [UInt32]) -> Data {
        var words = Array(repeating: UInt32(0), count: 8)
        words += [1, UInt32(payload.count + 2), command] + payload
        let sum = words.dropFirst(9).reduce(UInt32(0), &+)
        words.append(~sum)
        var data = Data()
        for word in words { var value = word.bigEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        return data
    }
    public static func response(_ data: Data, command: UInt32, count: Int) throws -> [UInt32] {
        guard data.count >= 28, data.count % 4 == 0 else { throw Failure.malformed }
        let bytes = [UInt8](data)
        var words: [UInt32] = []
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let high = (UInt32(bytes[i]) << 24) | (UInt32(bytes[i + 1]) << 16)
            let low = (UInt32(bytes[i + 2]) << 8) | UInt32(bytes[i + 3])
            words.append(high | low)
        }
        guard words[0] == 1, words[1] == 28, words[4] == command, words[5] == 1 else { throw Failure.malformed }
        guard words[2] == 0 else { throw Failure.rejected }
        guard words[3] == count + 3, data.count == (count + 7) * 4 else { throw Failure.malformed }
        return Array(words[6..<(6 + count)])
    }
    private func request(_ command: UInt32, _ payload: [UInt32] = [], count: Int) throws -> [UInt32] {
        let data = Self.packet(command: command, payload: payload)
        let sent = data.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) }
        guard sent == data.count else { throw Failure.transport }
        var reply = [UInt8](repeating: 0, count: 4096)
        let received = Darwin.recv(socketFD, &reply, reply.count, 0)
        guard received > 0 else { throw Failure.transport }
        // Never replay a potentially committed write after timeout.
        return try Self.response(Data(reply.prefix(received)), command: command, count: count)
    }
    private func address() throws -> UInt32 {
        if let bufferAddress { return bufferAddress }
        let base = try request(0xb1, count: 1)[0]
        guard base > 0, base <= UInt32.max - 0x10000 else { throw Failure.malformed }
        let buffer = base + 0x8000
        bufferAddress = buffer
        return buffer
    }
    public func read(number: Int) throws -> [Int: Int] {
        _ = try PresetArchive.number(channel: number > 100 ? 2 : 1, slot: number > 100 ? number - 100 : number)
        let base = try address()
        let pairs = Int(try request(0x105, [base, UInt32(number - 1)], count: 1)[0])
        guard (0...512).contains(pairs) else { throw Failure.malformed }
        var words: [UInt32] = []
        for offset in stride(from: 0, to: pairs * 2, by: 64) {
            let size = min(64, pairs * 2 - offset)
            words += try request(0x8a, [base + UInt32(offset * 4), UInt32(size)], count: size)
        }
        var values: [Int: Int] = [:]
        for offset in stride(from: 0, to: words.count, by: 2) {
            let id = Int(words[offset]), value = Int(words[offset + 1])
            guard (1...10000).contains(id), (0...65535).contains(value), values[id] == nil else { throw Failure.malformed }
            values[id] = value
        }
        return values
    }
    /// Caller must preserve the previous preset before calling. Successful commit
    /// is followed by an independent read of the entire stored preset.
    public func write(_ preset: ChannelPreset) throws {
        _ = try preset.moved(to: preset.number)
        guard preset.values.count <= 512, preset.values.values.allSatisfy({ (0...65535).contains($0) }) else { throw Failure.malformed }
        let base = try address()
        // _writePreset packs pairs as two big-endian 16-bit values per word.
        let packed = preset.values.keys.sorted().map { id in UInt32(id) << 16 | UInt32(preset.values[id]!) }
        for offset in stride(from: 0, to: packed.count, by: 128) {
            let chunk = Array(packed[offset..<min(offset + 128, packed.count)])
            _ = try request(0x89, [base + UInt32(offset * 4), UInt32(chunk.count)] + chunk, count: 0)
        }
        let committed = try request(0x10a, [base, UInt32(preset.number - 1), UInt32(packed.count)], count: 1)[0]
        guard committed == packed.count else { throw Failure.verification }
        guard try read(number: preset.number) == preset.values else { throw Failure.verification }
    }
}
