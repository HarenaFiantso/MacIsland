import SwiftUI
import EventKit
import UserNotifications
import IslandCore

// MARK: - Sections

/// The settings window is laid out like System Settings: a sidebar of sections on the
/// left, one page on the right with a title, a one-line description and grouped rows.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, modules, media, activities, sounds, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .modules: return "Modules"
        case .media: return "Media"
        case .activities: return "Live Activities"
        case .sounds: return "Sounds"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "How the island opens, which displays it lives on, launch at login."
        case .appearance: return "Size of the panel, speed of the animations, how long activities stay."
        case .modules: return "Turn the panel's modules on or off."
        case .media: return "Which player the island follows, and how it announces tracks."
        case .activities: return "What the collapsed island announces in its wings."
        case .sounds: return "Alcove's cues, the launch greeting and the trackpad tick."
        case .about: return "Version, displays, notifications and reset."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .modules: return "square.grid.2x2.fill"
        case .media: return "music.note"
        case .activities: return "bolt.fill"
        case .sounds: return "speaker.wave.2.fill"
        case .about: return "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .purple
        case .modules: return .blue
        case .media: return .pink
        case .activities: return .orange
        case .sounds: return .red
        case .about: return .gray
        }
    }
}

// MARK: - Window content

struct SettingsView: View {
    /// Posted with a `SettingsSection` object to switch pages from outside (debug commands).
    static let selectSectionNotification = Notification.Name("com.macisland.settings.selectSection")

    @State private var selection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                SettingsSidebarRow(section: section)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter() }
            .navigationSplitViewColumnWidth(min: 210, ideal: 226, max: 270)
        } detail: {
            SettingsPage(section: selection ?? .general)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 740, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(for: Self.selectSectionNotification)) { note in
            if let section = note.object as? SettingsSection { selection = section }
        }
    }
}

/// System Settings-style row: a coloured rounded tile with a symbol, then the name.
struct SettingsSidebarRow: View {
    let section: SettingsSection

    var body: some View {
        Label {
            Text(section.title)
                .lineLimit(1)
                .padding(.leading, 2)
        } icon: {
            SettingsIconTile(symbol: section.symbol, tint: section.tint, size: 23)
        }
        .padding(.vertical, 1)
    }
}

struct SettingsIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(tint.gradient)
            )
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

