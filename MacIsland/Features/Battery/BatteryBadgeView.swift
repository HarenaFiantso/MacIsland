import SwiftUI

/// Compact battery read-out for the expanded header.
struct BatteryBadgeView: View {
    @Environment(BatteryService.self) private var battery

    var body: some View {
        let s = battery.snapshot
        HStack(spacing: 4) {
            Text("\(s.level)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(IslandDesign.secondary)
            Image(systemName: s.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color(for: s))
                .contentTransition(.symbolEffect(.replace))
        }
        .help(helpText(s))
    }

    private func color(for s: BatterySnapshot) -> Color {
        if s.isCharging || (s.isPluggedIn && s.isCharged) { return IslandDesign.positive }
        if s.level <= 10 { return IslandDesign.negative }
        if s.level <= 20 { return IslandDesign.warning }
        return IslandDesign.secondary
    }

    private func helpText(_ s: BatterySnapshot) -> String {
        var parts: [String] = []
        parts.append(s.isPluggedIn ? (s.isCharged ? "Charged" : (s.isCharging ? "Charging" : "On power adapter, not charging")) : "On battery")
        if let estimate = s.estimateText { parts.append(estimate) }
        if let watts = s.adapterWatts, s.isPluggedIn { parts.append("\(watts) W adapter") }
        return parts.joined(separator: " · ")
    }
}
