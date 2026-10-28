import Foundation
import CoreGraphics

/// Where the (physical or virtual) notch sits on a given screen.
/// Coordinates follow AppKit conventions: origin at the bottom-left of the main screen.
public struct NotchGeometry: Equatable, Sendable {
    public var displayID: UInt32
    public var screenFrame: CGRect
    public var hasPhysicalNotch: Bool
    public var isBuiltIn: Bool
    public var notchSize: CGSize
    public var menuBarHeight: CGFloat
    public var maximumFramesPerSecond: Int

    public init(
        displayID: UInt32,
        screenFrame: CGRect,
        hasPhysicalNotch: Bool,
        isBuiltIn: Bool,
        notchSize: CGSize,
        menuBarHeight: CGFloat,
        maximumFramesPerSecond: Int = 60
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.hasPhysicalNotch = hasPhysicalNotch
        self.isBuiltIn = isBuiltIn
        self.notchSize = notchSize
        self.menuBarHeight = menuBarHeight
        self.maximumFramesPerSecond = maximumFramesPerSecond
    }

    /// Rect of the notch in screen coordinates (top-centre of the screen).
    public var notchRect: CGRect {
        CGRect(
            x: screenFrame.midX - notchSize.width / 2,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    /// A window frame of `size`, glued to the top edge and horizontally centred.
    ///
    /// AppKit rounds window origins to whole points. When centring would land on a
    /// half point (odd width on an even-width screen, or vice-versa) the frame is
    /// widened by one point so the origin stays integral and the island content —
    /// centred inside the window by SwiftUI — still lands exactly on the notch.
    public func topCenteredFrame(size: CGSize) -> CGRect {
        var width = size.width.rounded(.up)
        var x = screenFrame.midX - width / 2
        if x != x.rounded() {
            width += 1
            x = screenFrame.midX - width / 2
        }
        return CGRect(
            x: x,
            y: screenFrame.maxY - size.height.rounded(.up),
            width: width,
            height: size.height.rounded(.up)
        )
    }
}

/// Size presets for the expanded panel.
public enum PanelSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case compact, regular, large
    public var id: String { rawValue }

    public var expandedWidth: CGFloat {
        switch self {
        case .compact: return 560
        case .regular: return 640
        case .large: return 740
        }
    }

    /// Height of the panel *below* the notch band.
    public var expandedBodyHeight: CGFloat {
        switch self {
        case .compact: return 148
        case .regular: return 168
        case .large: return 196
        }
    }
}

/// Corner radii of the island shape. `top` is the outward fillet that merges the
/// island into the screen edge; `bottom` the regular convex corner.
public struct IslandRadii: Equatable, Sendable {
    public var top: CGFloat
    public var bottom: CGFloat
    public init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }
}

/// A resolved target layout of the island.
public struct IslandLayout: Equatable, Sendable {
    /// Size of the opaque body, *excluding* the top fillets.
    public var bodySize: CGSize
    public var radii: IslandRadii

    public init(bodySize: CGSize, radii: IslandRadii) {
        self.bodySize = bodySize
        self.radii = radii
    }

    /// Size including the fillets, i.e. the frame the shape view needs.
    public var totalSize: CGSize {
        CGSize(width: bodySize.width + radii.top * 2, height: bodySize.height)
    }

    /// Frame of the island inside a container whose origin is top-left (flipped) —
    /// the island hugs the top edge and is horizontally centred.
    public func frame(inContainerOfSize container: CGSize, flipped: Bool) -> CGRect {
        let size = totalSize
        let x = (container.width - size.width) / 2
        let y = flipped ? 0 : container.height - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// Produces every layout from the notch size + the user's panel preset.
public struct IslandMetrics: Equatable, Sendable {
    public var notchSize: CGSize
    public var panelSize: PanelSize

    public static let collapsedRadii = IslandRadii(top: 6, bottom: 12)
    public static let peekRadii = IslandRadii(top: 7, bottom: 15)
    public static let activityRadii = IslandRadii(top: 7, bottom: 14)
    public static let expandedRadii = IslandRadii(top: 16, bottom: 28)

    /// Extra width / height the island gains while in `.peek`.
    public static let peekGrowth = CGSize(width: 24, height: 8)
    /// Transparent margins kept around the expanded panel inside the window.
    public static let windowMargin = CGSize(width: 48, height: 32)

    public init(notchSize: CGSize, panelSize: PanelSize) {
        self.notchSize = notchSize
        self.panelSize = panelSize
    }

    public var collapsed: IslandLayout {
        IslandLayout(bodySize: notchSize, radii: Self.collapsedRadii)
    }

    /// A collapsed island with symmetric wings for a live activity.
    public func liveActivity(wing: CGFloat, extraHeight: CGFloat = 0) -> IslandLayout {
        IslandLayout(
            bodySize: CGSize(width: notchSize.width + wing * 2, height: notchSize.height + extraHeight),
            radii: IslandRadii(top: Self.activityRadii.top, bottom: Self.activityRadii.bottom + extraHeight / 2)
        )
    }

    /// Peek derived from the layout the island currently rests in.
    public func peek(from base: IslandLayout) -> IslandLayout {
        IslandLayout(
            bodySize: CGSize(
                width: base.bodySize.width + Self.peekGrowth.width,
                height: base.bodySize.height + Self.peekGrowth.height
            ),
            radii: IslandRadii(top: Self.peekRadii.top, bottom: max(base.radii.bottom, Self.peekRadii.bottom) + 2)
        )
    }

    public var expanded: IslandLayout {
        IslandLayout(
            bodySize: CGSize(
                width: max(panelSize.expandedWidth, notchSize.width + 2 * 120),
                height: notchSize.height + panelSize.expandedBodyHeight
            ),
            radii: Self.expandedRadii
        )
    }

    /// Size of the transparent host window that must contain every layout.
    public var windowSize: CGSize {
        let largest = expanded.totalSize
        return CGSize(
            width: largest.width + Self.windowMargin.width * 2,
            height: largest.height + Self.windowMargin.height
        )
    }

    /// Width of one wing (left or right of the notch) inside the expanded body.
    public var expandedWingWidth: CGFloat {
        (expanded.bodySize.width - notchSize.width) / 2
    }
}
