import SwiftUI

@main struct VP2xMacApp: App {
    @StateObject private var device = DeviceStore()
    @StateObject private var shortcuts = QuickPresetStore()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup("VP2x Control") {
            ClassicContentView(device: device)
                .frame(minWidth: 1006, minHeight: 742)
        }
        .defaultSize(width: 1006, height: 742)
        .commands {
            CommandMenu("VP2x") {
                Button("Snelle presets…") { openWindow(id: "quick-presets") }.keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Verbind") { device.connect() }.disabled(device.connected || device.connecting)
                Button("Verbreek verbinding") { device.disconnect() }.disabled(!device.connected && !device.connecting)
                Divider()
                Button("Ververs instellingen") { device.refresh() }.keyboardShortcut("r").disabled(!device.connected)
            }
        }
        Window("Snelle presets", id: "quick-presets") {
            QuickPresetsView(device: device, shortcuts: shortcuts)
        }.windowResizability(.contentSize).defaultPosition(.topTrailing)
    }
}
