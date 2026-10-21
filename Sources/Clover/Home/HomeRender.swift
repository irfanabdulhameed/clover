import AppKit
import SwiftUI
import CloverCore

/// Draws pictures of Home to PNG files, for checking the layout without clicking the menu bar.
/// Run with `Clover --render-home <folder>`. The Dashboard has its own, in `DashboardRender`.
@MainActor
enum HomeRender {
    // MARK: Home

    static func renderHome(into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let samples = makeSamples()
        defer { try? FileManager.default.removeItem(at: samples.directory) }

        // Thumbnails load later in the real app. Here they're made first so they show up.
        for item in samples.items { if let url = item.outputs.first { _ = await Thumbnailer.shared.load(url) } }

        let allFound = [EngineInfo(name: "ffmpeg", path: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), install: "brew install ffmpeg"),
                        EngineInfo(name: "cwebp", path: URL(fileURLWithPath: "/opt/homebrew/bin/cwebp"), install: "brew install webp")]
        let oneMissing = [allFound[0], EngineInfo(name: "cwebp", path: nil, install: "brew install webp")]
        let bothMissing = [EngineInfo(name: "ffmpeg", path: nil, install: "brew install ffmpeg"), oneMissing[1]]

        struct Scene {
            let name: String
            let items: [RecentItem]
            let engines: [EngineInfo]
            var targeted = false
            var hoverRow: UUID?
        }
        let scenes = [
            Scene(name: "recents", items: Array(samples.items.prefix(5)), engines: allFound),
            Scene(name: "empty", items: [], engines: oneMissing),
            Scene(name: "busy", items: samples.items, engines: bothMissing, targeted: true, hoverRow: samples.items[1].id),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for scene in scenes {
                let view = HomeView(items: scene.items, engines: scene.engines, trigger: .shift, actions: .none,
                                    forceDropTargeted: scene.targeted, forceHoverRow: scene.hoverRow)
                let png = await capture(view, scheme: scheme)
                let file = folder.appendingPathComponent("home-\(scene.name)-\(scheme == .dark ? "dark" : "light").png")
                try? png?.write(to: file)
                print(file.path)
            }
        }
    }

    // MARK: Drawing

    private static func capture<V: View>(_ content: V, scheme: ColorScheme) async -> Data? {
        let background = Color(nsColor: .windowBackgroundColor)
        let host = NSHostingView(rootView: content.background(background).environment(\.colorScheme, scheme))
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        try? await Task.sleep(nanoseconds: 300_000_000)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return bitmap(of: host)
    }

    static func bitmap(of view: NSView) -> Data? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Sample data

    /// A few real files, so thumbnails and icons are the real thing. Made in a temp folder.
    static func makeSamples() -> (directory: URL, items: [RecentItem]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clover-render-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func image(_ name: String, _ type: NSBitmapImageRep.FileType, _ a: NSColor, _ b: NSColor) -> URL {
            let size = NSSize(width: 480, height: 320)
            let picture = NSImage(size: size, flipped: false) { rect in
                NSGradient(starting: a, ending: b)?.draw(in: rect, angle: 35)
                NSColor.white.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: 320, y: 190, width: 70, height: 70)).fill()
                return true
            }
            let url = dir.appendingPathComponent(name)
            if let tiff = picture.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: type, properties: [:]) {
                try? data.write(to: url)
            }
            return url
        }

        func pdf(_ name: String) -> URL {
            let url = dir.appendingPathComponent(name)
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            if let context = CGContext(url as CFURL, mediaBox: &box, nil) {
                context.beginPDFPage(nil)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                ("Quarterly report" as NSString).draw(at: NSPoint(x: 72, y: 680),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 32, weight: .bold)])
                for line in 0..<12 {
                    NSColor.gray.setFill()
                    NSRect(x: 72, y: 620 - line * 24, width: 460 - (line % 3) * 60, height: 8).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
                context.endPDFPage()
                context.closePDF()
            }
            return url
        }

        func plain(_ name: String) -> URL {
            let url = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            return url
        }

        let beach = image("Beach trip.jpg", .jpeg, .systemTeal, .systemOrange)
        let report = pdf("Quarterly report.pdf")
        let holiday = (0..<12).map { i in
            i == 0 ? image("IMG_2041.png", .png, .systemPink, .systemPurple) : dir.appendingPathComponent("IMG_\(2041 + i).png")
        }
        let song = plain("Voice memo with a really long name that has to be cut in the middle.mp3")
        let archive = plain("Project files.zip")
        let logo = image("logo-final.png", .png, .systemIndigo, .systemMint)
        let clip = plain("Screen recording.mp4")

        let now = Date()
        let items = [
            RecentItem(title: "Convert to JPG", inputNames: ["Beach trip.heic"], outputs: [beach], bytesIn: 3_400_000, bytesOut: 1_200_000, date: now.addingTimeInterval(-20)),
            RecentItem(title: "Convert to PNG", inputNames: (0..<12).map { "IMG_\(2041 + $0).heic" }, outputs: holiday, bytesIn: 21_000_000, bytesOut: 38_500_000, date: now.addingTimeInterval(-5 * 60)),
            RecentItem(title: "Convert to PDF", inputNames: ["report.docx"], outputs: [report], bytesIn: 84_000, bytesOut: 84_300, date: now.addingTimeInterval(-3 * 3600)),
            RecentItem(title: "Convert to MP3", inputNames: ["memo.m4a"], outputs: [song], bytesIn: 2_600_000, bytesOut: 920_000, date: now.addingTimeInterval(-26 * 3600)),
            RecentItem(title: "Zip", inputNames: ["a", "b"], outputs: [archive], bytesIn: 9_800_000, bytesOut: 7_100_000, date: now.addingTimeInterval(-3 * 86400)),
            RecentItem(title: "Convert to PNG", inputNames: ["logo.svg"], outputs: [logo], bytesIn: 4_200, bytesOut: 18_000, date: now.addingTimeInterval(-4 * 86400)),
            RecentItem(title: "Convert to GIF", inputNames: ["clip.mov"], outputs: [clip], bytesIn: 48_000_000, bytesOut: 9_000_000, date: now.addingTimeInterval(-6 * 86400)),
        ]
        return (dir, items)
    }
}
