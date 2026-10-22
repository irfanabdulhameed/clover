import CoreGraphics
import Foundation

/// Every timing, distance and easing of the clover's motion, in seconds and points, and the
/// choreography that turns them into a look at a moment in time. Tune here.
///
/// Irfan's direction (21 Oct 2026): the clover is plain until a leaf is chosen. Opening,
/// hover, chips, the tray and cancel are instant; choosing a leaf plays the AirDrop wave
/// (`Drop`). The earlier motion for the plain moments is kept behind the `animated` and
/// `...Enabled` flags, so any part can come back.
///
/// House rules for what moves: no bounce or overshoot; fast attack and a long soft
/// slow-down (about 75 % of the way in the first 47 % of the time); blur as a material; a
/// state change is a one-frame flip plus a small pop; exits are faster than entrances.
enum Motion {
    // MARK: Open

    enum Open {
        /// Off: no unfolding. The window fades in instead (`fadeIn`) while the slots and
        /// hub settle from `settleFrom` to full size, all as one piece with their labels
        /// (Irfan, 22 Oct 2026: the instant open felt abrupt).
        static let animated = false
        static let fadeIn: TimeInterval = 0.18
        static let settle: TimeInterval = 0.20
        static let settleFrom: CGFloat = 0.97
        /// The glass disc grows from the pointer.
        static let disc: TimeInterval = 0.30
        static let discFrom: CGFloat = 0.85
        /// Each slot unfolds from the centre circle, clockwise from 12 o'clock.
        static let slot: TimeInterval = 0.30
        static let slotStagger: TimeInterval = 0.014
        /// A slot starts this far in (scale about the disc's centre) and this blurred.
        static let slotFrom: CGFloat = 0.55
        static let slotBlur: CGFloat = 12
        /// The centre circle and its picture are born slightly large and blurred.
        static let hub: TimeInterval = 0.22
        static let hubFrom: CGFloat = 1.10
        static let hubBlur: CGFloat = 10
        /// The size capsule follows a beat later.
        static let capsuleDelay: TimeInterval = 0.07
        static let capsule: TimeInterval = 0.20
        /// The ring of light that radiates from the pointer. Off for now: Irfan wants a
        /// different AirDrop effect, to be designed in the animation pass.
        static let ringEnabled = false
        static let ring: TimeInterval = 0.50
        static let ringFrom: CGFloat = 40
        static let ringTo: CGFloat = 250
        static let ringPeak: Double = 0.55
    }

    // MARK: Hover

    enum Hover {
        /// The pointer rests this long before a slot lights, so a sweep doesn't flicker.
        static let delay: TimeInterval = 0.08
        /// Off: the lit slot flips to green with no pop, and has no glow or breathing.
        static let popEnabled = false
        static let glowEnabled = false
        /// The other slots dim smoothly.
        static let dimAnimated = true
        /// Hover fades in and out instead of switching (Irfan, 21 Oct 2026: "smoothen it").
        /// The bright fill eases in over `fadeIn`, out over `fadeOut`, and the slot lifts.
        static let smooth = true
        static let fadeIn: TimeInterval = 0.16
        static let fadeOut: TimeInterval = 0.12
        static let lift: CGFloat = 1.03
        /// The lit flip pops to `peak`, then settles at `rest`.
        static let popRise: TimeInterval = 0.03
        static let popSettle: TimeInterval = 0.09
        static let peak: CGFloat = 1.08
        static let rest: CGFloat = 1.04
        /// A slot going dark returns to its size, faster than it popped.
        static let leave: TimeInterval = 0.07
        /// One ripple of light leaves the lit slot's outline. Off for now, like the ring.
        static let rippleEnabled = false
        static let ripple: TimeInterval = 0.45
        static let rippleGrow: CGFloat = 0.16
        static let rippleOpacity: Double = 0.75
        /// The glow under the lit slot breathes.
        static let breath: TimeInterval = 2.4
        static let breathAmount: CGFloat = 0.03
        static let glowIn: TimeInterval = 0.16
        /// The other slots dim and soften.
        static let dim: TimeInterval = 0.16
        static let undim: TimeInterval = 0.12
        static let dimOpacity: Double = 0.85
        /// No blur on the dimmed slots (it was 1.5, then 0.8).
        static let dimBlur: CGFloat = 0
    }

    // MARK: Option chips

    enum Chips {
        /// The pointer rests on a slot this long before its chips open: after the slot has lit.
        static let delay: TimeInterval = 0.12
        /// Off: chips appear and go at once, and a lit chip has no pop.
        static let animated = false
        static let settle: TimeInterval = 0.13
        static let stagger: TimeInterval = 0.02
        static let bornScale: CGFloat = 1.10
        static let bornBlur: CGFloat = 20
        /// Leaving, they shrink back into their slot.
        static let leave: TimeInterval = 0.11
        static let leaveScale: CGFloat = 0.5
        static let leaveBlur: CGFloat = 8
        /// A lit chip or pill pops like a slot, and rests at its size.
        static let litPop: TimeInterval = 0.09
        static let litPeak: CGFloat = 1.08
    }

    // MARK: More tray

    enum Tray {
        /// Resting on More this long, during a drag, opens the tray.
        static let delay: TimeInterval = 0.30
        /// Off: the tray and its pills appear and go at once.
        static let animated = false
        /// It grows out of the More slot, born blurred and slightly small.
        static let settle: TimeInterval = 0.26
        static let bornScale: CGFloat = 0.88
        static let bornBlur: CGFloat = 16
        static let pillDelay: TimeInterval = 0.04
        static let pill: TimeInterval = 0.16
        static let pillStagger: TimeInterval = 0.02
        static let pillBornScale: CGFloat = 1.10
        static let pillBornBlur: CGFloat = 14
        static let close: TimeInterval = 0.12
    }

