import AppKit
import SwiftUI
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
        tints()
        triggerToggle()
        moreIcon()
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
                // Turned with its leaf, the label still sits wholly inside it.
                for withIcon in [false, true] {
                    let t = L.turnedLabel(i, of: n, icon: withIcon)
                    let hw = t.size.width / 2, hh = t.size.height / 2
                    let corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)].map { dx, dy in
                        CGPoint(x: t.center.x + dx * cos(t.angle) - dy * sin(t.angle),
                                y: t.center.y + dx * sin(t.angle) + dy * cos(t.angle))
                    }
                    expect(corners.allSatisfy { path.contains($0) } && L.sector(t.center, count: n) == i,
                           "slot \(i) of \(n)\(withIcon ? " with an icon" : ""): the turned label inside its leaf")
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
        let size = ResultChipView.size
        expect(size.width == 400 && size.height == 68, "the chip is 400 x 68: \(size)")
        // A finished chip keeps room for its name beside Undo, Copy and ✕.
        expect(ResultChipView.titleRoom >= 170, "room for the name beside the buttons: \(ResultChipView.titleRoom)")
        // Its window, shadow room included, fits the smallest Mac screen in use.
        expect(size.width + ChipPanel.margin * 2 <= 1280 - 24, "the chip's window fits a 1280 pt screen")
        let small = CGRect(x: 0, y: 0, width: 1280, height: 775)
        for x in [0.0, 200, 640, 1100, 1280] {
            let frame = ChipStackLayout.frames(count: 1, size: size, origin: CGPoint(x: x, y: 700), visible: small)[0]
            expect(small.insetBy(dx: 12, dy: 12).contains(frame), "a chip from x \(x) stays on a small screen: \(frame)")
        }
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

        // Click mode too: resting on More opens its tray after a short intent delay; a
        // click on More still toggles it.
        let moreLabel = center(L.labelBox(5, of: 6))
        expect(m.moreDelay == Motion.More.intent && abs(Motion.More.intent - 0.12) < 0.001, "the intent delay is 120 ms")
        m.moreDelay = 0.05
        m.pointer(at: moreLabel)
        expect(!m.trayOpen, "a sweep across More doesn't pop the tray")
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(m.trayOpen, "in click mode, resting on More opens the tray")
        expect(m.hint == "\(arrangement.more.count) more", "More's hint: \(m.hint)")
        m.toggleTray()
        expect(!m.trayOpen, "clicking More closes it")
        m.toggleTray()
        expect(m.trayOpen && m.litLeaf == 5, "and opens it again, More lit")
        m.toggleTray()
        m.pointer(at: .zero)

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
        try? await Task.sleep(nanoseconds: UInt64(Motion.More.leaveGrace * 0.5 * 1e9))
        expect(m.trayOpen, "crossing the gap to the tray, it stays open")
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
        // Off More and off the tray a moment, the tray closes.
        m.pointer(at: moreLabel)
        try? await Task.sleep(nanoseconds: 150_000_000)
        m.pointerLeft()
        try? await Task.sleep(nanoseconds: UInt64((Motion.More.leaveGrace + 0.1) * 1e9))
        expect(!m.trayOpen, "leaving More and the tray closes it")
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

        // The press: the button goes down on a slot; the choice is made on release over it.
        let pm = BloomModel()
        pm.chipDelay = 0
        pm.hoverDelay = 0.5
        pm.reset(mode: .click)
        pm.setFiles([png], arrangement: arrangement)
        pm.open()
        pm.pointer(at: label0)
        pm.pressDown(.leaf(0), at: label0)
        expect(pm.events.press?.target == .leaf(0) && pm.events.press?.point == label0 && pm.events.press?.releasedAt == nil,
               "the press starts where the button went down")
        expect(pm.litLeaf == 0, "a pressed slot lights at once, without the hover's rest")
        expect(pm.pressUp(over: .leaf(0)) && pm.events.press?.chosen == true && pm.events.press?.releasedAt != nil,
               "release over the same slot chooses")
        pm.pressDown(.leaf(0), at: label0)
        expect(!pm.pressUp(over: .leaf(1)) && pm.events.press?.chosen == false && pm.events.press?.releasedAt != nil,
               "release over another slot springs back and chooses nothing")
        expect(pm.phase == .open && pm.events.drop == nil, "and the clover stays open")
        pm.pressDown(.leaf(0), at: label0)
        expect(!pm.pressUp(over: nil), "release off the clover chooses nothing")
        pm.pressDown(.leaf(0), at: label0)
        pm.pressMoved(over: .leaf(1), at: .zero)
        expect(pm.events.press?.releasedAt != nil, "dragged off its slot, the press lets go")
        pm.pressMoved(over: .leaf(0), at: label0)
        expect(pm.events.press?.releasedAt == nil, "back on, it presses again")
        expect(pm.pressUp(over: .leaf(0)), "and a release there chooses")
        pm.pressDown(.leaf(0), at: label0)
        expect(pm.escape() && pm.events.press?.releasedAt != nil && pm.events.press?.chosen == false && pm.phase == .open,
               "Esc lets go of the press only")
        expect(!pm.pressUp(over: .leaf(0)), "a press that has let go doesn't choose on release")
        pm.quickPress(.leaf(2), at: center(L.labelBox(2, of: 6)))
        expect(pm.events.press?.quick == true && pm.events.press?.chosen == true
               && pm.events.press?.endsAt == (pm.events.press?.at ?? 0) + Motion.Press.quickHold,
               "a drop or Return is a quick press that lets go by itself")
        expect(!pm.pressUp(over: .leaf(2)), "a quick press ignores the button")
        expect(BloomModel.pressTarget(BloomHit.hub) == nil && BloomModel.pressTarget(BloomHit.chip(leaf: 0, index: 1)) == .chip(leaf: 0, index: 1)
               && BloomModel.pressTarget(TrayHit.background) == nil && BloomModel.pressTarget(TrayHit.pill(2)) == .pill(2),
               "slots, chips and pills press; the hub and the tray's background don't")
        pm.focusNumber(2)
        expect(pm.keyboardPress?.target == .leaf(1) && pm.keyboardPress?.point == L.leafCenter(1, of: 6), "Return presses from the slot's middle")

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

    /// Everything is plain until a leaf is chosen; the choice plays the wave, keeping the
    /// house rules: fast attack, no overshoot, a one-frame flip, exits faster.
    private static func motion() {
        typealias M = Motion
        let at = M.settle(0.140 / 0.300)
        expect(abs(at - 0.75) < 0.02, "75 % of the way at 140 ms of 300: \(at)")
        var last = 0.0
        var overshoot = false
        for i in 0...100 {
            let v = M.settle(Double(i) / 100)
            if v < last - 1e-9 || v > 1 + 1e-9 { overshoot = true }
            last = v
        }
        expect(!overshoot && M.settle(1) == 1 && M.settle(0) == 0, "settle never overshoots")
        expect(M.exit(0) == 0 && M.exit(1) == 1 && M.exit(0.5) < 0.5, "exits accelerate away")

        // Plain: opening, hover, chips, tray and cancel are instant.
        var e = BloomEvents()
        e.openedAt = 0
        e.slotsAt = 0
        let c = CGPoint(x: 0, y: -120)
        let first = M.slot(0, count: 6, center: c, e, now: 0).look
        expect(first.opacity == 1 && first.blur == 0 && abs(first.scale - M.Open.settleFrom) < 0.001,
               "slots are there at once, sharp, with their labels, settling from 97 %")
        expect(M.slot(5, count: 6, center: c, e, now: M.Open.settle + 0.01).look == .still, "and are full size after the settle")
        expect(M.disc(e, now: 0) == .still && M.capsule(e, now: 0) == .still && M.hub(e, now: M.Open.settle + 0.01) == .still,
               "the disc and capsule don't move; the hub settles with the slots")
        expect(M.lightRing(e, now: 0.2) == nil, "no ring of light on open")
        expect(abs(M.busyUntil(e, count: 6) - M.Open.settle) < 0.001, "opening runs the frame clock only for the settle")
        e.lit = 1
        e.litAt = 2
        e.dimAt = 2
        let (litLook, litFill) = M.slot(1, count: 6, center: c, e, now: 2)
        expect(litFill == .lit && litLook == .still, "the lit slot flips to green at once, with no pop")
        let otherStart = M.slot(0, count: 6, center: c, e, now: 2).look
        let other = M.slot(0, count: 6, center: c, e, now: 2 + M.Hover.dim + 0.01).look
        expect(abs(otherStart.opacity - 1) < 0.001 && abs(other.opacity - M.Hover.dimOpacity) < 0.001 && other.blur == 0 && other.scale == 1,
               "the others dim smoothly to 85 %, with no blur")
        let lifted = M.slot(1, count: 6, center: c, e, now: e.litAt + M.Hover.fadeIn + 0.01).look
        expect(abs(M.litAmount(1, e, now: e.litAt + M.Hover.fadeIn + 0.01) - 1) < 0.001 && abs(lifted.scale - M.Hover.lift) < 0.001,
               "the lit slot fades in and lifts 3 %")
        expect(M.glow(e, now: 2.5) == nil, "no glow or breathing")
        expect(M.ripple(BloomEvents.Ripple(slot: 1, at: 2), e, now: 2.1) == nil, "no hover ripple")
        e.chipsLeaf = 1
        e.chipsAt = 4
        expect(M.chipIn(rank: 0, since: 4, e, now: 4) == .still && M.chipOut(towards: .zero, e, now: 4) == nil
               && M.litPop(at: 4, e, now: 4.01) == 1, "chips come and go at once")
        e.trayAt = 5
        expect(M.tray(e, now: 5) == .still && M.pill(3, e, now: 5) == .still, "the tray and its pills appear at once")
        e.trayClosingAt = 6
        expect(M.tray(e, now: 6) == .hidden && M.trayCloseDuration(reduce: false) == 0, "and go at once")
        e.trayClosingAt = nil
        var cancelled = e
        cancelled.cancelAt = 7
        expect(M.slot(0, count: 6, center: c, cancelled, now: 7).look.opacity == 0 && M.disc(cancelled, now: 7).opacity == 0
               && M.cancelDuration(reduce: false) == 0, "cancel hides the clover at once")

        // Choosing a leaf: light through the glass.
        let d0: TimeInterval = 10
        let origin = L.leafCenter(1, of: 6)
        let centers = (0..<6).map { L.leafCenter($0, of: 6) }
        e.drop = BloomEvents.Drop(at: d0, slot: 1, chip: nil, pill: nil)
        func slotLook(_ i: Int, _ t: TimeInterval) -> (look: Look, fill: SlotFill) {
            M.slot(i, count: 6, center: centers[i], e, now: d0 + t, origin: origin)
        }
        let chosenFills = stride(from: 0.0, through: M.Drop.ringAt - 0.01, by: 0.004).map { slotLook(1, $0).fill }
        expect(chosenFills.allSatisfy { $0 == .lit }, "no white flash: the chosen leaf keeps its bright hover look")
        expect(abs(slotLook(1, 0).look.scale - M.Hover.lift) < 0.001 && abs(slotLook(1, M.Drop.choose).look.scale - M.Drop.chooseLift) < 0.001,
               "it lifts from 103 % to 107 % in 90 ms")
        let lifts = stride(from: 0.0, through: M.Drop.glideStart, by: 0.004).map { slotLook(1, $0).look.scale }
        expect(lifts.max()! <= M.Drop.chooseLift + 0.0001, "with no overshoot")
        expect(M.chosenGlow(e, now: d0 + M.Drop.choose) > 0.99 && M.chosenGlow(e, now: d0 + M.Drop.glideStart + M.Drop.glowOut + 0.001) == 0,
               "a soft inner glow comes up with it and goes as it glides")
        // The distortion wave: from the chosen leaf, the original's ring, then the carry.
        if DistortionWaves.available {
            let W = DistortionWaves.self
            expect(M.Drop.handoff < 1.5 && W.style.aberration > 0 && W.style.palette == .colorful,
                   "the distortion wave is the original's ring, colourful and colour-split, and the pill comes within 1.5 s")
            let early = W.front(e, now: d0 + 0.1, slot: 1, count: 6)!.front
            expect(!early.launched && early.gravity > 0, "it pulls the clover in toward the leaf first")
            let radii = stride(from: 0.2, through: 1.4, by: 0.02).map { W.front(e, now: d0 + $0, slot: 1, count: 6)!.front.radius }
            expect(zip(radii, radii.dropFirst()).allSatisfy { $0 <= $1 }, "then its front only moves out")
            let atCarry = W.front(e, now: d0 + W.carryAfter, slot: 1, count: 6)!
            let farthest = hypot(atCarry.source.midX - G.discRadius, atCarry.source.midY - G.discRadius) + G.discRadius
            expect(atCarry.front.radius >= farthest, "its front has crossed the whole disc before the carry")
            expect(M.Drop.gatherAt == 0.34 + W.carryAfter && M.Drop.handoff == 0.55 + W.carryAfter, "the carry waits for it")
            var rd = e
            rd.reduce = true
            expect(W.front(rd, now: d0 + 0.5, slot: 1, count: 6) == nil, "reduce motion: no distortion wave")
        }
        // The leaves in order of distance from the chosen one.
        let order = (0..<6).filter { $0 != 1 }.sorted { L.distance(centers[$0], origin) < L.distance(centers[$1], origin) }
        if M.Drop.waveEnabled {
            // One thin wave from the chosen leaf, over the disc only.
            let reach = M.waveReach(origin)
            expect(M.wave(e, now: d0 + 0.01, origin: origin) == nil && (M.wave(e, now: d0 + M.Drop.waveStart + 1e-6, origin: origin)?.radius ?? 1) < 0.1,
                   "the wave sets off at 20 ms from the leaf's middle")
            let mid = M.wave(e, now: d0 + M.Drop.waveStart + M.Drop.wave * 0.467, origin: origin)!
            expect(abs(mid.radius / reach - 0.75) < 0.03, "fast attack: 75 % of its way at 47 % of its time")
            var radii: [CGFloat] = []
            for i in 0..<100 { radii.append(M.wave(e, now: d0 + M.Drop.waveStart + 1e-6 + M.Drop.wave * Double(i) / 100, origin: origin)!.radius) }
            expect(zip(radii, radii.dropFirst()).allSatisfy { $0 <= $1 } && radii.max()! <= reach, "the wave never overshoots or comes back")
            expect(abs(reach - (hypot(origin.x, origin.y) + G.discRadius)) < 0.01, "it reaches the far side of the disc")
            expect(M.wave(e, now: d0 + M.Drop.waveStart + M.Drop.wave + 0.001, origin: origin) == nil, "and is gone at 380 ms")
            expect(M.Drop.waveCore <= 2.5 && M.Drop.waveGlow <= 14 && M.Drop.waveTrailLight <= 0.08, "a thin front, a faint light behind it")
            expect(M.Drop.waveRimFade > 0, "it fades out before the rim and is clipped to the disc")
            // Each leaf is nudged as the front reaches its middle, in order of distance.
            let arrivals = order.map { M.waveArrives(L.distance(centers[$0], origin), origin: origin) }
            expect(zip(arrivals, arrivals.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 }, "the nearer leaves are nudged first")
            for i in order {
                let distance = L.distance(centers[i], origin)
                let arrive = M.waveArrives(distance, origin: origin)
                let atFront = M.wave(e, now: d0 + arrive, origin: origin)?.radius ?? -1
                expect(abs(atFront - distance) < 0.5, "leaf \(i) is nudged when the front reaches its middle")
                // Its peak, before the fold can begin for the farthest leaves.
                let peak = stride(from: arrive, through: arrive + M.Drop.nudge * 0.6, by: 0.002).map { slotLook(i, $0).look }
                let away = peak.map { hypot($0.offset.width, $0.offset.height) }
                expect(away.max()! > M.Drop.nudgeShift - 0.1 && away.max()! <= M.Drop.nudgeShift + 0.001 && peak.map(\.scale).max()! <= M.Drop.nudgeScale + 0.0001,
                       "leaf \(i): out about 3.5 pt and to 103 %, no further")
                let out = CGVector(dx: centers[i].x - origin.x, dy: centers[i].y - origin.y)
                let best = peak.max { hypot($0.offset.width, $0.offset.height) < hypot($1.offset.width, $1.offset.height) }!
                expect(best.offset.width * out.dx + best.offset.height * out.dy > 0, "leaf \(i): pushed away from the chosen leaf")
                let back = slotLook(i, arrive + M.Drop.nudge + 0.001).look
                expect(back.offset == .zero || back.opacity < 1, "leaf \(i): back in place after 180 ms")
            }
            let hubPeak = stride(from: 0.0, through: M.Drop.gatherAt, by: 0.002).map { M.hub(e, now: d0 + $0, origin: origin) }
            let hubAway = hubPeak.map { hypot($0.offset.width, $0.offset.height) }.max()!
            expect(hubAway > 1 && hubAway <= M.Drop.hubNudgeShift + 0.001, "the hub is nudged too, less")
        } else {
            expect(M.wave(e, now: d0 + M.Drop.waveStart + M.Drop.wave * 0.5, origin: origin) == nil
                   && M.nudged(centers[order[0]], origin: origin, t: 0.1, shift: M.Drop.nudgeShift, scale: M.Drop.nudgeScale) == .still,
                   "no ring of light and no nudges while the wave is off")
        }
        // Gather: the others fold one by one, the farthest last, all gone by the handoff.
        let gone = order.map { i in stride(from: M.Drop.gatherAt, through: M.Drop.handoff, by: 0.002).first { slotLook(i, $0).look.opacity == 0 } ?? 1 }
        expect(zip(gone, gone.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 } && gone.last! <= M.Drop.handoff,
               "the others fold to the hub one by one, the farthest last, before the handoff")
        let folding = slotLook(order.last!, gone.last! - 0.12).look
        expect(folding.blur > 0 && folding.scale < 1, "they shrink and blur as they fold")
        // Nothing hangs outside the glass: a leaf still showing stays inside the contracting disc.
        var outside = 0
        for t in stride(from: M.Drop.gatherAt, through: M.Drop.handoff, by: 0.005) {
            let disc = M.disc(e, now: d0 + t).scale * G.discRadius
            for i in order {
                let look = slotLook(i, t).look
                let reachOut = hypot(centers[i].x + look.offset.width, centers[i].y + look.offset.height) + 50 * look.scale
                if look.opacity > 0.15 && reachOut > disc + 4 { outside += 1 }
            }
        }
        expect(outside == 0, "the leaves are gone before the glass draws in under them: \(outside) frames out")
        // The chosen leaf glides in, the hub becomes the ring on its glass, no dark disc.
        let gathered = slotLook(1, M.Drop.glideStart + M.Drop.glide - 0.001).look
        expect(abs(gathered.offset.width + origin.x) < 0.6 && abs(gathered.offset.height + origin.y) < 0.6, "the chosen leaf glides to the hub")
        let landing = stride(from: M.Drop.glideStart, to: M.Drop.ringAt - 0.0005, by: 0.002).map { slotLook(1, $0).look.opacity }
        expect(landing.allSatisfy { $0 == 1 } && slotLook(1, M.Drop.ringAt + 1e-6).look.opacity == 0,
               "solid all the way in, then it flips into the ring in one frame: no ghost")
        expect(M.carryRing(e, now: d0 + M.Drop.ringAt - 0.001) == nil && M.carryRing(e, now: d0 + M.Drop.ringAt + 0.001) != nil,
               "the ring appears on the hub")
        let atHandoff = M.carryRing(e, now: d0 + M.Drop.handoff)
        expect(atHandoff?.scale == 1 && atHandoff?.offset == .zero && abs((atHandoff?.blur ?? 0) - M.Drop.handoffBlur) < 0.01,
               "and sits still at the handoff, a little soft, as the chip starts")
        let hubEnd = M.hub(e, now: d0 + M.Drop.handoff, origin: origin)
        expect(abs(hubEnd.scale * G.hubSize - M.Drop.ringSide) < 0.5 && hubEnd.opacity == 1, "the hub has become the ring's frosted glass, 56 pt")
        expect(M.hubContent(e, now: d0 + M.Drop.hubContentAt + M.Drop.hubContent + 0.001).opacity == 0, "its picture and capsule have gone")
        let discEnd = M.disc(e, now: d0 + M.Drop.handoff)
        expect(abs(discEnd.scale * G.discRadius * 2 - M.Drop.discTo) < 0.5 && discEnd.opacity == 1, "the disc's glass contracts to just under the ring")
        expect(M.Drop.handoff == 0.55 + M.Drop.afterWave && ChipMotion.ringAppearDelay == M.Drop.handoff, "the result chip picks up the ring at 550 ms after the wave, no gap")
        expect(M.Drop.ringSide == ChipMotion.dropRingDiameter, "the same 56 pt ring")
        expect(M.busyUntil(e, count: 6) >= d0 + M.Drop.handoff, "the frame clock runs to the handoff")

        // The press: a glass button.
        let pressed = BloomEvents.Press(target: .leaf(0), point: CGPoint(x: centers[0].x + 14, y: centers[0].y - 10), at: 20)
        let held = stride(from: 0.0, through: 0.8, by: 0.004).map { M.pressScale(pressed, peak: M.Press.leafPeak, reduce: false, now: 20 + $0) }
        expect(held.first == 1 && held.max()! > M.Press.leafPeak && held.max()! < M.Press.leafPeak + 0.01
               && abs(held.last! - M.Press.leafPeak) < 0.002, "held, the slot swells with a soft spring, a little give")
        expect(abs(Double(M.Hover.lift * M.Press.leafPeak) - 1.09) < 0.015, "to about 1.09 from its hover size")
        var let_go = pressed
        let_go.releasedAt = 20.5
        let after = stride(from: 0.0, through: 1.0, by: 0.004).map { M.pressScale(let_go, peak: M.Press.leafPeak, reduce: false, now: 20.5 + $0) }
        expect(after.min()! > 0.97 && after.min()! < 0.995, "let go, it springs back past its size, about 0.98: \(after.min()!)")
        let settled = stride(from: M.Press.releaseSettle, through: 1.0, by: 0.004).map {
            M.pressScale(let_go, peak: M.Press.leafPeak, reduce: false, now: 20.5 + $0)
        }
        expect(settled.allSatisfy { abs($0 - 1) < 0.003 }, "and settles at 1 within \(Int(M.Press.releaseSettle * 1000)) ms")
        expect(M.pressScale(pressed, peak: M.Press.leafPeak, reduce: false, now: 19.9) == 1, "nothing before the press")
        // The light starts at the press point and grows to fill the slot.
        let early = M.pressLight(pressed, reduce: false, now: 20.03)!, grown = M.pressLight(pressed, reduce: false, now: 20.3)!
        expect(early.grow < 0.5 && early.intensity > 0.3 && grown.grow > 0.99, "the light comes up at once and fills the slot in 250 ms")
        let size = L.leafBounds(0, of: 6).size
        let local = CGPoint(x: pressed.point.x - L.leafBounds(0, of: 6).minX, y: pressed.point.y - L.leafBounds(0, of: 6).minY)
        let small = PressLight.filling(size, from: local, early), big = PressLight.filling(size, from: local, grown)
        expect(small.point == local && small.radius < big.radius && big.radius >= hypot(size.width, size.height) / 2,
               "the light is centred on the press point and spreads from it")
        expect(M.pressLight(let_go, reduce: false, now: 20.5 + M.Press.lightFade + 0.001) == nil
               && M.pressLight(let_go, reduce: false, now: 20.6)!.intensity < M.pressLight(let_go, reduce: false, now: 20.5)!.intensity,
               "let go, the light fades in 300 ms")
        // A drop or Return: a quick press and release.
        let quick = BloomEvents.Press(target: .leaf(0), point: centers[0], at: 30, quick: true, chosen: true)
        expect(M.pressScale(quick, peak: M.Press.leafPeak, reduce: false, now: 30 + M.Press.quickHold) > 1.03
               && abs(M.pressScale(quick, peak: M.Press.leafPeak, reduce: false, now: 30 + M.Press.quickHold + M.Press.releaseSettle) - 1) < 0.003,
               "a quick press swells for 120 ms and springs back")
        // Choosing after a press: the press's settle carries on; no second lift, no extra glow.
        var chosenAfterPress = e
        chosenAfterPress.press = BloomEvents.Press(target: .leaf(1), point: origin, at: d0 - 0.4, releasedAt: d0, chosen: true)
        let handed = M.slot(1, count: 6, center: centers[1], chosenAfterPress, now: d0 + 0.05, origin: origin).look.scale
        let expected = M.Hover.lift * M.pressScale(chosenAfterPress.press!, peak: M.Press.leafPeak, reduce: false, now: d0 + 0.05)
        expect(abs(handed - expected) < 0.0001 && M.chosenGlow(chosenAfterPress, now: d0 + 0.05) == 0,
               "the wave's choose step hands over from the press without doubling up")
        // Reduce motion: no scale or spring; the light appears and fades.
        expect(M.pressScale(pressed, peak: M.Press.leafPeak, reduce: true, now: 20.2) == 1, "reduce motion: no swell")
        let soft = M.pressLight(pressed, reduce: true, now: 20 + M.fade / 2)!
        expect(soft.grow == 1 && abs(soft.intensity - 0.5) < 0.01 && M.pressLight(let_go, reduce: true, now: 20.5 + M.fade + 0.001) == nil,
               "reduce motion: the light fades in and out over 150 ms")
        expect(M.busyUntil(BloomEvents(press: let_go), count: 6) >= 20.5 + M.Press.releaseSettle, "the frame clock runs through the settle")

        // Reduce motion: no wave and no fold, a fade, then the ring until the chip.
        var r = e
        r.reduce = true
        expect(M.wave(r, now: d0 + 0.1, origin: origin) == nil && M.chosenGlow(r, now: d0 + 0.05) == 0, "reduce motion: no wave, no glow")
        let faded = M.slot(0, count: 6, center: c, r, now: d0 + M.fade / 2).look
        expect(faded.scale == 1 && faded.blur == 0 && faded.offset == .zero && faded.opacity < 0.85, "reduce motion: the others fade in place")
        expect(M.slot(1, count: 6, center: c, r, now: d0 + M.fade).look.opacity == 0, "reduce motion: gone in 150 ms")
        expect(M.carryRing(r, now: d0 + M.Drop.handoff)?.opacity == 1, "reduce motion: the ring waits for the chip")
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

    // MARK: Glass tint

    private static func tints() {
        let all: [GlassTint] = [.none] + GlassTint.Preset.allCases.map(GlassTint.preset) + [.custom(0x4AA3A2), .custom(0x000000), .custom(0xFFFFFF)]
        for tint in all {
            expect(GlassTint(stored: tint.stored) == tint, "\(tint.title) is stored and read back as \(tint.stored)")
        }
        expect(GlassTint.none.stored == "none" && GlassTint.preset(.clover).stored == "clover" && GlassTint.custom(0x4AA3A2).stored == "#4AA3A2",
               "stored as none, a preset's name, or #RRGGBB")
        expect(GlassTint(stored: nil) == nil && GlassTint(stored: "bogus") == nil && GlassTint(stored: "#12345") == nil && GlassTint(stored: "#GG0000") == nil,
               "anything else isn't a tint")
        expect(GlassTint.migrated(fromLeafStyle: "clover") == .preset(.clover), "the old clover green stays clover green")
        expect(GlassTint.migrated(fromLeafStyle: "clear") == .none && GlassTint.migrated(fromLeafStyle: nil) == .none,
               "the old clear glass, and no setting at all, is no tint")
        expect(GlassTint.Preset.allCases.map(\.rawValue) == ["clover", "blue", "purple", "pink", "orange", "graphite"], "the six presets, in order")
        for scheme in [ColorScheme.light, .dark] {
            expect(BloomStyle.glassTint(.none, scheme) == nil, "no tint is clear glass")
            for tint in all.dropFirst() {
                expect(BloomStyle.glassTint(tint, scheme) != nil, "\(tint.title) tints the glass")
            }
        }
        expect(GlassTint.preset(.clover).rgb == 0x3FC779 && GlassTint.custom(0xFF4AA3A2).rgb == 0x4AA3A2, "colours are 0xRRGGBB; anything above is ignored")
        expect(TintPicker.rgb(of: BloomStyle.rgb(0x4AA3A2)) == 0x4AA3A2, "a picked colour round-trips to its hex")
    }

    // MARK: The trigger key closes the clover

    private static func triggerToggle() {
        // Drag mode: the press that opened it doesn't count; a new press does.
        var drag = TriggerToggle(keyDown: true)
        expect(!drag.poll(keyDown: true) && !drag.poll(keyDown: true), "the opening press, still held, doesn't close it")
        expect(!drag.poll(keyDown: false), "the key comes up")
        expect(drag.poll(keyDown: true), "a new press closes it")
        expect(!drag.poll(keyDown: true), "once")
        var already = TriggerToggle(keyDown: false)
        expect(already.poll(keyDown: true), "opened with the key up (the shortcut): its next press closes it")
        // Click mode: a clean tap closes it on the way up; a press with another key doesn't.
        var click = TriggerToggle(keyDown: true)
        expect(!click.changed(keyDown: false), "the opening press coming up doesn't close it")
        expect(!click.changed(keyDown: true), "a new press goes down")
        expect(click.changed(keyDown: false), "and closes it on the way up")
        var shiftTab = TriggerToggle(keyDown: false)
        _ = shiftTab.changed(keyDown: true)
        shiftTab.otherKey()
        expect(!shiftTab.changed(keyDown: false), "Shift-Tab isn't a tap")
        expect(!shiftTab.changed(keyDown: true) && shiftTab.changed(keyDown: false), "but the next clean tap is")
        // From drag mode into click mode (a hold let go): the key state carries over.
        var hold = TriggerToggle(keyDown: true)
        _ = hold.poll(keyDown: true)
        expect(!hold.changed(keyDown: false), "let go of a hold, the opening press coming up doesn't close it")
        expect(!hold.changed(keyDown: true) && hold.changed(keyDown: false), "a tap after it does")
    }

    // MARK: More: a + that turns into ×

    private static func moreIcon() {
        var e = BloomEvents()
        e.openedAt = 0
        expect(Motion.moreTurn(e, now: 1) == 0, "at rest, More is a +")
        e.trayAt = 2
        let turning = stride(from: 0.0, through: 0.4, by: 0.005).map { Motion.moreTurn(e, now: 2 + $0) }
        expect(turning.first == 0 && zip(turning, turning.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 } && turning.max()! <= 1,
               "the tray opening turns it towards ×, never past")
        expect(abs(Motion.moreTurn(e, now: 2 + Motion.More.turn) - 1) < 1e-9 && Motion.More.turn == 0.18 && Motion.More.angle == 45,
               "a 45° turn, × in 180 ms")
        expect(Motion.moreTurn(e, now: 2 + 0.09) > 0.5, "eased: most of the turn early")
        e.trayClosingAt = 3
        expect(abs(Motion.moreTurn(e, now: 3) - 1) < 1e-9 && Motion.moreTurn(e, now: 3 + Motion.More.back + 0.001) == 0 && Motion.More.back < Motion.More.turn,
               "closing turns it back to + in 150 ms")
        e.trayClosingAt = 2.05
        let from = Motion.moreTurn(e, now: 2.05)
        expect(from > 0 && from < 1 && Motion.moreTurn(e, now: 2.06) < from, "closed mid-turn, it turns back from where it was")
        var r = BloomEvents()
        r.reduce = true
        r.trayAt = 5
        expect(abs(Motion.moreTurn(r, now: 5 + Motion.fade / 2) - 0.5) < 0.01, "reduce motion: + cross-fades into ×")
        expect(Motion.busyUntil(e, count: 6) >= 2.05 + Motion.More.back, "the frame clock runs through the turn")
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
