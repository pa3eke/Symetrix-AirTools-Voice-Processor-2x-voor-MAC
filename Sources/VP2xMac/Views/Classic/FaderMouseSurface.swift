import SwiftUI
import AppKit
import VP2xCore

/// AppKit owns mouse tracking; SwiftUI remains the only owner of the value.
struct FaderMouseSurface: NSViewRepresentable {
    let enabled: Bool
    let horizontal: Bool
    let handleRect: CGRect
    let adjusted: (Int, Bool) -> Void
    let focusChanged: (Bool) -> Void
    let changed: (CGPoint) -> Void
    let ended: () -> Void
    func makeNSView(context: Context) -> FaderTrackingView { FaderTrackingView() }
    func updateNSView(_ view: FaderTrackingView, context: Context) {
        view.enabled = enabled; view.changed = changed; view.ended = ended
        view.horizontal = horizontal; view.handleRect = handleRect; view.adjusted = adjusted; view.focusChanged = focusChanged
        view.needsDisplay = true
    }
}
struct NumberMouseSurface: NSViewRepresentable {
    let enabled: Bool
    let doubleClicked: () -> Void
    func makeNSView(context: Context) -> FaderTrackingView { FaderTrackingView() }
    func updateNSView(_ view: FaderTrackingView, context: Context) {
        view.enabled = enabled; view.doubleClicked = doubleClicked
    }
}
final class FaderTrackingView: NSView {
    var enabled = false
    var changed: ((CGPoint) -> Void)?
    var ended: (() -> Void)?
    var doubleClicked: (() -> Void)?
    var horizontal = true
    var handleRect = CGRect.zero
    private var grabbedHandle = false
    private var hasDragged = false
    private var dragOrigin = CGPoint.zero
    private var handleOrigin = CGPoint.zero
    var adjusted: ((Int, Bool) -> Void)?
    var focusChanged: ((Bool) -> Void)?
    private var keyboardAdjusting = false
    private var trackingMouse = false
    private var wheelSteps = FaderWheelSteps()
    private var wheelAdjusting = false
    private var wheelEndTimer: Timer?
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseExited(with event: NSEvent) { finishWheelAdjustment() }
    override func scrollWheel(with event: NSEvent) {
        guard enabled, let adjusted else { super.scrollWheel(with: event); return }
        guard !trackingMouse, event.momentumPhase.isEmpty,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            finishWheelAdjustment(); return
        }
        if event.phase.contains(.began) { finishWheelAdjustment() }
        let delta = horizontal && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let steps = wheelSteps.consume(delta: delta, precise: event.hasPreciseScrollingDeltas)
        if steps != 0 {
            finishKeyboardAdjustment()
            if window?.firstResponder !== self { window?.makeFirstResponder(self) }
            wheelAdjusting = true
            for _ in 0..<abs(steps) { adjusted(steps > 0 ? 1 : -1, event.modifierFlags.contains(.shift)) }
        }
        wheelEndTimer?.invalidate()
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            finishWheelAdjustment()
        } else {
            let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in self?.finishWheelAdjustment() }
            wheelEndTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    private func finishWheelAdjustment() {
        wheelEndTimer?.invalidate(); wheelEndTimer = nil
        wheelSteps.reset()
        if wheelAdjusting { wheelAdjusting = false; ended?() }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { enabled && adjusted != nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool {
        guard acceptsFirstResponder else { return false }
        needsDisplay = true; focusChanged?(true); return true
    }
    override func resignFirstResponder() -> Bool {
        finishWheelAdjustment()
        finishKeyboardAdjustment()
        needsDisplay = true; focusChanged?(false); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if enabled, adjusted != nil, window?.firstResponder === self {
            NSColor.cyan.withAlphaComponent(0.9).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            ring.lineWidth = 1; ring.stroke()
        }
    }
    private func direction(_ event: NSEvent) -> Int? {
        switch event.keyCode {
        case 123: return horizontal ? -1 : nil
        case 124: return horizontal ? 1 : nil
        case 125: return horizontal ? nil : -1
        case 126: return horizontal ? nil : 1
        default: return nil
        }
    }
    override func keyDown(with event: NSEvent) {
        finishWheelAdjustment()
        if event.keyCode == 48 {
            finishKeyboardAdjustment()
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        guard enabled, let adjusted,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        if let direction = direction(event) {
            keyboardAdjusting = true
            adjusted(direction, event.modifierFlags.contains(.shift))
        } else if !(123...126).contains(event.keyCode) { super.keyDown(with: event) }
    }
    override func keyUp(with event: NSEvent) {
        if direction(event) != nil { finishKeyboardAdjustment() }
        else { super.keyUp(with: event) }
    }
    private func finishKeyboardAdjustment() {
        if keyboardAdjusting { keyboardAdjusting = false; ended?() }
    }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        if let doubleClicked {
            if event.clickCount >= 2 { doubleClicked() }
            return
        }
        finishWheelAdjustment()
        finishKeyboardAdjustment()
        trackingMouse = true; hasDragged = false
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        grabbedHandle = handleRect.contains(dragOrigin)
        handleOrigin = CGPoint(x: handleRect.midX, y: handleRect.midY)
        // Selecting the knob must not round its existing value to a mouse pixel.
        if !grabbedHandle { changed?(dragOrigin) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard trackingMouse else { return }
        hasDragged = true
        changed?(dragPoint(event))
    }
    private func dragPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return grabbedHandle ? CGPoint(x: handleOrigin.x + point.x - dragOrigin.x, y: handleOrigin.y + point.y - dragOrigin.y) : point
    }
    override func mouseUp(with event: NSEvent) {
        guard trackingMouse else { return }
        if hasDragged || !grabbedHandle { changed?(dragPoint(event)) }
        trackingMouse = false
        ended?()
    }
}
