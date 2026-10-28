import SwiftUI

/// SwiftUI app shell. The island itself is *not* a SwiftUI scene: it lives in
/// AppKit `NSPanel`s managed by `NotchWindowManager` (see Core/). SwiftUI only
/// provides the Settings window and the status-bar menu.
@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Only a status item: the island lives in AppKit panels, settings in their own
        // NSWindow (`SettingsWindowController`). A SwiftUI `Settings` scene is avoided on
        // purpose — in an accessory app it opened itself at launch.
        MenuBarExtra("MacIsland", systemImage: "rectangle.topthird.inset.filled") {
            AppCoordinator.shared.inject(StatusMenuView())
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already hides the Dock icon; make it explicit for clarity.
        NSApp.setActivationPolicy(.accessory)
        AppCoordinator.shared.start()
        Log.app.notice("MacIsland started (\(Bundle.main.shortVersion, privacy: .public))")
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        AppCoordinator.shared.windowManager.screensChanged()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Log.app.notice("reopen requested (visible windows: \(flag))")
        SettingsOpener.open()
        return true
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}

/// Opens the settings window from anywhere (status menu, island gear, reopen event).
enum SettingsOpener {
    @MainActor static func open() {
        SettingsWindowController.shared.show()
    }
}
