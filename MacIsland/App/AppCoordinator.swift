import AppKit
import Combine
import SwiftUI
import IslandCore

/// Composition root: owns every service and wires them together.
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    let preferences = Preferences.shared
    let activities = LiveActivityCenter()
    let media = MediaService()
    let shelf = ShelfStore()
    let calendar = CalendarService()
    let battery = BatteryService()
    let volume = AudioVolumeService()
    let timer = TimerModel()
    let launchAtLogin = LaunchAtLoginService()
    let eventMonitor = EventMonitor()
    private(set) lazy var windowManager = NotchWindowManager(coordinator: self)
    #if DEBUG
    private lazy var debugCommands = DebugCommandService(coordinator: self)
    #endif

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private let launchDate = Date()

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        activities.animationSpeed = { [preferences] in preferences.animationSpeed }
        media.preferredPlayer = { [preferences] in preferences.preferredPlayer }
        wireLiveActivities()

        shelf.load()
        media.start()
        battery.start()
        volume.start()
        calendar.start()
        windowManager.start()
        eventMonitor.start(coordinator: self)
        #if DEBUG
        debugCommands.start()
        #endif

        preferences.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in self?.preferencesChanged(key) }
            .store(in: &cancellables)
    }

    /// Attaches every shared model to a view hierarchy.
    func inject<V: View>(_ view: V) -> AnyView {
        AnyView(
            view
                .environmentObject(preferences)
                .environment(media)
                .environment(shelf)
                .environment(calendar)
                .environment(battery)
                .environment(volume)
                .environment(timer)
                .environment(activities)
                .environment(launchAtLogin)
        )
    }

    // MARK: Live activity wiring

    private func wireLiveActivities() {
        media.onTrackChanged = { [weak self] track in
            guard let self, preferences.mediaEnabled, preferences.nowPlayingActivityEnabled else { return }
            // Don't announce what was already playing when the app launches.
            guard Date().timeIntervalSince(launchDate) > 3 else { return }
            activities.present(LiveActivity(
                kind: .nowPlaying,
                duration: preferences.nowPlayingActivityDuration,
                payload: .nowPlaying(trackID: track.id)
            ))
        }

        battery.onChange = { [weak self] new, old in
            guard let self, preferences.batteryEnabled, preferences.batteryActivityEnabled, new.hasBattery else { return }
            let payload = LiveActivity.Payload.battery(level: new.level, charging: new.isCharging, pluggedIn: new.isPluggedIn)
            if new.isPluggedIn != old.isPluggedIn {
                activities.present(LiveActivity(kind: new.isPluggedIn ? .charging : .battery,
                                                duration: preferences.liveActivityDuration + 1, payload: payload))
            } else if new.isPluggedIn, new.isCharged, !old.isCharged {
                activities.present(LiveActivity(kind: .charging, duration: preferences.liveActivityDuration + 1, payload: payload))
            } else if !new.isPluggedIn, crossedDown(old.level, new.level, thresholds: [20, 10, 5]) {
                activities.present(LiveActivity(kind: .lowBattery, duration: preferences.liveActivityDuration + 2, payload: payload))
            }
        }

        volume.onChange = { [weak self] snapshot in
            guard let self, preferences.volumeActivityEnabled else { return }
            activities.present(LiveActivity(
                kind: .volume,
                duration: preferences.liveActivityDuration,
                payload: .volume(level: snapshot.volume, muted: snapshot.isMuted)
            ))
        }

        timer.onPhaseChanged = { [weak self] phase in
            guard let self else { return }
            switch phase {
            case .running, .paused:
                guard preferences.timerActivityEnabled else { return }
                activities.present(LiveActivity(kind: .timer, isSticky: true, duration: nil, payload: .none))
            case .idle:
                activities.dismissSticky(kind: .timer)
            case .finished:
                activities.dismissSticky(kind: .timer)
                activities.present(LiveActivity(kind: .timerFinished, duration: 4, payload: .none))
            }
        }

        shelf.onItemsAdded = { [weak self] count in
            guard let self, preferences.shelfActivityEnabled, count > 0 else { return }
            activities.present(LiveActivity(kind: .shelfDrop, duration: preferences.liveActivityDuration, payload: .count(count)))
        }
    }

    private func crossedDown(_ old: Int, _ new: Int, thresholds: [Int]) -> Bool {
        thresholds.contains { new <= $0 && old > $0 }
    }

    private func preferencesChanged(_ key: String) {
        windowManager.preferencesChanged(key)
    }
}
