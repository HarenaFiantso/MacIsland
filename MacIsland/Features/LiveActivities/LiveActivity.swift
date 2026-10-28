import SwiftUI

enum LiveActivityKind: Equatable {
    case nowPlaying
    case volume
    case battery
    case charging
    case lowBattery
    case lowPower
    case timer
    case timerFinished
    case shelfDrop
    case calendarEvent
    case unlocked
    /// The launch "Hello": a bubble under the notch rather than two wings.
    case greeting

    /// Width of each wing (left and right of the notch) while the activity shows.
    var wingWidth: CGFloat {
        switch self {
        case .nowPlaying: return 48
        case .volume: return 82
        case .battery, .charging, .lowBattery: return 62
        case .lowPower: return 74
        case .timer: return 66
        case .timerFinished: return 64
        case .shelfDrop: return 56
        case .calendarEvent: return 98
        case .unlocked: return 70
        case .greeting: return 56
        }
    }

    /// Extra height below the notch band (the greeting hangs under the notch).
    var extraHeight: CGFloat {
        switch self {
        case .greeting: return 40
        default: return 0
        }
    }
}

/// A transient (or sticky) piece of context displayed in the collapsed island's wings.
struct LiveActivity: Identifiable, Equatable {
    enum Payload: Equatable {
        case none
        case nowPlaying(trackID: String)
        case volume(level: Float, muted: Bool)
        case battery(level: Int, charging: Bool, pluggedIn: Bool)
        case count(Int)
        case text(String)
        case event(title: String, tint: Color)
    }

    var id = UUID()
    let kind: LiveActivityKind
    let isSticky: Bool
    /// nil = stays until dismissed (sticky activities such as the timer).
    let duration: TimeInterval?
    var payload: Payload
    let createdAt = Date()

    init(kind: LiveActivityKind, isSticky: Bool = false, duration: TimeInterval?, payload: Payload = .none) {
        self.kind = kind
        self.isSticky = isSticky
        self.duration = duration
        self.payload = payload
    }

    /// Seconds the greeting stays on screen (the jingle lasts about as long).
    static let greetingDuration: TimeInterval = 5.2
}
