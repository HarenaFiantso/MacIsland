import SwiftUI
import UniformTypeIdentifiers
import IslandCore

/// File shelf: drop zone when empty, grid of draggable tiles otherwise.
struct ShelfView: View {
    @Environment(ShelfStore.self) private var shelf
    @Environment(IslandViewModel.self) private var island

    private let tile: CGFloat = 68

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Shelf")
                    .font(IslandDesign.label(11, .semibold))
                Spacer()
                if !shelf.items.isEmpty {
                    Text("\(shelf.items.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(IslandDesign.tertiary)
                    IslandIconButton(systemName: "xmark", size: 9, frame: 18, tint: IslandDesign.secondary, help: "Clear shelf") {
                        withAnimation(IslandMotion.micro(speed: island.animationSpeed)) { shelf.removeAll() }
                    }
                }
            }
            .foregroundStyle(IslandDesign.secondary)
            .frame(height: 18)

            if shelf.items.isEmpty {
                ShelfDropZone(targeted: island.isDropTargeted)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tile, maximum: tile), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(item: item, tile: tile)
                        }
                    }
                    .animation(IslandMotion.micro(speed: island.animationSpeed), value: shelf.items.map(\.id))
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct ShelfDropZone: View {
    var targeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: IslandDesign.tileRadius, style: .continuous)
                .fill(targeted ? IslandDesign.surface : Color.clear)
            RoundedRectangle(cornerRadius: IslandDesign.tileRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(targeted ? Color.white : Color.white.opacity(0.22))
            VStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 17, weight: .medium))
                Text(targeted ? "Release to add" : "Drop files here")
                    .font(IslandDesign.label(11))
            }
            .foregroundStyle(targeted ? Color.white : IslandDesign.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}

struct ShelfItemView: View {
    let item: ShelfItem
    let tile: CGFloat

    @Environment(ShelfStore.self) private var shelf
    @Environment(IslandViewModel.self) private var island
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: tile * 0.34))
                        .foregroundStyle(IslandDesign.tertiary)
                }
            }
            .frame(width: tile - 18, height: tile - 28)

            Text(item.name)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(IslandDesign.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: tile - 10)
        }
        .frame(width: tile, height: tile)
        .background(
            RoundedRectangle(cornerRadius: IslandDesign.tileRadius, style: .continuous)
                .fill(hovering ? IslandDesign.surfaceHover : IslandDesign.surface)
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    withAnimation(IslandMotion.micro(speed: island.animationSpeed)) { shelf.remove(item.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture(count: 2) { shelf.open(item) }
        .onTapGesture(count: 1) { shelf.quickLook(item) }
        .onDrag {
            shelf.draggingItemID = item.id
            return shelf.itemProvider(for: item)
        } preview: {
            dragPreview
        }
        .onDrop(of: [.fileURL, ShelfItem.dragType], delegate: ShelfReorderDelegate(target: item, shelf: shelf, island: island))
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.revealInFinder(item) }
            Button("Quick Look") { shelf.quickLook(item) }
            Divider()
            Button("Remove from Shelf", role: .destructive) { shelf.remove(item.id) }
        }
        .help(item.url.path)
        .task(id: item.url) {
            thumbnail = await ThumbnailProvider.shared.thumbnail(for: item.url, size: tile, scale: 2)
        }
    }

    private var dragPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.85))
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit().padding(6)
            } else {
                Image(systemName: "doc.fill").foregroundStyle(.white)
            }
        }
        .frame(width: 56, height: 56)
    }
}

/// Per-tile drop target: live reordering for internal drags, positional insert for files.
@MainActor
struct ShelfReorderDelegate: DropDelegate {
    let target: ShelfItem
    let shelf: ShelfStore
    let island: IslandViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) || info.hasItemsConforming(to: [ShelfItem.dragType])
    }

    func dropEntered(info: DropInfo) {
        island.send(.dragEntered)
        if !info.hasItemsConforming(to: [ShelfItem.dragType]) {
            shelf.draggingItemID = nil
            return
        }
        if let dragging = shelf.draggingItemID, dragging != target.id {
            withAnimation(IslandMotion.micro(speed: island.animationSpeed)) {
                shelf.move(dragging, before: target.id)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: shelf.draggingItemID == nil ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        island.send(.dragExited)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            shelf.draggingItemID = nil
            island.send(.dropPerformed)
        }
        if shelf.draggingItemID != nil { return true }
        shelf.add(providers: info.itemProviders(for: [.fileURL]), at: shelf.index(of: target.id))
        return true
    }
}
