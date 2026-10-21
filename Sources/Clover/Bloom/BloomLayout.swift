import CoreGraphics
import Foundation

/// Fixed sizes of the clover, in points.
enum BloomGeometry {
    /// The glass disc: 380 pt across, with room
    /// for air around every slot.
    static let discRadius: CGFloat = 190
    /// The rim, a thin ring of clear glass inside the disc's edge.
    static let rimWidth: CGFloat = 10
    /// Between two neighbouring slots, so plenty of the disc's glass shows between them.
    static let slotGap: CGFloat = 14
    /// Between a slot and the centre circle, and between a slot and the rim.
    static let slotInset: CGFloat = 10
    /// The centre circle, with the files' picture: a third of the disc.
    static let hubSize: CGFloat = 120
    /// Where slots start and how far their lobes reach, from the centre.
    static var slotInner: CGFloat { hubSize / 2 + slotInset }
    static var slotOuter: CGFloat { discRadius - rimWidth - slotInset }
    /// Most slots the clover shows. With more targets, the last one is "More".
    static let maxLeaves = 6
    /// A slot's base is this half-wide at the centre circle and widens at `baseSlope`
    /// until it meets the gaps, so it reads as a leaflet's narrow base.
    static let baseHalfWidth: CGFloat = 24
    static let baseSlope: CGFloat = 1.7
    /// Rounding of the base's corners, and of the notch.
    static let baseRounding: CGFloat = 12
    static let notchRounding: CGFloat = 3
    /// How round a lobe's shoulder is, as a share of the lobe's half-width, and its cap as
    /// a share of the slot's depth (wide slots would otherwise turn into beans).
    static let shoulder: CGFloat = 0.9
    static let shoulderCap: CGFloat = 0.55
    /// The notch between the lobes: a share of the slot's depth, or of its half-width for
    /// wide slots, whichever is deeper.
    static let notchOfDepth: CGFloat = 0.14
    static let notchOfWidth: CGFloat = 0.11
    /// The label block in a slot: a title alone, or a tool's small icon over its title.
    static let titleHeight: CGFloat = 18
    static let labelHeight: CGFloat = 34
    /// The tool's icon, and the space under it.
    static let labelIcon = CGSize(width: 14, height: 12)
    static let labelIconGap: CGFloat = 2
    /// Clear space kept between a label and its slot's outline, on every side.
    static let labelClearance: CGFloat = 8
    /// The label fits in this width in every slot, so a long title shrinks the same way everywhere.
    static let labelMaxWidth: CGFloat = 84
    /// The ideal distance of a label's middle from the centre: 72 % of the disc's radius.
    static var labelRadius: CGFloat { (0.72 * discRadius).rounded() }
    static let chipHeight: CGFloat = 24
    /// Space between two chips.
    static let chipGap: CGFloat = 6
    /// Space between the disc's edge and its chips.
    static let chipClearance: CGFloat = 8
    /// Text inset inside a chip, each side.
    static let chipPadding: CGFloat = 10
    /// The default chip's dot and the space after it.
    static let chipDotWidth: CGFloat = 9
    static let chipMinWidth: CGFloat = 44
    /// The picture in the centre circle, with the size capsule on top of it.
    static let pictureSide: CGFloat = 56
    static let pictureCenterY: CGFloat = 10
    static let capsuleCenterY: CGFloat = -31
    static let capsuleHeight: CGFloat = 20
    static let capsuleMaxWidth: CGFloat = 84
    /// Room kept around a chip for its shadow.
    static let shadowMargin: CGFloat = 6
    /// A point this close outside the disc still counts as on it.
    static let leafHitSlop: CGFloat = 3
    /// The panel is a square of this side, centred on the clover.
    static let panelSize: CGFloat = 600
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

/// The clover-leaf slot: a wedge of the disc whose narrow base sits at the centre circle,
/// whose sides run along the gaps, and whose outer edge is two round lobes with a shallow
/// notch. Built for slot 0 at 12 o'clock, with the origin at the disc's centre and y down.
@MainActor
enum SlotShape {
    typealias G = BloomGeometry

    private static var paths: [Int: CGPath] = [:]

    /// Slots are drawn at least as narrow as three to a disc, so one or two still look like leaves.
    static func shapeCount(_ count: Int) -> Int { max(count, 3) }

