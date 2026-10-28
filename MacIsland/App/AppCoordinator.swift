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
    let screenState = ScreenStateService()
    private(set) lazy var sound = SoundService(preferences: preferences)
    private(set) lazy var calendarAlerts = CalendarAlertScheduler(preferences: preferences, calendar: calendar, activities: activities, sound: sound)
    private(set) lazy var windowManager = NotchWindowManager(coordinator: self)
    #if DEBUG
    private lazy var debugCommands = DebugCommandService(coordinator: self)
    #endif

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private let launchDate = Date()
    private var volumeFeedback = VolumeFeedbackGate()
    private var greetingTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        activities.animationSpeed = { [preferences] in preferences.animationSpeed }
        media.preferredPlayer = { [preferences] in preferences.preferredPlayer }
        wireLiveActivities()
        wireScreenState()

        shelf.load()
        media.start()
        battery.start()
        volume.start()
        calendar.start()
        screenState.start()
        windowManager.start()
        if screenState.isObscured { windowManager.setHidden(true) }
        eventMonitor.start(coordinator: self)
        calendarAlerts.start()
        sound.scheduleHourlyChime { [preferences] in preferences.hourlyChime }
        #if DEBUG
        debugCommands.start()
        #endif

        preferences.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in self?.preferencesChanged(key) }
            .store(in: &cancellables)

        if preferences.greetAtLaunch { greet(after: 0.7) }
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

    // MARK: Greeting

    /// Says hello in the notch: the greeting bubble plus the jingle, like Alcove at
    /// launch. Also used by the settings preview and the debug command.
    func greet(after delay: TimeInterval = 0) {
        greetingTask?.cancel()
        greetingTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            activities.present(LiveActivity(kind: .greeting, duration: LiveActivity.greetingDuration))
            // Alcove starts its jingle 0.15 s in at 60 % volume (observed in 1.7.7).
            sound.play(.blips, if: preferences.greetingSound, volume: 0.6, delay: 0.15)
        }
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
                sound.play(.lowBattery, if: preferences.lowBatterySound)
            }
        }

        battery.onLowPowerModeChanged = { [weak self] enabled in
            guard let self, enabled else { return }
            if preferences.lowPowerActivityEnabled {
                activities.present(LiveActivity(kind: .lowPower, duration: preferences.liveActivityDuration + 1))
            }
            sound.play(.lowPower, if: preferences.lowPowerSound)
        }

        volume.onChange = { [weak self] new, old in
            guard let self else { return }
            if preferences.volumeActivityEnabled {
                activities.present(LiveActivity(
                    kind: .volume,
                    duration: preferences.liveActivityDuration,
                    payload: .volume(level: new.volume, muted: new.isMuted)
                ))
            }
            // macOS pops by itself when "Play feedback when volume is changed" is on;
            // never double it.
            if preferences.volumeFeedbackSound, !SystemSoundPreferences.volumeFeedbackEnabled,
               volumeFeedback.shouldPlay(old: old.volume, new: new.volume, muted: new.isMuted) {
                sound.play(.volume)
            }
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

    /// Lock screen: hide the islands (they live in a Space above everything, so they
    /// would otherwise be drawn over the lock screen), play lock/unlock, and show a
    /// short "Unlocked" activity on the way back.
    private func wireScreenState() {
        screenState.onObscuredChanged = { [weak self] obscured in
            self?.windowManager.setHidden(obscured)
        }
        screenState.onLocked = { [weak self] in
            guard let self else { return }
            sound.play(.lock, if: preferences.lockSound)
        }
        screenState.onUnlocked = { [weak self] in
            guard let self else { return }
            sound.play(.unlock, if: preferences.unlockSound)
            if preferences.unlockActivityEnabled {
                activities.present(LiveActivity(kind: .unlocked, duration: preferences.liveActivityDuration + 0.5))
            }
        }
    }

    private func crossedDown(_ old: Int, _ new: Int, thresholds: [Int]) -> Bool {
        thresholds.contains { new <= $0 && old > $0 }
    }

    private func preferencesChanged(_ key: String) {
        windowManager.preferencesChanged(key)
        if key == "sound.hourlyChime" || key == "sound.enabled" || key == "reset" {
            sound.scheduleHourlyChime { [preferences] in preferences.hourlyChime }
        }
        if key.hasPrefix("modules.calendar") || key.hasPrefix("activities.calendarEvent") || key == "sound.calendarEvent" || key == "reset" {
            calendarAlerts.reschedule()
        }
    }
}
