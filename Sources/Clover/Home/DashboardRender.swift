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
        var tint = GlassTint.none
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
        let pdfLayout = LeafLayout(hidden: ["txt"])
        let audioLayout = LeafLayout(order: ["m4a", "mp3"], hidden: ["opus", "aiff"])
        let leafScenes: [Scene] = [DashboardSize.standard, DashboardSize.minimum].flatMap { size -> [Scene] in
            let suffix = size == DashboardSize.minimum ? "-min" : ""
            return [
                Scene(name: "leaves-images" + suffix, section: .clover, layouts: [.image: imageLayout],
                      forced: DashboardForced(leafKey: .image, leafSelected: "jpg", leafHovered: "webp", leafShowHidden: true), size: size),
                Scene(name: "leaves-pdf" + suffix, section: .clover, layouts: [.pdf: pdfLayout],
                      forced: DashboardForced(leafKey: .pdf, leafSelected: "png", leafHovered: "pdf-compress", leafShowHidden: true), size: size),
                Scene(name: "leaves-audio" + suffix, section: .clover, layouts: [.audio: audioLayout],
                      forced: DashboardForced(leafKey: .audio, leafSelected: "mp3", leafHovered: "flac", leafShowHidden: true), size: size),
            ]
        }
        let scenes: [Scene] = leafScenes + [
            Scene(name: "leaves-default", section: .clover, forced: DashboardForced(leafKey: .image), bothSchemes: false),
            Scene(name: "leaves-tinted", section: .clover, tint: .preset(.blue),
                  forced: DashboardForced(leafKey: .image, leafSelected: "jpg")),
            Scene(name: "leaves-archives", section: .clover, forced: DashboardForced(leafKey: .archive, leafSelected: "zip")),
            Scene(name: "leaves-video", section: .clover, forced: DashboardForced(leafKey: .video)),
            Scene(name: "leaves-lastone", section: .clover,
                  layouts: [.archive: LeafLayout(hidden: ["zip", "tgz"])],
                  forced: DashboardForced(leafKey: .archive, leafShowHidden: true), bothSchemes: false),
            Scene(name: "leaves-allhidden", section: .clover,
                  layouts: [.archive: LeafLayout(hidden: ["folder", "zip", "tgz"])],
                  forced: DashboardForced(leafKey: .archive), bothSchemes: false),
            Scene(name: "quality", section: .quality, conversion: custom),
            Scene(name: "output", section: .saving),
            Scene(name: "output-custom", section: .saving, conversion: replacing,
                  folder: URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Converted"), reveal: true,
                  login: LoginState(isEnabled: true, message: "macOS needs your approval. Turn Clover on in System Settings, under General, Login Items.", needsApproval: true)),
            Scene(name: "output-tall", section: .saving, conversion: replacing, folder: URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Converted"),
                  login: LoginState(isEnabled: true, message: "macOS needs your approval. Turn Clover on in System Settings, under General, Login Items.", needsApproval: true), size: NSSize(width: 860, height: 960), bothSchemes: false),
            Scene(name: "quality-tall", section: .quality, size: NSSize(width: 860, height: 960), bothSchemes: false),
            Scene(name: "output-min", section: .saving, conversion: replacing, folder: URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Converted"),
                  login: LoginState(inApplications: false), size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "shortcuts", section: .controls),
            Scene(name: "shortcuts-recording", section: .controls, trigger: .option, forced: DashboardForced(recording: true)),
            Scene(name: "shortcuts-rejected", section: .controls, forced: DashboardForced(recording: true, rejected: true), bothSchemes: false),
            Scene(name: "shortcuts-off", section: .controls, trigger: .control, hold: false, hotkey: nil),
            Scene(name: "general", section: .general, tint: .preset(.blue)),
            Scene(name: "general-custom", section: .general, motion: .reduced, haptics: false, sound: false, tint: .custom(0x4AA3A2)),
            Scene(name: "general-none", section: .general, tint: .none, bothSchemes: false),
            Scene(name: "general-min", section: .general, size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "history", section: .history, items: items),
            Scene(name: "history-search", section: .history, items: items, forced: DashboardForced(query: "img")),
            Scene(name: "history-nomatch", section: .history, items: items, forced: DashboardForced(query: "zzz")),
            Scene(name: "history-empty", section: .history),
            Scene(name: "history-min", section: .history, items: items, size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "home", section: .home, items: items, engines: found),
            Scene(name: "home-missing", section: .home, items: items, engines: oneMissing, bothSchemes: false),
            Scene(name: "home-empty", section: .home, engines: found),
            Scene(name: "home-min", section: .home, items: items, engines: oneMissing, size: DashboardSize.minimum, bothSchemes: false),
            Scene(name: "engines", section: .general, engines: oneMissing),
            Scene(name: "engines-found", section: .general, engines: found),
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
        @State private var tint: GlassTint

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
            _tint = State(initialValue: scene.tint)
        }

        var body: some View {
            DashboardView(
                section: $section,
                data: DashboardData(
                    catalog: catalog, layouts: $layouts, conversion: $conversion, outputFolder: $folder,
                    revealAfterConverting: $reveal, triggerKey: $trigger, holdToOpen: $hold, hotkey: $hotkey,
                    motion: $motion, haptics: $haptics, completionSound: $sound, glassTint: $tint,
                    login: scene.login, items: scene.items, engines: scene.engines, forced: scene.forced),
                actions: .none)
            // Glass doesn't draw in a captured window: the clover preview uses its frosted stand-in.
            .environment(\.bloomSnapshot, true)
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
        let plain = LeafEditing.rows(LeafEditing.ordered(images, layout: LeafLayout()), hidden: [], showHidden: false)
        check(images.count > 6, "images have more than six targets")
        let numbers = plain.compactMap { row -> Int? in if case .target(_, .clover(let n)) = row { return n }; return nil }
        check(numbers == [1, 2, 3, 4, 5], "five leaves on the clover, numbered from 12 o'clock: \(numbers)")
        check(plain.first == .header(.clover, count: 5) && plain.contains(.header(.more, count: ids.count - 5))
              && plain.last == .header(.hidden, count: 0), "three parts: on the clover, in More, hidden")
        check(plain.compactMap(\.targetID) == ids, "every target once, in order")
        let hiddenMost = Set(ids.dropFirst(4))
        let few = LeafEditing.rows(images, hidden: hiddenMost, showHidden: false)
        check(!few.contains(.header(.more, count: 0)) && !few.contains { if case .header(.more, _) = $0 { return true }; return false }
              && few.contains(.note(.allFit(4))), "four visible: no More, and a note that all fit")
        check(few.last == .header(.hidden, count: hiddenMost.count) && few.compactMap(\.targetID).count == 4, "Hidden is folded by default")
        let open = LeafEditing.rows(images, hidden: hiddenMost, showHidden: true)
        check(open.compactMap(\.targetID).count == ids.count && open.contains(.target(images[5], .hidden)), "opened, the hidden rows show")
        check(LeafEditing.rows(images, hidden: Set(ids), showHidden: false).contains(.note(.allHidden)), "everything hidden: a note")
        check(LeafEditing.rows(images, hidden: [], showHidden: true).contains(.note(.noneHidden)), "Hidden opened with nothing in it: a note")
        // Drags: within and across the parts.
        let third = plain.firstIndex { $0.targetID == ids[2] }!
        check(LeafEditing.moved(plain, from: IndexSet(integer: third), to: 1, folded: [])?.order.first == ids[2], "a drag moves a row to the top")
        let toHidden = LeafEditing.moved(plain, from: IndexSet(integer: 1), to: plain.count, folded: [])
        check(toHidden?.hidden == [ids[0]] && toHidden?.order.last == ids[0], "a drag under Hidden hides the row")
        let hiddenRow = open.firstIndex { $0.targetID == ids[5] }!
        let shown = LeafEditing.moved(open, from: IndexSet(integer: hiddenRow), to: 1, folded: [])
        check(shown?.order.first == ids[5] && shown?.hidden.contains(ids[5]) == false, "a drag out of Hidden shows the row")
        let keepFolded = LeafEditing.moved(few, from: IndexSet(integer: 1), to: 3, folded: Array(ids.dropFirst(4)))
        check(keepFolded?.hidden == hiddenMost, "folded hidden rows stay hidden")
        let one = LeafEditing.rows(images, hidden: Set(ids.dropFirst()), showHidden: false)
        check(LeafEditing.moved(one, from: IndexSet(integer: 1), to: one.count, folded: Array(ids.dropFirst())) == nil, "the last leaf can't be dragged into Hidden")
        let places = LeafEditing.places(images, hidden: [ids[6]])
        check(places[ids[0]] == .clover(1) && places[ids[5]] == .more && places[ids[6]] == .hidden, "places")
        check(LeafEditing.shifted(["a", "b", "c"], "a", by: -1) == ["a", "b", "c"], "the first row can't move up")
        check(LeafEditing.shifted(["a", "b", "c"], "a", by: 1) == ["b", "a", "c"], "move down")
        check(LeafEditing.normalized(LeafLayout(order: ids), defaultOrder: ids) == nil, "default order is stored as nothing")
        check(LeafEditing.normalized(LeafLayout(hidden: ["bmp"]), defaultOrder: ids)?.hidden == ["bmp"], "hidden is kept")
        // Honest notes.
        let imageNotes = LeafEditing.notes(catalog, key: .image, targets: images)
        check(imageNotes["mp4"] == "from GIF" && imageNotes["webm"] == "from GIF", "MP4 and WebM come from GIF: \(imageNotes)")
        check(imageNotes["jpg"] == nil && imageNotes["png"] == nil, "everyday formats have no note")
        let pdfNotes = LeafEditing.notes(catalog, key: .pdf, targets: catalog.allTargets(for: .pdf))
        check(pdfNotes["pdf-merge"] == "several files", "Merge needs several files: \(pdfNotes)")
        let archives = catalog.allTargets(for: .archive)
        check(archives.count <= 6 && LeafEditing.rows(archives, hidden: [], showHidden: false).contains(.note(.allFit(archives.count))),
              "archives all fit on the clover")

        // Naming.
        var naming = ConversionSettings()
        naming.namePattern = "{name} ({format})"
        check(naming.name(base: "IMG_0042", format: "JPG", option: nil) + ".jpg" == "IMG_0042 (JPG).jpg", "example name")
        return failures
    }
}
