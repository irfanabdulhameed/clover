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
        /// Off: the disc, slots, hub and capsule appear at once, full size and sharp.
        static let animated = false
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

    // MARK: Drop: the AirDrop wave

    /// Choosing a leaf: a flash and a glow, a wave of light that bends the slots as it
    /// rolls across the disc, then the fold into the progress ring. About 0.6 s.
    enum Drop {
        /// 0 ms: the chosen slot flashes white for one frame and pops.
        static let flash: TimeInterval = 1.0 / 60
        static let pop: TimeInterval = 0.12
        static let popPeak: CGFloat = 1.08
        /// A bright soft glow blooms behind it: white core, clover-green edge.
        static let glowRise: TimeInterval = 0.05
        static let glowFade: TimeInterval = 0.42
        static let glowFrom: CGFloat = 0.95
        static let glowTo: CGFloat = 1.35
        /// 0 to 420 ms: a ring of light expands from the chosen slot across the disc and
        /// just past the rim.
        static let wave: TimeInterval = 0.42
        static var waveReach: CGFloat { BloomGeometry.discRadius * 2 }
        /// The band where the slots bend.
        static let waveBand: CGFloat = 36
        /// How far the band pushes what's under it outward, like a lens, at full strength.
        static let waveShift: CGFloat = 8
        static let waveMaxScale: CGFloat = 1.12
        /// The bent copy is a little brighter.
        static let waveBrighten: Double = 0.14
        /// The soft white light trailing the leading edge, and how far it trails.
        static let waveLight: Double = 0.22
        static let waveTrail: CGFloat = 0.9
        /// The thin iridescent stroke on the leading edge.
        static let waveEdge: Double = 0.5
        static let waveEdgeWidth: CGFloat = 2
        /// The disc's slight brightness lift while the wave crosses it.
        static let discLift: Double = 0.08
        /// The wave shows this far past the rim, then fades out.
        static let wavePastRim: CGFloat = 6
        /// A tray choice: the tray stays for the flash, then goes.
        static let trayHold: TimeInterval = 0.05
        /// 380 ms: the other slots fold into the hub, blurring.
        static let foldAt: TimeInterval = 0.38
        static let fold: TimeInterval = 0.12
        static let foldTo: CGFloat = 0.45
        static let foldBlur: CGFloat = 10
        /// The chosen slot gathers to the centre, shrinking.
        static let glideDelay: TimeInterval = 0.38
        static let glide: TimeInterval = 0.17
        /// The slot's size when it arrives, as a scale of its own.
        static let glideTo: CGFloat = 0.62
        /// Then it flips into the progress ring, with a pop.
        static let ringAt: TimeInterval = 0.55
        static let ringPop: TimeInterval = 0.045
        /// The disc shrinks behind it to the ring's backing.
        static let discDelay: TimeInterval = 0.40
        static let disc: TimeInterval = 0.17
        /// The result chip takes over the ring at this moment, at `BloomAnchor`; the panel
        /// hides. `ChipMotion.ringAppearDelay` is the same moment.
        static let handoff: TimeInterval = 0.60
        /// The ring: a clover-green disc with a white ring on it.
        static let carrySide: CGFloat = 64
        static let ringSide: CGFloat = 56
        static let ringWidth: CGFloat = 3
        static let ringOpacity: Double = 0.9
        static let trackOpacity: Double = 0.2
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
    var radius: CGFloat
    var band: CGFloat
    var strength: Double
    var lift: Double

    /// A bent copy's scale about the wave's centre: what's under the band moves outward by
    /// `share` of `Motion.Drop.waveShift`. The band's middle takes the whole shift, its
    /// sides half, so the bend ramps up and down instead of tearing.
    func bendScale(_ share: CGFloat = 1) -> CGFloat {
        let shift = Motion.Drop.waveShift * CGFloat(strength) * share
        return min(1 + shift / max(radius, 1), 1 + (Motion.Drop.waveMaxScale - 1) * share)
    }
}

extension Motion {
    // MARK: Disc and hub

    static func disc(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let drop = e.drop {
            let t = now - drop.at
            if e.reduce { return Look(opacity: 1 - phase(t, 0, fade)) }
            let p = settle(phase(t, Drop.discDelay, Drop.disc))
            // Down to the ring's backing, then gone under the green disc.
            let to = Drop.carrySide / (BloomGeometry.discRadius * 2)
            return Look(scale: lerp(1, to, p), opacity: 1 - phase(t, Drop.ringAt, 0.04))
        }
        if let cancel = e.cancelAt { return cancelLook(e, now: now, since: cancel) }
        guard Open.animated else { return .still }
        if e.reduce { return Look(opacity: phase(now, e.openedAt, fade)) }
        let p = settle(phase(now, e.openedAt, Open.disc))
        return Look(scale: lerp(Open.discFrom, 1, p), opacity: clamp(phase(now, e.openedAt, Open.disc) * 4))
    }

    /// The centre circle with the picture.
    static func hub(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let drop = e.drop { return foldLook(e, now: now, since: drop.at, towards: .zero) }
        if let cancel = e.cancelAt { return cancelLook(e, now: now, since: cancel) }
        guard Open.animated else { return .still }
        if e.reduce { return Look(opacity: phase(now, e.openedAt, fade)) }
        let p = settle(phase(now, e.openedAt, Open.hub))
        return Look(scale: lerp(Open.hubFrom, 1, p), blur: lerp(Open.hubBlur, 0, p),
                    opacity: clamp(phase(now, e.openedAt, Open.hub) * 3))
    }

