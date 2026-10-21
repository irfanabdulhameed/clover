import CoreGraphics
import Foundation

/// Fixed sizes of the clover, in points.
enum BloomGeometry {
    static let hubSize: CGFloat = 72
    /// Each leaf's point sits this far from the centre, just under the hub.
    static let leafTip: CGFloat = 32
    /// The leaf's scale: the heart is 0.92 of this wide and 0.92 long. With the tip
    /// distance above, six leaves nearly touch.
    static let leafSize: CGFloat = 104
    /// Most leaves the clover shows. With more targets, the last one is "More".
    static let maxLeaves = 6
    /// The label block in a leaf: an icon over a title.
    static let labelHeight: CGFloat = 34
    /// The label fits in this width in every leaf, so a long title shrinks the same way everywhere.
    static let labelMaxWidth: CGFloat = 76
    static let chipHeight: CGFloat = 24
    /// Space between two chips.
    static let chipGap: CGFloat = 6
    /// Space between a leaf's outer edge and its chips.
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
    /// Room kept around a lit leaf for its glow.
    static let glowMargin: CGFloat = 14
    /// Room kept around a chip for its shadow.
    static let shadowMargin: CGFloat = 6
    /// A point this close to a leaf's edge, outside it, still counts as on the leaf.
    static let leafHitSlop: CGFloat = 3
    /// The panel is a square of this side, centred on the clover.
    static let panelSize: CGFloat = 500
}

/// Where a pointer is over the clover.
enum BloomHit: Equatable {
    case none
    case hub
    case leaf(Int)
    case chip(leaf: Int, index: Int)

    var leaf: Int? {
        switch self {
        case .leaf(let leaf), .chip(let leaf, _): leaf
        default: nil
        }
    }
}

/// The heart-shaped leaf of Clover's icon: the same curves as `CloverGlyph` draws for
/// the menu bar and the app icon. The point is at the origin and the leaf points along
/// +y; it is 0.92 wide and 0.92 long.
enum HeartLeaf {
    typealias Curve = (CGPoint, CGPoint, CGPoint, CGPoint)

    static let curves: [Curve] = [
        (CGPoint(x: 0, y: 0), CGPoint(x: -0.1, y: 0.12), CGPoint(x: -0.46, y: 0.34), CGPoint(x: -0.46, y: 0.6)),
        (CGPoint(x: -0.46, y: 0.6), CGPoint(x: -0.46, y: 1.0), CGPoint(x: -0.06, y: 1.04), CGPoint(x: 0, y: 0.66)),
        (CGPoint(x: 0, y: 0.66), CGPoint(x: 0.06, y: 1.04), CGPoint(x: 0.46, y: 1.0), CGPoint(x: 0.46, y: 0.6)),
        (CGPoint(x: 0.46, y: 0.6), CGPoint(x: 0.46, y: 0.34), CGPoint(x: 0.1, y: 0.12), CGPoint(x: 0, y: 0)),
    ]

    /// The leaf as a path in its unit box.
    static let path: CGPath = {
        let p = CGMutablePath()
        p.move(to: curves[0].0)
        for c in curves { p.addCurve(to: c.3, control1: c.1, control2: c.2) }
        p.closeSubpath()
        return p
    }()

    /// The outline as points, `steps` per curve.
    static func polygon(steps: Int) -> [CGPoint] {
        curves.flatMap { c in
            (0..<steps).map { i -> CGPoint in
                let t = CGFloat(i) / CGFloat(steps)
                let u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
                return CGPoint(x: a * c.0.x + b * c.1.x + d * c.2.x + e * c.3.x,
                               y: a * c.0.y + b * c.1.y + d * c.2.y + e * c.3.y)
            }
        }
    }

    static let outline = polygon(steps: 32)
}

/// Positions, leaf shapes, chip rows, hit-testing and screen-edge clamping. Pure math.
///
/// Clover coordinates have their origin at the hub's centre, with y pointing down.
/// Leaves are numbered clockwise from 12 o'clock; `count` is how many there are.
@MainActor
enum BloomLayout {
    typealias G = BloomGeometry

