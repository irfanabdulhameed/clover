import AppKit
import SwiftUI
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Quick Look thumbnails with the file's icon as the fallback.
@MainActor
final class Thumbnailer {
    static let shared = Thumbnailer()

    struct Entry {
        let image: NSImage
        /// False when this is only the file's icon.
        let isPreview: Bool
    }

    private final class Box { let entry: Entry; init(_ entry: Entry) { self.entry = entry } }
    private let cache = NSCache<NSURL, Box>()

    init() { cache.countLimit = 120 }

    func cached(_ url: URL) -> Entry? { cache.object(forKey: url as NSURL)?.entry }

    /// The file's icon. Works at once, even if the file is gone.
    static func icon(for url: URL?) -> NSImage {
        guard let url else { return NSWorkspace.shared.icon(for: .data) }
        if FileManager.default.fileExists(atPath: url.path) { return NSWorkspace.shared.icon(forFile: url.path) }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    /// Makes the thumbnail, or returns the cached one. Never fails: it falls back to the icon.
    func load(_ url: URL, points: CGFloat = 36) async -> Entry {
        if let hit = cached(url) { return hit }
        var entry = Entry(image: Self.icon(for: url), isPreview: false)
        if FileManager.default.fileExists(atPath: url.path) {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: points, height: points), scale: scale, representationTypes: .thumbnail)
            if let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                entry = Entry(image: result.nsImage, isPreview: true)
            }
        }
        cache.setObject(Box(entry), forKey: url as NSURL)
        return entry
    }
}

/// A 36 pt thumbnail. Shows the file's icon first, then the real preview when it's ready.
struct ThumbnailView: View {
    let url: URL?
    @State private var entry: Thumbnailer.Entry

    init(url: URL?) {
        self.url = url
        let hit = url.flatMap { Thumbnailer.shared.cached($0) }
        _entry = State(initialValue: hit ?? Thumbnailer.Entry(image: Thumbnailer.icon(for: url), isPreview: false))
    }

    var body: some View {
        Group {
            if entry.isPreview {
                Image(nsImage: entry.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            } else {
                Image(nsImage: entry.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            }
        }
        .frame(width: 36, height: 36)
        .task(id: url) {
            guard let url, !entry.isPreview else { return }
            entry = await Thumbnailer.shared.load(url)
        }
        .accessibilityHidden(true)
    }
}
