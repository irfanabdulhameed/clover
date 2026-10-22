import AppKit
import SwiftUI
import CloverCore

/// The clover: one Liquid Glass disc with a rim, clover-leaf slots packed around a centre
/// circle with the files, and chips beyond the open slot. Shapes and positions come from
/// `BloomLayout`, so what is drawn is exactly what is hit-tested; motion comes from
/// `Motion`, timed by the model's events. The view takes no clicks itself;
/// `BloomInteractionView` above it does.
struct BloomView: View {
    @ObservedObject var model: BloomModel
    /// A fixed moment to draw, for the debug renders. Nil follows the clock.
    var time: TimeInterval? = nil

    var body: some View {
        if let time {
            BloomScene(model: model, now: time)
        } else {
            // Frames run only while something moves; a lit slot's glow keeps breathing.
            TimelineView(.animation(minimumInterval: nil, paused: !model.animating)) { context in
                BloomScene(model: model, now: max(context.date.timeIntervalSinceReferenceDate,
                                                  Date().timeIntervalSinceReferenceDate))
            }
        }
    }
}

/// The clover drawn at one moment, `now`.
struct BloomScene: View {
    @ObservedObject var model: BloomModel
    let now: TimeInterval
    var side: CGFloat = BloomGeometry.panelSize

    @Environment(\.colorScheme) private var scheme
    @Environment(\.bloomSnapshot) private var snapshot
    private typealias G = BloomGeometry

