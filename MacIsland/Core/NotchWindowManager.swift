import AppKit
import SwiftUI
import IslandCore

/// Creates one `IslandWindowController` per eligible screen and keeps them in sync
/// with display changes and preferences.
@MainActor
final class NotchWindowManager {
    private unowned let coordinator: AppCoordinator
    private var controllers: [CGDirectDisplayID: IslandWindowController] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        reconcileScreens()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.controllers.values.forEach { $0.ensureVisible() } }
        })
    }

    /// Display changes come in bursts (resolution, arrangement, sleep); coalesce them.
    func screensChanged() {
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reconcileScreens()
        }
    }

    func reconcileScreens() {
        let preferences = coordinator.preferences
        var seen = Set<CGDirectDisplayID>()
        for screen in ScreenDetector.eligibleScreens(preferences: preferences) {
            let geometry = ScreenDetector.geometry(for: screen, preferences: preferences)
            seen.insert(geometry.displayID)
            if let existing = controllers[geometry.displayID] {
                existing.update(geometry: geometry)
            } else {
                let controller = IslandWindowController(geometry: geometry, coordinator: coordinator, manager: self)
                controllers[geometry.displayID] = controller
                Log.window.notice("island created on display \(geometry.displayID) notch=\(geometry.notchSize.width)x\(geometry.notchSize.height) physical=\(geometry.hasPhysicalNotch)")
            }
        }
        for (id, controller) in controllers where !seen.contains(id) {
            controller.tearDown()
            controllers[id] = nil
            Log.window.notice("island removed from display \(id)")
        }
        expandedStateChanged()
    }

    func preferencesChanged(_ key: String) {
        if key.hasPrefix("screen.") || key.hasPrefix("notch.") || key == "reset" {
            reconcileScreens()
        }
        for controller in controllers.values {
            controller.model.syncBehavior()
            controller.refreshFrame()
        }
    }

    func expandedStateChanged() {
        coordinator.eventMonitor.setGlobalMonitoring(controllers.values.contains { $0.model.mode == .expanded })
    }

    func forEachModel(_ body: (IslandViewModel) -> Void) {
        controllers.values.forEach { body($0.model) }
    }

    func controller(for window: NSWindow?) -> IslandWindowController? {
        guard let window else { return nil }
        return controllers.values.first { $0.panel === window }
    }

    var isAnyIslandExpanded: Bool {
        controllers.values.contains { $0.model.mode == .expanded }
    }

    func openAll(tab: IslandTab? = nil) {
        forEachModel { $0.send(.open(tab)) }
    }

    func closeAll() {
        forEachModel { $0.send(.close) }
    }

    func toggleAll() {
        if isAnyIslandExpanded { closeAll() } else { openAll() }
    }
}

/// Owns the panel + hosting view for one screen.
///
/// The SwiftUI hosting view keeps a *constant* size (the full expanded canvas). The
/// panel is only a viewport over it: when the island is idle the panel shrinks to the
/// notch, and the hosting view is offset so the island stays glued to the notch.
/// Resizing an `NSHostingView` that is the window's content view triggers an AppKit
/// layout-cycle exception on macOS 14+, hence this indirection.
@MainActor
final class IslandWindowController {
    let model: IslandViewModel
    let panel: IslandPanel
    let hostingView: IslandHostingView
    private let containerView = NSView()
    private(set) var footprint: IslandFootprint = .full
    private var isTornDown = false

    init(geometry: NotchGeometry, coordinator: AppCoordinator, manager: NotchWindowManager) {
        model = IslandViewModel(
            geometry: geometry,
            preferences: coordinator.preferences,
            activities: coordinator.activities,
            media: coordinator.media
        )

        hostingView = IslandHostingView(rootView: coordinator.inject(IslandRootView(model: model)))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear
        containerView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)

        let full = geometry.topCenteredFrame(size: model.metrics.windowSize)
        panel = IslandPanel(contentRect: full)
        containerView.frame = NSRect(origin: .zero, size: full.size)
        hostingView.frame = NSRect(origin: .zero, size: full.size)
        panel.contentView = containerView

        hostingView.hitRegion = { [weak self] in self?.islandRectInView() ?? .zero }
        hostingView.hoverChanged = { [weak model] inside in model?.send(.hoverChanged(inside)) }
        model.footprintHandler = { [weak self] footprint in self?.apply(footprint: footprint) }
        model.hoverRecheck = { [weak hostingView] in hostingView?.recheckHover() }
        model.onModeChanged = { [weak manager] _ in manager?.expandedStateChanged() }

        panel.orderFrontRegardless()
        // Start small: the window only covers the notch until something needs more room.
        apply(footprint: .collapsed, force: true)
    }

    // MARK: Frames

    private var fullFrame: NSRect {
        model.geometry.topCenteredFrame(size: model.metrics.windowSize)
    }

    private var collapsedFrame: NSRect {
        model.geometry.topCenteredFrame(size: model.metrics.collapsed.totalSize)
    }

    func apply(footprint: IslandFootprint, force: Bool = false) {
        guard !isTornDown else { return }
        let full = fullFrame
        let target = footprint == .full ? full : collapsedFrame
        guard force || panel.frame != target || hostingView.frame.size != full.size else {
            self.footprint = footprint
            return
        }
        self.footprint = footprint
        // Canvas keeps the full size; only its origin moves so that (0, top) of the
        // canvas keeps matching the screen's top-centre regardless of the viewport.
        let origin = NSPoint(x: full.minX - target.minX, y: full.minY - target.minY)
        panel.setFrame(target, display: false)
        hostingView.frame = NSRect(origin: origin, size: full.size)
        Log.window.debug("footprint \(String(describing: footprint), privacy: .public) window=\(NSStringFromRect(target), privacy: .public) canvas=\(NSStringFromRect(self.hostingView.frame), privacy: .public)")
    }

    /// Re-applies the current footprint (after a geometry or preference change).
    func refreshFrame() {
        apply(footprint: footprint, force: true)
    }

    func update(geometry: NotchGeometry) {
        model.updateGeometry(geometry)
        refreshFrame()
        ensureVisible()
    }

    func ensureVisible() {
        guard !isTornDown else { return }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func tearDown() {
        isTornDown = true
        model.tearDown()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: Hit testing

    func islandRectInView() -> CGRect {
        model.targetLayout.frame(inContainerOfSize: hostingView.bounds.size, flipped: hostingView.isFlipped)
    }

    func islandContains(windowPoint: NSPoint) -> Bool {
        islandRectInView().contains(hostingView.convert(windowPoint, from: nil))
    }
}
