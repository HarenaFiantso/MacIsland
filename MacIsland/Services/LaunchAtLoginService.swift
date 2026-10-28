import Foundation
import ServiceManagement
import Observation

/// Login item registration through `SMAppService` (macOS 13+). Works for the built
/// bundle; the user can always flip it in System Settings › General › Login Items.
@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var requiresApproval = SMAppService.mainApp.status == .requiresApproval
    private(set) var lastError: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Log.system.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