    var body: some View {
        let e = model.events
        let count = model.leafCount
        let center = CGPoint(x: side / 2, y: side / 2)
        let carried = e.drop?.slot
        // The chosen leaf's middle, where the wave of light starts.
        let origin = carried.map { BloomLayout.leafCenter($0, of: count) } ?? .zero
        let wave = Motion.wave(e, now: now, origin: origin)
        ZStack {
            if !snapshot {
                // Nearly invisible, so the window takes drags and clicks across the clover.
                Circle().fill(Color.black.opacity(0.012)).frame(width: side - 8, height: side - 8)
            }
            LiquidGlassGroup(spacing: 6) {
                ZStack {
                    disc(e)
                    chips(e, count: count, center: center)
                }
                .frame(width: side, height: side)
            }
            if let lit = e.lit, lit < count, let glow = Motion.glow(e, now: now) {
                SlotGlow(index: lit, count: count, color: BloomStyle.cloverGlow(scheme))
                    .scaleEffect(glow.scale)
                    .opacity(glow.opacity)
                    .position(offset(BloomLayout.leafCenter(lit, of: count), center))
            }
            layer(e, count: count, center: center, carried: carried, origin: origin)
            if let wave {
                WaveFront(origin: offset(origin, center), wave: wave, side: side)
            }
            ForEach(Array(e.ripples.enumerated()), id: \.offset) { _, ripple in
                if ripple.slot < count, let r = Motion.ripple(ripple, e, now: now) {
                    Path(SlotView.localPath(ripple.slot, count))
                        .stroke(rippleColor.opacity(r.opacity), lineWidth: r.width)
                        .frame(width: BloomLayout.leafBounds(ripple.slot, of: count).width,
                               height: BloomLayout.leafBounds(ripple.slot, of: count).height)
                        .scaleEffect(r.scale)
                        .blur(radius: 0.4)
                        .position(offset(BloomLayout.leafCenter(ripple.slot, of: count), center))
                }
            }
            if let carried, carried < model.leaves.count {
                slot(carried, model.leaves[carried], count: count, center: center, e, origin: origin)
            }
            if let ring = Motion.carryRing(e, now: now) {
                // The ring on the hub's glass: the chip's own ring, which it picks up here.
                if e.reduce {
                    RingButton().look(ring).position(center)
                } else {
                    ChipRing(progress: 0, diameter: Motion.Drop.ringSide).look(ring).position(center)
                }
            }
            if let ring = Motion.lightRing(e, now: now) {
                LightRing(radius: ring.radius, width: ring.width, color: rippleColor)
                    .opacity(ring.opacity)
                    .position(center)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    // MARK: Parts

    /// The slots that aren't carried, the centre circle and its capsule.
    private func layer(_ e: BloomEvents, count: Int, center: CGPoint, carried: Int?, origin: CGPoint) -> some View {
        ZStack {
            ForEach(Array(model.leaves.enumerated()), id: \.offset) { index, leaf in
                if index != carried { slot(index, leaf, count: count, center: center, e, origin: origin) }
            }
            HubView(pictures: model.pictures, count: model.files.count, hasFiles: model.hasFiles,
                    content: Motion.hubContent(e, now: now))
                .look(Motion.hub(e, now: now, origin: origin))
                .position(center)
            if !model.hint.isEmpty {
                CapsuleLabel(text: model.hint)
                    .look(Motion.capsule(e, now: now))
                    .position(x: center.x, y: center.y + G.capsuleCenterY)
            }
        }
        .frame(width: side, height: side)
    }

    private func disc(_ e: BloomEvents) -> some View {
        let r = G.discRadius
        let look = Motion.disc(e, now: now)
        return ZStack {
            LiquidGlass(cornerRadius: r, tint: BloomStyle.glassTint(model.tint, scheme), bright: true)
            RimView()
        }
        .frame(width: r * 2, height: r * 2)
        .scaleEffect(look.scale)
        .opacity(look.opacity)
        .position(x: side / 2, y: side / 2)
    }

    @ViewBuilder
    private func slot(_ index: Int, _ leaf: BloomModel.Leaf, count: Int, center: CGPoint, _ e: BloomEvents,
                      origin: CGPoint = .zero) -> some View {
        let middle = BloomLayout.leafCenter(index, of: count)
        let state = Motion.slot(index, count: count, center: middle, e, now: now, origin: origin)
        // While a slot fades out it still draws its bright fill, fading.
        let amount = state.fill == .flash || e.drop != nil ? 1 : Motion.litAmount(index, e, now: now)
        let fill: SlotFill = state.fill == .frosted && amount > 0 && e.drop == nil ? .lit : state.fill
        let lights = slotLights(index, count: count, e)
        SlotView(index: index, count: count, title: title(of: leaf), symbol: symbol(of: leaf), hue: hue(of: index),
                 fill: fill, litAmount: amount, innerGlow: e.drop?.slot == index ? Motion.chosenGlow(e, now: now) : 0,
                 press: lights.press, spill: lights.spill,
                 plus: leaf == .more ? Motion.moreTurn(e, now: now) : nil, plusFades: e.reduce,
                 focused: model.focusedLeaf == index && model.focusChip == nil && model.phase == .open)
            .look(state.look)
            .position(offset(middle, center))
    }

    /// A press's light on slot `index`: its own light when it is the pressed slot, or the
    /// faint spill on its near edge when it is close to the press point.
    private func slotLights(_ index: Int, count: Int, _ e: BloomEvents) -> (press: PressLight?, spill: PressLight?) {
        guard let p = e.press, case .leaf(let pressed) = p.target, pressed < count,
              let light = Motion.pressLight(p, reduce: e.reduce, now: now) else { return (nil, nil) }
        let bounds = BloomLayout.leafBounds(index, of: count)
        let local = CGPoint(x: p.point.x - bounds.minX, y: p.point.y - bounds.minY)
        if pressed == index {
            return (PressLight.filling(bounds.size, from: local, light), nil)
        }
        let near = BloomLayout.distance(p.point, toOutline: BloomLayout.leafOutline(index, of: count))
        guard near < Motion.Press.spillReach else { return (nil, nil) }
        return (nil, PressLight(point: local, radius: near, intensity: light.intensity))
    }

    /// The open slot's chips being born, the last slot's chips shrinking back into it.
    @ViewBuilder
    private func chips(_ e: BloomEvents, count: Int, center: CGPoint) -> some View {
        let leaving = Motion.chipsLeaving(e, now: now)
        if let open = e.chipsLeaf, let target = model.target(at: open) {
            let frames = model.chipFrames(for: open)
            ForEach(Array(zip(target.options.indices, frames)), id: \.0) { index, frame in
                let rank = e.chipRank.indices.contains(index) ? e.chipRank[index] : index
                let born = Motion.chipIn(rank: rank, since: e.chipsAt, e, now: now)
                let lit = e.litChip == index
                let chosen = e.drop?.chip == index && e.drop?.pill == nil
                let press = PressLight.on(.chip(leaf: open, index: index), frame: frame, e, now: now)
                ChipView(title: target.options[index].title,
                         isDefault: target.options[index].id == target.defaultOption?.id,
                         isLit: lit || chosen,
                         isFlash: false,
                         isFocused: model.usingKeyboard && model.focusChip == index && model.phase == .open,
                         hue: BloomStyle.hue(target.format.family, scheme),
                         look: leaving ?? born,
                         pop: (lit ? Motion.litPop(at: e.litChipAt, e, now: now) : 1) * press.scale,
                         press: press.light)
                    .frame(width: frame.width, height: frame.height)
                    .position(offset(frame.mid, center))
            }
        }
        if let closing = e.closingLeaf, closing != e.chipsLeaf, let target = model.target(at: closing) {
            let frames = model.chipFrames(for: closing)
            let rim = BloomLayout.radial(closing, of: count)
            ForEach(Array(zip(target.options.indices, frames)), id: \.0) { index, frame in
                let toward = CGVector(dx: rim.dx * G.discRadius - frame.midX, dy: rim.dy * G.discRadius - frame.midY)
                // Only while they are still going: chips that have gone don't come back to fold in a drop.
                if let out = Motion.chipOut(towards: toward, e, now: now) {
                    let look = leaving ?? out
                    ChipView(title: target.options[index].title,
                             isDefault: target.options[index].id == target.defaultOption?.id,
                             isLit: false, isFlash: false, isFocused: false,
                             hue: BloomStyle.hue(target.format.family, scheme), look: look, pop: 1)
                        .frame(width: frame.width, height: frame.height)
                        .position(offset(frame.mid, center))
                }
            }
        }
    }

    private var rippleColor: Color { Color.white }

    private func title(of leaf: BloomModel.Leaf) -> String {
        switch leaf {
        case .target(let target): target.title
        case .more: "More formats"
        }
    }

    /// Tools carry a small icon; formats are a title alone; More
    /// is a + of its own.
    private func symbol(of leaf: BloomModel.Leaf) -> String? {
        switch leaf {
        case .target(let target): BloomStyle.isTool(target) ? BloomStyle.symbol(for: target) : nil
        case .more: nil
        }
    }

    private func hue(of index: Int) -> Color {
        guard let target = model.target(at: index) else { return Color.secondary }
        return BloomStyle.hue(target.format.family, scheme)
    }

    private func offset(_ p: CGPoint, _ center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x, y: center.y + p.y)
    }
}

extension CGRect {
    var mid: CGPoint { CGPoint(x: midX, y: midY) }
}

extension View {
    /// Applies a motion look: scale about the middle, offset, blur, opacity.
    func look(_ look: Look) -> some View {
        scaleEffect(look.scale)
            .offset(look.offset)
            .blur(radius: look.blur)
            .opacity(look.opacity)
    }
}

// MARK: - Disc parts

/// The rim: a thin ring of clear glass inside the disc's edge, marked by a fine line on
/// its inner side.
struct RimView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let w = BloomGeometry.rimWidth
        ZStack {
            Circle().strokeBorder(Color.white.opacity(dark ? 0.03 : 0.12), lineWidth: w)
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.16 : 0.75), Color.white.opacity(dark ? 0.05 : 0.30)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                .padding(w)
        }
    }
}

