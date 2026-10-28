import SwiftUI
import EventKit

struct CalendarView: View {
    @Environment(CalendarService.self) private var calendar

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let month: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    private static let shortDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d"; return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            dateColumn
                .frame(width: 92, alignment: .leading)
            Rectangle()
                .fill(IslandDesign.separator)
                .frame(width: 1)
                .padding(.vertical, 2)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var dateColumn: some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: 0) {
            Text(Self.weekday.string(from: now).uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(IslandDesign.negative)
            Text("\(Calendar.current.component(.day, from: now))")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(IslandDesign.primary)
                .padding(.top, -4)
            Text(Self.month.string(from: now))
                .font(IslandDesign.label(11))
                .foregroundStyle(IslandDesign.secondary)
            Spacer(minLength: 0)
            if calendar.hasAccess {
                let count = calendar.upcoming.count
                Text(count == 0 ? "No events" : "\(count) upcoming")
                    .font(IslandDesign.label(10))
                    .foregroundStyle(IslandDesign.tertiary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !calendar.hasAccess {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text(calendar.isDenied ? "Calendar access denied" : "Calendar access needed")
                }
                .font(IslandDesign.label(12, .semibold))
                .foregroundStyle(IslandDesign.secondary)
                Text("MacIsland reads your events locally to show what is next.")
                    .font(IslandDesign.label(10.5))
                    .foregroundStyle(IslandDesign.tertiary)
                if calendar.isDenied {
                    IslandPillButton(title: "Open Privacy Settings", systemImage: "lock.shield") { PrivacyPane.calendars.open() }
                } else {
                    IslandPillButton(title: "Allow Access", systemImage: "checkmark", prominent: true) {
                        Task { await calendar.requestAccess() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if calendar.upcoming.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(IslandDesign.tertiary)
                Text("Nothing scheduled for the next 7 days")
                    .font(IslandDesign.label(11.5))
                    .foregroundStyle(IslandDesign.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(calendar.upcoming) { event in
                        EventRow(event: event, timeText: timeText(for: event))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func timeText(for event: CalendarService.EventItem) -> String {
        let cal = Calendar.current
        let dayLabel: String
        if cal.isDateInToday(event.start) {
            dayLabel = "Today"
        } else if cal.isDateInTomorrow(event.start) {
            dayLabel = "Tomorrow"
        } else {
            dayLabel = Self.shortDay.string(from: event.start)
        }
        if event.isAllDay { return "\(dayLabel) · All day" }
        return "\(dayLabel) · \(Self.time.string(from: event.start)) – \(Self.time.string(from: event.end))"
    }
}

private struct EventRow: View {
    let event: CalendarService.EventItem
    let timeText: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(IslandDesign.label(12, .semibold))
                    .foregroundStyle(IslandDesign.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timeText)
                    if let location = event.location, !location.isEmpty {
                        Text("· \(location)").lineLimit(1)
                    }
                }
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandDesign.secondary)
            }
            Spacer(minLength: 0)
            if event.isHappeningNow {
                Text("Now")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IslandDesign.positive)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(IslandDesign.positive.opacity(0.22)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? IslandDesign.surface : Color.clear)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
