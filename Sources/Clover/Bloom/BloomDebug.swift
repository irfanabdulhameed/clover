import AppKit
import SwiftUI
import CloverCore

/// Debug commands for checking the bloom without a real drag. Read from the command
/// line when the bloom starts; each one runs, prints, and quits the app.
///
///   Clover --render-bloom <out.png> [--no-targets] <file>...
///   Clover --render-hud <out.png> [<file>]
///   Clover --bloom-selftest
@MainActor
enum BloomDebug {
    /// Returns true when a debug command was found and is running.
    static func run(_ arguments: [String], model: AppModel) -> Bool {
        let args = Array(arguments.dropFirst())
        guard let command = args.first, command.hasPrefix("--render-") || command == "--bloom-selftest" else { return false }
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

    /// A sheet of the clover for these files, in Light and Dark: 3, 4, 5 and 6 leaves;
    /// six with More; a leaf hovered with its chips; a chip lit; keyboard focus; the More
    /// tray open with a pill hovered; the tray kept on screen in a corner; and the
    /// dashboard's still preview.
    static func renderBloom(_ args: [String], model: AppModel) async -> Int32 {
        var rest = args
        guard !rest.isEmpty else {
            print("Usage: Clover --render-bloom <out.png> [--no-targets] <file>...")
            return 2
        }
        let out = URL(fileURLWithPath: rest.removeFirst())
        let noTargets = rest.contains("--no-targets")
        rest.removeAll { $0 == "--no-targets" }
        let files = rest.map { URL(fileURLWithPath: $0) }
        let arrangement = noTargets ? Arrangement(leaves: [], more: []) : model.arrangement(for: files)
        let all = arrangement.all

        func make(_ a: Arrangement) -> BloomModel {
            let m = BloomModel()
            m.chipDelay = 0
            m.reset(mode: .click)
            m.setFiles(files, arrangement: a)
            return m
        }
        func center(_ box: CGRect) -> CGPoint { CGPoint(x: box.midX, y: box.midY) }

        let counts = (3...6).map { n in ("\(n) leaves", make(Arrangement(leaves: Array(all.prefix(n)), more: []))) }
        let resting = make(arrangement)
        let hovered = make(arrangement)
        let chip = make(arrangement)
        let focus = make(arrangement)
        // The tray shows chips only for targets with options; put some behind More if needed.
        let trayArrangement: Arrangement = {
            guard !arrangement.more.isEmpty, !arrangement.more.contains(where: { !$0.options.isEmpty }) else { return arrangement }
            let leaves = BloomGeometry.maxLeaves - 1
            return Arrangement(leaves: Array(all.suffix(leaves)), more: Array(all.dropLast(leaves)))
        }()
        let tray = make(trayArrangement)
        let corner = make(trayArrangement)
        let count = resting.leafCount
        // The first leaf with options shows its chips; otherwise the first leaf.
        let withChips = (0..<count).filter { !(hovered.target(at: $0)?.options.isEmpty ?? true) }
        if let leaf = withChips.first ?? (count > 0 ? 0 : nil) {
            hovered.pointer(at: center(BloomLayout.labelBox(leaf, of: count)))
            chip.pointer(at: center(BloomLayout.labelBox(leaf, of: count)))
            if let last = chip.chipFrames(for: leaf).last { chip.pointer(at: center(last)) }
        }
        // Keyboard focus on another leaf with chips.
        if let leaf = (withChips.count > 1 ? withChips[1] : nil) ?? (count > 1 ? 1 : nil) {
            focus.focusNumber(leaf + 1)
        }
        // The tray: More lit, the first pill with options hovered with its chips; in the corner, a chip lit.
        for m in [tray, corner] where m.moreIndex != nil {
            m.openTray(focusFirst: false)
            let pills = m.pillFrames
            let pill = pills.indices.first { !(m.pillTarget($0)?.options.isEmpty ?? true) } ?? 0
            if pills.indices.contains(pill) { m.trayPointer(at: center(pills[pill])) }
            if m === corner, let first = m.pillChipFrames(for: pill).first { m.trayPointer(at: center(first)) }
        }
        for m in counts.map(\.1) + [resting, hovered, chip, focus, tray, corner] { await m.waitForThumbnails(timeout: 4) }

        let rows: [[(String, BloomModel)]] = [
            counts,
            [("6 with More", resting), ("leaf hovered, chips", hovered), ("chip lit", chip), ("keyboard focus", focus)],
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
                            Tile(title: "\(name) · \(title)", scheme: scheme) { BloomView(model: m) }
                        }
                    }
                }
                HStack(spacing: 0) {
                    Tile(title: "\(name) · More tray, pill hovered", scheme: scheme, width: 700, height: 560) {
                        ScreenScene(model: tray, size: CGSize(width: 700, height: 560), anchor: CGPoint(x: 440, y: 280))
                    }
                    Tile(title: "\(name) · top-left corner: clover and tray kept on screen", scheme: scheme, width: 900, height: 560) {
                        ScreenScene(model: corner, size: CGSize(width: 900, height: 560), anchor: CGPoint(x: 4, y: 556))
                    }
                    Tile(title: "\(name) · dashboard preview", scheme: scheme, width: 400, height: 560, plain: true) {
                        CloverPreview(arrangement: preview, file: files.first, highlighted: highlight)
                    }
                }
            }
        }
        return write(sheet, to: out)
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

    private static func write<V: View>(_ view: V, to url: URL) -> Int32 {
        let renderer = ImageRenderer(content: view.environment(\.bloomSnapshot, true))
        renderer.scale = 2
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
/// at `anchor` and its More tray, both placed as the live windows are.
private struct ScreenScene: View {
    let model: BloomModel
    let size: CGSize
    let anchor: CGPoint

    var body: some View {
        let visible = CGRect(origin: .zero, size: size)
        let c = BloomLayout.clampedCenter(anchor, bounds: BloomController.extent, visible: visible)
        ZStack(alignment: .topLeading) {
            BloomView(model: model)
                .position(x: c.x, y: size.height - c.y)
            if model.trayOpen, let more = model.moreIndex {
                let leaf = BloomLayout.screenRect(BloomLayout.leafBounds(more, of: model.leafCount), center: c)
                let rect = TrayLayout.frame(size: model.traySize, more: leaf, clover: c, visible: visible)
                TrayView(model: model)
                    .position(x: rect.midX, y: size.height - rect.midY)
            }
            Rectangle()
                .strokeBorder(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(width: size.width, height: size.height)
    }
}
