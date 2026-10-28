import SwiftUI
import Observation
import IslandCore

enum IslandFootprint: Equatable {
    /// Window large enough for the expanded panel.
    case full
    /// Window shrunk to the collapsed notch so it cannot intercept anything else.
    case collapsed
}

/// One island per screen. Wraps the pure `IslandStateMachine`, owns its timers,
/// derives the geometry the views need and talks to the window controller through
/// closures (footprint, hover re-check, mode change).
@MainActor
@Observable
final class IslandViewModel: Identifiable {
    let id: CGDirectDisplayID
    private(set) var geometry: NotchGeometry
    private(set) var machine: IslandStateMachine
    private(set) var selectedTab: IslandTab = .home
    var isDropTargeted = false

    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored let activities: LiveActivityCenter
    @ObservationIgnored let media: MediaService

    @ObservationIgnored var footprintHandler: ((IslandFootprint) -> Void)?
    @ObservationIgnored var hoverRecheck: (() -> Void)?
    @ObservationIgnored var onModeChanged: ((IslandMode) -> Void)?

    @ObservationIgnored private var hoverOpenTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var shrinkTask: Task<Void, Never>?
    @ObservationIgnored private var activityObserver: UUID?

    init(geometry: NotchGeometry, preferences: Preferences, activities: LiveActivityCenter, media: MediaService) {
        self.id = geometry.displayID
        self.geometry = geometry
        self.preferences = preferences
        self.activities = activities
        self.media = media
        self.machine = IslandStateMachine(behavior: Self.behavior(from: preferences))
        activityObserver = activities.addObserver { [weak self] phase, activity in
            self?.activityChanged(phase, activity)
        }
    }

    func tearDown() {
        hoverOpenTask?.cancel()
        closeTask?.cancel()
        shrinkTask?.cancel()
        if let activityObserver { activities.removeObserver(activityObserver) }
    }

    // MARK: Derived state

    var mode: IslandMode { machine.mode }
    var isHovering: Bool { machine.isHovering }
    var isDragging: Bool { machine.isDragging }
    var animationSpeed: Double { preferences.animationSpeed }

    var metrics: IslandMetrics {
        IslandMetrics(notchSize: geometry.notchSize, panelSize: preferences.panelSize)
    }

    var currentActivity: LiveActivity? { activities.current }

    /// True when the peek state should expose the now-playing wings.
    var showsNowPlayingPeek: Bool {
        preferences.mediaEnabled && media.track != nil && media.playback.isPlaying
    }

    /// Layout while collapsed: the notch, or the notch + live-activity wings.
    var restingLayout: IslandLayout {
        if let activity = currentActivity {
            return metrics.liveActivity(wing: activity.kind.wingWidth, extraHeight: activity.kind.extraHeight)
        }
        return metrics.collapsed
    }

    /// The layout the island is animating towards.
    var targetLayout: IslandLayout {
        switch mode {
        case .expanded:
            return metrics.expanded
        case .peek:
            if currentActivity != nil { return metrics.peek(from: restingLayout) }
            if showsNowPlayingPeek {
                return metrics.peek(from: metrics.liveActivity(wing: LiveActivityKind.nowPlaying.wingWidth))
            }
            return metrics.peek(from: metrics.collapsed)
        case .collapsed:
            return restingLayout
        }
    }

    /// What the collapsed/peek wings should show.
    var wingsContent: WingsContent {
        if let activity = currentActivity { return .activity(activity) }
        if mode == .peek && showsNowPlayingPeek { return .nowPlaying }
        return .none
    }

    enum WingsContent: Equatable {
        case none
        case nowPlaying
        case activity(LiveActivity)

        var identity: String {
            switch self {
            case .none: return "none"
            case .nowPlaying: return "nowPlaying"
            case .activity(let a): return "activity-\(a.id.uuidString)"
            }
        }
    }

    // MARK: Events

    func send(_ event: IslandEvent) {
        var next = machine
        let effects = next.handle(event)
        let oldMode = machine.mode
        let modeChanged = next.mode != oldMode

        if modeChanged && next.mode != .collapsed {
            // Grow the window *before* the animation so nothing gets clipped.
            footprintHandler?(.full)
            shrinkTask?.cancel()
        }

        if modeChanged {
            let spec = IslandMotion.spec(for: next.mode)
            withAnimation(IslandMotion.animation(spec, speed: animationSpeed)) {
                machine = next
            }
            Log.island.debug("island \(self.id) \(oldMode.rawValue, privacy: .public) -> \(next.mode.rawValue, privacy: .public) via \(String(describing: event), privacy: .public)")
        } else {
            machine = next
        }

        apply(effects)

        if modeChanged {
            onModeChanged?(next.mode)
            if next.mode == .collapsed { scheduleShrinkIfIdle() }
            hoverRecheck?()
        }
    }

    func select(_ tab: IslandTab) {
        guard tab != selectedTab else { return }
        withAnimation(IslandMotion.micro(speed: animationSpeed)) {
            selectedTab = tab
        }
    }

    /// Tap on the island background (not on a control).
    func backgroundTapped() {
        if mode != .expanded { send(.tapped) }
    }

    /// Tap on the expanded header band (toggles closed).
    func headerTapped() {
        send(.tapped)
    }

    func syncBehavior() {
        send(.behaviorChanged(Self.behavior(from: preferences)))
    }

    func updateGeometry(_ newGeometry: NotchGeometry) {
        guard newGeometry != geometry else { return }
        geometry = newGeometry
    }

    private static func behavior(from preferences: Preferences) -> IslandBehavior {
        IslandBehavior(
            openOnHover: preferences.openOnHover,
            peekOnHover: preferences.peekOnHover,
            shelfEnabled: preferences.shelfEnabled
        )
    }

    // MARK: Effects

    private func apply(_ effects: [IslandEffect]) {
        for effect in effects {
            switch effect {
            case .scheduleHoverOpen:
                hoverOpenTask?.cancel()
                let delay = preferences.hoverOpenDelay
                hoverOpenTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.send(.hoverOpenTimerFired)
                }
            case .cancelHoverOpen:
                hoverOpenTask?.cancel()
                hoverOpenTask = nil
            case .scheduleClose(let kind):
                closeTask?.cancel()
                let delay = kind == .afterDrop ? max(preferences.closeDelay, 1.2) : preferences.closeDelay
                closeTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.send(.closeTimerFired)
                }
            case .cancelClose:
                closeTask?.cancel()
                closeTask = nil
            case .selectTab(let tab):
                select(tab)
            }
        }
    }

    private func activityChanged(_ phase: LiveActivityCenter.Phase, _ activity: LiveActivity?) {
        switch phase {
        case .willChange:
            if activity != nil {
                footprintHandler?(.full)
                shrinkTask?.cancel()
            }
        case .didChange:
            if activity == nil { scheduleShrinkIfIdle() }
            hoverRecheck?()
        }
    }

    private func scheduleShrinkIfIdle() {
        shrinkTask?.cancel()
        shrinkTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            guard mode == .collapsed, currentActivity == nil else { return }
            footprintHandler?(.collapsed)
        }
    }
}
