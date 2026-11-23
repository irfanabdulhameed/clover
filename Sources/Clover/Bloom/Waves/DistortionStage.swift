import SwiftUI

// Clover's distortion wave: Distortion Waves (see the notice in WaveFront.swift) spreading
// from the chosen leaf across the clover. Its three shaders are in Shaders/DistortionWaves.metal,
// compiled by GitHub into Resources/DistortionWaves.metallib, since the Command Line Tools
// have no Metal compiler.

/// The wave's shaders, style and timing in the drop.
@MainActor
enum DistortionWaves {
    /// The compiled shaders, or nil when the metallib isn't there: then there is no wave.
    nonisolated(unsafe) static let library: ShaderLibrary? = ShaderFiles.library("DistortionWaves")

    nonisolated static var available: Bool { library != nil }

    /// The original's ring from an avatar (`.center`), sized for a card like the disc, with
    /// the colour, colour split and rim of its main demo, as on libraries.dev/waves.
    static let style: DistortionWaveStyle = {
        var style = DistortionWaveStyle(type: .center)
        // The main demo's colour, its strength and colour split.
        style.palette = .colorful
        style.aberration = 0.78
        style.strength = 0.92
        style.rimStrength = 0.82
        style.gatherGlow = 0.33
        style.gatherDots = 1
        // Quick (Irfan, 23 Nov 2026: "after the wave it's stuck for 2-3 seconds"): a short
        // pull, and the rim, hairline and sparks gone within the second after the front
        // has crossed, so the carry to the ring follows straight on.
        style.anticipation = 0.18
        style.rimFade = 1.15
        style.hairlineLinger = 0.1
        style.hairlineFade = 1.0
        style.particleLife = 1.0
        style.cornerRadius = BloomGeometry.discRadius
        return style
    }()

    /// The carry to the ring starts this long after the drop: just after the front has
    /// crossed the clover (about 0.55 s), while the rim's colour fades.
    nonisolated static let carryAfter: TimeInterval = 0.7

    /// The disc's square, which the wave fills.
    static var discSize: CGSize { CGSize(width: BloomGeometry.discRadius * 2, height: BloomGeometry.discRadius * 2) }

    /// The wave in a drop, in the disc's square, or nil before and after it and with
    /// reduce motion. `origin` is the chosen leaf's middle, relative to the disc's centre.
    static func front(_ e: BloomEvents, now: TimeInterval, slot: Int, count: Int) -> (front: WaveFront, source: CGRect)? {
        guard available, let drop = e.drop, !e.reduce else { return nil }
        let t = now - drop.at
        guard t >= 0, t < style.duration else { return nil }
        return front(at: t, slot: slot, count: count, in: discSize)
    }

    /// The wave `t` seconds after it starts, from leaf `slot`, in a square of `size`
    /// centred on the disc.
    static func front(at t: TimeInterval, slot: Int, count: Int, in size: CGSize) -> (front: WaveFront, source: CGRect) {
        let leaf = BloomLayout.leafBounds(slot, of: count)
        let source = leaf.offsetBy(dx: size.width / 2, dy: size.height / 2)
        let front = WaveFront(progress: t / style.duration, source: source, size: size, style: style)
        return (front, source)
    }
}

/// Content seen through the wave: bent, blurred and split into its colours where the
/// front passes, with the colour band, the rim and the sparks over it. The content is
/// plain SwiftUI (system glass can't go through a shader); it stays where it is on both
/// sides of the front.
struct DistortionStage<Content: View>: View {
    let front: WaveFront
    let source: CGRect
    var style = DistortionWaves.style
    /// While set, the content is drawn once, the first time this key is seen, and the
    /// picture goes through the lens: three copies of a picture cost far less a frame than
    /// three of the views. Nil draws the content live, as it changes.
    var freezeKey: Double? = nil
    @ViewBuilder let content: () -> Content

