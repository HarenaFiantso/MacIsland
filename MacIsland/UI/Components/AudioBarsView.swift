import SwiftUI
import AppKit
import QuartzCore

/// Animated "equalizer" bars shown while something is playing.
///
/// This is a *playback indicator*, not a spectrum analyser: it does not sample the
/// audio output (that would need a Core Audio process tap + the System Audio
/// Recording permission). The bars are `CALayer`s driven by repeating Core Animation
/// keyframe animations, so the motion runs entirely in the render server: zero
/// main-thread work per frame, nothing at all while paused.
struct AudioBarsView: NSViewRepresentable {
    var isPlaying: Bool
    var tint: Color = .white
    var barCount = 4
    var height: CGFloat = 16
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    private var totalWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
    }

    func makeNSView(context: Context) -> AudioBarsLayerView {
        AudioBarsLayerView(barCount: barCount, barWidth: barWidth, spacing: spacing, height: height)
    }

    func updateNSView(_ view: AudioBarsLayerView, context: Context) {
        view.tint = NSColor(tint)
        view.isPlaying = isPlaying
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AudioBarsLayerView, context: Context) -> CGSize? {
        CGSize(width: totalWidth, height: height)
    }
}

final class AudioBarsLayerView: NSView {
    private var bars: [CALayer] = []
    private let restingScale: CGFloat = 0.2

    var tint: NSColor = .white {
        didSet { bars.forEach { $0.backgroundColor = tint.cgColor } }
    }

    var isPlaying = false {
        didSet { if isPlaying != oldValue { updateAnimations() } }
    }

    init(barCount: Int, barWidth: CGFloat, spacing: CGFloat, height: CGFloat) {
        let width = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for index in 0..<barCount {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0) // grow from the bottom
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height)
            bar.position = CGPoint(x: CGFloat(index) * (barWidth + spacing) + barWidth / 2, y: 0)
            bar.cornerRadius = barWidth / 2
            bar.backgroundColor = tint.cgColor
            bar.transform = CATransform3DMakeScale(1, restingScale, 1)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { updateAnimations() }
    }

    private func updateAnimations() {
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            if isPlaying {
                let values = Self.pattern(seed: index)
                let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
                animation.values = values + [values[0]]
                animation.calculationMode = .cubic
                animation.duration = 1.1 + Double(index) * 0.17
                animation.repeatCount = .infinity
                animation.isRemovedOnCompletion = false
                bar.transform = CATransform3DMakeScale(1, values[0], 1)
                bar.add(animation, forKey: "pulse")
            } else {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.25)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                bar.transform = CATransform3DMakeScale(1, restingScale, 1)
                CATransaction.commit()
            }
        }
    }

    /// Deterministic per-bar height pattern (0.25…1.0), different for each bar.
    private static func pattern(seed: Int) -> [CGFloat] {
        var state = UInt32(truncatingIfNeeded: seed &* 2_654_435_761 &+ 12345)
        return (0..<7).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = CGFloat(state >> 8) / CGFloat(UInt32.max >> 8)
            return 0.25 + 0.75 * unit
        }
    }
}
