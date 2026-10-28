import AppKit
import SwiftUI

/// Hosts the SwiftUI island and does two AppKit-only jobs:
/// 1. `hitTest` returns nil outside the island's current shape, so the transparent
///    part of the window never swallows clicks or drags.
/// 2. A single `.activeAlways` tracking area drives hover (works while another app
///    is frontmost, which is always the case for an accessory app).
final class IslandHostingView: NSHostingView<AnyView> {
    /// Rect of the island in this view's coordinates.
    var hitRegion: (() -> CGRect)?
    var hoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var lastInside = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let region = hitRegion?() else { return super.hitTest(point) }
        let local = superview.map { convert(point, from: $0) } ?? point
        guard region.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Only real pointer motion may *start* a hover. Synthetic enter events (sent when
    /// the viewport grows or the tracking area is rebuilt under a motionless pointer)
    /// and programmatic re-checks can only *end* one. This prevents the island from
    /// opening just because a live activity widened the notch under a parked pointer.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        evaluate(locationInWindow: event.locationInWindow, allowEnter: false)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        evaluate(locationInWindow: event.locationInWindow, allowEnter: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Trust the live pointer position rather than the event: AppKit emits a synthetic
        // exit/enter pair whenever the viewport (window) changes size.
        if let window {
            evaluate(locationInWindow: window.mouseLocationOutsideOfEventStream, allowEnter: false)
        } else {
            setInside(false)
        }
    }

    /// Re-evaluates hover without waiting for the next mouse event (used after the
    /// island changes size under a motionless pointer). Can only end a hover.
    func recheckHover() {
        guard let window else { return }
        evaluate(locationInWindow: window.mouseLocationOutsideOfEventStream, allowEnter: false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func evaluate(locationInWindow: NSPoint, allowEnter: Bool) {
        let local = convert(locationInWindow, from: nil)
        let inside = hitRegion?().contains(local) ?? bounds.contains(local)
        if inside && !allowEnter { return }
        setInside(inside)
    }

    private func setInside(_ inside: Bool) {
        guard inside != lastInside else { return }
        lastInside = inside
        hoverChanged?(inside)
    }
}
