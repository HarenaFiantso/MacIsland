import XCTest
@testable import IslandCore

final class SpringSpecTests: XCTestCase {
    func testPresetsAreUnderdampedButSettled() {
        for spec in [SpringSpec.open, .close, .peek, .activity, .micro] {
            XCTAssertGreaterThan(spec.dampingRatio, 0.6, "too bouncy")
            XCTAssertLessThan(spec.dampingRatio, 1.0, "should keep a little overshoot")
            XCTAssertLessThan(spec.response, 0.5, "should feel snappy")
        }
    }

    func testScalingPreservesDampingRatio() {
        let base = SpringSpec.open
        for speed in [0.5, 1.0, 1.7, 2.0] {
            let scaled = base.scaled(speed: speed)
            XCTAssertEqual(scaled.dampingRatio, base.dampingRatio, accuracy: 1e-9)
            XCTAssertEqual(scaled.response, base.response / speed, accuracy: 1e-9)
        }
    }

    func testScalingIsClamped() {
        let slow = SpringSpec.open.scaled(speed: 0.01)
        XCTAssertEqual(slow.response, SpringSpec.open.response / 0.2, accuracy: 1e-9)
    }
}
