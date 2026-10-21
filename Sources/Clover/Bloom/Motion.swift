import CoreGraphics
import Foundation

/// Every timing, distance and easing of the clover's motion, in seconds and points, and the
/// choreography that turns them into a look at a moment in time. Tune here.
///
/// House rules: no bounce or overshoot; fast attack and a long soft slow-down (about 75 %
/// of the way in the first 140 ms of 300); things are born blurred and slightly large and
/// come into focus; a state change is a one-frame flip plus a small pop; exits are faster
/// than entrances; nothing lit sits dead still.
enum Motion {
    // MARK: Open

    enum Open {
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
        /// The ring of light that radiates from the pointer, like AirDrop's radar.
        static let ring: TimeInterval = 0.50
        static let ringFrom: CGFloat = 40
        static let ringTo: CGFloat = 250
        static let ringPeak: Double = 0.55
    }

    // MARK: Hover

    enum Hover {
        /// The pointer rests this long before a slot lights, so a sweep doesn't flicker.
        static let delay: TimeInterval = 0.08
        /// The lit flip pops to `peak`, then settles at `rest`.
        static let popRise: TimeInterval = 0.03
        static let popSettle: TimeInterval = 0.09
        static let peak: CGFloat = 1.08
        static let rest: CGFloat = 1.04
        /// A slot going dark returns to its size, faster than it popped.
        static let leave: TimeInterval = 0.07
        /// One ripple of light leaves the lit slot's outline.
        static let ripple: TimeInterval = 0.45
        static let rippleGrow: CGFloat = 0.16
        static let rippleOpacity: Double = 0.75
        /// The glow under the lit slot breathes.
        static let breath: TimeInterval = 2.4
        static let breathAmount: CGFloat = 0.03
        static let glowIn: TimeInterval = 0.16
        /// The other slots dim and soften.
        static let dim: TimeInterval = 0.12
        static let undim: TimeInterval = 0.09
        static let dimOpacity: Double = 0.75
        static let dimBlur: CGFloat = 1.5
    }

    // MARK: Option chips

    enum Chips {
        /// The pointer rests on a slot this long before its chips open: after the slot has lit.
        static let delay: TimeInterval = 0.12
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

    // MARK: Drop

    enum Drop {
        /// The chosen slot flashes white for one frame.
        static let flash: TimeInterval = 1.0 / 60
        static let pop: TimeInterval = 0.09
        /// The other slots fold into the hub, blurring.
        static let fold: TimeInterval = 0.14
        static let foldTo: CGFloat = 0.45
        static let foldBlur: CGFloat = 10
        /// The chosen slot glides to the centre, shrinking.
        static let glideDelay: TimeInterval = 0.05
        static let glide: TimeInterval = 0.25
        /// The slot's size when it arrives, as a scale of its own.
        static let glideTo: CGFloat = 0.62
        /// Then it flips into the progress ring, with a pop.
        static let ringAt: TimeInterval = 0.30
        static let ringPop: TimeInterval = 0.06
        /// The disc shrinks behind it to the ring's backing.
        static let discDelay: TimeInterval = 0.04
        static let disc: TimeInterval = 0.26
        /// The result chip takes over the ring at this moment, at `BloomAnchor`; the panel hides.
        static let handoff: TimeInterval = 0.38
        /// The ring: a clover-green disc with a white ring on it.
        static let carrySide: CGFloat = 64
        static let ringSide: CGFloat = 56
        static let ringWidth: CGFloat = 3
        static let ringOpacity: Double = 0.9
        static let trackOpacity: Double = 0.2
    }

    // MARK: Cancel

    enum Cancel {
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
        if e.reduce { return Look(opacity: phase(now, e.openedAt, fade)) }
        let p = settle(phase(now, e.openedAt, Open.disc))
        return Look(scale: lerp(Open.discFrom, 1, p), opacity: clamp(phase(now, e.openedAt, Open.disc) * 4))
    }

