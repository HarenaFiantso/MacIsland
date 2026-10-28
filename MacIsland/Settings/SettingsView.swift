import SwiftUI
import EventKit
import UserNotifications
import IslandCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ModulesSettingsView()
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            ActivitiesSettingsView()
                .tabItem { Label("Live Activities", systemImage: "bolt.badge.clock") }
            SoundsSettingsView()
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Grow slightly when the pointer rests on the notch (peek)", isOn: $preferences.peekOnHover)
                Toggle("Open on hover", isOn: $preferences.openOnHover)
                    .disabled(!preferences.peekOnHover)
                LabeledSlider(title: "Hover delay", value: $preferences.hoverOpenDelay, range: 0.1...1.5, step: 0.05, unit: "s")
                    .disabled(!preferences.openOnHover || !preferences.peekOnHover)
                LabeledSlider(title: "Close delay after the pointer leaves", value: $preferences.closeDelay, range: 0.1...2.0, step: 0.05, unit: "s")
                Text("Clicking the notch always opens the island; clicking outside, pressing Escape or clicking the header closes it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Displays") {
                Picker("Show the island on", selection: $preferences.screenMode) {
                    ForEach(ScreenMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Also show on displays without a notch (virtual notch)", isOn: $preferences.showOnScreensWithoutNotch)
                LabeledSlider(title: "Virtual notch width", value: $preferences.virtualNotchWidth, range: 120...320, step: 5, unit: "pt")
                    .disabled(!preferences.showOnScreensWithoutNotch)
                LabeledSlider(title: "Virtual notch height", value: $preferences.virtualNotchHeight, range: 24...44, step: 1, unit: "pt")
                    .disabled(!preferences.showOnScreensWithoutNotch)
            }
            Section("System") {
                Toggle("Launch MacIsland at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.requiresApproval {
                    HStack {
                        Text("Approval pending in System Settings › Login Items").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section("Panel") {
                Picker("Expanded panel size", selection: $preferences.panelSize) {
                    ForEach(PanelSize.allCases) { size in
                        Text("\(size.rawValue.capitalized) — \(Int(size.expandedWidth)) × \(Int(size.expandedBodyHeight)) pt").tag(size)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section("Motion") {
                LabeledSlider(title: "Animation speed", value: $preferences.animationSpeed, range: 0.5...2.0, step: 0.05, unit: "×")
                Text("Springs keep the same damping ratio at every speed, so they stay natural: 1× is the reference tuning, 2× settles twice as fast.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Show the playback bars next to the media controls", isOn: $preferences.showVisualizer)
            }
            Section("Live activities") {
                LabeledSlider(title: "Default duration", value: $preferences.liveActivityDuration, range: 1...6, step: 0.5, unit: "s")
                LabeledSlider(title: "Now-playing announcement", value: $preferences.nowPlayingActivityDuration, range: 1...8, step: 0.5, unit: "s")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Modules

struct ModulesSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(MediaService.self) private var media
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        Form {
            Section("Modules") {
                Toggle("Media player", isOn: $preferences.mediaEnabled)
                Toggle("File shelf", isOn: $preferences.shelfEnabled)
                Toggle("Calendar", isOn: $preferences.calendarEnabled)
                Toggle("Timer", isOn: $preferences.timerEnabled)
                Toggle("Battery indicator", isOn: $preferences.batteryEnabled)
            }
            Section("Media") {
                Picker("Preferred player", selection: $preferences.preferredPlayer) {
                    ForEach(PlayerPreference.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Announce track changes in the notch", isOn: $preferences.nowPlayingActivityEnabled)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automation permission")
                        Text(automationStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Test now") { media.refreshNow() }
                    Button("Privacy Settings…") { PrivacyPane.automation.open() }
                }
                Text("Music and Spotify are controlled through Apple Events (public scripting API). Other players, including browsers, expose no public now-playing API on macOS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Calendar") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar access")
                        Text(calendarStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if calendar.status == .notDetermined {
                        Button("Request Access") { Task { await calendar.requestAccess() } }
                    } else {
                        Button("Privacy Settings…") { PrivacyPane.calendars.open() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var automationStatus: String {
        if !media.permissionDeniedSources.isEmpty {
            return "Denied for " + media.permissionDeniedSources.map(\.displayName).sorted().joined(separator: ", ")
        }
        if media.track != nil { return "Working (\(media.activeSource?.displayName ?? "player") responds)" }
        if media.runningSources.isEmpty { return "Neither Music nor Spotify is running" }
        return "Granted or not yet requested — press Test now to trigger the prompt"
    }

    private var calendarStatus: String {
        switch calendar.status {
        case .fullAccess: return "Granted"
        case .writeOnly: return "Write-only (events cannot be read)"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined:
            if let error = calendar.lastError { return "Request failed: \(error)" }
            return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Live activities

struct ActivitiesSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section("Show in the notch when…") {
                Toggle("Volume or mute changes", isOn: $preferences.volumeActivityEnabled)
                Toggle("Power is connected / disconnected, battery is low", isOn: $preferences.batteryActivityEnabled)
                Toggle("Low Power Mode turns on", isOn: $preferences.lowPowerActivityEnabled)
                Toggle("A calendar event starts", isOn: $preferences.calendarEventActivityEnabled)
                    .disabled(!preferences.calendarEnabled)
                Toggle("The screen is unlocked", isOn: $preferences.unlockActivityEnabled)
                Toggle("A timer is running (stays until it ends)", isOn: $preferences.timerActivityEnabled)
                Toggle("Files are dropped on the shelf", isOn: $preferences.shelfActivityEnabled)
            }
            Section {
                Text("Brightness changes are not available: macOS exposes no public API to observe display brightness. Everything listed above uses public, event-driven system APIs (Core Audio, IOKit power sources).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sounds

struct SoundsSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section("Sounds") {
                Toggle("Play sounds", isOn: $preferences.soundsEnabled)
                SoundRow(sound: .volume, isOn: $preferences.volumeFeedbackSound)
                SoundRow(sound: .lock, isOn: $preferences.lockSound)
                SoundRow(sound: .unlock, isOn: $preferences.unlockSound)
                SoundRow(sound: .lowBattery, isOn: $preferences.lowBatterySound)
                SoundRow(sound: .lowPower, isOn: $preferences.lowPowerSound)
                SoundRow(sound: .event, isOn: $preferences.calendarEventSound)
                SoundRow(sound: .chime, isOn: $preferences.hourlyChime)
                Text(volumeFeedbackNote)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .disabled(!preferences.soundsEnabled)
            Section("Launch") {
                Toggle("Say hello in the notch when MacIsland starts", isOn: $preferences.greetAtLaunch)
                SoundRow(sound: .blips, title: "Play the greeting jingle", isOn: $preferences.greetingSound)
                    .disabled(!preferences.soundsEnabled)
                HStack {
                    Text("Preview the greeting")
                    Spacer()
                    Button("Say Hello") { AppCoordinator.shared.greet() }
                }
            }
            Section("Haptics") {
                Toggle("Haptic feedback when the island opens or closes", isOn: $preferences.hapticsEnabled)
                Text("Force Touch trackpads only; macOS only plays it while a finger rests on the trackpad.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text(filesNote)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var volumeFeedbackNote: String {
        if SystemSoundPreferences.volumeFeedbackEnabled {
            return "macOS already plays its own feedback when the volume changes (System Settings › Sound), so the island stays quiet to avoid a double pop."
        }
        return "Short sounds use the sound-effects output device and the alert volume, exactly like macOS's own feedback."
    }

    private var filesNote: String {
        let bundled = IslandSound.allCases.filter(\.isBundled).count
        return "\(bundled) of \(IslandSound.allCases.count) sound files are bundled with this build; the rest use sounds that ship with macOS. See Scripts/import-alcove-sounds.sh."
    }
}

private struct SoundRow: View {
    let sound: IslandSound
    var title: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Toggle(title ?? sound.title, isOn: $isOn)
            Button {
                AppCoordinator.shared.sound.preview(sound)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help(sound.isBundled ? "Bundled file" : "macOS fallback sound")
            .disabled(sound.url == nil)
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MacIsland").font(.headline)
                        Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))").font(.footnote).foregroundStyle(.secondary)
                        Text("A Dynamic Island for the MacBook notch. Swift · SwiftUI · AppKit.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Detected displays") {
                ForEach(NSScreen.screens, id: \.self) { screen in
                    let geometry = ScreenDetector.geometry(for: screen, preferences: preferences)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(screen.localizedName)
                            Text(geometry.hasPhysicalNotch
                                 ? "Physical notch \(Int(geometry.notchSize.width)) × \(Int(geometry.notchSize.height)) pt · \(geometry.maximumFramesPerSecond) Hz"
                                 : "No notch — virtual notch · \(geometry.maximumFramesPerSecond) Hz")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Notifications") {
                HStack {
                    Text(notificationText)
                    Spacer()
                    Button("Notification Settings…") { PrivacyPane.notifications.open() }
                }
            }
            Section {
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset every MacIsland setting to its default value?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { preferences.resetToDefaults() }
                    }
            }
        }
        .formStyle(.grouped)
        .task { notificationStatus = await NotificationService.shared.authorizationStatus() }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional: return "Timer alerts: allowed"
        case .denied: return "Timer alerts: denied"
        case .notDetermined: return "Timer alerts: asked when the first timer starts"
        default: return "Timer alerts: checking…"
        }
    }
}

// MARK: - Helpers

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: $value, in: range, step: step)
                .frame(width: 180)
            Text(formatted)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }

    private var formatted: String {
        let text = step < 1 ? String(format: "%.2f", value) : String(format: "%.0f", value)
        return "\(text) \(unit)"
    }
}