    // MARK: Press: the glass button

    /// Pressing a leaf, chip or pill reacts like a macOS 26 glass button: it swells with a
    /// soft spring and lights up from the press point; letting go springs back with a
    /// slight jelly settle while the light fades. Irfan asked for the glass button's feel
    /// here (22 Oct 2026), so the press, and only the press, may bounce a little.
    enum Press {
        /// The swell, on top of the hover's lift: a leaf reaches about 1.09 in all; a chip
        /// or pill, which has no hover lift, 1.06.
        static let leafPeak: CGFloat = 1.06
        static let chipPeak: CGFloat = 1.06
        /// The press spring: a little give, a small bounce.
        static let damping: Double = 0.72
        static let response: TimeInterval = 0.30
        /// Letting go: a jelly settle, about 0.98, then 1, settled within `releaseSettle`.
        static let releaseDamping: Double = 0.34
        static let releaseResponse: TimeInterval = 0.26
        static let releaseSettle: TimeInterval = 0.45
        /// The light comes up at the press point and grows to fill the shape, then rests a
        /// little lower while held; letting go, it fades.
        static let lightRise: TimeInterval = 0.06
        static let lightGrow: TimeInterval = 0.25
        static let lightHeld: Double = 0.8
        static let lightEase: TimeInterval = 0.5
        static let lightFade: TimeInterval = 0.30
        /// Its strength: added light in Dark; in Light, white over a touch of shade, so the
        /// lit part stands out from the rest of the leaf.
        static let lightDark: Double = 0.34
        static let lightLight: Double = 0.95
        static let shadeLight: Double = 0.12
        /// How far the light's bright middle reaches before it thins out, as a share of its reach.
        static let lightCore: CGFloat = 0.35
        /// The soft glow along the inside of the edge, in Dark and in Light.
        static let edgeDark: Double = 0.22
        static let edgeLight: Double = 0.6
        /// The specular rim, brightest along the top edge.
        static let rim: Double = 0.95
        /// The faint spill on the near edges of the neighbouring leaves.
        static let spill: Double = 0.2
        static let spillReach: CGFloat = 44
        /// A drop or a key: a quick press, then the release, as the start of the wave.
        static let quickHold: TimeInterval = 0.12
    }

    // MARK: Drop: light through the glass

    /// Choosing a leaf, about 0.55 s: the leaf brightens and lifts, one thin wave of light
    /// passes through the glass from it, each leaf the wave reaches is nudged like water,
    /// then the others fold to the hub one by one and the hub becomes the progress ring.
    enum Drop {
        /// 0 to 90 ms: the chosen leaf at full hover brightness, with a soft inner glow,
        /// lifts from the hover's 103 % to this.
        static let choose: TimeInterval = 0.09
        static let chooseLift: CGFloat = 1.07
        /// 20 to 380 ms: one thin wave of light from the chosen leaf's middle across the
        /// disc, fading as it nears the rim.
        /// Off (Irfan, 22 Oct 2026: "remove the outer ripple"): no ring of light and no
        /// nudges. The press, then the gather to the ring, carry the choice.
        static let waveEnabled = false
        static let waveStart: TimeInterval = 0.02
        static let wave: TimeInterval = 0.36
        /// Its white core, the soft glow around it, and the faint light behind it.
        static let waveCore: CGFloat = 2.25
        static let waveGlow: CGFloat = 12
        static let waveTrail: CGFloat = 40
        static let waveTrailLight: Double = 0.07
        /// It fades out over this distance inside the rim, and never shows past it.
        static let waveRimFade: CGFloat = 40
        /// When the front reaches a leaf's middle, the leaf is nudged outward and back.
        static let nudge: TimeInterval = 0.18
        static let nudgeRise: Double = 0.3
        static let nudgeShift: CGFloat = 3.5
        static let nudgeScale: CGFloat = 1.03
        /// The hub, less.
        static let hubNudgeShift: CGFloat = 2
        static let hubNudgeScale: CGFloat = 1.015
        /// 340 to 540 ms: the others fold to the hub one by one, the farthest last. They
        /// fold with a fast attack and fade quickly, so they are gone before the disc's glass
        /// draws in under them.
        static let gatherAt: TimeInterval = 0.34
        static let gatherStagger: TimeInterval = 0.05
        static let fold: TimeInterval = 0.15
        static let foldTo: CGFloat = 0.5
        static let foldBlur: CGFloat = 7
        /// The option chips go first, quickly.
        static let chipsFold: TimeInterval = 0.12
        /// The disc's glass contracts to just under the ring, once the leaves are going.
        static let discAt: TimeInterval = 0.44
        static let disc: TimeInterval = 0.11
        static let discTo: CGFloat = 62
        /// The hub's picture and capsule go, and the hub shrinks to the ring's size.
        static let hubContentAt: TimeInterval = 0.34
        static let hubContent: TimeInterval = 0.10
        static let hubContentBlur: CGFloat = 6
        static let hubShrinkAt: TimeInterval = 0.42
        static let hubShrink: TimeInterval = 0.11
        /// The chosen leaf glides into the hub, shrinking, solid all the way, and flips into
        /// the ring in one frame as it lands. Its inner glow goes as it sets off.
        static let glideStart: TimeInterval = 0.36
        static let glide: TimeInterval = 0.13
        static let glideTo: CGFloat = 0.35
        static let glowOut: TimeInterval = 0.08
        /// The ring appears on the hub's glass with a small pop, and is still by the handoff.
        static let ringAt: TimeInterval = 0.49
        static let ringPop: TimeInterval = 0.05
        static let ringPopPeak: CGFloat = 1.06
        /// The result chip takes over the ring at this moment, at `BloomAnchor`; the panel
        /// hides. `ChipMotion.ringAppearDelay` is the same moment.
        static let handoff: TimeInterval = 0.55
        /// The ring is the chip's own (`ChipRing`), at its size.
        static var ringSide: CGFloat { ChipMotion.dropRingDiameter }
        /// A tray choice: the tray stays a moment, then goes.
        static let trayHold: TimeInterval = 0.05
    }