    /// Clockwise angle from 12 o'clock, in radians: evenly spaced, the first at 12.
    static func angle(_ index: Int, of count: Int) -> CGFloat {
        CGFloat(index) * .pi * 2 / CGFloat(max(count, 1))
    }

    /// Unit vector from the centre along a leaf.
    static func radial(_ index: Int, of count: Int) -> CGVector {
        let a = angle(index, of: count)
        return CGVector(dx: clean(sin(a)), dy: clean(-cos(a)))
    }

    /// Unit vector across a leaf, pointed so chips read top to bottom, or left to right
    /// in a level row.
    static func across(_ index: Int, of count: Int) -> CGVector {
        let a = angle(index, of: count)
        var t = CGVector(dx: clean(cos(a)), dy: clean(sin(a)))
        if t.dy < 0 || (t.dy == 0 && t.dx < 0) { t = CGVector(dx: -t.dx, dy: -t.dy) }
        return t
    }

    /// Maps the unit leaf onto a leaf of the clover: point at `leafTip`, along its angle.
    static func leafTransform(_ index: Int, of count: Int) -> CGAffineTransform {
        let r = radial(index, of: count)
        let s = G.leafSize
        // Unit x runs across the leaf, unit y along it.
        return CGAffineTransform(a: -r.dy * s, b: r.dx * s, c: r.dx * s, d: r.dy * s,
                                 tx: r.dx * G.leafTip, ty: r.dy * G.leafTip)
    }

    private struct Key: Hashable {
        let index: Int
        let count: Int
    }

    private static var paths: [Key: CGPath] = [:]
    private static var outlines: [Key: [CGPoint]] = [:]
    private static var labels: [Key: CGRect] = [:]

    /// The leaf's outline in clover coordinates.
    static func leafPath(_ index: Int, of count: Int) -> CGPath {
        let key = Key(index: index, count: count)
        if let cached = paths[key] { return cached }
        var t = leafTransform(index, of: count)
        let path = HeartLeaf.path.copy(using: &t) ?? HeartLeaf.path
        paths[key] = path
        return path
    }

    /// The outline as points, for distances and label fitting.
    static func leafOutline(_ index: Int, of count: Int) -> [CGPoint] {
        let key = Key(index: index, count: count)
        if let cached = outlines[key] { return cached }
        let t = leafTransform(index, of: count)
        let points = HeartLeaf.outline.map { $0.applying(t) }
        outlines[key] = points
        return points
    }

    static func leafBounds(_ index: Int, of count: Int) -> CGRect {
        leafPath(index, of: count).boundingBoxOfPath
    }

    /// The farthest any leaf reaches from the centre.
    static let leafReach: CGFloat = {
        HeartLeaf.polygon(steps: 64).map { hypot($0.x * G.leafSize, G.leafTip + $0.y * G.leafSize) }.max() ?? 0
    }()

