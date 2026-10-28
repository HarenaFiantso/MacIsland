import AppKit
import Observation

@MainActor
@Observable
final class TimerModel {
    enum Phase: Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    static let presets: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60, 25 * 60, 45 * 60]
    private static let durationKey = "macisland.timer.lastDuration"

    private(set) var phase: Phase = .idle
    private(set) var totalDuration: TimeInterval
    /// Duration armed for the next start (editable while idle).
    var selectedDuration: TimeInterval {
        didSet { UserDefaults.standard.set(selectedDuration, forKey: Self.durationKey) }
    }

    @ObservationIgnored var onPhaseChanged: ((Phase) -> Void)?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.durationKey)
        let initial = stored > 0 ? stored : 10 * 60
        selectedDuration = initial
        totalDuration = initial
    }

    var isActive: Bool {
        switch phase {
        case .running, .paused: return true
        default: return false
        }
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func remaining(at date: Date = Date()) -> TimeInterval {
        switch phase {
        case .idle: return selectedDuration
        case .running(let endsAt): return max(0, endsAt.timeIntervalSince(date))
        case .paused(let remaining): return remaining
        case .finished: return 0
        }
    }

    /// 0 → 1 as the timer elapses.
    func progress(at date: Date = Date()) -> Double {
        switch phase {
        case .idle: return 0
        case .finished: return 1
        default:
            guard totalDuration > 0 else { return 0 }
            return min(1, max(0, 1 - remaining(at: date) / totalDuration))
        }
    }

    func start(duration: TimeInterval? = nil) {
        let d = max(1, duration ?? selectedDuration)
        selectedDuration = d
        totalDuration = d
        resetTask?.cancel()
        setPhase(.running(endsAt: Date().addingTimeInterval(d)))
        scheduleCompletion(after: d)
        Task { _ = await NotificationService.shared.requestAuthorizationIfNeeded() }
    }

    func pause() {
        guard case .running(let endsAt) = phase else { return }
        completionTask?.cancel()
        setPhase(.paused(remaining: max(0, endsAt.timeIntervalSinceNow)))
    }

    func resume() {
        guard case .paused(let remaining) = phase else { return }
        setPhase(.running(endsAt: Date().addingTimeInterval(remaining)))
        scheduleCompletion(after: remaining)
    }

    func toggle() {
        switch phase {
        case .idle, .finished: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    func reset() {
        completionTask?.cancel()
        resetTask?.cancel()
        setPhase(.idle)
    }

    func adjust(by delta: TimeInterval) {
        switch phase {
        case .idle:
            selectedDuration = min(max(60, selectedDuration + delta), 12 * 3600)
        case .running(let endsAt):
            let newEnd = max(Date().addingTimeInterval(1), endsAt.addingTimeInterval(delta))
            totalDuration = max(1, totalDuration + delta)
            setPhase(.running(endsAt: newEnd))
            scheduleCompletion(after: newEnd.timeIntervalSinceNow)
        case .paused(let remaining):
            totalDuration = max(1, totalDuration + delta)
            setPhase(.paused(remaining: max(1, remaining + delta)))
        case .finished:
            break
        }
    }

    private func scheduleCompletion(after seconds: TimeInterval) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        setPhase(.finished)
        NSSound(named: "Glass")?.play()
        let total = Self.format(totalDuration)
        Task {
            await NotificationService.shared.post(title: "Timer finished", body: "\(total) elapsed", identifier: "macisland.timer")
        }
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, case .finished = self.phase else { return }
            self.setPhase(.idle)
        }
    }

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        onPhaseChanged?(newPhase)
    }

    nonisolated static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