    // MARK: Cancel

    enum Cancel {
        /// Off: the clover hides at once.
        static let animated = false
        /// Everything folds into the hub, which shrinks away blurred.
        static let duration: TimeInterval = 0.16
        static let shrinkTo: CGFloat = 0.55
        static let blur: CGFloat = 14
    }

    /// Reduce motion: nothing travels, pops, ripples or blurs; things fade in place.
    static let fade: TimeInterval = 0.15

    // MARK: Easing

    /// Fast attack and a long, soft slow-down with no overshoot: an exponential ease-out
    /// normalised to land exactly at 1. With 300 ms it is 75 % there at 140 ms.
    static func settle(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let k = 2.5
        return (1 - exp(-k * t)) / (1 - exp(-k))
    }

    /// Exits: leave briskly and keep accelerating away.
    static func exit(_ t: Double) -> Double {
        let t = clamp(t)
        return t * (0.35 + 0.65 * t)
    }

    static func clamp(_ x: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
        min(max(x, low), high)
    }

    /// How far `now` is through `duration` from `start`: 0 before, 1 after. A start of
    /// minus infinity means long ago.
    static func phase(_ now: TimeInterval, _ start: TimeInterval, _ duration: TimeInterval) -> Double {
        guard start.isFinite else { return start > 0 ? 0 : 1 }
        guard duration > 0 else { return now >= start ? 1 : 0 }
        return clamp((now - start) / duration)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}

// MARK: - What happened, and when

/// The clover's motion events, as times on `Date`'s reference clock. The view turns them
/// into a look for any moment, so a frame can be drawn for any time.
struct BloomEvents: Equatable {
    struct Ripple: Equatable {
        let slot: Int
        let at: TimeInterval
    }

    struct Drop: Equatable {
        let at: TimeInterval
        /// The slot that carries the choice to the hub: the chosen slot, a chip's slot, or More.
        let slot: Int
        /// A chosen chip, on that slot or on a pill.
        let chip: Int?
        /// A chosen pill in the More tray.
        let pill: Int?
    }

    var reduce = false
    /// The disc started to grow.
    var openedAt = -Double.infinity
    /// The slots started to unfold: when the files arrived.
    var slotsAt = -Double.infinity
    /// The lit slot, since when, and the slot that went dark last.
    var lit: Int?
    var litAt = -Double.infinity
    var unlit: Int?
    var unlitAt = -Double.infinity
    /// Any slot has been lit since, or none since.
    var dimAt = -Double.infinity
    var undimAt = -Double.infinity
    var ripples: [Ripple] = []
    /// Chips showing beyond a slot, since when, and the order they are born in.
    var chipsLeaf: Int?
    var chipsAt = -Double.infinity
    var chipRank: [Int] = []
    /// Chips shrinking back into a slot.
    var closingLeaf: Int?
    var closingAt = -Double.infinity
    var closingRank: [Int] = []
    var litChip: Int?
    var litChipAt = -Double.infinity
    /// Chips under a pill in the More tray.
    var pillChips: Int?
    var pillChipsAt = -Double.infinity
    var pillChipRank: [Int] = []
    /// The More tray.
    var trayAt = -Double.infinity
    var trayClosingAt: TimeInterval?
    var litPill: Int?
    var litPillAt = -Double.infinity
    var drop: Drop?
    var cancelAt: TimeInterval?
    /// The leaf, chip or pill being pressed, or last pressed.
    var press: Press?

    /// A press: what, where and when, and when it let go.
    struct Press: Equatable {
        enum Target: Equatable {
            case leaf(Int)
            case chip(leaf: Int, index: Int)
            case pill(Int)
            case pillChip(pill: Int, index: Int)
        }

        var target: Target
        /// Where it was pressed: clover coordinates for leaves and chips, tray coordinates
        /// for pills and their chips.
        var point: CGPoint
        var at: TimeInterval
        var releasedAt: TimeInterval?
        /// A drop or a key: it lets go by itself after `Motion.Press.quickHold`.
        var quick = false
        /// It let go over its own target: a choice.
        var chosen = false

        /// When it lets go, once that is known.
        var endsAt: TimeInterval? { releasedAt ?? (quick ? at + Motion.Press.quickHold : nil) }
    }
}

// MARK: - Looks

/// How one element looks at a moment: applied as scale, offset, blur and opacity.
struct Look: Equatable {
    var scale: CGFloat = 1
    var offset = CGSize.zero
    var blur: CGFloat = 0
    var opacity: Double = 1

    static let still = Look()
    static let hidden = Look(opacity: 0)
}

/// A slot's fill at a moment.
enum SlotFill: Equatable {
    case frosted
    case lit
    case flash
}


/// The wave of light at a moment: its radius from the chosen slot's middle, the band where
/// the slots bend, how strong it still is (1 to 0 as it travels), and the disc's lift.
struct Wave: Equatable {
    /// The front's distance from the chosen leaf's middle.
    var radius: CGFloat
    /// 1 when it sets off, 0 when it's gone.
    var strength: Double
}

extension Motion {
    // MARK: Disc and hub