/// One clover-leaf slot: frosted, or solid clover green when lit, with a faint midrib and
/// an upright icon over its title. Its frame is the slot's bounding box.
struct SlotView: View {
    let index: Int
    let count: Int
    let title: String
    let symbol: String?
    let hue: Color
    let fill: SlotFill
    /// How far the bright fill has faded in, while lit or letting go.
    var litAmount: Double = 1
    /// The chosen leaf's soft white inner glow, 0 to 1.
    var innerGlow: Double = 0
    /// A press's light on this slot, and the spill of a press on a neighbour.
    var press: PressLight? = nil
    var spill: PressLight? = nil
    /// More: a + instead of a label, turned this far (0 to 1) into ×; cross-faded instead
    /// with `plusFades` (reduce motion).
    var plus: Double? = nil
    var plusFades = false
    let focused: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let bounds = BloomLayout.leafBounds(index, of: count)
        let local = SlotView.localPath(index, count)
        let shape = Path(local)
        let label = BloomLayout.turnedLabel(index, of: count, icon: symbol != nil)
        let dark = scheme == .dark
        let lit = fill == .flash || (fill == .lit && litAmount > 0.5)
        ZStack(alignment: .topLeading) {
            switch fill {
            case .frosted: shape.fill(Color.white.opacity(dark ? 0.11 : 0.62))
            case .lit:
                shape.fill(Color.white.opacity(dark ? 0.11 : 0.62))
                shape.fill(BloomStyle.litFill(scheme))
                    .shadow(color: BloomStyle.litShadow(scheme), radius: 6, y: 2)
                    .opacity(litAmount)
            case .flash: shape.fill(Color.white)
            }
            if innerGlow > 0 {
                // Light inside the glass, strongest at the edge: not a white fill.
                shape.stroke(Color.white, lineWidth: 16)
                    .blur(radius: 8)
                    .clipShape(shape)
                    .opacity(0.9 * innerGlow)
            }
            if let spill { SpillLightView(shape: shape, light: spill, size: bounds.size) }
            shape.stroke(rim(lit: lit, dark: dark), lineWidth: 0.75)
            if let press { PressLightView(shape: shape, light: press, size: bounds.size) }
            // No midrib line (Irfan, 22 Oct 2026). The label turns with its leaf.
            if let plus {
                // A + looks the same every 90°: turned with the leaf it would sit at a slant
                // (30° at 10 o'clock) and read as ×, so it keeps the leaf's nearest quarter turn.
                PlusIcon(turn: plus, fades: plusFades, lit: lit)
                    .rotationEffect(.radians((label.angle / (.pi / 2)).rounded() * (.pi / 2)))
                    .position(x: label.center.x - bounds.minX, y: label.center.y - bounds.minY)
                    .accessibilityLabel(title)
            } else if fill != .flash {
                SlotLabel(title: title, symbol: symbol, hue: hue, lit: lit, width: label.size.width)
                    .frame(width: label.size.width, height: label.size.height)
                    .rotationEffect(.radians(label.angle))
                    .position(x: label.center.x - bounds.minX, y: label.center.y - bounds.minY)
            }
            if focused {
                Path(PathOutset.outset(local, by: 1.5, key: "slot \(index) of \(count)"))
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
    }

    private func rim(lit: Bool, dark: Bool) -> LinearGradient {
        let top = Color.white.opacity(lit ? 0.55 : (dark ? 0.26 : 0.95))
        let bottom = lit ? Color.black.opacity(0.10) : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.07))
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private static var localPaths: [Int: CGPath] = [:]