    /// Where a leaf's label goes: an upright box in the broad part of the leaf, as wide
    /// as its title row fits (at most `labelMaxWidth`), as near the middle of the broad
    /// part as that allows. The icon sits in the box's upper half and needs less room;
    /// the title fills the lower half. Both are centred on the box.
    static func labelBox(_ index: Int, of count: Int) -> CGRect {
        let key = Key(index: index, count: count)
        if let cached = labels[key] { return cached }
        let outline = leafOutline(index, of: count)
        let r = radial(index, of: count)
        let half = G.labelHeight / 2
        let iconRows = stride(from: -half, through: -1, by: 4).map { $0 }
        let titleRows = stride(from: 2, through: half, by: 3).map { $0 }
        let ideal = G.leafTip + 0.46 * G.leafSize
        let middle = CGPoint(x: r.dx * ideal, y: r.dy * ideal)
        // Room for the longest title at full size, with a little air.
        let wanted = G.labelMaxWidth + 6
        /// The widest box centred on `x` that every row fits, or nil.
        func halfWidth(x: CGFloat, y: CGFloat, rows: [CGFloat]) -> CGFloat? {
            var room = CGFloat.infinity
            for dy in rows {
                guard let span = chord(outline, y: y + dy, around: x) else { return nil }
                room = min(room, x - span.lowerBound, span.upperBound - x)
            }
            return room
        }
        var best: (center: CGPoint, width: CGFloat, score: CGFloat)?
        func consider(_ c: CGPoint) {
            // Far from the middle of the broad part, a label reads as off to one side.
            guard distance(c, middle) < 0.3 * G.leafSize,
                  let icon = halfWidth(x: c.x, y: c.y, rows: iconRows), icon >= 12,
                  let title = halfWidth(x: c.x, y: c.y, rows: titleRows) else { return }
            let width = title * 2
            let score = min(width, wanted) * 4 - distance(c, middle)
            if best == nil || score > best!.score { best = (c, width, score) }
        }
        // Coarse, then fine around the best.
        let reach = 0.3 * G.leafSize
        for dy in stride(from: -reach, through: reach, by: 4) {
            for dx in stride(from: -reach, through: reach, by: 4) { consider(CGPoint(x: middle.x + dx, y: middle.y + dy)) }
        }
        if let coarse = best?.center {
            for dy in stride(from: -4.0, through: 4, by: 1) {
                for dx in stride(from: -4.0, through: 4, by: 1) { consider(CGPoint(x: coarse.x + dx, y: coarse.y + dy)) }
            }
        }
        let center = best?.center ?? middle
        let width = min((best?.width ?? 0) - 6, G.labelMaxWidth).rounded(.down)
        let box = CGRect(x: (center.x - width / 2).rounded(), y: (center.y - half).rounded(), width: width, height: G.labelHeight)
        labels[key] = box
        return box
    }

