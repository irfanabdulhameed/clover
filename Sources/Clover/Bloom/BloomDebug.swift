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

    // MARK: Bloom sheet

    /// A sheet of the bloom for these files: resting, a petal lit with its chips, a chip
    /// lit, and keyboard focus, in Light and Dark.
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
        let targets = noTargets ? [] : model.targets(for: files)

        func make() -> BloomModel {
            let m = BloomModel()
            m.chipDelay = 0
            m.reset(mode: .click)
            m.setFiles(files, targets: targets)
            return m
        }
        let resting = make()
        let lit = make()
        let chip = make()
        let focus = make()
        // The first petal with options shows its chips; otherwise the first petal.
        let withChips = lit.items.filter { lit.target(at: $0.slot).map { !$0.options.isEmpty } ?? false }
        if let item = withChips.first ?? lit.items.first {
            lit.pointer(at: BloomLayout.petalCenter(item.slot))
            chip.pointer(at: BloomLayout.petalCenter(item.slot))
            if let last = chip.chipFrames(for: item.slot).last {
                chip.pointer(at: CGPoint(x: last.midX, y: last.midY))
            }
        }
        // Keyboard focus on the last petal with chips, down onto its first chip.
        let other = (withChips.count > 1 ? withChips.last : nil) ?? focus.items.dropFirst().first ?? focus.items.first
        if let other, let number = focus.items.firstIndex(of: other) {
            focus.focusNumber(number + 1)
            focus.moveChipFocus(by: 1)
        }
        for m in [resting, lit, chip, focus] { await m.waitForThumbnails(timeout: 4) }

        let columns: [(String, BloomModel)] = [("resting", resting), ("petal lit", lit), ("chip lit", chip), ("keyboard focus", focus)]
        let sheet = VStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { i in
                        let (name, m) = columns[i]
                        Tile(title: "\(scheme == .dark ? "Dark" : "Light") · \(name)", scheme: scheme) {
                            BloomView(model: m)
                        }
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
                backdrop
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
