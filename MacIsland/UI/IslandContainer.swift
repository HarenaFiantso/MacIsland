import SwiftUI
import UniformTypeIdentifiers
import IslandCore

/// The black shape + whatever content the current mode calls for.
///
/// Content is laid out at its *final* size and revealed by the animated clip, so
/// text never reflows mid-animation; only the shape and a fade/scale/blur move.
struct IslandContainer: View {
    let model: IslandViewModel
    @Environment(ShelfStore.self) private var shelf

    var body: some View {
        let layout = model.targetLayout
        let shape = IslandShape(topRadius: layout.radii.top, bottomRadius: layout.radii.bottom)
        let speed = model.animationSpeed

        ZStack(alignment: .top) {
            switch model.mode {
            case .expanded:
                let expanded = model.metrics.expanded
                ExpandedIslandView(model: model)
                    .frame(width: expanded.bodySize.width, height: expanded.bodySize.height)
                    .padding(.horizontal, expanded.radii.top)
                    .transition(.islandContent(speed: speed))
            case .collapsed, .peek:
                WingsView(model: model)
                    .frame(width: layout.bodySize.width, height: layout.bodySize.height)
                    .padding(.horizontal, layout.radii.top)
                    .transition(.islandContent(speed: speed))
            }
        }
        .frame(width: layout.totalSize.width, height: layout.totalSize.height, alignment: .top)
        .background(shape.fill(IslandDesign.background))
        .overlay {
            if model.isDropTargeted {
                shape.stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { model.backgroundTapped() }
        .onDrop(of: [.fileURL], delegate: IslandDropDelegate(model: model, shelf: shelf))
    }
}

/// Drop target covering the whole island: dragging files onto the notch opens the
/// shelf; dropping anywhere on the island adds them.
@MainActor
struct IslandDropDelegate: DropDelegate {
    let model: IslandViewModel
    let shelf: ShelfStore

    func validateDrop(info: DropInfo) -> Bool {
        model.preferences.shelfEnabled && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        if !info.hasItemsConforming(to: [ShelfItem.dragType]) {
            shelf.draggingItemID = nil // external drag: forget any stale internal marker
        }
        model.isDropTargeted = true
        model.send(.dragEntered)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: shelf.draggingItemID == nil ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        model.isDropTargeted = false
        model.send(.dragExited)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.isDropTargeted = false
        defer { model.send(.dropPerformed) }
        if shelf.draggingItemID != nil {
            shelf.draggingItemID = nil // internal reorder that ended on the background: nothing to add
            return true
        }
        let providers = info.itemProviders(for: [.fileURL])
        shelf.add(providers: providers)
        return !providers.isEmpty
    }
}
