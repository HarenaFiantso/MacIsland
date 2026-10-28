import AppKit

/// Screen lock / screen saver state, from the distributed notifications loginwindow
/// and the screen saver post. No permission needed.
@MainActor
final class ScreenStateService {
    private(set) var isLocked = false
    private(set) var isScreenSaverRunning = false
    /// Called with the new "obscured" state (locked or screen saver) when it changes.
    var onObscuredChanged: ((Bool) -> Void)?
    var onLocked: (() -> Void)?
    var onUnlocked: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    var isObscured: Bool { isLocked || isScreenSaverRunning }

    func start() {
        // Initial state: the notifications only report changes, and the app may start
        // while the session is already locked (relaunch, login item on a locked Mac).
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let locked = session["CGSSessionScreenIsLocked"] as? Bool {
            isLocked = locked
        }
        let center = DistributedNotificationCenter.default()
        func observe(_ name: String, _ handler: @escaping @MainActor () -> Void) {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                Task { @MainActor in handler() }
            })
        }
        observe("com.apple.screenIsLocked") { [weak self] in self?.set(locked: true) }
        observe("com.apple.screenIsUnlocked") { [weak self] in self?.set(locked: false) }
        observe("com.apple.screensaver.didstart") { [weak self] in self?.set(screenSaver: true) }
        observe("com.apple.screensaver.didstop") { [weak self] in self?.set(screenSaver: false) }
    }

    private func set(locked: Bool) {
        guard locked != isLocked else { return }
        let wasObscured = isObscured
        isLocked = locked
        Log.system.notice("screen \(locked ? "locked" : "unlocked", privacy: .public)")
        if locked { onLocked?() } else { onUnlocked?() }
        if wasObscured != isObscured { onObscuredChanged?(isObscured) }
    }

    private func set(screenSaver: Bool) {
        guard screenSaver != isScreenSaverRunning else { return }
        let wasObscured = isObscured
        isScreenSaverRunning = screenSaver
        if wasObscured != isObscured { onObscuredChanged?(isObscured) }
    }
}
