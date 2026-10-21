import AppKit
import Carbon.HIToolbox
import SwiftUI
import CloverCore

/// Draws pictures of the Dashboard to PNG files, with sample data, for checking the layout
/// without clicking through the window. Run with `Clover --render-dashboard <folder>`.
/// It never touches the saved settings or history.
@MainActor
enum DashboardRender {
    /// One picture: a section, the data behind it, and any state a picture can't reach by itself.
    private struct Scene {
        var name: String
        var section: DashboardSection
        var layouts: [LayoutKey: LeafLayout] = [:]
        var conversion = ConversionSettings()
        var folder: URL?
        var reveal = false
        var trigger = TriggerKey.shift
        var hold = true
        var hotkey: Hotkey? = .standard
        var motion = MotionPreference.system
        var haptics = true
        var sound = true
        var leafStyle = LeafStyle.clover
        var login = LoginState()
        var items: [RecentItem] = []
        var engines: [EngineInfo] = []
        var forced = DashboardForced()
        /// Also drawn dark. Off for the pictures that only check the smallest window.
        var size = DashboardSize.standard
        var bothSchemes = true
    }

    static func render(into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let samples = HomeRender.makeSamples()
        defer { try? FileManager.default.removeItem(at: samples.directory) }

        let failures = runChecks()
        print(failures.isEmpty ? "Checks passed." : "Checks failed:\n" + failures.map { "  " + $0 }.joined(separator: "\n"))

        // Thumbnails load later in the real app. Here they're made first so they show up.
        for item in samples.items { if let url = item.outputs.first { _ = await Thumbnailer.shared.load(url) } }
        let items = historyItems(samples)

        let tools = Tools(ffmpeg: URL(fileURLWithPath: "/bin/echo"), cwebp: URL(fileURLWithPath: "/bin/echo"))
        let catalog = Catalog(router: Registry.makeRouter(tools: tools))
        let found = [EngineInfo(name: "ffmpeg", path: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), install: "brew install ffmpeg"),
                     EngineInfo(name: "cwebp", path: URL(fileURLWithPath: "/opt/homebrew/bin/cwebp"), install: "brew install webp")]
        let oneMissing = [found[0], EngineInfo(name: "cwebp", path: nil, install: "brew install webp")]

        var custom = ConversionSettings()
        custom.imageQuality = Levels(best: 95, balanced: 85, small: 50)
        custom.videoQuality = 72
        custom.smallVideoHeight = 540
        custom.audioBitrate = Levels(best: 320, balanced: 160, small: 96)
        custom.gifWidth = Levels(best: 640, balanced: 480, small: 240)

        var named = ConversionSettings()
        named.namePattern = "{name} ({format})"
        var replacing = named
        replacing.onConflict = .replace

        let imageLayout = LeafLayout(order: ["png", "jpg", "webp", "heic"], hidden: ["bmp", "ico"], defaultOptions: ["webp": "small"])
        let scenes: [Scene] = [
            Scene(name: "leaves-images", section: .leaves, layouts: [.image: imageLayout],
                  forced: DashboardForced(leafKey: .image, leafSelected: "png", leafHovered: "webp")),
            Scene(name: "leaves-default", section: .leaves, forced: DashboardForced(leafKey: .image)),
            Scene(name: "leaves-archives", section: .leaves, forced: DashboardForced(leafKey: .archive, leafSelected: "zip")),
            Scene(name: "leaves-video", section: .leaves, forced: DashboardForced(leafKey: .video)),
            Scene(name: "leaves-lastone", section: .leaves,
                  layouts: [.archive: LeafLayout(hidden: ["zip", "tgz"])],
                  forced: DashboardForced(leafKey: .archive), bothSchemes: false),
            Scene(name: "leaves-images-min", section: .leaves, layouts: [.image: imageLayout],
                  forced: DashboardForced(leafKey: .image, leafSelected: "jpg"),
                  size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "quality", section: .quality, conversion: custom),
            Scene(name: "output", section: .output),
            Scene(name: "output-custom", section: .output, conversion: replacing,
                  folder: URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Converted"), reveal: true,
                  login: LoginState(isEnabled: true, message: "macOS needs your approval. Turn Clover on in System Settings, under General, Login Items.", needsApproval: true)),
            Scene(name: "output-tall", section: .output, conversion: replacing, folder: URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Converted"),
                  login: LoginState(isEnabled: true, message: "macOS needs your approval. Turn Clover on in System Settings, under General, Login Items.", needsApproval: true), size: NSSize(width: 860, height: 960), bothSchemes: false),
            Scene(name: "quality-tall", section: .quality, size: NSSize(width: 860, height: 960), bothSchemes: false),
            Scene(name: "output-min", section: .output, conversion: replacing, folder: URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Converted"),
                  login: LoginState(inApplications: false), size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "shortcuts", section: .shortcuts),
            Scene(name: "shortcuts-recording", section: .shortcuts, trigger: .option, forced: DashboardForced(recording: true)),
            Scene(name: "shortcuts-rejected", section: .shortcuts, forced: DashboardForced(recording: true, rejected: true), bothSchemes: false),
            Scene(name: "shortcuts-off", section: .shortcuts, trigger: .control, hold: false, hotkey: nil),
            Scene(name: "feel", section: .feel),
            Scene(name: "feel-custom", section: .feel, motion: .reduced, haptics: false, sound: false, leafStyle: .clear),
            Scene(name: "feel-min", section: .feel, size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "history", section: .history, items: items),
            Scene(name: "history-search", section: .history, items: items, forced: DashboardForced(query: "img")),
            Scene(name: "history-nomatch", section: .history, items: items, forced: DashboardForced(query: "zzz")),
            Scene(name: "history-empty", section: .history),
            Scene(name: "history-min", section: .history, items: items, size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "engines", section: .engines, engines: oneMissing),
            Scene(name: "engines-found", section: .engines, engines: found),
        ]