    static func disc(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let drop = e.drop {
            let t = now - drop.at
            if e.reduce { return Look(opacity: 1 - phase(t, 0, fade)) }
            // The glass contracts to just under the ring, and stays as its backing.
            let p = settle(phase(t, Drop.discAt, Drop.disc))
            return Look(scale: lerp(1, Drop.discTo / (BloomGeometry.discRadius * 2), p))
        }
        if let cancel = e.cancelAt { return cancelLook(e, now: now, since: cancel) }
        guard Open.animated else { return .still }
        if e.reduce { return Look(opacity: phase(now, e.openedAt, fade)) }
        let p = settle(phase(now, e.openedAt, Open.disc))
        return Look(scale: lerp(Open.discFrom, 1, p), opacity: clamp(phase(now, e.openedAt, Open.disc) * 4))
    }

    /// The centre circle. In a drop it is nudged when the wave reaches it, then shrinks to
    /// the ring's size; `origin` is the chosen leaf's middle.
    static func hub(_ e: BloomEvents, now: TimeInterval, origin: CGPoint = .zero) -> Look {
        if let drop = e.drop {
            let t = now - drop.at
            if e.reduce { return Look(opacity: 1 - phase(t, 0, fade)) }
            var look = nudged(.zero, origin: origin, t: t, shift: Drop.hubNudgeShift, scale: Drop.hubNudgeScale)
            let p = settle(phase(t, Drop.hubShrinkAt, Drop.hubShrink))
            look.scale *= lerp(1, Drop.ringSide / BloomGeometry.hubSize, p)
            return look
        }
        if let cancel = e.cancelAt { return cancelLook(e, now: now, since: cancel) }
        guard Open.animated else {
            if e.reduce { return .still }
            return Look(scale: lerp(Open.settleFrom, 1, settle(phase(now, max(e.slotsAt, e.openedAt), Open.settle))))
        }
        if e.reduce { return Look(opacity: phase(now, e.openedAt, fade)) }
        let p = settle(phase(now, e.openedAt, Open.hub))
        return Look(scale: lerp(Open.hubFrom, 1, p), blur: lerp(Open.hubBlur, 0, p),
                    opacity: clamp(phase(now, e.openedAt, Open.hub) * 3))
    }

    /// The size capsule on the centre circle.
    static func capsule(_ e: BloomEvents, now: TimeInterval) -> Look {
        if e.drop != nil { return hubContent(e, now: now) }
        if let cancel = e.cancelAt { return cancelLook(e, now: now, since: cancel) }
        guard Open.animated else { return .still }
        let start = max(e.openedAt, e.slotsAt) + (e.reduce ? 0 : Open.capsuleDelay)
        if e.reduce { return Look(opacity: phase(now, start, fade)) }
        let p = settle(phase(now, start, Open.capsule))
        return Look(scale: lerp(1.12, 1, p), blur: lerp(10, 0, p), opacity: clamp(phase(now, start, Open.capsule) * 3))
    }

    /// The ring of light on open: its radius, opacity and line width, or nil.
    static func lightRing(_ e: BloomEvents, now: TimeInterval) -> (radius: CGFloat, opacity: Double, width: CGFloat)? {
        guard Open.ringEnabled, !e.reduce, e.drop == nil, e.cancelAt == nil, e.openedAt.isFinite else { return nil }
        let t = (now - e.openedAt) / Open.ring
        guard t >= 0, t < 1 else { return nil }
        let p = settle(t)
        let opacity = Open.ringPeak * clamp(t / 0.12) * (1 - exit(t))
        return (lerp(Open.ringFrom, Open.ringTo, p), opacity, lerp(2.2, 0.8, p))
    }

    // MARK: Slots

    /// A slot's look: its unfold, pop and dimming, or its part in a drop or a cancel.
    /// `center` is the slot's middle in clover coordinates, for folding towards the hub.
    static func slot(_ i: Int, count: Int, center: CGPoint, _ e: BloomEvents, now: TimeInterval,
                     origin: CGPoint = .zero) -> (look: Look, fill: SlotFill) {
        if let drop = e.drop {
            if drop.slot == i { return carrySlot(center: center, e, now: now, drop: drop) }
            let t = now - drop.at
            if e.reduce { return (Look(opacity: Hover.dimOpacity * (1 - phase(t, 0, fade))), .frosted) }
            // Nudged when the wave reaches it, then folded to the hub, the farthest last.
            var look = nudged(center, origin: origin, t: t, shift: Drop.nudgeShift, scale: Drop.nudgeScale)
            let distance = hypot(center.x - origin.x, center.y - origin.y)
            let start = Drop.gatherAt + Drop.gatherStagger * Double(min(distance / waveReach(origin), 1))
            let p = settle(phase(t, start, Drop.fold))
            let s = lerp(1, Drop.foldTo, p)
            look.scale *= s
            look.offset.width += center.x * (s - 1)
            look.offset.height += center.y * (s - 1)
            look.blur = lerp(0, Drop.foldBlur, p)
            look.opacity = Hover.dimOpacity * (1 - p)
            return (look, .frosted)
        }
        if let cancel = e.cancelAt {
            return (Cancel.animated ? foldLook(e, now: now, since: cancel, towards: center, duration: Cancel.duration) : .hidden, .frosted)
        }
        var look = unfold(i, center: center, e, now: now)
        let fill: SlotFill = e.lit == i ? .lit : .frosted
        if Hover.smooth, !e.reduce { look.scale *= lerp(1, Hover.lift, litAmount(i, e, now: now)) }
        if let p = e.press, p.target == .leaf(i) { look.scale *= pressScale(p, peak: Press.leafPeak, reduce: e.reduce, now: now) }
        if e.lit == i {
            if Hover.popEnabled, !e.reduce { look.scale *= litScale(e, now: now) }
        } else {
            if e.unlit == i, Hover.popEnabled, !e.reduce {
                // Back to its size, quickly.
                look.scale *= lerp(Hover.rest, 1, exit(phase(now, e.unlitAt, Hover.leave)))
            }
            let d = dimAmount(e, now: now)
            look.opacity *= 1 - (1 - Hover.dimOpacity) * d
            if !e.reduce { look.blur += Hover.dimBlur * CGFloat(d) }
        }
        return (look, fill)
    }

