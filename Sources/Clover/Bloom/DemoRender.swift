import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import CloverCore

/// The README's demo, drawn frame by frame from the app's own views and motion on a fake
/// clock: the clover opens at the pointer, the pointer rests on HEIC, WebP and JPG, presses
/// JPG and lets go on it, the clover gathers into the ring, and the result chip takes the
/// ring over, converts and shows the result, then leaves. Written as numbered PNGs at 30 fps
/// for ffmpeg to make the GIF; the last frame leads back into the first.
///
///   Clover --render-demo <folder> [<file>]
///
/// Without a file it makes a photo-like `photo.png` of about 3.35 MB to convert. Build
/// against the macOS 15 SDK for the pictures to draw. `docs/images/clover-demo.gif` is made
/// from the frames with:
///
///   ffmpeg -framerate 30 -i <folder>/frame-%04d.png -vf "scale=720:-2:flags=lanczos,split[a][b];
///     [a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
///     -loop 0 clover-demo.gif
@MainActor
enum DemoRender {
    static let fps = 30.0
    /// The picture in points, drawn at 2x, and where the clover opens in it.
    static let canvas = CGSize(width: 760, height: 560)
    static let center = CGPoint(x: 380, y: 296)
    /// The pointer events' rate, so a leaf is entered and left at the right moment.
    static let eventRate = 240.0

    // MARK: The script, in seconds from the first frame

    /// The shortcut opens the clover at the pointer, with the photo selected in Finder.
    static let openAt = 0.55
    /// The button goes down on JPG and comes up on it.
    static let pressAt = 2.95
    static let releaseAt = 3.20
    /// After the drop: the job's progress, and when it is done, as the result chip takes
    /// the ring over once the distortion wave has played.
    static var progress: [(at: Double, value: Double)] {
        let w = Motion.Drop.afterWave
        return [(0, 0), (0.6 + w, 0.55), (0.9 + w, 0.9)]
    }
    static var doneAt: Double { 1.2 + Motion.Drop.afterWave }
    /// How long the result stays before it is dismissed (5 s in the app): long enough for
    /// the border beam's two laps.
    static var doneHold: Double { max(1.2, BorderBeams.available ? BorderBeams.duration + 0.3 : 0) }

    /// Where the pointer is, in clover coordinates (y down, the hub's centre at zero), and
    /// how it travels: rests, and glides with a human ease along a slight curve.
    struct Key {
        var at: Double
        var point: CGPoint
        /// How far the path bows out to its left, as a share of its length.
        var bend: CGFloat = 0
    }

    // MARK: Command

