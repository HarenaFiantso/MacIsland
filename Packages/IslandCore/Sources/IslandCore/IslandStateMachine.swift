import Foundation

/// Pure, synchronous state machine driving the island.
///
/// It owns no timers: it *asks* the host to schedule/cancel them through
/// `IslandEffect`s, which keeps every transition deterministic and testable.
public struct IslandStateMachine: Equatable, Sendable {
    public private(set) var mode: IslandMode = .collapsed
    public private(set) var isHovering = false
    public private(set) var isDragging = false
    public private(set) var behavior: IslandBehavior

    public init(behavior: IslandBehavior = IslandBehavior()) {
        self.behavior = behavior
    }

    @discardableResult
    public mutating func handle(_ event: IslandEvent) -> [IslandEffect] {
        switch event {
        case .hoverChanged(let hovering):
            return handleHover(hovering)

        case .hoverOpenTimerFired:
            guard mode == .peek, isHovering, behavior.openOnHover else { return [] }
            mode = .expanded
            return [.cancelClose]

        case .closeTimerFired:
            guard mode == .expanded, !isHovering, !isDragging else { return [] }
            mode = .collapsed
            return []

        case .tapped:
            switch mode {
            case .collapsed, .peek:
                mode = .expanded
                return [.cancelHoverOpen, .cancelClose]
            case .expanded:
                // Closing while the pointer is still inside: stay collapsed until the
                // pointer leaves and re-enters (no hoverChanged(true) will fire before).
                mode = .collapsed
                isDragging = false
                return [.cancelHoverOpen, .cancelClose]
            }

        case .tappedOutside:
            guard mode == .expanded else { return [] }
            mode = .collapsed
            isDragging = false
            return [.cancelHoverOpen, .cancelClose]

        case .dragEntered:
            isDragging = true
            guard behavior.shelfEnabled else { return [] }
            var effects: [IslandEffect] = [.cancelClose, .cancelHoverOpen, .selectTab(.shelf)]
            if mode != .expanded {
                mode = .expanded
            }
            effects.append(.cancelClose)
            return dedupe(effects)

        case .dragExited:
            isDragging = false
            if mode == .expanded && !isHovering {
                return [.scheduleClose(.standard)]
            }
            return []

        case .dropPerformed:
            isDragging = false
            if mode == .expanded && !isHovering {
                return [.scheduleClose(.afterDrop)]
            }
            return []

        case .open(let tab):
            mode = .expanded
            var effects: [IslandEffect] = [.cancelHoverOpen, .cancelClose]
            if let tab { effects.append(.selectTab(tab)) }
            return effects

        case .close, .escape:
            guard mode != .collapsed else { return [.cancelHoverOpen, .cancelClose] }
            mode = .collapsed
            isDragging = false
            return [.cancelHoverOpen, .cancelClose]

        case .toggle:
            if mode == .expanded {
                mode = .collapsed
                isDragging = false
            } else {
                mode = .expanded
            }
            return [.cancelHoverOpen, .cancelClose]

        case .behaviorChanged(let newBehavior):
            behavior = newBehavior
            if mode == .peek && !newBehavior.peekOnHover {
                mode = .collapsed
                return [.cancelHoverOpen]
            }
            return []
        }
    }

    private mutating func handleHover(_ hovering: Bool) -> [IslandEffect] {
        guard hovering != isHovering else { return [] }
        isHovering = hovering
        switch mode {
        case .collapsed:
            guard hovering else { return [] }
            if behavior.peekOnHover {
                mode = .peek
                return behavior.openOnHover ? [.scheduleHoverOpen] : []
            }
            // No peek: still allow hover-to-open, timer fires against .collapsed? No —
            // keep semantics simple: without peek there is no hover-open either.
            return []
        case .peek:
            if !hovering {
                mode = .collapsed
                return [.cancelHoverOpen]
            }
            return []
        case .expanded:
            if hovering {
                return [.cancelClose]
            }
            return isDragging ? [] : [.scheduleClose(.standard)]
        }
    }

    private func dedupe(_ effects: [IslandEffect]) -> [IslandEffect] {
        var seen: [IslandEffect] = []
        for effect in effects where !seen.contains(effect) {
            seen.append(effect)
        }
        return seen
    }
}
