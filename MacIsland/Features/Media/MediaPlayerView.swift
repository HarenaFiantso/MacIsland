import SwiftUI

/// Now-playing card: artwork, title/artist marquee, transport, scrubber.
struct MediaPlayerView: View {
    @Environment(MediaService.self) private var media
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        if let track = media.track {
            player(track)
        } else {
            emptyState
        }
    }

    private func player(_ track: NowPlayingTrack) -> some View {
        GeometryReader { geo in
            let art = min(geo.size.height, 112)
            HStack(alignment: .top, spacing: 14) {
                ArtworkView(image: media.artwork, size: art, cornerRadius: 14)
                    .onTapGesture { openPlayer(track.source) }
                    .help("Open \(track.source.displayName)")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MarqueeText(text: track.title, size: 14, weight: .semibold, color: IslandDesign.primary, height: 18)
                        Image(systemName: track.source.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(IslandDesign.tertiary)
                    }
                    MarqueeText(text: track.artist.isEmpty ? track.album : track.artist, size: 12, weight: .medium, color: IslandDesign.secondary, height: 16)

                    Spacer(minLength: 2)

                    HStack(spacing: 2) {
                        IslandIconButton(systemName: "backward.fill", size: 12, frame: 28, help: "Previous") { media.previousTrack() }
                        IslandIconButton(systemName: media.isPlaying ? "pause.fill" : "play.fill", size: 15, frame: 32, help: media.isPlaying ? "Pause" : "Play") {
                            media.togglePlayPause()
                        }
                        .contentTransition(.symbolEffect(.replace))
                        IslandIconButton(systemName: "forward.fill", size: 12, frame: 28, help: "Next") { media.nextTrack() }
                        Spacer(minLength: 4)
                        if preferences.showVisualizer {
                            AudioBarsView(isPlaying: media.isPlaying, tint: media.artworkTint ?? .white, barCount: 5, height: 16)
                        }
                    }

                    progress(track)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func progress(_ track: NowPlayingTrack) -> some View {
        TimelineView(.periodic(from: .now, by: media.isPlaying ? 0.25 : 3600)) { context in
            let position = min(max(0, media.playback.position(at: context.date)), max(track.duration, 0))
            let fraction = track.duration > 0 ? position / track.duration : 0
            VStack(spacing: 1) {
                IslandProgressBar(progress: fraction, tint: media.artworkTint ?? .white) { media.seek(toFraction: $0) }
                HStack {
                    Text(TimerModel.format(position))
                    Spacer()
                    Text("-" + TimerModel.format(max(0, track.duration - position)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandDesign.tertiary)
            }
        }
        .task(id: media.isPlaying) {
            // While the panel is open and playing, re-sync against the player every 5 s
            // (the position is extrapolated in between at 4 Hz — sub-pixel steps, so no
            // continuous SwiftUI animation is needed; no polling otherwise).
            guard media.isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await media.resyncPosition()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(IslandDesign.tertiary)
            Text("Nothing playing")
                .font(IslandDesign.label(13, .semibold))
                .foregroundStyle(IslandDesign.secondary)
            if !media.permissionDeniedSources.isEmpty {
                let names = media.permissionDeniedSources.map(\.displayName).sorted().joined(separator: ", ")
                Text("Automation denied for \(names)")
                    .font(IslandDesign.label(10.5))
                    .foregroundStyle(IslandDesign.tertiary)
                IslandPillButton(title: "Open Privacy Settings", systemImage: "lock.shield") {
                    PrivacyPane.automation.open()
                }
            } else if media.runningSources.isEmpty {
                Text("Open Music or Spotify")
                    .font(IslandDesign.label(10.5))
                    .foregroundStyle(IslandDesign.tertiary)
            } else {
                let names = media.runningSources.map(\.displayName).joined(separator: " or ")
                Text("Play something in \(names)")
                    .font(IslandDesign.label(10.5))
                    .foregroundStyle(IslandDesign.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPlayer(_ source: MediaSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Deep links into System Settings › Privacy & Security.
enum PrivacyPane: String {
    case automation = "Privacy_Automation"
    case calendars = "Privacy_Calendars"
    case notifications = "Notifications"

    func open() {
        let path = self == .notifications
            ? "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            : "x-apple.systempreferences:com.apple.preference.security?\(rawValue)"
        if let url = URL(string: path) { NSWorkspace.shared.open(url) }
    }
}
