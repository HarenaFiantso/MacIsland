import AppKit
import AVFoundation
import AudioToolbox

/// Every sound the island can make. Raw values are the file names looked up in the
/// app bundle (`<name>.caf` / `.m4a` / `.aiff` / `.wav`), the same names Alcove uses,
/// so its files can be dropped into `MacIsland/Resources/Sounds/`
/// (`Scripts/import-alcove-sounds.sh`). Without a bundled file the sound falls back
/// to one that ships with macOS.
enum IslandSound: String, CaseIterable, Identifiable {
    /// Feedback pop when the volume changes (Alcove's file is the macOS one).
    case volume
    case lock
    case unlock
    case lowBattery = "low-battery"
    case lowPower = "low-power"
    /// Hourly chime.
    case chime
    /// A calendar event starts.
    case event
    /// Time to leave for an event (unused for now, kept for parity).
    case directions
    /// Sleep focus (unused for now, kept for parity).
    case sleep
    /// Launch greeting jingle.
    case blips
    /// Onboarding jingles in Alcove, available for the greeting as alternatives.
    case pad
    case altJingle = "alt-jingle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volume: return "Volume change"
        case .lock: return "Screen locked"
        case .unlock: return "Screen unlocked"
        case .lowBattery: return "Low battery"
        case .lowPower: return "Low Power Mode"
        case .chime: return "Hourly chime"
        case .event: return "Calendar event"
        case .directions: return "Time to leave"
        case .sleep: return "Sleep focus"
        case .blips: return "Greeting jingle"
        case .pad: return "Greeting pad"
        case .altJingle: return "Alternate jingle"
        }
    }

    private static let bundledExtensions = ["caf", "m4a", "aiff", "aif", "wav", "mp3"]

    /// File inside the app bundle, if one was added.
    var bundledURL: URL? {
        for ext in Self.bundledExtensions {
            if let url = Bundle.main.url(forResource: rawValue, withExtension: ext) { return url }
        }
        return nil
    }

    /// A sound that ships with macOS and plays the same role.
    var systemFallbackURL: URL? {
        let tones = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/"
        let path: String
        switch self {
        case .volume: path = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        case .lock: path = tones + "Modern/Keys.m4r"
        case .unlock: path = tones + "Modern/Input.m4r"
        case .lowBattery: path = tones + "Classic/Descent.m4r"
        case .lowPower: path = tones + "Classic/Ladder.m4r"
        case .chime: path = tones + "Classic/Chime.m4r"
        case .event: path = tones + "Modern/Note.m4r"
        case .directions: path = tones + "Modern/Circles.m4r"
        case .sleep: path = tones + "Modern/Aurora.m4r"
        case .blips: path = tones + "Modern/Hello.m4r"
        case .pad: path = tones + "Modern/Synth.m4r"
        case .altJingle: path = tones + "Modern/Chord.m4r"
        }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    var url: URL? { bundledURL ?? systemFallbackURL }
    var isBundled: Bool { bundledURL != nil }
}

/// Plays the island's sounds.
///
/// Short UI sounds (CAF/AIFF/WAV) go through `AudioServicesPlaySystemSound`, exactly
/// like macOS's own feedback: they come out of the *sound effects* output device at
/// the alert volume, so the volume pop is inaudible at volume 0 just as Apple's is.
/// Compressed, music-like files (the jingles) go through `AVAudioPlayer`, which also
/// allows a volume and a start delay.
@MainActor
final class SoundService {
    private unowned let preferences: Preferences
    private var systemSounds: [IslandSound: SystemSoundID] = [:]
    private var players: [IslandSound: AVAudioPlayer] = [:]
    private var chimeTask: Task<Void, Never>?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Plays `sound` unless sounds are globally off (or `enabled` says no).
    /// `volume` and `delay` only apply to sounds played through `AVAudioPlayer`.
    func play(_ sound: IslandSound, if enabled: Bool = true, volume: Float = 1, delay: TimeInterval = 0) {
        guard enabled, preferences.soundsEnabled else { return }
        guard let url = sound.url else {
            Log.system.error("sound \(sound.rawValue, privacy: .public): no file available")
            return
        }
        Log.system.debug("sound \(sound.rawValue, privacy: .public) \(sound.isBundled ? "bundled" : "fallback", privacy: .public) delay=\(delay) volume=\(volume)")
        if Self.usesSystemSound(url) {
            playSystemSound(sound, url: url, delay: delay)
        } else {
            playWithPlayer(sound, url: url, volume: volume, delay: delay)
        }
    }

    /// Previews a sound regardless of the preferences (settings window).
    func preview(_ sound: IslandSound) {
        guard let url = sound.url else { return }
        if Self.usesSystemSound(url) {
            playSystemSound(sound, url: url, delay: 0)
        } else {
            playWithPlayer(sound, url: url, volume: 0.6, delay: 0)
        }
    }

    func stop(_ sound: IslandSound) {
        players[sound]?.stop()
    }

    // MARK: Hourly chime

    /// Plays `chime` at the top of every hour while `isEnabled()` says so. Call again
    /// whenever the preference changes; the pending timer is replaced.
    func scheduleHourlyChime(isEnabled: @escaping () -> Bool) {
        chimeTask?.cancel()
        guard isEnabled() else { return }
        chimeTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                guard let next = Calendar.current.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
                try? await Task.sleep(for: .seconds(next.timeIntervalSince(now)))
                guard !Task.isCancelled, let self else { return }
                // Guard against a long sleep: only chime if we woke close to the hour.
                if abs(Date().timeIntervalSince(next)) < 90, isEnabled() {
                    self.play(.chime)
                }
            }
        }
    }

    // MARK: Engines

    private static func usesSystemSound(_ url: URL) -> Bool {
        ["caf", "aiff", "aif", "wav"].contains(url.pathExtension.lowercased())
    }

    private func playSystemSound(_ sound: IslandSound, url: URL, delay: TimeInterval) {
        let id: SystemSoundID
        if let cached = systemSounds[sound] {
            id = cached
        } else {
            var created: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &created)
            guard status == noErr else {
                Log.system.error("sound \(sound.rawValue, privacy: .public): AudioServicesCreateSystemSoundID failed (\(status))")
                return
            }
            systemSounds[sound] = created
            id = created
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { AudioServicesPlaySystemSound(id) }
        } else {
            AudioServicesPlaySystemSound(id)
        }
    }

    private func playWithPlayer(_ sound: IslandSound, url: URL, volume: Float, delay: TimeInterval) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            players[sound]?.stop()
            players[sound] = player
            if delay > 0 {
                player.play(atTime: player.deviceCurrentTime + delay)
            } else {
                player.play()
            }
        } catch {
            Log.system.error("sound \(sound.rawValue, privacy: .public): AVAudioPlayer failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Trackpad haptics (Force Touch trackpads only; macOS ignores the call otherwise).
@MainActor
enum Haptics {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// Reads the macOS "Play feedback when volume is changed" setting (System Settings ›
/// Sound). When it is on, macOS already pops on every volume key press and the island
/// must stay quiet to avoid a double pop. The key is absent on a fresh system, where
/// the feature is off.
enum SystemSoundPreferences {
    static var volumeFeedbackEnabled: Bool {
        guard let value = CFPreferencesCopyAppValue("com.apple.sound.beep.feedback" as CFString, kCFPreferencesAnyApplication) else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