    /// Half the slot's angle at radius `r`: the wedge less the gap, narrowed near the base.
    static func sideAngle(_ r: CGFloat, count: Int) -> CGFloat {
        let h = CGFloat.pi / CGFloat(shapeCount(count))
        let wedge = r * (h - asin(min(1, (G.slotGap / 2) / r)))
        let taper = G.baseHalfWidth + max(0, r - G.slotInner) * G.baseSlope
        // A smooth minimum, so the taper flows into the side.
        let k: CGFloat = 12
        let width = 0.5 * (wedge + taper - sqrt((wedge - taper) * (wedge - taper) + k * k))
        return width / r
    }

    static func notchDepth(count: Int) -> CGFloat {
        let depth = G.slotOuter - G.slotInner
        let halfArc = sideAngle(G.slotOuter, count: count) * G.slotOuter
        return max(G.notchOfDepth * depth, G.notchOfWidth * halfArc)
    }

    /// The slot's outline for a clover of `count` slots.
    static func path(count: Int) -> CGPath {
        let n = shapeCount(count)
        if let cached = paths[n] { return cached }
        let built = build(count: n)
        paths[n] = built
        return built
    }

    private static func build(count: Int) -> CGPath {
        let inner = G.slotInner, outer = G.slotOuter
        let depth = outer - inner
        let d = notchDepth(count: count)
        // The lobe tops sit halfway out each half; the shoulders round down into the sides.
        let top: CGFloat = 0.5
        let halfLobe = (1 - top) * sideAngle(outer, count: count) * outer
        let shoulder = min(G.shoulder * halfLobe, G.shoulderCap * depth)
        func profile(_ u: CGFloat) -> CGFloat {
            let a = abs(u)
            if a <= top {
                // From the lobe's top down into the notch: a soft V.
                return outer - d * pow((top - a) / top, 1.7)
            }
            let t = min((a - top) / (1 - top), 1)
            return outer - shoulder * (1 - sqrt(max(0, 1 - t * t)))
        }
        func polar(_ r: CGFloat, _ phi: CGFloat) -> CGPoint { CGPoint(x: r * sin(phi), y: -r * cos(phi)) }
        var points: [CGPoint] = []
        let steps = 240
        for i in 0...steps {
            let u = -1 + 2 * CGFloat(i) / CGFloat(steps)
            let r = profile(u)
            points.append(polar(r, u * sideAngle(r, count: count)))
        }
        let side = profile(1)
        let sideSteps = 48
        for i in 1...sideSteps {
            let r = side + (inner - side) * CGFloat(i) / CGFloat(sideSteps)
            points.append(polar(r, sideAngle(r, count: count)))
        }
        let baseSteps = 24
        for i in 1..<baseSteps {
            points.append(polar(inner, sideAngle(inner, count: count) * (1 - 2 * CGFloat(i) / CGFloat(baseSteps))))
        }
        for i in 0..<sideSteps {
            let r = inner + (side - inner) * CGFloat(i) / CGFloat(sideSteps)
            points.append(polar(r, -sideAngle(r, count: count)))
        }
        let raw = CGMutablePath()
        raw.addLines(between: points)
        raw.closeSubpath()
        // Round the base's corners (an opening), then soften the notch (a closing).
        let opened = dilate(erode(raw, G.baseRounding), G.baseRounding)
        return erode(dilate(opened, G.notchRounding), G.notchRounding)
    }

