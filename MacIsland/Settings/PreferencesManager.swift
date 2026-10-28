import Foundation
import Combine
import IslandCore

// MARK: - UserDefaults plumbing

protocol DefaultsRepresentable {
    static func readDefaults(_ defaults: UserDefaults, key: String) -> Self?
    func writeDefaults(_ defaults: UserDefaults, key: String)
}

extension Bool: DefaultsRepresentable {
    static func readDefaults(_ d: UserDefaults, key: String) -> Bool? { d.object(forKey: key) == nil ? nil : d.bool(forKey: key) }
    func writeDefaults(_ d: UserDefaults, key: String) { d.set(self, forKey: key) }
}
extension Int: DefaultsRepresentable {
    static func readDefaults(_ d: UserDefaults, key: String) -> Int? { d.object(forKey: key) == nil ? nil : d.integer(forKey: key) }
    func writeDefaults(_ d: UserDefaults, key: String) { d.set(self, forKey: key) }
}
extension Double: DefaultsRepresentable {
    static func readDefaults(_ d: UserDefaults, key: String) -> Double? { d.object(forKey: key) == nil ? nil : d.double(forKey: key) }
    func writeDefaults(_ d: UserDefaults, key: String) { d.set(self, forKey: key) }
}
extension String: DefaultsRepresentable {
    static func readDefaults(_ d: UserDefaults, key: String) -> String? { d.string(forKey: key) }
    func writeDefaults(_ d: UserDefaults, key: String) { d.set(self, forKey: key) }
}
extension DefaultsRepresentable where Self: RawRepresentable, RawValue == String {
    static func readDefaults(_ d: UserDefaults, key: String) -> Self? { d.string(forKey: key).flatMap(Self.init(rawValue:)) }
    func writeDefaults(_ d: UserDefaults, key: String) { d.set(rawValue, forKey: key) }
}

extension PanelSize: DefaultsRepresentable {}

enum ScreenMode: String, CaseIterable, Identifiable, DefaultsRepresentable {
    case builtIn, all, primary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtIn: return "Built-in display"
        case .all: return "Every display"
        case .primary: return "Primary display only"
        }
    }
}

enum PlayerPreference: String, CaseIterable, Identifiable, DefaultsRepresentable {
    case automatic, music, spotify
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic (whichever is playing)"
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

/// Property wrapper persisting to UserDefaults and publishing through the
/// enclosing `Preferences` (ObservableObject) so SwiftUI bindings just work.
@propertyWrapper
struct Pref<Value: DefaultsRepresentable> {
    let key: String
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.defaultValue = wrappedValue
        self.key = Preferences.keyPrefix + key
    }

    @available(*, unavailable, message: "Pref is only usable inside Preferences")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript<T: Preferences>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        get {
            let wrapper = instance[keyPath: storageKeyPath]
            return Value.readDefaults(instance.defaults, key: wrapper.key) ?? wrapper.defaultValue
        }
        set {
            let wrapper = instance[keyPath: storageKeyPath]
            instance.objectWillChange.send()
            newValue.writeDefaults(instance.defaults, key: wrapper.key)
            instance.didChange.send(String(wrapper.key.dropFirst(Preferences.keyPrefix.count)))
        }
    }
}

// MARK: - Preferences

/// All user-facing settings. Every property is persisted immediately.
class Preferences: ObservableObject {
    static let shared = Preferences()
    static let keyPrefix = "macisland."

    let defaults: UserDefaults
    /// Emits the (un-prefixed) key of the setting that changed, or "reset".
    let didChange = PassthroughSubject<String, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Behaviour
    @Pref("behavior.openOnHover") var openOnHover = true
    @Pref("behavior.peekOnHover") var peekOnHover = true
    @Pref("behavior.hoverOpenDelay") var hoverOpenDelay = 0.35
    @Pref("behavior.closeDelay") var closeDelay = 0.4

    // Appearance / motion
    @Pref("appearance.panelSize") var panelSize = PanelSize.regular
    @Pref("appearance.animationSpeed") var animationSpeed = 1.0
    @Pref("appearance.showVisualizer") var showVisualizer = true

    // Screens
    @Pref("screen.mode") var screenMode = ScreenMode.builtIn
    @Pref("screen.showOnScreensWithoutNotch") var showOnScreensWithoutNotch = true
    @Pref("notch.virtualWidth") var virtualNotchWidth = 185.0
    @Pref("notch.virtualHeight") var virtualNotchHeight = 32.0

    // Modules
    @Pref("modules.media") var mediaEnabled = true
    @Pref("modules.shelf") var shelfEnabled = true
    @Pref("modules.calendar") var calendarEnabled = true
    @Pref("modules.timer") var timerEnabled = true
    @Pref("modules.battery") var batteryEnabled = true

    // Media
    @Pref("media.preferredPlayer") var preferredPlayer = PlayerPreference.automatic
    @Pref("media.nowPlayingActivity") var nowPlayingActivityEnabled = true
    @Pref("media.nowPlayingActivityDuration") var nowPlayingActivityDuration = 3.0

    // Live activities
    @Pref("activities.volume") var volumeActivityEnabled = true
    @Pref("activities.battery") var batteryActivityEnabled = true
    @Pref("activities.lowPower") var lowPowerActivityEnabled = true
    @Pref("activities.timer") var timerActivityEnabled = true
    @Pref("activities.shelf") var shelfActivityEnabled = true
    @Pref("activities.calendarEvent") var calendarEventActivityEnabled = true
    @Pref("activities.unlock") var unlockActivityEnabled = true
    @Pref("activities.duration") var liveActivityDuration = 2.0

    // Sounds (Alcove's set) and haptics
    @Pref("sound.enabled") var soundsEnabled = true
    @Pref("sound.volumeFeedback") var volumeFeedbackSound = true
    @Pref("sound.lock") var lockSound = true
    @Pref("sound.unlock") var unlockSound = true
    @Pref("sound.lowBattery") var lowBatterySound = true
    @Pref("sound.lowPower") var lowPowerSound = true
    @Pref("sound.calendarEvent") var calendarEventSound = true
    @Pref("sound.hourlyChime") var hourlyChime = false
    @Pref("sound.greeting") var greetingSound = true
    @Pref("behavior.haptics") var hapticsEnabled = true

    // Launch
    @Pref("launch.greeting") var greetAtLaunch = true

    func resetToDefaults() {
        objectWillChange.send()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
        didChange.send("reset")
    }
}
