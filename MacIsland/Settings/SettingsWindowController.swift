import AppKit
import SwiftUI

/// Hosts the SwiftUI settings in a regular AppKit window. For an accessory app this
/// is more predictable than the SwiftUI `Settings` scene (which can open at launch
/// and does not activate the app).
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacIsland Settings"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if window.contentViewController == nil {
            let host = NSHostingController(rootView: AppCoordinator.shared.inject(SettingsView()))
            window.contentViewController = host
            window.setContentSize(host.view.fittingSize == .zero ? NSSize(width: 540, height: 500) : host.view.fittingSize)
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
