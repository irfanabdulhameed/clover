import AppKit
import SwiftUI
import CloverCore

/// Debug commands for the updater. Each one runs, prints, and quits; neither shows anything.
///
///   Clover --update-check [--accept] [--png <file>] [--manual-folder <dir>] [--relaunch-probe <file>]
///       Checks the feed (point it elsewhere with -updateFeedURL <url>), prints what the window
///       shows, and with --accept presses Update Now: downloads, installs over this copy and
///       relaunches it. The window is real but invisible. --relaunch-probe makes the relaunched
///       copy only write its version to <file>. Nothing is opened in Finder or the browser.
///   Clover --render-update <folder>
///       Draws every state of the window, Light and Dark, to PNG files.
@MainActor
enum UpdateDebug {
    static let commands = ["--update-check", "--render-update"]

    static func isCommand(_ arguments: [String]) -> Bool {
        arguments.dropFirst().first.map(commands.contains) ?? false
    }

    /// Returns true when a command was found and is running.
    static func run(_ arguments: [String]) -> Bool {
        let args = Array(arguments.dropFirst())
        switch args.first {
        case "--update-check":
            check(args)
            return true
        case "--render-update":
            guard args.count > 1 else {
                print("Usage: Clover --render-update <folder>")
                exit(2)
            }
            Task { @MainActor in
                await UpdateRender.render(into: URL(fileURLWithPath: args[1]))
                exit(0)
            }
            return true
        default:
            return false
        }
    }

    // MARK: --update-check

    /// Kept alive for the run.
    private static var controller: UpdateController?

    private static func check(_ args: [String]) {
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        let accept = args.contains("--accept")
        let png = value("--png").map { URL(fileURLWithPath: $0) }

        print("app: \(Bundle.main.bundleURL.path)")
        print("bundle id: \(Bundle.main.bundleIdentifier ?? "none")")
        print("running: \(UpdateChecker.currentVersion?.description ?? "no version")")
        print("feed: \(UpdateChecker.feedURL.absoluteString)")

        let controller = UpdateController(reduceMotion: { false })
        controller.window.headless = true
        controller.installOptions = UpdateInstaller.Options(
            manualFolder: value("--manual-folder").map { URL(fileURLWithPath: $0, isDirectory: true) },
            dryOpen: true,
            relaunchProbe: value("--relaunch-probe").map { URL(fileURLWithPath: $0) })
        self.controller = controller

        var accepted = false
        controller.onPhase = { phase in
            print("phase: \(describe(phase))")
            switch phase {
            case .checking, .downloading, .installing:
                break
            case .ready(let offer):
                print("window lists:")
                for line in shownLines(offer) { print("  " + line) }
                Task { @MainActor in
                    // Let the window lay out, then read it back and draw it.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    report(controller.window, png: png)
                    if accept && !accepted {
                        accepted = true
                        print("pressing Update Now")
                        controller.updateNow()
                    } else {
                        exit(0)
                    }
                }
            case .upToDate:
                exit(0)
            case .manual:
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    report(controller.window, png: nil)
                    exit(0)
                }
            case .checkFailed, .failed:
                exit(1)
            }
        }
        controller.onInstalled = { outcome in
            switch outcome {
            case .installed(let app, let trashed):
                print("installed: \(app.path)")
                print("old copy in the Trash: \(trashed?.path ?? "none (replaced in place)")")
                print("relaunching")
            case .openedInFinder(let message):
                print("manual install: \(message)")
            }
        }
        controller.checkManually()
    }

    private static func describe(_ phase: UpdatePhase) -> String {
        switch phase {
        case .checking: "checking"
        case .upToDate(let version): "up to date (\(version))"
        case .checkFailed(let message): "check failed: \(message)"
        case .ready(let offer): "ready: \(UpdateText.available(offer))"
        case .downloading(_, let received, let total): "downloading " + UpdateText.progress(received: received, total: total)
        case .installing: "installing"
        case .failed(_, let message): "failed: \(message)"
        case .manual(_, let message): "manual: \(message)"
        }
    }

    /// The notes as the window lists them: each version's heading and date, then its lines.
    private static func shownLines(_ offer: UpdateOffer) -> [String] {
        offer.releases.flatMap { release -> [String] in
            let date = release.published.map { " · " + $0.formatted(.dateTime.day().month(.wide).year()) } ?? ""
            let lines = ReleaseNotes.lines(release.notes).map { line -> String in
                switch line.kind {
                case .heading: "  " + line.text
                case .item(let level): String(repeating: "  ", count: level + 1) + "• " + line.text
                }
            }
            return ["Clover \(release.version)" + date] + lines
        }
    }

    /// Prints the window's size and draws the live window to `png`.
    private static func report(_ window: UpdateWindowController, png: URL?) {
        guard let panel = window.panel, let view = panel.contentView else { return }
        print("window: \(Int(panel.frame.width)) × \(Int(panel.frame.height)) pt, content \(Int(view.frame.width)) × \(Int(view.frame.height)), visible to the user: \(panel.alphaValue > 0)")
        if let png, let frame = view.superview ?? Optional(view) {
            frame.layoutSubtreeIfNeeded()
            if let data = HomeRender.bitmap(of: frame) {
                try? data.write(to: png)
                print("drew \(png.path)")
            }
        }
    }
}

