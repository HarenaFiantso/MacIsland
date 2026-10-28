#if DEBUG
import AppKit
import IslandCore

/// DEBUG-only remote control through a distributed notification, so the island can be
/// exercised from a terminal without synthetic mouse input:
///
///   swift Scripts/island-cmd.swift open | close | toggle | tab:shelf | media:toggle |
///         media:next | media:prev | activity:volume | activity:charging | activity:shelf |
///         timer:start:90 | timer:reset | hello | sound:lock | lock:on | lock:off |
///         space:dump | dump
///
/// Compiled out of Release builds.
@MainActor
final class DebugCommandService {
    static let notificationName = Notification.Name("com.macisland.debug.command")
    private var observer: NSObjectProtocol?
    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.notificationName, object: nil, queue: .main) { [weak self] note in
            let command = (note.userInfo?["command"] as? String) ?? note.object as? String ?? ""
            Task { @MainActor in self?.handle(command) }
        }
        Log.app.notice("debug command listener active")
    }

    private func handle(_ command: String) {
        Log.app.notice("debug command: \(command, privacy: .public)")
        let parts = command.split(separator: ":").map(String.init)
        guard let head = parts.first else { return }
        let manager = coordinator.windowManager
        switch head {
        case "open": manager.openAll(tab: parts.count > 1 ? IslandTab(rawValue: parts[1]) : nil)
        case "close": manager.closeAll()
        case "toggle": manager.toggleAll()
        case "tab":
            if parts.count > 1, let tab = IslandTab(rawValue: parts[1]) { manager.forEachModel { $0.select(tab) } }
        case "hover":
            let inside = parts.count > 1 && parts[1] == "in"
            manager.forEachModel { $0.send(.hoverChanged(inside)) }
        case "media":
            switch parts.dropFirst().first {
            case "toggle": coordinator.media.togglePlayPause()
            case "next": coordinator.media.nextTrack()
            case "prev": coordinator.media.previousTrack()
            case "refresh": coordinator.media.refreshNow()
            case "seek": if parts.count > 2, let s = Double(parts[2]) { coordinator.media.seek(to: s) }
            default: break
            }
        case "activity":
            let activities = coordinator.activities
            switch parts.dropFirst().first {
            case "volume": activities.present(LiveActivity(kind: .volume, duration: 2, payload: .volume(level: Float(parts.count > 2 ? Double(parts[2]) ?? 0.5 : 0.5), muted: false)))
            case "charging": activities.present(LiveActivity(kind: .charging, duration: 3, payload: .battery(level: coordinator.battery.snapshot.level, charging: true, pluggedIn: true)))
            case "battery": activities.present(LiveActivity(kind: .lowBattery, duration: 3, payload: .battery(level: 9, charging: false, pluggedIn: false)))
            case "shelf": activities.present(LiveActivity(kind: .shelfDrop, duration: 2, payload: .count(3)))
            case "lowpower": activities.present(LiveActivity(kind: .lowPower, duration: 3))
            case "event": activities.present(LiveActivity(kind: .calendarEvent, duration: 4, payload: .event(title: "Design review", tint: .orange)))
            case "unlock": activities.present(LiveActivity(kind: .unlocked, duration: 3))
            case "greeting": activities.present(LiveActivity(kind: .greeting, duration: LiveActivity.greetingDuration))
            case "nowplaying": if let t = coordinator.media.track { activities.present(LiveActivity(kind: .nowPlaying, duration: 3, payload: .nowPlaying(trackID: t.id))) }
            case "dismiss": activities.dismissAll()
            default: break
            }
        case "timer":
            switch parts.dropFirst().first {
            case "start": coordinator.timer.start(duration: parts.count > 2 ? Double(parts[2]) : nil)
            case "pause": coordinator.timer.pause()
            case "resume": coordinator.timer.resume()
            case "reset": coordinator.timer.reset()
            default: break
            }
        case "shelf":
            if parts.count > 2, parts[1] == "add" {
                let path = parts.dropFirst(2).joined(separator: ":")
                coordinator.shelf.add(urls: [URL(fileURLWithPath: path)])
            } else if parts.count > 1, parts[1] == "clear" {
                coordinator.shelf.removeAll()
            }
        case "settings": SettingsOpener.open()
        case "hello": coordinator.greet()
        case "sound":
            if parts.count > 1, let sound = IslandSound(rawValue: parts[1]) {
                coordinator.sound.preview(sound)
            } else {
                Log.app.error("unknown sound; valid: \(IslandSound.allCases.map(\.rawValue).joined(separator: ","), privacy: .public)")
            }
        case "lock":
            // Simulates the lock-screen notifications end to end (hide/show + sounds).
            let name = parts.count > 1 && parts[1] == "on" ? "com.apple.screenIsLocked" : "com.apple.screenIsUnlocked"
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
        case "space":
            for line in coordinator.windowManager.spaceDiagnostics() {
                Log.app.notice("space: \(line, privacy: .public)")
            }
        case "dump": dump()
        default: Log.app.error("unknown debug command \(command, privacy: .public)")
        }
    }

    private func dump() {
        let mouse = NSEvent.mouseLocation
        Log.app.notice("dump mouse: \(mouse.x) \(mouse.y) (screen coords, origin bottom-left)")
        coordinator.windowManager.forEachModel { model in
            let layout = model.targetLayout
            Log.app.notice("dump island \(model.id): mode=\(model.mode.rawValue, privacy: .public) hovering=\(model.isHovering) dragging=\(model.isDragging) tab=\(model.selectedTab.rawValue, privacy: .public) layout=\(layout.totalSize.width)x\(layout.totalSize.height) r=\(layout.radii.top)/\(layout.radii.bottom) activity=\(String(describing: model.currentActivity?.kind), privacy: .public)")
        }
        let media = coordinator.media
        Log.app.notice("dump media: source=\(media.activeSource?.displayName ?? "none", privacy: .public) track=\(media.track?.title ?? "-", privacy: .public) by \(media.track?.artist ?? "-", privacy: .public) playing=\(media.isPlaying) pos=\(media.playback.position()) dur=\(media.track?.duration ?? 0) artwork=\(media.artwork != nil) denied=\(media.permissionDeniedSources.count) running=\(media.runningSources.map(\.displayName).joined(separator: ","), privacy: .public) err=\(media.lastError ?? "-", privacy: .public)")
        let b = coordinator.battery.snapshot
        Log.app.notice("dump battery: \(b.level)% plugged=\(b.isPluggedIn) charging=\(b.isCharging) tte=\(b.timeToEmptyMinutes ?? -1) ttf=\(b.timeToFullMinutes ?? -1) watts=\(b.adapterWatts ?? -1)")
        let v = coordinator.volume.snapshot
        Log.app.notice("dump audio: \(v.deviceName, privacy: .public) vol=\(v.volume) muted=\(v.isMuted) supports=\(v.supportsVolume)")
        Log.app.notice("dump calendar: status=\(self.coordinator.calendar.status.rawValue) events=\(self.coordinator.calendar.events.count) upcoming=\(self.coordinator.calendar.upcoming.count)")
        Log.app.notice("dump shelf: \(self.coordinator.shelf.items.map(\.name).joined(separator: ", "), privacy: .public)")
        Log.app.notice("dump timer: \(String(describing: self.coordinator.timer.phase), privacy: .public) remaining=\(self.coordinator.timer.remaining())")
        for line in coordinator.windowManager.spaceDiagnostics() {
            Log.app.notice("dump \(line, privacy: .public)")
        }
        let sounds = IslandSound.allCases.map { "\($0.rawValue)=\($0.isBundled ? "bundled" : ($0.url == nil ? "missing" : "fallback"))" }
        Log.app.notice("dump sounds: \(sounds.joined(separator: " "), privacy: .public) systemFeedback=\(SystemSoundPreferences.volumeFeedbackEnabled)")
    }
}
#endif