    /// The slot's outline moved so its bounding box starts at the origin.
    static func localPath(_ index: Int, _ count: Int) -> CGPath {
        let key = count * 100 + index
        if let cached = localPaths[key] { return cached }
        let bounds = BloomLayout.leafBounds(index, of: count)
        var shift = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        let path = BloomLayout.leafPath(index, of: count)
        let local = path.copy(using: &shift) ?? path
        localPaths[key] = local
        return local
    }
}

/// The soft clover-green glow under a lit slot.
struct SlotGlow: View {
    let index: Int
    let count: Int
    let color: Color

    var body: some View {
        let bounds = BloomLayout.leafBounds(index, of: count)
        Path(SlotView.localPath(index, count))
            .fill(color.opacity(0.55))
            .frame(width: bounds.width, height: bounds.height)
            .blur(radius: 12)
    }
}

/// The More slot's +, turning 45° into × while its tray is open, or cross-fading into ×
/// with reduce motion.
struct PlusIcon: View {
    /// 0 is +, 1 is ×.
    let turn: Double
    let fades: Bool
    let lit: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = lit ? BloomStyle.litInk(scheme) : Color.primary
        let font = Font.system(size: Motion.More.iconSize, weight: .semibold)
        ZStack {
            if fades {
                Image(systemName: "plus").font(font).opacity(1 - turn)
                Image(systemName: "xmark").font(font).opacity(turn)
            } else {
                Image(systemName: "plus").font(font)
                    .rotationEffect(.degrees(Motion.More.angle * turn))
            }
        }
        .foregroundStyle(ink)
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0), radius: 1, y: 0.5)
    }
}

