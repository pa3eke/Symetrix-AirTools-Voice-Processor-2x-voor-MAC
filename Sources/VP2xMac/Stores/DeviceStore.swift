import Foundation
import SwiftUI
import Combine
import VP2xCore

@MainActor final class DeviceStore: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "VP2xHost") ?? "192.168.1.100"
    @Published var connected = false
    @Published var ready = false
    @Published var connecting = false
    @Published var status = "Offline — verbind om actuele instellingen uit te lezen"
    @Published var values: [Int: Int] = [:]
    @Published var pending: [Int: Int] = [:]
    @Published var previews: [Int: Int] = [:]
    @Published var focusedControl: Int?
    let activity = DeviceActivity()
    let meters = MeterStore()
    let presets = PresetStore()
    var log: [String] { activity.entries }
    @Published var channel = 1
    @Published var section = "Ingang"
    @Published var classicPanelNames: Set<String> = [] {
        didSet { meters.select(ids: MeterPlan.visible(panels: classicPanelNames)) }
    }
    private let auxiliaryIDs = [195,196,197,1195,1196,1197,700,701,1700,1701,8602,9604,9605,6220,6240,6300,6309,7220,7240,7300,7309]
    @Published var snapshot: VPSnapshot?
    @Published var importedSnapshot: VPSnapshot?
    @Published var errorMessage: String?
    @Published var capturing = false
    @Published var refreshing = false
    let catalog: ControlCatalog
    let loadError: String?
    private let client = VPClient()
    private var worker: Task<Void, Never>?
    private var idleWait: Task<Void, Error>?
    private lazy var liveControls = LiveControlDispatcher { [weak self] id, value in
        guard let self, self.canEdit else { return }
        self.enqueue(id, value: value)
    }
    private var pendingPresets: [Int] = []
    @Published private(set) var recallingPresets = false
    private var quickRecallName: String?
    @Published var quickRecallError: String?
    private var presetSubscription: AnyCancellable?
    private var presetCapture: (channel: Int, slot: Int, name: String, location: PresetLocation)?
    private var applyingPreset = false
    private var captureRequested = false
    private var refreshRequested = false
    private var lastFullRefresh = Date.distantPast
    private var session = UUID()
    private var failed: Set<Int> = []
    let sections = ["Overzicht", "Ingang", "Filters", "De-esser & expander", "Compressor", "Equalizer", "Uitgang", "Systeem", "Presets", "Logboek"]

    init() {
        do { catalog = try ControlCatalog.load(); loadError = nil }
        catch { catalog = ControlCatalog(sourceSHA256: "", controls: []); loadError = error.localizedDescription }
        presetSubscription = presets.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        presets.failed = { [weak self] in self?.errorMessage = $0 }
        client.trace = { [weak self] entry in self?.activity.append(entry) }
        meters.diagnostics = { [weak self] entry in self?.activity.append(entry) }
    }
    var visibleControls: [VPControl] {
        catalog.controls.filter { $0.section == section && ($0.channel == channel || $0.channel == 0) }
    }
    var canEdit: Bool { connected && ready && !capturing && !applyingPreset && !presets.busy && !recallingPresets }
    func connect() {
        guard !presets.busy else { return }
        disconnect()
        do { try client.connect(host: host.trimmingCharacters(in: .whitespaces)) }
        catch { errorMessage = error.localizedDescription; return }
        UserDefaults.standard.set(host, forKey: "VP2xHost")
        connecting = true; status = "VP2x uitlezen…"
        let token = session
        worker = Task {
            do {
                let first: Int
                do { first = try await client.read(109) }
                catch VPClient.Failure.timeout { first = try await client.read(109) }
                guard session == token, !Task.isCancelled else { return }
                values[109] = first; connected = true; connecting = false
                presets.load(host: host.trimmingCharacters(in: .whitespaces))
                refreshRequested = true
                while !Task.isCancelled, session == token {
                    if presets.busy { try await Task.sleep(for: .milliseconds(200)); continue }
                    if let preset = pendingPresets.first {
                        pendingPresets.removeFirst()
                        try await client.recall(preset)
                        guard session == token else { return }
                        values.removeAll(); ready = false; refreshRequested = true
                        status = "Preset \(preset) geladen; instellingen uitlezen…"
                        if !pendingPresets.isEmpty { continue }
                    }
                    if let id = pending.keys.sorted().first, let value = pending[id] {
                        // Keep the desired value visible throughout ACK/readback.
                        // A newer click on this controller must remain queued.
                        let actual = try await client.write(id, value: value)
                        guard session == token else { return }
                        values[id] = actual
                        if pending[id] == value { pending.removeValue(forKey: id) }
                        status = "Wijziging bevestigd door VP2x"
                        continue
                    }
                    if applyingPreset, pending.isEmpty {
                        applyingPreset = false; refreshRequested = true
                    }
                    let full = refreshRequested || captureRequested || presetCapture != nil || Date().timeIntervalSince(lastFullRefresh) > 15
                    if full { refreshing = true }
                    let controls = full ? catalog.controls : catalog.controls.filter {
                        (classicPanelNames.isEmpty ? ($0.channel == channel || $0.channel == 0) : true) && ($0.section == section || classicPanelNames.contains($0.sourcePanel) || $0.kind == "meter")
                    }
                    for control in controls where !failed.contains(control.id) && (!ready || !MeterPlan.all.contains(control.id)) {
                        if Task.isCancelled || session != token { return }
                        if !pending.isEmpty || !pendingPresets.isEmpty { break }
                        do {
                            let value = try await client.read(control.id)
                            guard session == token else { return }
                            if values[control.id] != value { values[control.id] = value }
                        } catch VPClient.Failure.rejected {
                            failed.insert(control.id)
                        }
                        try await Task.sleep(for: .milliseconds(12))
                    }
                    if pending.isEmpty, pendingPresets.isEmpty {
                        for id in auxiliaryIDs where !failed.contains(id) && (!ready || !MeterPlan.all.contains(id)) {
                            if Task.isCancelled || session != token { return }
                            if !pending.isEmpty { break }
                            do {
                                let value = try await client.read(id)
                                guard session == token else { return }
                                if values[id] != value { values[id] = value }
                                if id == 700 || id == 1700 { presets.observeIndicator(channel: id == 700 ? 1 : 2, raw: value) }
                            } catch VPClient.Failure.rejected { failed.insert(id) }
                        }
                    }
                    guard session == token else { return }
                    refreshing = false
                    if full, pending.isEmpty, pendingPresets.isEmpty {
                        if !ready {
                            meters.start(client: client, ids: MeterPlan.visible(panels: classicPanelNames))
                        }
                        lastFullRefresh = Date(); refreshRequested = false; ready = true
                        recallingPresets = false; quickRecallName = nil
                        if captureRequested {
                            let writable = catalog.controls.filter(\.isWritable).filter { !failed.contains($0.id) }
                            guard writable.allSatisfy({ values[$0.id] != nil }) else { throw VPClient.Failure.rejected }
                            snapshot = VPSnapshot(host: host, catalogSHA256: catalog.sourceSHA256,
                                values: Dictionary(uniqueKeysWithValues: writable.map { ($0.id, values[$0.id]!) }))
                            captureRequested = false; capturing = false
                        }
                        if let capture = presetCapture {
                            let number = try PresetArchive.number(channel: capture.channel, slot: capture.slot)
                            let template = presets.hardware.first { $0.channel == capture.channel && !$0.isEmpty }
                            let permitted = Set(catalog.controls.filter { $0.channel == capture.channel && $0.isWritable }.map(\.id))
                                .union(capture.channel == 1 ? [195,196,197] : [1195,1196,1197])
                            let ids = template.map { Set($0.values.keys).intersection(permitted) } ?? permitted
                            guard !ids.isEmpty, ids.allSatisfy({ values[$0] != nil && !failed.contains($0) }) else { throw VPClient.Failure.rejected }
                            let captured = ChannelPreset(number: number, name: capture.name,
                                values: Dictionary(uniqueKeysWithValues: ids.map { ($0, values[$0]!) }))
                            do {
                                if capture.location == .hardware { presets.saveHardware(captured, host: host) }
                                else { try presets.save(captured) }
                            }
                            catch { errorMessage = error.localizedDescription }
                            presetCapture = nil; capturing = false
                        }
                    }
                    status = "Verbonden met \(host) · \(values.count) regelaars uitgelezen" + (failed.isEmpty ? "" : " · \(failed.count) niet ondersteund")
                    if !pending.isEmpty || !pendingPresets.isEmpty { continue }
                    // A new control value cancels only this idle pause, never a
                    // socket request or its ACK/readback verification.
                    let pause = Task { try await Task.sleep(for: .milliseconds(650)) }
                    idleWait = pause
                    _ = try? await pause.value
                    if session == token { idleWait = nil }
                }
            } catch {
                guard session == token, !Task.isCancelled else { return }
                if let quickRecallName {
                    quickRecallError = "Snelkeuze ‘\(quickRecallName)’ is niet volledig bevestigd. Een kanaal kan al zijn omgeschakeld. \(error.localizedDescription)"
                } else { errorMessage = error.localizedDescription }
                disconnect()
                status = "Verbinding gestopt: \(error.localizedDescription)"
            }
        }
    }
    func disconnect() {
        guard !presets.busy else { return }
        idleWait?.cancel(); idleWait = nil; liveControls.cancelAll()
        session = UUID(); worker?.cancel(); worker = nil; client.disconnect(); meters.stop(); presets.cancelLoad()
        connected = false; ready = false; connecting = false; capturing = false; refreshing = false
        captureRequested = false; refreshRequested = false; pendingPresets = []; recallingPresets = false; quickRecallName = nil; presetCapture = nil; applyingPreset = false
        values.removeAll(); pending.removeAll(); previews.removeAll(); focusedControl = nil; failed.removeAll()
        snapshot = nil; importedSnapshot = nil; status = "Offline"
    }
    func write(_ control: VPControl, value: Int) {
        guard canEdit, control.isWritable, values[control.id] != nil else { return }
        liveControls.finish(control.id, value: value)
    }
    private func canWriteRaw(_ id: Int) -> Bool {
        let permitted = catalog.controls.contains { $0.id == id && $0.isWritable } || [195,196,197,1195,1196,1197,8602].contains(id)
        return canEdit && permitted && values[id] != nil
    }
    func writeLiveRaw(_ id: Int, value: Int) {
        guard canWriteRaw(id) else { return }
        liveControls.submit(id, value: value)
    }
    func writeRaw(_ id: Int, value: Int) {
        guard canWriteRaw(id) else { return }
        liveControls.finish(id, value: value)
    }
    private func enqueue(_ id: Int, value: Int) {
        pending[id] = min(65535, max(0, value))
        wakeWorker()
    }
    private func wakeWorker() { idleWait?.cancel(); idleWait = nil }
    func refresh() { guard connected else { return }; refreshRequested = true; wakeWorker() }
    func capture() { guard canEdit else { return }; capturing = true; captureRequested = true; wakeWorker() }
    func recall(_ number: Int) {
        guard canEdit, pending.isEmpty, (1...50).contains(number) || (101...150).contains(number) else { return }
        pendingPresets = [number]; recallingPresets = true; wakeWorker()
    }
    func canActivate(_ shortcut: QuickPreset) -> Bool {
        guard canEdit, pending.isEmpty, !shortcut.numbers.isEmpty, presets.loadedHost == host else { return false }
        return shortcut.numbers.allSatisfy { number in presets.hardware.contains { $0.number == number && !$0.isEmpty } }
    }
    func activate(_ shortcut: QuickPreset) {
        guard canActivate(shortcut), (try? shortcut.validate()) != nil else { return }
        quickRecallError = nil; pendingPresets = shortcut.numbers; recallingPresets = true; quickRecallName = shortcut.name
        status = "Snelkeuze ‘\(shortcut.name)’ laden…"; wakeWorker()
    }
    func storePreset(channel: Int, slot: Int, name: String, location: PresetLocation) {
        guard canEdit, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 64 else { return }
        presetCapture = (channel, slot, name.trimmingCharacters(in: .whitespacesAndNewlines), location)
        capturing = true; refreshRequested = true; wakeWorker()
        status = "Kanaal \(channel) uitlezen voor preset…"
    }
    func recallPreset(_ preset: ChannelPreset, from location: PresetLocation) {
        guard canEdit, !preset.isEmpty else { return }
        if location == .hardware { recall(preset.number); return }
        let allowed = Set(catalog.controls.filter { $0.channel == preset.channel && $0.isWritable }.map(\.id))
            .union(preset.channel == 1 ? [195,196,197] : [1195,1196,1197])
        let writable = preset.values.filter { allowed.contains($0.key) }
        guard !writable.isEmpty, writable.count == preset.values.filter({ ![700,701,1700,1701].contains($0.key) }).count,
              writable.keys.allSatisfy({ values[$0] != nil && !failed.contains($0) }) else {
            errorMessage = "Deze preset bevat niet-ondersteunde regelaars; er is niets toegepast."; return
        }
        pending.merge(writable) { _, new in new }
        applyingPreset = true; wakeWorker(); status = "Mac-preset \(preset.slot) toepassen op kanaal \(preset.channel)…"
    }
    func stageSnapshot(_ data: Data) {
        do {
            let snapshot = try JSONDecoder().decode(VPSnapshot.self, from: data)
            _ = try snapshot.validated(for: catalog)
            importedSnapshot = snapshot
        } catch { errorMessage = "Ongeldig snapshotbestand: \(error.localizedDescription)" }
    }
    func applySnapshot() {
        guard canEdit, let importedSnapshot else { return }
        do { pending.merge(try importedSnapshot.validated(for: catalog)) { _, new in new }; self.importedSnapshot = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
