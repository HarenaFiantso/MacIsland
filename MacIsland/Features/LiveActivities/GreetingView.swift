import SwiftUI

/// The launch greeting: "hello" written by hand under the notch, the way a Mac greets
/// you the first time it starts — one continuous cursive stroke drawn from the first
/// letter to the last, held for a moment, then folded back into the notch.
struct GreetingView: View {
    let notchSize: CGSize
    let speed: Double

    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // The notch band stays empty: on a notched display it is the camera housing.
            Color.clear.frame(height: notchSize.height)

            HandwrittenHello(progress: progress)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // A pen does not move at a constant speed: ease in, cruise, ease out.
            withAnimation(
                .timingCurve(0.45, 0.05, 0.35, 1, duration: HandwrittenHello.drawDuration / speed)
                    .delay(0.25 / speed)
            ) {
                progress = 1
            }
        }
    }
}

/// "hello" as a single pen stroke, revealed with `trim` so it looks written rather
/// than faded in.
struct HandwrittenHello: View {
    var progress: CGFloat

    /// Seconds the pen takes at 1× speed.
    static let drawDuration: Double = 1.9

    var body: some View {
        GeometryReader { geo in
            let rect = HelloStroke.fittedRect(in: geo.size)
            HelloStroke.path(in: rect)
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: HelloStroke.lineWidth(in: rect), lineCap: .round, lineJoin: .round)
                )
        }
    }
}

/// The handwriting itself: pen positions recorded in a design box (x right, y down;
/// baseline at y = 50, x-height at 30, ascender loops up to y ≈ 1), joined by a
/// Catmull-Rom spline so the stroke stays smooth through every loop.
enum HelloStroke {
    static let pen: [CGPoint] = [
        // h: entry stroke, tall loop, stem, arch
        (5, 46), (12, 34), (20, 20), (27, 8), (30, 3), (28, 0.5), (23, 2.5), (19, 9), (17, 22), (17, 36), (17, 50),
        (19, 44), (21, 34), (25, 29), (31, 28), (36, 32), (38, 40), (38, 50), (40, 53), (44, 50),
        // e: wide open loop
        (52, 41), (58, 32), (59, 28.5), (55, 26.5), (49, 29.5), (46, 38), (46, 47), (51, 52.5), (57, 50),
        // l
        (64, 34), (72, 20), (79, 8), (82, 3), (80, 0.5), (75, 2.5), (71, 9), (69, 22), (69, 36), (69, 50), (71, 53), (76, 50),
        // l
        (84, 34), (92, 20), (99, 8), (102, 3), (100, 0.5), (95, 2.5), (91, 9), (89, 22), (89, 36), (89, 50),
        // o: in along the bottom, up the right side, round, closing into the tail
        (91.5, 53.5), (97, 53.5), (103, 51.5), (107.5, 46), (109.5, 39), (107.5, 31.5), (102.5, 28), (97.5, 30.5), (95, 38), (95.5, 46),
        (99, 52), (104, 52.5), (108, 48), (110.5, 42), (113.5, 35.5), (118, 31), (123, 29), (127, 27),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// Stroke width in design units.
    static let designLineWidth: CGFloat = 3.8

    /// Bounds of the stroke in design units, including the pen's thickness.
    static let designBox: CGRect = {
        let xs = pen.map(\.x), ys = pen.map(\.y)
        let half = designLineWidth / 2
        return CGRect(
            x: xs.min()! - half, y: ys.min()! - half,
            width: xs.max()! - xs.min()! + designLineWidth,
            height: ys.max()! - ys.min()! + designLineWidth
        )
    }()

    /// The largest rect of the stroke's aspect ratio that fits `size`, centred.
    static func fittedRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / designBox.width, size.height / designBox.height)
        let fitted = CGSize(width: designBox.width * scale, height: designBox.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    static func lineWidth(in rect: CGRect) -> CGFloat {
        designLineWidth * rect.height / designBox.height
    }

    static func path(in rect: CGRect) -> Path {
        let scale = rect.height / designBox.height
        let points = pen.map { point in
            CGPoint(
                x: rect.minX + (point.x - designBox.minX) * scale,
                y: rect.minY + (point.y - designBox.minY) * scale
            )
        }
        var path = Path()
        guard points.count > 1 else { return path }
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }
}
