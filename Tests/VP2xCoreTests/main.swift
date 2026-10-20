import Foundation
import VP2xCore
import Darwin

// Run from a relocated app with no SwiftPM build resources available.
if CommandLine.arguments.contains("--resources-check") {
    let missing = CommandLine.arguments.contains("--expect-missing")
    for name in ["Controls", "Skin"] {
        let url = VPResources.url(name, withExtension: "json")
        guard (url == nil) == missing else { fatalError("Resource availability mismatch: \(name)") }
        if let url { _ = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) }
    }
    guard VPResources.url("does-not-exist", withExtension: "json") == nil else { fatalError("Missing lookup") }
    if !missing { _ = try ControlCatalog.load(); guard VPArtwork.url("mainmeter.png") != nil else { fatalError("Artwork missing") } }
    print("PASS: relocated resource lookup; missing files return safely")
    exit(0)
}

// Timing check for live drags: bounded traffic, newest value, mouse-up wins.
if CommandLine.arguments.contains("--live-control-check") {
    Task { @MainActor in
        var sent: [(Int,Int,Double)] = []
        let start = ProcessInfo.processInfo.systemUptime
        let live = LiveControlDispatcher { id, value in sent.append((id,value,ProcessInfo.processInfo.systemUptime - start)) }
        for value in 0...35 {
            live.submit(533, value: value)
            try await Task.sleep(for: .milliseconds(5))
        }
        live.finish(533, value: 54321)
        let finishedCount = sent.count
        try await Task.sleep(for: .milliseconds(100))
        guard sent.first?.1 == 0, sent.last?.1 == 54321, sent.count == finishedCount,
              sent.count >= 3, sent.count <= 6 else { fatalError("live control coalescing/final value failed") }
        live.submit(533, value: 100); live.submit(539, value: 200)
        live.cancelAll()
        let cancelledCount = sent.count
        try await Task.sleep(for: .milliseconds(100))
        guard sent.count == cancelledCount else { fatalError("cancelled drag sent a deferred value") }
        let report: [String:Any] = ["passed":true,"drag_events":36,"drag_commands":finishedCount,
            "first_delivery_ms":sent[0].2*1000,"final_value":54321,"deferred_value_after_mouse_up":false,"cancelled_values_sent":false]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
        exit(0)
    }
    dispatchMain()
}

// Quick-button recall framing is exercised only against loopback.
if CommandLine.arguments.contains("--quick-fixture-check") {
    Task { @MainActor in
        let client = VPClient()
        do {
            try client.connect(host: "127.0.0.1")
            let untouchedTwo = try await client.read(1700)
            for number in QuickPreset(id: 0, name: "One", channelOne: 15).numbers { try await client.recall(number) }
            let one = try await client.read(700), two = try await client.read(1700)
            guard one == 14, two == untouchedTwo else { fatalError("single-channel recall changed wrong bank") }
            for number in QuickPreset(id: 1, name: "Two", channelTwo: 22).numbers { try await client.recall(number) }
            let keptOne = try await client.read(700), updatedTwo = try await client.read(1700)
            guard keptOne == 14, updatedTwo == 21 else { fatalError("channel two recall changed wrong bank") }
            for number in QuickPreset(id: 2, name: "Pair", channelOne: 19, channelTwo: 21).numbers { try await client.recall(number) }
            let pairedOne = try await client.read(700), pairedTwo = try await client.read(1700)
            guard pairedOne == 18, pairedTwo == 20 else { fatalError("pair recall did not confirm both banks") }
            client.disconnect()
            print("PASS: quick single-channel recalls preserve the other channel; pair recall confirms both banks on loopback")
            exit(0)
        } catch { print("FAIL: \(error)"); client.disconnect(); exit(1) }
    }
    dispatchMain()
}

