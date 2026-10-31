import AppKit
import SwiftUI
import Observation
import CoreImage

// MARK: - Model

enum MediaSource: String, CaseIterable, Sendable, Identifiable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"
    case lyrify = "com.lyrify.lyrify"

    var id: String { rawValue }
    var bundleID: String { rawValue }

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .lyrify: return "Lyrify"
        }
    }

    var symbolName: String {
        switch self {
        case .music: return "music.note"
        case .spotify: return "waveform"
        case .lyrify: return "music.mic"
        }
    }

    /// Distributed notification each player posts when playback changes (public mechanism).
    var playbackNotificationName: Notification.Name {
        switch self {
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .lyrify: return Notification.Name("com.lyrify.lyrify.nowPlaying")
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

// MARK: - Provider

/// One player, as `MediaService` sees it: what it plays now, and its transport.
@MainActor
protocol MediaProvider: AnyObject {
    var source: MediaSource { get }
    var snapshot: ProviderSnapshot? { get }
    var lastChange: Date { get }
    var permissionDenied: Bool { get }
    var lastError: String? { get }
    var onUpdate: (() -> Void)? { get set }
    var isRunning: Bool { get }

    func start()
    func stop()
    func scheduleRefresh()
    func refresh() async
    func togglePlayPause() async
    func nextTrack() async
    func previousTrack() async
    func seek(to seconds: TimeInterval) async
    func fetchArtwork(for track: NowPlayingTrack) async -> NSImage?
}

extension MediaProvider {
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }
}

// MARK: - Scripted provider (AppleScript + distributed notifications)

/// One player (Music or Spotify). Entirely event-driven: the player's distributed
/// notification triggers a single AppleScript round-trip; nothing polls while idle.
@MainActor
final class ScriptedMediaProvider: MediaProvider {
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
        precondition(source != .lyrify, "Lyrify has no scripting dictionary: see LyrifyMediaProvider")
        self.source = source
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
        case .spotify, .lyrify:
            return await NSImage.download(track.artworkURL)
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
        case .lyrify:
            preconditionFailure("Lyrify has no scripting dictionary: see LyrifyMediaProvider")
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

// MARK: - Lyrify provider (distributed notifications both ways)

/// Lyrify, a Flutter player with no scripting dictionary. It is sandboxed, and a
/// sandboxed app may only post distributed notifications without a userInfo, so both
/// directions carry their payload in the notification's object string: Lyrify posts
/// its state as JSON on `com.lyrify.lyrify.nowPlaying` whenever the track, play/pause
/// or the position (a seek) changes, and the island posts its commands — `playpause`,
/// `next`, `previous`, `seek:<seconds>`, `refresh` — on `com.lyrify.lyrify.command`.
@MainActor
final class LyrifyMediaProvider: MediaProvider {
    let source = MediaSource.lyrify
    private(set) var snapshot: ProviderSnapshot?
    private(set) var lastChange = Date.distantPast
    let permissionDenied = false
    private(set) var lastError: String?
    var onUpdate: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private static let commandNotificationName = Notification.Name("com.lyrify.lyrify.command")

    /// What Lyrify says; times in seconds.
    private struct Payload: Decodable {
        var state: String
        var position: Double
        var duration: Double
        var id: String
        var title: String
        var artist: String
        var album: String
        var artwork: String?
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: source.playbackNotificationName, object: nil, queue: .main) { [weak self] note in
            let json = note.object as? String
            Task { @MainActor in self?.receive(json) }
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

        // Lyrify says what it plays as soon as its player is up: nothing to ask at launch.
        if isRunning { send("refresh") }
    }

    func stop() {
        observers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    func scheduleRefresh() { send("refresh") }

    /// The answer comes back as a `nowPlaying` notification.
    func refresh() async { send("refresh") }

    // Lyrify posts its new state itself after each command.
    func togglePlayPause() async { send("playpause") }
    func nextTrack() async { send("next") }
    func previousTrack() async { send("previous") }
    func seek(to seconds: TimeInterval) async { send("seek:\(max(0, seconds))") }

    func fetchArtwork(for track: NowPlayingTrack) async -> NSImage? {
        await NSImage.download(track.artworkURL)
    }

    private func send(_ command: String) {
        guard isRunning else { clear(); return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.commandNotificationName, object: command, userInfo: nil, deliverImmediately: true
        )
    }

    private func receive(_ json: String?) {
        guard let data = json?.data(using: .utf8) else { return }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            lastError = "Lyrify: unreadable state (\(error.localizedDescription))"
            Log.media.error("Lyrify: unreadable state: \(error.localizedDescription, privacy: .public)")
            onUpdate?()
            return
        }
        lastError = nil
        let state = PlayerState(rawValue: payload.state) ?? .stopped
        guard state != .stopped, !payload.title.isEmpty else { clear(); return }
        let track = NowPlayingTrack(
            id: payload.id.isEmpty ? "\(payload.title)|\(payload.artist)" : payload.id,
            title: payload.title,
            artist: payload.artist,
            album: payload.album,
            duration: max(0, payload.duration),
            source: source,
            artworkURL: payload.artwork.flatMap(URL.init(string:))
        )
        let new = ProviderSnapshot(state: state, position: max(0, payload.position), track: track)
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
    /// The artwork's dominant colours, most prominent first (empty until the artwork loads).
    private(set) var artworkPalette: [Color] = []
    private(set) var activeSource: MediaSource?
    private(set) var permissionDeniedSources: Set<MediaSource> = []
    private(set) var lastError: String?

    @ObservationIgnored var preferredPlayer: () -> PlayerPreference = { .automatic }
    @ObservationIgnored var onTrackChanged: ((NowPlayingTrack) -> Void)?

    @ObservationIgnored private var providers: [any MediaProvider] = []
    @ObservationIgnored private var artworkCache: [String: (NSImage, Color?, [Color])] = [:]
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    var isPlaying: Bool { track != nil && playback.isPlaying }

    var runningSources: [MediaSource] {
        providers.filter(\.isRunning).map(\.source)
    }

    func start() {
        providers = [
            ScriptedMediaProvider(source: .music),
            ScriptedMediaProvider(source: .spotify),
            LyrifyMediaProvider(),
        ]
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

    private var activeProvider: (any MediaProvider)? {
        providers.first { $0.source == activeSource }
    }

    private func recompute() {
        permissionDeniedSources = Set(providers.filter(\.permissionDenied).map(\.source))
        lastError = providers.compactMap(\.lastError).first

        let available = providers.filter { $0.snapshot?.track != nil }
        let chosen: (any MediaProvider)? = {
            if let preferred = preferredPlayer().source,
               let p = available.first(where: { $0.source == preferred }) {
                return p
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
                artworkPalette = []
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

    private func loadArtwork(for track: NowPlayingTrack, from provider: any MediaProvider) {
        artworkTask?.cancel()
        let cacheKey = "\(track.source.rawValue)|\(track.id)"
        if let cached = artworkCache[cacheKey] {
            artwork = cached.0
            artworkTint = cached.1
            artworkPalette = cached.2
            return
        }
        artwork = nil
        artworkTint = nil
        artworkPalette = []
        artworkTask = Task { [weak self] in
            guard let image = await provider.fetchArtwork(for: track) else { return }
            let (tint, palette) = await Task.detached(priority: .utility) {
                (image.dominantTint(), image.dominantPalette())
            }.value
            guard !Task.isCancelled, let self, self.track?.id == track.id else { return }
            if artworkCache.count > 12 { artworkCache.removeAll() }
            artworkCache[cacheKey] = (image, tint, palette)
            withAnimation(.easeInOut(duration: 0.35)) {
                self.artwork = image
                self.artworkTint = tint
                self.artworkPalette = palette
            }
        }
    }
}

// MARK: - Artwork colour

extension NSImage {
    /// The artwork behind an HTTPS URL (Spotify, Lyrify).
    static func download(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

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

    /// The artwork's dominant colours, most prominent first: the most populated
    /// hue/saturation/brightness buckets of a 32 × 32 downsample, colourful ones first,
    /// lifted so they glow on black. Greys only fill in when the cover has nothing else.
    nonisolated func dominantPalette(count: Int = 3) -> [Color] {
        guard let tiff = tiffRepresentation, let ciImage = CIImage(data: tiff) else { return [] }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return [] }
        let side = 32
        let scaled = ciImage
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(side) / extent.width, y: CGFloat(side) / extent.height))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(scaled, toBitmap: &pixels, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side), format: .RGBA8, colorSpace: nil)

        struct Bucket { var count = 0; var r = 0.0, g = 0.0, b = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[offset]) / 255, g = Double(pixels[offset + 1]) / 255, b = Double(pixels[offset + 2]) / 255
            let (h, s, v) = Self.hsv(r, g, b)
            if v < 0.1 { continue } // near-black: that is the island's own background
            let key = s < 0.14 ? 1000 + Int(v * 3) : Int(h * 12) * 9 + Int(s * 3) * 3 + Int(v * 3)
            buckets[key, default: Bucket()].count += 1
            buckets[key, default: Bucket()].r += r
            buckets[key, default: Bucket()].g += g
            buckets[key, default: Bucket()].b += b
        }
        guard !buckets.isEmpty else { return [] }

        let averaged: [(count: Int, h: Double, s: Double, v: Double)] = buckets.values.map { bucket in
            let n = Double(bucket.count)
            let (h, s, v) = Self.hsv(bucket.r / n, bucket.g / n, bucket.b / n)
            return (bucket.count, h, s, v)
        }
        // Colourful buckets rank above greys of the same size.
        let ranked = averaged.sorted { Double($0.count) * (0.2 + $0.s) > Double($1.count) * (0.2 + $1.s) }

        var chosen: [(h: Double, s: Double, v: Double)] = []
        for candidate in ranked where chosen.count < count {
            // Same hue family counts once, unless it is a clearly lighter or darker variant.
            let tooClose = chosen.contains { picked in
                let hueGap = abs(picked.h - candidate.h)
                let sameHue = min(hueGap, 1 - hueGap) < 0.06
                let bothGrey = picked.s < 0.14 && candidate.s < 0.14
                return (sameHue && !bothGrey && abs(picked.v - candidate.v) < 0.5) || (bothGrey && abs(picked.v - candidate.v) < 0.3)
            }
            if !tooClose { chosen.append((candidate.h, candidate.s, candidate.v)) }
        }
        return chosen.map { c in
            // Greys stay dim (a fog, not a floodlight); colours are lifted so they glow.
            let grey = c.s < 0.14
            return Color(nsColor: NSColor(
                hue: c.h,
                saturation: grey ? c.s : min(1, max(c.s, 0.45)),
                brightness: grey ? min(max(c.v, 0.35), 0.55) : max(c.v, 0.6),
                alpha: 1
            ))
        }
    }

    nonisolated private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0.0001 {
            if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = maxC > 0 ? delta / maxC : 0
        return (h, s, maxC)
    }
}