    /// The size capsule on the centre circle.
    static func capsule(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let drop = e.drop { return foldLook(e, now: now, since: drop.at, towards: .zero) }
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
    static func slot(_ i: Int, count: Int, center: CGPoint, _ e: BloomEvents, now: TimeInterval) -> (look: Look, fill: SlotFill) {
        if let drop = e.drop {
            if drop.slot == i { return carrySlot(center: center, e, now: now, drop: drop) }
            // The others stay, dimmed, while the wave bends them, then fold away.
            var look = foldLook(e, now: now, since: drop.at, towards: center)
            look.opacity *= Hover.dimOpacity
            return (look, .frosted)
        }
        if let cancel = e.cancelAt {
            return (Cancel.animated ? foldLook(e, now: now, since: cancel, towards: center, duration: Cancel.duration) : .hidden, .frosted)
        }
        var look = unfold(i, center: center, e, now: now)
        let fill: SlotFill = e.lit == i ? .lit : .frosted
        if Hover.smooth, !e.reduce { look.scale *= lerp(1, Hover.lift, litAmount(i, e, now: now)) }
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
        guard Open.animated else { return .still }
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
        if let drop = e.drop { return foldLook(e, now: now, since: drop.at, towards: .zero, scaleAboutCentre: false) }
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

    // MARK: Drop: the wave and the carry

    /// The wave at a moment, or nil before and after it, and with reduce motion.
    static func wave(_ e: BloomEvents, now: TimeInterval) -> Wave? {
        guard let drop = e.drop, !e.reduce else { return nil }
        let t = (now - drop.at) / Drop.wave
        guard t >= 0, t < 1 else { return nil }
        return Wave(radius: Drop.waveReach * CGFloat(settle(t)), band: Drop.waveBand,
                    strength: 1 - exit(t), lift: Drop.discLift * sin(.pi * t))
    }

    /// The glow that blooms behind the chosen slot: scale and opacity, or nil.
    static func dropGlow(_ e: BloomEvents, now: TimeInterval) -> (scale: CGFloat, opacity: Double)? {
        guard let drop = e.drop, !e.reduce else { return nil }
        let t = now - drop.at
        guard t >= 0, t < Drop.glowFade else { return nil }
        let rise = settle(t / Drop.glowRise)
        let fall = 1 - exit(phase(t, Drop.glowRise, Drop.glowFade - Drop.glowRise))
        return (lerp(Drop.glowFrom, Drop.glowTo, settle(t / Drop.glowFade)), rise * fall)
    }

    /// A pop: up to `peak` in the first 30 % of `duration`, back to 1 by its end.
    static func pop(_ t: TimeInterval, duration: TimeInterval, peak: CGFloat) -> CGFloat {
        let rise = duration * 0.3
        if t < 0 || t >= duration { return 1 }
        if t < rise { return lerp(1, peak, settle(t / rise)) }
        return lerp(peak, 1, settle((t - rise) / (duration - rise)))
    }

    /// The carried slot: flash and pop, stay lit while the wave rolls, then gather to the
    /// centre shrinking, and flip into the ring.
    static func carrySlot(center: CGPoint, _ e: BloomEvents, now: TimeInterval, drop: BloomEvents.Drop) -> (look: Look, fill: SlotFill) {
        let t = now - drop.at
        let flash = t >= 0 && t < Drop.flash && drop.chip == nil && drop.pill == nil
        if e.reduce {
            return (Look(opacity: 1 - phase(t, 0, fade)), flash ? .flash : .lit)
        }
        if t >= Drop.ringAt { return (.hidden, .lit) }
        let p = settle(phase(t, Drop.glideDelay, Drop.glide))
        let s = pop(t, duration: Drop.pop, peak: Drop.popPeak) * lerp(1, Drop.glideTo, p)
        // Its middle travels to the hub.
        let offset = CGSize(width: -center.x * CGFloat(p), height: -center.y * CGFloat(p))
        return (Look(scale: s, offset: offset), flash ? .flash : .lit)
    }

    /// The ring at the hub, from the moment the slot flips into it. Nil before.
    static func carryRing(_ e: BloomEvents, now: TimeInterval) -> Look? {
        guard let drop = e.drop else { return nil }
        let t = now - drop.at
        if e.reduce {
            // Fades in as the clover fades out, so there is never an empty frame.
            guard t >= fade / 2 else { return nil }
            return Look(opacity: phase(t, fade / 2, fade))
        }
        guard t >= Drop.ringAt else { return nil }
        return Look(scale: pop(t - Drop.ringAt, duration: Drop.ringPop, peak: Hover.peak))
    }

    /// Something folding into the hub in a drop (after the wave) or a cancel: it shrinks
    /// about the disc's centre, so it moves in, and blurs away.
    static func foldLook(_ e: BloomEvents, now: TimeInterval, since: TimeInterval, towards center: CGPoint,
                         duration: TimeInterval? = nil, scaleAboutCentre: Bool = true) -> Look {
        let isDrop = e.drop != nil
        if e.reduce { return Look(opacity: 1 - phase(now, since, fade)) }
        let start = isDrop ? since + Drop.foldAt : since
        let raw = phase(now, start, duration ?? Drop.fold)
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
        if Cancel.animated { end = max(end, (e.cancelAt ?? -.infinity) + Cancel.duration) }
        return end + (e.reduce ? fade : 0)
    }
}