    /// The slot unfolding from the centre circle when the files arrive.
    static func unfold(_ i: Int, center: CGPoint, _ e: BloomEvents, now: TimeInterval) -> Look {
        guard Open.animated else {
            if e.reduce { return .still }
            // Settles about the disc's centre, with the hub, as the window fades in.
            let s = lerp(Open.settleFrom, 1, settle(phase(now, max(e.slotsAt, e.openedAt), Open.settle)))
            return Look(scale: s, offset: CGSize(width: center.x * (s - 1), height: center.y * (s - 1)))
        }
        let start = max(e.slotsAt, e.openedAt) + (e.reduce ? 0 : Double(i) * Open.slotStagger)
        if e.reduce { return Look(opacity: phase(now, start, fade)) }
        let raw = phase(now, start, Open.slot)
        let p = settle(raw)
        // Scaled about the disc's centre: the slot travels out from the hub as it grows.
        let s = lerp(Open.slotFrom, 1, p)
        let offset = CGSize(width: center.x * (s - 1), height: center.y * (s - 1))
        return Look(scale: s, offset: offset, blur: lerp(Open.slotBlur, 0, p), opacity: clamp(raw * 4))
    }

    /// The lit slot's size: a pop to `peak` in the first frames, then a settle at `rest`.
    static func litScale(_ e: BloomEvents, now: TimeInterval) -> CGFloat {
        guard Hover.popEnabled else { return 1 }
        let t = now - e.litAt
        if !e.litAt.isFinite || t >= Hover.popRise + Hover.popSettle { return Hover.rest }
        if t < Hover.popRise { return lerp(1, Hover.peak, settle(t / Hover.popRise)) }
        return lerp(Hover.peak, Hover.rest, settle((t - Hover.popRise) / Hover.popSettle))
    }

    /// 0 when nothing is lit, 1 when the others are fully dimmed.
    /// How lit slot `i` is, 0...1: it eases in when lit and out when the pointer leaves.
    static func litAmount(_ i: Int, _ e: BloomEvents, now: TimeInterval) -> Double {
        guard Hover.smooth else { return e.lit == i ? 1 : 0 }
        if e.lit == i {
            return e.reduce ? phase(now, e.litAt, fade) : settle(phase(now, e.litAt, Hover.fadeIn))
        }
        if e.unlit == i {
            return 1 - (e.reduce ? phase(now, e.unlitAt, fade) : exit(phase(now, e.unlitAt, Hover.fadeOut)))
        }
        return 0
    }

    static func dimAmount(_ e: BloomEvents, now: TimeInterval) -> Double {
        guard Hover.dimAnimated else { return e.lit == nil ? 0 : 1 }
        if e.lit != nil {
            return e.reduce ? phase(now, e.dimAt, fade) : settle(phase(now, e.dimAt, Hover.dim))
        }
        return 1 - (e.reduce ? phase(now, e.undimAt, fade) : exit(phase(now, e.undimAt, Hover.undim)))
    }

    /// The glow under the lit slot: scale and opacity, breathing. Nil when off.
    static func glow(_ e: BloomEvents, now: TimeInterval) -> (scale: CGFloat, opacity: Double)? {
        guard Hover.glowEnabled, e.lit != nil, e.drop == nil, e.cancelAt == nil else { return nil }
        if e.reduce { return (1, phase(now, e.litAt, fade)) }
        let t = now - e.litAt
        let breath = e.litAt.isFinite ? sin(2 * .pi * t / Hover.breath) : 0
        let rise = settle(phase(now, e.litAt, Hover.glowIn))
        return (litScale(e, now: now) * (1 + Hover.breathAmount * CGFloat(breath)), rise * (0.9 + 0.1 * breath))
    }

    /// A hover ripple's scale, opacity and line width, or nil.
    static func ripple(_ r: BloomEvents.Ripple, _ e: BloomEvents, now: TimeInterval) -> (scale: CGFloat, opacity: Double, width: CGFloat)? {
        guard Hover.rippleEnabled, !e.reduce, e.drop == nil, e.cancelAt == nil else { return nil }
        let t = (now - r.at) / Hover.ripple
        guard t >= 0, t < 1 else { return nil }
        let p = settle(t)
        return (Hover.rest * (1 + Hover.rippleGrow * CGFloat(p)), Hover.rippleOpacity * (1 - p), lerp(1.6, 0.6, p))
    }

    // MARK: Chips

    /// A chip being born: `rank` is its place in the order, nearest the pointer first, and
    /// `since` when its row opened.
    static func chipIn(rank: Int, since: TimeInterval, _ e: BloomEvents, now: TimeInterval) -> Look {
        guard Chips.animated else { return .still }
        let start = since + (e.reduce ? 0 : Double(rank) * Chips.stagger)
        if e.reduce { return Look(opacity: phase(now, start, fade)) }
        let raw = phase(now, start, Chips.settle)
        let p = settle(raw)
        return Look(scale: lerp(Chips.bornScale, 1, p), blur: lerp(Chips.bornBlur, 0, p), opacity: clamp(raw * 3))
    }