    /// The stretch of row `y` inside a polygon that contains `x`, or nil when `x` is outside.
    static func chord(_ polygon: [CGPoint], y: CGFloat, around x: CGFloat) -> ClosedRange<CGFloat>? {
        var crossings: [CGFloat] = []
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if (a.y <= y) != (b.y <= y) {
                crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
            }
        }
        crossings.sort()
        var i = 0
        while i + 1 < crossings.count {
            if crossings[i] <= x && x <= crossings[i + 1] { return crossings[i]...crossings[i + 1] }
            i += 2
        }
        return nil
    }

    /// Chip frames for a leaf's options: one straight row just beyond the leaf's outer
    /// edge, across its direction. A level row at 12 and 6, a column at 3 and 9 with its
    /// inner edges at the same depth, and a tight staircase at other angles. Chips never
    /// overlap each other or any leaf.
    static func chipFrames(_ index: Int, of count: Int, widths: [CGFloat]) -> [CGRect] {
        guard !widths.isEmpty else { return [] }
        let r = radial(index, of: count)
        let t = across(index, of: count)
        let h = G.chipHeight
        let slanted = r.dx != 0 && r.dy != 0
        let inner = leafReach + G.chipClearance
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
            let depth = slanted ? sharedDepth : inner + halfDepths[i]
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

    /// What is under `point`. `open` is the leaf whose chips show, with their frames.
    ///
    /// Order: the open leaf's chips, the hub (it sits over the leaves' points), any leaf by
    /// its real outline, the band joining the open leaf to its chips (so moving onto a chip
    /// never closes them), and last a leaf within `leafHitSlop` of the point.
    static func hit(_ point: CGPoint, count: Int, open: Int?, chips: [CGRect]) -> BloomHit {
        if let open {
            for (i, frame) in chips.enumerated() where frame.insetBy(dx: -3, dy: -3).contains(point) {
                return .chip(leaf: open, index: i)
            }
        }
        if distance(point, .zero) <= G.hubSize / 2 { return .hub }
        for index in 0..<count where leafPath(index, of: count).contains(point) {
            return .leaf(index)
        }
        if let open, open < count, inBand(point, leaf: open, of: count, chips: chips) {
            return .leaf(open)
        }
        var nearest: (index: Int, distance: CGFloat)?
        for index in 0..<count {
            let d = distance(point, toOutline: leafOutline(index, of: count))
            if d <= G.leafHitSlop, nearest == nil || d < nearest!.distance { nearest = (index, d) }
        }
        if let nearest { return .leaf(nearest.index) }
        return .none
    }

    /// The area from the middle of a leaf out to the far edge of its chips, across the
    /// leaf's width and the chips' full width.
    static func inBand(_ point: CGPoint, leaf index: Int, of count: Int, chips: [CGRect]) -> Bool {
        guard !chips.isEmpty else { return false }
        let r = radial(index, of: count)
        let t = across(index, of: count)
        func project(_ p: CGPoint) -> (r: CGFloat, t: CGFloat) { (p.x * r.dx + p.y * r.dy, p.x * t.dx + p.y * t.dy) }
        var outer = -CGFloat.infinity
        let halfWidth = 0.46 * G.leafSize
        var low = -halfWidth
        var high = halfWidth
        for frame in chips {
            for corner in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                           CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
                let p = project(corner)
                outer = max(outer, p.r)
                low = min(low, p.t)
                high = max(high, p.t)
            }
        }
        let p = project(point)
        let inner = G.leafTip + 0.45 * G.leafSize
        return p.r >= inner && p.r <= outer + 4 && p.t >= low - 4 && p.t <= high + 4
    }

    /// Everything a clover of `count` leaves can show, chips included, around the centre (y down).
    static func contentBounds(count: Int, chipWidths: [[CGFloat]]) -> CGRect {
        var bounds = CGRect(x: -G.hubSize / 2, y: -G.hubSize / 2, width: G.hubSize, height: G.hubSize)
        bounds = bounds.union(CGRect(x: -G.hintMaxWidth / 2, y: G.hintCenterY - G.hintHeight / 2,
                                     width: G.hintMaxWidth, height: G.hintHeight))
        for index in 0..<count {
            bounds = bounds.union(leafBounds(index, of: count).insetBy(dx: -G.glowMargin, dy: -G.glowMargin))
            for widths in chipWidths {
                for frame in chipFrames(index, of: count, widths: widths) {
                    bounds = bounds.union(frame.insetBy(dx: -G.shadowMargin, dy: -G.shadowMargin))
                }
            }
        }
        return bounds
    }

    /// Moves a clover centre inward so `bounds` (clover coordinates, y down) fits inside
    /// `visible` (screen coordinates, y up). Rounded to whole points.
    static func clampedCenter(_ point: CGPoint, bounds: CGRect, visible: CGRect) -> CGPoint {
        // In screen space y points up, so the clover's top is -bounds.minY above the centre.
        func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat, middle: CGFloat) -> CGFloat {
            low > high ? middle : min(max(v, low), high)
        }
        let x = clamp(point.x, visible.minX - bounds.minX, visible.maxX - bounds.maxX, middle: visible.midX)
        let y = clamp(point.y, visible.minY + bounds.maxY, visible.maxY + bounds.minY, middle: visible.midY)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// A rectangle in clover coordinates (y down) placed on screen (y up) around `center`.
    static func screenRect(_ r: CGRect, center: CGPoint) -> CGRect {
        CGRect(x: center.x + r.minX, y: center.y - r.maxY, width: r.width, height: r.height)
    }

    /// Converts a point in the panel's own view (origin bottom-left, y up) to clover coordinates.
    static func bloomPoint(fromView p: CGPoint, panelSize: CGFloat = G.panelSize) -> CGPoint {
        CGPoint(x: p.x - panelSize / 2, y: panelSize / 2 - p.y)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Shortest distance from a point to a closed outline.
    static func distance(_ p: CGPoint, toOutline outline: [CGPoint]) -> CGFloat {
        var best = CGFloat.infinity
        for i in outline.indices {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1) : 0
            best = min(best, hypot(p.x - a.x - t * dx, p.y - a.y - t * dy))
        }
        return best
    }

    /// Snaps tiny floating-point leftovers (cos 90°) to zero.
    private static func clean(_ v: CGFloat) -> CGFloat {
        abs(v) < 1e-9 ? 0 : v
    }
}