/// Draws the update window's states to PNG files, for checking the layout without a real update.
@MainActor
enum UpdateRender {
    static func render(into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let day: TimeInterval = 86400
        let now = Date(timeIntervalSince1970: 1_792_661_400)
        let dmg = ReleaseAsset(name: ReleaseFeed.assetName, url: URL(string: "https://example.com/Clover.dmg")!, size: 18_000_000)
        func release(_ version: String, _ daysAgo: Double, _ notes: String) -> Release {
            Release(tag: "v" + version, version: SemanticVersion(version)!, name: "Clover " + version, notes: notes,
                    published: now.addingTimeInterval(-daysAgo * day), page: URL(string: "https://example.com"), dmg: dmg)
        }
        let r103 = release("1.0.3", 0, """
        - Convert **HEIC** to JPG faster on Apple silicon
        - The result pill shows how much smaller the file got
        - Fixed: the clover sometimes opened on the wrong display
        """)
        let r102 = release("1.0.2", 8, """
        ## New
        - A Copy button on the result pill puts the converted file on the clipboard
        - Merge PDFs straight from the clover, in the order you selected them
        ## Fixes
        - `cwebp` is found when Homebrew lives in /usr/local
        """)
        let r101 = release("1.0.1", 13, "- Undo moves a result to the Trash even after the pill has gone")
        let r100 = release("1.0.0", 20, "- First release")
        let current = SemanticVersion(1, 0, 1)
        let two = UpdateOffer(current: current, release: r103, releases: [r103, r102])
        let one = UpdateOffer(current: SemanticVersion(1, 0, 2), release: r103, releases: [r103])
        let many = UpdateOffer(current: SemanticVersion(0, 9, 0), release: r103, releases: [r103, r102, r101, r100])
        let manual = UpdateInstaller.whyNotReplaceable(URL(fileURLWithPath: "/Volumes/Clover/Clover.app/Contents/AppTranslocation/x.app"))!

        let scenes: [(String, UpdatePhase)] = [
            ("ready", .ready(two)),
            ("ready-one", .ready(one)),
            ("ready-many", .ready(many)),
            ("downloading", .downloading(two, received: 12_400_000, total: 18_000_000)),
            ("installing", .installing(two)),
            ("failed", .failed(two, UpdateFailure.offline.message)),
            ("manual", .manual(two, manual)),
            ("checking", .checking),
            ("uptodate", .upToDate(SemanticVersion(1, 0, 3))),
            ("checkfailed", .checkFailed(UpdateFailure.status(404).message + " Try again later.")),
        ]
        let icon = NSImage(contentsOfFile: "Resources/Clover.icns") ?? NSApp.applicationIconImage!
        for (name, phase) in scenes {
            for dark in [false, true] {
                let controller = UpdateWindowController()
                controller.headless = true
                controller.state.icon = icon
                controller.show(phase, activate: false)
                guard let panel = controller.panel else { continue }
                panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                if let hosting = panel.contentView?.subviews.first as? NSHostingView<UpdateRoot> {
                    hosting.rootView = UpdateRoot(state: controller.state, actions: .none)
                }
                let png = await capture(panel)
                let file = folder.appendingPathComponent("update-\(name)-\(dark ? "dark" : "light").png")
                try? png?.write(to: file)
                print("\(file.path)  \(Int(panel.frame.width)) × \(Int(panel.frame.height))")
                panel.orderOut(nil)
            }
        }
    }

    /// Draws until three pictures in a row match, as the Dashboard renders do.
    private static func capture(_ panel: NSWindow) async -> Data? {
        var png: Data?
        var same = 0
        for _ in 0..<30 where same < 2 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let view = panel.contentView?.superview ?? panel.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            let next = HomeRender.bitmap(of: view)
            same = next != nil && next == png ? same + 1 : 0
            png = next
        }
        return png
    }
}
