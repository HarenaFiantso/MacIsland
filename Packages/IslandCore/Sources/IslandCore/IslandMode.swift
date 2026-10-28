import Foundation

/// The three visual states of the island.
public enum IslandMode: String, Equatable, Sendable, Codable {
    /// Flush with the notch. May host a live activity in its wings.
    case collapsed
    /// Slightly enlarged while the pointer rests on the notch.
    case peek
    /// Fully open panel.
    case expanded
}

/// Modules reachable from the expanded panel.
public enum IslandTab: String, CaseIterable, Codable, Sendable, Identifiable {
    case home, shelf, calendar, timer
    public var id: String { rawValue }
}

/// Behaviour knobs the state machine needs (mirrors user preferences).
public struct IslandBehavior: Equatable, Sendable {
    public var openOnHover: Bool
    public var peekOnHover: Bool
    public var shelfEnabled: Bool

    public init(openOnHover: Bool = true, peekOnHover: Bool = true, shelfEnabled: Bool = true) {
        self.openOnHover = openOnHover
        self.peekOnHover = peekOnHover
        self.shelfEnabled = shelfEnabled
    }
}

/// Everything that can happen to the island.
public enum IslandEvent: Equatable, Sendable {
    case hoverChanged(Bool)
    case hoverOpenTimerFired
    case closeTimerFired
    /// Click on the island itself (collapsed/peek body, or expanded header).
    case tapped
    /// Click anywhere else on screen.
    case tappedOutside
    case dragEntered
    case dragExited
    case dropPerformed
    case open(IslandTab?)
    case close
    case toggle
    case escape
    case behaviorChanged(IslandBehavior)
}

public enum CloseDelay: Equatable, Sendable {
    case standard
    case afterDrop
}

/// Side effects the host must perform after a transition (timers, tab selection).
public enum IslandEffect: Equatable, Sendable {
    case scheduleHoverOpen
    case cancelHoverOpen
    case scheduleClose(CloseDelay)
    case cancelClose
    case selectTab(IslandTab)
}
