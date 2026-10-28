import SwiftUI
import IslandCore

/// Full panel: a header band as tall as the notch (tabs on the left wing, status on
/// the right wing, nothing under the physical notch) and the selected module below.
struct ExpandedIslandView: View {
    let model: IslandViewModel
    @EnvironmentObject private var preferences: Preferences
    @Environment(MediaService.self) private var media
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        VStack(spacing: 0) {
            ExpandedHeaderView(model: model)
                .frame(height: model.geometry.notchSize.height)

            ZStack {
                moduleContent
                    .transition(.islandContent(speed: model.animationSpeed))
                    .id(model.selectedTab)
            }
            .padding(.horizontal, IslandDesign.bodyPadding)
            .padding(.top, 6)
            .padding(.bottom, IslandDesign.bodyPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            media.refreshNow()
            if preferences.calendarEnabled { calendar.refreshIfStale() }
            ensureSelectedTabEnabled()
        }
        .onChange(of: enabledTabs) { ensureSelectedTabEnabled() }
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch model.selectedTab {
        case .home: HomeView()
        case .shelf: ShelfView(mode: .full)
        case .calendar: CalendarView()
        case .timer: TimerView()
        }
    }

    private var enabledTabs: [IslandTab] {
        IslandTab.allCases.filter { preferences.isEnabled($0) }
    }

    private func ensureSelectedTabEnabled() {
        if !preferences.isEnabled(model.selectedTab) {
            model.select(.home)
        }
    }
}

extension Preferences {
    func isEnabled(_ tab: IslandTab) -> Bool {
        switch tab {
        case .home: return true
        case .shelf: return shelfEnabled
        case .calendar: return calendarEnabled
        case .timer: return timerEnabled
        }
    }
}

struct ExpandedHeaderView: View {
    let model: IslandViewModel
    @EnvironmentObject private var preferences: Preferences
    @Environment(BatteryService.self) private var battery

    var body: some View {
        let wing = model.metrics.expandedWingWidth
        HStack(spacing: 0) {
            IslandTabBar(model: model)
                .padding(.leading, IslandDesign.bodyPadding - 2)
                .frame(width: wing, alignment: .leading)

            Color.clear
                .frame(width: model.geometry.notchSize.width)

            HStack(spacing: 8) {
                if preferences.batteryEnabled && battery.snapshot.hasBattery {
                    BatteryBadgeView()
                }
                IslandIconButton(systemName: "gearshape.fill", size: 12, frame: 24, tint: IslandDesign.secondary, help: "Settings") {
                    model.send(.close)
                    SettingsOpener.open()
                }
            }
            .padding(.trailing, IslandDesign.bodyPadding - 2)
            .frame(width: wing, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.headerTapped() }
    }
}

struct IslandTabBar: View {
    let model: IslandViewModel
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        HStack(spacing: 2) {
            ForEach(IslandTab.allCases.filter { preferences.isEnabled($0) }) { tab in
                TabButton(tab: tab, isSelected: model.selectedTab == tab) {
                    model.select(tab)
                }
            }
        }
    }

    private struct TabButton: View {
        let tab: IslandTab
        let isSelected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? IslandDesign.primary : IslandDesign.tertiary)
                    .frame(width: 30, height: 22)
                    .background(
                        Capsule().fill(isSelected ? IslandDesign.surfaceHover : (hovering ? IslandDesign.surface : .clear))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(IslandPressStyle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help(tab.title)
        }
    }
}

extension IslandTab {
    var symbolName: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        case .calendar: return "calendar"
        case .timer: return "timer"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .shelf: return "Shelf"
        case .calendar: return "Calendar"
        case .timer: return "Timer"
        }
    }
}

/// Home: media on the left, shelf on the right (NotchNook-style split).
struct HomeView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: IslandDesign.bodyPadding) {
                if preferences.mediaEnabled {
                    MediaPlayerView()
                        .frame(width: preferences.shelfEnabled ? geo.size.width * 0.56 : geo.size.width)
                }
                if preferences.shelfEnabled {
                    ShelfView(mode: .compact)
                        .frame(maxWidth: .infinity)
                }
                if !preferences.mediaEnabled && !preferences.shelfEnabled {
                    VStack(spacing: 6) {
                        Image(systemName: "rectangle.topthird.inset.filled")
                            .font(.system(size: 22))
                            .foregroundStyle(IslandDesign.tertiary)
                        Text("Enable a module in Settings")
                            .font(IslandDesign.label(12))
                            .foregroundStyle(IslandDesign.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
