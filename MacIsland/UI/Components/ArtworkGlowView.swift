import SwiftUI
import AppKit
import QuartzCore

/// Ambient glow along the bottom of the panel in the artwork's dominant colours: a few
/// soft radial blobs that drift and breathe, fading out towards the top.
///
/// Like `AudioBarsView`, the motion is a set of repeating Core Animation keyframe
/// animations on `CALayer`s, so it runs entirely in the render server: zero
/// main-thread work per frame.
struct ArtworkGlowView: NSViewRepresentable {
    var colors: [Color]
    /// Radius of the bottom corners, so the glow follows the island's silhouette even
    /// where the SwiftUI clip does not reach a platform view.
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> ArtworkGlowLayerView {
        let view = ArtworkGlowLayerView()
        view.cornerRadius = cornerRadius
        view.setColors(colors.map { NSColor($0) }, animated: false)
        return view
    }

    func updateNSView(_ view: ArtworkGlowLayerView, context: Context) {
        view.cornerRadius = cornerRadius
        view.setColors(colors.map { NSColor($0) }, animated: true)
    }
}

final class ArtworkGlowLayerView: NSView {
    private static let blobCount = 4

    private var blobs: [CAGradientLayer] = []
    private let fade = CAGradientLayer()
    private var colors: [NSColor] = []
    private var animatedSize: CGSize = .zero

    var cornerRadius: CGFloat = 0 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        guard let layer else { return }
        layer.backgroundColor = NSColor.clear.cgColor
        layer.masksToBounds = true
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // bottom corners (y grows upwards)

        for _ in 0..<Self.blobCount {
            let blob = CAGradientLayer()
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            blob.locations = [0, 0.4, 1]
            layer.addSublayer(blob)
            blobs.append(blob)
        }

        // Opaque at the bottom, transparent at the top: the glow rises out of the edge.
        fade.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.45, 1]
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        layer.mask = fade
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Purely decorative: clicks go through to the island behind it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        CATransaction.commit()
        if bounds.size != animatedSize {
            animatedSize = bounds.size
            restartAnimations()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, bounds.size != .zero { restartAnimations() }
    }

    func setColors(_ new: [NSColor], animated: Bool) {
        guard new != colors else { return }
        colors = new
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, blob) in blobs.enumerated() {
            let stops = Self.stops(for: new, blob: index)
            if animated, let from = (blob.presentation() ?? blob).colors {
                let crossfade = CABasicAnimation(keyPath: "colors")
                crossfade.fromValue = from
                crossfade.toValue = stops
                crossfade.duration = 0.9
                crossfade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                blob.add(crossfade, forKey: "colors")
            }
            blob.colors = stops
        }
        CATransaction.commit()
    }

    /// Radial stops for one blob: its colour at the centre, fully transparent at the rim.
    private static func stops(for palette: [NSColor], blob index: Int) -> [CGColor] {
        guard !palette.isEmpty else { return [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.clear.cgColor] }
        let color = palette[index % palette.count]
        return [
            color.withAlphaComponent(0.85).cgColor,
            color.withAlphaComponent(0.32).cgColor,
            color.withAlphaComponent(0).cgColor,
        ]
    }

    /// Each blob wanders between a few anchor points along the bottom edge and breathes,
    /// on its own period, so the pattern never visibly repeats.
    private func restartAnimations() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let diameter = max(size.width * 0.58, size.height * 1.6)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, blob) in blobs.enumerated() {
            blob.removeAllAnimations()
            blob.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)

            let anchors = Self.anchors(blob: index, count: blobs.count, in: size)
            blob.position = anchors[0]

            let drift = CAKeyframeAnimation(keyPath: "position")
            drift.values = anchors.map { NSValue(point: $0) } + [NSValue(point: anchors[0])]
            drift.calculationMode = .cubic
            drift.duration = 11 + Double(index) * 2.7
            drift.repeatCount = .infinity
            drift.isRemovedOnCompletion = false
            blob.add(drift, forKey: "drift")

            let breathe = CAKeyframeAnimation(keyPath: "transform.scale")
            let scales: [CGFloat] = [0.86, 1.12, 0.94, 1.06, 0.86]
            breathe.values = scales
            breathe.calculationMode = .cubic
            breathe.duration = 7 + Double(index) * 1.9
            breathe.repeatCount = .infinity
            breathe.isRemovedOnCompletion = false
            blob.add(breathe, forKey: "breathe")
        }
        CATransaction.commit()
    }

    /// Deterministic wander points for a blob: spread across the width, hugging the bottom.
    private static func anchors(blob index: Int, count: Int, in size: CGSize) -> [CGPoint] {
        let lane = (CGFloat(index) + 0.5) / CGFloat(count)
        var state = UInt32(truncatingIfNeeded: (index + 1) &* 2_654_435_761)
        func unit() -> CGFloat {
            state = state &* 1_664_525 &+ 1_013_904_223
            return CGFloat(state >> 8) / CGFloat(UInt32.max >> 8)
        }
        return (0..<4).map { _ in
            let x = size.width * min(0.95, max(0.05, lane + (unit() - 0.5) * 0.7))
            let y = size.height * (0.05 + unit() * 0.4)
            return CGPoint(x: x, y: y)
        }
    }
}