    /// The centre circle with the picture.
    static func hub(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let drop = e.drop { return foldLook(e, now: now, since: drop.at, towards: .zero) }
        if let cancel = e.cancelAt { return cancelLook(e, now: now, since: cancel) }
        if e.reduce { return Look(opacity: phase(now, e.openedAt, fade)) }
        let p = settle(phase(now, e.openedAt, Open.hub))
        return Look(scale: lerp(Open.hubFrom, 1, p), blur: lerp(Open.hubBlur, 0, p),
                    opacity: clamp(phase(now, e.openedAt, Open.hub) * 3))
    }

    /// The size capsule on the centre circle.
    static func capsule(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let drop = e.drop { return foldLook(e, now: now, since: drop.at, towards: .zero) }
        if let cancel = e.cancelAt { return cancelLook(e, now: now, since: cancel) }
        let start = max(e.openedAt, e.slotsAt) + (e.reduce ? 0 : Open.capsuleDelay)
        if e.reduce { return Look(opacity: phase(now, start, fade)) }
        let p = settle(phase(now, start, Open.capsule))
        return Look(scale: lerp(1.12, 1, p), blur: lerp(10, 0, p), opacity: clamp(phase(now, start, Open.capsule) * 3))
    }

    /// The ring of light: its radius, opacity and line width, or nil when it's done.
    static func lightRing(_ e: BloomEvents, now: TimeInterval) -> (radius: CGFloat, opacity: Double, width: CGFloat)? {
        guard !e.reduce, e.drop == nil, e.cancelAt == nil, e.openedAt.isFinite else { return nil }
        let t = (now - e.openedAt) / Open.ring
        guard t >= 0, t < 1 else { return nil }
        let p = settle(t)
        // Bright almost at once, then fades as it travels.
        let opacity = Open.ringPeak * clamp(t / 0.12) * (1 - exit(t))
        return (lerp(Open.ringFrom, Open.ringTo, p), opacity, lerp(2.2, 0.8, p))
    }

    // MARK: Slots

