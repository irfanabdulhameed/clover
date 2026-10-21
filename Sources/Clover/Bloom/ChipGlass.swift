import AppKit
import SwiftUI

// Liquid Glass is in the macOS 26 SDK. The SDK 15 build that draws pictures for checking
// (SDKROOT=.../MacOSX15.sdk) does not have it, and live glass never shows in pictures anyway.
// FoundationModels arrived with the same SDK, so its presence tells the two apart.
// (`Glass` in this app is Clover's frosted look; the system's is `SwiftUI.Glass`.)

/// Holds all the chips of a stack, so the system's glass can blend between them as they
/// move. Before macOS 26 it holds them and does nothing else.
struct ChipGlassContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.bloomSnapshot) private var snapshot

    var body: some View {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), !snapshot {
            // Closer than this and two chips run together; the stack's 8 pt gap keeps them apart.
            GlassEffectContainer(spacing: 6) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// The chip's body: a Liquid Glass capsule on macOS 26, the frosted look before it.
/// `clover` tints it with the clover's green, as the clover's own glass is; otherwise it is clear.
struct ChipGlassBackground: View {
    var cornerRadius: CGFloat
    var clover: Bool
    @Environment(\.bloomSnapshot) private var snapshot
    @Environment(\.colorScheme) private var scheme

    /// True when this Mac and this build have Liquid Glass.
    static var isLiquid: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    var body: some View {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), !snapshot {
            let regular = SwiftUI.Glass.regular
            Color.clear
                .glassEffect(clover ? regular.tint(BloomStyle.green(scheme).opacity(0.28)) : regular, in: Capsule())
        } else {
            frosted
        }
        #else
        frosted
        #endif
    }

    private var frosted: some View {
        Glass(cornerRadius: cornerRadius, tint: clover ? BloomStyle.green(scheme).opacity(0.10) : nil, bright: true)
    }
}

/// The progress ring: 3 pt, white at 90 % over a track at 20 %. The same ring the clover
/// leaves at its hub, so the chip can pick it up.
struct ChipRing: View {
    var progress: Double
    var diameter: CGFloat

    var body: some View {
        let inset = ChipMotion.ringLineWidth / 2
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(Color.white.opacity(ChipMotion.trackOpacity), lineWidth: ChipMotion.ringLineWidth)
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(Color.white.opacity(ChipMotion.ringOpacity),
                        style: StrokeStyle(lineWidth: ChipMotion.ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        // A hairline of shadow keeps a white ring readable over light glass.
        .shadow(color: .black.opacity(0.22), radius: 1.2, y: 0.5)
    }
}

/// One Clover-green ripple leaving the chip: a ring that spreads past its edge and fades,
/// with a soft glow under it. `age` runs 0 to 1 over the ripple.
struct ChipRipple: View {
    var age: Double
    var width: CGFloat
    var color: Color

    var body: some View {
        let e = ChipMotion.out(age, over: 1)
        let spread = ChipMotion.rippleSpread * CGFloat(e)
        let height = ChipMotion.chipSize.height
        ZStack {
            Capsule()
                .fill(color.opacity(0.30 * (1 - e)))
                .frame(width: width + spread, height: height + spread)
                .blur(radius: 9)
            Capsule()
                .stroke(color.opacity(0.75 * (1 - e)), lineWidth: 2.2 - 1.5 * CGFloat(e))
                .frame(width: width + spread * 2, height: height + spread * 2)
        }
        .allowsHitTesting(false)
    }
}
