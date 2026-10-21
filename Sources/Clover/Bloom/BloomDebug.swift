import AppKit
import SwiftUI
import CloverCore

/// Debug commands for checking the bloom without a real drag. Read from the command
/// line when the bloom starts; each one runs, prints, and quits the app.
///
///   Clover --render-bloom <out.png> [--no-targets] [--frames | --bench] <file>...
///   Clover --render-hud <out.png> [<file>]
///   Clover --bloom-selftest
@MainActor
enum BloomDebug {
    /// Returns true when a debug command was found and is running.
    static func run(_ arguments: [String], model: AppModel) -> Bool {
        let args = Array(arguments.dropFirst())
        guard let command = args.first, ["--render-bloom", "--render-hud", "--bloom-selftest"].contains(command) else { return false }
        Task { @MainActor in
            let code: Int32
            switch command {
            case "--render-bloom":
                code = await renderBloom(Array(args.dropFirst()), model: model)
            case "--render-hud":
                code = await renderHUD(Array(args.dropFirst()))
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
        rest.removeAll { $0 == "--no-targets" || $0 == "--frames" || $0 == "--bench" }
        let files = rest.map { URL(fileURLWithPath: $0) }
        let arrangement = noTargets ? Arrangement(leaves: [], more: []) : model.arrangement(for: files)
        if bench { return await benchmark(files: files, arrangement: arrangement) }
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
        let sorted = times.sorted()
        print(String(format: "first frame %.1f ms; then %d frames: median %.1f ms, 95th %.1f ms, max %.1f ms",
                     first, times.count, sorted[sorted.count / 2], sorted[sorted.count * 95 / 100], sorted.last ?? 0))
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
        let reduceOpen = make(files, arrangement, reduce: true), reduceDrop = make(files, arrangement, reduce: true)
        let all = [open, openLight, hover, chipsIn, chipsOut, drop, cancel, tray, reduceOpen, reduceDrop]
        for (m, _) in all { await m.waitForThumbnails(timeout: 4) }

        // Scripted on the fake clock, after every await, so no timer fires in between.
        for (m, clock) in [open, openLight, reduceOpen] {
            clock.now = t0
            m.open()
        }
        for (m, clock) in [hover, chipsIn, chipsOut, drop, cancel, tray, reduceDrop] {
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
        for (m, clock) in [drop, reduceDrop] {
            clock.now = t0 - 1
            m.pointer(at: label)
            clock.now = t0
            m.drop()
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
            ("open", open.0, .dark, [0, 30, 60, 140, 300, 500]),
            ("open", openLight.0, .light, [0, 30, 60, 140, 300, 500]),
            ("hover: flip, pop, ripple, glow", hover.0, .dark, [0, 30, 90, 200, 300, 450]),
            ("chips born", chipsIn.0, .dark, [0, 40, 80, 130, 170, 300]),
            ("chips leave", chipsOut.0, .dark, [0, 30, 55, 80, 110, 160]),
            ("drop and carry", drop.0, .dark, [0, 17, 60, 140, 250, 299, 310, 380]),
            ("cancel", cancel.0, .dark, [0, 40, 80, 120, 160]),
            ("reduce motion: open", reduceOpen.0, .dark, [0, 75, 150, 300]),
            ("reduce motion: drop", reduceDrop.0, .dark, [0, 17, 75, 150, 225, 380]),
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
        let states: [(String, ResultChipState)] = snapshots.map { name, snapshot in
            let state = ResultChipState(display: ChipDisplay(snapshot))
            state.thumbnail = thumbnail
            return (name, state)
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
                    backdrop
                }
                content()
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .frame(width: width)
        .environment(\.colorScheme, scheme)
    }

    private var backdrop: some View {
        let dark = scheme == .dark
        return ZStack(alignment: .topLeading) {
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
