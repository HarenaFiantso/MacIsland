import SwiftUI

/// The launch greeting: "hello" written by hand under the notch, the way a Mac greets
/// you the first time it starts — the same handwriting, drawn stroke by stroke from the
/// first letter to the last, held for a moment, then folded back into the notch.
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
                .timingCurve(0.42, 0.05, 0.4, 1, duration: HandwrittenHello.drawDuration / speed)
                    .delay(0.25 / speed)
            ) {
                progress = 1
            }
        }
    }
}

/// The word as pen strokes, revealed in writing order so it looks written rather
/// than faded in.
struct HandwrittenHello: View {
    var progress: CGFloat

    /// Seconds the pen takes at 1× speed.
    static let drawDuration: Double = 2.3

    var body: some View {
        GeometryReader { geo in
            let glyph = HelloGlyph.current
            let rect = glyph.fittedRect(in: geo.size)
            HelloGlyphShape(glyph: glyph, rect: rect, progress: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: glyph.lineWidth(in: rect), lineCap: .round, lineJoin: .round)
                )
        }
    }
}

/// The strokes of `glyph` written up to `progress` (0…1 of the pen's total travel):
/// each stroke is trimmed in turn, so the pen lifts between strokes exactly where
/// the handwriting does.
struct HelloGlyphShape: Shape {
    let glyph: HelloGlyph
    let rect: CGRect
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in _: CGRect) -> Path {
        let scale = rect.height / glyph.box.height
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -glyph.box.minX, y: -glyph.box.minY)

        var written = glyph.totalLength * min(max(progress, 0), 1)
        var path = Path()
        for (stroke, length) in zip(glyph.strokes, glyph.lengths) {
            guard written > 0 else { break }
            let fraction = min(written / length, 1)
            path.addPath(fraction >= 1 ? stroke : stroke.trimmedPath(from: 0, to: fraction), transform: transform)
            written -= length
        }
        return path
    }
}

/// A handwritten word in a design box (x right, y down), as the pen strokes that wrote it.
///
/// macOS ships the handwriting of its own "hello" — the one the setup assistant draws
/// on a new Mac — as cubic Bézier strokes in the Hello screen saver, one file per
/// language. `HelloGlyph.current` reads the English one from the system at launch, so
/// nothing of Apple's is copied into this project; when the file is missing (older or
/// trimmed systems) it falls back to a spline recorded by hand that imitates it.
struct HelloGlyph {
    /// One continuous pen stroke each, in design units.
    let strokes: [Path]
    /// Pen width in design units.
    let designLineWidth: CGFloat
    /// Bounds of the ink, including the pen's thickness.
    let box: CGRect
    /// Length of each stroke, in design units (drives the writing pace).
    let lengths: [CGFloat]
    var totalLength: CGFloat { lengths.reduce(0, +) }

    init(strokes: [Path], designLineWidth: CGFloat) {
        self.strokes = strokes
        self.designLineWidth = designLineWidth
        let ink = strokes.map(\.boundingRect).reduce(CGRect.null) { $0.union($1) }
        box = ink.insetBy(dx: -designLineWidth / 2, dy: -designLineWidth / 2)
        lengths = strokes.map(Self.length(of:))
    }

    /// The system's handwriting when available, the hand-recorded imitation otherwise.
    static let current: HelloGlyph = system(language: "en") ?? .fallback

    /// The largest rect of the glyph's aspect ratio that fits `size`, centred.
    func fittedRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(size.width / box.width, size.height / box.height)
        let fitted = CGSize(width: box.width * scale, height: box.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    func lineWidth(in rect: CGRect) -> CGFloat {
        designLineWidth * rect.height / box.height
    }

    /// Length of a path, by walking its curves in small steps.
    private static func length(of path: Path) -> CGFloat {
        var total: CGFloat = 0
        var last = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(let to):
                last = to
            case .line(let to):
                total += hypot(to.x - last.x, to.y - last.y)
                last = to
            case .quadCurve(let to, let control):
                total += curveLength(from: last, controls: [control], to: to)
                last = to
            case .curve(let to, let c1, let c2):
                total += curveLength(from: last, controls: [c1, c2], to: to)
                last = to
            case .closeSubpath:
                break
            }
        }
        return total
    }

    private static func curveLength(from start: CGPoint, controls: [CGPoint], to end: CGPoint) -> CGFloat {
        let points = [start] + controls + [end]
        var previous = start
        var length: CGFloat = 0
        for step in 1...24 {
            let t = CGFloat(step) / 24
            var layer = points
            while layer.count > 1 {
                layer = zip(layer, layer.dropFirst()).map { a, b in
                    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
            }
            length += hypot(layer[0].x - previous.x, layer[0].y - previous.y)
            previous = layer[0]
        }
        return length
    }
}