    static func render(_ args: [String], model: AppModel) async -> Int32 {
        guard let path = args.first else {
            print("Usage: Clover --render-demo <folder> [<file>]")
            return 2
        }
        let folder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var madePhoto: URL?
        let file: URL
        if args.count > 1 {
            file = URL(fileURLWithPath: args[1])
        } else {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clover-demo-\(getpid())")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            file = dir.appendingPathComponent("photo.png")
            guard makePhoto(at: file, bytes: 3_350_000) else {
                print("Couldn't make the photo.")
                return 1
            }
            madePhoto = dir
        }
        defer { if let madePhoto { try? FileManager.default.removeItem(at: madePhoto) } }
        let bytesIn = fileSize(file) ?? 0

        // The clover as it comes for a new user, whatever this Mac's own layout is.
        let files = [file]
        let arrangement = LeafArranger.arrange(model.catalog.targets(for: files), layout: LeafLayout())
        print("\(file.lastPathComponent), \(bytesIn) bytes: " + arrangement.leaves.map(\.title).joined(separator: ", ")
              + (arrangement.more.isEmpty ? "" : ", More (\(arrangement.more.count))"))
        func leaf(_ id: String) -> Int? { arrangement.leaves.firstIndex { $0.id == id } }
        guard let heic = leaf("heic"), let webp = leaf("webp"), let jpg = leaf("jpg") else {
            print("The clover needs HEIC, WebP and JPG leaves for this file.")
            return 1
        }

        // The model on a fake clock, with the app's own rest delays run on that clock.
        let (m, clock) = BloomDebug.make(files, arrangement)
        let timers = Timers()
        m.after = { delay, work in timers.add(at: clock.now + delay, work) }
        m.hoverDelay = Motion.Hover.delay
        m.chipDelay = Motion.Chips.delay
        await m.waitForThumbnails(timeout: 6)
        let thumbnail = await Thumbnails.thumbnail(for: file, side: 72) ?? Thumbnails.icon(for: file)

        // The result chip, as the job reports it.
        let running = ChipDisplay(JobSnapshot(phase: .running, title: "Convert to JPG", formatName: "JPG", family: .image,
                                              inputNames: [file.lastPathComponent]))
        let output = file.deletingPathExtension().appendingPathExtension("jpg")
        let done = ChipDisplay(JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                           inputNames: [file.lastPathComponent], outputNames: [output.lastPathComponent],
                                           finished: 1, total: 1, bytesIn: bytesIn, bytesOut: 1_200_000))
        let chipState = ResultChipState(display: done)
        chipState.running = running
        chipState.thumbnail = thumbnail
        chipState.outputs = [output]
        // The chip hears of each event when it happens, as the live chip does; a dry run
        // first finds when it flips to the result, so it can be dismissed after `doneHold`.
        var playback = ChipPlayback(reduced: false, ringStart: .zero)
        var dry = playback
        dry.end(.done, at: doneAt)
        let flip = dry.ending?.at ?? doneAt
        let leaveAt = flip + doneHold
        // The pointer goes home after the chip has left, and rests there a moment.
        let length = releaseAt + leaveAt + 0.09 + 0.45 + 0.6
        var chipEvents: [(at: Double, apply: (inout ChipPlayback) -> Void)] = progress.map { p in
            (p.at, { $0.progress(p.value, at: p.at) })
        }
        chipEvents.append((doneAt, { $0.end(.done, at: doneAt) }))
        chipEvents.append((leaveAt, { $0.leave(at: leaveAt) }))

        // Where the pointer goes: in from the corner, onto HEIC, WebP and JPG, then away.
        let count = m.leafCount
        func on(_ leaf: Int, radius: CGFloat, turn: CGFloat = 0) -> CGPoint {
            let a = BloomLayout.angle(leaf, of: count) + turn * .pi / 180
            return CGPoint(x: (radius * sin(a)).rounded(), y: (-radius * cos(a)).rounded())
        }
        let home = CGPoint(x: 250, y: 205)
        let pHEIC = on(heic, radius: 118, turn: 4)
        let pWebP = on(webp, radius: 158, turn: -2)
        let pJPG = on(jpg, radius: 124, turn: 6)
        let dropAt = releaseAt
        let pointerHome = dropAt + leaveAt + 0.09
        let keys: [Key] = [
            Key(at: 0, point: home), Key(at: 0.10, point: home, bend: 0.10),
            Key(at: 0.50, point: .zero), Key(at: 0.80, point: .zero, bend: -0.10),
            Key(at: 1.12, point: pHEIC), Key(at: 1.42, point: pHEIC, bend: -0.12),
            Key(at: 1.76, point: pWebP), Key(at: 2.08, point: pWebP, bend: 0.04),
            Key(at: 2.40, point: pJPG), Key(at: pointerHome, point: pJPG, bend: -0.12),
            Key(at: pointerHome + 0.45, point: home), Key(at: length, point: home),
        ]
        let route = PointerPath(keys: keys)
        let titles = m.leaves.map { leaf -> String in
            if case .target(let target) = leaf { return target.title }
            return "More"
        }

