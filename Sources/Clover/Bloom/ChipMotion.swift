import CoreGraphics
import Foundation

/// Every timing, size and curve of the result chip, in one place. Times are in seconds.
///
/// The house rules: no bounce, a fast start and a long soft landing,
/// blur as a material, state changes that flip in one frame with a small pop, exits
/// faster than entrances.
enum ChipMotion {
    // MARK: Sizes

    /// 400 pt wide, for room around the name beside Undo, Copy and ✕ (Irfan, 22 Oct 2026).
    static let chipSize = CGSize(width: 400, height: 68)
    /// The slot at the chip's leading edge that holds the ring, and later the thumbnail.
    static let slot: CGFloat = 44
    /// The ring the clover leaves at its hub, so the chip can pick it up.
    static let dropRingDiameter: CGFloat = 56
    static let ringLineWidth: CGFloat = 3
    static let ringOpacity = 0.9
    static let trackOpacity = 0.2
    /// In Light the ring is dark, so it reads on the frosted chip and the hub's light glass.
    static let lightRingOpacity = 0.72
    static let lightTrackOpacity = 0.12

    // MARK: Entrance

    /// With a clover behind it, the chip waits this long after the drop. The clover's own
    /// ring is on screen until then, so the two never show at once.
    static var ringAppearDelay: TimeInterval { Motion.Drop.handoff }
    /// The ring grows into the chip.
    static let grow = 0.30
    /// Without a clover, the chip is born blurred, a little large, and sharpens.
    static let bornDuration = 0.30
    static let bornBlur: CGFloat = 12
    static let bornScale: CGFloat = 1.10
    /// The words are born a little after the shape, blurred and large, and sharpen.
    /// Words fading in on a delay left the chip empty at first. Off: the words are there
    /// from the first frame, and the result shows all at once when it is ready.
    static let textAnimated = false
    static let textStart = 0.10
    static let textDuration = 0.20
    static let textBlur: CGFloat = 6
    static let textScale: CGFloat = 1.06

    // MARK: While it runs

    /// How closely the ring follows the real progress. The ring never goes backwards.
    static let progressLag = 0.18
    /// A job still running after this long sends its chip up under the menu bar icon.
    /// Off (Irfan, 23 Nov 2026: "the pill should be exactly at the centre of the clover;
    /// sometimes it moves to the top of the screen"): a long job's pill stays where the
    /// clover was instead of going up under the menu bar icon.
    static let dockEnabled = false
    static let dockAfter = 1.5
    static let dockDuration = 0.35

    // MARK: Ending

    /// The ring closes before the chip flips.
    static let ringClose = 0.16
    /// The new picture is there in one frame, at this size, and settles back.
    static let popScale: CGFloat = 1.08
    static let popDuration = 0.24
    /// The words of the result come in after the flip.
    static let resultTextDelay = 0.06
    static let failureTextDelay = 0.20
    /// The green ripple when a job is done. Off for now, until the animation pass.
    static let rippleEnabled = false
    static let rippleDuration = 0.50
    /// How far the ripple spreads past the chip's edge.
    static let rippleSpread: CGFloat = 22

    /// The Mac's wrong-password shake: swings, how far the first one goes, how long.
    static let shakeSwings = 3.0
    static let shakeAmplitude: CGFloat = 8
    static let shakeDuration = 0.30

    /// After Copy, its button shows a checkmark this long.
    static let copiedHold = 1.2

    static let exitDuration = 0.16
    static let exitBlur: CGFloat = 8
    static let exitScale: CGFloat = 0.92
    /// Reduce motion: every change is a fade this long.
    static let reducedFade = 0.15
    /// When chips are added or leave, the others glide to their places.
    static let reflowDuration = 0.25

    // MARK: Feedback

    static let soundName = "Glass"
    static let soundVolume: Float = 0.3

    // MARK: Curves

    /// A fast start and a long landing, with no overshoot: 75 % of the way by 47 % of the time
    /// (140 ms of a 300 ms move).
    static let sharpness = 2.46

