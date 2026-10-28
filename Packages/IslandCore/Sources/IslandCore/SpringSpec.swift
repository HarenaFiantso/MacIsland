import Foundation

/// A physical spring description, independent from SwiftUI so it can be tested
/// and tuned here. Converted to `Animation` by the app layer.
public struct SpringSpec: Equatable, Sendable {
    public var mass: Double
    public var stiffness: Double
    public var damping: Double
    public var initialVelocity: Double

    public init(mass: Double = 1, stiffness: Double, damping: Double, initialVelocity: Double = 0) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
        self.initialVelocity = initialVelocity
    }

    /// Damping ratio ζ. < 1 bounces, 1 is critically damped.
    public var dampingRatio: Double {
        damping / (2 * (stiffness * mass).squareRoot())
    }

    /// Undamped natural period in seconds (≈ SwiftUI's `response`).
    public var response: Double {
        2 * Double.pi / (stiffness / mass).squareRoot()
    }

    /// Scales the spring in time while preserving its damping ratio.
    /// `speed` 2 makes it settle twice as fast, 0.5 twice as slow.
    public func scaled(speed: Double) -> SpringSpec {
        let s = max(0.2, min(speed, 4))
        return SpringSpec(
            mass: mass,
            stiffness: stiffness * s * s,
            damping: damping * s,
            initialVelocity: initialVelocity
        )
    }

    // MARK: Presets (tuned for the notch)

    /// Opening the full panel: assertive but settled, light overshoot.
    public static let open = SpringSpec(stiffness: 260, damping: 26)
    /// Closing: slightly stiffer and more damped so the notch "snaps home".
    public static let close = SpringSpec(stiffness: 320, damping: 32)
    /// Hover peek: quick, with a visible bounce.
    public static let peek = SpringSpec(stiffness: 420, damping: 28)
    /// Live-activity wings growing out of the notch.
    public static let activity = SpringSpec(stiffness: 280, damping: 26)
    /// Buttons, tab changes, small layout shifts.
    public static let micro = SpringSpec(stiffness: 600, damping: 40)
}
