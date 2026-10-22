import AppKit
import SwiftUI
import CloverCore

/// Debug commands for checking the bloom without a real drag. Read from the command
/// line when the bloom starts; each one runs, prints, and quits the app.
///
///   Clover --render-bloom <out.png> [--no-targets] [--frames | --bench] <file>...
///   Clover --render-hud <out.png> [<file>]
///   Clover --render-demo <folder> [<file>]
///   Clover --bloom-selftest
@MainActor
enum BloomDebug {
    static let commands = ["--render-bloom", "--render-hud", "--render-demo", "--bloom-selftest"]

    /// True when Clover was started for one of these commands, so it shows nothing.
    static func isCommand(_ arguments: [String]) -> Bool {
        arguments.dropFirst().first.map(commands.contains) ?? false
    }

    /// Returns true when a debug command was found and is running.
    static func run(_ arguments: [String], model: AppModel) -> Bool {
        let args = Array(arguments.dropFirst())
        guard let command = args.first, commands.contains(command) else { return false }
        Task { @MainActor in
            let code: Int32
            switch command {
            case "--render-bloom":
                code = await renderBloom(Array(args.dropFirst()), model: model)
            case "--render-hud":
                code = await renderHUD(Array(args.dropFirst()))
            case "--render-demo":
                code = await DemoRender.render(Array(args.dropFirst()), model: model)
            case "--bloom-selftest":
                code = await BloomSelfTest.run(model: model)
            default:
                print("Unknown command \(command)")
                code = 2
            }
            exit(code)
        }
        return true
    }

    // MARK: Clover sheet

    /// A clock the renders set by hand, so every moment can be drawn.
    final class FakeClock {
        var now: TimeInterval = 1000
    }

    /// Makes a model on a fake clock for these files, with no rest delays.
    static func make(_ files: [URL], _ a: Arrangement, reduce: Bool = false) -> (BloomModel, FakeClock) {
        let clock = FakeClock()
        let m = BloomModel()
        m.clock = { clock.now }
        m.hoverDelay = 0
        m.chipDelay = 0
        m.reset(mode: .click)
        m.reduceMotion = reduce
        m.setFiles(files, arrangement: a)
        return (m, clock)
    }

