import EventKit
import SwiftUI
import Observation

@MainActor
@Observable
final class CalendarService {
    struct EventItem: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: Color
        let calendarTitle: String
        let location: String?

        var isHappeningNow: Bool {
            let now = Date()
            return !isAllDay && start <= now && now < end
        }
    }

    private(set) var status: EKAuthorizationStatus = .notDetermined
    private(set) var events: [EventItem] = []
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Called after every refresh (event alerts reschedule from it).
    @ObservationIgnored var onEventsChanged: (() -> Void)?

    var hasAccess: Bool { status == .fullAccess }
    var isDenied: Bool { status == .denied || status == .restricted }

    func start() {
        status = EKEventStore.authorizationStatus(for: .event)
        if hasAccess { refresh() }
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            if !granted, status == .notDetermined {
                // TCC refused without prompting (typically: hardened runtime without the
                // com.apple.security.personal-information.calendars entitlement, or a broken signature).
                lastError = "macOS refused the request without asking. Check the app signature and entitlements."
            } else {
                lastError = nil
            }
            Log.calendar.notice("calendar access \(granted ? "granted" : "denied", privacy: .public)")
            if granted { refresh() }
        } catch {
            lastError = error.localizedDescription
            status = EKEventStore.authorizationStatus(for: .event)
            Log.calendar.error("calendar access failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh() {
        guard hasAccess else {
            events = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay && lhs.startDate <= rhs.startDate ? lhs.startDate < rhs.startDate : rhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
        events = found.prefix(40).map { event in
            EventItem(
                id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                color: event.calendar.cgColor.map { Color(cgColor: $0) } ?? .white,
                calendarTitle: event.calendar.title,
                location: event.location
            )
        }
        lastRefresh = Date()
        onEventsChanged?()
    }

    /// Cheap refresh when the panel opens (EventKit already pushes changes).
    func refreshIfStale(maxAge: TimeInterval = 120) {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < maxAge { return }
        refresh()
    }

    /// Events still relevant: ongoing or upcoming (past ones of today are hidden).
    var upcoming: [EventItem] {
        let now = Date()
        return events.filter { $0.isAllDay ? Calendar.current.isDateInToday($0.start) || $0.start > now : $0.end > now }
    }

    var nextEvent: EventItem? {
        upcoming.first { !$0.isAllDay }
    }
}