    @State private var frozen = FrozenContent()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    /// The first blurred copy's radius; the second has the style's full radius.
    private static var nearBlur: Double { 7 }

    var body: some View {
        let field = front.packed
        let live = front.time > 0 && front.time < style.duration
        let acting = live && front.energy > 0
        let size = front.size
        ZStack {
            lensed(field: field, lens: acting || (live && front.gravity > 0), blurred: acting)
            if let library = DistortionWaves.library {
                Rectangle()
                    .fill(Color.white)
                    .colorEffect(library.waveBand(
                        .floatArray(field), .floatArray(style.bandPalette),
                        .float(style.lead), .float(style.tail), .float(style.strength),
                        .float(style.rimWidth), .float(style.rimSoftness), .float(style.cornerRadius),
                        .float(style.rimUnevenness), .float(style.rimPulse),
                        .float(style.hairlineWidth), .float(style.hairlineOpacity), .float(style.hairlineWhite),
                        .floatArray(WaveRim.lumps(time: front.time, size: size, cornerRadius: style.cornerRadius, pulse: style.rimPulse))),
                        isEnabled: live)
                    .opacity(live ? 1 : 0)
                    .clipShape(Circle())
                    .allowsHitTesting(false)
            }
            WaveParticles(front: front, source: source, style: style, on: live)
                .clipShape(Circle())
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    /// The content, or its picture while frozen.
    @ViewBuilder private func base() -> some View {
        if let key = freezeKey, let image = frozen.image(for: key, build: snapshot) {
            Image(decorative: image, scale: displayScale)
                .resizable()
                .frame(width: front.size.width, height: front.size.height)
        } else {
            content()
        }
    }

    /// The content drawn once into a picture, as it looks now: plain SwiftUI, with the
    /// frosted stand-in for any system glass, which can't be pictured or go through a shader.
    private func snapshot() -> CGImage? {
        let renderer = ImageRenderer(content: content()
            .frame(width: front.size.width, height: front.size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.bloomSnapshot, true))
        renderer.scale = displayScale
        return renderer.cgImage
    }

    /// The content with its two blurred copies over it, through the lens as one layer. The
    /// copies stay built while hidden when the content is a picture: building them on the
    /// wave's first frame would stall it.
    @ViewBuilder private func lensed(field: [Float], lens: Bool, blurred: Bool) -> some View {
        if let library = DistortionWaves.library {
            let keep = freezeKey != nil
            ZStack {
                base()
                copy(library, radius: Self.nearBlur, from: 0, to: Self.nearBlur, field: field, on: blurred, keep: keep)
                copy(library, radius: style.blur, from: Self.nearBlur, to: style.blur, field: field, on: blurred, keep: keep)
            }
            .compositingGroup()
            // Side 0: the same content on both sides of the front, never covered.
            .layerEffect(library.waveLens(.floatArray(field), .float(style.amplitude), .float(style.lensWidth),
                                          .float(style.aberration), .float(0)),
                         maxSampleOffset: .zero, isEnabled: lens)
        } else {
            content()
        }
    }

    @ViewBuilder private func copy(_ library: ShaderLibrary, radius: Double, from: Double, to: Double, field: [Float],
                                   on: Bool, keep: Bool) -> some View {
        if on || keep {
            base()
                .compositingGroup()
                // No radius while hidden: a hidden copy then costs nothing.
                .blur(radius: on ? radius : 0)
                .colorEffect(library.waveBlurMask(.floatArray(field), .float(style.blur), .float(style.blurAhead),
                                                  .float(style.blurBehind), .float(from), .float(to)),
                             isEnabled: on)
                .opacity(on ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

/// The picture of a frozen stage's content, made once per key.
final class FrozenContent {
    private var key: Double?
    private var image: CGImage?

    @MainActor func image(for key: Double, build: () -> CGImage?) -> CGImage? {
        if self.key != key {
            self.key = key
            image = build()
        }
        return image
    }
}