// Exercises the very same read-only transport used by the app, against an explicit host.
if let index = CommandLine.arguments.firstIndex(of: "--meters"), CommandLine.arguments.count > index + 1 {
    let host = CommandLine.arguments[index + 1]
    final class Counts: @unchecked Sendable {
        let lock = NSLock()
        var frames = 0
        var replies = 0
        var sweeps = 0
        var lastValues: [Int:Int] = [:]
    }
    let counts = Counts()
    let stream = MeterStream()
    let ids = MeterPlan.visible(panels: ["DsExp1", "Compressor2"])
    let start = ProcessInfo.processInfo.systemUptime
    stream.start(host: host, ids: ids) { frame in
        counts.lock.lock(); defer { counts.lock.unlock() }
        counts.frames += 1; counts.replies = frame.receivedReplies
        counts.sweeps = frame.completedSweeps; counts.lastValues = frame.values
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        counts.lock.lock(); defer { counts.lock.unlock() }
        let seconds = ProcessInfo.processInfo.systemUptime - start
        let report: [String:Any] = ["host": host, "seconds": seconds, "requested_hz": 30,
            "delivered_frames": counts.frames, "complete_meter_sweeps": counts.sweeps,
            "received_replies": counts.replies, "fresh_meters": counts.lastValues.count,
            "frame_hz": Double(counts.frames) / seconds, "complete_sweep_hz": Double(counts.sweeps) / seconds,
            "controller_ids": ids, "read_only": true]
        let json = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: json, encoding: .utf8)!)
        stream.stop()
        exit(counts.frames >= 100 && counts.sweeps >= 80 && counts.lastValues.count == ids.count ? 0 : 1)
    }
    dispatchMain()
}

// Endurance check of the exact shared-socket client used by the app. Read-only.
if let index = CommandLine.arguments.firstIndex(of: "--connection-check"), CommandLine.arguments.count > index + 2 {
    let host = CommandLine.arguments[index + 1]
    let duration = Double(CommandLine.arguments[index + 2]) ?? 60
    Task { @MainActor in
        let client = VPClient()
        let stream = MeterStream()
        var retries = 0
        var frames = 0
        var replies = 0
        var sweeps = 0
        var settings = 0
        var minimumFresh = 8
        var lastFresh = 0
        let started = ProcessInfo.processInfo.systemUptime
        var recent: [String] = []
        client.trace = {
            if $0.contains("nieuwe poging") { retries += 1 }
            recent.append($0)
            if recent.count > 16 { recent.removeFirst() }
        }
        do {
            try client.connect(host: host)
            _ = try await client.read(109)
            client.attachMeters(stream, ids: MeterPlan.visible(panels: ["Compressor1", "Compressor2"])) { frame in
                Task { @MainActor in
                    frames += 1; replies = frame.receivedReplies; sweeps = frame.completedSweeps
                    lastFresh = frame.values.count
                    if ProcessInfo.processInfo.systemUptime - started > 2 { minimumFresh = min(minimumFresh, lastFresh) }
                }
            }
            let ids = try ControlCatalog.load().controls.filter { !MeterPlan.all.contains($0.id) }.map(\.id)
            while ProcessInfo.processInfo.systemUptime - started < duration {
                _ = try await client.read(ids[settings % ids.count])
                settings += 1
                try await Task.sleep(for: .milliseconds(50))
            }
            let report: [String:Any] = ["host":host,"seconds":ProcessInfo.processInfo.systemUptime-started,
                "settings_read":settings,"retried_reads":retries,"meter_frames":frames,
                "meter_replies":replies,"complete_sweeps":sweeps,"minimum_fresh_after_warmup":minimumFresh,
                "last_fresh":lastFresh,"shared_socket":true,"read_only":true]
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
            client.disconnect()
            exit(settings > 0 && replies > 0 && lastFresh == 8 ? 0 : 1)
        } catch {
            print("FAIL shared-socket endurance: \(error), settings=\(settings), replies=\(replies), frames=\(frames), retries=\(retries), seconds=\(ProcessInfo.processInfo.systemUptime-started)")
            print(recent.joined(separator: "\n"))
            client.disconnect(); exit(1)
        }
    }
    dispatchMain()
}

