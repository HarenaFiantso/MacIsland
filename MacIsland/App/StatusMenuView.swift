import SwiftUI

/// Status-bar menu (the app has no Dock icon).
struct StatusMenuView: View {
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        Button("Open Island") { AppCoordinator.shared.windowManager.openAll() }
        Button("Close Island") { AppCoordinator.shared.windowManager.closeAll() }
        Divider()
        Button("Settings…") { SettingsOpener.open() }
            .keyboardShortcut(",", modifiers: .command)
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.set($0) }
        ))
        Divider()
        Button("Quit MacIsland") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