    /// A chip shrinking back into its slot: `towards` is the slot's rim point relative to
    /// the chip. Nil once gone, and at once when chips aren't animated.
    static func chipOut(towards: CGVector, _ e: BloomEvents, now: TimeInterval) -> Look? {
        guard Chips.animated else { return nil }
        let raw = phase(now, e.closingAt, e.reduce ? fade : Chips.leave)
        guard raw < 1 else { return nil }
        if e.reduce { return Look(opacity: 1 - raw) }
        let p = exit(raw)
        return Look(scale: lerp(1, Chips.leaveScale, p),
                    offset: CGSize(width: towards.dx * CGFloat(p) * 0.6, height: towards.dy * CGFloat(p) * 0.6),
                    blur: lerp(0, Chips.leaveBlur, p), opacity: 1 - p)
    }

    /// The pop of a lit chip or pill, from `at`.
    static func litPop(at: TimeInterval, _ e: BloomEvents, now: TimeInterval) -> CGFloat {
        guard Chips.animated, !e.reduce, at.isFinite else { return 1 }
        return pop(now - at, duration: Chips.litPop, peak: Chips.litPeak)
    }

    /// Chips during a drop (they fold with the others) or a cancel.
    static func chipsLeaving(_ e: BloomEvents, now: TimeInterval) -> Look? {
        if let drop = e.drop {
            let t = now - drop.at
            if e.reduce { return Look(opacity: 1 - phase(t, 0, fade)) }
            let p = exit(phase(t, Drop.gatherAt, Drop.chipsFold))
            return Look(scale: lerp(1, Drop.foldTo, p), blur: lerp(0, Drop.foldBlur, p), opacity: 1 - p)
        }
        if let cancel = e.cancelAt {
            return Cancel.animated ? foldLook(e, now: now, since: cancel, towards: .zero, duration: Cancel.duration, scaleAboutCentre: false) : .hidden
        }
        return nil
    }

    // MARK: Tray

    /// The tray itself, growing out of the More slot.
    static func tray(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let drop = e.drop {
            if e.reduce { return Look(opacity: 1 - phase(now, drop.at, fade)) }
            return now - drop.at < Drop.trayHold ? .still : .hidden
        }
        if let cancel = e.cancelAt { return Cancel.animated ? trayOut(e, now: now, since: cancel) : .hidden }
        if let closing = e.trayClosingAt { return Tray.animated ? trayOut(e, now: now, since: closing) : .hidden }
        guard Tray.animated else { return .still }
        if e.reduce { return Look(opacity: phase(now, e.trayAt, fade)) }
        let raw = phase(now, e.trayAt, Tray.settle)
        let p = settle(raw)
        return Look(scale: lerp(Tray.bornScale, 1, p), blur: lerp(Tray.bornBlur, 0, p), opacity: clamp(raw * 4))
    }

    private static func trayOut(_ e: BloomEvents, now: TimeInterval, since: TimeInterval) -> Look {
        let raw = phase(now, since, e.reduce ? fade : Tray.close)
        if e.reduce { return Look(opacity: 1 - raw) }
        let p = exit(raw)
        return Look(scale: lerp(1, Tray.bornScale, p), blur: lerp(0, Tray.bornBlur * 0.6, p), opacity: 1 - p)
    }

    /// A pill in the tray, born in turn.
    static func pill(_ i: Int, _ e: BloomEvents, now: TimeInterval) -> Look {
        guard Tray.animated, !e.reduce else { return .still }
        let start = e.trayAt + Tray.pillDelay + Double(i) * Tray.pillStagger
        let raw = phase(now, start, Tray.pill)
        let p = settle(raw)
        return Look(scale: lerp(Tray.pillBornScale, 1, p), blur: lerp(Tray.pillBornBlur, 0, p), opacity: clamp(raw * 3))
    }

    // MARK: Press

    /// A damped spring from `from` to `to`, starting with `velocity`, `t` seconds in: its
    /// value and velocity. `response` is the period of its swing; `damping` below 1 lets it
    /// swing past its target a little.
    static func spring(_ t: Double, from: Double, to: Double, velocity: Double,
                       damping z: Double, response: Double) -> (value: Double, velocity: Double) {
        guard t > 0 else { return (from, velocity) }
        let w = 2 * Double.pi / response
        let a = from - to
        if z >= 1 {
            let e = exp(-w * t), b = velocity + w * a
            return (to + (a + b * t) * e, (b - w * (a + b * t)) * e)
        }
        let wd = w * sqrt(1 - z * z)
        let b = (velocity + z * w * a) / wd
        let e = exp(-z * w * t), c = cos(wd * t), s = sin(wd * t)
        return (to + e * (a * c + b * s), e * ((b * wd - z * w * a) * c - (a * wd + z * w * b) * s))
    }

    /// A press's scale on the pressed shape: the swell while held, the jelly settle after.
    static func pressScale(_ p: BloomEvents.Press, peak: CGFloat, reduce: Bool, now: TimeInterval) -> CGFloat {
        guard !reduce, now > p.at else { return 1 }
        let top = Double(peak)
        if let end = p.endsAt, now > end {
            let atEnd = spring(end - p.at, from: 1, to: top, velocity: 0, damping: Press.damping, response: Press.response)
            return CGFloat(spring(now - end, from: atEnd.value, to: 1, velocity: atEnd.velocity,
                                  damping: Press.releaseDamping, response: Press.releaseResponse).value)
        }
        return CGFloat(spring(now - p.at, from: 1, to: top, velocity: 0, damping: Press.damping, response: Press.response).value)
    }

