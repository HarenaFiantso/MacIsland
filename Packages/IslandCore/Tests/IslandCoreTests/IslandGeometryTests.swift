import XCTest
@testable import IslandCore

final class IslandGeometryTests: XCTestCase {
    // Geometry measured on a 16" MacBook Pro (2021): 1728x1117 pt, notch 185x32.
    let screen = NotchGeometry(
        displayID: 1,
        screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        hasPhysicalNotch: true,
        isBuiltIn: true,
        notchSize: CGSize(width: 185, height: 32),
        menuBarHeight: 33,
        maximumFramesPerSecond: 120
    )

    func testNotchRectIsTopCentred() {
        let rect = screen.notchRect
        XCTAssertEqual(rect.midX, 864, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 1117, accuracy: 0.001)
        XCTAssertEqual(rect.size, CGSize(width: 185, height: 32))
    }

    func testCollapsedLayoutMatchesNotch() {
        let metrics = IslandMetrics(notchSize: screen.notchSize, panelSize: .regular)
        XCTAssertEqual(metrics.collapsed.bodySize, screen.notchSize)
        XCTAssertEqual(metrics.collapsed.totalSize.width, 185 + 12)
    }

    func testEveryLayoutFitsInsideWindow() {
        for size in PanelSize.allCases {
            let metrics = IslandMetrics(notchSize: screen.notchSize, panelSize: size)
            let window = metrics.windowSize
            for layout in [metrics.collapsed, metrics.peek(from: metrics.collapsed), metrics.liveActivity(wing: 90), metrics.expanded] {
                XCTAssertLessThanOrEqual(layout.totalSize.width, window.width, "\(size)")
                XCTAssertLessThanOrEqual(layout.totalSize.height, window.height, "\(size)")
            }
        }
    }

    func testPeekGrowsSymmetrically() {
        let metrics = IslandMetrics(notchSize: screen.notchSize, panelSize: .regular)
        let peek = metrics.peek(from: metrics.collapsed)
        XCTAssertEqual(peek.bodySize.width - metrics.collapsed.bodySize.width, IslandMetrics.peekGrowth.width)
        XCTAssertEqual(peek.bodySize.height - metrics.collapsed.bodySize.height, IslandMetrics.peekGrowth.height)
    }

    func testExpandedWingsAreSymmetricAroundNotch() {
        let metrics = IslandMetrics(notchSize: screen.notchSize, panelSize: .large)
        XCTAssertEqual(metrics.expandedWingWidth * 2 + screen.notchSize.width, metrics.expanded.bodySize.width, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.expandedWingWidth, 100)
    }

    func testExpandedNeverNarrowerThanWideNotch() {
        let wide = IslandMetrics(notchSize: CGSize(width: 600, height: 32), panelSize: .compact)
        XCTAssertGreaterThanOrEqual(wide.expanded.bodySize.width, 600 + 240)
    }

    func testLayoutFrameHugsTopInBothCoordinateSystems() {
        let layout = IslandLayout(bodySize: CGSize(width: 185, height: 32), radii: IslandRadii(top: 6, bottom: 12))
        let container = CGSize(width: 800, height: 300)
        let flipped = layout.frame(inContainerOfSize: container, flipped: true)
        let unflipped = layout.frame(inContainerOfSize: container, flipped: false)
        XCTAssertEqual(flipped.minY, 0)
        XCTAssertEqual(unflipped.maxY, 300)
        XCTAssertEqual(flipped.midX, 400)
        XCTAssertEqual(flipped.width, 197)
    }

    func testTopCenteredFrameKeepsIntegralOriginAndCentre() {
        // 197 pt wide island on a 1728 pt screen: naive centring gives x = 765.5.
        let frame = screen.topCenteredFrame(size: CGSize(width: 197, height: 32))
        XCTAssertEqual(frame.minX, frame.minX.rounded(), "origin must be integral so AppKit does not shift the window")
        XCTAssertEqual(frame.midX, 864, accuracy: 0.001, "centre must stay on the notch centre")
        XCTAssertEqual(frame.width, 198)
        XCTAssertEqual(frame.maxY, 1117)
        // Already integral: untouched.
        let even = screen.topCenteredFrame(size: CGSize(width: 200, height: 40))
        XCTAssertEqual(even.width, 200)
        XCTAssertEqual(even.minX, 764)
    }

    func testTopCenteredWindowFrameOnSecondaryScreenOffset() {
        let external = NotchGeometry(
            displayID: 2,
            screenFrame: CGRect(x: 1728, y: 200, width: 2560, height: 1440),
            hasPhysicalNotch: false,
            isBuiltIn: false,
            notchSize: CGSize(width: 185, height: 32),
            menuBarHeight: 24
        )
        let frame = external.topCenteredFrame(size: CGSize(width: 700, height: 240))
        XCTAssertEqual(frame.midX, 1728 + 1280, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, 1640, accuracy: 0.001)
    }
}
