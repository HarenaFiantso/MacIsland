import SwiftUI
import IslandCore

/// Bridges `SpringSpec` (IslandCore) to SwiftUI animations and centralises
/// the choice of curve for each transition. Interpolating springs are
/// additive, so retargeting mid-flight preserves velocity: open/close can be
/// interrupted and reversed without any visual jump.
enum IslandMotion {
    static func animation(_ spec: SpringSpec, speed: Double) -> Animation {
        let s = spec.scaled(speed: speed)
        return .interpolatingSpring(
            Spring(mass: s.mass, stiffness: s.stiffness, damping: s.damping),
            initialVelocity: s.initialVelocity
        )
    }

    static func spec(for mode: IslandMode) -> SpringSpec {
        switch mode {
        case .expanded: return .open
        case .collapsed: return .close
        case .peek: return .peek
        }
    }

    static func micro(speed: Double) -> Animation { animation(.micro, speed: speed) }
    static func activity(speed: Double) -> Animation { animation(.activity, speed: speed) }

    /// Content appearing inside the island: slight scale + blur + fade, delayed so the
    /// black shape leads and the content follows.
    static func contentInsertion(speed: Double) -> Animation {
        .easeOut(duration: 0.22 / speed).delay(0.07 / speed)
    }
    static func contentRemoval(speed: Double) -> Animation {
        .easeIn(duration: 0.12 / speed)
    }
}

/// Fade + scale + blur used when island content changes.
struct IslandContentEffect: ViewModifier {
    var opacity: Double
    var scale: CGFloat
    var blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
    }
}

extension AnyTransition {
    static func islandContent(speed: Double) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandContentEffect(opacity: 0, scale: 0.94, blur: 6),
                identity: IslandContentEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(IslandMotion.contentInsertion(speed: speed)),
            removal: .modifier(
                active: IslandContentEffect(opacity: 0, scale: 0.97, blur: 3),
                identity: IslandContentEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(IslandMotion.contentRemoval(speed: speed))
        )
    }

    static func wingContent(speed: Double) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandContentEffect(opacity: 0, scale: 0.7, blur: 2),
                identity: IslandContentEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(.easeOut(duration: 0.2 / speed).delay(0.05 / speed)),
            removal: .modifier(
                active: IslandContentEffect(opacity: 0, scale: 0.8, blur: 2),
                identity: IslandContentEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(.easeIn(duration: 0.1 / speed))
        )
    }
}