    /// A press's light: how bright, and how far it has grown from the press point (0 to 1
    /// of the way to the shape's far edge). Nil once it has faded.
    static func pressLight(_ p: BloomEvents.Press, reduce: Bool, now: TimeInterval) -> (intensity: Double, grow: Double)? {
        let t = now - p.at
        guard t >= 0 else { return nil }
        func held(_ t: Double) -> Double {
            if reduce { return phase(t, 0, fade) }
            return settle(t / Press.lightRise) * (1 - (1 - Press.lightHeld) * settle(phase(t, Press.lightGrow, Press.lightEase)))
        }
        var intensity = held(t)
        if let end = p.endsAt, now > end {
            let out = reduce ? phase(now, end, fade) : settle(phase(now, end, Press.lightFade))
            intensity = held(end - p.at) * (1 - out)
        }
        guard intensity > 0.001 else { return nil }
        return (intensity, reduce ? 1 : settle(t / Press.lightGrow))
    }

    /// The last moment a press moves: its swell and light while held, its settle and fade after.
    static func pressBusyUntil(_ p: BloomEvents.Press) -> TimeInterval {
        guard let end = p.endsAt else { return p.at + max(Press.response * 2, Press.lightGrow + Press.lightEase) }
        return end + max(Press.releaseSettle, Press.lightFade)
    }

    // MARK: Drop: light through the glass

    /// How far the wave travels from `origin`: to the far side of the disc.
    static func waveReach(_ origin: CGPoint) -> CGFloat {
        hypot(origin.x, origin.y) + BloomGeometry.discRadius
    }

    /// The wave at a moment, or nil before and after it, and with reduce motion.
    static func wave(_ e: BloomEvents, now: TimeInterval, origin: CGPoint) -> Wave? {
        guard Drop.waveEnabled, let drop = e.drop, !e.reduce else { return nil }
        let u = (now - drop.at - Drop.waveStart) / Drop.wave
        guard u >= 0, u < 1 else { return nil }
        return Wave(radius: waveReach(origin) * CGFloat(settle(u)), strength: 1 - exit(u))
    }

    /// When the wave's front reaches `distance` from its origin, after the drop.
    static func waveArrives(_ distance: CGFloat, origin: CGPoint) -> TimeInterval {
        let f = Double(min(max(distance / waveReach(origin), 0), 0.999))
        // The inverse of `settle`.
        let k = 2.5
        let u = -log(1 - f * (1 - exp(-k))) / k
        return Drop.waveStart + u * Drop.wave
    }

    /// A nudge's strength at `t` after it starts: up quickly, back softly, never past 0.
    static func nudge(_ t: TimeInterval) -> Double {
        guard t > 0, t < Drop.nudge else { return 0 }
        let u = t / Drop.nudge
        if u < Drop.nudgeRise { return settle(u / Drop.nudgeRise) }
        return 1 - settle((u - Drop.nudgeRise) / (1 - Drop.nudgeRise))
    }

    /// Something at `center` nudged outward from `origin` as the wave passes it.
    static func nudged(_ center: CGPoint, origin: CGPoint, t: TimeInterval, shift: CGFloat, scale: CGFloat) -> Look {
        guard Drop.waveEnabled else { return .still }
        let dx = center.x - origin.x, dy = center.y - origin.y
        let distance = hypot(dx, dy)
        guard distance > 1 else { return .still }
        let n = CGFloat(nudge(t - waveArrives(distance, origin: origin)))
        return Look(scale: 1 + (scale - 1) * n, offset: CGSize(width: dx / distance * shift * n, height: dy / distance * shift * n))
    }

    /// The hub's picture, count and capsule as the hub becomes the ring: they go, blurring.
    static func hubContent(_ e: BloomEvents, now: TimeInterval) -> Look {
        guard let drop = e.drop else { return .still }
        let t = now - drop.at
        if e.reduce { return Look(opacity: 1 - phase(t, 0, fade)) }
        // Gone quickly, so nothing lingers under the leaf gliding in.
        let p = settle(phase(t, Drop.hubContentAt, Drop.hubContent))
        return Look(blur: lerp(0, Drop.hubContentBlur, p), opacity: 1 - p)
    }

    /// The chosen leaf's soft inner glow: 0 to 1, or 0 with no drop.
    static func chosenGlow(_ e: BloomEvents, now: TimeInterval) -> Double {
        // A press lights the leaf itself.
        guard let drop = e.drop, !e.reduce, e.press == nil else { return 0 }
        let t = now - drop.at
        return settle(phase(t, 0, Drop.choose)) * (1 - phase(t, Drop.glideStart, Drop.glowOut))
    }

    /// A pop: up to `peak` in the first 30 % of `duration`, back to 1 by its end.
    static func pop(_ t: TimeInterval, duration: TimeInterval, peak: CGFloat) -> CGFloat {
        let rise = duration * 0.3
        if t < 0 || t >= duration { return 1 }
        if t < rise { return lerp(1, peak, settle(t / rise)) }
        return lerp(peak, 1, settle((t - rise) / (duration - rise)))
    }

