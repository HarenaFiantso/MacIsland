import AppKit

/// Borderless, non-activating, transparent panel that floats above the menu bar.
///
/// Why these flags:
/// - `.nonactivatingPanel`: clicking the island never steals focus from the front app.
/// - level `mainMenu + 3`: above the menu bar (where the notch lives) but below menus/alerts.
/// - `.canJoinAllSpaces` + `.fullScreenAuxiliary`: visible on every Space, including
///   full-screen apps (the island then floats over the app, as NotchNook does).
/// - `.stationary` + `.ignoresCycle`: untouched by Mission Control / Exposé and ⌘`.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        tabbingMode = .disallowed
    }

    // Needed so text fields (timer) can take keyboard focus when clicked.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit normally keeps windows below the menu bar. The island *is* the notch,
    /// so it must be allowed to sit over the menu-bar band.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
