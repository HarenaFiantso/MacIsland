import SwiftUI

/// Thin scrubber: grows on hover, seeks on click/drag.
struct IslandProgressBar: View {
    var progress: Double
    var tint: Color = .white
    var onSeek: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let shown = min(1, max(0, dragFraction ?? progress))
            let active = hovering || dragFraction != nil
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(0, geo.size.width * shown))
            }
            .frame(height: active ? 5 : 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = fraction(value.location.x, width: geo.size.width)
                    }
                    .onEnded { value in
                        onSeek(fraction(value.location.x, width: geo.size.width))
                        dragFraction = nil
                    }
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 12)
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }
}