    private static func band(_ p: CGPath, _ r: CGFloat) -> CGPath {
        p.copy(strokingWithWidth: 2 * r, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }

    private static func erode(_ p: CGPath, _ r: CGFloat) -> CGPath { p.subtracting(band(p, r)) }
    private static func dilate(_ p: CGPath, _ r: CGFloat) -> CGPath { p.union(band(p, r)) }

    /// The path's largest closed outline as points, about `step` apart along curves.
    static func flatten(_ path: CGPath, step: CGFloat = 1.5) -> [CGPoint] {
        var outlines: [[CGPoint]] = []
        var current: [CGPoint] = []
        var last = CGPoint.zero
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                if current.count > 2 { outlines.append(current) }
                current = [e.points[0]]
                last = e.points[0]
            case .addLineToPoint:
                current.append(e.points[0])
                last = e.points[0]
            case .addQuadCurveToPoint:
                let c = e.points[0], p = e.points[1]
                let n = max(2, Int((hypot(c.x - last.x, c.y - last.y) + hypot(p.x - c.x, p.y - c.y)) / step))
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    current.append(CGPoint(x: u * u * last.x + 2 * u * t * c.x + t * t * p.x,
                                           y: u * u * last.y + 2 * u * t * c.y + t * t * p.y))
                }
                last = p
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], p = e.points[2]
                let length = hypot(c1.x - last.x, c1.y - last.y) + hypot(c2.x - c1.x, c2.y - c1.y) + hypot(p.x - c2.x, p.y - c2.y)
                let n = max(2, Int(length / step))
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    current.append(CGPoint(x: a * last.x + b * c1.x + c * c2.x + d * p.x,
                                           y: a * last.y + b * c1.y + c * c2.y + d * p.y))
                }
                last = p
            case .closeSubpath:
                if current.count > 2 { outlines.append(current) }
                current = []
            @unknown default:
                break
            }
        }
        if current.count > 2 { outlines.append(current) }
        return outlines.max { $0.count < $1.count } ?? []
    }
}

/// Positions, slot shapes, chip rows, hit-testing and screen-edge clamping. Pure math.
///
/// Clover coordinates have their origin at the disc's centre, with y pointing down.
/// Slots are numbered clockwise from 12 o'clock; `count` is how many there are.
@MainActor
enum BloomLayout {
    typealias G = BloomGeometry

    /// Clockwise angle from 12 o'clock, in radians: evenly spaced, the first at 12.
    static func angle(_ index: Int, of count: Int) -> CGFloat {
        CGFloat(index) * .pi * 2 / CGFloat(max(count, 1))
    }

    /// Unit vector from the centre along a slot.
    static func radial(_ index: Int, of count: Int) -> CGVector {
        let a = angle(index, of: count)
        return CGVector(dx: clean(sin(a)), dy: clean(-cos(a)))
    }

    /// Unit vector across a slot, pointed so chips read top to bottom, or left to right
    /// in a level row.
    static func across(_ index: Int, of count: Int) -> CGVector {
        let a = angle(index, of: count)
        var t = CGVector(dx: clean(cos(a)), dy: clean(sin(a)))
        if t.dy < 0 || (t.dy == 0 && t.dx < 0) { t = CGVector(dx: -t.dx, dy: -t.dy) }
        return t
    }

    private struct Key: Hashable {
        let index: Int
        let count: Int
        var icon = false
    }

    private static var paths: [Key: CGPath] = [:]
    private static var outlines: [Key: [CGPoint]] = [:]
    private static var labels: [Key: CGRect] = [:]

    /// The slot's outline in clover coordinates.
    static func leafPath(_ index: Int, of count: Int) -> CGPath {
        let key = Key(index: index, count: count)
        if let cached = paths[key] { return cached }
        var t = CGAffineTransform(rotationAngle: angle(index, of: count))
        let base = SlotShape.path(count: count)
        let path = base.copy(using: &t) ?? base
        paths[key] = path
        return path
    }

    /// The outline as points, for distances and label fitting.
    static func leafOutline(_ index: Int, of count: Int) -> [CGPoint] {
        let key = Key(index: index, count: count)
        if let cached = outlines[key] { return cached }
        let points = SlotShape.flatten(leafPath(index, of: count))
        outlines[key] = points
        return points
    }

    static func leafBounds(_ index: Int, of count: Int) -> CGRect {
        leafPath(index, of: count).boundingBoxOfPath
    }

    /// The middle of a slot's bounding box, where it is drawn.
    static func leafCenter(_ index: Int, of count: Int) -> CGPoint {
        let b = leafBounds(index, of: count)
        return CGPoint(x: b.midX, y: b.midY)
    }

    /// The slot whose sector of the disc holds `point`.
    static func sector(_ point: CGPoint, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var a = atan2(point.x, -point.y)
        if a < 0 { a += 2 * .pi }
        let step = 2 * CGFloat.pi / CGFloat(count)
        return Int(((a + step / 2) / step).rounded(.down)) % count
    }