    /// A slot's look: where it is in its unfold, its pop and dimming. `count` slots.
    /// `center` is the slot's middle in clover coordinates, for folding towards the hub.
    static func slot(_ i: Int, count: Int, center: CGPoint, _ e: BloomEvents, now: TimeInterval) -> (look: Look, fill: SlotFill) {
        if let drop = e.drop {
            if drop.slot == i { return carrySlot(center: center, e, now: now, drop: drop) }
            return (foldLook(e, now: now, since: drop.at, towards: center), .frosted)
        }
        if let cancel = e.cancelAt { return (foldLook(e, now: now, since: cancel, towards: center, duration: Cancel.duration), .frosted) }
        var look = unfold(i, center: center, e, now: now)
        let fill: SlotFill = e.lit == i ? .lit : .frosted
        if e.lit == i {
            if !e.reduce { look.scale *= litScale(e, now: now) }
        } else {
            if e.unlit == i, !e.reduce {
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
        let t = now - e.litAt
        if !e.litAt.isFinite || t >= Hover.popRise + Hover.popSettle { return Hover.rest }
        if t < Hover.popRise { return lerp(1, Hover.peak, settle(t / Hover.popRise)) }
        return lerp(Hover.peak, Hover.rest, settle((t - Hover.popRise) / Hover.popSettle))
    }

    /// 0 when nothing is lit, 1 when the others are fully dimmed.
    static func dimAmount(_ e: BloomEvents, now: TimeInterval) -> Double {
        if e.lit != nil {
            return e.reduce ? phase(now, e.dimAt, fade) : settle(phase(now, e.dimAt, Hover.dim))
        }
        return 1 - (e.reduce ? phase(now, e.undimAt, fade) : exit(phase(now, e.undimAt, Hover.undim)))
    }

    /// The glow under the lit slot: scale and opacity, breathing.
    static func glow(_ e: BloomEvents, now: TimeInterval) -> (scale: CGFloat, opacity: Double)? {
        guard e.lit != nil, e.drop == nil, e.cancelAt == nil else { return nil }
        if e.reduce { return (1, phase(now, e.litAt, fade)) }
        let t = now - e.litAt
        let breath = e.litAt.isFinite ? sin(2 * .pi * t / Hover.breath) : 0
        let rise = settle(phase(now, e.litAt, Hover.glowIn))
        return (litScale(e, now: now) * (1 + Hover.breathAmount * CGFloat(breath)), rise * (0.9 + 0.1 * breath))
    }

    /// A ripple's scale, opacity and line width, or nil when it has gone.
    static func ripple(_ r: BloomEvents.Ripple, _ e: BloomEvents, now: TimeInterval) -> (scale: CGFloat, opacity: Double, width: CGFloat)? {
        guard !e.reduce, e.drop == nil, e.cancelAt == nil else { return nil }
        let t = (now - r.at) / Hover.ripple
        guard t >= 0, t < 1 else { return nil }
        let p = settle(t)
        return (Hover.rest * (1 + Hover.rippleGrow * CGFloat(p)), Hover.rippleOpacity * (1 - p), lerp(1.6, 0.6, p))
    }

    // MARK: Chips

    /// A chip being born: `rank` is its place in the order, nearest the pointer first, and
    /// `since` when its row opened.
    static func chipIn(rank: Int, since: TimeInterval, _ e: BloomEvents, now: TimeInterval) -> Look {
        let start = since + (e.reduce ? 0 : Double(rank) * Chips.stagger)
        if e.reduce { return Look(opacity: phase(now, start, fade)) }
        let raw = phase(now, start, Chips.settle)
        let p = settle(raw)
        return Look(scale: lerp(Chips.bornScale, 1, p), blur: lerp(Chips.bornBlur, 0, p), opacity: clamp(raw * 3))
    }

    /// A chip shrinking back into its slot: `towards` is the slot's rim point relative to the chip.
    static func chipOut(towards: CGVector, _ e: BloomEvents, now: TimeInterval) -> Look? {
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
        guard !e.reduce, at.isFinite else { return 1 }
        let t = now - at
        let rise = Chips.litPop * 0.3
        if t < 0 || t >= Chips.litPop { return 1 }
        if t < rise { return lerp(1, Chips.litPeak, settle(t / rise)) }
        return lerp(Chips.litPeak, 1, settle((t - rise) / (Chips.litPop - rise)))
    }

    /// Chips during a drop or a cancel: they fold away with the others.
    static func chipsLeaving(_ e: BloomEvents, now: TimeInterval) -> Look? {
        guard let since = e.drop?.at ?? e.cancelAt else { return nil }
        let raw = phase(now, since, e.reduce ? fade : Drop.fold)
        if e.reduce { return Look(opacity: 1 - raw) }
        let p = exit(raw)
        return Look(scale: lerp(1, Chips.leaveScale, p), blur: lerp(0, Drop.foldBlur, p), opacity: 1 - p)
    }

    // MARK: Tray

    /// The tray itself, growing out of the More slot.
    static func tray(_ e: BloomEvents, now: TimeInterval) -> Look {
        if let closing = e.trayClosingAt ?? e.drop?.at ?? e.cancelAt {
            let raw = phase(now, closing, e.reduce ? fade : Tray.close)
            if e.reduce { return Look(opacity: 1 - raw) }
            let p = exit(raw)
            return Look(scale: lerp(1, Tray.bornScale, p), blur: lerp(0, Tray.bornBlur * 0.6, p), opacity: 1 - p)
        }
        if e.reduce { return Look(opacity: phase(now, e.trayAt, fade)) }
        let raw = phase(now, e.trayAt, Tray.settle)
        let p = settle(raw)
        return Look(scale: lerp(Tray.bornScale, 1, p), blur: lerp(Tray.bornBlur, 0, p), opacity: clamp(raw * 4))
    }

    /// A pill in the tray, born in turn.
    static func pill(_ i: Int, _ e: BloomEvents, now: TimeInterval) -> Look {
        if e.reduce { return .still }
        let start = e.trayAt + Tray.pillDelay + Double(i) * Tray.pillStagger
        let raw = phase(now, start, Tray.pill)
        let p = settle(raw)
        return Look(scale: lerp(Tray.pillBornScale, 1, p), blur: lerp(Tray.pillBornBlur, 0, p), opacity: clamp(raw * 3))
    }

    // MARK: Drop and cancel

    /// The carried slot: flash and pop, glide to the centre shrinking, then the ring.
    static func carrySlot(center: CGPoint, _ e: BloomEvents, now: TimeInterval, drop: BloomEvents.Drop) -> (look: Look, fill: SlotFill) {
        let t = now - drop.at
        let flash = t < Drop.flash && drop.chip == nil && drop.pill == nil
        if e.reduce {
            return (Look(opacity: 1 - phase(t, 0, fade)), flash ? .flash : .lit)
        }
        if t >= Drop.ringAt { return (.hidden, .lit) }
        // The pop, from wherever it rested.
        let pop: CGFloat = t < Drop.pop ? lerp(Hover.peak, Hover.rest, settle(t / Drop.pop)) : Hover.rest
        let p = settle(phase(t, Drop.glideDelay, Drop.glide))
        let s = pop * lerp(1, Drop.glideTo, p)
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
        let u = t - Drop.ringAt
        let rise = Drop.ringPop * 0.35
        let s: CGFloat = u < rise ? lerp(1, Hover.peak, settle(u / rise))
            : lerp(Hover.peak, 1, settle((u - rise) / (Drop.ringPop - rise)))
        return Look(scale: s)
    }

    /// Something folding into the hub: the other slots on a drop, everything on a cancel.
    static func foldLook(_ e: BloomEvents, now: TimeInterval, since: TimeInterval, towards center: CGPoint,
                         duration: TimeInterval = Drop.fold) -> Look {
        let raw = phase(now, since, e.reduce ? fade : duration)
        if e.reduce { return Look(opacity: 1 - raw) }
        let p = exit(raw)
        let s = lerp(1, Drop.foldTo, p)
        // Scaled about the disc's centre, so it moves in as it shrinks.
        return Look(scale: s, offset: CGSize(width: center.x * (s - 1), height: center.y * (s - 1)),
                    blur: lerp(0, Drop.foldBlur, p), opacity: 1 - p)
    }

    /// The disc, hub and capsule on a cancel: they shrink away, blurred.
    static func cancelLook(_ e: BloomEvents, now: TimeInterval, since: TimeInterval) -> Look {
        let raw = phase(now, since, e.reduce ? fade : Cancel.duration)
        if e.reduce { return Look(opacity: 1 - raw) }
        let p = exit(raw)
        return Look(scale: lerp(1, Cancel.shrinkTo, p), blur: lerp(0, Cancel.blur, p), opacity: 1 - p)
    }

    // MARK: Quiet

    /// The last moment anything moves, for pausing the frame clock. Lit slots breathe
    /// forever, so they are handled by the caller.
    static func busyUntil(_ e: BloomEvents, count: Int) -> TimeInterval {
        var end = max(e.openedAt + Open.ring, max(e.slotsAt, e.openedAt) + Open.slot + Open.slotStagger * Double(count))
        end = max(end, max(e.openedAt, e.slotsAt) + Open.capsuleDelay + Open.capsule)
        end = max(end, e.litAt + Hover.popRise + Hover.popSettle, e.unlitAt + Hover.leave)
        end = max(end, e.dimAt + Hover.dim, e.undimAt + Hover.undim)
        end = max(end, (e.ripples.map(\.at).max() ?? -.infinity) + Hover.ripple)
        end = max(end, e.chipsAt + Chips.settle + Chips.stagger * Double(e.chipRank.count))
        end = max(end, e.pillChipsAt + Chips.settle + Chips.stagger * Double(e.pillChipRank.count))
        end = max(end, e.closingAt + Chips.leave, e.litChipAt + Chips.litPop, e.litPillAt + Chips.litPop)
        end = max(end, e.trayAt + Tray.pillDelay + Tray.pill + Tray.pillStagger * 12, (e.trayClosingAt ?? -.infinity) + Tray.close)
        end = max(end, (e.drop?.at ?? -.infinity) + Drop.handoff, (e.cancelAt ?? -.infinity) + Cancel.duration)
        return end + (e.reduce ? fade : 0)
    }
}