/// A slot's title, upright, with a tool's small icon over it: dark on frosted glass in
/// Light, light in Dark, white on green.
struct SlotLabel: View {
    let title: String
    let symbol: String?
    let hue: Color
    let lit: Bool
    let width: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: BloomGeometry.labelIconGap) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(lit ? BloomStyle.litInk(scheme) : hue)
                    .frame(height: BloomGeometry.labelIcon.height)
            }
            Text(title)
                .font(Font(BloomStyle.leafFont(for: title, width: width)))
                .foregroundStyle(lit ? BloomStyle.litInk(scheme) : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: width)
        }
        // A faint shadow keeps the white title crisp on green, and light titles on busy glass.
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0), radius: 1, y: 0.5)
    }
}

/// The centre circle: the file's thumbnail, or a small stack with a count for many files.
struct HubView: View {
    let pictures: [NSImage]
    let count: Int
    let hasFiles: Bool
    /// The picture and count, which go first when the hub becomes the ring.
    var content = Look.still

    @Environment(\.colorScheme) private var scheme
    private typealias G = BloomGeometry

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Circle().fill(Color.white.opacity(dark ? 0.11 : 0.62))
            Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.26 : 0.95),
                                                          dark ? Color.white.opacity(0.05) : Color.black.opacity(0.07)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            Group {
                if !hasFiles || pictures.isEmpty {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.secondary)
                } else if pictures.count == 1 {
                    picture(pictures[0], side: G.pictureSide)
                } else {
                    stack
                }
            }
            .offset(y: G.pictureCenterY)
            .blur(radius: content.blur)
            .opacity(content.opacity)
            if count > 1 {
                Text(count < 1000 ? "\(count)" : "999+")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(dark ? Color.black : Color.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(dark ? Color(white: 0.92) : Color(white: 0.18)))
                    .offset(x: 28, y: G.pictureCenterY + 24)
                    .opacity(content.opacity)
            }
        }
        .frame(width: G.hubSize, height: G.hubSize)
    }

    /// Up to three cards fanned behind each other. Mixed files show their different icons.
    private var stack: some View {
        ZStack {
            ForEach(Array(pictures.prefix(3).enumerated().reversed()), id: \.offset) { index, image in
                let angle: Double = index == 0 ? 0 : (index == 1 ? -10 : 10)
                picture(image, side: 46)
                    .rotationEffect(.degrees(angle))
                    .offset(x: index == 0 ? 0 : (index == 1 ? -12 : 12), y: index == 0 ? 3 : -2)
            }
        }
    }

    private func picture(_ image: NSImage, side: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// The small capsule on the centre circle: the files' size, or the hovered format.
struct CapsuleLabel: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let measured: CGFloat = BloomStyle.textWidth(text, font: BloomStyle.capsuleFont) + 18
        let width: CGFloat = min(max(measured, 40), BloomGeometry.capsuleMaxWidth)
        let ink: Color = dark ? Color.white : Color(white: 0.12)
        let fill: Color = dark ? Color.black.opacity(0.45) : Color.white.opacity(0.9)
        let edge: Color = dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        Text(text)
            .font(Font(BloomStyle.capsuleFont))
            .foregroundStyle(ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 8)
            .frame(width: width, height: BloomGeometry.capsuleHeight)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(edge, lineWidth: 0.75))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

/// A small glass capsule with one option. The default option carries a dot; a lit chip
/// is solid clover green.
struct ChipView: View {
    let title: String
    let isDefault: Bool
    let isLit: Bool
    var isFlash = false
    let isFocused: Bool
    let hue: Color
    var look = Look.still
    var pop: CGFloat = 1
    /// A press's light, in the chip's own coordinates.
    var press: PressLight? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if isLit { Capsule().fill(isFlash ? Color.white : BloomStyle.litFill(scheme)) }
            if let press {
                GeometryReader { geo in PressLightView(shape: Capsule(), light: press, size: geo.size) }
            }
            HStack(spacing: 4) {
                if isDefault {
                    Circle().fill(isLit ? BloomStyle.litInk(scheme) : hue).frame(width: 5, height: 5)
                }
                Text(title)
                    .font(Font(BloomStyle.chipFont))
                    .foregroundStyle(isLit ? BloomStyle.litInk(scheme) : Color.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .blur(radius: look.blur)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBehind(cornerRadius: BloomGeometry.chipHeight / 2)
        .overlay {
            if isFocused {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
            }
        }
        // Glass takes scale and opacity; only its content blurs.
        .scaleEffect(look.scale * pop)
        .offset(look.offset)
        .opacity(look.opacity)
    }
}

/// With reduce motion, the ring the chip picks up: the chip's own ring on a small glass circle.
struct RingButton: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side = Motion.Drop.ringSide
        ChipRing(progress: 0, diameter: side)
            .background(Circle().fill(Color.white.opacity(scheme == .dark ? 0.11 : 0.62)))
            .glassBehind(cornerRadius: side / 2)
    }
}

