import CoreGraphics
import Foundation

/// Fixed sizes of the bloom, in points.
enum BloomGeometry {
    static let hubSize: CGFloat = 72
    static let petalSize: CGFloat = 60
    /// Distance from the bloom's centre to each petal's centre.
    static let petalRadius: CGFloat = 100
    /// A lit petal grows to this size.
    static let litPetalSize: CGFloat = 66
    /// A petal reacts this far from its centre, a little beyond its edge.
    static let petalHitRadius: CGFloat = 36
    static let chipHeight: CGFloat = 24
    /// Space between two chips.
    static let chipGap: CGFloat = 6
    /// Space between a petal's edge and its chips.
    static let chipClearance: CGFloat = 10
    /// Text inset inside a chip, each side.
    static let chipPadding: CGFloat = 10
    /// The default chip's dot and the space after it.
    static let chipDotWidth: CGFloat = 9
    static let chipMinWidth: CGFloat = 44
    /// The hint label sits on the lower edge of the hub.
    static let hintCenterY: CGFloat = 36
    static let hintHeight: CGFloat = 20
    static let hintMaxWidth: CGFloat = 118
    /// Room kept around a lit petal for its glow.
    static let glowMargin: CGFloat = 14
    /// Room kept around a chip for its shadow.
    static let shadowMargin: CGFloat = 6
    /// The panel is a square of this side, centred on the bloom.
    static let panelSize: CGFloat = 500
}

/// Where a pointer is over the bloom.
enum BloomHit: Equatable {
    case none
    case hub
    case petal(slot: Int)
    case chip(slot: Int, index: Int)

    var slot: Int? {
        switch self {
        case .petal(let slot), .chip(let slot, _): slot
        default: nil
        }
    }
}

/// Which petal goes in which of the eight slots, page by page.
///
/// Slots run clockwise from 12 o'clock: 0 is 12, 2 is 3, 4 is 6, 6 is 9.
/// PDF targets keep 6 o'clock and ZIP keeps 9 on the first page, so they are always
/// in the same place. When there are more targets than slots, "More" takes 7:30 on
/// every page and cycles through them.
struct BloomPlan: Equatable {
    enum Kind: Equatable {
        case target(String)
        case more
    }

    struct Item: Equatable {
        let slot: Int
        let kind: Kind
    }

    static let slotCount = 8
    static let pdfSlot = 4
    static let moreSlot = 5
    static let zipSlot = 6
    static let pdfIDs = ["pdf", "pdf-merge", "pdf-compress"]

    let pages: [[Item]]

    /// `ids` in the order they should fill the free slots.
    init(targetIDs ids: [String]) {
        var seen = Set<String>()
        let ids = ids.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else {
            pages = [[]]
            return
        }
        var first: [Item] = []
        var used = Set<Int>()
        let pdf = BloomPlan.pdfIDs.first { ids.contains($0) }
        if let pdf {
            first.append(Item(slot: BloomPlan.pdfSlot, kind: .target(pdf)))
            used.insert(BloomPlan.pdfSlot)
        }
        let zipID = ids.contains("zip") ? "zip" : nil
        if zipID != nil {
            first.append(Item(slot: BloomPlan.zipSlot, kind: .target("zip")))
            used.insert(BloomPlan.zipSlot)
        }
        var rest = ids.filter { $0 != pdf && $0 != zipID }
        var free = (0..<BloomPlan.slotCount).filter { !used.contains($0) }

        if rest.count <= free.count {
            for (slot, id) in zip(free, rest) { first.append(Item(slot: slot, kind: .target(id))) }
            pages = [first.sorted { $0.slot < $1.slot }]
            return
        }

        first.append(Item(slot: BloomPlan.moreSlot, kind: .more))
        free.removeAll { $0 == BloomPlan.moreSlot }
        for slot in free where !rest.isEmpty {
            first.append(Item(slot: slot, kind: .target(rest.removeFirst())))
        }
        var result = [first.sorted { $0.slot < $1.slot }]
        let later = (0..<BloomPlan.slotCount).filter { $0 != BloomPlan.moreSlot }
        while !rest.isEmpty {
            var page = [Item(slot: BloomPlan.moreSlot, kind: .more)]
            for slot in later where !rest.isEmpty {
                page.append(Item(slot: slot, kind: .target(rest.removeFirst())))
            }
            result.append(page.sorted { $0.slot < $1.slot })
        }
        pages = result
    }

    var pageCount: Int { pages.count }

    func items(onPage page: Int) -> [Item] {
        pages.indices.contains(page) ? pages[page] : []
    }

