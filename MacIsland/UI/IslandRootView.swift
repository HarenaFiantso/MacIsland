import SwiftUI

/// Root of each island window: a transparent canvas with the island pinned to the
/// top-centre, exactly where the notch is.
struct IslandRootView: View {
    let model: IslandViewModel

    var body: some View {
        IslandContainer(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(model)
    }
}