    /// The bounding box of a slot's whole sector, out to the disc's edge.
    static func sectorBounds(_ index: Int, of count: Int) -> CGRect {
        let a = angle(index, of: count)
        let half = CGFloat.pi / CGFloat(max(count, 1))
        var points: [CGPoint] = []
        for i in 0...24 {
            let phi = a - half + 2 * half * CGFloat(i) / 24
            points.append(CGPoint(x: G.discRadius * sin(phi), y: -G.discRadius * cos(phi)))
            points.append(CGPoint(x: G.hubSize / 2 * sin(phi), y: -G.hubSize / 2 * cos(phi)))
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Where a slot's label goes: an upright box in the broad part of the slot, as wide
    /// as its title fits (at most `labelMaxWidth`) with `labelClearance` of clear space on
    /// every side, as near `labelRadius` along the slot as that allows. With `icon`, a
    /// tool's small icon sits over the title and needs less width.
    static func labelBox(_ index: Int, of count: Int, icon: Bool = false) -> CGRect {
        let key = Key(index: index, count: count, icon: icon)
        if let cached = labels[key] { return cached }
        let outline = leafOutline(index, of: count)
        let r = radial(index, of: count)
        let height = icon ? G.labelHeight : G.titleHeight
        let half = height / 2
        // The rows the label covers, and its clear space above and below.
        let clear = G.labelClearance
        // The title's rows need the full width; a tool's icon rows above need only its own.
        let titleTop = icon ? -half + G.labelIcon.height + G.labelIconGap : -half - clear
        let iconRows = icon ? stride(from: -half - clear, through: titleTop - 1, by: 2).map { $0 } : []
        let titleRows = stride(from: titleTop, through: half + clear, by: 2).map { $0 }
        let middle = CGPoint(x: r.dx * G.labelRadius, y: r.dy * G.labelRadius)
        let wanted = G.labelMaxWidth
        let reach: CGFloat = 30
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
            guard distance(c, middle) < reach,
                  iconRows.isEmpty || (halfWidth(x: c.x, y: c.y, rows: iconRows) ?? 0) >= G.labelIcon.width / 2 + clear,
                  let title = halfWidth(x: c.x, y: c.y, rows: titleRows) else { return }
            let width = (title - clear) * 2
            let score = min(width, wanted) * 4 - distance(c, middle)
            if best == nil || score > best!.score { best = (c, width, score) }
        }
        for dy in stride(from: -reach, through: reach, by: 4) {
            for dx in stride(from: -reach, through: reach, by: 4) { consider(CGPoint(x: middle.x + dx, y: middle.y + dy)) }
        }
        if let coarse = best?.center {
            for dy in stride(from: -4.0, through: 4, by: 1) {
                for dx in stride(from: -4.0, through: 4, by: 1) { consider(CGPoint(x: coarse.x + dx, y: coarse.y + dy)) }
            }
        }
        let center = best?.center ?? middle
        let width = min(best?.width ?? 0, G.labelMaxWidth).rounded(.down)
        let box = CGRect(x: (center.x - width / 2).rounded(), y: (center.y - half).rounded(), width: width, height: height)
        labels[key] = box
        return box
    }

    /// The faint midrib from a slot's base to its notch, in pieces that leave its label clear.
    static func midrib(_ index: Int, of count: Int, icon: Bool = false) -> [(CGPoint, CGPoint)] {
        let r = radial(index, of: count)
        let start = G.slotInner + 8
        let end = G.slotOuter - SlotShape.notchDepth(count: count) - 7
        let a = CGPoint(x: r.dx * start, y: r.dy * start), b = CGPoint(x: r.dx * end, y: r.dy * end)
        let box = labelBox(index, of: count, icon: icon).insetBy(dx: -4, dy: -3)
        // The stretch of the segment inside the box (Liang-Barsky), cut out.
        var t0: CGFloat = 0, t1: CGFloat = 1
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - box.minX), (dx, box.maxX - a.x), (-dy, a.y - box.minY), (dy, box.maxY - a.y)] {
            if p == 0 {
                if q < 0 { return [(a, b)] }
            } else {
                let t = q / p
                if p < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
            }
        }
        guard t0 < t1 else { return [(a, b)] }
        func at(_ t: CGFloat) -> CGPoint { CGPoint(x: a.x + dx * t, y: a.y + dy * t) }
        var pieces: [(CGPoint, CGPoint)] = []
        if t0 > 0.04 { pieces.append((a, at(t0))) }
        if t1 < 0.96 { pieces.append((at(t1), b)) }
        return pieces
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

