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
            ForEach(Array(model.leaves.enumerated()), id: \.offset) { index, leaf in
                if index != carried { slot(index, leaf, count: count, center: center, e) }
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
            HubView(pictures: model.pictures, count: model.files.count, hasFiles: model.hasFiles)
                .look(Motion.hub(e, now: now))
                .position(center)
            if !model.hint.isEmpty {
                CapsuleLabel(text: model.hint)
                    .look(Motion.capsule(e, now: now))
                    .position(x: center.x, y: center.y + G.capsuleCenterY)
            }
            if let carried, carried < model.leaves.count {
                slot(carried, model.leaves[carried], count: count, center: center, e)
            }
            if let ring = Motion.carryRing(e, now: now) {
                CarryRing()
                    .look(ring)
                    .position(center)
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

    private func disc(_ e: BloomEvents) -> some View {
        let r = G.discRadius
        let look = Motion.disc(e, now: now)
        return ZStack {
            LiquidGlass(cornerRadius: r, tint: model.tinted ? BloomStyle.discTint(scheme) : nil, bright: true)
            RimView()
        }
        .frame(width: r * 2, height: r * 2)
        .scaleEffect(look.scale)
        .opacity(look.opacity)
        .position(x: side / 2, y: side / 2)
    }

    @ViewBuilder
    private func slot(_ index: Int, _ leaf: BloomModel.Leaf, count: Int, center: CGPoint, _ e: BloomEvents) -> some View {
        let middle = BloomLayout.leafCenter(index, of: count)
        let state = Motion.slot(index, count: count, center: middle, e, now: now)
        SlotView(index: index, count: count, title: title(of: leaf), symbol: symbol(of: leaf), hue: hue(of: index),
                 fill: state.fill, focused: model.focusedLeaf == index && model.focusChip == nil && model.phase == .open)
            .look(state.look)
            .position(offset(middle, center))
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
                ChipView(title: target.options[index].title,
                         isDefault: target.options[index].id == target.defaultOption?.id,
                         isLit: lit || chosen,
                         isFlash: chosen && now - (e.drop?.at ?? 0) < Motion.Drop.flash,
                         isFocused: model.usingKeyboard && model.focusChip == index && model.phase == .open,
                         hue: BloomStyle.hue(target.format.family, scheme),
                         look: leaving ?? born,
                         pop: lit ? Motion.litPop(at: e.litChipAt, e, now: now) : 1)
                    .frame(width: frame.width, height: frame.height)
                    .position(offset(frame.mid, center))
            }
        }
        if let closing = e.closingLeaf, closing != e.chipsLeaf, let target = model.target(at: closing) {
            let frames = model.chipFrames(for: closing)
            let rim = BloomLayout.radial(closing, of: count)
            ForEach(Array(zip(target.options.indices, frames)), id: \.0) { index, frame in
                let toward = CGVector(dx: rim.dx * G.discRadius - frame.midX, dy: rim.dy * G.discRadius - frame.midY)
                if let look = leaving ?? Motion.chipOut(towards: toward, e, now: now) {
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

    private var rippleColor: Color {
        scheme == .dark ? Color.white : BloomStyle.cloverGlow(scheme)
    }

    private func title(of leaf: BloomModel.Leaf) -> String {
        switch leaf {
        case .target(let target): target.title
        case .more: "More"
        }
    }

    /// Tools and More carry a small icon; formats are a title alone.
    private func symbol(of leaf: BloomModel.Leaf) -> String? {
        switch leaf {
        case .target(let target): BloomStyle.isTool(target) ? BloomStyle.symbol(for: target) : nil
        case .more: "ellipsis"
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
    let focused: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let bounds = BloomLayout.leafBounds(index, of: count)
        let local = SlotView.localPath(index, count)
        let shape = Path(local)
        let label = BloomLayout.labelBox(index, of: count, icon: symbol != nil)
        let dark = scheme == .dark
        let lit = fill != .frosted
        ZStack(alignment: .topLeading) {
            switch fill {
            case .frosted: shape.fill(Color.white.opacity(dark ? 0.11 : 0.62))
            case .lit: shape.fill(BloomStyle.cloverFill)
            case .flash: shape.fill(Color.white)
            }
            shape.stroke(rim(lit: lit, dark: dark), lineWidth: 0.75)
            Path { p in
                for (a, b) in BloomLayout.midrib(index, of: count, icon: symbol != nil) {
                    p.move(to: CGPoint(x: a.x - bounds.minX, y: a.y - bounds.minY))
                    p.addLine(to: CGPoint(x: b.x - bounds.minX, y: b.y - bounds.minY))
                }
            }
            .stroke(lit ? Color.white.opacity(0.35) : (dark ? Color.white.opacity(0.16) : Color.black.opacity(0.07)),
                    style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
            if fill != .flash {
                SlotLabel(title: title, symbol: symbol, hue: hue, lit: lit, width: label.width)
                    .frame(width: label.width, height: label.height)
                    .offset(x: label.minX - bounds.minX, y: label.minY - bounds.minY)
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
                    .foregroundStyle(lit ? Color.white : hue)
                    .frame(height: BloomGeometry.labelIcon.height)
            }
            Text(title)
                .font(Font(BloomStyle.leafFont(for: title, width: width)))
                .foregroundStyle(lit ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: width)
        }
        // A faint shadow keeps the white title crisp on green, and light titles on busy glass.
        .shadow(color: .black.opacity(lit ? 0.22 : (scheme == .dark ? 0.25 : 0)), radius: 1, y: 0.5)
    }
}

/// The centre circle: the file's thumbnail, or a small stack with a count for many files.
struct HubView: View {
    let pictures: [NSImage]
    let count: Int
    let hasFiles: Bool

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
            if count > 1 {
                Text(count < 1000 ? "\(count)" : "999+")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(dark ? Color.black : Color.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(dark ? Color(white: 0.92) : Color(white: 0.18)))
                    .offset(x: 28, y: G.pictureCenterY + 24)
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

    var body: some View {
        ZStack {
            if isLit { Capsule().fill(isFlash ? AnyShapeStyle(Color.white) : AnyShapeStyle(BloomStyle.cloverFill)) }
            HStack(spacing: 4) {
                if isDefault {
                    Circle().fill(isLit ? Color.white : hue).frame(width: 5, height: 5)
                }
                Text(title)
                    .font(Font(BloomStyle.chipFont))
                    .foregroundStyle(isLit ? Color.white : Color.primary)
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

/// The progress ring the chosen slot becomes at the hub: a clover-green disc with a white
/// ring track. The result chip starts as this same ring at `BloomAnchor`.
struct CarryRing: View {
    var body: some View {
        let d = Motion.Drop.self
        ZStack {
            Circle().fill(BloomStyle.cloverFill)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle()
                .stroke(Color.white.opacity(d.trackOpacity), lineWidth: d.ringWidth)
                .frame(width: d.ringSide, height: d.ringSide)
        }
        .frame(width: d.carrySide, height: d.carrySide)
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
                        PillView(title: target.title, symbol: BloomStyle.symbol(for: target),
                                 hue: BloomStyle.hue(target.format.family, scheme),
                                 isLit: lit || chosen,
                                 isFlash: chosen && now - (e.drop?.at ?? 0) < Motion.Drop.flash,
                                 isFocused: model.focusedPill == index && model.focusChip == nil && model.phase == .open)
                            .frame(width: frames[index].width, height: frames[index].height)
                            .scaleEffect(lit ? Motion.litPop(at: e.litPillAt, e, now: now) : 1)
                            .look(Motion.pill(index, e, now: now))
                            .offset(x: frames[index].minX, y: frames[index].minY)
                    }
                }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .glassBehind(cornerRadius: TrayLayout.cornerRadius,
                             tint: model.tinted ? BloomStyle.discTint(scheme) : nil, bright: true)
                if let open = e.pillChips, let target = model.pillTarget(open) {
                    let chips = model.pillChipFrames(for: open)
                    ForEach(Array(zip(target.options.indices, chips)), id: \.0) { index, frame in
                        let rank = e.pillChipRank.indices.contains(index) ? e.pillChipRank[index] : index
                        let lit = e.litChip == index
                        let chosen = e.drop?.pill == open && e.drop?.chip == index
                        ChipView(title: target.options[index].title,
                                 isDefault: target.options[index].id == target.defaultOption?.id,
                                 isLit: lit || chosen,
                                 isFlash: chosen && now - (e.drop?.at ?? 0) < Motion.Drop.flash,
                                 isFocused: model.usingKeyboard && model.focusChip == index && model.phase == .open,
                                 hue: BloomStyle.hue(target.format.family, scheme),
                                 look: Motion.chipIn(rank: rank, since: e.pillChipsAt, e, now: now),
                                 pop: lit ? Motion.litPop(at: e.litChipAt, e, now: now) : 1)
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if isFlash {
                Capsule().fill(Color.white)
            } else if isLit {
                Capsule().fill(BloomStyle.cloverFill)
            } else {
                Capsule().fill(dark ? Color.white.opacity(0.09) : Color.white.opacity(0.55))
                Capsule().strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07), lineWidth: 0.75)
            }
            HStack(spacing: TrayLayout.iconGap) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isLit ? Color.white : hue)
                    .frame(width: TrayLayout.iconWidth)
                Text(title)
                    .font(Font(BloomStyle.pillFont))
                    .foregroundStyle(isLit ? Color.white : Color.primary)
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
