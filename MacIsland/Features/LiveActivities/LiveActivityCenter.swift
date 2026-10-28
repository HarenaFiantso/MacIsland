import SwiftUI
import Observation

/// Single source of truth for what the collapsed island is currently announcing.
///
/// Policy: one *transient* activity at a time (a newer one replaces the older one;
/// same-kind replacements keep their identity so only the payload animates) layered
/// on top of at most one *sticky* activity (e.g. a running timer) that comes back
/// once the transient one expires.
@MainActor
@Observable
final class LiveActivityCenter {
    enum Phase { case willChange, didChange }

    private(set) var current: LiveActivity?

    @ObservationIgnored var animationSpeed: () -> Double = { 1 }
    @ObservationIgnored private var transient: LiveActivity?
    @ObservationIgnored private var sticky: LiveActivity?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [UUID: (Phase, LiveActivity?) -> Void] = [:]

    func addObserver(_ observer: @escaping (Phase, LiveActivity?) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func present(_ activity: LiveActivity) {
        var activity = activity
        if activity.isSticky {
            if let sticky, sticky.kind == activity.kind { activity.id = sticky.id }
            sticky = activity
        } else {
            if let transient, transient.kind == activity.kind { activity.id = transient.id }
            transient = activity
            scheduleExpiry(for: activity)
        }
        publish()
    }

    func dismissSticky(kind: LiveActivityKind) {
        guard sticky?.kind == kind else { return }
        sticky = nil
        publish()
    }

    func dismissTransient() {
        expiryTask?.cancel()
        transient = nil
        publish()
    }

    /// Dismisses the transient activity only if it is of `kind`.
    func dismissTransient(kind: LiveActivityKind) {
        guard transient?.kind == kind else { return }
        dismissTransient()
    }

    func dismissAll() {
        expiryTask?.cancel()
        transient = nil
        sticky = nil
        publish()
    }

    private func scheduleExpiry(for activity: LiveActivity) {
        expiryTask?.cancel()
        guard let duration = activity.duration else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            if transient?.id == activity.id {
                transient = nil
                publish()
            }
        }
    }

    private func publish() {
        let next = transient ?? sticky
        guard next != current else { return }
        observers.values.forEach { $0(.willChange, next) }
        withAnimation(IslandMotion.activity(speed: animationSpeed())) {
            current = next
        }
        observers.values.forEach { $0(.didChange, next) }
    }
}