    /// Chip frames for a slot's options: one straight row just outside the disc beyond the
    /// slot, across its direction. A level row at 12 and 6, a column at 3 and 9 with its
    /// inner edges at the same depth, and a tight staircase at other angles. Chips never
    /// overlap each other or the disc.
    static func chipFrames(_ index: Int, of count: Int, widths: [CGFloat]) -> [CGRect] {
        guard !widths.isEmpty else { return [] }
        let r = radial(index, of: count)
        let t = across(index, of: count)
        let h = G.chipHeight
        let slanted = r.dx != 0 && r.dy != 0
        let inner = G.discRadius + G.chipClearance
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
            var depth = slanted ? sharedDepth : inner + halfDepths[i]
            let offset = offsets[i] - middle
            // A chip far to the side of a level row would cut into the disc's curve: push it out.
            var cx = r.dx * depth + t.dx * offset, cy = r.dy * depth + t.dy * offset
            while nearest(CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)) < inner {
                depth += 1
                cx = r.dx * depth + t.dx * offset
                cy = r.dy * depth + t.dy * offset
            }
            cx = cx.rounded()
            cy = cy.rounded()
            return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        }
    }

    /// The distance from the centre to the nearest point of a rectangle.
    static func nearest(_ rect: CGRect) -> CGFloat {
        let x = min(max(0, rect.minX), rect.maxX), y = min(max(0, rect.minY), rect.maxY)
        return hypot(x, y)
    }

    /// The width of a chip for a title of the given text width.
    static func chipWidth(textWidth: CGFloat, isDefault: Bool) -> CGFloat {
        let w = textWidth + G.chipPadding * 2 + (isDefault ? G.chipDotWidth : 0)
        return max(G.chipMinWidth, w.rounded(.up))
    }

    /// What is under `point`. `open` is the slot whose chips show, with their frames.
    ///
    /// Order: the open slot's chips, the centre circle, the slot whose sector of the disc
    /// holds the point (gaps and rim included, so nothing flickers between slots), the
    /// band joining the open slot to its chips (so moving onto a chip never closes them),
    /// and nothing beyond.
    static func hit(_ point: CGPoint, count: Int, open: Int?, chips: [CGRect]) -> BloomHit {
        if let open {
            for (i, frame) in chips.enumerated() where frame.insetBy(dx: -3, dy: -3).contains(point) {
                return .chip(leaf: open, index: i)
            }
        }
        let r = distance(point, .zero)
        if r <= G.hubSize / 2 + G.slotInset / 2 { return .hub }
        if count > 0, r <= G.discRadius + G.leafHitSlop { return .leaf(sector(point, count: count)) }
        if let open, open < count, inBand(point, leaf: open, of: count, chips: chips) {
            return .leaf(open)
        }
        return .none
    }

    /// The area from the disc's edge out to the far edge of a slot's chips, across the
    /// chips' full width.
    static func inBand(_ point: CGPoint, leaf index: Int, of count: Int, chips: [CGRect]) -> Bool {
        guard !chips.isEmpty else { return false }
        let r = radial(index, of: count)
        let t = across(index, of: count)
        func project(_ p: CGPoint) -> (r: CGFloat, t: CGFloat) { (p.x * r.dx + p.y * r.dy, p.x * t.dx + p.y * t.dy) }
        var outer = -CGFloat.infinity
        var low: CGFloat = -40
        var high: CGFloat = 40
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
        return p.r >= G.discRadius - 4 && p.r <= outer + 4 && p.t >= low - 4 && p.t <= high + 4
    }

    /// Everything a clover of `count` slots can show, chips included, around the centre (y down).
    static func contentBounds(count: Int, chipWidths: [[CGFloat]]) -> CGRect {
        let d = G.discRadius + G.shadowMargin
        var bounds = CGRect(x: -d, y: -d, width: 2 * d, height: 2 * d)
        for index in 0..<count {
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

    /// The point the tray grows out of, as a fraction of its frame from its top-left: the
    /// spot on its edge nearest the More slot. Both rectangles on screen (y up).
    static func anchor(tray: CGRect, more: CGRect) -> CGPoint {
        let x = min(max(more.midX, tray.minX), tray.maxX)
        let y = min(max(more.midY, tray.minY), tray.maxY)
        return CGPoint(x: (x - tray.minX) / max(tray.width, 1), y: (tray.maxY - y) / max(tray.height, 1))
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
