import Foundation

/// Announces calendar events as they start: a live activity in the notch and the
/// `event` sound (Alcove's "Play sound on calendar event"). Re-arms itself from the
/// calendar service after every refresh, so edits in Calendar.app are honoured.
@MainActor
final class CalendarAlertScheduler {
    private unowned let preferences: Preferences
    private unowned let calendar: CalendarService
    private unowned let activities: LiveActivityCenter
    private unowned let sound: SoundService
    private var task: Task<Void, Never>?
    private var announced: Set<String> = []

    init(preferences: Preferences, calendar: CalendarService, activities: LiveActivityCenter, sound: SoundService) {
        self.preferences = preferences
        self.calendar = calendar
        self.activities = activities
        self.sound = sound
    }

    func start() {
        calendar.onEventsChanged = { [weak self] in self?.reschedule() }
        reschedule()
    }

    func reschedule() {
        task?.cancel()
        task = nil
        guard preferences.calendarEnabled, preferences.calendarEventActivityEnabled || preferences.calendarEventSound else { return }
        let now = Date()
        guard let next = calendar.events.first(where: { !$0.isAllDay && $0.start > now.addingTimeInterval(-2) && !announced.contains($0.id) }) else { return }
        let delay = max(0, next.start.timeIntervalSince(now))
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // After a long system sleep the timer fires late; skip stale events.
            if abs(Date().timeIntervalSince(next.start)) < 120 { announce(next) } else { announced.insert(next.id) }
            reschedule()
        }
    }

    private func announce(_ event: CalendarService.EventItem) {
        announced.insert(event.id)
        Log.calendar.notice("event starting: \(event.title, privacy: .public)")
        if preferences.calendarEventActivityEnabled {
            activities.present(LiveActivity(
                kind: .calendarEvent,
                duration: max(preferences.liveActivityDuration, 6),
                payload: .event(title: event.title, tint: event.color)
            ))
        }
        sound.play(.event, if: preferences.calendarEventSound)
    }
}