private struct SidebarFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("MacIsland").font(.system(size: 11, weight: .semibold))
                Text("Version \(Bundle.main.shortVersion)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// One page: a header, then the section's grouped form.
struct SettingsPage: View {
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                SettingsIconTile(symbol: section.symbol, tint: section.tint, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.system(size: 20, weight: .bold))
                    Text(section.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 2)

            form
                .id(section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var form: some View {
        switch section {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .modules: ModulesSettingsView()
        case .media: MediaSettingsView()
        case .activities: ActivitiesSettingsView()
        case .sounds: SoundsSettingsView()
        case .about: AboutSettingsView()
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        Form {
            Section {
                SettingsToggle(
                    "Peek when the pointer rests on the notch",
                    subtitle: "The island grows slightly to show it noticed you.",
                    isOn: $preferences.peekOnHover
                )
                SettingsToggle(
                    "Open on hover",
                    subtitle: "Keep hovering and the panel opens by itself.",
                    isOn: $preferences.openOnHover
                )
                .disabled(!preferences.peekOnHover)
                LabeledSlider(title: "Hover delay", value: $preferences.hoverOpenDelay, range: 0.1...1.5, step: 0.05, unit: "s")
                    .disabled(!preferences.openOnHover || !preferences.peekOnHover)
                LabeledSlider(title: "Close delay after the pointer leaves", value: $preferences.closeDelay, range: 0.1...2.0, step: 0.05, unit: "s")
            } header: {
                Text("Opening")
            } footer: {
                Text("Clicking the notch always opens the island. Clicking outside, pressing Escape or clicking the header closes it.")
            }

            Section {
                Picker("Show the island on", selection: $preferences.screenMode) {
                    ForEach(ScreenMode.allCases) { Text($0.title).tag($0) }
                }
                SettingsToggle(
                    "Virtual notch on displays without one",
                    subtitle: "A black notch is drawn at the top of external displays.",
                    isOn: $preferences.showOnScreensWithoutNotch
                )
                LabeledSlider(title: "Virtual notch width", value: $preferences.virtualNotchWidth, range: 120...320, step: 5, unit: "pt")
                    .disabled(!preferences.showOnScreensWithoutNotch)
                LabeledSlider(title: "Virtual notch height", value: $preferences.virtualNotchHeight, range: 24...44, step: 1, unit: "pt")
                    .disabled(!preferences.showOnScreensWithoutNotch)
            } header: {
                Text("Displays")
            }

            Section {
                SettingsToggle(
                    "Launch MacIsland at login",
                    subtitle: launchAtLogin.requiresApproval ? "Approval pending in System Settings › Login Items." : "Starts quietly in the menu bar.",
                    isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) })
                )
                if launchAtLogin.requiresApproval {
                    SettingsActionRow(title: "Login Items", status: "Waiting for your approval") {
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("System")
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
            Section {
                Picker("Expanded panel", selection: $preferences.panelSize) {
                    ForEach(PanelSize.allCases) { size in
                        Text("\(size.rawValue.capitalized) · \(Int(size.expandedWidth)) × \(Int(size.expandedBodyHeight)) pt").tag(size)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Panel")
            } footer: {
                Text("The panel always stays wide enough to clear the notch on both sides.")
            }

            Section {
                LabeledSlider(title: "Animation speed", value: $preferences.animationSpeed, range: 0.5...2.0, step: 0.05, unit: "×")
            } header: {
                Text("Motion")
            } footer: {
                Text("Springs keep the same damping ratio at every speed, so they stay natural: 1× is the reference tuning, 2× settles twice as fast.")
            }

            Section {
                LabeledSlider(title: "Default duration", value: $preferences.liveActivityDuration, range: 1...6, step: 0.5, unit: "s")
                LabeledSlider(title: "Now-playing announcement", value: $preferences.nowPlayingActivityDuration, range: 1...8, step: 0.5, unit: "s")
            } header: {
                Text("Live activities")
            } footer: {
                Text("How long the wings stay out before the island folds back into the notch.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Modules

struct ModulesSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        Form {
            Section {
                ModuleToggle(title: "Media player", subtitle: "Artwork, controls and a scrubber on the Home tab.", symbol: "music.note", tint: .pink, isOn: $preferences.mediaEnabled)
                ModuleToggle(title: "File shelf", subtitle: "Drop files on the notch to park them in their own tab.", symbol: "tray.full.fill", tint: .blue, isOn: $preferences.shelfEnabled)
                ModuleToggle(title: "Calendar", subtitle: "Today and the next seven days of events.", symbol: "calendar", tint: .red, isOn: $preferences.calendarEnabled)
                ModuleToggle(title: "Timer", subtitle: "Presets, a progress ring and a notification at the end.", symbol: "timer", tint: .orange, isOn: $preferences.timerEnabled)
                ModuleToggle(title: "Battery indicator", subtitle: "Level and charging state in the panel's header.", symbol: "battery.100percent", tint: .green, isOn: $preferences.batteryEnabled)
            } header: {
                Text("Modules")
            } footer: {
                Text("Home always stays: it is where the media player lives.")
            }

            Section {
                SettingsActionRow(title: "Calendar access", status: calendarStatus) {
                    if calendar.status == .notDetermined {
                        Button("Request Access") { Task { await calendar.requestAccess() } }
                    } else {
                        Button("Privacy Settings…") { PrivacyPane.calendars.open() }
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
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

// MARK: - Media

struct MediaSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(MediaService.self) private var media

    var body: some View {
        Form {
            Section {
                Picker("Preferred player", selection: $preferences.preferredPlayer) {
                    ForEach(PlayerPreference.allCases) { Text($0.title).tag($0) }
                }
                SettingsToggle(
                    "Announce track changes in the notch",
                    subtitle: "Artwork and playback bars in the wings for a few seconds.",
                    isOn: $preferences.nowPlayingActivityEnabled
                )
                SettingsToggle(
                    "Playback bars next to the controls",
                    subtitle: "Tinted with the artwork, like the glow at the bottom of the panel.",
                    isOn: $preferences.showVisualizer
                )
            } header: {
                Text("Player")
            } footer: {
                Text("Music and Spotify are controlled through Apple Events (their public scripting API). Other players, including browsers, expose no public now-playing API on macOS.")
            }

            Section {
                SettingsActionRow(title: "Automation permission", status: automationStatus) {
                    Button("Test now") { media.refreshNow() }
                    Button("Privacy Settings…") { PrivacyPane.automation.open() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("macOS asks once per player the first time the island talks to it.")
            }
        }
        .formStyle(.grouped)
    }

    private var automationStatus: String {
        if !media.permissionDeniedSources.isEmpty {
            return "Denied for " + media.permissionDeniedSources.map(\.displayName).sorted().joined(separator: ", ")
        }
        if media.track != nil { return "Working — \(media.activeSource?.displayName ?? "player") responds" }
        if media.runningSources.isEmpty { return "Neither Music nor Spotify is running" }
        return "Granted or not yet requested — press Test now to trigger the prompt"
    }
}

// MARK: - Live activities

struct ActivitiesSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section {
                ActivityToggle(title: "Volume or mute changes", symbol: "speaker.wave.2.fill", isOn: $preferences.volumeActivityEnabled)
                ActivityToggle(title: "Power connected or disconnected, battery low", symbol: "bolt.fill", isOn: $preferences.batteryActivityEnabled)
                ActivityToggle(title: "Low Power Mode turns on", symbol: "battery.25percent", isOn: $preferences.lowPowerActivityEnabled)
                ActivityToggle(title: "A calendar event starts", symbol: "calendar", isOn: $preferences.calendarEventActivityEnabled)
                    .disabled(!preferences.calendarEnabled)
                ActivityToggle(title: "The screen is unlocked", symbol: "lock.open.fill", isOn: $preferences.unlockActivityEnabled)
                ActivityToggle(title: "A timer is running (stays until it ends)", symbol: "timer", isOn: $preferences.timerActivityEnabled)
                ActivityToggle(title: "Files are dropped on the shelf", symbol: "tray.and.arrow.down.fill", isOn: $preferences.shelfActivityEnabled)
            } header: {
                Text("Show in the notch when…")
            } footer: {
                Text("Everything above comes from public, event-driven system APIs (Core Audio, IOKit power sources, EventKit). Brightness changes are not available: macOS exposes no public API to observe display brightness.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ActivityToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
        }
    }
}

// MARK: - Sounds

struct SoundsSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section {
                SettingsToggle("Play sounds", subtitle: "Master switch for every cue below.", isOn: $preferences.soundsEnabled)
            }

            Section {
                SoundRow(sound: .volume, isOn: $preferences.volumeFeedbackSound)
                SoundRow(sound: .lock, isOn: $preferences.lockSound)
                SoundRow(sound: .unlock, isOn: $preferences.unlockSound)
                SoundRow(sound: .lowBattery, isOn: $preferences.lowBatterySound)
                SoundRow(sound: .lowPower, isOn: $preferences.lowPowerSound)
                SoundRow(sound: .event, isOn: $preferences.calendarEventSound)
                SoundRow(sound: .chime, isOn: $preferences.hourlyChime)
            } header: {
                Text("Cues")
            } footer: {
                Text(volumeFeedbackNote)
            }
            .disabled(!preferences.soundsEnabled)

            Section {
                SettingsToggle(
                    "Write hello in the notch when MacIsland starts",
                    subtitle: "The word is drawn by hand, the way a new Mac greets you.",
                    isOn: $preferences.greetAtLaunch
                )
                SoundRow(sound: .blips, title: "Play the greeting jingle", isOn: $preferences.greetingSound)
                    .disabled(!preferences.soundsEnabled)
                SettingsActionRow(title: "Preview", status: "Writes hello under the notch right now") {
                    Button("Say hello") { AppCoordinator.shared.greet() }
                }
            } header: {
                Text("Launch")
            }

            Section {
                SettingsToggle(
                    "Haptic feedback when the island opens or closes",
                    subtitle: "Force Touch trackpads only; macOS plays it while a finger rests on the trackpad.",
                    isOn: $preferences.hapticsEnabled
                )
            } header: {
                Text("Haptics")
            } footer: {
                Text(filesNote)
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
        HStack(spacing: 10) {
            Button {
                AppCoordinator.shared.sound.preview(sound)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(sound.url == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.borderless)
            .help(sound.isBundled ? "Preview (bundled file)" : "Preview (macOS fallback sound)")
            .disabled(sound.url == nil)
            Toggle(title ?? sound.title, isOn: $isOn)
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
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacIsland").font(.system(size: 17, weight: .bold))
                        Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("A Dynamic Island for the MacBook notch. Swift · SwiftUI · AppKit.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(NSScreen.screens, id: \.self) { screen in
                    let geometry = ScreenDetector.geometry(for: screen, preferences: preferences)
                    HStack(spacing: 12) {
                        Image(systemName: geometry.isBuiltIn ? "laptopcomputer" : "display")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(screen.localizedName)
                            Text(verbatim: geometry.hasPhysicalNotch
                                 ? "Physical notch \(Int(geometry.notchSize.width)) × \(Int(geometry.notchSize.height)) pt · \(geometry.maximumFramesPerSecond) Hz"
                                 : "No notch — virtual notch · \(geometry.maximumFramesPerSecond) Hz")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt")
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Displays")
            }

            Section {
                SettingsActionRow(title: "Timer alerts", status: notificationText) {
                    Button("Notification Settings…") { PrivacyPane.notifications.open() }
                }
            } header: {
                Text("Notifications")
            }

            Section {
                SettingsActionRow(title: "Reset", status: "Every setting back to its default value") {
                    Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                        .confirmationDialog("Reset every MacIsland setting to its default value?", isPresented: $confirmReset) {
                            Button("Reset", role: .destructive) { preferences.resetToDefaults() }
                        }
                }
            }
        }
        .formStyle(.grouped)
        .task { notificationStatus = await NotificationService.shared.authorizationStatus() }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Asked when the first timer starts"
        default: return "Checking…"
        }
    }
}

// MARK: - Row helpers

/// A switch with a title and an optional one-line explanation underneath.
struct SettingsToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A module row: coloured tile, name, what it does, switch.
struct ModuleToggle: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SettingsIconTile(symbol: symbol, tint: tint, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A title with a status line on the left and one or more buttons on the right.
struct SettingsActionRow<Actions: View>: View {
    let title: String
    let status: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            actions
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Slider(value: $value, in: range, step: step)
                .frame(width: 170)
            Text(formatted)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private var formatted: String {
        let text = step < 1 ? String(format: "%.2f", value) : String(format: "%.0f", value)
        return "\(text) \(unit)"
    }
}
