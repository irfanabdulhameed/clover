import AppKit
import CloverCore

/// Checks the clover's slots, geometry, hit-testing, edge clamping, More tray, model,
/// motion curves, chip texts, the Finder selection parsing and the hold logic. Run with
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
        let targets = LayoutKey.allCases.flatMap { model.catalog.allTargets(for: $0) }
        titles = ["More"] + targets.map(\.title)
        toolTitles = ["More"] + targets.filter(BloomStyle.isTool).map(\.title)
        formatTitles = targets.filter { !BloomStyle.isTool($0) }.map(\.title)
        leaves()
        slotShapes()
        geometry()
        chips()
        hitTesting()
        clamping()
        tray()
        chipStack()
        await bloomModel(model)
        motion()
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

    /// True when points every 2 pt along `rect`'s edges are inside `path`.
    private static func edgesInside(_ rect: CGRect, _ path: CGPath) -> Bool {
        var points: [CGPoint] = []
        for x in stride(from: rect.minX, through: rect.maxX, by: 2) { points += [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)] }
        for y in stride(from: rect.minY, through: rect.maxY, by: 2) { points += [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)] }
        return points.allSatisfy { path.contains($0) }
    }

    // MARK: Slot shapes

    /// Each slot is a clover leaflet: a narrow base at the centre circle, two lobes reaching
    /// the rim's inset, and a shallow notch between them, on the slot's axis.
    private static func slotShapes() {
        let depth = G.slotOuter - G.slotInner
        for n in 1...G.maxLeaves {
            let path = L.leafPath(0, of: n)
            let outline = L.leafOutline(0, of: n)
            let radii = outline.map { L.distance($0, .zero) }
            expect(abs(radii.max()! - G.slotOuter) < 1.5, "\(n) slots: lobes reach \(radii.max()!), want \(G.slotOuter)")
            expect(radii.min()! >= G.slotInner - 0.5, "\(n) slots: the base \(radii.min()!) stays off the centre circle")
            let notch = SlotShape.notchDepth(count: n)
            expect(notch >= 0.10 * depth && notch <= 0.24 * depth, "\(n) slots: notch \(notch) of a \(depth) slot")
            if n >= 5 { expect(notch <= 0.145 * depth, "\(n) slots: a shallow notch, \(notch / depth)") }
            // The notch is on the axis at the outer end: in front of it is the leaf, past it isn't.
            let floor = G.slotOuter - notch
            expect(path.contains(CGPoint(x: 0, y: -(floor - 5))), "\(n) slots: the leaf runs up to the notch")
            expect(!path.contains(CGPoint(x: 0, y: -(floor + 3))), "\(n) slots: the notch is open")
            // The two lobes beside it reach further out than the notch.
            let lobe = SlotShape.sideAngle(G.slotOuter, count: n) * 0.5
            for side: CGFloat in [-1, 1] {
                let r = G.slotOuter - 3
                expect(path.contains(CGPoint(x: side * r * sin(lobe), y: -r * cos(lobe))), "\(n) slots: lobe \(side) reaches the rim's inset")
            }
            // The base is narrower than the broad part: the arc across the slot at each radius.
            func across(_ r: CGFloat) -> CGFloat {
                let inside = stride(from: -CGFloat.pi, through: CGFloat.pi, by: 0.002).filter {
                    path.contains(CGPoint(x: r * sin($0), y: -r * cos($0)))
                }
                guard let low = inside.min(), let high = inside.max() else { return 0 }
                return r * (high - low)
            }
            let base = across(G.slotInner + 6), broad = across(G.labelRadius)
            expect(base > 20 && base < broad * 0.45, "\(n) slots: narrow base \(base) under a broad part \(broad)")
        }
    }

    // MARK: Geometry

    /// Every title a slot can show; those with a small icon (tools and More), and formats.
    private static var titles: [String] = []
    private static var toolTitles: [String] = []
    private static var formatTitles: [String] = []

    private static func geometry() {
        func widest(_ list: [String]) -> CGFloat { list.map { BloomStyle.textWidth($0, font: BloomStyle.leafSmallFont) }.max() ?? 0 }
        let widestFormat = widest(formatTitles), widestTool = widest(toolTitles)
        expect(widestFormat > 40 && widestTool > 40, "titles measured: formats \(widestFormat), tools \(widestTool)")
        for n in 1...G.maxLeaves {
            for i in 0..<n {
                let path = L.leafPath(i, of: n)
                let outline = L.leafOutline(i, of: n)
                // Inside the band between the centre circle and the rim.
                let radii = outline.map { L.distance($0, .zero) }
                expect(radii.min()! >= G.slotInner - 0.5 && radii.max()! <= G.slotOuter + 0.5,
                       "slot \(i) of \(n) inside the band: \(radii.min()!)...\(radii.max()!)")
                // Its own sector.
                expect(L.sector(L.leafCenter(i, of: n), count: n) == i, "slot \(i) of \(n) in its sector")
                // The label stands upright inside the slot, clear of the hub, wide enough: a
                // title alone, or a tool's icon over its title.
                for withIcon in [false, true] {
                    let label = L.labelBox(i, of: n, icon: withIcon)
                    let c8 = G.labelClearance
                    let titleTop = withIcon ? label.minY + G.labelIcon.height + G.labelIconGap : label.minY
                    let text = CGRect(x: label.minX - c8, y: titleTop - (withIcon ? 0 : c8), width: label.width + 2 * c8,
                                      height: label.maxY + c8 - (titleTop - (withIcon ? 0 : c8))).insetBy(dx: 0.75, dy: 0.75)
                    let iconArea = CGRect(x: label.midX - G.labelIcon.width / 2 - c8, y: label.minY - c8,
                                          width: G.labelIcon.width + 2 * c8, height: titleTop - label.minY + c8).insetBy(dx: 0.75, dy: 0.75)
                    expect(edgesInside(text, path) && (!withIcon || edgesInside(iconArea, path)),
                           "slot \(i) of \(n)\(withIcon ? " with an icon" : ""): 8 pt clear around the label \(label)")
                    // Every title fits at 14 pt or more. In a three-slot clover the leaves at 4 and
                    // 8 o'clock lie across, so a tool's title may shrink a little further there.
                    let need = withIcon ? (n == 3 ? 0.8 * widestTool : widestTool) : widestFormat
                    expect(label.width >= need, "slot \(i) of \(n)\(withIcon ? " with an icon" : ""): label width \(label.width) for titles up to \(need)")
                    let nearest = CGPoint(x: min(max(0, label.minX), label.maxX), y: min(max(0, label.minY), label.maxY))
                    expect(L.distance(nearest, .zero) > G.hubSize / 2 + 2, "slot \(i) of \(n): label clear of the hub")
                    expect(abs(L.distance(label.mid, .zero) - G.labelRadius) < 32, "slot \(i) of \(n): label near 72 % of the radius")
                }
                let label = L.labelBox(i, of: n)
                // No two slots overlap; neighbours keep the gap, so the disc's glass shows between them.
                for j in 0..<n where j > i {
                    let other = L.leafPath(j, of: n)
                    expect(!outline.contains { other.contains($0) }, "slots \(i) and \(j) of \(n) don't overlap")
                }
                if n >= 3 {
                    let next = L.leafOutline((i + 1) % n, of: n)
                    let gap = outline.map { L.distance($0, toOutline: next) }.min()!
                    // Six and five pack at the gap; fewer, wider leaves keep a little more air.
                    let most: CGFloat = n >= 5 ? G.slotGap + 3.5 : (n == 4 ? G.slotGap + 6 : G.slotGap + 22)
                    expect(gap >= G.slotGap - 0.75 && gap < most, "slots \(i) and \(i + 1) of \(n): gap \(gap)")
                }
                // The midrib stays inside the slot and off the label.
                for (a, b) in L.midrib(i, of: n) {
                    expect(path.contains(a) && path.contains(b), "slot \(i) of \(n): midrib inside")
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    expect(!label.contains(mid), "slot \(i) of \(n): midrib off the label")
                }
            }
        }
        let half = G.panelSize / 2
        let panel = CGRect(x: -half, y: -half, width: G.panelSize, height: G.panelSize)
        let extent = BloomController.extent
        expect(panel.insetBy(dx: 4, dy: 4).contains(extent), "worst-case content \(extent) fits the panel")
        expect(extent.width >= 2 * G.discRadius, "extent covers the disc")
        expect(G.discRadius * 2 == 380 && G.hubSize == 120, "a 380 pt disc with a 120 pt centre")
        expect(G.slotGap == 14 && G.slotInset == 10, "air: 14 pt between slots, 10 pt off the rim and the centre")
        expect(G.labelRadius == 137, "labels at 72 % of the radius")
        expect(Motion.Open.ringTo > G.discRadius && Motion.Open.ringTo < half, "the ring of light passes the rim and stays in the panel")
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
                        let c = L.nearest(frame) - G.discRadius
                        expect(c >= G.chipClearance - 0.75, "\(n) slots, slot \(leaf): chip \(titles[i]) clears the disc by \(c)")
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
            // Every point: the hub, the slot whose sector holds it out to the disc's edge
            // (its gaps and rim included), or nothing beyond.
            var wrong = 0
            for x in stride(from: -220.0, through: 220.0, by: 5) {
                for y in stride(from: -220.0, through: 220.0, by: 5) {
                    let p = CGPoint(x: x, y: y)
                    let hit = L.hit(p, count: n, open: nil, chips: [])
                    let r = L.distance(p, .zero)
                    if r <= G.hubSize / 2 {
                        if hit != .hub { wrong += 1 }
                    } else if r > G.hubSize / 2 + G.slotInset && r <= G.discRadius {
                        if hit != .leaf(L.sector(p, count: n)) { wrong += 1 }
                        // A point on a slot's drawn shape hits that slot.
                        if let owner = (0..<n).first(where: { L.leafPath($0, of: n).contains(p) }), hit != .leaf(owner) { wrong += 1 }
                    } else if r > G.discRadius + G.leafHitSlop {
                        if hit != .none { wrong += 1 }
                    }
                }
            }
            expect(wrong == 0, "\(n) slots: \(wrong) points hit the wrong thing")
            for leaf in 0..<n {
                expect(L.hit(center(L.labelBox(leaf, of: n)), count: n, open: nil, chips: []) == .leaf(leaf), "label of slot \(leaf) of \(n)")
                // The notch and the rim beyond a slot are still that slot.
                expect(L.hit(notchPoint(leaf, n), count: n, open: nil, chips: []) == .leaf(leaf), "notch of slot \(leaf) of \(n)")
                let r = L.radial(leaf, of: n)
                let rim = CGPoint(x: r.dx * (G.discRadius - 4), y: r.dy * (G.discRadius - 4))
                expect(L.hit(rim, count: n, open: nil, chips: []) == .leaf(leaf), "rim beyond slot \(leaf) of \(n)")
            }
        }
        expect(L.hit(.zero, count: 6, open: nil, chips: []) == .hub, "hub")
        expect(L.hit(CGPoint(x: 120, y: 0), count: 0, open: nil, chips: []) == .none, "no slots: the disc is nothing")
        expect(L.hit(CGPoint(x: 290, y: 0), count: 6, open: nil, chips: []) == .none, "far away")

        for n in [3, 4, 5, 6] {
            for leaf in 0..<n {
                let chips = L.chipFrames(leaf, of: n, widths: widths(["Best", "Balanced", "Small"]))
                for (i, frame) in chips.enumerated() {
                    expect(L.hit(center(frame), count: n, open: leaf, chips: chips) == .chip(leaf: leaf, index: i),
                           "chip \(i) of open slot \(leaf) of \(n)")
                    expect(L.hit(center(frame), count: n, open: nil, chips: []) == .none, "closed chips don't react")
                }
                // The gap between the disc and its chips keeps the slot.
                let r = L.radial(leaf, of: n)
                let gap = G.discRadius + G.leafHitSlop + 1
                let gapPoint = CGPoint(x: r.dx * gap, y: r.dy * gap)
                expect(L.hit(gapPoint, count: n, open: leaf, chips: chips) == .leaf(leaf), "gap to chips keeps slot \(leaf) of \(n)")
                if chips.count > 1 {
                    let mid = CGPoint(x: (chips[0].midX + chips[1].midX) / 2, y: (chips[0].midY + chips[1].midY) / 2)
                    expect(L.hit(mid, count: n, open: leaf, chips: chips).leaf == leaf, "between chips of \(leaf) stays on it")
                }
                let far = CGPoint(x: r.dx * 292, y: r.dy * 292)
                expect(L.hit(far, count: n, open: leaf, chips: chips) == .none, "beyond chips of \(leaf) of \(n)")
                // A neighbouring slot wins over the open slot's band.
                let next = (leaf + 1) % n
                expect(L.hit(center(L.labelBox(next, of: n)), count: n, open: leaf, chips: chips) == .leaf(next),
                       "neighbour \(next) over open \(leaf) of \(n)")
            }
        }

        // View to clover coordinates: the view's y points up.
        let h = G.panelSize / 2
        expect(L.bloomPoint(fromView: CGPoint(x: h, y: h)) == .zero, "panel centre is the hub")
        expect(L.bloomPoint(fromView: CGPoint(x: h, y: h + 100)) == CGPoint(x: 0, y: -100), "up in the view is 12 o'clock")
    }

    private static func notchPoint(_ leaf: Int, _ n: Int) -> CGPoint {
        let r = L.radial(leaf, of: n)
        let d = G.slotOuter - SlotShape.notchDepth(count: n) / 2
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
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 400)
        expect(L.clampedCenter(CGPoint(x: 5, y: 5), bounds: bounds, visible: tiny) == CGPoint(x: 200, y: 200), "tiny screen")
        // The smallest Mac screen in use still fits the whole clover, chips included.
        expect(bounds.width <= 1280 - 16 && bounds.height <= 800 - 40, "the clover fits a 1280 x 800 screen: \(bounds.size)")
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
            let more = L.screenRect(L.sectorBounds(5, of: 6), center: c)
            return (TrayLayout.frame(size: size, more: more, clover: c, visible: visible), more)
        }
        let roomyCenter = CGPoint(x: 800, y: 400)
        let (roomy, roomyMore) = place(roomyCenter, screen)
        expect(roomy.maxX <= roomyMore.minX - TrayLayout.leafGap + 0.5, "More is on the left, so the tray is left of it: \(roomy)")
        expect(abs((roomy.minY + TrayLayout.overhang + size.height / 2) - roomyMore.midY) <= 1, "the tray is centred on More")
        let nearestToClover = CGPoint(x: min(max(roomyCenter.x, roomy.minX), roomy.maxX), y: min(max(roomyCenter.y, roomy.minY), roomy.maxY))
        expect(L.distance(nearestToClover, roomyCenter) >= G.discRadius, "with room, the tray covers no part of the disc")
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
        m.hoverDelay = 0
        m.reset(mode: .click)
        m.setFiles([png], arrangement: arrangement)
        expect(arrangement.leaves.count == 5 && !arrangement.more.isEmpty, "a PNG has five leaves and More")
        expect(m.leafCount == 6 && m.moreIndex == 5 && m.isMore(5) && m.leaves.last == .more, "More is the sixth leaf")
        expect(m.target(at: 0)?.id == arrangement.leaves[0].id, "the first leaf is the first target")
        expect(m.hint == "photo.png", "one file without a size: its name")
        m.pointer(at: .zero)
        expect(m.hint == "photo.png", "resting on the centre shows the name")
        m.pointerLeft()

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
        expect(m.hint == "\(arrangement.more.count) more", "More's hint: \(m.hint)")
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
        expect(m.hint == "Can't convert" && m.leaves.isEmpty, "no targets: hub only")
        m.focusNumber(1)
        m.tab(forward: true)
        m.moveFocus(by: 1)
        expect(m.focus == nil, "no leaves, no focus")
        m.reset(mode: .drag)
        expect(!m.hasFiles && m.hint.isEmpty && m.leaves.isEmpty, "a drag not yet over the clover shows the hub only")

        // The rest before a slot lights, then the light moves with the pointer.
        var now: TimeInterval = 5000
        var ticks = 0
        let r = BloomModel()
        r.clock = { now }
        r.chipDelay = 0
        r.hoverDelay = 0.05
        r.onLight = { ticks += 1 }
        r.reset(mode: .drag)
        r.setFiles([png], arrangement: arrangement)
        r.open()
        expect(r.events.openedAt == 5000 && r.events.slotsAt == 5000, "opening stamps the disc and the slots")
        r.pointer(at: center(L.labelBox(0, of: 6)))
        expect(r.hover == .leaf(0) && r.litLeaf == nil && r.choice(at: r.hover) != nil, "a drop goes at once; the light waits")
        now += 0.1
        try? await Task.sleep(nanoseconds: 120_000_000)
        expect(r.litLeaf == 0 && r.events.lit == 0 && r.events.litAt == now && ticks == 1, "after the rest, the slot lights with a tick")
        expect(r.events.ripples.last == BloomEvents.Ripple(slot: 0, at: now), "one ripple leaves its outline")
        r.pointer(at: center(L.labelBox(1, of: 6)))
        expect(r.litLeaf == 0, "moving on, the light stays until the next rest")
        try? await Task.sleep(nanoseconds: 120_000_000)
        expect(r.litLeaf == 1 && r.events.unlit == 0, "then it moves")
        r.pointer(at: .zero)
        expect(r.litLeaf == nil && r.events.lit == nil, "off the slots it goes at once")
        // Drop: input stops and the chosen slot carries it.
        r.pointer(at: center(L.labelBox(2, of: 6)))
        now += 1
        r.drop()
        expect(r.phase == .dropping && r.events.drop?.slot == 2 && r.events.drop?.at == now, "the drop is stamped on its slot")
        r.pointer(at: center(L.labelBox(3, of: 6)))
        expect(r.hover == .leaf(2), "no input while carrying")
        r.reset(mode: .drag)
        expect(r.phase == .open && r.events.drop == nil && !r.animating, "reset for the next clover")
        r.setFiles([png], arrangement: arrangement)
        r.open()
        r.cancel()
        expect(r.phase == .closing && r.events.cancelAt == now, "cancel is stamped")
        r.drop()
        expect(r.events.drop == nil, "no drop after a cancel")
    }

    // MARK: Motion

    /// The curves keep the house rules: fast attack, no overshoot, the pop, exits faster.
    private static func motion() {
        typealias M = Motion
        let at140 = M.settle(0.140 / M.Open.slot)
        expect(abs(at140 - 0.75) < 0.02, "75 % of the way at 140 ms of 300: \(at140)")
        var last = 0.0
        var overshoot = false
        for i in 0...100 {
            let v = M.settle(Double(i) / 100)
            if v < last - 1e-9 || v > 1 + 1e-9 { overshoot = true }
            last = v
        }
        expect(!overshoot && M.settle(1) == 1 && M.settle(0) == 0, "settle never overshoots")
        expect(M.exit(0) == 0 && M.exit(1) == 1 && M.exit(0.5) < 0.5, "exits accelerate away")
        expect(M.Cancel.duration < M.Open.slot && M.Chips.leave < M.Chips.settle + 0.02 && M.Tray.close < M.Tray.settle,
               "exits are faster than entrances")

        var e = BloomEvents()
        e.openedAt = 0
        e.slotsAt = 0
        let c = CGPoint(x: 0, y: -115)
        let born = M.slot(0, count: 6, center: c, e, now: 0).look
        expect(born.blur == M.Open.slotBlur && born.scale == M.Open.slotFrom && born.opacity == 0, "slots are born blurred, near the hub")
        let settledSlot = M.slot(0, count: 6, center: c, e, now: 1).look
        expect(settledSlot == .still, "and settle sharp, in place")
        let third = M.slot(2, count: 6, center: c, e, now: 0.3).look
        expect(third.scale < 1, "staggered clockwise: the third slot is still unfolding at 300 ms")
        expect(M.disc(e, now: 0).scale == M.Open.discFrom && M.disc(e, now: 0.3).scale == 1, "the disc grows from 85 %")
        expect(M.lightRing(e, now: 0.25) != nil && M.lightRing(e, now: 0.5) == nil, "the ring of light lasts 500 ms")

        e.lit = 1
        e.litAt = 2
        e.dimAt = 2
        let pops = stride(from: 2.0, through: 2.3, by: 0.005).map { M.litScale(e, now: $0) }
        expect(abs(pops.max()! - M.Hover.peak) < 0.002 && pops.last! == M.Hover.rest, "the lit slot pops to 108 % and rests at 104 %")
        let (litLook, litFill) = M.slot(1, count: 6, center: c, e, now: 2.002)
        expect(litFill == .lit && litLook.blur == 0, "the lit flip is instant, with no fade")
        let other = M.slot(0, count: 6, center: c, e, now: 3).look
        expect(abs(other.opacity - M.Hover.dimOpacity) < 0.001 && other.blur == M.Hover.dimBlur, "the others dim and soften")
        let g1 = M.glow(e, now: 2.6)!, g2 = M.glow(e, now: 3.8)!
        expect(abs(g1.scale - g2.scale) > 0.03, "the glow breathes")
        expect(M.ripple(BloomEvents.Ripple(slot: 1, at: 2), e, now: 2.2) != nil && M.ripple(BloomEvents.Ripple(slot: 1, at: 2), e, now: 2.46) == nil,
               "one ripple, 450 ms")

        e.chipsLeaf = 1
        e.chipsAt = 4
        e.chipRank = [1, 0, 2]
        let chip = M.chipIn(rank: 0, since: e.chipsAt, e, now: 4)
        expect(chip.blur == M.Chips.bornBlur && chip.scale == M.Chips.bornScale, "chips are born at 20 px and 110 %")
        expect(M.chipIn(rank: 2, since: e.chipsAt, e, now: 4.13).blur > 0 && M.chipIn(rank: 0, since: e.chipsAt, e, now: 4.131).blur == 0,
               "chips sharpen in 130 ms, 20 ms apart")

        e.drop = BloomEvents.Drop(at: 6, slot: 1, chip: nil, pill: nil)
        expect(M.slot(1, count: 6, center: c, e, now: 6).fill == .flash && M.slot(1, count: 6, center: c, e, now: 6.02).fill == .lit,
               "the chosen slot flashes white for one frame")
        let folded = M.slot(0, count: 6, center: c, e, now: 6 + M.Drop.fold + 0.001)
        expect(folded.look.opacity == 0, "the others fold away in 140 ms")
        expect(M.carryRing(e, now: 6.29) == nil && M.carryRing(e, now: 6.31) != nil, "the slot becomes the ring at the hub")
        let handoff = M.carryRing(e, now: 6 + M.Drop.handoff)!
        expect(handoff == .still, "at the handoff the ring sits still at the hub, ready for the chip")
        expect(abs(M.disc(e, now: 6 + M.Drop.handoff).scale - M.Drop.carrySide / (G.discRadius * 2)) < 0.001, "the disc shrinks to the ring's size")
        let glide = M.slot(1, count: 6, center: c, e, now: 6 + M.Drop.glideDelay + M.Drop.glide - 0.001).look
        expect(abs(glide.offset.height + c.y) < 0.5, "the chosen slot glides to the hub in 250 ms")

        var r = BloomEvents()
        r.reduce = true
        r.openedAt = 0
        r.slotsAt = 0
        let half = M.slot(0, count: 6, center: c, r, now: M.fade / 2).look
        expect(half.scale == 1 && half.blur == 0 && half.offset == .zero && half.opacity > 0.3, "reduce motion: slots fade in place")
        expect(M.lightRing(r, now: 0.1) == nil, "reduce motion: no ring of light")
        r.lit = 0
        r.litAt = 1
        expect(M.slot(0, count: 6, center: c, r, now: 1.01).look.scale == 1 && M.slot(0, count: 6, center: c, r, now: 1.01).fill == .lit,
               "reduce motion: the slot lights without a pop")
        expect(M.ripple(BloomEvents.Ripple(slot: 0, at: 1), r, now: 1.1) == nil, "reduce motion: no ripple")
        let still1 = M.glow(r, now: 2)!, still2 = M.glow(r, now: 3)!
        expect(still1.scale == still2.scale && still1.opacity == still2.opacity && still1.opacity == 1, "reduce motion: the glow is lit and still")
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
