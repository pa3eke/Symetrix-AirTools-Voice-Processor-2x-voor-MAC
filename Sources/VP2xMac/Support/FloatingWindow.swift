import SwiftUI
import AppKit

/// Only the utility scene's own window is changed.
struct FloatingWindow: NSViewRepresentable {
    var enabled: Bool
    final class Anchor: NSView {
        var floating = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() { window?.level = floating ? .floating : .normal }
    }
    func makeNSView(context: Context) -> Anchor { let view = Anchor(); view.floating = enabled; return view }
    func updateNSView(_ view: Anchor, context: Context) { view.floating = enabled; view.apply() }
}