    /// The slot holding a target, and its page.
    func place(of id: String) -> (page: Int, slot: Int)? {
        for (p, items) in pages.enumerated() {
            if let item = items.first(where: { $0.kind == .target(id) }) { return (p, item.slot) }
        }
        return nil
    }
}

/// Positions, chip rows, hit-testing and screen-edge clamping. Pure math.
///
/// Bloom coordinates have their origin at the hub's centre, with y pointing down.
enum BloomLayout {
    typealias G = BloomGeometry

    /// Clockwise angle from 12 o'clock, in radians.
    static func angle(ofSlot slot: Int) -> CGFloat {
        CGFloat(slot) * .pi * 2 / CGFloat(BloomPlan.slotCount)
    }

    /// Unit vector from the centre towards a slot.
    static func radial(_ slot: Int) -> CGVector {
        let a = angle(ofSlot: slot)
        return CGVector(dx: clean(sin(a)), dy: clean(-cos(a)))
    }

    /// Unit vector across a slot, pointed so chips read top to bottom, or left to right
    /// in a level row.
    static func across(_ slot: Int) -> CGVector {
        let a = angle(ofSlot: slot)
        var t = CGVector(dx: clean(cos(a)), dy: clean(sin(a)))
        if t.dy < 0 || (t.dy == 0 && t.dx < 0) { t = CGVector(dx: -t.dx, dy: -t.dy) }
        return t
    }

    static func petalCenter(_ slot: Int) -> CGPoint {
        let r = radial(slot)
        return CGPoint(x: (r.dx * G.petalRadius).rounded(), y: (r.dy * G.petalRadius).rounded())
    }

    /// Chip frames for a petal's options: one straight row just beyond the petal, across
    /// its direction. A level row at 12 and 6, a column at 3 and 9 with its inner edges
    /// against the petal, and a tight staircase on the diagonals. Chips never overlap
    /// each other or any petal.
    static func chipFrames(slot: Int, widths: [CGFloat]) -> [CGRect] {
        guard !widths.isEmpty else { return [] }
        let r = radial(slot)
        let t = across(slot)
        let h = G.chipHeight
        let diagonal = r.dx != 0 && r.dy != 0
        let inner = G.petalRadius + G.petalSize / 2 + G.chipClearance
        let halfDepths = widths.map { (abs(r.dx) * $0 + abs(r.dy) * h) / 2 }
        let sharedDepth = inner + (halfDepths.max() ?? 0)
        // Centre to centre: just enough to part two chips by the gap along x or along y,
        // whichever is shorter.
        func step(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
            let byX = t.dx != 0 ? ((a + b) / 2 + G.chipGap) / abs(t.dx) : .infinity
            let byY = t.dy != 0 ? (h + G.chipGap) / abs(t.dy) : .infinity
            return min(byX, byY)
        }
        var offsets: [CGFloat] = [0]
        for i in widths.indices.dropFirst() { offsets.append(offsets[i - 1] + step(widths[i - 1], widths[i])) }
        let middle = (offsets[0] + offsets[offsets.count - 1]) / 2
        return widths.enumerated().map { i, w in
            let depth = diagonal ? sharedDepth : inner + halfDepths[i]
            let offset = offsets[i] - middle
            let cx = (r.dx * depth + t.dx * offset).rounded()
            let cy = (r.dy * depth + t.dy * offset).rounded()
            return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        }
    }

    /// The width of a chip for a title of the given text width.
    static func chipWidth(textWidth: CGFloat, isDefault: Bool) -> CGFloat {
        let w = textWidth + G.chipPadding * 2 + (isDefault ? G.chipDotWidth : 0)
        return max(G.chipMinWidth, w.rounded(.up))
    }

    /// What is under `point`. `open` is the petal whose chips show, with their frames.
    ///
    /// Order: the open petal's chips, then any petal, then the band joining the open
    /// petal to its chips (so moving onto a chip never closes them), then the hub.
    static func hit(_ point: CGPoint, slots: [Int], open: Int?, chips: [CGRect]) -> BloomHit {
        if let open {
            for (i, frame) in chips.enumerated() where frame.insetBy(dx: -3, dy: -3).contains(point) {
                return .chip(slot: open, index: i)
            }
        }
        var nearest: (slot: Int, distance: CGFloat)?
        for slot in slots {
            let d = distance(point, petalCenter(slot))
            if d <= G.petalHitRadius, nearest == nil || d < nearest!.distance { nearest = (slot, d) }
        }
        if let nearest { return .petal(slot: nearest.slot) }
        if let open, slots.contains(open), inBand(point, slot: open, chips: chips) {
            return .petal(slot: open)
        }
        if distance(point, .zero) <= G.hubSize / 2 + 4 { return .hub }
        return .none
    }

