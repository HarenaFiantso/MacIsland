import Foundation

/// Decides whether a volume change deserves the feedback "pop".
///
/// Mirrors what macOS does for its own key feedback: one sound per discrete step
/// (the volume keys move by 1/16), nothing while muted, and never more than about
/// twelve sounds per second — a slider drag produces dozens of tiny changes that
/// must not turn into a machine-gun.
public struct VolumeFeedbackGate: Equatable, Sendable {
    public var minimumInterval: TimeInterval
    public var minimumStep: Float
    private var lastPlayed: Date?

    public init(minimumInterval: TimeInterval = 0.08, minimumStep: Float = 1.0 / 16 - 0.004) {
        self.minimumInterval = minimumInterval
        self.minimumStep = minimumStep
    }

    /// True when a sound should play for the transition `old → new`.
    public mutating func shouldPlay(old: Float, new: Float, muted: Bool, at date: Date = Date()) -> Bool {
        guard !muted, abs(new - old) >= minimumStep else { return false }
        if let lastPlayed, date.timeIntervalSince(lastPlayed) < minimumInterval { return false }
        lastPlayed = date
        return true
    }
}
