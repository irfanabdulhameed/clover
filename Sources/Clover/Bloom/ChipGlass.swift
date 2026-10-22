import AppKit
import SwiftUI

// The chip is frosted, not Liquid Glass (Irfan, 22 Oct 2026): clear glass let busy windows
// show through its words. The frosted look is the same in the app and in the pictures drawn
// for checking, except that the pictures can't show the system's blur and use a flat stand-in.

/// Holds all the chips of a stack. (It once let the system's glass blend between them; that
/// container drew the merged glass over the chips' contents, so it holds them and nothing else.)
struct ChipGlassContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

/// The chip's body: frosted glass in its pill shape. The system's blur of what is behind the
/// window, a light veil so the words always read, a lit rim and a soft shadow. `clover`
/// tints it with the clover's green, as the clover's own glass is; otherwise it is clear.
struct ChipGlassBackground: View {
    var cornerRadius: CGFloat
    var clover: Bool
    @Environment(\.bloomSnapshot) private var snapshot
    @Environment(\.colorScheme) private var scheme

    /// The system material under the veil: frosted and solid enough to read on, in both modes.
    static let material = NSVisualEffectView.Material.popover

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        ZStack {
            if snapshot {
                shape.fill(dark ? Color(white: 0.17).opacity(0.94) : Color(white: 0.96).opacity(0.94))
            } else {
                VisualEffectBlur(cornerRadius: cornerRadius, material: ChipGlassBackground.material)
                shape.fill(dark ? Color.black.opacity(0.12) : Color.white.opacity(0.30))
            }
            if clover { shape.fill(BloomStyle.green(scheme).opacity(0.10)) }
            shape.strokeBorder(rim(dark), lineWidth: 0.75)
        }
        .background {
            // A close shadow for the edge and a wide, soft one so the chip floats.
            shape.fill(Color.black.opacity(dark ? 0.32 : 0.16)).blur(radius: 5).offset(y: 2.5)
            shape.fill(Color.black.opacity(dark ? 0.24 : 0.10)).blur(radius: 12).offset(y: 6)
        }
    }

    private func rim(_ dark: Bool) -> LinearGradient {
        let top = Color.white.opacity(dark ? 0.42 : 0.95)
        let bottom = dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Puts the chip's frosted glass behind its content.
struct ChipGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var clover: Bool

    func body(content: Content) -> some View {
        content.background(ChipGlassBackground(cornerRadius: cornerRadius, clover: clover))
    }
}

/// The progress ring: 3 pt, white at 90 % over a track at 20 % in Dark; in Light, dark at
/// 72 % over a track at 12 %, as white vanished on the frosted chip. The same ring the clover
/// leaves at its hub, so the chip can pick it up.
struct ChipRing: View {
    var progress: Double
    var diameter: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let inset = ChipMotion.ringLineWidth / 2
        let dark = scheme == .dark
        let ink = dark ? Color.white : Color.black
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(ink.opacity(dark ? ChipMotion.trackOpacity : ChipMotion.lightTrackOpacity),
                        lineWidth: ChipMotion.ringLineWidth)
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(ink.opacity(dark ? ChipMotion.ringOpacity : ChipMotion.lightRingOpacity),
                        style: StrokeStyle(lineWidth: ChipMotion.ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        // A hairline of shadow keeps the white ring readable over light parts of the glass.
        .shadow(color: .black.opacity(dark ? 0.22 : 0), radius: 1.2, y: 0.5)
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
