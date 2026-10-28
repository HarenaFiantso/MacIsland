import SwiftUI

/// The launch greeting: a bubble hanging under the notch that says "Hello" (what
/// Alcove does when it starts), letters settling in one after the other with a
/// waving hand, then a soft shimmer across the word.
struct GreetingView: View {
    let notchSize: CGSize
    let speed: Double

    @State private var revealed = false
    @State private var waving = false
    @State private var shimmer: CGFloat = -1.2

    private let letters = Array("Hello")

    var body: some View {
        VStack(spacing: 0) {
            // The notch band stays empty: on a notched display it is the camera housing.
            Color.clear.frame(height: notchSize.height)

            HStack(spacing: 9) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(IslandDesign.warning)
                    .rotationEffect(.degrees(waving ? 16 : -12), anchor: .bottomTrailing)
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed ? 1 : 0.6)
                    .animation(.spring(response: 0.45 / speed, dampingFraction: 0.7), value: revealed)

                HStack(spacing: 0) {
                    ForEach(letters.indices, id: \.self) { index in
                        Text(String(letters[index]))
                            .opacity(revealed ? 1 : 0)
                            .blur(radius: revealed ? 0 : 6)
                            .offset(y: revealed ? 0 : 8)
                            .animation(
                                .spring(response: 0.5 / speed, dampingFraction: 0.78)
                                    .delay((0.12 + 0.07 * Double(index)) / speed),
                                value: revealed
                            )
                    }
                }
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .overlay {
                    // Shimmer sweep, revealed through the glyphs.
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.9), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: shimmer * geo.size.width)
                        .blendMode(.plusLighter)
                    }
                    .mask {
                        HStack(spacing: 0) {
                            ForEach(letters.indices, id: \.self) { Text(String(letters[$0])) }
                        }
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            revealed = true
            withAnimation(.easeInOut(duration: 0.32 / speed).repeatCount(6, autoreverses: true).delay(0.2 / speed)) {
                waving = true
            }
            withAnimation(.easeInOut(duration: 1.1 / speed).delay(0.9 / speed)) {
                shimmer = 1.4
            }
        }
    }
}
