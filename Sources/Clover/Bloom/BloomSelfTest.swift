import AppKit
import CloverCore

/// Checks the clover's leaves, geometry, hit-testing, edge clamping, More tray, model,
/// chip texts, the Finder selection parsing and the hold logic. Run with
/// `Clover --bloom-selftest`; exits 1 on any failure. Never runs AppleScript.
@MainActor
enum BloomSelfTest {
    private static var failures = 0
    private static var checks = 0

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL \(message())")
        }
    }

    static func run(model: AppModel) async -> Int32 {
        titles = ["More"] + LayoutKey.allCases.flatMap { model.catalog.allTargets(for: $0).map(\.title) }
        leaves()
        masks()
        geometry()
        chips()
        hitTesting()
        clamping()
        tray()
        chipStack()
        await bloomModel(model)
        chipTexts()
        finder()
        hold()
        reveal()
        print("\(checks - failures) of \(checks) checks passed")
        return failures == 0 ? 0 : 1
    }

    private typealias G = BloomGeometry
    private typealias L = BloomLayout

    private static func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    /// True when every corner and edge midpoint of `rect` is inside `path`.
    private static func inside(_ rect: CGRect, _ path: CGPath) -> Bool {
        let xs = [rect.minX, rect.midX, rect.maxX], ys = [rect.minY, rect.midY, rect.maxY]
        return xs.allSatisfy { x in ys.allSatisfy { y in path.contains(CGPoint(x: x, y: y)) } }
    }

    /// Shortest distance from a rectangle to an outline; negative when they overlap.
    private static func clearance(_ rect: CGRect, _ outline: [CGPoint], _ path: CGPath) -> CGFloat {
        if outline.contains(where: { rect.contains($0) }) || path.contains(center(rect)) { return -1 }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let fromCorners = corners.map { L.distance($0, toOutline: outline) }.min() ?? 0
        let fromOutline = outline.map { p in
            hypot(max(rect.minX - p.x, 0, p.x - rect.maxX), max(rect.minY - p.y, 0, p.y - rect.maxY))
        }.min() ?? 0
        return min(fromCorners, fromOutline)
    }

    // MARK: Leaves

    private static func leaves() {
        // Evenly spaced, the first at 12 o'clock, clockwise.
        for n in 1...G.maxLeaves {
            for i in 0..<n {
                let a = L.angle(i, of: n)
                expect(abs(a - CGFloat(i) * 2 * .pi / CGFloat(n)) < 1e-9, "leaf \(i) of \(n) at \(a)")
            }
        }
        expect(L.radial(0, of: 6) == CGVector(dx: 0, dy: -1), "the first leaf points up")
        let second = L.radial(1, of: 6)
        expect(second.dx > 0 && second.dy < 0, "the second leaf is clockwise, up right: \(second)")
        expect(L.radial(1, of: 4) == CGVector(dx: 1, dy: 0), "four leaves: the second at 3 o'clock")
    }

    // MARK: Glass masks

    /// The live blur is masked by an image of the leaf. It must be upright: the point at
    /// the bottom for the leaf at 12 o'clock, the notch at the top.
    private static func masks() {
        let bounds = L.leafBounds(0, of: 6)
        let image = PathEffectBlur.mask(LeafView.localPath(0, 6), key: "self-test leaf 0 of 6")
        let w = Int(bounds.width.rounded(.up)), h = Int(bounds.height.rounded(.up))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        expect(drawn, "the leaf mask draws")
        // Rows run from the top of the image.
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * w + x) * 4 + 3] }
        expect(alpha(w / 2, h - 12) > 128, "the mask's point is at the bottom")
        expect(alpha(w / 2, 4) < 128, "the mask's notch is at the top")
        expect(alpha(w / 4, h / 3) > 128 && alpha(3 * w / 4, h / 3) > 128, "the mask's lobes are at the top")
    }

    // MARK: Geometry

    /// Every title a leaf can show.
    private static var titles: [String] = []

    private static func geometry() {
        let size = L.leafBounds(0, of: 6).size
        for n in 1...G.maxLeaves {
            // Same leaf for 1 to 6 leaves.
            let s = L.leafBounds(0, of: n).size
            expect(abs(s.width - size.width) < 0.5 && abs(s.height - size.height) < 0.5, "leaf size with \(n) leaves: \(s)")
            for i in 0..<n {
                let path = L.leafPath(i, of: n)
                let outline = L.leafOutline(i, of: n)
                // The point is under the hub; the leaf reaches out past it.
                let tip = CGPoint(x: L.radial(i, of: n).dx * G.leafTip, y: L.radial(i, of: n).dy * G.leafTip)
                expect(L.distance(tip, .zero) < G.hubSize / 2, "leaf \(i) of \(n) starts under the hub")
                expect(outline.map { L.distance($0, .zero) }.max()! > G.hubSize / 2 + 60, "leaf \(i) of \(n) reaches out")
                // The label stands upright inside the leaf, clear of the hub, wide enough.
                let label = L.labelBox(i, of: n)
                let title = CGRect(x: label.minX, y: label.midY + 2, width: label.width, height: label.height / 2 - 2)
                let icon = CGRect(x: label.midX - 11, y: label.minY, width: 22, height: label.height / 2 - 1)
                expect(inside(title, path) && inside(icon, path), "leaf \(i) of \(n): label \(label) inside the leaf")
                // Every title fits at nine tenths of its size or more (it may shrink to three quarters).
                let widest = titles.map { BloomStyle.textWidth($0, font: BloomStyle.leafFont) }.max() ?? 0
                expect(label.width >= 0.9 * widest, "leaf \(i) of \(n): label width \(label.width) for titles up to \(widest)")
                let nearest = CGPoint(x: min(max(0, label.minX), label.maxX), y: min(max(0, label.minY), label.maxY))
                expect(L.distance(nearest, .zero) > G.hubSize / 2, "leaf \(i) of \(n): label clear of the hub")
                // No two leaves overlap.
                for j in 0..<n where j > i {
                    let other = L.leafPath(j, of: n)
                    expect(!outline.contains { other.contains($0) }, "leaves \(i) and \(j) of \(n) don't overlap")
                }
            }
        }
        // Six leaves nearly touch, like a clover.
        let dense = { (i: Int) in HeartLeaf.polygon(steps: 200).map { $0.applying(L.leafTransform(i, of: 6)) } }
        for i in 0..<6 {
            let a = dense(i), b = dense((i + 1) % 6)
            let gap = a.map { p in L.distance(p, toOutline: b) }.min()!
            expect(gap > 0.5 && gap < 6, "leaves \(i) and \(i + 1) of 6 nearly touch: gap \(gap)")
        }
        let half = G.panelSize / 2
        let panel = CGRect(x: -half, y: -half, width: G.panelSize, height: G.panelSize)
        let extent = BloomController.extent
        expect(panel.insetBy(dx: 4, dy: 4).contains(extent), "worst-case content \(extent) fits the panel")
        expect(extent.width > 2 * L.leafReach, "extent covers the leaves")
    }

    // MARK: Chips

    static let optionSets: [[String]] = [
        ["Best", "Balanced", "Small"],
        ["Original", "1080p", "720p", "Small"],
        ["Best", "Balanced", "Small", "Lossless"],
        ["Large", "Medium", "Small"],
        ["One PDF", "PDF per file"],
        ["Balanced", "Small"],
    ]

    static func widths(_ titles: [String]) -> [CGFloat] {
        titles.enumerated().map { i, title in
            L.chipWidth(textWidth: BloomStyle.textWidth(title), isDefault: i == 1)
        }
    }

    private static func chips() {
        let half = G.panelSize / 2
        let panel = CGRect(x: -half, y: -half, width: G.panelSize, height: G.panelSize)
        for n in 1...G.maxLeaves {
            for leaf in 0..<n {
                for titles in optionSets {
                    let frames = L.chipFrames(leaf, of: n, widths: widths(titles))
                    expect(frames.count == titles.count, "one frame per chip")
                    for (i, frame) in frames.enumerated() {
                        expect(panel.insetBy(dx: G.shadowMargin, dy: G.shadowMargin).contains(frame),
                               "\(n) leaves, leaf \(leaf): chip \(titles[i]) inside the panel: \(frame)")
                        for other in 0..<n {
                            let c = clearance(frame, L.leafOutline(other, of: n), L.leafPath(other, of: n))
                            expect(c >= 4, "\(n) leaves, leaf \(leaf): chip \(titles[i]) clears leaf \(other) by \(c)")
                        }
                        if i > 0 {
                            let prev = frames[i - 1]
                            let apart = max(frame.minX - prev.maxX, prev.minX - frame.maxX, frame.minY - prev.maxY, prev.minY - frame.maxY)
                            expect(apart >= G.chipGap - 1, "\(n) leaves, leaf \(leaf): chips \(i - 1),\(i) apart by \(apart)")
                            // Reading order: left to right, or top to bottom when stacked.
                            let t = L.across(leaf, of: n)
                            let step = (frame.midX - prev.midX) * t.dx + (frame.midY - prev.midY) * t.dy
                            expect(step > 0 && (t.dx > 0 || t.dy > 0), "\(n) leaves, leaf \(leaf): chips read in order")
                        }
                    }
                }
            }
        }
    }

    // MARK: Hit-testing

    private static func hitTesting() {
        for n in 1...G.maxLeaves {
            // Every point: the hub, the leaf whose real outline holds it, or nothing once
            // it is past the slop from every leaf.
            var wrong = 0
            for x in stride(from: -170.0, through: 170.0, by: 5) {
                for y in stride(from: -170.0, through: 170.0, by: 5) {
                    let p = CGPoint(x: x, y: y)
                    let hit = L.hit(p, count: n, open: nil, chips: [])
                    if L.distance(p, .zero) <= G.hubSize / 2 {
                        if hit != .hub { wrong += 1 }
                        continue
                    }
                    if let owner = (0..<n).first(where: { L.leafPath($0, of: n).contains(p) }) {
                        if hit != .leaf(owner) { wrong += 1 }
                    } else if (0..<n).allSatisfy({ L.distance(p, toOutline: L.leafOutline($0, of: n)) > G.leafHitSlop + 0.5 }) {
                        if hit != .none { wrong += 1 }
                    }
                }
            }
            expect(wrong == 0, "\(n) leaves: \(wrong) points hit the wrong thing")
            for leaf in 0..<n {
                expect(L.hit(center(L.labelBox(leaf, of: n)), count: n, open: nil, chips: []) == .leaf(leaf), "label of leaf \(leaf) of \(n)")
            }
        }
        // The notch between a leaf's lobes is not the leaf, unless its chips are open.
        let r = L.radial(0, of: 6)
        let notch = CGPoint(x: r.dx * (G.leafTip + 0.88 * G.leafSize), y: r.dy * (G.leafTip + 0.88 * G.leafSize))
        expect(!L.leafPath(0, of: 6).contains(notch), "the notch is outside the leaf")
        expect(L.hit(notch, count: 6, open: nil, chips: []) == .none, "the notch is nothing")
        expect(L.hit(.zero, count: 6, open: nil, chips: []) == .hub, "hub")
        expect(L.hit(CGPoint(x: 300, y: 0), count: 6, open: nil, chips: []) == .none, "far away")

        for n in [3, 4, 5, 6] {
            for leaf in 0..<n {
                let chips = L.chipFrames(leaf, of: n, widths: widths(["Best", "Balanced", "Small"]))
                for (i, frame) in chips.enumerated() {
                    expect(L.hit(center(frame), count: n, open: leaf, chips: chips) == .chip(leaf: leaf, index: i),
                           "chip \(i) of open leaf \(leaf) of \(n)")
                    expect(L.hit(center(frame), count: n, open: nil, chips: []) == .none, "closed chips don't react")
                }
                // The gap between the leaf and its chips keeps the leaf.
                let r = L.radial(leaf, of: n)
                let gap = L.leafReach + G.chipClearance / 2
                let gapPoint = CGPoint(x: r.dx * gap, y: r.dy * gap)
                expect(L.hit(gapPoint, count: n, open: leaf, chips: chips) == .leaf(leaf), "gap to chips keeps leaf \(leaf) of \(n)")
                expect(L.hit(notchPoint(leaf, n), count: n, open: leaf, chips: chips) == .leaf(leaf), "notch of open leaf \(leaf) of \(n) keeps it")
                if chips.count > 1 {
                    let mid = CGPoint(x: (chips[0].midX + chips[1].midX) / 2, y: (chips[0].midY + chips[1].midY) / 2)
                    expect(L.hit(mid, count: n, open: leaf, chips: chips).leaf == leaf, "between chips of \(leaf) stays on it")
                }
                let far = CGPoint(x: r.dx * 245, y: r.dy * 245)
                expect(L.hit(far, count: n, open: leaf, chips: chips) == .none, "beyond chips of \(leaf) of \(n)")
                // A neighbouring leaf wins over the open leaf's band.
                let next = (leaf + 1) % n
                if next != leaf {
                    expect(L.hit(center(L.labelBox(next, of: n)), count: n, open: leaf, chips: chips) == .leaf(next),
                           "neighbour \(next) over open \(leaf) of \(n)")
                }
            }
        }

        // View to clover coordinates: the view's y points up.
        let h = G.panelSize / 2
        expect(L.bloomPoint(fromView: CGPoint(x: h, y: h)) == .zero, "panel centre is the hub")
        expect(L.bloomPoint(fromView: CGPoint(x: h, y: h + 100)) == CGPoint(x: 0, y: -100), "up in the view is 12 o'clock")
    }

    private static func notchPoint(_ leaf: Int, _ n: Int) -> CGPoint {
        let r = L.radial(leaf, of: n)
        let d = G.leafTip + 0.88 * G.leafSize
        return CGPoint(x: r.dx * d, y: r.dy * d)
    }

    // MARK: Screen edges

    private static func clamping() {
        let bounds = BloomController.extent
        func fits(_ c: CGPoint, _ visible: CGRect) -> Bool {
            let onScreen = CGRect(x: c.x + bounds.minX, y: c.y - bounds.maxY, width: bounds.width, height: bounds.height)
            return visible.insetBy(dx: -0.5, dy: -0.5).contains(onScreen)
        }
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let middle = CGPoint(x: 700, y: 420)
        expect(L.clampedCenter(middle, bounds: bounds, visible: main) == middle, "middle stays put")
        let screens: [(String, CGRect, [CGPoint])] = [
            ("main", main, [CGPoint(x: 3, y: 3), CGPoint(x: 1437, y: 872), CGPoint(x: 3, y: 870), CGPoint(x: 1439, y: 1), CGPoint(x: 720, y: 870)]),
            ("right display", CGRect(x: 1440, y: -200, width: 1920, height: 1055), [CGPoint(x: 1441, y: 400), CGPoint(x: 3359, y: -199)]),
            ("left display", CGRect(x: -1728, y: 0, width: 1728, height: 1092), [CGPoint(x: -1, y: 1091), CGPoint(x: -1727, y: 5)]),
        ]
        for (name, visible, points) in screens {
            for p in points {
                let c = L.clampedCenter(p, bounds: bounds, visible: visible)
                expect(fits(c, visible), "\(name): clover at \(p) moved to \(c) fits \(visible)")
                expect(c.x == c.x.rounded() && c.y == c.y.rounded(), "whole points")
            }
        }
        // Near the left edge only x moves.
        let left = L.clampedCenter(CGPoint(x: 10, y: 420), bounds: bounds, visible: main)
        expect(left.y == 420 && left.x == (-bounds.minX).rounded(), "left edge moves x only: \(left)")
        // A screen smaller than the clover centres it.
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 300)
        expect(L.clampedCenter(CGPoint(x: 5, y: 5), bounds: bounds, visible: tiny) == CGPoint(x: 150, y: 150), "tiny screen")
    }

    // MARK: More tray

    private static func tray() {
        let w = TrayLayout.pillWidth(textWidths: ["WebP", "Compress", "ICNS"].map { BloomStyle.textWidth($0, font: BloomStyle.pillFont) })
        expect(w >= TrayLayout.pillMinWidth && w <= TrayLayout.pillMaxWidth, "pill width \(w)")
        let widest = TrayLayout.chipRowWidth(widths(["Best", "Balanced", "Small", "Lossless"]))
        for count in 1...14 {
            let size = TrayLayout.size(count: count, pillWidth: w, chipRow: widest)
            let pills = TrayLayout.pillFrames(count: count, pillWidth: w, trayWidth: size.width)
            let tray = CGRect(origin: .zero, size: size)
            expect(TrayLayout.columnCount(count) == min(3, count), "\(count) pills: \(TrayLayout.columnCount(count)) columns")
            expect(pills.allSatisfy { tray.insetBy(dx: TrayLayout.padding - 0.5, dy: TrayLayout.padding - 0.5).contains($0) },
                   "\(count) pills inside the tray")
            for i in pills.indices {
                for j in pills.indices where j > i { expect(!pills[i].intersects(pills[j]), "pills \(i) and \(j) apart") }
                let chips = TrayLayout.chipFrames(under: pills[i], widths: widths(["Best", "Balanced", "Small", "Lossless"]), trayWidth: size.width)
                expect(chips.allSatisfy { $0.minY >= pills[i].maxY && $0.minX >= TrayLayout.padding && $0.maxX <= size.width - TrayLayout.padding },
                       "\(count) pills: chips of \(i) under it, within the tray's width")
                expect(chips.allSatisfy { $0.maxY <= size.height + TrayLayout.overhang }, "\(count) pills: chips of \(i) within the window")
                for k in chips.indices.dropFirst() { expect(chips[k].minX >= chips[k - 1].maxX + G.chipGap - 0.5, "tray chips apart") }
                // Chips sit in the lane under their row: they never cover a pill.
                expect(chips.allSatisfy { chip in !pills.contains { $0.intersects(chip) } }, "\(count) pills: chips of \(i) cover no pill")
                let hit = TrayLayout.hit(center(pills[i]), pills: pills, open: nil, chips: [], size: size)
                expect(hit == .pill(i), "\(count) pills: centre of pill \(i) is \(hit)")
                for (k, chip) in chips.enumerated() {
                    expect(TrayLayout.hit(center(chip), pills: pills, open: i, chips: chips, size: size) == .chip(pill: i, index: k),
                           "chip \(k) of open pill \(i)")
                }
                // The strip between a pill and its chips keeps the pill.
                let strip = CGPoint(x: pills[i].midX, y: pills[i].maxY + TrayLayout.chipDrop / 2)
                expect(TrayLayout.hit(strip, pills: pills, open: i, chips: chips, size: size).pill == i, "strip under pill \(i)")
            }
            if count > 1 {
                let between = CGPoint(x: pills[0].maxX + TrayLayout.gap / 2, y: pills[0].midY)
                expect(TrayLayout.hit(between, pills: pills, open: nil, chips: [], size: size) == .background, "between pills")
            }
            expect(TrayLayout.hit(CGPoint(x: -20, y: 5), pills: pills, open: nil, chips: [], size: size) == .none, "outside the tray")
        }

        // Placement: beside More on its outer side, clear of every leaf when there's room,
        // never over More, and always on screen.
        let size = TrayLayout.size(count: 9, pillWidth: w, chipRow: widest)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        func place(_ c: CGPoint, _ visible: CGRect) -> (tray: CGRect, more: CGRect) {
            let more = L.screenRect(L.leafBounds(5, of: 6), center: c)
            return (TrayLayout.frame(size: size, more: more, clover: c, visible: visible), more)
        }
        let roomyCenter = CGPoint(x: 800, y: 400)
        let (roomy, roomyMore) = place(roomyCenter, screen)
        expect(roomy.maxX <= roomyMore.minX - TrayLayout.leafGap + 0.5, "More is on the left, so the tray is left of it: \(roomy)")
        expect(abs((roomy.minY + TrayLayout.overhang + size.height / 2) - roomyMore.midY) <= 1, "the tray is centred on More")
        let outlines = (0..<6).flatMap { i in L.leafOutline(i, of: 6).map { CGPoint(x: roomyCenter.x + $0.x, y: roomyCenter.y - $0.y) } }
        expect(!outlines.contains { roomy.contains($0) }, "with room, the tray covers no leaf")
        expect(roomy.height == size.height + TrayLayout.overhang, "the tray's frame has room for chips under its last row")
        let edges: [(CGPoint, CGRect)] = [
            (L.clampedCenter(CGPoint(x: 0, y: 875), bounds: BloomController.extent, visible: screen), screen),
            (L.clampedCenter(CGPoint(x: 0, y: 0), bounds: BloomController.extent, visible: screen), screen),
            (L.clampedCenter(CGPoint(x: 1440, y: 875), bounds: BloomController.extent, visible: screen), screen),
            (CGPoint(x: 420, y: 430), screen),
            (CGPoint(x: -1500, y: 800), CGRect(x: -1728, y: 0, width: 1728, height: 1092)),
            (CGPoint(x: 1700, y: 600), CGRect(x: 1440, y: -200, width: 1920, height: 1055)),
        ]
        for (c, visible) in edges {
            let (frame, more) = place(c, visible)
            expect(visible.insetBy(dx: TrayLayout.screenMargin - 0.5, dy: TrayLayout.screenMargin - 0.5).contains(frame),
                   "tray for a clover at \(c) stays on \(visible): \(frame)")
            expect(!frame.intersects(more.insetBy(dx: 2, dy: 2)), "tray for a clover at \(c) leaves More uncovered: \(frame) \(more)")
            expect(frame.minX == frame.minX.rounded() && frame.minY == frame.minY.rounded(), "tray on whole points")
        }
    }

    private static func chipStack() {
        let size = CGSize(width: 300, height: 56)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frames = ChipStackLayout.frames(count: 3, size: size, origin: CGPoint(x: 720, y: 500), visible: visible)
        expect(frames.count == 3, "three chips")
        expect(frames[0].maxY == 500 && frames[0].midX == 720, "first chip hangs from the origin")
        expect(frames[1].maxY < frames[0].minY && frames[2].maxY < frames[1].minY, "chips stack downward")
        expect(frames.allSatisfy { visible.contains($0) }, "chips on screen")
        let low = ChipStackLayout.frames(count: 3, size: size, origin: CGPoint(x: 720, y: 90), visible: visible)
        expect(low[1].minY > low[0].maxY, "near the bottom they stack upward")
        expect(low.allSatisfy { visible.contains($0) }, "low chips on screen")
        let corner = ChipStackLayout.cornerOrigin(size: size, visible: visible)
        let top = ChipStackLayout.frames(count: 2, size: size, origin: corner, visible: visible)
        expect(top[0].maxX == visible.maxX - 12 && top[0].maxY == visible.maxY - 12, "top right under the menu bar")
        let edge = ChipStackLayout.frames(count: 1, size: size, origin: CGPoint(x: 1430, y: 870), visible: visible)
        expect(visible.contains(edge[0]), "a chip at the edge is pulled in")
    }

    // MARK: Model

    private static func bloomModel(_ app: AppModel) async {
        let png = URL(fileURLWithPath: "/nonexistent/photo.png")
        let targets = app.targets(for: [png])
        let arrangement = LeafArranger.arrange(targets, layout: nil)
        let m = BloomModel()
        m.chipDelay = 0
        m.reset(mode: .click)
        m.setFiles([png], arrangement: arrangement)
        expect(arrangement.leaves.count == 5 && !arrangement.more.isEmpty, "a PNG has five leaves and More")
        expect(m.leafCount == 6 && m.moreIndex == 5 && m.isMore(5) && m.leaves.last == .more, "More is the sixth leaf")
        expect(m.target(at: 0)?.id == arrangement.leaves[0].id, "the first leaf is the first target")
        expect(m.hint == "photo.png", "one file's hint is its name")

        // The user's order decides the leaves.
        let mine = LeafArranger.arrange(targets, layout: LeafLayout(order: ["webp", "pdf"], hidden: ["jpg"]))
        let ordered = BloomModel()
        ordered.setFiles([png], arrangement: mine)
        expect(ordered.target(at: 0)?.id == "webp" && ordered.target(at: 1)?.id == "pdf", "user order: \(mine.leaves.map(\.id))")
        expect(!ordered.arrangement.all.contains { $0.id == "jpg" }, "hidden targets stay hidden")

        let first = m.target(at: 0)!
        let label0 = center(L.labelBox(0, of: 6))
        m.pointer(at: label0)
        expect(m.hover == .leaf(0) && m.openLeaf == 0, "resting on the first leaf opens its chips")
        expect(m.hint == BloomModel.hint(for: first, option: nil), "hint for the first leaf: \(m.hint)")
        expect(m.choice(at: m.hover)?.option == first.defaultOption, "leaf drop uses the default")
        let chips = m.chipFrames(for: 0)
        if chips.count >= 2 {
            m.pointer(at: center(chips[1]))
            expect(m.hover == .chip(leaf: 0, index: 1), "on the second chip")
            expect(m.choice(at: m.hover)?.option == first.options[1], "chip drop uses its option")
        } else {
            expect(false, "the first leaf has chips")
        }
        m.pointer(at: .zero)
        expect(m.openLeaf == nil && m.hover == .hub, "back on the hub closes the chips")
        expect(m.hint == "photo.png", "hint back to the file")

        // The rest delay: chips wait, then open.
        m.chipDelay = 0.05
        m.pointer(at: center(L.labelBox(1, of: 6)))
        expect(m.openLeaf == nil, "chips wait before opening")
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(m.openLeaf == 1, "chips open after resting")
        m.chipDelay = 0

        // Click mode: hovering More does nothing; clicking it opens the tray.
        let moreLabel = center(L.labelBox(5, of: 6))
        m.moreDelay = 0.05
        m.pointer(at: moreLabel)
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(!m.trayOpen, "in click mode, resting on More doesn't open the tray")
        expect(m.hint == "\(arrangement.more.count) more formats", "More's hint: \(m.hint)")
        m.toggleTray()
        expect(m.trayOpen && m.litLeaf == 5, "clicking More opens the tray, More lit")
        m.toggleTray()
        expect(!m.trayOpen, "clicking More again closes it")

        // Drag mode: resting on More opens the tray; it stays open off the clover and
        // closes back on a leaf or the hub.
        var changes: [Bool] = []
        m.onTrayChange = { changes.append($0) }
        m.mode = .drag
        m.pointer(at: .zero)
        m.pointer(at: moreLabel)
        expect(!m.trayOpen, "the tray waits")
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(m.trayOpen && changes == [true], "resting on More opens the tray")
        m.pointer(at: CGPoint(x: 0, y: -240))
        expect(m.trayOpen, "the gap between More and the tray keeps it open")
        m.pointerLeft()
        let pills = m.pillFrames
        m.trayPointer(at: center(pills[0]))
        expect(m.trayHover == .pill(0) && m.litPill == 0, "on the first pill")
        let pill0 = m.pillTarget(0)!
        expect(m.trayChoice(at: m.trayHover)?.target.id == pill0.id, "a drop on a pill converts with it")
        expect(m.hint == BloomModel.hint(for: pill0, option: nil), "pill hint: \(m.hint)")
        if let withOptions = m.arrangement.more.firstIndex(where: { !$0.options.isEmpty }) {
            m.trayPointer(at: center(pills[withOptions]))
            expect(m.openPill == withOptions, "a pill with options shows its chips")
            let pillChips = m.pillChipFrames(for: withOptions)
            m.trayPointer(at: center(pillChips.last!))
            let target = m.pillTarget(withOptions)!
            expect(m.trayHover == .chip(pill: withOptions, index: pillChips.count - 1), "on the pill's last chip")
            expect(m.trayChoice(at: m.trayHover)?.option == target.options.last, "a drop on a pill chip uses its option")
        }
        m.trayPointerLeft()
        m.pointer(at: moreLabel)
        expect(m.trayOpen, "back on More keeps the tray")
        m.pointer(at: label0)
        expect(!m.trayOpen && changes == [true, false], "back on another leaf closes the tray")
        m.pointer(at: moreLabel)
        try? await Task.sleep(nanoseconds: 150_000_000)
        m.pointer(at: .zero)
        expect(!m.trayOpen, "the hub closes it too")
        m.mode = .click
        m.onTrayChange = nil

        // Keyboard.
        m.pointerLeft()
        m.moveFocus(by: 1)
        expect(m.focus == .leaf(0) && m.litLeaf == 0 && m.usingKeyboard, "arrow focuses 12 o'clock first")
        m.moveFocus(by: -1)
        expect(m.focus == .leaf(5), "left goes counter-clockwise, to More: \(String(describing: m.focus))")
        m.focusNumber(1)
        m.moveChipFocus(by: 1)
        expect(m.keyboardChoice?.option == first.options.first, "down onto the first chip")
        m.moveChipFocus(by: -1)
        expect(m.focusChip == nil && m.keyboardChoice?.option == first.defaultOption, "up back to the leaf")
        m.focusNumber(9)
        expect(m.focus == .leaf(0), "no ninth leaf")
        // Tab: every leaf, then into the tray, then around.
        for _ in 0..<4 { m.tab(forward: true) }
        expect(m.focus == .leaf(4) && !m.trayOpen, "Tab walks the leaves")
        m.tab(forward: true)
        expect(m.focus == .pill(0) && m.trayOpen && m.litLeaf == 5, "Tab past the last leaf opens the tray")
        m.moveFocus(by: 1)
        expect(m.focus == .pill(1), "arrows move between pills")
        for _ in 0..<m.arrangement.more.count - 1 { m.tab(forward: true) }
        expect(m.focus == .leaf(0) && !m.trayOpen, "Tab past the last pill comes back to the first leaf")
        m.tab(forward: false)
        expect(m.focus == .pill(m.arrangement.more.count - 1) && m.trayOpen, "Shift-Tab from the first leaf goes to the last pill")
        expect(m.escape() && !m.trayOpen && m.focus == .leaf(5), "Esc closes the tray, back on More")
        expect(!m.escape(), "a second Esc is for the clover")
        expect(m.focusIsMore, "More has the focus")
        m.openTray(focusFirst: true)
        expect(m.focus == .pill(0) && m.trayOpen, "Return on More opens the tray at the first pill")
        if let withOptions = m.arrangement.more.firstIndex(where: { !$0.options.isEmpty }) {
            while m.focus != .pill(withOptions) { m.moveFocus(by: 1) }
            m.moveChipFocus(by: 1)
            expect(m.keyboardChoice?.option == m.pillTarget(withOptions)?.options.first, "down onto a pill's first chip")
        }
        m.focusNumber(2)
        expect(m.focus == .leaf(1) && !m.trayOpen, "a digit goes back to the leaves")
        m.pointer(at: label0)
        expect(!m.usingKeyboard && m.litLeaf == 0, "the pointer takes over from the keys")

        // Three to five leaves, no More.
        for n in 3...5 {
            m.setFiles([png], arrangement: Arrangement(leaves: Array(targets.prefix(n)), more: []))
            expect(m.leafCount == n && m.moreIndex == nil, "\(n) leaves without More")
            m.pointer(at: center(L.labelBox(n - 1, of: n)))
            expect(m.hover == .leaf(n - 1), "the last of \(n) leaves")
            m.openTray(focusFirst: false)
            expect(!m.trayOpen, "no tray without More")
        }

        // Many files, mixed files, nothing to do.
        let twelve = (1...12).map { URL(fileURLWithPath: "/nonexistent/IMG_\($0).png") }
        m.setFiles(twelve, arrangement: app.arrangement(for: twelve))
        expect(m.summary == "PNG · 12 files", "twelve PNGs: \(m.summary)")
        if let pdf = m.arrangement.all.first(where: { $0.id == "pdf" }), pdf.mode == .byOption {
            expect(BloomModel.hint(for: pdf, option: pdf.options.first) == "One PDF", "byOption chip hint")
        } else {
            expect(false, "twelve PNGs can make one PDF or many")
        }
        let mixed = [URL(fileURLWithPath: "/nonexistent/a.png"), URL(fileURLWithPath: "/nonexistent/b.mp3")]
        m.setFiles(mixed, arrangement: app.arrangement(for: mixed))
        expect(m.isMixed && m.summary == "2 files", "mixed summary: \(m.summary)")
        expect(m.arrangement.all.contains { $0.id == "zip" }, "mixed files can still be zipped")
        m.setFiles([png], arrangement: Arrangement(leaves: [], more: []))
        expect(m.hint == "Clover can't convert these" && m.leaves.isEmpty, "no targets: hub only")
        m.focusNumber(1)
        m.tab(forward: true)
        m.moveFocus(by: 1)
        expect(m.focus == nil, "no leaves, no focus")
        m.reset(mode: .drag)
        expect(!m.hasFiles && m.hint.isEmpty && m.leaves.isEmpty, "a drag not yet over the clover shows the hub only")
    }

    // MARK: Chip texts

    private static func chipTexts() {
        func display(_ s: JobSnapshot) -> ChipDisplay { ChipDisplay(s) }
        let batch = display(JobSnapshot(phase: .running, title: "Convert to JPG", formatName: "JPG", family: .image,
                                        inputNames: Array(repeating: "a.png", count: 12), finished: 7, total: 12))
        expect(batch.kind == .running && batch.subtitle == "7 of 12" && batch.canCancel, "batch: \(batch.subtitle)")
        let done = display(JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                       inputNames: ["photo.png"], outputNames: ["photo.jpg"], finished: 1,
                                       bytesIn: 3_333_333, bytesOut: 1_200_000))
        expect(done.title == "photo.jpg" && done.subtitle == "1.2 MB · 64 % smaller" && done.canUndo, "done: \(done.subtitle)")
        expect(ChipDisplay.sizeChange(from: 1_000_000, to: 1_380_000) == "1.4 MB · 38 % larger", "larger")
        expect(ChipDisplay.sizeChange(from: 1_000_000, to: 1_001_000)?.hasSuffix("same size") == true, "same size")
        let partial = display(JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                          inputNames: [], outputNames: Array(repeating: "x.jpg", count: 9), finished: 12, total: 12,
                                          failures: [("a", "bad"), ("b", "bad"), ("c", "bad")]))
        expect(partial.kind == .partial && partial.title == "9 converted · 3 failed", "partial: \(partial.title)")
        let skipped = display(JobSnapshot(phase: .failed("Already JPG."), title: "Convert to JPG", formatName: "JPG",
                                          family: .image, inputNames: ["photo.jpg"], finished: 1, skipped: 1))
        expect(skipped.kind == .skipped && skipped.title == "Already JPG" && !skipped.canUndo, "skipped: \(skipped.title)")
        let failed = display(JobSnapshot(phase: .failed("Clover can't convert images yet."), title: "Convert to JPG",
                                         formatName: "JPG", family: .image, inputNames: ["photo.png"], finished: 1,
                                         failures: [("photo.png", "Clover can't convert images yet.")]))
        expect(failed.kind == .failed && failed.title == "Couldn't convert to JPG"
               && failed.subtitle == "Clover can't convert images yet.", "failed: \(failed.title)")
        expect(ChipDisplay.couldNot("Merge") == "Couldn't merge", "couldn't merge")
        let undone = display(JobSnapshot(phase: .undone, title: "Convert to JPG", formatName: "JPG", family: .image,
                                         inputNames: ["photo.png"], outputNames: ["photo.jpg"]))
        expect(undone.kind == .undone && undone.subtitle == "photo.jpg moved to the Trash", "undone")
        let cancelled = display(JobSnapshot(phase: .cancelled, title: "Convert to MP4", formatName: "MP4", family: .video,
                                            inputNames: ["trip.mov"]))
        expect(cancelled.kind == .cancelled && !cancelled.canUndo && !cancelled.canCancel, "cancelled")
    }

    // MARK: Finder and the hold

    private static func finder() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "/Users/someone/Desktop/photo one.png"), at: 0)
        list.insert(NSAppleEventDescriptor(fileURL: URL(fileURLWithPath: "/Users/someone/Documents/report.pdf")), at: 0)
        list.insert(NSAppleEventDescriptor(string: "/Users/someone/Desktop/Folder/"), at: 0)
        list.insert(NSAppleEventDescriptor(string: "not a path"), at: 0)
        let urls = FinderSelection.urls(from: list)
        expect(urls.map(\.path) == ["/Users/someone/Desktop/photo one.png", "/Users/someone/Documents/report.pdf",
                                    "/Users/someone/Desktop/Folder"], "selection paths, text that isn't a path dropped: \(urls.map(\.path))")
        expect(urls.allSatisfy(\.isFileURL), "file URLs")
        expect(FinderSelection.urls(from: .list()).isEmpty, "nothing selected")
        expect(FinderSelection.urls(from: .null()).isEmpty, "no result")
        expect(FinderSelection.urls(from: NSAppleEventDescriptor(string: "/tmp/one.txt")).map(\.path) == ["/tmp/one.txt"], "a single path")
        expect(FinderSelection.failure(from: [NSAppleScript.errorNumber: -1743, NSAppleScript.errorMessage: "Not authorized"]) == .notPermitted,
               "-1743 is a refused permission")
        expect(FinderSelection.failure(from: [NSAppleScript.errorNumber: -1744]) == .notPermitted, "-1744 too")
        expect(FinderSelection.failure(from: [NSAppleScript.errorNumber: -600, NSAppleScript.errorMessage: "Not running"]) == .script(-600, "Not running"),
               "other errors are kept")
        expect(FinderSelection.source.contains("get selection as alias list"), "the script asks for aliases")
    }

    private static func hold() {
        let start = CGPoint(x: 500, y: 300)
        var watch = HoldWatch(start: start, keyDown: false)
        expect(watch.update(buttonDown: true, location: start, keyDown: false) == .wait, "holding still waits")
        expect(watch.update(buttonDown: true, location: CGPoint(x: 502, y: 301), keyDown: false) == .wait, "a tremble still waits")
        expect(watch.update(buttonDown: true, location: CGPoint(x: 502, y: 301), keyDown: true) == .fire, "the key going down opens")
        expect(watch.update(buttonDown: true, location: CGPoint(x: 502, y: 301), keyDown: true) == .wait, "held, it opens once")

        var moved = HoldWatch(start: start, keyDown: false)
        expect(moved.update(buttonDown: true, location: CGPoint(x: 505, y: 300), keyDown: true) == .stop, "moving 5 pt is a drag")
        var released = HoldWatch(start: start, keyDown: false)
        expect(released.update(buttonDown: false, location: start, keyDown: true) == .stop, "letting go ends the hold")

        // Shift-click in Finder: the key was already down.
        var shiftClick = HoldWatch(start: start, keyDown: true)
        expect(shiftClick.update(buttonDown: true, location: start, keyDown: true) == .wait, "a Shift-click doesn't open")
        expect(shiftClick.update(buttonDown: true, location: start, keyDown: false) == .wait, "the key comes up")
        expect(shiftClick.update(buttonDown: true, location: start, keyDown: true) == .fire, "and down again opens")
    }

    private static func reveal() {
        let out = [URL(fileURLWithPath: "/tmp/photo.jpg")]
        expect(ResultHUD.shouldReveal(.done, outputs: out, enabled: true), "done, with files, on: reveal")
        expect(!ResultHUD.shouldReveal(.done, outputs: out, enabled: false), "off: no reveal")
        expect(!ResultHUD.shouldReveal(.done, outputs: [], enabled: true), "no files: no reveal")
        expect(!ResultHUD.shouldReveal(.failed("x"), outputs: out, enabled: true), "failed: no reveal")
        expect(!ResultHUD.shouldReveal(.cancelled, outputs: out, enabled: true), "cancelled: no reveal")
    }
}