    /// The chosen leaf: full hover brightness and a lift, then a glide into the hub,
    /// shrinking, and a one-frame flip into the ring as it lands.
    static func carrySlot(center: CGPoint, _ e: BloomEvents, now: TimeInterval, drop: BloomEvents.Drop) -> (look: Look, fill: SlotFill) {
        let t = now - drop.at
        if e.reduce { return (Look(opacity: 1 - phase(t, 0, fade)), .lit) }
        if t >= Drop.ringAt { return (.hidden, .lit) }
        let from = Hover.smooth ? Hover.lift : 1
        // After a press, the press's own settle carries on; the lift is only for a choice
        // that came without one.
        let lift: CGFloat
        if let p = e.press, p.target == .leaf(drop.slot) {
            lift = from * pressScale(p, peak: Press.leafPeak, reduce: false, now: now)
        } else if e.press != nil {
            lift = from
        } else {
            lift = lerp(from, Drop.chooseLift, settle(phase(t, 0, Drop.choose)))
        }
        let p = settle(phase(t, Drop.glideStart, Drop.glide))
        let offset = CGSize(width: -center.x * CGFloat(p), height: -center.y * CGFloat(p))
        return (Look(scale: lift * lerp(1, Drop.glideTo, p), offset: offset), .lit)
    }

    /// The ring on the hub's glass, from the moment the leaf is taken in. Nil before.
    static func carryRing(_ e: BloomEvents, now: TimeInterval) -> Look? {
        guard let drop = e.drop else { return nil }
        let t = now - drop.at
        if e.reduce {
            // Fades in as the clover fades out, so there is never an empty frame.
            guard t >= fade / 2 else { return nil }
            return Look(opacity: phase(t, fade / 2, fade))
        }
        guard t >= Drop.ringAt else { return nil }
        return Look(scale: pop(t - Drop.ringAt, duration: Drop.ringPop, peak: Drop.ringPopPeak))
    }

    /// Something folding into the hub on an animated cancel: it shrinks about the disc's
    /// centre, so it moves in, and blurs away.
    static func foldLook(_ e: BloomEvents, now: TimeInterval, since: TimeInterval, towards center: CGPoint,
                         duration: TimeInterval? = nil, scaleAboutCentre: Bool = true) -> Look {
        if e.reduce { return Look(opacity: 1 - phase(now, since, fade)) }
        let raw = phase(now, since, duration ?? Drop.fold)
        let p = exit(raw)
        let s = lerp(1, Drop.foldTo, p)
        let offset = scaleAboutCentre ? CGSize(width: center.x * (s - 1), height: center.y * (s - 1)) : .zero
        return Look(scale: s, offset: offset, blur: lerp(0, Drop.foldBlur, p), opacity: 1 - p)
    }

    /// The disc, hub and capsule on a cancel: they shrink away, blurred, or go at once.
    static func cancelLook(_ e: BloomEvents, now: TimeInterval, since: TimeInterval) -> Look {
        guard Cancel.animated else { return .hidden }
        let raw = phase(now, since, e.reduce ? fade : Cancel.duration)
        if e.reduce { return Look(opacity: 1 - raw) }
        let p = exit(raw)
        return Look(scale: lerp(1, Cancel.shrinkTo, p), blur: lerp(0, Cancel.blur, p), opacity: 1 - p)
    }

    /// How long the clover takes to hide after a cancel.
    static func cancelDuration(reduce: Bool) -> TimeInterval {
        guard Cancel.animated else { return 0 }
        return reduce ? fade : Cancel.duration
    }

    /// How long the tray takes to hide.
    static func trayCloseDuration(reduce: Bool) -> TimeInterval {
        guard Tray.animated else { return 0 }
        return reduce ? fade : Tray.close
    }

    // MARK: Quiet

    /// The last moment anything moves, for pausing the frame clock. A breathing glow is
    /// handled by the caller.
    static func busyUntil(_ e: BloomEvents, count: Int) -> TimeInterval {
        var end = -Double.infinity
        if Open.animated {
            end = max(end, max(e.slotsAt, e.openedAt) + Open.slot + Open.slotStagger * Double(count))
            end = max(end, max(e.openedAt, e.slotsAt) + Open.capsuleDelay + Open.capsule)
        } else if !e.reduce {
            end = max(end, max(e.slotsAt, e.openedAt) + Open.settle)
        }
        if Open.ringEnabled { end = max(end, e.openedAt + Open.ring) }
        if Hover.popEnabled { end = max(end, e.litAt + Hover.popRise + Hover.popSettle, e.unlitAt + Hover.leave) }
        if Hover.dimAnimated { end = max(end, e.dimAt + Hover.dim, e.undimAt + Hover.undim) }
        if Hover.smooth { end = max(end, e.litAt + Hover.fadeIn, e.unlitAt + Hover.fadeOut) }
        if Hover.rippleEnabled { end = max(end, (e.ripples.map(\.at).max() ?? -.infinity) + Hover.ripple) }
        if Chips.animated {
            end = max(end, e.chipsAt + Chips.settle + Chips.stagger * Double(e.chipRank.count))
            end = max(end, e.pillChipsAt + Chips.settle + Chips.stagger * Double(e.pillChipRank.count))
            end = max(end, e.closingAt + Chips.leave, e.litChipAt + Chips.litPop, e.litPillAt + Chips.litPop)
        }
        if Tray.animated {
            end = max(end, e.trayAt + Tray.pillDelay + Tray.pill + Tray.pillStagger * 12, (e.trayClosingAt ?? -.infinity) + Tray.close)
        }
        end = max(end, (e.drop?.at ?? -.infinity) + Drop.handoff)
        if let p = e.press { end = max(end, pressBusyUntil(p)) }
        if Cancel.animated { end = max(end, (e.cancelAt ?? -.infinity) + Cancel.duration) }
        return end + (e.reduce ? fade : 0)
    }
}
