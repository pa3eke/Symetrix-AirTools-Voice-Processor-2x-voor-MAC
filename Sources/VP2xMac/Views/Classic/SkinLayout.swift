import Foundation
import AppKit
import VP2xCore

struct SkinPanel: Decodable, Identifiable {
    let id: Int
    let name: String
    let width, height: Double
    let background: String
    let controls: [SkinControl]
}
struct SkinControl: Decodable, Identifiable {
    var id: String { name }
    let name, kind: String
    let x, y, width, height: Double
    let controller: Int?
    let off, on, handle: String
    let horizontal, inverted: Bool
    let selected: Int?
    let target: Int
    let viewer: String
    let fontSize, minimum, maximum: Double
}
@MainActor final class SkinLayout {
    static let shared = SkinLayout()
    let panels: [SkinPanel]
    private var images: [String: NSImage] = [:]
    private init() {
        if let url = VPArtwork.url("Skin.json"), let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([SkinPanel].self, from: data) {
            panels = decoded
        } else { panels = [] }
    }
    func panel(_ id: Int) -> SkinPanel? { panels.first { $0.id == id } }
    func image(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard !name.isEmpty, let url = VPArtwork.url(name), let image = NSImage(contentsOf: url) else { return nil }
        images[name] = image
        return image
    }
}
