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
        // The main demo's colour, its strength, and its rim, which holds until the carry.
        style.palette = .colorful
        style.aberration = 0.78
        style.strength = 0.92
        style.rimStrength = 0.82
        style.rimFade = 3.03
        style.hairlineLinger = 0.47
        style.gatherGlow = 0.33
        style.gatherDots = 1
        style.cornerRadius = BloomGeometry.discRadius
        return style
    }()

    /// The carry to the ring starts this long after the drop: the front has crossed the
    /// clover and the colour on the rim has mostly cleared.
    nonisolated static let carryAfter: TimeInterval = 3.0

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
    @ViewBuilder let content: () -> Content

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

    /// The content with its two blurred copies over it, through the lens as one layer.
    @ViewBuilder private func lensed(field: [Float], lens: Bool, blurred: Bool) -> some View {
        if let library = DistortionWaves.library {
            ZStack {
                content()
                copy(library, radius: Self.nearBlur, from: 0, to: Self.nearBlur, field: field, on: blurred)
                copy(library, radius: style.blur, from: Self.nearBlur, to: style.blur, field: field, on: blurred)
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

    @ViewBuilder private func copy(_ library: ShaderLibrary, radius: Double, from: Double, to: Double, field: [Float], on: Bool) -> some View {
        if on {
            content()
                .compositingGroup()
                .blur(radius: radius)
                .colorEffect(library.waveBlurMask(.floatArray(field), .float(style.blur), .float(style.blurAhead),
                                                  .float(style.blurBehind), .float(from), .float(to)))
                .allowsHitTesting(false)
        }
    }
}
