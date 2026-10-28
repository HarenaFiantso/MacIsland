import AppKit
import SwiftUI

/// Hosts the SwiftUI settings in a regular AppKit window. For an accessory app this
/// is more predictable than the SwiftUI `Settings` scene (which can open at launch
/// and does not activate the app).
///
/// The window is full-size-content with a transparent, title-less title bar, so the
/// sidebar runs the whole height behind the traffic lights, like System Settings.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private static let defaultSize = NSSize(width: 800, height: 580)
    private static let autosaveName = "MacIsland.Settings"

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacIsland Settings"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 740, height: 540)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if window.contentViewController == nil {
            let host = NSHostingController(rootView: AppCoordinator.shared.inject(SettingsView()))
            host.sizingOptions = [] // the window keeps its own size; SwiftUI only enforces the minimum
            window.contentViewController = host // resizes the window to the view's fitting size
            if !window.setFrameUsingName(Self.autosaveName) {
                window.setContentSize(Self.defaultSize)
                window.center()
            }
            // Only now: with the autosave name set earlier, the resize above would have
            // been saved at once and "restored" instead of the default size.
            window.setFrameAutosaveName(Self.autosaveName)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
