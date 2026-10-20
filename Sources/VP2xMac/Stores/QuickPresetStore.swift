import Foundation
import Combine
import VP2xCore

@MainActor final class QuickPresetStore: ObservableObject {
    @Published private(set) var shortcuts = QuickPresetLibrary().shortcuts
    @Published var error: String?
    private let key = "QuickPresetLibrary.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            do { shortcuts = try QuickPresetLibrary.decode(data).shortcuts.sorted { $0.id < $1.id } }
            catch { self.error = "De snelknoppen konden niet worden gelezen. Stel ze opnieuw in." }
        }
    }
    func save(_ shortcut: QuickPreset) {
        do {
            try shortcut.validate()
            let updated = shortcuts.map { $0.id == shortcut.id ? shortcut : $0 }
            let data = try JSONEncoder().encode(QuickPresetLibrary(shortcuts: updated))
            _ = try QuickPresetLibrary.decode(data)
            UserDefaults.standard.set(data, forKey: key)
            shortcuts = updated
        } catch { self.error = error.localizedDescription }
    }
}