    static func out(_ t: Double, over duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let u = min(max(t / duration, 0), 1)
        return (1 - exp(-sharpness * u)) / (1 - exp(-sharpness))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    /// 108 % at the instant of the flip, settling to 100 % without going under.
    static func pop(_ since: Double) -> CGFloat {
        1 + (popScale - 1) * CGFloat(1 - out(since, over: popDuration))
    }

    /// Sideways offset in points: swings that die away, the first one reaching `shakeAmplitude`.
    static func shake(_ since: Double) -> CGFloat {
        let u = since / shakeDuration
        guard u > 0, u < 1 else { return 0 }
        let firstPeak = 1 - 1 / (4 * shakeSwings)
        return shakeAmplitude * CGFloat(sin(2 * Double.pi * shakeSwings * u) * (1 - u) / firstPeak)
    }
}

/// What the chip looks like at one instant. The default is the chip at rest.
struct ChipValues: Equatable {
    /// Hidden before the clover has handed over.
    var opacity = 1.0
    var blur: CGFloat = 0
    var scale: CGFloat = 1
    var width: CGFloat = ChipMotion.chipSize.width
    /// The chip's centre from its place in the stack: the clover's ring while it grows, and the shake.
    var offset = CGSize.zero
    /// The ring's outer diameter. It starts at the clover's 56 pt.
    var ringDiameter: CGFloat = ChipMotion.slot
    /// nil: the display's own progress.
    var ringProgress: Double?
    /// The buttons, born with the words and then left alone by the flip.
    var controlsOpacity = 1.0
    /// The words and the glyph in the ring.
    var textOpacity = 1.0
    var textBlur: CGFloat = 0
    var textScale: CGFloat = 1
    /// The picture in the leading slot.
    var pop: CGFloat = 1
    /// Still showing the running chip: the result has not flipped in yet.
    var showsRunning = false
    /// 0...1 over the ripple, nil when there is none.
    var ripple: Double?
    /// Seconds since a finished chip's border beam started, nil when there is none.
    var beamAge: Double?
    /// Nothing travels or pops: set by reduce motion.
    var reduced = false

    static let rest = ChipValues()

    var isHidden: Bool { opacity <= 0.001 }
    var isFullSize: Bool { width >= ChipMotion.chipSize.width - 0.5 }
}

/// One chip's clock: when it appears, how far its ring has got, when it flips to the
/// result, when it leaves. `values(at:)` turns that into what is drawn, for any time, so
/// the live chip and the pictures made for checking use the same numbers.
///
/// Times are seconds since the chip was made (the moment of the drop).
struct ChipPlayback {
    struct Ending: Equatable {
        var kind: ChipDisplay.Kind
        /// When the picture flips to the result.
        var at: Double
    }

    let reduced: Bool
    /// Where the clover's ring was, from this chip's centre. nil: no clover, so a blur-born entrance.
    let ringStart: CGSize?
    let appearAt: Double

    private var from = 0.0
    private var fromAt = 0.0
    private var target = 0.0
    private(set) var endedAt: Double?
    private(set) var ending: Ending?
    private(set) var exitAt: Double?
    private var slotFrom = 0.0
    private var slotTo = 0.0
    private var slotAt = -10.0

    init(reduced: Bool, ringStart: CGSize?, slot: Int = 0) {
        self.reduced = reduced
        self.ringStart = ringStart
        appearAt = ringStart == nil ? 0 : ChipMotion.ringAppearDelay
        slotFrom = Double(slot)
        slotTo = Double(slot)
    }

    // MARK: Events

    /// The job's progress. The ring follows it, and never goes back.
    mutating func progress(_ value: Double, at t: Double) {
        let now = displayed(at: t)
        from = now
        fromAt = t
        target = max(target, min(max(value, 0), 1))
    }

    /// The job ended with `kind`. The first ending waits for the ring to close and the chip
    /// to be grown; a later one (undone) shows at once.
    mutating func end(_ kind: ChipDisplay.Kind, at t: Double) {
        if let current = ending {
            ending = Ending(kind: kind, at: max(t, current.at))
            return
        }
        endedAt = t
        let grown = appearAt + (reduced ? ChipMotion.reducedFade : ChipMotion.grow)
        let closes = kind == .done || kind == .partial
        let ready = closes && !reduced ? t + ChipMotion.ringClose : t
        ending = Ending(kind: kind, at: max(ready, grown))
    }

    mutating func leave(at t: Double) {
        if exitAt == nil { exitAt = t }
    }

    mutating func setSlot(_ index: Int, at t: Double) {
        let now = slot(at: t)
        slotFrom = now
        slotTo = Double(index)
        slotAt = t
    }

    // MARK: Reading

    func displayed(at t: Double) -> Double {
        target - (target - from) * exp(-max(t - fromAt, 0) / ChipMotion.progressLag)
    }

    /// The chip's place in the stack, between slots while it glides.
    func slot(at t: Double) -> Double {
        ChipMotion.lerp(slotFrom, slotTo, ChipMotion.out(t - slotAt, over: ChipMotion.reflowDuration))
    }

    func ringProgress(at t: Double) -> Double {
        // Taking the clover's empty ring over, it starts empty too and fills as the chip
        // grows, however far the job has got: no jump at the handoff.
        let fill = ringStart != nil && !reduced ? ChipMotion.out(t - appearAt, over: ChipMotion.grow) : 1
        return fill * jobProgress(at: t)
    }

    private func jobProgress(at t: Double) -> Double {
        guard let endedAt else { return displayed(at: t) }
        guard let kind = ending?.kind, kind == .done || kind == .partial else { return displayed(at: min(t, endedAt)) }
        let start = max(endedAt, appearAt)
        let u = ChipMotion.out(t - start, over: ChipMotion.ringClose)
        return ChipMotion.lerp(displayed(at: start), 1, u)
    }