// MARK: - More tray

/// Where a pointer is over the More tray.
enum TrayHit: Equatable {
    case none
    /// Inside the tray, between pills.
    case background
    case pill(Int)
    case chip(pill: Int, index: Int)

    var pill: Int? {
        switch self {
        case .pill(let pill), .chip(let pill, _): pill
        default: nil
        }
    }
}

/// The More tray: every target that isn't on a leaf, as pills in a grid, with the
/// hovered pill's chips in a row just under it. Each row of pills has a lane under it
/// for those chips, so they never cover a pill and nothing moves under the pointer;
/// the last row's chips hang just below the tray. Tray coordinates have their origin at
/// the tray's top-left corner, y down. Pure math.
enum TrayLayout {
    static let columns = 3
    static let pillHeight: CGFloat = 28
    /// Between two pills in a row.
    static let gap: CGFloat = 6
    static let padding: CGFloat = 8
    static let cornerRadius: CGFloat = 14
    static let pillMinWidth: CGFloat = 78
    static let pillMaxWidth: CGFloat = 112
    /// Icon, space after it, and the text inset on each side of a pill.
    static let iconWidth: CGFloat = 14
    static let iconGap: CGFloat = 5
    static let pillPadding: CGFloat = 10
    /// From a pill's lower edge to its chips.
    static let chipDrop: CGFloat = 4
    /// Between two rows: the lane for the upper row's chips.
    static var lane: CGFloat { chipDrop * 2 + BloomGeometry.chipHeight }
    /// Space kept between the tray and the More leaf's outer edge.
    static let leafGap: CGFloat = 10
    /// Space kept between the tray and the screen's edges.
    static let screenMargin: CGFloat = 8
    /// Room around the tray, in its window, for shadows.
    static let windowMargin: CGFloat = 12

    /// One width for every pill, so the grid lines up.
    static func pillWidth(textWidths: [CGFloat]) -> CGFloat {
        let widest = (textWidths.max() ?? 0) + iconWidth + iconGap + pillPadding * 2
        return min(max(pillMinWidth, widest.rounded(.up)), pillMaxWidth)
    }

    static func columnCount(_ count: Int) -> Int { min(columns, max(count, 1)) }

    static func rowCount(_ count: Int) -> Int { (max(count, 1) + columns - 1) / columns }

    /// The pills' grid, without padding.
    static func gridSize(count: Int, pillWidth: CGFloat) -> CGSize {
        let c = CGFloat(columnCount(count)), r = CGFloat(rowCount(count))
        return CGSize(width: c * pillWidth + (c - 1) * gap, height: r * pillHeight + (r - 1) * lane)
    }

    /// The tray's own size, without the chips that may hang below its last row. It is
    /// wide enough for its widest row of chips, `chipRow`, so they never stick out.
    static func size(count: Int, pillWidth: CGFloat, chipRow: CGFloat = 0) -> CGSize {
        let grid = gridSize(count: count, pillWidth: pillWidth)
        return CGSize(width: max(grid.width, chipRow) + padding * 2, height: grid.height + padding * 2)
    }

    /// The width of a row of chips.
    static func chipRowWidth(_ widths: [CGFloat]) -> CGFloat {
        widths.isEmpty ? 0 : widths.reduce(0, +) + BloomGeometry.chipGap * CGFloat(widths.count - 1)
    }

    /// How far chips under the last row reach below the tray.
    static var overhang: CGFloat { max(0, chipDrop + BloomGeometry.chipHeight - padding) }

    /// Pills fill rows left to right, top to bottom, the grid centred across the tray.
    static func pillFrames(count: Int, pillWidth: CGFloat, trayWidth: CGFloat) -> [CGRect] {
        let columns = columnCount(count)
        let left = ((trayWidth - gridSize(count: count, pillWidth: pillWidth).width) / 2).rounded()
        return (0..<count).map { i in
            let row = CGFloat(i / columns), column = CGFloat(i % columns)
            return CGRect(x: left + column * (pillWidth + gap), y: padding + row * (pillHeight + lane),
                          width: pillWidth, height: pillHeight)
        }
    }