        let only = CommandLine.arguments.firstIndex(of: "--only").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
        for scene in scenes where only.map({ scene.name.hasPrefix($0) }) ?? true {
            for scheme in scene.bothSchemes ? [ColorScheme.light, .dark] : [.light] {
                let png = await capture(Harness(scene: scene, catalog: catalog), title: scene.section.title, scheme: scheme, size: scene.size)
                let file = folder.appendingPathComponent("dashboard-\(scene.name)-\(scheme == .dark ? "dark" : "light").png")
                try? png?.write(to: file)
                print(file.path)
            }
        }
    }

    // MARK: Drawing

    private static func capture<V: View>(_ content: V, title: String, scheme: ColorScheme, size: NSSize) async -> Data? {
        let window = DashboardWindowController.makeWindow(content: content)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.title = title
        window.setContentSize(size)
        // The window goes through its whole life, laid out and drawn like a real one, but
        // stays invisible: fully transparent, and far off every screen.
        window.alphaValue = 0
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.makeKeyAndOrderFront(nil)
        // A busy Mac can take a while to lay a window out, so draw until three pictures in a row match.
        // A busy Mac can take a while to lay a window out, so draw until three pictures in a row match.
        var png: Data?
        var same = 0
        for _ in 0..<40 where same < 2 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let view = window.contentView?.superview ?? window.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            let next = HomeRender.bitmap(of: view)
            same = next != nil && next == png ? same + 1 : 0
            png = next
        }
        window.close()
        return png
    }

    private struct Harness: View {
        let catalog: Catalog
        let scene: Scene
        @State private var section: DashboardSection
        @State private var layouts: [LayoutKey: LeafLayout]
        @State private var conversion: ConversionSettings
        @State private var folder: URL?
        @State private var reveal: Bool
        @State private var trigger: TriggerKey
        @State private var hold: Bool
        @State private var hotkey: Hotkey?
        @State private var motion: MotionPreference
        @State private var haptics: Bool
        @State private var sound: Bool
        @State private var leafStyle: LeafStyle

        init(scene: Scene, catalog: Catalog) {
            self.scene = scene
            self.catalog = catalog
            _section = State(initialValue: scene.section)
            _layouts = State(initialValue: scene.layouts)
            _conversion = State(initialValue: scene.conversion)
            _folder = State(initialValue: scene.folder)
            _reveal = State(initialValue: scene.reveal)
            _trigger = State(initialValue: scene.trigger)
            _hold = State(initialValue: scene.hold)
            _hotkey = State(initialValue: scene.hotkey)
            _motion = State(initialValue: scene.motion)
            _haptics = State(initialValue: scene.haptics)
            _sound = State(initialValue: scene.sound)
            _leafStyle = State(initialValue: scene.leafStyle)
        }

        var body: some View {
            DashboardView(
                section: $section,
                data: DashboardData(
                    catalog: catalog, layouts: $layouts, conversion: $conversion, outputFolder: $folder,
                    revealAfterConverting: $reveal, triggerKey: $trigger, holdToOpen: $hold, hotkey: $hotkey,
                    motion: $motion, haptics: $haptics, completionSound: $sound, leafStyle: $leafStyle,
                    login: scene.login, items: scene.items, engines: scene.engines, forced: scene.forced),
                actions: .none)
        }
    }

    // MARK: Sample data

    /// The sample conversions, with originals for some, and one whose file has gone.
    private static func historyItems(_ samples: (directory: URL, items: [RecentItem])) -> [RecentItem] {
        var items = samples.items
        let dir = samples.directory
        func original(_ name: String) -> URL {
            let url = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            return url
        }
        items[0].inputs = [original("Beach trip.heic")]
        items[2].inputs = [original("report.docx")]
        items[3].inputs = [dir.appendingPathComponent("memo-that-was-deleted.m4a")]
        items[5].inputs = [original("logo.svg")]
        items.insert(RecentItem(title: "Convert to JPG", inputNames: ["IMG_0042.heic"],
                                inputs: [dir.appendingPathComponent("IMG_0042.heic")],
                                outputs: [dir.appendingPathComponent("IMG_0042.jpg")],
                                bytesIn: 4_100_000, bytesOut: 1_900_000, date: Date().addingTimeInterval(-9 * 86400)),
                     at: 4)
        return items
    }

    // MARK: Checks

    /// Checks the logic behind the sections and returns what failed. A picture can't show these.
    private static func runChecks() -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }

        // Shortcut text.
        let ctrlOpt = UInt32(controlKey | optionKey)
        check(Hotkey.display(keyCode: 49, modifiers: ctrlOpt) == "⌃⌥Space", "⌃⌥Space")
        check(Hotkey.standard.display == Hotkey.display(keyCode: UInt32(Hotkey.standard.keyCode), modifiers: Hotkey.standard.modifiers), "standard matches its text")
        check(Hotkey.display(keyCode: 0, modifiers: UInt32(cmdKey)) == "⌘A", "⌘A: \(Hotkey.display(keyCode: 0, modifiers: UInt32(cmdKey)))")
        check(Hotkey.display(keyCode: 96, modifiers: UInt32(cmdKey | shiftKey)) == "⇧⌘F5", "⇧⌘F5")
        check(Hotkey.display(keyCode: 122, modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)) == "⌃⌥⇧⌘F1", "all four modifiers")
        check(Hotkey.from(keyCode: 0, flags: []) == nil, "a bare key is refused")
        check(Hotkey.from(keyCode: 0, flags: [.shift]) == nil, "⇧ alone is refused")
        check(Hotkey.from(keyCode: 49, flags: [.control, .option]) == .standard, "⌃⌥Space is the standard shortcut")
        check(Hotkey.from(keyCode: 11, flags: [.command, .shift])?.display == "⇧⌘B", "⇧⌘B")

        // Levels keep their order.
        var levels = Levels(best: 92, balanced: 80, small: 60)
        levels = LevelRules.set(levels, .best, to: 70)
        check(levels.balanced == 70 && levels.small == 60, "lowering Best pulls Balanced down")
        levels = LevelRules.set(levels, .small, to: 90)
        check(levels.small == 90 && levels.balanced == 90 && levels.best == 90, "raising Small pushes the rest up")
        check(LevelRules.choices([96, 128], including: 100) == [96, 100, 128], "a stored value stays in the picker")

        // Leaf rows.
        let tools = Tools(ffmpeg: URL(fileURLWithPath: "/bin/echo"), cwebp: URL(fileURLWithPath: "/bin/echo"))
        let catalog = Catalog(router: Registry.makeRouter(tools: tools))
        let images = catalog.allTargets(for: .image)
        let ids = images.map(\.id)
        let plain = LeafEditing.rows(LeafEditing.ordered(images, layout: LeafLayout()), hidden: [])
        check(images.count > 6, "images have more than six targets")
        check(plain.firstIndex { $0.targetID == nil } == LeafArranger.maxLeaves - 1, "the divider sits after the fifth leaf")
        check(plain.compactMap(\.targetID) == ids, "the divider is not a target")
        let hiddenMost = Set(ids.dropFirst(6))
        check(LeafEditing.rows(images, hidden: hiddenMost).allSatisfy { $0.targetID != nil }, "six visible or fewer has no divider")
        let archives = catalog.allTargets(for: .archive)
        check(archives.count <= 6 && LeafEditing.rows(archives, hidden: []).allSatisfy { $0.targetID != nil }, "archives have no divider")
        let moved = LeafEditing.moved(plain, from: IndexSet(integer: 2), to: 0)
        check(moved.first == ids[2] && moved.count == ids.count, "a drag moves a row to the top")
        let acrossDivider = LeafEditing.moved(plain, from: IndexSet(integer: 0), to: plain.count)
        check(acrossDivider.last == ids[0], "a drag to the end puts the row last")
        check(LeafEditing.shifted(["a", "b", "c"], "a", by: -1) == ["a", "b", "c"], "the first row can't move up")
        check(LeafEditing.shifted(["a", "b", "c"], "a", by: 1) == ["b", "a", "c"], "move down")
        check(LeafEditing.normalized(LeafLayout(order: ids), defaultOrder: ids) == nil, "default order is stored as nothing")
        check(LeafEditing.normalized(LeafLayout(hidden: ["bmp"]), defaultOrder: ids)?.hidden == ["bmp"], "hidden is kept")

        // Naming.
        var naming = ConversionSettings()
        naming.namePattern = "{name} ({format})"
        check(naming.name(base: "IMG_0042", format: "JPG", option: nil) + ".jpg" == "IMG_0042 (JPG).jpg", "example name")
        return failures
    }
}