    /// True when nothing is moving, so the clock can stop.
    func isSettled(at t: Double) -> Bool {
        if t < appearAt + ChipMotion.textStart + ChipMotion.textDuration + 0.1 { return false }
        if let exitAt { return t > exitAt + ChipMotion.exitDuration + 0.05 }
        if t < slotAt + ChipMotion.reflowDuration + 0.05 { return false }
        if let ending {
            return t > ending.at + ChipMotion.failureTextDelay + ChipMotion.textDuration + 0.1
                + (ending.kind == .done && ChipMotion.rippleEnabled ? ChipMotion.rippleDuration : 0)
                && !(ending.kind == .done && !reduced && BorderBeams.available && t < ending.at + BorderBeams.duration + 0.05)
        }
        return abs(displayed(at: t) - target) < 0.0005
    }

    func values(at t: Double) -> ChipValues {
        var v = ChipValues()
        if t < appearAt {
            v.opacity = 0
            v.showsRunning = true
            return v
        }
        v.reduced = reduced
        let u = t - appearAt
        let flipped = ending.map { t >= $0.at } ?? false
        v.showsRunning = !flipped
        v.ringProgress = ringProgress(at: t)

        // Entrance.
        var words = 1.0
        var wordsBlur = 0.0
        var wordsScale = 1.0
        func born(_ since: Double) {
            guard ChipMotion.textAnimated else {
                words = 1
                wordsBlur = 0
                wordsScale = 0
                return
            }
            let e = ChipMotion.out(since, over: ChipMotion.textDuration)
            words = ChipMotion.out(since, over: ChipMotion.textDuration * 0.6)
            wordsBlur = (1 - e)
            wordsScale = (1 - e)
        }
        if reduced {
            v.opacity = min(u / ChipMotion.reducedFade, 1)
            words = v.opacity
        } else if let start = ringStart {
            let e = ChipMotion.out(u, over: ChipMotion.grow)
            v.width = ChipMotion.lerp(ChipMotion.dropRingDiameter, ChipMotion.chipSize.width, e)
            v.offset = CGSize(width: start.width * CGFloat(1 - e), height: start.height * CGFloat(1 - e))
            v.ringDiameter = ChipMotion.lerp(ChipMotion.dropRingDiameter, ChipMotion.slot, e)
            born(u - ChipMotion.textStart)
            if ChipMotion.textAnimated, u < ChipMotion.textStart { words = 0 }
        } else {
            let e = ChipMotion.out(u, over: ChipMotion.bornDuration)
            v.opacity = ChipMotion.out(u, over: ChipMotion.bornDuration * 0.4)
            v.blur = ChipMotion.bornBlur * CGFloat(1 - e)
            v.scale = 1 + (ChipMotion.bornScale - 1) * CGFloat(1 - e)
            born(u - 0.06)
            if ChipMotion.textAnimated, u < 0.06 { words = 0 }
        }

        v.controlsOpacity = words

        // The result: a flip in one frame, then the words.
        if let ending, flipped {
            let since = t - ending.at
            switch ending.kind {
            case .undone:
                // A short fade, nothing more.
                words = min(since / ChipMotion.reducedFade, 1)
                wordsBlur = 0
                wordsScale = 0
            case .failed where !reduced:
                v.pop = ChipMotion.pop(since)
                v.offset.width += ChipMotion.shake(since)
                born(since - ChipMotion.failureTextDelay)
                if ChipMotion.textAnimated, since < ChipMotion.failureTextDelay { words = 0 }
            default:
                if reduced {
                    words = min(since / ChipMotion.reducedFade, 1)
                    wordsBlur = 0
                    wordsScale = 0
                } else {
                    v.pop = ChipMotion.pop(since)
                    born(since - ChipMotion.resultTextDelay)
                    if ChipMotion.textAnimated, since < ChipMotion.resultTextDelay { words = 0 }
                    if ChipMotion.rippleEnabled, ending.kind == .done, since < ChipMotion.rippleDuration {
                        v.ripple = since / ChipMotion.rippleDuration
                    }
                    // Done: the border beam goes twice round the chip, fading out.
                    if ending.kind == .done, BorderBeams.available, since < BorderBeams.duration {
                        v.beamAge = since
                    }
                }
            }
        }
        v.textOpacity = words
        v.textBlur = ChipMotion.textBlur * CGFloat(wordsBlur)
        v.textScale = 1 + (ChipMotion.textScale - 1) * CGFloat(wordsScale)

        // Exit: faster than the entrance.
        if let exitAt, t >= exitAt {
            let x = t - exitAt
            if reduced {
                v.opacity *= max(1 - x / ChipMotion.reducedFade, 0)
            } else {
                let e = ChipMotion.out(x, over: ChipMotion.exitDuration)
                v.opacity *= 1 - e
                v.blur += ChipMotion.exitBlur * CGFloat(e)
                v.scale *= 1 - (1 - ChipMotion.exitScale) * CGFloat(e)
            }
        }
        return v
    }
}
