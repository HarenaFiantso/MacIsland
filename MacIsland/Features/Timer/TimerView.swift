import SwiftUI

struct TimerView: View {
    @Environment(TimerModel.self) private var timer
    @Environment(IslandViewModel.self) private var island

    var body: some View {
        HStack(spacing: 22) {
            ring
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 10, weight: .semibold))
                    Text("Timer").font(IslandDesign.label(11, .semibold))
                    Spacer()
                    Text(phaseLabel)
                        .font(IslandDesign.label(10))
                        .foregroundStyle(IslandDesign.tertiary)
                }
                .foregroundStyle(IslandDesign.secondary)

                HStack(spacing: 6) {
                    ForEach(TimerModel.presets, id: \.self) { preset in
                        IslandPillButton(
                            title: "\(Int(preset / 60)) min",
                            isSelected: timer.phase == .idle && timer.selectedDuration == preset
                        ) {
                            if timer.phase == .idle {
                                timer.selectedDuration = preset
                            } else {
                                timer.start(duration: preset)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    IslandIconButton(systemName: timer.isRunning ? "pause.fill" : "play.fill", size: 14, frame: 32, filled: true, help: timer.isRunning ? "Pause" : "Start") {
                        timer.toggle()
                    }
                    IslandIconButton(systemName: "arrow.counterclockwise", size: 12, frame: 28, tint: IslandDesign.secondary, help: "Reset") {
                        timer.reset()
                    }
                    IslandPillButton(title: "−1 min") { timer.adjust(by: -60) }
                    IslandPillButton(title: "+1 min") { timer.adjust(by: 60) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ring: some View {
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 0.25 : 3600)) { context in
            let progress = timer.progress(at: context.date)
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
                VStack(spacing: 2) {
                    Text(TimerModel.format(timer.remaining(at: context.date)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(IslandDesign.primary)
                    Text(TimerModel.format(timer.phase == .idle ? timer.selectedDuration : timer.totalDuration))
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(IslandDesign.tertiary)
                }
            }
        }
        .frame(width: 108, height: 108)
        .padding(.leading, 6)
    }

    private var ringColor: Color {
        switch timer.phase {
        case .finished: return IslandDesign.positive
        case .paused: return IslandDesign.warning
        default: return .white
        }
    }

    private var phaseLabel: String {
        switch timer.phase {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .finished: return "Finished"
        }
    }
}
