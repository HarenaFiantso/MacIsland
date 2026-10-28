import AppKit
import Observation
import UniformTypeIdentifiers
import QuickLookThumbnailing
import Quartz

// MARK: - Shelf model

struct ShelfItem: Identifiable, Equatable, Codable {
    var id: UUID
    var url: URL
    var bookmark: Data?
    var addedAt: Date

    var name: String { url.lastPathComponent }

    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// Private pasteboard type used to reorder inside the shelf (never leaves the process).
    static let dragType = UTType(exportedAs: "com.macisland.shelf-item")
}

/// Temporary file shelf. Items are persisted (as bookmarks + URLs) in Application Support.
@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    /// Item currently being dragged *from* the shelf (used for live reordering).
    var draggingItemID: UUID?

    @ObservationIgnored var onItemsAdded: ((Int) -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let storeURL: URL

    static let maxItems = 24

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MacIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("shelf.json")
    }

    // MARK: Persistence

    func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        var resolved: [ShelfItem] = []
        for var item in decoded {
            if let bookmark = item.bookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    item.url = url
                    if stale { item.bookmark = try? url.bookmarkData() }
                }
            }
            if FileManager.default.fileExists(atPath: item.url.path) {
                resolved.append(item)
            }
        }
        items = resolved
        Log.shelf.notice("shelf loaded: \(resolved.count) item(s)")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        let url = storeURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: Mutations

    /// Adds files, skipping duplicates. Returns how many were actually added.
    @discardableResult
    func add(urls: [URL], at index: Int? = nil) -> Int {
        var insertionIndex = min(index ?? items.count, items.count)
        var added = 0
        for url in urls {
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL, FileManager.default.fileExists(atPath: standardized.path) else { continue }
            if let existing = items.firstIndex(where: { $0.url.standardizedFileURL == standardized }) {
                // Move the duplicate to the drop position instead of adding twice.
                let item = items.remove(at: existing)
                if existing < insertionIndex { insertionIndex -= 1 }
                items.insert(item, at: min(insertionIndex, items.count))
                insertionIndex += 1
                continue
            }
            let item = ShelfItem(id: UUID(), url: standardized, bookmark: try? standardized.bookmarkData(), addedAt: Date())
            items.insert(item, at: min(insertionIndex, items.count))
            insertionIndex += 1
            added += 1
        }
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        if added > 0 {
            Log.shelf.notice("added \(added) item(s) to shelf")
            onItemsAdded?(added)
        }
        scheduleSave()
        return added
    }

    func add(providers: [NSItemProvider], at index: Int? = nil) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.loadFileURL(from: provider) { urls.append(url) }
            }
            add(urls: urls, at: index)
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    func removeAll() {
        items.removeAll()
        scheduleSave()
    }

    func move(_ id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        scheduleSave()
    }

    func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    // MARK: Actions

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func quickLook(_ item: ShelfItem) {
        let urls = items.map(\.url)
        QuickLookController.shared.preview(urls, index: index(of: item.id) ?? 0)
    }

    /// Provider used when dragging an item *out* of the shelf: a real file URL for
    /// other apps + a private marker so our own grid can reorder.
    func itemProvider(for item: ShelfItem) -> NSItemProvider {
        let provider = NSItemProvider(object: item.url as NSURL)
        provider.suggestedName = item.name
        let idData = Data(item.id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: ShelfItem.dragType.identifier, visibility: .ownProcess) { completion in
            completion(idData, nil)
            return nil
        }
        return provider
    }

    nonisolated static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let direct = item as? URL {
                    url = direct
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let string = item as? String {
                    url = URL(string: string)
                }
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - Thumbnails

/// Quick Look thumbnails with an in-memory cache; falls back to the Finder icon.
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()
    private var cache: [String: NSImage] = [:]

    func thumbnail(for url: URL, size: CGFloat, scale: CGFloat) async -> NSImage {
        let key = "\(url.path)|\(Int(size))|\(Int(scale))"
        if let cached = cache[key] { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        if cache.count > 200 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

// MARK: - Quick Look

final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var urls: [URL] = []

    @MainActor
    func preview(_ urls: [URL], index: Int) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = min(index, max(0, urls.count - 1))
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