/// The ring of light that radiates out from the pointer when the clover opens.
struct LightRing: View {
    let radius: CGFloat
    let width: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.5), lineWidth: width * 3).blur(radius: 4)
            Circle().stroke(Color.white.opacity(0.9), lineWidth: width)
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

// MARK: - The wave

/// One thin wave of light passing through the glass: a white core with a soft glow around
/// it, tinted cyan to violet to pink, and a faint light just behind it. In Light a faint
/// darker edge keeps it from being white on white. It stays on the disc, fading out as it
/// nears the rim. Drawn with strokes and gradients only: no blur, no copies of the slots.
struct WaveFront: View {
    /// The chosen leaf's middle, in the scene.
    let origin: CGPoint
    let wave: Wave
    let side: CGFloat

    @Environment(\.colorScheme) private var scheme

    private static let tint: [Color] = [
        Color(red: 0.40, green: 0.88, blue: 1.00), Color(red: 0.62, green: 0.48, blue: 1.00),
        Color(red: 1.00, green: 0.52, blue: 0.80), Color(red: 0.62, green: 0.48, blue: 1.00),
        Color(red: 0.40, green: 0.88, blue: 1.00),
    ]

    var body: some View {
        let d = Motion.Drop.self
        let dark = scheme == .dark
        let r = max(wave.radius, 0.5), k = wave.strength
        let g = d.waveGlow / 2
        let end = r + g + 1
        let unit = UnitPoint(x: origin.x / side, y: origin.y / side)
        func at(_ x: CGFloat) -> CGFloat { min(max(x / end, 0), 1) }
        let rim = BloomGeometry.discRadius
        return ZStack {
            // A very faint light just behind the front.
            Rectangle().fill(RadialGradient(stops: [
                Gradient.Stop(color: Color.white.opacity(0), location: at(r - d.waveTrail)),
                Gradient.Stop(color: Color.white.opacity(d.waveTrailLight * k), location: at(r - 2)),
                Gradient.Stop(color: Color.white.opacity(0), location: at(r)),
                Gradient.Stop(color: Color.white.opacity(0), location: 1),
            ], center: unit, startRadius: 0, endRadius: end))
            // The soft, faintly iridescent glow around the front.
            Circle()
                .stroke(AngularGradient(colors: WaveFront.tint, center: .center, angle: .degrees(Double(r) * 0.5)),
                        lineWidth: d.waveGlow)
                .frame(width: r * 2, height: r * 2)
                .position(origin)
                .mask(Rectangle().fill(RadialGradient(stops: [
                    Gradient.Stop(color: .clear, location: at(r - g)),
                    Gradient.Stop(color: .black, location: at(r)),
                    Gradient.Stop(color: .clear, location: at(r + g)),
                    Gradient.Stop(color: .clear, location: 1),
                ], center: unit, startRadius: 0, endRadius: end)))
                .opacity((dark ? 0.5 : 0.7) * k)
            if !dark {
                Circle()
                    .stroke(Color.black.opacity(0.16 * k), lineWidth: 1)
                    .frame(width: (r + 2.2) * 2, height: (r + 2.2) * 2)
                    .position(origin)
            }
            // The bright core.
            Circle()
                .stroke(Color.white.opacity(0.95 * k), lineWidth: d.waveCore)
                .frame(width: r * 2, height: r * 2)
                .position(origin)
        }
        .frame(width: side, height: side)
        // On the disc only, fading out as it nears the rim.
        .mask(Rectangle().fill(RadialGradient(stops: [
            Gradient.Stop(color: .black, location: 0),
            Gradient.Stop(color: .black, location: (rim - d.waveRimFade) / rim),
            Gradient.Stop(color: .clear, location: (rim - 4) / rim),
            Gradient.Stop(color: .clear, location: 1),
        ], center: .center, startRadius: 0, endRadius: rim)))
        .allowsHitTesting(false)
    }
}

// MARK: - The press