    /// A sheet of the clover for these files, in Light and Dark: 3, 4, 5 and 6 slots;
    /// six with More; a slot hovered with its chips; a chip lit; keyboard focus; the More
    /// tray open with a pill hovered; the tray kept on screen in a corner; and the
    /// dashboard's still preview. With `--frames`, the motion instead: each moment drawn
    /// at fixed times.
    static func renderBloom(_ args: [String], model: AppModel) async -> Int32 {
        var rest = args
        guard !rest.isEmpty else {
            print("Usage: Clover --render-bloom <out.png> [--no-targets] [--frames | --bench] <file>...")
            return 2
        }
        let out = URL(fileURLWithPath: rest.removeFirst())
        let noTargets = rest.contains("--no-targets")
        let frames = rest.contains("--frames")
        let bench = rest.contains("--bench")
        let tints = rest.contains("--tints")
        rest.removeAll { $0 == "--no-targets" || $0 == "--frames" || $0 == "--bench" || $0 == "--tints" }
        let files = rest.map { URL(fileURLWithPath: $0) }
        let arrangement = noTargets ? Arrangement(leaves: [], more: []) : model.arrangement(for: files)
        if bench { return await benchmark(files: files, arrangement: arrangement) }
        if tints { return await renderTints(files: files, arrangement: arrangement, to: out) }
        if frames { return await renderFrames(files: files, arrangement: arrangement, to: out) }
        let all = arrangement.all

        func center(_ box: CGRect) -> CGPoint { CGPoint(x: box.midX, y: box.midY) }
        let settled: TimeInterval = 1000
        let counts = (3...6).map { n in ("\(n) slots", make(files, Arrangement(leaves: Array(all.prefix(n)), more: []))) }
        let resting = make(files, arrangement)
        let hovered = make(files, arrangement)
        let chip = make(files, arrangement)
        let focus = make(files, arrangement)
        // The tray shows chips only for targets with options; put some behind More if needed.
        let trayArrangement: Arrangement = {
            guard !arrangement.more.isEmpty, !arrangement.more.contains(where: { !$0.options.isEmpty }) else { return arrangement }
            let leaves = BloomGeometry.maxLeaves - 1
            return Arrangement(leaves: Array(all.suffix(leaves)), more: Array(all.dropLast(leaves)))
        }()
        let tray = make(files, trayArrangement)
        let corner = make(files, trayArrangement)
        let everyone = counts.map(\.1) + [resting, hovered, chip, focus, tray, corner]
        for (m, _) in everyone { await m.waitForThumbnails(timeout: 4) }
        // Everything opened long ago and settled; the pointer arrived a while ago.
        for (m, clock) in everyone {
            clock.now = settled - 10
            m.open()
            clock.now = settled - 5
        }
        let count = resting.0.leafCount
        // The first slot with options shows its chips; otherwise the first slot.
        let withChips = (0..<count).filter { !(hovered.0.target(at: $0)?.options.isEmpty ?? true) }
        if let leaf = withChips.first ?? (count > 0 ? 0 : nil) {
            hovered.0.pointer(at: center(BloomLayout.labelBox(leaf, of: count)))
            chip.0.pointer(at: center(BloomLayout.labelBox(leaf, of: count)))
            if let last = chip.0.chipFrames(for: leaf).last { chip.0.pointer(at: center(last)) }
        }
        // Keyboard focus on another slot with chips.
        if let leaf = (withChips.count > 1 ? withChips[1] : nil) ?? (count > 1 ? 1 : nil) {
            focus.0.focusNumber(leaf + 1)
        }
        // The tray: More lit, the first pill with options hovered with its chips; in the corner, a chip lit.
        for (m, _) in [tray, corner] where m.moreIndex != nil {
            m.openTray(focusFirst: false)
            let pills = m.pillFrames
            let pill = pills.indices.first { !(m.pillTarget($0)?.options.isEmpty ?? true) } ?? 0
            if pills.indices.contains(pill) { m.trayPointer(at: center(pills[pill])) }
            if m === corner.0, let first = m.pillChipFrames(for: pill).first { m.trayPointer(at: center(first)) }
        }

        let tile = BloomGeometry.panelSize - 40
        let rows: [[(String, BloomModel)]] = [
            counts.map { ($0.0, $0.1.0) },
            [("6 with More", resting.0), ("slot hovered, chips", hovered.0), ("chip lit", chip.0), ("keyboard focus", focus.0)],
        ]
        let preview = Arrangement(leaves: arrangement.leaves, more: arrangement.more)
        let highlight = withChips.first.flatMap { arrangement.leaves.indices.contains($0) ? arrangement.leaves[$0].id : nil }
        let sheet = VStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                let name = scheme == .dark ? "Dark" : "Light"
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { i in
                            let (title, m) = rows[r][i]
                            Tile(title: "\(name) · \(title)", scheme: scheme, width: tile, height: tile) {
                                BloomView(model: m, time: settled)
                            }
                        }
                    }
                }
                HStack(spacing: 0) {
                    Tile(title: "\(name) · More tray, pill hovered", scheme: scheme, width: 860, height: 640) {
                        ScreenScene(model: tray.0, time: settled, size: CGSize(width: 860, height: 640), anchor: CGPoint(x: 520, y: 320))
                    }
                    Tile(title: "\(name) · top-left corner: clover and tray kept on screen", scheme: scheme, width: 1000, height: 640) {
                        ScreenScene(model: corner.0, time: settled, size: CGSize(width: 1000, height: 640), anchor: CGPoint(x: 4, y: 636))
                    }
                    Tile(title: "\(name) · dashboard preview", scheme: scheme, width: 380, height: 640, plain: true) {
                        CloverPreview(arrangement: preview, file: files.first, highlighted: highlight)
                    }
                }
            }
        }
        return write(sheet, to: out)
    }

    // MARK: Tints

    /// The clover in a few glass tints, in Light and Dark, with a slot lit so the neutral
    /// hover shows against the tint.
    static func renderTints(files: [URL], arrangement: Arrangement, to out: URL) async -> Int32 {
        let tints: [GlassTint] = [.none, .preset(.clover), .preset(.blue), .preset(.pink), .preset(.graphite), .custom(0xE0A030)]
        let models = tints.map { tint -> (GlassTint, BloomModel, FakeClock) in
            let (m, clock) = make(files, arrangement)
            m.tint = tint
            return (tint, m, clock)
        }
        for (_, m, _) in models { await m.waitForThumbnails(timeout: 4) }
        let t0: TimeInterval = 1000
        for (_, m, clock) in models {
            clock.now = t0 - 10
            m.open()
            clock.now = t0 - 5
            m.pointer(at: BloomLayout.labelBox(1, of: m.leafCount).mid)
        }
        let tile: CGFloat = 470
        let sheet = VStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                HStack(spacing: 0) {
                    ForEach(models.indices, id: \.self) { i in
                        Tile(title: "\(scheme == .dark ? "Dark" : "Light") · \(models[i].0.title)", scheme: scheme, width: tile, height: tile) {
                            BloomView(model: models[i].1, time: t0)
                        }
                    }
                }
            }
        }
        return write(sheet, to: out, scale: 1)
    }

    // MARK: Frame cost

    /// Times whole frames of the clover (the view built, laid out and drawn at 2x on the
    /// CPU) through the open and a lit, breathing slot. The live window draws on the GPU,
    /// so this is an upper bound; at 120 Hz a frame has 8.3 ms.
    static func benchmark(files: [URL], arrangement: Arrangement) async -> Int32 {
        let (m, clock) = make(files, arrangement)
        await m.waitForThumbnails(timeout: 4)
        let t0: TimeInterval = 1000
        clock.now = t0
        m.open()
        var times: [Double] = []
        func frame(_ t: TimeInterval) {
            let start = Date()
            let renderer = ImageRenderer(content: BloomView(model: m, time: t).environment(\.bloomSnapshot, true))
            renderer.scale = 2
            _ = renderer.cgImage
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        for i in 0..<60 { frame(t0 + Double(i) / 120) }
        clock.now = t0 + 1
        m.pointer(at: BloomLayout.labelBox(0, of: m.leafCount).mid)
        for i in 0..<60 { frame(t0 + 1 + Double(i) / 120) }
        let first = times.removeFirst()
        func report(_ name: String, _ list: [Double]) {
            let sorted = list.sorted()
            print(String(format: "%@: %d frames, median %.1f ms, 95th %.1f ms, max %.1f ms",
                         name, list.count, sorted[sorted.count / 2], sorted[sorted.count * 95 / 100], sorted.last ?? 0))
        }
        print(String(format: "first frame %.1f ms", first))
        report("open and hover", times)
        times = []
        let label = BloomLayout.labelBox(0, of: m.leafCount).mid
        clock.now = t0 + 1.5
        m.pressDown(.leaf(0), at: label)
        for i in 0..<36 { frame(t0 + 1.5 + Double(i) / 120) }
        clock.now = t0 + 1.8
        _ = m.pressUp(over: nil)
        for i in 0..<36 { frame(t0 + 1.8 + Double(i) / 120) }
        report("press and release", times)
        // The drop: the wave and the carry, every frame at 120 Hz.
        times = []
        clock.now = t0 + 2
        m.drop()
        for i in 0...66 { frame(t0 + 2 + Double(i) / 120) }
        report("drop wave and carry", times)
        return 0
    }

    // MARK: Motion frames

    /// Each moment of the motion, drawn at fixed times after it starts, in the fallback
    /// glass: open, hover with its pop and ripple, chips in and out, the drop and its
    /// carry to the ring, cancel, the tray, and the same with reduce motion.
    static func renderFrames(files: [URL], arrangement: Arrangement, to out: URL) async -> Int32 {
        let t0: TimeInterval = 1000
        let count = arrangement.leaves.count + (arrangement.more.isEmpty ? 0 : 1)
        guard count > 0 else {
            print("No targets for these files.")
            return 1
        }
        func center(_ box: CGRect) -> CGPoint { CGPoint(x: box.midX, y: box.midY) }
        let leaf = (0..<count).first { !(arrangement.leaves.indices.contains($0) ? arrangement.leaves[$0].options.isEmpty : true) } ?? 0
        let label = center(BloomLayout.labelBox(leaf, of: count))

        let open = make(files, arrangement), openLight = make(files, arrangement)
        let hover = make(files, arrangement), chipsIn = make(files, arrangement), chipsOut = make(files, arrangement)
        let drop = make(files, arrangement), cancel = make(files, arrangement), tray = make(files, arrangement)
        let dropLight = make(files, arrangement)
        let reduceOpen = make(files, arrangement, reduce: true), reduceDrop = make(files, arrangement, reduce: true)
        let held = make(files, arrangement), heldLight = make(files, arrangement)
        let release = make(files, arrangement), releaseLight = make(files, arrangement), releaseChoose = make(files, arrangement)
        let chipPress = make(files, arrangement), reducePress = make(files, arrangement, reduce: true)
        let presses = [held, heldLight, release, releaseLight, releaseChoose, chipPress, reducePress]
        let moreOpen = make(files, arrangement), moreOpenLight = make(files, arrangement), moreClose = make(files, arrangement)
        let moreFade = make(files, arrangement, reduce: true)
        let mores = [moreOpen, moreOpenLight, moreClose, moreFade]
        let all = [open, openLight, hover, chipsIn, chipsOut, drop, dropLight, cancel, tray, reduceOpen, reduceDrop] + presses + mores
        for (m, _) in all { await m.waitForThumbnails(timeout: 4) }

        // Scripted on the fake clock, after every await, so no timer fires in between.
        for (m, clock) in [open, openLight, reduceOpen] {
            clock.now = t0
            m.open()
        }
        for (m, clock) in [hover, chipsIn, chipsOut, drop, dropLight, cancel, tray, reduceDrop] + presses + mores {
            clock.now = t0 - 10
            m.open()
        }
        hover.0.chipDelay = 99
        hover.1.now = t0
        hover.0.pointer(at: label)
        chipsIn.1.now = t0
        chipsIn.0.pointer(at: label)
        chipsOut.1.now = t0 - 1
        chipsOut.0.pointer(at: label)
        chipsOut.1.now = t0
        chipsOut.0.pointer(at: .zero)
        for (m, clock) in [drop, dropLight, reduceDrop] {
            clock.now = t0 - 1
            m.pointer(at: label)
            clock.now = t0
            // As a drop does: a quick press at the drop point, then the choice.
            m.quickPress(.leaf(leaf), at: label)
            m.drop()
        }
        // More: the + turns into × as its tray opens, and back as it closes.
        if let more = moreOpen.0.moreIndex {
            let moreAt = BloomLayout.labelBox(more, of: count).mid
            for (m, clock) in [moreOpen, moreOpenLight, moreFade] {
                clock.now = t0 - Motion.More.intent
                m.pointer(at: moreAt)
                clock.now = t0
                m.openTray(focusFirst: false)
            }
            moreClose.1.now = t0 - 1
            moreClose.0.pointer(at: moreAt)
            moreClose.0.openTray(focusFirst: false)
            moreClose.1.now = t0
            moreClose.0.closeTray()
        }
        // Presses: off-centre in the slot, towards its outer edge.
        let r = BloomLayout.radial(leaf, of: count), t = BloomLayout.across(leaf, of: count)
        let middle = BloomLayout.leafCenter(leaf, of: count)
        let pressAt = CGPoint(x: middle.x + r.dx * 18 + t.dx * 20, y: middle.y + r.dy * 18 + t.dy * 20)
        for (m, clock) in [held, heldLight, reducePress] {
            clock.now = t0 - 1
            m.pointer(at: pressAt)
            clock.now = t0
            m.pressDown(.leaf(leaf), at: pressAt)
        }
        for (m, clock) in [release, releaseLight, releaseChoose] {
            clock.now = t0 - 1
            m.pointer(at: pressAt)
            clock.now = t0 - 0.5
            m.pressDown(.leaf(leaf), at: pressAt)
            clock.now = t0
            if m === releaseChoose.0 {
                if m.pressUp(over: .leaf(leaf)) { m.drop() }
            } else {
                _ = m.pressUp(over: nil)
            }
        }
        chipPress.1.now = t0 - 1
        chipPress.0.pointer(at: label)
        if let chip = chipPress.0.chipFrames(for: leaf).dropFirst().first {
            let at = CGPoint(x: chip.minX + chip.width * 0.3, y: chip.midY)
            chipPress.0.pointer(at: at)
            chipPress.1.now = t0
            chipPress.0.pressDown(.chip(leaf: leaf, index: 1), at: at)
        }
        cancel.1.now = t0
        cancel.0.cancel()
        if let more = tray.0.moreIndex {
            tray.1.now = t0
            tray.0.openTray(focusFirst: false)
            let visible = CGRect(x: 0, y: 0, width: 860, height: 600)
            let c = BloomLayout.clampedCenter(CGPoint(x: 520, y: 300), bounds: BloomController.extent, visible: visible)
            let sector = BloomLayout.screenRect(BloomLayout.sectorBounds(more, of: tray.0.leafCount), center: c)
            let rect = TrayLayout.frame(size: tray.0.traySize, more: sector, clover: c, visible: visible)
            tray.0.trayAnchor = TrayLayout.anchor(tray: rect, more: sector)
        }

        let ms: (Double) -> TimeInterval = { t0 + $0 / 1000 }
        let rows: [(String, BloomModel, ColorScheme, [Double])] = [
            ("More opens: + to ×", moreOpen.0, .dark, [-200, 0, 45, 90, 180]),
            ("More opens: + to ×", moreOpenLight.0, .light, [-200, 0, 45, 90, 180]),
            ("More closes: × to +", moreClose.0, .dark, [0, 40, 80, 150]),
            ("reduce motion: More", moreFade.0, .dark, [0, 75, 150]),
            ("press, held", held.0, .dark, [0, 60, 150, 300]),
            ("press, held", heldLight.0, .light, [0, 60, 150, 300]),
            ("released", release.0, .dark, [0, 80, 160, 300]),
            ("released", releaseLight.0, .light, [0, 80, 160, 300]),
            ("released on it: the choice", releaseChoose.0, .dark, [0, 80, 160, 300, 420, 550]),
            ("chip pressed", chipPress.0, .dark, [0, 60, 150, 300]),
            ("reduce motion: press", reducePress.0, .dark, [0, 75, 150]),
            ("drop", drop.0, .dark, [0, 45, 90, 140, 200, 280, 360, 420, 480, 550]),
            ("drop", dropLight.0, .light, [0, 45, 90, 140, 200, 280, 360, 420, 480, 550]),
            ("open, instant", open.0, .dark, [0]),
            ("open, instant", openLight.0, .light, [0]),
            ("hover, instant", hover.0, .dark, [0]),
            ("chips, instant", chipsIn.0, .dark, [0]),
            ("chips gone at once", chipsOut.0, .dark, [0]),
            ("cancel: gone at once", cancel.0, .dark, [0]),
            ("reduce motion: drop", reduceDrop.0, .dark, [0, 75, 150, 300, 550]),
        ]
        let tile: CGFloat = 520
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                let (name, m, scheme, times) = rows[r]
                HStack(spacing: 0) {
                    ForEach(times.indices, id: \.self) { i in
                        Tile(title: "\(name) · \(Int(times[i])) ms", scheme: scheme, width: tile, height: tile) {
                            BloomView(model: m, time: ms(times[i]))
                        }
                    }
                }
            }
            if tray.0.moreIndex != nil {
                HStack(spacing: 0) {
                    ForEach([0.0, 60, 140, 260, 400], id: \.self) { t in
                        Tile(title: "tray opens · \(Int(t)) ms", scheme: .dark, width: 860, height: 600) {
                            ScreenScene(model: tray.0, time: ms(t), size: CGSize(width: 860, height: 600), anchor: CGPoint(x: 520, y: 300))
                        }
                    }
                }
            }
        }
        return write(sheet, to: out, scale: 1)
    }

    // MARK: Result chip sheet

    /// Every state of the result chip, in Light and Dark.
    static func renderHUD(_ args: [String]) async -> Int32 {
        guard let path = args.first else {
            print("Usage: Clover --render-hud <out.png> [<file>]")
            return 2
        }
        let out = URL(fileURLWithPath: path)
        var thumbnail: NSImage?
        if args.count > 1 {
            let file = URL(fileURLWithPath: args[1])
            thumbnail = await Thumbnails.thumbnail(for: file, side: 72) ?? Thumbnails.icon(for: file)
        }
        let one = ["photo.png"]
        let twelve = (1...12).map { "IMG_\(4800 + $0).heic" }
        let snapshots: [(String, JobSnapshot)] = [
            ("converting", JobSnapshot(phase: .running, title: "Convert to JPG", formatName: "JPG", family: .image,
                                       inputNames: one, progress: 0.42)),
            ("batch", JobSnapshot(phase: .running, title: "Convert to JPG", formatName: "JPG", family: .image,
                                  inputNames: twelve, finished: 7, total: 12, progress: 0.6)),
            ("video", JobSnapshot(phase: .running, title: "Convert to MP4", formatName: "MP4", family: .video,
                                  inputNames: ["trip.mov"], progress: 0.15)),
            ("done", JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                 inputNames: one, outputNames: ["photo.jpg"], finished: 1, total: 1,
                                 bytesIn: 3_350_000, bytesOut: 1_200_000)),
            ("done, larger", JobSnapshot(phase: .done, title: "Convert to PNG", formatName: "PNG", family: .image,
                                         inputNames: ["scan.jpg"], outputNames: ["scan.png"], finished: 1, total: 1,
                                         bytesIn: 1_000_000, bytesOut: 1_380_000)),
            ("partial", JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                    inputNames: twelve, outputNames: (1...9).map { "IMG_\(4800 + $0).jpg" },
                                    finished: 12, total: 12,
                                    failures: [("IMG_4810.heic", "The file is damaged."), ("IMG_4811.heic", "x"), ("IMG_4812.heic", "x")],
                                    bytesIn: 30_000_000, bytesOut: 9_000_000)),
            ("failed", JobSnapshot(phase: .failed("Clover can't convert images yet."), title: "Convert to JPG",
                                   formatName: "JPG", family: .image, inputNames: one, finished: 1, total: 1,
                                   failures: [("photo.png", "Clover can't convert images yet.")])),
            ("skipped", JobSnapshot(phase: .failed("Already JPG."), title: "Convert to JPG", formatName: "JPG",
                                    family: .image, inputNames: ["photo.jpg"], finished: 1, total: 1, skipped: 1)),
            ("cancelled", JobSnapshot(phase: .cancelled, title: "Convert to MP4", formatName: "MP4", family: .video,
                                      inputNames: ["trip.mov"])),
            ("undone", JobSnapshot(phase: .undone, title: "Convert to JPG", formatName: "JPG", family: .image,
                                   inputNames: one, outputNames: ["photo.jpg"])),
        ]
        var states: [(String, ResultChipState)] = snapshots.map { name, snapshot in
            let state = ResultChipState(display: ChipDisplay(snapshot))
            state.thumbnail = thumbnail
            state.outputs = snapshot.outputNames.map { URL(fileURLWithPath: "/tmp/" + $0) }
            return (name, state)
        }
        // Just after Copy: the checkmark.
        if let done = snapshots.first(where: { $0.0 == "done" }) {
            let state = ResultChipState(display: ChipDisplay(done.1))
            state.thumbnail = thumbnail
            state.outputs = [URL(fileURLWithPath: "/tmp/photo.jpg")]
            state.copied = true
            states.insert(("done, copied", state), at: 4)
        }
        let size = ResultChipView.size
        let sheet = HStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                VStack(spacing: 0) {
                    ForEach(states.indices, id: \.self) { i in
                        let (name, state) = states[i]
                        Tile(title: name, scheme: scheme, width: size.width + 40, height: size.height + 24) {
                            ResultChipView(state: state, actions: ChipActions())
                        }
                    }
                }
            }
        }
        return write(sheet, to: out)
    }

    // MARK: Helpers

    private static func write<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) -> Int32 {
        let renderer = ImageRenderer(content: view.environment(\.bloomSnapshot, true))
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("Couldn't render.")
            return 1
        }
        do {
            try data.write(to: url)
            print("\(url.path) \(image.width)×\(image.height)")
            return 0
        } catch {
            print("Couldn't write \(url.path): \(error.localizedDescription)")
            return 1
        }
    }
}