    /// The area from a petal out to the far edge of its chips, across their full width.
    static func inBand(_ point: CGPoint, slot: Int, chips: [CGRect]) -> Bool {
        guard !chips.isEmpty else { return false }
        let r = radial(slot)
        let t = across(slot)
        func project(_ p: CGPoint) -> (r: CGFloat, t: CGFloat) { (p.x * r.dx + p.y * r.dy, p.x * t.dx + p.y * t.dy) }
        var outer = -CGFloat.infinity
        var low = CGFloat.infinity
        var high = -CGFloat.infinity
        for frame in chips {
            for corner in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                           CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
                let p = project(corner)
                outer = max(outer, p.r)
                low = min(low, p.t)
                high = max(high, p.t)
            }
        }
        let c = project(petalCenter(slot))
        low = min(low, c.t - G.petalHitRadius)
        high = max(high, c.t + G.petalHitRadius)
        let p = project(point)
        return p.r >= c.r - G.petalHitRadius && p.r <= outer + 4 && p.t >= low - 4 && p.t <= high + 4
    }

    /// Everything a page can show, chips included, around the centre (y down).
    static func contentBounds(slots: [Int], chipWidths: [[CGFloat]]) -> CGRect {
        var bounds = CGRect(x: -G.hubSize / 2, y: -G.hubSize / 2, width: G.hubSize, height: G.hubSize)
        bounds = bounds.union(CGRect(x: -G.hintMaxWidth / 2, y: G.hintCenterY - G.hintHeight / 2,
                                     width: G.hintMaxWidth, height: G.hintHeight))
        for slot in slots {
            let c = petalCenter(slot)
            let half = G.litPetalSize / 2 + G.glowMargin
            bounds = bounds.union(CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2))
            for widths in chipWidths {
                for frame in chipFrames(slot: slot, widths: widths) {
                    bounds = bounds.union(frame.insetBy(dx: -G.shadowMargin, dy: -G.shadowMargin))
                }
            }
        }
        return bounds
    }

    /// Moves a bloom centre inward so `bounds` (bloom coordinates, y down) fits inside
    /// `visible` (screen coordinates, y up). Rounded to whole points.
    static func clampedCenter(_ point: CGPoint, bounds: CGRect, visible: CGRect) -> CGPoint {
        // In screen space y points up, so the bloom's top is -bounds.minY above the centre.
        func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat, middle: CGFloat) -> CGFloat {
            low > high ? middle : min(max(v, low), high)
        }
        let x = clamp(point.x, visible.minX - bounds.minX, visible.maxX - bounds.maxX, middle: visible.midX)
        let y = clamp(point.y, visible.minY + bounds.maxY, visible.maxY + bounds.minY, middle: visible.midY)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// Converts a point in the panel's own view (origin bottom-left, y up) to bloom coordinates.
    static func bloomPoint(fromView p: CGPoint, panelSize: CGFloat = G.panelSize) -> CGPoint {
        CGPoint(x: p.x - panelSize / 2, y: panelSize / 2 - p.y)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Snaps tiny floating-point leftovers (cos 90°) to zero.
    private static func clean(_ v: CGFloat) -> CGFloat {
        abs(v) < 1e-9 ? 0 : v
    }
}

/// Where result chips go: a column that starts at `origin` and grows down, or up when
/// there's no room below. Pure math, screen coordinates (y up).
enum ChipStackLayout {
    static let gap: CGFloat = 8

    /// `origin` is the top-centre of the first chip.
    static func frames(count: Int, size: CGSize, origin: CGPoint, visible: CGRect, margin: CGFloat = 12) -> [CGRect] {
        guard count > 0 else { return [] }
        let x = min(max(origin.x - size.width / 2, visible.minX + margin), visible.maxX - margin - size.width)
        let top = min(max(origin.y, visible.minY + margin + size.height), visible.maxY - margin)
        let step = size.height + gap
        let roomBelow = top - size.height - (visible.minY + margin)
        let downward = roomBelow >= step * CGFloat(count - 1)
        return (0..<count).map { i in
            let y = downward ? top - size.height - step * CGFloat(i) : top - size.height + step * CGFloat(i)
            return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        }
    }

    /// The top-centre for chips when no bloom was just open: top right, under the menu bar.
    static func cornerOrigin(size: CGSize, visible: CGRect, margin: CGFloat = 12) -> CGPoint {
        CGPoint(x: visible.maxX - margin - size.width / 2, y: visible.maxY - margin)
    }
}