/// A press's light on a shape, in the shape's own coordinates: where it comes from, how
/// far it reaches now, and how bright it is.
struct PressLight: Equatable {
    var point: CGPoint
    var radius: CGFloat
    var intensity: Double

    /// The light of a press on a shape of `size`, grown from `point` towards its far corner.
    static func filling(_ size: CGSize, from point: CGPoint, _ light: (intensity: Double, grow: Double)) -> PressLight {
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        let far = corners.map { hypot($0.x - point.x, $0.y - point.y) }.max() ?? 1
        return PressLight(point: point, radius: far * CGFloat(light.grow), intensity: light.intensity)
    }

    /// The light and scale of a press on `target`, drawn in `frame`, if it is the one pressed.
    static func on(_ target: BloomEvents.Press.Target, frame: CGRect, _ e: BloomEvents, now: TimeInterval) -> (light: PressLight?, scale: CGFloat) {
        guard let p = e.press, p.target == target else { return (nil, 1) }
        let scale = Motion.pressScale(p, peak: Motion.Press.chipPeak, reduce: e.reduce, now: now)
        guard let light = Motion.pressLight(p, reduce: e.reduce, now: now) else { return (nil, scale) }
        let local = CGPoint(x: p.point.x - frame.minX, y: p.point.y - frame.minY)
        return (filling(frame.size, from: local, light), scale)
    }
}

