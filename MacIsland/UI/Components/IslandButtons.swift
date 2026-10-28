import SwiftUI

/// Press feedback shared by every island control.
struct IslandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round icon button with a hover halo.
struct IslandIconButton: View {
    let systemName: String
    var size: CGFloat = 13
    var frame: CGFloat = 28
    var tint: Color = IslandDesign.primary
    var filled = false
    var help: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(filled ? Color.black : tint)
                .frame(width: frame, height: frame)
                .background(
                    Circle().fill(filled ? Color.white : (hovering ? IslandDesign.surfaceHover : Color.clear))
                )
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help ?? "")
    }
}

/// Small capsule button with text (presets, permission prompts…).
struct IslandPillButton: View {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.black : (isSelected ? IslandDesign.primary : IslandDesign.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    prominent ? Color.white :
                        (isSelected ? IslandDesign.surfacePressed : (hovering ? IslandDesign.surfaceHover : IslandDesign.surface))
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
