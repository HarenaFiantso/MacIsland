import XCTest
@testable import IslandCore

final class VolumeFeedbackGateTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testOneKeyStepPlays() {
        var gate = VolumeFeedbackGate()
        XCTAssertTrue(gate.shouldPlay(old: 0.5, new: 0.5 + 1.0 / 16, muted: false, at: t0))
    }

    func testTinySliderChangeIsIgnored() {
        var gate = VolumeFeedbackGate()
        XCTAssertFalse(gate.shouldPlay(old: 0.5, new: 0.51, muted: false, at: t0))
    }

    func testMutedNeverPlays() {
        var gate = VolumeFeedbackGate()
        XCTAssertFalse(gate.shouldPlay(old: 0.5, new: 0.75, muted: true, at: t0))
    }

    func testBurstIsThrottled() {
        var gate = VolumeFeedbackGate(minimumInterval: 0.08)
        XCTAssertTrue(gate.shouldPlay(old: 0.5, new: 0.5625, muted: false, at: t0))
        XCTAssertFalse(gate.shouldPlay(old: 0.5625, new: 0.625, muted: false, at: t0.addingTimeInterval(0.03)))
        XCTAssertTrue(gate.shouldPlay(old: 0.625, new: 0.6875, muted: false, at: t0.addingTimeInterval(0.1)))
    }
}
