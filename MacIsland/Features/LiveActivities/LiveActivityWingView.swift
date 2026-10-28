import SwiftUI

enum WingSide { case leading, trailing }

/// Routes the collapsed island's wing content to the right activity view.
struct LiveActivityWingView: View {
    let content: IslandViewModel.WingsContent
    let side: WingSide

    var body: some View {
        switch content {
        case .none:
            EmptyView()
        case .nowPlaying:
            NowPlayingWing(side: side)
        case .activity(let activity):
            switch activity.kind {
            case .nowPlaying:
                NowPlayingWing(side: side)
            case .volume:
                if case .volume(let level, let muted) = activity.payload {
                    VolumeWing(side: side, level: level, muted: muted)
                }
            case .battery, .charging, .lowBattery:
                if case .battery(let level, let charging, let pluggedIn) = activity.payload {
                    BatteryWing(side: side, kind: activity.kind, level: level, charging: charging, pluggedIn: pluggedIn)
                }
            case .timer:
                TimerWing(side: side)
            case .timerFinished:
                TimerFinishedWing(side: side)
            case .shelfDrop:
                if case .count(let count) = activity.payload {
                    ShelfDropWing(side: side, count: count)
                }
            }
        }
    }
}

// MARK: - Now playing

struct NowPlayingWing: View {
    let side: WingSide
    @Environment(MediaService.self) private var media

    var body: some View {
        switch side {
        case .leading:
            ArtworkView(image: media.artwork, size: 22, cornerRadius: 5)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .trailing:
            AudioBarsView(isPlaying: media.isPlaying, tint: media.artworkTint ?? .white, barCount: 4, height: 15)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Volume

struct VolumeWing: View {
    let side: WingSide
    let level: Float
    let muted: Bool

    private var symbol: String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        switch side {
        case .leading:
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(muted ? IslandDesign.secondary : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, alignment: .center)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .trailing:
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(muted ? IslandDesign.secondary : .white)
                    .frame(width: 60 * CGFloat(muted ? 0 : level))
            }
            .frame(width: 60, height: 4)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: level)
            .animation(.easeOut(duration: 0.15), value: muted)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Battery

struct BatteryWing: View {
    let side: WingSide
    let kind: LiveActivityKind
    let level: Int
    let charging: Bool
    let pluggedIn: Bool

    private var color: Color {
        switch kind {
        case .charging: return IslandDesign.positive
        case .lowBattery: return IslandDesign.negative
        default: return level <= 20 ? IslandDesign.warning : .white
        }
    }

    private var symbol: String {
        switch kind {
        case .charging: return "bolt.fill"
        case .lowBattery: return "battery.25percent"
        default: return BatterySnapshot(hasBattery: true, level: level, isCharging: charging, isPluggedIn: pluggedIn).symbolName
        }
    }

    var body: some View {
        switch side {
        case .leading:
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .trailing:
            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Timer

struct TimerWing: View {
    let side: WingSide
    @Environment(TimerModel.self) private var timer

    var body: some View {
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 0.5 : 60)) { context in
            switch side {
            case .leading:
                ZStack {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: context.date))
                        .stroke(timer.isRunning ? Color.white : IslandDesign.warning, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .trailing:
                Text(TimerModel.format(timer.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timer.isRunning ? .white : IslandDesign.warning)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct TimerFinishedWing: View {
    let side: WingSide

    var body: some View {
        switch side {
        case .leading:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IslandDesign.positive)
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .trailing:
            Text("Done")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandDesign.positive)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Shelf

struct ShelfDropWing: View {
    let side: WingSide
    let count: Int

    var body: some View {
        switch side {
        case .leading:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .trailing:
            Text("+\(count)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
