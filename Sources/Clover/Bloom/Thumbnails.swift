import AppKit
import QuickLookThumbnailing

/// File icons now, Quick Look thumbnails a moment later.
@MainActor
enum Thumbnails {
    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// A Quick Look thumbnail fitting `side` points, or nil when Quick Look has none.
    static func thumbnail(for url: URL, side: CGFloat, scale: CGFloat = 2) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: scale, representationTypes: .thumbnail)
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return nil
        }
    }
}