    /// A row of chips just under a pill, centred on it and kept within the tray's width.
    static func chipFrames(under pill: CGRect, widths: [CGFloat], trayWidth: CGFloat) -> [CGRect] {
        guard !widths.isEmpty else { return [] }
        let total = chipRowWidth(widths)
        var x = pill.midX - total / 2
        if total <= trayWidth - padding * 2 {
            x = min(max(x, padding), trayWidth - padding - total)
        } else {
            x = (trayWidth - total) / 2
        }
        x = x.rounded()
        let y = pill.maxY + chipDrop
        var frames: [CGRect] = []
        for w in widths {
            frames.append(CGRect(x: x, y: y, width: w, height: BloomGeometry.chipHeight))
            x += w + BloomGeometry.chipGap
        }
        return frames
    }

    /// What is under `point`. `open` is the pill whose chips show, with their frames.
    /// Chips first, then the strip joining the open pill to its chips (so moving onto a
    /// chip never closes them), then pills, then the tray itself.
    static func hit(_ point: CGPoint, pills: [CGRect], open: Int?, chips: [CGRect], size: CGSize) -> TrayHit {
        if let open, pills.indices.contains(open) {
            for (i, frame) in chips.enumerated() where frame.insetBy(dx: -3, dy: -2).contains(point) {
                return .chip(pill: open, index: i)
            }
            if let first = chips.first, let last = chips.last {
                let pill = pills[open]
                let strip = CGRect(x: min(pill.minX, first.minX), y: pill.maxY,
                                   width: max(pill.maxX, last.maxX) - min(pill.minX, first.minX), height: first.minY - pill.maxY)
                if strip.insetBy(dx: 0, dy: -1).contains(point) { return .pill(open) }
            }
        }
        for (i, frame) in pills.enumerated() where frame.insetBy(dx: -2, dy: -2).contains(point) {
            return .pill(i)
        }
        if CGRect(origin: .zero, size: size).contains(point) { return .background }
        return .none
    }

    /// The tray's frame on screen (y up), `size` tall plus `overhang`. `more` is the More
    /// leaf's bounding box on screen and `clover` the clover's centre.
    ///
    /// Beside the More leaf on its outer side, centred on it, like a submenu, so the
    /// pointer goes straight across without touching another leaf. When the screen's edge
    /// would push it over the More leaf, it goes above the leaf (below, for a lower
    /// leaf), and failing that on the other side, so More always stays in view.
    static func frame(size: CGSize, more: CGRect, clover: CGPoint, visible: CGRect) -> CGRect {
        let height = size.height + overhang
        let area = visible.insetBy(dx: screenMargin, dy: screenMargin)
        func clamped(_ rect: CGRect) -> CGRect {
            var r = rect
            r.origin.x = r.width <= area.width ? min(max(r.minX, area.minX), area.maxX - r.width) : area.midX - r.width / 2
            r.origin.y = r.height <= area.height ? min(max(r.minY, area.minY), area.maxY - r.height) : area.midY - r.height / 2
            return CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width, height: r.height)
        }
        let onLeft = more.midX < clover.x - 0.5
        let beside = CGRect(x: onLeft ? more.minX - leafGap - size.width : more.maxX + leafGap,
                            y: more.midY - size.height / 2 - overhang, width: size.width, height: height)
        let over = CGRect(x: more.midX - size.width / 2, y: more.maxY + leafGap, width: size.width, height: height)
        let under = CGRect(x: more.midX - size.width / 2, y: more.minY - leafGap - height, width: size.width, height: height)
        let candidates = (more.midY >= clover.y ? [beside, over, under] : [beside, under, over]).map(clamped)
        func cover(_ r: CGRect) -> CGFloat {
            let i = r.intersection(more.insetBy(dx: 2, dy: 2))
            return i.isNull ? 0 : i.width * i.height
        }
        // The first that leaves More uncovered, or the one covering least of it.
        return candidates.first { cover($0) == 0 } ?? candidates.min { cover($0) < cover($1) }!
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
