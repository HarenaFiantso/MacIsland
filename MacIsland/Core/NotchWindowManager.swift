import AppKit
import SwiftUI
import IslandCore

/// Creates one `IslandWindowController` per eligible screen and keeps them in sync
/// with display changes, Space changes, screen lock and preferences.
@MainActor
final class NotchWindowManager {
    private unowned let coordinator: AppCoordinator
    private var controllers: [CGDirectDisplayID: IslandWindowController] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// True while the screen is locked or the screen saver runs: the panels are
    /// ordered out so nothing of ours is drawn over the lock screen.
    private(set) var isHidden = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        reconcileScreens()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.activeSpaceChanged() }
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

    /// The panels live in their own Space, so a desktop switch leaves them in place.
    /// The pointer, however, may now rest elsewhere: re-evaluate hover (it can only
    /// end one) so an island opened by hover does not stay open on the new desktop.
    private func activeSpaceChanged() {
        for controller in controllers.values {
            controller.ensureVisible()
            controller.hostingView.recheckHover()
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
                if isHidden { controller.setHidden(true) }
                Log.window.notice("island created on display \(geometry.displayID) notch=\(geometry.notchSize.width)x\(geometry.notchSize.height) physical=\(geometry.hasPhysicalNotch) privateSpace=\(IslandSpace.shared.isAvailable)")
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

    /// Hides every island (screen locked / screen saver) or brings them back.
    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden { closeAll() }
        controllers.values.forEach { $0.setHidden(hidden) }
        Log.window.notice("islands \(hidden ? "hidden" : "shown", privacy: .public)")
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

    /// One line per panel: window number, Space membership, visibility (debug dump).
    func spaceDiagnostics() -> [String] {
        controllers.values.map { controller in
            let number = controller.panel.windowNumber
            let spaces = IslandSpace.shared.spaces(containing: number).map { "\($0)" } ?? "unknown"
            return "window \(number) display \(controller.model.id) spaces=\(spaces) private=\(IslandSpace.shared.currentSpaceID) visible=\(controller.panel.isVisible) onActiveSpace=\(controller.panel.isOnActiveSpace)"
        }
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
    private var isHidden = false

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
        panel = IslandPanel(contentRect: full, usesPrivateSpace: IslandSpace.shared.isAvailable)
        containerView.frame = NSRect(origin: .zero, size: full.size)
        hostingView.frame = NSRect(origin: .zero, size: full.size)
        panel.contentView = containerView

        hostingView.hitRegion = { [weak self] in self?.islandRectInView() ?? .zero }
        hostingView.hoverChanged = { [weak model] inside in model?.send(.hoverChanged(inside)) }
        model.footprintHandler = { [weak self] footprint in self?.apply(footprint: footprint) }
        model.hoverRecheck = { [weak hostingView] in hostingView?.recheckHover() }
        model.onModeChanged = { [weak manager] _ in manager?.expandedStateChanged() }

        panel.orderFrontRegardless()
        IslandSpace.shared.attach(panel)
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

    /// Orders the panel back in if needed and re-asserts its private-Space membership
    /// (ordering a window in puts it back into the active user Space).
    func ensureVisible() {
        guard !isTornDown, !isHidden else { return }
        if !panel.isVisible { panel.orderFrontRegardless() }
        IslandSpace.shared.attach(panel)
    }

    func setHidden(_ hidden: Bool) {
        guard !isTornDown, hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            panel.orderOut(nil)
        } else {
            ensureVisible()
        }
    }

    func tearDown() {
        isTornDown = true
        model.tearDown()
        IslandSpace.shared.detach(panel)
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
