import SwiftUI

/// Album artwork tile with placeholder and crossfade.
struct ArtworkView: View {
    let image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(IslandDesign.surface)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.34, weight: .medium))
                    .foregroundStyle(IslandDesign.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: image)
    }
}