/// One labelled cell of a debug sheet, over a backdrop like a desktop with a window.
private struct Tile<Content: View>: View {
    let title: String
    let scheme: ColorScheme
    var width: CGFloat = BloomGeometry.panelSize
    var height: CGFloat = BloomGeometry.panelSize
    /// A plain window background instead of the desktop.
    var plain = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(scheme == .dark ? Color(white: 0.1) : Color(white: 0.93))
            ZStack {
                if plain {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    DeskBackdrop(dark: scheme == .dark, width: width, height: height)
                }
                content()
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .frame(width: width)
        .environment(\.colorScheme, scheme)
    }
}

/// A desktop with a window on it, behind the debug pictures and the demo.
struct DeskBackdrop: View {
    let dark: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: dark ? [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.22, green: 0.16, blue: 0.26)]
                                        : [Color(red: 0.66, green: 0.76, blue: 0.88), Color(red: 0.90, green: 0.82, blue: 0.76)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 10)
                .fill(dark ? Color(white: 0.16) : Color.white)
                .frame(width: width * 0.55, height: height * 0.62)
                .offset(x: width * 0.5, y: height * 0.08)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<9, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dark ? Color(white: 0.32) : Color(white: 0.80))
                        .frame(width: width * (0.28 + 0.15 * CGFloat(i % 3)), height: 6)
                }
            }
            .offset(x: width * 0.54, y: height * 0.14)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// A screen of `size` (its visible frame, y up from the bottom) with the clover opened
/// at `anchor` and its More tray, both placed as the live windows are, drawn at `time`.
private struct ScreenScene: View {
    let model: BloomModel
    let time: TimeInterval
    let size: CGSize
    let anchor: CGPoint

    var body: some View {
        let visible = CGRect(origin: .zero, size: size)
        let c = BloomLayout.clampedCenter(anchor, bounds: BloomController.extent, visible: visible)
        ZStack(alignment: .topLeading) {
            BloomView(model: model, time: time)
                .position(x: c.x, y: size.height - c.y)
            if model.events.trayAt.isFinite, let more = model.moreIndex {
                let sector = BloomLayout.screenRect(BloomLayout.sectorBounds(more, of: model.leafCount), center: c)
                let rect = TrayLayout.frame(size: model.traySize, more: sector, clover: c, visible: visible)
                TrayView(model: model, time: time)
                    .position(x: rect.midX, y: size.height - rect.midY)
            }
            Rectangle()
                .strokeBorder(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(width: size.width, height: size.height)
    }
}