if let index = CommandLine.arguments.firstIndex(of: "--preset-check") ?? CommandLine.arguments.firstIndex(of: "--preset-host"), CommandLine.arguments.count > index + 1 {
    let input = CommandLine.arguments[index + 1]
    let data = CommandLine.arguments[index] == "--preset-host" ? try DevicePresetFiles.readSite(host: input) : try Data(contentsOf: URL(fileURLWithPath: input))
    let archive = try PresetArchive.decode(data)
    let report: [String: Any] = ["presets": archive.presets.count,
        "channel_one": archive.presets.filter { $0.channel == 1 }.count,
        "channel_two": archive.presets.filter { $0.channel == 2 }.count,
        "populated": archive.presets.filter { !$0.isEmpty }.count,
        "slot_19": archive.presets.first { $0.number == 19 }?.name ?? "",
        "slot_121": archive.presets.first { $0.number == 121 }?.name ?? ""]
    print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
    exit(0)
}

// Explicit hardware validation: only an identical rewrite of the backed-up P19.
// No recall, clear, parameter change, or retries. Abort before any write on drift.
if let i = CommandLine.arguments.firstIndex(of: "--hardware-identical-preset-check"), CommandLine.arguments.count > i + 3 {
    let host = CommandLine.arguments[i + 1]
    let reference = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
    let backup = URL(fileURLWithPath: CommandLine.arguments[i + 3], isDirectory: true)
    let expectedArchive = try PresetArchive.decode(reference)
    let expected = expectedArchive.presets.first { $0.number == 19 }!
    let site = try DevicePresetFiles.readSite(host: host)
    guard site == reference else { fatalError("Project changed: stopped before writing") }
    let session = try NativePresetSession(host: host)
    let actual = try session.read(number: 19)
    guard actual == expected.values, actual.count == 51 else { fatalError("P19 changed: stopped before writing") }
    try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
    try site.write(to: backup.appendingPathComponent("before.site"), options: .atomic)
    try JSONEncoder().encode(MacPresetLibrary(presets: [expected])).write(to: backup.appendingPathComponent("before-P19.json"), options: .atomic)
    print("Backups written. Rewriting identical P19 values; no recall.")
    try session.write(expected)
    print("PASS: identical P19 native write and all 51 values verified")
    try DevicePresetFiles.writeSite(host: host, data: site)
    let after = try DevicePresetFiles.readSite(host: host)
    guard after == site, try PresetArchive.decode(after) == expectedArchive else { fatalError("Site verification failed") }
    try after.write(to: backup.appendingPathComponent("after.site"), options: .atomic)
    print("PASS: identical project upload, atomic rename, and all 100 presets verified")
    exit(0)
}

// Full-bank integration remains loopback-only; FTP commit is captured locally.
if let i = CommandLine.arguments.firstIndex(of: "--bank-fixture-check"), CommandLine.arguments.count > i + 1 {
    let original = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    var target = try PresetBankRestore.archive(original).presets
    for number in [19,121] {
        let index = target.firstIndex { $0.number == number }!
        let id = number > 100 ? 1109 : 109
        target[index].values[id] = (target[index].values[id]! + 1) % 65536
        target[index].name = "Fixture \(number)"
    }
    let data = try JSONEncoder().encode(MacPresetLibrary(presets: target))
    let session = try NativePresetSession(host: "127.0.0.1")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vp2x-bank-fixture-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    var committed: Data?
    let result = try PresetBankRestore.run(data: data, original: original, backupDirectory: folder, memory: session, commitSite: { committed = $0 }, progress: { _ in })
    guard result.presets == target, try PresetBankRestore.archive(committed!).presets == target else { fatalError("bank metadata mismatch") }
    for preset in target { guard try session.read(number: preset.number) == preset.values else { fatalError("slot mismatch") } }
    print("PASS: full native bank restore; 100 safety reads, both channels changed, all 100 slots verified; project metadata captured locally")
    exit(0)
}

