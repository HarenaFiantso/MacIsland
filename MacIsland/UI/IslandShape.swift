import SwiftUI

/// The notch silhouette: concave fillets at the top (merging into the screen edge),
/// convex corners at the bottom. Both radii are animatable, so the shape morphs
/// continuously between the collapsed notch and the expanded panel.
///
/// `rect` includes the fillets: the opaque body is `rect` inset by `topRadius` on
/// both sides.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(0, min(topRadius, rect.width / 2, rect.height))
        let bodyWidth = rect.width - 2 * t
        let b = max(0, min(bottomRadius, bodyWidth / 2, max(0, rect.height - t)))
        // Cubic Bézier control distance for a quarter circle.
        let k = b * 0.5523

        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let leftWall = minX + t
        let rightWall = maxX - t

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        // Top-left fillet: from the screen edge down into the left wall.
        path.addQuadCurve(to: CGPoint(x: leftWall, y: minY + t), control: CGPoint(x: leftWall, y: minY))
        path.addLine(to: CGPoint(x: leftWall, y: maxY - b))
        // Bottom-left corner.
        path.addCurve(
            to: CGPoint(x: leftWall + b, y: maxY),
            control1: CGPoint(x: leftWall, y: maxY - b + k),
            control2: CGPoint(x: leftWall + b - k, y: maxY)
        )
        path.addLine(to: CGPoint(x: rightWall - b, y: maxY))
        // Bottom-right corner.
        path.addCurve(
            to: CGPoint(x: rightWall, y: maxY - b),
            control1: CGPoint(x: rightWall - b + k, y: maxY),
            control2: CGPoint(x: rightWall, y: maxY - b + k)
        )
        path.addLine(to: CGPoint(x: rightWall, y: minY + t))
        // Top-right fillet back to the screen edge.
        path.addQuadCurve(to: CGPoint(x: maxX, y: minY), control: CGPoint(x: rightWall, y: minY))
        path.closeSubpath()
        return path
    }
}
