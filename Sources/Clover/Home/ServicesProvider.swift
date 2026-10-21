import AppKit

/// "Convert with Clover" in Finder's right-click Services menu.
@MainActor
final class ServicesProvider: NSObject {
    private let bloom: BloomController

    init(bloom: BloomController) { self.bloom = bloom }

    @objc func convertFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were selected." as NSString
            return
        }
        bloom.present(files: urls, at: nil)
    }
}
