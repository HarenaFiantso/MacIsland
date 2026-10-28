import SwiftUI

/// Collapsed / peek content: two wings around the (physical) notch.
struct WingsView: View {
    let model: IslandViewModel

    var body: some View {
        let content = model.wingsContent
        let speed = model.animationSpeed
        HStack(spacing: 0) {
            ZStack {
                LiveActivityWingView(content: content, side: .leading)
                    .transition(.wingContent(speed: speed))
                    .id(content.identity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear
                .frame(width: model.geometry.notchSize.width)

            ZStack {
                LiveActivityWingView(content: content, side: .trailing)
                    .transition(.wingContent(speed: speed))
                    .id(content.identity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