// MARK: - The system's handwriting

extension HelloGlyph {
    /// Where macOS keeps the Hello screen saver's glyph files (one JSON per language).
    private static let systemGlyphFolders = [
        "/System/Library/ExtensionKit/Extensions/Hello.appex/Contents/Resources/Languages", // macOS 14+
        "/System/Library/Screen Savers/Hello.saver/Contents/Resources/Languages", // macOS 13
    ]

    /// Each stroke is a chain of cubic Béziers; every point is [x, y, pen tilt, pen width]
    /// in font units (y up, 1000 per em). `scale` multiplies the four components.
    private struct File: Decodable {
        struct Segment: Decodable {
            let p0: [Double], p1: [Double], p2: [Double], p3: [Double]
        }
        let strokes: [[Segment]]
        let scale: [Double]?
    }

    /// The handwriting macOS draws for `language` ("en" = hello, "fr" = bonjour, …), or nil
    /// when the system does not ship it.
    static func system(language: String) -> HelloGlyph? {
        for folder in systemGlyphFolders {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(language).json")
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(File.self, from: data) else { continue }
            return glyph(from: file)
        }
        return nil
    }

    private static func glyph(from file: File) -> HelloGlyph? {
        let scale = file.scale ?? [1, 1, 1, 1]
        func point(_ p: [Double]) -> CGPoint? {
            guard p.count >= 2 else { return nil }
            // Font coordinates grow upwards; the design box grows downwards.
            return CGPoint(x: p[0] * (scale.count > 0 ? scale[0] : 1), y: -p[1] * (scale.count > 1 ? scale[1] : 1))
        }
        var strokes: [Path] = []
        var widths: [Double] = []
        for segments in file.strokes {
            guard let first = segments.first, let start = point(first.p0) else { continue }
            var path = Path()
            path.move(to: start)
            for segment in segments {
                guard let c1 = point(segment.p1), let c2 = point(segment.p2), let end = point(segment.p3) else { return nil }
                path.addCurve(to: end, control1: c1, control2: c2)
                if segment.p0.count > 3 { widths.append(segment.p0[3] * (scale.count > 3 ? scale[3] : 1)) }
            }
            strokes.append(path)
        }
        guard !strokes.isEmpty else { return nil }
        // The pen width barely varies along the word; the setup assistant draws it uniform,
        // and a shade thicker than the screen saver's ribbon (which also reads better small).
        let width = widths.isEmpty ? 36 : widths.reduce(0, +) / Double(widths.count)
        return HelloGlyph(strokes: strokes, designLineWidth: width * 1.2)
    }
}

// MARK: - Fallback handwriting

extension HelloGlyph {
    /// An imitation recorded by hand: pen positions in a design box (baseline at y = 50,
    /// x-height at 30, ascender loops up to y ≈ 1), joined by a Catmull-Rom spline so the
    /// stroke stays smooth through every loop. Used only when the system has no glyph file.
    static let fallback: HelloGlyph = {
        let pen: [CGPoint] = [
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

        var path = Path()
        path.move(to: pen[0])
        for index in 0..<(pen.count - 1) {
            let p0 = pen[max(index - 1, 0)]
            let p1 = pen[index]
            let p2 = pen[index + 1]
            let p3 = pen[min(index + 2, pen.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return HelloGlyph(strokes: [path], designLineWidth: 3.8)
    }()
}
