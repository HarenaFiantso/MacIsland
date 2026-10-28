import AppKit

/// Global + local event monitors: close the island on outside clicks and on Escape.
/// Mouse monitors need no Accessibility permission. The global monitor is installed
/// only while an island is expanded to keep idle cost at zero.
@MainActor
final class EventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var coordinator: AppCoordinator?

    func start(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.handleLocal(event)
            return event
        }
    }

    func setGlobalMonitoring(_ enabled: Bool) {
        if enabled, globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.outsideClick(except: nil) }
            }
        } else if !enabled, let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handleLocal(_ event: NSEvent) {
        guard let manager = coordinator?.windowManager else { return }
        if event.type == .keyDown {
            if event.keyCode == 53 { // Escape
                manager.forEachModel { $0.send(.escape) }
            }
            return
        }
        if let controller = manager.controller(for: event.window) {
            if controller.islandContains(windowPoint: event.locationInWindow) {
                outsideClick(except: controller.model)
            } else {
                outsideClick(except: nil)
            }
        } else {
            outsideClick(except: nil)
        }
    }

    private func outsideClick(except model: IslandViewModel?) {
        coordinator?.windowManager.forEachModel { candidate in
            if candidate !== model { candidate.send(.tappedOutside) }
        }
    }
}
