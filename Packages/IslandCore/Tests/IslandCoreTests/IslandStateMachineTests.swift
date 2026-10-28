import XCTest
@testable import IslandCore

final class IslandStateMachineTests: XCTestCase {

    func testHoverPeeksThenOpensAfterDelay() {
        var sm = IslandStateMachine()
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [.scheduleHoverOpen])
        XCTAssertEqual(sm.mode, .peek)
        XCTAssertEqual(sm.handle(.hoverOpenTimerFired), [.cancelClose])
        XCTAssertEqual(sm.mode, .expanded)
    }

    func testHoverExitDuringPeekCollapsesAndCancelsTimer() {
        var sm = IslandStateMachine()
        sm.handle(.hoverChanged(true))
        XCTAssertEqual(sm.handle(.hoverChanged(false)), [.cancelHoverOpen])
        XCTAssertEqual(sm.mode, .collapsed)
        // A late timer must be ignored.
        XCTAssertEqual(sm.handle(.hoverOpenTimerFired), [])
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testHoverOpenDisabledOnlyPeeks() {
        var sm = IslandStateMachine(behavior: IslandBehavior(openOnHover: false))
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [])
        XCTAssertEqual(sm.mode, .peek)
        XCTAssertEqual(sm.handle(.hoverOpenTimerFired), [])
        XCTAssertEqual(sm.mode, .peek)
        XCTAssertEqual(sm.handle(.tapped), [.cancelHoverOpen, .cancelClose])
        XCTAssertEqual(sm.mode, .expanded)
    }

    func testPeekDisabledKeepsCollapsed() {
        var sm = IslandStateMachine(behavior: IslandBehavior(peekOnHover: false))
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [])
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testExpandedClosesAfterPointerLeavesAndTimerFires() {
        var sm = IslandStateMachine()
        sm.handle(.open(nil))
        sm.handle(.hoverChanged(true))
        XCTAssertEqual(sm.handle(.hoverChanged(false)), [.scheduleClose(.standard)])
        XCTAssertEqual(sm.mode, .expanded)
        XCTAssertEqual(sm.handle(.closeTimerFired), [])
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testReenteringCancelsPendingClose() {
        var sm = IslandStateMachine()
        sm.handle(.open(nil))
        sm.handle(.hoverChanged(true))
        sm.handle(.hoverChanged(false))
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [.cancelClose])
        // Timer that was not cancelled in time must be a no-op.
        XCTAssertEqual(sm.handle(.closeTimerFired), [])
        XCTAssertEqual(sm.mode, .expanded)
    }

    func testTapOnExpandedHeaderClosesWithoutReopening() {
        var sm = IslandStateMachine()
        sm.handle(.hoverChanged(true))
        sm.handle(.hoverOpenTimerFired)
        XCTAssertEqual(sm.mode, .expanded)
        sm.handle(.tapped)
        XCTAssertEqual(sm.mode, .collapsed)
        XCTAssertTrue(sm.isHovering, "pointer is still inside")
        // Pointer still inside: nothing should re-open until it leaves and comes back.
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [])
        XCTAssertEqual(sm.mode, .collapsed)
        sm.handle(.hoverChanged(false))
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [.scheduleHoverOpen])
        XCTAssertEqual(sm.mode, .peek)
    }

    func testTapOutsideClosesOnlyWhenExpanded() {
        var sm = IslandStateMachine()
        XCTAssertEqual(sm.handle(.tappedOutside), [])
        sm.handle(.open(.calendar))
        XCTAssertEqual(sm.handle(.tappedOutside), [.cancelHoverOpen, .cancelClose])
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testDragOpensShelfAndBlocksAutoClose() {
        var sm = IslandStateMachine()
        let effects = sm.handle(.dragEntered)
        XCTAssertEqual(sm.mode, .expanded)
        XCTAssertTrue(effects.contains(.selectTab(.shelf)))
        XCTAssertTrue(effects.contains(.cancelClose))
        XCTAssertTrue(sm.isDragging)
        // While dragging, a stray close timer must not collapse the island.
        XCTAssertEqual(sm.handle(.closeTimerFired), [])
        XCTAssertEqual(sm.mode, .expanded)
        // Pointer "leaving" during a drag session does not schedule a close.
        XCTAssertEqual(sm.handle(.hoverChanged(false)), [])
    }

    func testDropSchedulesLongerCloseWhenPointerNotTracked() {
        var sm = IslandStateMachine()
        sm.handle(.dragEntered)
        XCTAssertEqual(sm.handle(.dropPerformed), [.scheduleClose(.afterDrop)])
        XCTAssertFalse(sm.isDragging)
        XCTAssertEqual(sm.handle(.closeTimerFired), [])
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testDragExitedWhileHoveringKeepsOpen() {
        var sm = IslandStateMachine()
        sm.handle(.open(nil))
        sm.handle(.hoverChanged(true))
        sm.handle(.dragEntered)
        XCTAssertEqual(sm.handle(.dragExited), [])
        XCTAssertEqual(sm.mode, .expanded)
    }

    func testDragIgnoredWhenShelfDisabled() {
        var sm = IslandStateMachine(behavior: IslandBehavior(shelfEnabled: false))
        XCTAssertEqual(sm.handle(.dragEntered), [])
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testOpenSelectsTabAndToggle() {
        var sm = IslandStateMachine()
        XCTAssertEqual(sm.handle(.open(.timer)), [.cancelHoverOpen, .cancelClose, .selectTab(.timer)])
        XCTAssertEqual(sm.mode, .expanded)
        sm.handle(.toggle)
        XCTAssertEqual(sm.mode, .collapsed)
        sm.handle(.toggle)
        XCTAssertEqual(sm.mode, .expanded)
        sm.handle(.escape)
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testBehaviorChangeCollapsesPeekWhenPeekDisabled() {
        var sm = IslandStateMachine()
        sm.handle(.hoverChanged(true))
        XCTAssertEqual(sm.mode, .peek)
        XCTAssertEqual(sm.handle(.behaviorChanged(IslandBehavior(peekOnHover: false))), [.cancelHoverOpen])
        XCTAssertEqual(sm.mode, .collapsed)
    }

    func testHoverIsIdempotent() {
        var sm = IslandStateMachine()
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [.scheduleHoverOpen])
        XCTAssertEqual(sm.handle(.hoverChanged(true)), [], "duplicate hover must not restart timers")
    }
}