        // Play the script at the pointer's event rate, drawing every frame.
        var opened = false, openedAt = 0.0
        var lastFed: CGPoint?
        var downHit: BloomHit?
        var dropped: Double?
        var log = Log()
        let frames = Int((length * fps).rounded())
        var event = 0
        for frame in 0..<frames {
            let t = Double(frame) / fps
            while Double(event) / eventRate <= t + 1e-9 {
                let now = Double(event) / eventRate
                event += 1
                timers.run(until: now, clock: clock)
                clock.now = now
                let p = route.point(at: now)
                if !opened, now >= openAt - 1e-9 {
                    m.open()
                    opened = true
                    openedAt = now
                    // The pointer is still: no event reaches the clover until it moves.
                    lastFed = p
                }
                if opened, m.phase == .open, let last = lastFed, hypot(p.x - last.x, p.y - last.y) > 0.01 {
                    m.pointer(at: p)
                    lastFed = p
                }
                if opened, downHit == nil, now >= pressAt - 1e-9 {
                    // As a mouse-down on the clover.
                    m.pointer(at: p)
                    downHit = m.hover
                    if let target = BloomModel.pressTarget(m.hover) { m.pressDown(target, at: p) }
                }
                if let down = downHit, dropped == nil, m.phase == .open, now >= releaseAt - 1e-9 {
                    // As a mouse-up: released on the leaf it went down on, it is chosen.
                    m.pointer(at: p)
                    let hit = m.hover
                    let released = m.pressUp(over: BloomModel.pressTarget(hit))
                    if released, hit == down, m.choice(at: hit) != nil {
                        m.drop()
                        dropped = now
                    }
                }
                log.note(now, m, titles: titles)
            }
            clock.now = t

            let windowAlpha = opened ? Double(revealCurve(min(max((t - openedAt) / Motion.Open.fadeIn, 0), 1))) : 0
            // As in the app, the clover stays a frame past the handoff, under the chip's first frame.
            let cloverShown = opened && (dropped.map { t < $0 + Motion.Drop.handoff + 1.0 / 60 } ?? true)
            var chip: ChipValues?
            if let dropped {
                while let next = chipEvents.first, next.at <= t - dropped + 1e-9 {
                    next.apply(&playback)
                    chipEvents.removeFirst()
                }
            }
            if let dropped, t - dropped >= playback.appearAt, t - dropped <= leaveAt + ChipMotion.exitDuration + 0.05 {
                chip = playback.values(at: t - dropped)
            }
            let pressScale = pointerPress(t, down: pressAt, up: releaseAt)
            let scene = DemoFrame(model: m, now: t, windowAlpha: cloverShown ? windowAlpha : 0,
                                  chipState: chipState, chip: chip,
                                  pointer: route.point(at: t), pointerScale: pressScale)
            let url = folder.appendingPathComponent(String(format: "frame-%04d.png", frame))
            guard writePNG(scene, to: url) else {
                print("Couldn't draw frame \(frame).")
                return 1
            }
        }
        print(log.lines.joined(separator: "\n"))
        if let dropped {
            print(String(format: "drop %.3f s, chip at %.3f s, done flips at %.3f s, leaves at %.3f s",
                         dropped, dropped + playback.appearAt, dropped + flip, dropped + leaveAt))
        }
        print("\(frames) frames at \(Int(fps)) fps in \(folder.path)")
        return 0
    }

    // MARK: Pointer

    /// The pointer's path: rests between keys at the same point, glides between others.
    struct PointerPath {
        let keys: [Key]

        func point(at t: Double) -> CGPoint {
            guard let next = keys.firstIndex(where: { $0.at > t }) else { return keys.last?.point ?? .zero }
            guard next > 0 else { return keys[0].point }
            let a = keys[next - 1], b = keys[next]
            guard a.point != b.point else { return a.point }
            let u = CGFloat(DemoRender.glide((t - a.at) / (b.at - a.at)))
            // A quadratic curve, bowed `bend` of its length to the left of the way.
            let dx = b.point.x - a.point.x, dy = b.point.y - a.point.y
            let control = CGPoint(x: (a.point.x + b.point.x) / 2 + dy * a.bend, y: (a.point.y + b.point.y) / 2 - dx * a.bend)
            let v = 1 - u
            return CGPoint(x: v * v * a.point.x + 2 * v * u * control.x + u * u * b.point.x,
                           y: v * v * a.point.y + 2 * v * u * control.y + u * u * b.point.y)
        }
    }

    /// A hand moving a mouse: it starts briskly from rest and lands with a long, soft slow-down.
    nonisolated static let glide = CubicBezier(0.38, 0.0, 0.18, 1.0)

    /// The window's fade-in on open: `CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)`.
    nonisolated static let revealCurve = CubicBezier(0.16, 1, 0.3, 1)

    /// The pointer dips a little while the button is down, and comes back on release.
    static func pointerPress(_ t: Double, down: Double, up: Double) -> CGFloat {
        let depth = 0.12
        if t < down { return 1 }
        let pressed = Motion.settle(Motion.phase(t, down, 0.08))
        if t < up { return CGFloat(1 - depth * pressed) }
        let atUp = Motion.settle(Motion.phase(up, down, 0.08))
        return CGFloat(1 - depth * atUp * (1 - Motion.settle(Motion.phase(t, up, 0.14))))
    }

    // MARK: Drawing

    private static func writePNG<V: View>(_ view: V, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view.environment(\.bloomSnapshot, true))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    // MARK: The photo

    /// A photo-like landscape at dusk with film grain, written as PNG, its grain tuned so
    /// the file comes to about `bytes`.
    static func makePhoto(at url: URL, bytes: Int) -> Bool {
        let width = 2048, height = 1536
        guard let base = landscape(width: width, height: height) else { return false }
        var low = 0.0, high = 32.0
        var best: (amount: Double, gap: Int)?
        for _ in 0..<9 {
            let amount = (low + high) / 2
            guard let image = grained(base, width: width, height: height, amount: amount),
                  let size = writeImage(image, to: url) else { return false }
            if best == nil || abs(size - bytes) < best!.gap { best = (amount, abs(size - bytes)) }
            if abs(size - bytes) < bytes / 200 { return true }
            if size < bytes { low = amount } else { high = amount }
        }
        guard let best, let image = grained(base, width: width, height: height, amount: best.amount) else { return false }
        return writeImage(image, to: url) != nil
    }

    /// Writes a PNG and returns its size in bytes.
    private static func writeImage(_ image: CGImage, to url: URL) -> Int? {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return fileSize(url).map(Int.init)
    }

    /// Read afresh each time: a URL's resource values are cached.
    private static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// Sky, sun, two ranges of hills and a lake that mirrors them, in RGBA bytes.
    private static func landscape(width: Int, height: Int) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
        let horizon = h * 0.40
        // The sky, deep blue overhead to a warm glow at the horizon (y up).
        let sky = CGGradient(colorsSpace: space, colors: [color(1.00, 0.66, 0.38), color(0.93, 0.50, 0.46),
                                                         color(0.48, 0.36, 0.58), color(0.12, 0.17, 0.38)] as CFArray,
                             locations: [0, 0.18, 0.5, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: h), options: [.drawsBeforeStartLocation])
        // The sun and its glow.
        let sun = CGPoint(x: w * 0.63, y: horizon + h * 0.10)
        let glow = CGGradient(colorsSpace: space, colors: [color(1, 0.93, 0.75, 0.9), color(1, 0.75, 0.5, 0.35), color(1, 0.6, 0.4, 0)] as CFArray,
                              locations: [0, 0.25, 1])!
        ctx.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: h * 0.42, options: [])
        ctx.setFillColor(color(1, 0.96, 0.84))
        ctx.fillEllipse(in: CGRect(x: sun.x - 46, y: sun.y - 46, width: 92, height: 92))
        // Two ranges of hills, the far one hazy.
        func ridge(base: CGFloat, height amp: CGFloat, seed: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: CGFloat(0), through: w, by: 4) {
                let u = x / w
                let y = base + amp * (0.55 * sin(u * 7.1 + seed) + 0.3 * sin(u * 17.3 + seed * 2.1)
                                      + 0.15 * sin(u * 41.7 + seed * 3.7))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            return path
        }
        ctx.addPath(ridge(base: horizon + h * 0.07, height: h * 0.06, seed: 1.3))
        ctx.setFillColor(color(0.42, 0.33, 0.50))
        ctx.fillPath()
        ctx.addPath(ridge(base: horizon + h * 0.02, height: h * 0.05, seed: 4.2))
        ctx.setFillColor(color(0.20, 0.17, 0.29))
        ctx.fillPath()
        // The lake: the sky mirrored and darkened, with the sun's path broken by ripples.
        let lake = CGGradient(colorsSpace: space, colors: [color(0.80, 0.50, 0.40), color(0.30, 0.24, 0.40), color(0.08, 0.10, 0.20)] as CFArray,
                              locations: [0, 0.45, 1])!
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: horizon))
        ctx.drawLinearGradient(lake, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: 0), options: [])
        for i in 0..<70 {
            let y = horizon - CGFloat(i) * horizon / 70 - 3
            let spread = 30 + CGFloat(i) * 3.2
            let jitter = sin(CGFloat(i) * 12.9898) * spread * 0.4
            ctx.setFillColor(color(1, 0.86, 0.66, 0.55 - CGFloat(i) * 0.006))
            ctx.fill(CGRect(x: sun.x - spread / 2 + jitter, y: y, width: spread, height: 2.2))
        }
        ctx.restoreGState()
        // A dark shore in front.
        ctx.addPath(ridge(base: h * 0.07, height: h * 0.04, seed: 7.7))
        ctx.setFillColor(color(0.05, 0.05, 0.09))
        ctx.fillPath()
        guard let data = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    /// The picture with even film grain of `amount` levels, the same every time.
    private static func grained(_ pixels: [UInt8], width: Int, height: Int, amount: Double) -> CGImage? {
        var out = pixels
        var seed: UInt32 = 0x2545F491
        for i in stride(from: 0, to: out.count, by: 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let n = (Double(seed >> 8) / Double(1 << 24) - 0.5) * 2 * amount
            for c in 0..<3 {
                out[i + c] = UInt8(min(max(Double(out[i + c]) + n * (c == 2 ? 0.9 : 1), 0), 255))
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Parts

extension DemoRender {
    /// The app's rest timers, run on the fake clock in the order they fall due.
    final class Timers {
        private var pending: [(at: TimeInterval, work: DispatchWorkItem)] = []

        func add(at time: TimeInterval, _ work: DispatchWorkItem) {
            pending.append((time, work))
        }

        @MainActor
        func run(until time: TimeInterval, clock: BloomDebug.FakeClock) {
            while true {
                pending.removeAll { $0.work.isCancelled }
                guard let next = pending.indices.filter({ pending[$0].at <= time + 1e-9 })
                    .min(by: { pending[$0].at < pending[$1].at }) else { return }
                let item = pending.remove(at: next)
                clock.now = item.at
                item.work.perform()
            }
        }
    }

    /// What changed on the clover and when, to check the script against the app's rules.
    struct Log {
        var lines: [String] = []
        private var lit: Int?
        private var chips: Int?
        private var hint = ""
        private var phase = BloomModel.Phase.open

        @MainActor
        mutating func note(_ t: Double, _ m: BloomModel, titles: [String]) {
            func name(_ i: Int?) -> String { i.map { titles.indices.contains($0) ? titles[$0] : "\($0)" } ?? "none" }
            if m.events.lit != lit {
                lit = m.events.lit
                lines.append(String(format: "%6.3f lit %@", t, name(lit)))
            }
            if m.events.chipsLeaf != chips {
                chips = m.events.chipsLeaf
                lines.append(String(format: "%6.3f chips %@", t, name(chips)))
            }
            if m.hint != hint {
                hint = m.hint
                lines.append(String(format: "%6.3f capsule \"%@\"", t, hint))
            }
            if m.phase != phase {
                phase = m.phase
                lines.append(String(format: "%6.3f %@", t, phase == .dropping ? "dropped" : "\(phase)"))
            }
        }
    }

    /// One frame: the desktop, the clover's window at its alpha, the result chip at the
    /// clover's centre, where `ResultHUD` puts it, and the pointer on top.
    struct DemoFrame: View {
        @ObservedObject var model: BloomModel
        let now: TimeInterval
        let windowAlpha: Double
        @ObservedObject var chipState: ResultChipState
        let chip: ChipValues?
        let pointer: CGPoint
        let pointerScale: CGFloat

        var body: some View {
            let size = DemoRender.canvas
            let c = DemoRender.center
            ZStack(alignment: .topLeading) {
                DeskBackdrop(dark: true, width: size.width, height: size.height)
                if windowAlpha > 0 {
                    BloomView(model: model, time: now)
                        .compositingGroup()
                        .opacity(windowAlpha)
                        .position(c)
                }
                if let chip {
                    ResultChipView(state: chipState, actions: ChipActions(), values: chip)
                        .position(c)
                }
                ArrowPointer()
                    .scaleEffect(pointerScale, anchor: ArrowPointer.tipAnchor)
                    .position(x: c.x + pointer.x + ArrowPointer.size.width / 2 - ArrowPointer.tip.x,
                              y: c.y + pointer.y + ArrowPointer.size.height / 2 - ArrowPointer.tip.y)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .environment(\.colorScheme, .dark)
        }
    }

    /// A macOS-style arrow pointer, about 18 pt tall: black, with a white outline and a
    /// tiny shadow. Its tip is the hot spot.
    struct ArrowPointer: View {
        static let size = CGSize(width: 18, height: 24)
        static let tip = CGPoint(x: 3, y: 2.5)
        static var tipAnchor: UnitPoint { UnitPoint(x: tip.x / size.width, y: tip.y / size.height) }

        /// The arrow's black body, its tip at `tip`.
        static let shape: Path = {
            var p = Path()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: 0, y: 15.6))
            p.addLine(to: CGPoint(x: 3.7, y: 12.2))
            p.addLine(to: CGPoint(x: 6.2, y: 17.9))
            p.addLine(to: CGPoint(x: 8.6, y: 16.9))
            p.addLine(to: CGPoint(x: 6.2, y: 11.4))
            p.addLine(to: CGPoint(x: 11.2, y: 11.4))
            p.closeSubpath()
            return p.offsetBy(dx: tip.x, dy: tip.y)
        }()

        var body: some View {
            ZStack {
                ArrowPointer.shape
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.45), radius: 1.4, y: 1)
                ArrowPointer.shape.fill(Color.black)
            }
            .frame(width: ArrowPointer.size.width, height: ArrowPointer.size.height, alignment: .topLeading)
        }
    }
}

/// A CSS-style cubic Bézier easing from (0, 0) to (1, 1), as `CAMediaTimingFunction` draws it.
struct CubicBezier {
    let x1, y1, x2, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2)
    }

    func callAsFunction(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        // Find s where x(s) = t, by Newton's method with bisection to fall back on.
        var s = t
        for _ in 0..<8 {
            let error = curve(s, x1, x2) - t
            if abs(error) < 1e-7 { return curve(s, y1, y2) }
            let slope = derivative(s, x1, x2)
            if abs(slope) < 1e-6 { break }
            s -= error / slope
        }
        var low = 0.0, high = 1.0
        s = t
        for _ in 0..<50 {
            if curve(s, x1, x2) < t { low = s } else { high = s }
            s = (low + high) / 2
        }
        return curve(s, y1, y2)
    }

    private func curve(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - s
        return 3 * v * v * s * a + 3 * v * s * s * b + s * s * s
    }

    private func derivative(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - s
        return 3 * v * v * a + 6 * v * s * (b - a) + 3 * s * s * (1 - b)
    }
}
