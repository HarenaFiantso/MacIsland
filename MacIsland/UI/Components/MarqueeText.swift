import SwiftUI
import AppKit
import QuartzCore

/// Single-line text that scrolls horizontally when it does not fit.
///
/// Implemented with `CATextLayer`s and a repeating Core Animation keyframe so the
/// scroll runs in the render server (SwiftUI-driven offsets would redraw the text at
/// the display refresh rate). Fits its proposed width; shows a static label when the
/// text fits.
struct MarqueeText: View {
    let text: String
    var size: CGFloat = 13
    var weight: NSFont.Weight = .medium
    var color: Color = IslandDesign.primary
    var height: CGFloat = 18
    var speed: CGFloat = 28 // points per second

    var body: some View {
        MarqueeTextRepresentable(text: text, font: .systemFont(ofSize: size, weight: weight), color: NSColor(color), height: height, speed: speed)
            .frame(height: height)
    }
}

private struct MarqueeTextRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let height: CGFloat
    let speed: CGFloat

    func makeNSView(context: Context) -> MarqueeLayerView {
        MarqueeLayerView()
    }

    func updateNSView(_ view: MarqueeLayerView, context: Context) {
        view.configure(text: text, font: font, color: color, speed: speed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeLayerView, context: Context) -> CGSize? {
        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: nsView.textWidth, height: height)
    }
}

final class MarqueeLayerView: NSView {
    private let primary = CATextLayer()
    private let secondary = CATextLayer()
    private let fade = CAGradientLayer()
    private var textSize = CGSize.zero
    private var speed: CGFloat = 28
    private let gap: CGFloat = 36
    private let pause: Double = 1.6
    private var key = ""

    var textWidth: CGFloat { ceil(textSize.width) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for textLayer in [primary, secondary] {
            textLayer.isWrapped = false
            textLayer.truncationMode = .none
            textLayer.alignmentMode = .left
            textLayer.anchorPoint = .zero
            layer?.addSublayer(textLayer)
        }
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.05, 0.92, 1]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, font: NSFont, color: NSColor, speed: CGFloat) {
        let newKey = "\(text)|\(font.pointSize)|\(font.fontName)|\(color.description)|\(speed)"
        guard newKey != key else { return }
        key = newKey
        self.speed = speed
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        textSize = attributed.size()
        primary.string = attributed
        secondary.string = attributed
        updateScale()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
        needsLayout = true
    }

    private func updateScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        primary.contentsScale = scale
        secondary.contentsScale = scale
    }

    private var overflows: Bool { textWidth > bounds.width + 1 }

    override func layout() {
        super.layout()
        let h = ceil(textSize.height)
        let y = ((bounds.height - h) / 2).rounded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primary.frame = CGRect(x: 0, y: y, width: textWidth, height: h)
        secondary.frame = CGRect(x: textWidth + gap, y: y, width: textWidth, height: h)
        secondary.isHidden = !overflows
        if overflows {
            fade.frame = bounds
            layer?.mask = fade
        } else {
            layer?.mask = nil
        }
        CATransaction.commit()
        restartAnimation()
    }

    private func restartAnimation() {
        primary.removeAnimation(forKey: "scroll")
        secondary.removeAnimation(forKey: "scroll")
        guard overflows, speed > 0 else { return }
        let distance = textWidth + gap
        let travel = Double(distance / speed)
        let total = travel + pause
        for textLayer in [primary, secondary] {
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, 0, -distance]
            animation.keyTimes = [0, NSNumber(value: pause / total), 1]
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear)]
            animation.duration = total
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            textLayer.add(animation, forKey: "scroll")
        }
    }
}
