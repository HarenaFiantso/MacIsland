import AppKit
import SwiftUI
import Observation
import CoreImage

// MARK: - Model

enum MediaSource: String, CaseIterable, Sendable, Identifiable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var id: String { rawValue }
    var bundleID: String { rawValue }

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    var symbolName: String {
        switch self {
        case .music: return "music.note"
        case .spotify: return "waveform"
        }
    }

    /// Distributed notification each player posts when playback changes (public mechanism).
    var playbackNotificationName: Notification.Name {
        switch self {
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

struct NowPlayingTrack: Equatable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var source: MediaSource
    var artworkURL: URL?
}

struct PlaybackState: Equatable, Sendable {
    var isPlaying: Bool
    var position: TimeInterval
    var capturedAt: Date

    /// Extrapolated position, so the UI can tick without polling the player.
    func position(at date: Date = Date()) -> TimeInterval {
        isPlaying ? position + date.timeIntervalSince(capturedAt) : position
    }

    static let stopped = PlaybackState(isPlaying: false, position: 0, capturedAt: Date())
}

enum PlayerState: String, Sendable {
    case playing, paused, stopped
}

struct ProviderSnapshot: Equatable, Sendable {
    var state: PlayerState
    var position: TimeInterval
    var track: NowPlayingTrack?
}

/// Raw list returned by the AppleScript snapshot (8 items, see `snapshotScript`).
struct RawSnapshot: Sendable {
    var state: String
    var position: Double
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artworkURL: String
    var trackID: String
}

// MARK: - Provider (AppleScript + distributed notifications)

/// One player (Music or Spotify). Entirely event-driven: the player's distributed
/// notification triggers a single AppleScript round-trip; nothing polls while idle.
@MainActor
final class ScriptedMediaProvider {
    let source: MediaSource
    private(set) var snapshot: ProviderSnapshot?
    private(set) var lastChange = Date.distantPast
    private(set) var permissionDenied = false
    private(set) var lastError: String?
    var onUpdate: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var lastPermissionFailure = Date.distantPast
    private let runner = AppleScriptRunner.shared

    init(source: MediaSource) {
        self.source = source
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: source.playbackNotificationName, object: nil, queue: .main) { [weak self] note in
            let state = (note.userInfo?["Player State"] as? String)?.lowercased()
            Task { @MainActor in self?.playbackNotification(state: state) }
        })

        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier
            Task { @MainActor in
                guard let self, bundleID == self.source.bundleID else { return }
                self.clear()
            }
        })
        observers.append(wnc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier
            Task { @MainActor in
                guard let self, bundleID == self.source.bundleID else { return }
                try? await Task.sleep(for: .seconds(2))
                self.scheduleRefresh()
            }
        })

        if isRunning { scheduleRefresh() }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func playbackNotification(state: String?) {
        if state == "stopped" {
            clear()
        } else {
            scheduleRefresh()
        }
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        guard isRunning else { clear(); return }
        if permissionDenied, Date().timeIntervalSince(lastPermissionFailure) < 20 { return }
        do {
            let raw = try await runner.run(snapshotScript) { Self.parseSnapshot($0) }
            permissionDenied = false
            lastError = nil
            apply(raw)
        } catch let error as AppleScriptError {
            lastError = error.localizedDescription
            if error.isPermissionDenied {
                permissionDenied = true
                lastPermissionFailure = Date()
                Log.media.error("\(self.source.displayName, privacy: .public): automation denied (\(error.localizedDescription, privacy: .public))")
            } else if error.isTargetNotRunning {
                clear()
            } else {
                Log.media.error("\(self.source.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            onUpdate?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(_ raw: RawSnapshot?) {
        guard let raw else { clear(); return }
        let state = PlayerState(rawValue: raw.state.lowercased()) ?? .stopped
        guard state != .stopped, !raw.title.isEmpty else { clear(); return }

        // Spotify reports duration in milliseconds, Music in seconds.
        let duration = source == .spotify ? raw.duration / 1000 : raw.duration
        let id = raw.trackID.isEmpty ? "\(raw.title)|\(raw.artist)|\(raw.album)" : raw.trackID
        let track = NowPlayingTrack(
            id: id,
            title: raw.title,
            artist: raw.artist,
            album: raw.album,
            duration: duration,
            source: source,
            artworkURL: raw.artworkURL.isEmpty ? nil : URL(string: raw.artworkURL)
        )
        let new = ProviderSnapshot(state: state, position: max(0, raw.position), track: track)
        if new != snapshot {
            snapshot = new
            lastChange = Date()
        }
        onUpdate?()
    }

    private func clear() {
        guard snapshot != nil else { return }
        snapshot = nil
        lastChange = Date()
        onUpdate?()
    }

    // MARK: Controls

    func togglePlayPause() async { await control("playpause") }
    func nextTrack() async { await control("next track") }
    func previousTrack() async { await control("previous track") }
    func seek(to seconds: TimeInterval) async { await control("set player position to \(max(0, seconds))") }

    private func control(_ command: String) async {
        guard isRunning else { return }
        do {
            try await runner.run("tell application id \"\(source.bundleID)\" to \(command)")
            try? await Task.sleep(for: .milliseconds(150))
            await refresh()
        } catch let error as AppleScriptError {
            lastError = error.localizedDescription
            if error.isPermissionDenied { permissionDenied = true; lastPermissionFailure = Date() }
            Log.media.error("\(self.source.displayName, privacy: .public) control failed: \(error.localizedDescription, privacy: .public)")
            onUpdate?()
        } catch {}
    }

    // MARK: Artwork

    func fetchArtwork(for track: NowPlayingTrack) async -> NSImage? {
        switch source {
        case .spotify:
            guard let url = track.artworkURL else { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        case .music:
            guard isRunning else { return nil }
            let script = """
            tell application id "com.apple.Music"
                try
                    return data of artwork 1 of current track
                on error
                    return ""
                end try
            end tell
            """
            let data: Data? = try? await runner.run(script) { $0.data.isEmpty ? nil : $0.data }
            return data.flatMap { NSImage(data: $0) }
        }
    }

    // MARK: Scripts

    private var snapshotScript: String {
        switch source {
        case .spotify:
            return """
            try
                tell application id "com.spotify.client"
                    set playerState to (player state as string)
                    if playerState is "stopped" then return {playerState, 0, "", "", "", 0, "", ""}
                    set t to current track
                    return {playerState, player position, name of t, artist of t, album of t, duration of t, artwork url of t, id of t}
                end tell
            on error errMsg number errNum
                if errNum is -1728 then return {"stopped", 0, "", "", "", 0, "", ""}
                error errMsg number errNum
            end try
            """
        case .music:
            return """
            try
                tell application id "com.apple.Music"
                    set playerState to (player state as string)
                    if playerState is "stopped" then return {playerState, 0, "", "", "", 0, "", ""}
                    set pos to 0
                    try
                        set pos to player position
                    end try
                    set t to current track
                    set dur to 0
                    try
                        set dur to duration of t
                    end try
                    set pid to ""
                    try
                        set pid to persistent ID of t
                    end try
                    return {playerState, pos, name of t, artist of t, album of t, dur, "", pid}
                end tell
            on error errMsg number errNum
                if errNum is -1728 then return {"stopped", 0, "", "", "", 0, "", ""}
                error errMsg number errNum
            end try
            """
        }
    }

    nonisolated private static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) -> RawSnapshot? {
        guard descriptor.numberOfItems >= 8 else { return nil }
        func string(_ index: Int) -> String { descriptor.atIndex(index)?.stringValue ?? "" }
        func double(_ index: Int) -> Double {
            guard let item = descriptor.atIndex(index) else { return 0 }
            if let text = item.stringValue, let value = Double(text) { return value }
            return item.doubleValue
        }
        return RawSnapshot(
            state: string(1),
            position: double(2),
            title: string(3),
            artist: string(4),
            album: string(5),
            duration: double(6),
            artworkURL: string(7),
            trackID: string(8)
        )
    }
}

// MARK: - Service

/// Aggregates the providers into one "now playing" state for the UI.
@MainActor
@Observable
final class MediaService {
    private(set) var track: NowPlayingTrack?
    private(set) var playback = PlaybackState.stopped
    private(set) var artwork: NSImage?
    private(set) var artworkTint: Color?
    private(set) var activeSource: MediaSource?
    private(set) var permissionDeniedSources: Set<MediaSource> = []
    private(set) var lastError: String?

    @ObservationIgnored var preferredPlayer: () -> PlayerPreference = { .automatic }
    @ObservationIgnored var onTrackChanged: ((NowPlayingTrack) -> Void)?

    @ObservationIgnored private var providers: [ScriptedMediaProvider] = []
    @ObservationIgnored private var artworkCache: [String: (NSImage, Color?)] = [:]
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    var isPlaying: Bool { track != nil && playback.isPlaying }

    var runningSources: [MediaSource] {
        providers.filter(\.isRunning).map(\.source)
    }

    func start() {
        providers = MediaSource.allCases.map { ScriptedMediaProvider(source: $0) }
        for provider in providers {
            provider.onUpdate = { [weak self] in self?.recompute() }
            provider.start()
        }
    }

    /// Forces a fresh AppleScript round-trip for every running player.
    func refreshNow() {
        providers.filter(\.isRunning).forEach { $0.scheduleRefresh() }
    }

    /// Re-syncs the position of the active player (called sparingly while the panel is open).
    func resyncPosition() async {
        await activeProvider?.refresh()
    }

    func togglePlayPause() { Task { await activeProvider?.togglePlayPause() } }
    func nextTrack() { Task { await activeProvider?.nextTrack() } }
    func previousTrack() { Task { await activeProvider?.previousTrack() } }

    func seek(to seconds: TimeInterval) {
        guard let track else { return }
        let clamped = min(max(0, seconds), track.duration)
        // Optimistic update so the progress bar follows the pointer immediately.
        playback = PlaybackState(isPlaying: playback.isPlaying, position: clamped, capturedAt: Date())
        Task { await activeProvider?.seek(to: clamped) }
    }

    func seek(toFraction fraction: Double) {
        guard let track, track.duration > 0 else { return }
        seek(to: fraction * track.duration)
    }

    private var activeProvider: ScriptedMediaProvider? {
        providers.first { $0.source == activeSource }
    }

    private func recompute() {
        permissionDeniedSources = Set(providers.filter(\.permissionDenied).map(\.source))
        lastError = providers.compactMap(\.lastError).first

        let available = providers.filter { $0.snapshot?.track != nil }
        let chosen: ScriptedMediaProvider? = {
            switch preferredPlayer() {
            case .music:
                if let p = available.first(where: { $0.source == .music }) { return p }
            case .spotify:
                if let p = available.first(where: { $0.source == .spotify }) { return p }
            case .automatic:
                break
            }
            let playing = available.filter { $0.snapshot?.state == .playing }
            if let latestPlaying = playing.max(by: { $0.lastChange < $1.lastChange }) { return latestPlaying }
            return available.max { $0.lastChange < $1.lastChange }
        }()

        guard let chosen, let snapshot = chosen.snapshot, let newTrack = snapshot.track else {
            if track != nil {
                track = nil
                artwork = nil
                artworkTint = nil
                activeSource = nil
                playback = .stopped
            }
            return
        }

        let trackChanged = newTrack.id != track?.id || newTrack.source != track?.source
        activeSource = chosen.source
        track = newTrack
        playback = PlaybackState(isPlaying: snapshot.state == .playing, position: snapshot.position, capturedAt: Date())

        if trackChanged {
            Log.media.notice("now playing: \(newTrack.title, privacy: .public) — \(newTrack.artist, privacy: .public) [\(chosen.source.displayName, privacy: .public)]")
            loadArtwork(for: newTrack, from: chosen)
            onTrackChanged?(newTrack)
        }
    }

    private func loadArtwork(for track: NowPlayingTrack, from provider: ScriptedMediaProvider) {
        artworkTask?.cancel()
        let cacheKey = "\(track.source.rawValue)|\(track.id)"
        if let cached = artworkCache[cacheKey] {
            artwork = cached.0
            artworkTint = cached.1
            return
        }
        artwork = nil
        artworkTint = nil
        artworkTask = Task { [weak self] in
            guard let image = await provider.fetchArtwork(for: track) else { return }
            let tint = await Task.detached(priority: .utility) { image.dominantTint() }.value
            guard !Task.isCancelled, let self, self.track?.id == track.id else { return }
            if artworkCache.count > 12 { artworkCache.removeAll() }
            artworkCache[cacheKey] = (image, tint)
            withAnimation(.easeInOut(duration: 0.35)) {
                self.artwork = image
                self.artworkTint = tint
            }
        }
    }
}

// MARK: - Artwork colour

extension NSImage {
    /// Average colour of the artwork, lifted so it reads well on black.
    nonisolated func dominantTint() -> Color? {
        guard let tiff = tiffRepresentation, let ciImage = CIImage(data: tiff) else { return nil }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let base = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        guard let hsb = base.usingColorSpace(.deviceRGB) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        hsb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let lifted = NSColor(hue: h, saturation: min(1, max(s, 0.35)), brightness: max(b, 0.72), alpha: 1)
        return Color(nsColor: lifted)
    }
}