/// Glass lighting up where it is pressed: a soft radial light growing from the press
/// point, a soft glow along the inside of the edge and a specular rim, brightest on top.
/// In Light a touch of shade under it lets the lit part stand out. Drawn on the shape and
/// clipped to it, with no glass of its own.
struct PressLightView<S: Shape>: View {
    let shape: S
    let light: PressLight
    let size: CGSize

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Motion.Press.self
        let dark = scheme == .dark
        let i = light.intensity
        let core = (dark ? p.lightDark : p.lightLight) * i
        let unit = UnitPoint(x: light.point.x / max(size.width, 1), y: light.point.y / max(size.height, 1))
        return ZStack {
            if !dark { shape.fill(Color.black.opacity(p.shadeLight * i)) }
            Rectangle()
                .fill(RadialGradient(stops: [
                    Gradient.Stop(color: Color.white.opacity(core), location: 0),
                    Gradient.Stop(color: Color.white.opacity(core * 0.45), location: p.lightCore),
                    Gradient.Stop(color: Color.white.opacity(0), location: 1),
                ], center: unit, startRadius: 0, endRadius: max(light.radius, 1)))
                .blendMode(dark ? .plusLighter : .normal)
            shape.stroke(Color.white.opacity((dark ? p.edgeDark : p.edgeLight) * i), lineWidth: 8)
                .blur(radius: 5)
            shape.stroke(LinearGradient(colors: [Color.white.opacity(p.rim * i), Color.white.opacity(0.2 * i)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// The faint spill of a press's light on a neighbour's near edge: brightest at the edge
/// nearest the press point (`light.radius` away), gone `Motion.Press.spillReach` further in.
struct SpillLightView<S: Shape>: View {
    let shape: S
    let light: PressLight
    let size: CGSize

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let end = light.radius + Motion.Press.spillReach
        let a = Motion.Press.spill * light.intensity * (dark ? 1 : 1.6)
        let unit = UnitPoint(x: light.point.x / max(size.width, 1), y: light.point.y / max(size.height, 1))
        return Rectangle()
            .fill(RadialGradient(stops: [
                Gradient.Stop(color: Color.white.opacity(a), location: 0),
                Gradient.Stop(color: Color.white.opacity(a), location: light.radius / end),
                Gradient.Stop(color: Color.white.opacity(0), location: 1),
            ], center: unit, startRadius: 0, endRadius: end))
            .blendMode(dark ? .plusLighter : .normal)
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .allowsHitTesting(false)
    }
}

// MARK: - More tray

/// The More tray: a glass panel of pills, one per target that isn't on a slot, with the
/// hovered pill's chips just under it. Drawn in its own window, `TrayLayout.windowMargin`
/// in from the window's edges.
struct TrayView: View {
    @ObservedObject var model: BloomModel
    var time: TimeInterval? = nil

    var body: some View {
        if let time {
            TrayScene(model: model, now: time)
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: !model.animating)) { context in
                TrayScene(model: model, now: max(context.date.timeIntervalSinceReferenceDate,
                                                 Date().timeIntervalSinceReferenceDate))
            }
        }
    }
}

struct TrayScene: View {
    @ObservedObject var model: BloomModel
    let now: TimeInterval

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let e = model.events
        let m = TrayLayout.windowMargin
        let size = model.traySize
        let frames = model.pillFrames
        let tray = Motion.tray(e, now: now)
        LiquidGlassGroup(spacing: 4) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(model.arrangement.more.enumerated()), id: \.offset) { index, target in
                    if frames.indices.contains(index) {
                        let lit = e.litPill == index
                        let chosen = e.drop?.pill == index && e.drop?.chip == nil
                        let press = PressLight.on(.pill(index), frame: frames[index], e, now: now)
                        PillView(title: target.title, symbol: BloomStyle.symbol(for: target),
                                 hue: BloomStyle.hue(target.format.family, scheme),
                                 isLit: lit || chosen,
                                 isFlash: false,
                                 isFocused: model.focusedPill == index && model.focusChip == nil && model.phase == .open,
                                 press: press.light)
                            .frame(width: frames[index].width, height: frames[index].height)
                            .scaleEffect((lit ? Motion.litPop(at: e.litPillAt, e, now: now) : 1) * press.scale)
                            .look(Motion.pill(index, e, now: now))
                            .offset(x: frames[index].minX, y: frames[index].minY)
                    }
                }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .glassBehind(cornerRadius: TrayLayout.cornerRadius,
                             tint: BloomStyle.glassTint(model.tint, scheme), bright: true)
                if let open = e.pillChips, let target = model.pillTarget(open) {
                    let chips = model.pillChipFrames(for: open)
                    ForEach(Array(zip(target.options.indices, chips)), id: \.0) { index, frame in
                        let rank = e.pillChipRank.indices.contains(index) ? e.pillChipRank[index] : index
                        let lit = e.litChip == index
                        let chosen = e.drop?.pill == open && e.drop?.chip == index
                        let press = PressLight.on(.pillChip(pill: open, index: index), frame: frame, e, now: now)
                        ChipView(title: target.options[index].title,
                                 isDefault: target.options[index].id == target.defaultOption?.id,
                                 isLit: lit || chosen,
                                 isFlash: false,
                                 isFocused: model.usingKeyboard && model.focusChip == index && model.phase == .open,
                                 hue: BloomStyle.hue(target.format.family, scheme),
                                 look: Motion.chipIn(rank: rank, since: e.pillChipsAt, e, now: now),
                                 pop: (lit ? Motion.litPop(at: e.litChipAt, e, now: now) : 1) * press.scale,
                                 press: press.light)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
            .frame(width: size.width, height: size.height + TrayLayout.overhang, alignment: .topLeading)
        }
        .scaleEffect(tray.scale, anchor: UnitPoint(x: model.trayAnchor.x, y: model.trayAnchor.y))
        .opacity(tray.opacity)
        .padding(m)
        .allowsHitTesting(false)
    }
}

/// One target in the More tray: an icon in its family's hue and its title. Lit, it is
/// solid clover green with white text.
struct PillView: View {
    let title: String
    let symbol: String
    let hue: Color
    let isLit: Bool
    var isFlash = false
    let isFocused: Bool
    /// A press's light, in the pill's own coordinates.
    var press: PressLight? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if isFlash {
                Capsule().fill(Color.white)
            } else if isLit {
                Capsule().fill(BloomStyle.litFill(scheme))
            } else {
                Capsule().fill(dark ? Color.white.opacity(0.09) : Color.white.opacity(0.55))
                Capsule().strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07), lineWidth: 0.75)
            }
            if let press {
                GeometryReader { geo in PressLightView(shape: Capsule(), light: press, size: geo.size) }
            }
            HStack(spacing: TrayLayout.iconGap) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isLit ? BloomStyle.litInk(scheme) : hue)
                    .frame(width: TrayLayout.iconWidth)
                Text(title)
                    .font(Font(BloomStyle.pillFont))
                    .foregroundStyle(isLit ? BloomStyle.litInk(scheme) : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, TrayLayout.pillPadding)
            .opacity(isFlash ? 0 : 1)
            if isFocused {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
            }
        }
    }
}