// This destructive protocol check is deliberately restricted to loopback.
if CommandLine.arguments.contains("--native-fixture-check") {
    let session = try NativePresetSession(host: "127.0.0.1")
    let original = try session.read(number: 19)
    let untouched = try session.read(number: 121)
    try session.write(ChannelPreset(number: 19, name: "Same", values: original))
    var changed = original; changed[109] = 12345
    try session.write(ChannelPreset(number: 19, name: "Changed", values: changed))
    guard try session.read(number: 19)[109] == 12345 else { fatalError("write/readback failed") }
    try session.write(ChannelPreset(number: 19, name: "Empty", values: [:]))
    guard try session.read(number: 19).isEmpty else { fatalError("clear failed") }
    try session.write(ChannelPreset(number: 19, name: "Restore", values: original))
    guard try session.read(number: 121) == untouched else { fatalError("other channel changed") }
    print("PASS: native preset same-value write, changed write, full verification, clear, restore, channel isolation")
    exit(0)
}

var count = 0
func expect(_ passed: @autoclosure () -> Bool, _ message: String) {
    count += 1
    guard passed() else { fatalError("FAILED: \(message)") }
}
func expectThrows(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError("FAILED: \(message)") }
    catch { count += 1 }
}
let data = Data("109 36863\r#00107=65535\r\n#00108=-0001\rACK\rCS 109 10\r111 65536\r0 12\r".utf8)
expect(VPProtocol.parse(data) == [109: 36863, 107: 65535], "mixed/malformed datagrams")
expect(VPProtocol.parse(Data([0xff, 0xfe])).isEmpty, "non-ASCII datagrams")
expect(VPProtocol.get(109) == "GS2 109\r", "GS2 framing")
expect(VPProtocol.set(109, value: 70000) == "CS 109 65535\r", "upper wire bound")
expect(VPProtocol.set(109, value: -1) == "CS 109 0\r", "lower wire bound")
expect(VPProtocol.validIPv4("192.0.2.100"), "valid IPv4")
for invalid in ["192.168.1", "256.1.1.1", "1..2.3", "1.2.3.4\rCS", "localhost"] {
    expect(!VPProtocol.validIPv4(invalid), "invalid IPv4: \(invalid)")
}
expect(Set(MeterPlan.visible(panels: [])) == Set(MeterPlan.main), "main meters always visible")
expect(MeterPlan.visible(panels: ["Compressor1", "DsExp2"]).count == 8, "only visible DSP meters")
expect(MeterPlan.visible(panels: ["Input1", "System"]).count == 4, "no invisible DSP polling")
expect(MeterPlan.all.count == 12, "read-only meter allowlist")
expect(!MeterPlan.all.contains(109), "gain cannot enter meter stream")
// Reproduce fresh -> expired -> fresh: missing packets must never expose lit backgrounds.
for id in [6220,6240,6300,7220,7240,7300] {
    let quiet = MeterScale.overlayFraction(raw: 65535, controller: id, invertedArtwork: true)
    let expired = MeterScale.overlayFraction(raw: nil, controller: id, invertedArtwork: true)
    expect(quiet == 1 && expired == quiet, "expired reduction meter stays dark: \(id)")
    expect(MeterScale.overlayFraction(raw: 0, controller: id, invertedArtwork: true) == 0,
           "real maximum reduction remains visible: \(id)")
}
for id in MeterPlan.main + [6309,7309] {
    expect(MeterScale.overlayFraction(raw: nil, controller: id, invertedArtwork: false) == 0,
           "expired level meter stays dark: \(id)")
}
let presetXML = Data("<SiteFile><presets><Preset><Name>Test &amp; voice</Name><Number>19</Number><presetData><unsignedShort>101</unsignedShort><unsignedShort>65535</unsignedShort></presetData></Preset></presets><presets2><Preset><Name>Second</Name><Number>121</Number><presetData><unsignedShort>1101</unsignedShort><unsignedShort>0</unsignedShort></presetData></Preset><Preset><Name>Empty</Name><Number>151</Number><presetData><unsignedShort>0</unsignedShort></presetData></Preset></presets2></SiteFile>".utf8)
let archive = try PresetArchive.decode(presetXML)
expect(archive.presets.count == 2, "original empty P151 placeholder is excluded")
expect(archive.presets[0].name == "Test & voice", "preset XML entities")
expect(archive.presets[1].channel == 2 && archive.presets[1].slot == 21, "channel bank number mapping")
expect(archive.presets[0].values == [101:65535], "preset preserves raw controller values")
let channelTwoNumber = try PresetArchive.number(channel: 2, slot: 21)
expect(channelTwoNumber == 121, "channel 2 hardware preset number")
expectThrows("reject invalid preset channel") { _ = try PresetArchive.number(channel: 3, slot: 1) }
expectThrows("reject invalid preset slot") { _ = try PresetArchive.number(channel: 1, slot: 51) }
expectThrows("reject duplicate preset slots") { _ = try PresetArchive.decode(Data("<SiteFile><Preset><Name>A</Name><Number>1</Number><presetData/></Preset><Preset><Name>B</Name><Number>1</Number><presetData/></Preset></SiteFile>".utf8)) }
expectThrows("reject incomplete controller pair") { _ = try PresetArchive.decode(Data("<SiteFile><Preset><Name>A</Name><Number>1</Number><presetData><unsignedShort>101</unsignedShort></presetData></Preset></SiteFile>".utf8)) }
expectThrows("reject XML external entities") { _ = try PresetArchive.decode(Data("<!DOCTYPE SiteFile [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><SiteFile/>".utf8)) }
expectThrows("reject truncated packed site") { _ = try PresetArchive.decode(Data([1,0,6,0])) }
let copied = try archive.presets[0].moved(to: 150)
expect(copied.number == 150 && copied.values == [1101:65535], "copy preset across channels shifts controller addresses")
let back = try copied.moved(to: 19)
expect(back.values == archive.presets[0].values, "channel copy round trip preserves values")
let macLibrary = MacPresetLibrary(presets: archive.presets)
let macJSON = try JSONEncoder().encode(macLibrary)
let decodedLibrary = try MacPresetLibrary.decode(macJSON)
expect(decodedLibrary == macLibrary, "Mac preset export/import round trip")
expectThrows("reject duplicate Mac slots") { _ = try MacPresetLibrary.decode(JSONEncoder().encode(MacPresetLibrary(presets: [copied,copied]))) }
expectThrows("reject incompatible controller on channel copy") { _ = try ChannelPreset(number: 19, name: "Invalid", values: [8602:1]).moved(to: 119) }
expectThrows("reject invalid Mac raw values") { _ = try MacPresetLibrary.decode(JSONEncoder().encode(MacPresetLibrary(presets: [ChannelPreset(number: 1, name: "Invalid", values: [101:65536])]))) }
let nativeGolden = Data([0,0,0,1, 0,0,0,28, 0,0,0,0, 0,0,0,4, 0,0,0,177, 0,0,0,1, 1,176,0,4, 73,255,79,221])
let nativeAddress = try NativePresetSession.response(nativeGolden, command: 0xb1, count: 1)
expect(nativeAddress == [0x1b00004], "decode observed physical host response")
expectThrows("reject host response for another command") { _ = try NativePresetSession.response(nativeGolden, command: 0x105, count: 1) }
expectThrows("reject incomplete host response") { _ = try NativePresetSession.response(nativeGolden.dropLast(), command: 0xb1, count: 1) }
// Captured 8A replies retain header field 28 even for multi-word payloads.
var nativeWide = Data()
for word: UInt32 in [1,28,0,7,0x8a,1,101,0,109,28672,0] {
    var big = word.bigEndian; withUnsafeBytes(of: &big) { nativeWide.append(contentsOf: $0) }
}
let nativeWideValues = try NativePresetSession.response(nativeWide, command: 0x8a, count: 4)
expect(nativeWideValues == [101,0,109,28672], "physical multi-word reply uses fixed header field")
expectThrows("response count must match packet size") { _ = try NativePresetSession.response(nativeWide, command: 0x8a, count: 3) }
let nativePacket = NativePresetSession.packet(command: 0xb1, payload: [])
expect(nativePacket.prefix(32) == Data(repeating: 0, count: 32), "original Ethernet send zeroes first eight words")
expect(nativePacket.suffix(4) == Data([255,255,255,76]), "physical read packet checksum")
var editedPreset = archive.presets[0]
editedPreset.name = "Mac <&> voice"
editedPreset.values[101] = 12345
let packedSite = try PresetSiteDocument(data: presetXML).replacing(editedPreset)
let editedArchive = try PresetArchive.decode(packedSite)
expect(editedArchive.presets.first { $0.number == 19 } == editedPreset, "write original packed site and verify XML name escaping")
expect(editedArchive.presets.first { $0.number == 121 } == archive.presets[1], "project update preserves other channel preset")
var badSite = packedSite; badSite[badSite.count - 5] ^= 1
expectThrows("reject corrupted compressed project checksum") { _ = try PresetArchive.decode(badSite) }
// Whole-bank recovery must finish the safety backup before its first write.
let bankNumbers = Array(1...50) + Array(101...150)
func bankXML() -> Data {
    func bank(_ numbers: [Int]) -> String {
        numbers.map { n in "<Preset><Name>Voice \(n)</Name><Number>\(n)</Number><NeedsDownloading>true</NeedsDownloading><presetData><unsignedShort>\(n > 100 ? 1101 : 101)</unsignedShort><unsignedShort>\(n)</unsignedShort></presetData></Preset>" }.joined()
    }
    return Data("<SiteFile><LiveSettings>keep-me</LiveSettings><presets>\(bank(Array(1...50)))</presets><presets2>\(bank(Array(101...150)))</presets2></SiteFile>".utf8)
}
let fullBankData = bankXML()
let fullBank = try PresetBankRestore.archive(fullBankData)
expect(fullBank.presets.count == 100, "complete backup requires both banks")
expectThrows("partial project cannot trigger full restore") { _ = try PresetBankRestore.archive(presetXML) }
expectThrows("partial Mac library cannot trigger full restore") { _ = try PresetBankRestore.archive(macJSON) }
final class RestoreMemoryFixture: PresetMemory {
    var values: [Int:[Int:Int]]
    var reads = 0
    var writes: [Int] = []
    var failOn: Int?
    let backup: URL
    init(_ presets: [ChannelPreset], backup: URL) { self.values = Dictionary(uniqueKeysWithValues: presets.map { ($0.number,$0.values) }); self.backup = backup }
    func read(number: Int) throws -> [Int:Int] { reads += 1; return values[number]! }
    func write(_ preset: ChannelPreset) throws {
        expect(reads == 100, "all 100 slots read before first restore write")
        let files = try FileManager.default.subpathsOfDirectory(atPath: backup.path)
        expect(files.contains { $0.hasSuffix("presets-before.site") }, "recovery site exists before writing")
        expect(files.contains { $0.hasSuffix("presets-before.json") }, "recovery memory JSON exists before writing")
        if failOn == preset.number { throw NativePresetSession.Failure.transport }
        writes.append(preset.number); values[preset.number] = preset.values
    }
}
let restoreTemp = FileManager.default.temporaryDirectory.appendingPathComponent("vp2x-restore-check-" + UUID().uuidString)
try FileManager.default.createDirectory(at: restoreTemp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: restoreTemp) }
var targetBank = fullBank.presets
for n in [19,121] { let i = targetBank.firstIndex { $0.number == n }!; targetBank[i].values[n > 100 ? 1101 : 101] = 5000; targetBank[i].name = "Restored \(n)" }
let targetBankData = try JSONEncoder().encode(MacPresetLibrary(presets: targetBank))
let restoreMemory = RestoreMemoryFixture(fullBank.presets, backup: restoreTemp)
var committedRestore: Data?
let restoredBank = try PresetBankRestore.run(data: targetBankData, original: fullBankData, backupDirectory: restoreTemp, memory: restoreMemory, commitSite: { committedRestore = $0 }, progress: { _ in })
expect(restoreMemory.writes == [19,121], "unchanged slots avoid needless writes; both channels restore")
expect(restoredBank.presets == targetBank, "full restore returns exact source values and names")
let restoreProject = try PresetArchive.decode(committedRestore!)
expect(restoreProject.presets == targetBank, "all 100 names and values committed together")
let restoredXML = try PresetArchive.unpack(committedRestore!)
expect(String(decoding: restoredXML, as: UTF8.self).contains("<LiveSettings>keep-me</LiveSettings>"), "restore preserves live project settings")
let unchangedMemory = RestoreMemoryFixture(fullBank.presets, backup: restoreTemp)
_ = try PresetBankRestore.run(data: fullBankData, original: fullBankData, backupDirectory: restoreTemp, memory: unchangedMemory, commitSite: { _ in }, progress: { _ in })
expect(unchangedMemory.writes.isEmpty && unchangedMemory.reads == 100, "identical restore checks all slots without native writes")
let failingMemory = RestoreMemoryFixture(fullBank.presets, backup: restoreTemp); failingMemory.failOn = 121
var metadataAfterFailure = false
expectThrows("failed restore stops without committing project names") {
    _ = try PresetBankRestore.run(data: targetBankData, original: fullBankData, backupDirectory: restoreTemp, memory: failingMemory, commitSite: { _ in metadataAfterFailure = true }, progress: { _ in })
}
expect(!metadataAfterFailure && failingMemory.writes == [19], "no automatic retry or metadata commit after uncertain write")
let rejectedMemory = RestoreMemoryFixture(fullBank.presets, backup: restoreTemp)
expectThrows("incomplete restore rejected before device reads") { _ = try PresetBankRestore.run(data: presetXML, original: fullBankData, backupDirectory: restoreTemp, memory: rejectedMemory, commitSite: { _ in }, progress: { _ in }) }
expect(rejectedMemory.reads == 0 && rejectedMemory.writes.isEmpty, "invalid backup has no device effects")
let quickPair = QuickPreset(id: 0, name: "Voice", channelOne: 19, channelTwo: 21)
expect(quickPair.numbers == [19,121], "quick pair uses correct independent hardware banks")
expect(QuickPreset(id: 1, name: "One", channelOne: 50).numbers == [50], "quick channel one only")
expect(QuickPreset(id: 2, name: "Two", channelTwo: 1).numbers == [101], "quick channel two only")
expect(QuickPreset(id: 3, name: "Empty").numbers.isEmpty, "unassigned shortcut has no recall commands")
var quickLibrary = QuickPresetLibrary(); quickLibrary.shortcuts[0] = quickPair
let quickRoundTrip = try QuickPresetLibrary.decode(JSONEncoder().encode(quickLibrary))
expect(quickRoundTrip == quickLibrary, "quick assignments persist including title and both channels")
expectThrows("reject invalid quick slot") { try QuickPreset(id: 0, name: "Bad", channelOne: 51).validate() }
expectThrows("reject empty quick name") { try QuickPreset(id: 0, name: " ").validate() }
expectThrows("reject duplicate quick button IDs") { _ = try QuickPresetLibrary.decode(JSONEncoder().encode(QuickPresetLibrary(shortcuts: Array(repeating: quickPair, count: 4)))) }
let catalog = try ControlCatalog.load()
expect(catalog.controls.count == 100, "catalog count")
expect(Set(catalog.controls.map(\.id)).count == 100, "unique addresses")
for control in catalog.controls where control.kind == "slider" {
    expect(control.minimum < control.maximum, "range: \(control.name)")
    for raw in [0, 1, 10923, 32768, 65534, 65535] {
        expect(abs(control.rawValue(display: control.displayValue(raw: raw)) - raw) <= 1, "scale round-trip: \(control.name), \(raw)")
    }
    if control.channel == 1 { expect(catalog.controls.contains { $0.id == control.id + 1000 }, "channel 2: \(control.name)") }
}
var wheel = FaderWheelSteps()
expect(wheel.consume(delta: 120, precise: false) == 1, "coarse wheel event is one increment")
expect(wheel.consume(delta: -1, precise: false) == -1, "wheel down decrements")
expect(wheel.consume(delta: 3, precise: true) == 0, "tiny trackpad motion waits")
expect(wheel.consume(delta: 5, precise: true) == 1, "trackpad pixels accumulate")
expect(wheel.consume(delta: 10000, precise: true) == 8, "large trackpad event is bounded")
expect(wheel.consume(delta: 7, precise: true) == 0, "partial step retained")
expect(wheel.consume(delta: -8, precise: true) == -1, "reversing discards previous direction remainder")
_ = wheel.consume(delta: 7, precise: true)
wheel.reset()
expect(wheel.consume(delta: 1, precise: true) == 0, "new gesture clears remainder")
expect(wheel.consume(delta: .infinity, precise: true) == 0, "invalid wheel input ignored")
let keyboardGain = catalog.controls.first { $0.id == 654 }!
let normalGain = FaderKeyboardStep.adjusted(raw: 50000, direction: 1, fine: false, control: keyboardGain)
let fineGain = FaderKeyboardStep.adjusted(raw: 50000, direction: 1, fine: true, control: keyboardGain)
expect(normalGain > fineGain && fineGain > 50000, "Shift gives a finer level adjustment")
expect(abs(keyboardGain.displayValue(raw: normalGain) - keyboardGain.displayValue(raw: 50000) - 0.1) < 0.002, "level arrow changes about 0.1 dB")
expect(abs(keyboardGain.displayValue(raw: fineGain) - keyboardGain.displayValue(raw: 50000) - 0.01) < 0.002, "fine level arrow changes about 0.01 dB")
expect(FaderKeyboardStep.adjusted(raw: 65535, direction: 1, fine: false, control: keyboardGain) == 65535, "arrow respects upper limit")
expect(FaderKeyboardStep.adjusted(raw: 0, direction: -1, fine: true, control: keyboardGain) == 0, "arrow respects lower limit")
expect(FaderKeyboardStep.adjusted(raw: 30000, direction: 1, fine: false) == 30064, "right/up moves logarithmic fader positively")
expect(FaderKeyboardStep.adjusted(raw: 30000, direction: -1, fine: true) == 29996, "fine left/down moves logarithmic fader negatively")
expect(FaderKeyboardStep.adjusted(raw: 30000, direction: 0, fine: false) == 30000, "no direction has no effect")
let q = catalog.controls.first { $0.id == 120 }!
expect(!q.inverted, "EQ Q matches original display")
expect(abs(q.displayValue(raw: 0) - 0.02) < 0.00001, "Q low endpoint")
expect(abs(q.displayValue(raw: 65535) - 50) < 0.00001, "Q high endpoint")
expect(abs(q.displayValue(raw: 17694) - 0.17) < 0.01, "Q matches supplied screenshot")
let resonance = catalog.controls.first { $0.id == 535 }!
expect(abs(resonance.displayValue(raw: 26869) - 0.77) < 0.01, "resonance matches supplied screenshot")
let trim = catalog.controls.first { $0.id == 109 }!
expect(abs(trim.displayValue(raw: 36863) - 3) < 0.001, "observed +3 dB trim")
let attack = catalog.controls.first { $0.id == 306 }!
expect(abs(attack.displayValue(raw: 0) - 0.0004) < 0.0000001, "attack lower endpoint")
expect(abs(attack.displayValue(raw: 65535) - 2.35) < 0.00001, "attack upper endpoint")
let eqGain = catalog.controls.first { $0.id == 116 }!
expect(eqGain.formatted(raw: 26214).hasSuffix(" dB"), "EQ gain unit")
let valid = VPSnapshot(host: "192.0.2.100", catalogSHA256: catalog.sourceSHA256, values: [109: 36863])
let validated = try valid.validated(for: catalog)
expect(validated == [109: 36863], "valid snapshot")
for values in [[6113: 100], [9999: 100], [109: -1], [109: 65536], [:]] {
    expectThrows("invalid snapshot \(values)") {
        _ = try VPSnapshot(host: "test", catalogSHA256: catalog.sourceSHA256, values: values).validated(for: catalog)
    }
}
expectThrows("incompatible catalog") {
    _ = try VPSnapshot(host: "test", catalogSHA256: "wrong", values: [109: 0]).validated(for: catalog)
}
let restored = try JSONDecoder().decode(VPSnapshot.self, from: JSONEncoder().encode(valid))
let restoredValues = try restored.validated(for: catalog)
expect(restoredValues == [109: 36863], "snapshot persistence")
print("PASS: \(count) assertions (protocol, controller mappings, scaling, snapshot validation)")
