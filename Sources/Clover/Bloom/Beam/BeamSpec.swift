// From Border Beam (github.com/Jakubantalik/Libraries.dev, packages/border-beam,
// ports/ios/BorderBeamKit), under its MIT License:
//
// Copyright (c) 2026 Jakub Antalik
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or
// substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
// BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// Vendored for Clover: internal instead of public; see the notes in the file where changed.

import Foundation
import CoreGraphics

/// Decoded `beam-spec.json` — the platform-neutral spec generated from the web
/// library (`npm run spec` in the repo root). All hand-tuned palette/preset/
/// oscillator data comes from here; nothing visual is hard-coded in Swift.
struct BeamSpec: Decodable {
    struct SizeConfig: Decodable {
        let borderRadius: Double
        let borderWidth: Double
        let width: Double?
        let height: Double?
    }

    struct ThemeColors: Decodable {
        let strokeOpacity: Double
        let innerOpacity: Double
        let bloomOpacity: Double
        /// CSS color string, e.g. "rgba(255, 255, 255, 0.27)" or "transparent".
        let innerShadow: String
        let saturation: Double
        let brightness: Double?
        let hairlineOpacity: Double?
    }

    struct GradientBlob: Decodable {
        /// CSS color string "rgb(r, g, b)" / "rgba(r, g, b, a)".
        let color: String
        /// "x% y%" position (values may be negative or >100).
        let pos: String
        /// "Wpx Hpx" ellipse *radii* per CSS explicit-size radial gradients.
        let size: String
    }

    struct SpikePair: Decodable {
        let primary: String
        let secondary: String
    }

    struct BorderPalette: Decodable {
        let border: [GradientBlob]
        let spike: SpikePair
        let spikeLt: SpikePair
    }

    struct SmallPalette: Decodable {
        let border: [GradientBlob]
        let inner: [GradientBlob]
    }

    struct LineBlob: Decodable {
        let color: String
        let sizeW: Double
        let sizeH: Double
        let offsetX: Double
        let offsetY: Double
    }

    struct Palettes: Decodable {
        let border: [String: BorderPalette]
        let small: [String: SmallPalette]
        let line: [String: [String: [LineBlob]]]
        let lineInner: [String: [LineBlob]]
    }

    struct InnerGradientDerivation: Decodable {
        let sizeScale: Double
        let alpha: Double
        let monoAlpha: Double
    }

    struct InnerShadowBlur: Decodable {
        let md: Double
        let sm: Double
    }

    struct Rotate: Decodable {
        /// [position%, alpha] stop pairs on white (dark) / black (light).
        let whiteGradientStops: [String: [[Double]]]
        let bloomGradientStops: [String: [[Double]]]
        let beamMaskStops: [[Double]]
        let smallMaskStops: [[Double]]
        let innerGradientDerivation: InnerGradientDerivation
        let innerEdgeMaskPx: Double
        let innerShadowBlur: InnerShadowBlur
        let bloomBlurPx: Double
    }

    struct Oscillator: Decodable {
        let prop: String
        let a: Double
        let b: Double
        let period: Double
        let delay: Double
        let unit: String
    }

    // ── Line family ──

    struct KeyframeDurationScales: Decodable {
        let travel: Double
        let edgeFade: Double
        let breathe: Double
        let spike: Double
        let spike2: Double
    }

    struct KeyframeTables: Decodable {
        struct Travel: Decodable {
            let x: [[Double]]
            let w: [[Double]]
        }
        let travel: Travel
        let edgeFade: [[Double]]
        let breathe: [[Double]]
        let spike: [[Double]]
        let spike2: [[Double]]
        let durationScale: KeyframeDurationScales
    }

    struct MaskEllipse: Decodable {
        let w: Double
        let h: Double
        /// [posPercent, alpha] of the soft middle stop.
        let softStop: [Double]
    }

    struct WhiteHighlight: Decodable {
        let w: Double
        let h: Double
        let yOffset: Double
        /// [posPercent, alpha] pairs.
        let stops: [[Double]]
        let onBlack: Bool?
    }

    struct BloomStop: Decodable {
        let r: Double
        let g: Double
        let b: Double
        let a: Double
        let pos: Double
    }

    struct BloomMult: Decodable {
        let base: Double
        /// 'spike' | 'spike2' | 'inv-spike' | 'inv-spike2' | 'h' | 'w' | 'one'
        let mult: String
    }

    struct BloomGradient: Decodable {
        /// Fixed x as % of width; nil = travels with the beam x.
        let xPct: Double?
        let yOffPx: Double
        let w: BloomMult
        let h: BloomMult
        let stops: [BloomStop]
    }

    struct Line: Decodable {
        let keyframes: KeyframeTables
        let beamMaskEllipse: MaskEllipse
        let bloomMaskEllipse: MaskEllipse
        let whiteHighlight: [String: WhiteHighlight]
        let bloomGradients: [String: [String: [BloomGradient]]]
        let monoBloomExtraBlurPx: Double
        let bloomBlurPx: Double
    }

    // ── Pulse constants ──

    struct XYScale: Decodable {
        let x: Double
        let y: Double
    }

    struct WHSize: Decodable {
        let w: Double
        let h: Double
    }

    struct ThemedDouble: Decodable {
        let dark: Double
        let light: Double
    }

    struct MinMax: Decodable {
        let min: Double
        let max: Double
    }

    struct OutsideConstants: Decodable {
        let glowScale: XYScale
        let glowBlurPx: ThemedDouble
        let bloomBlurPx: ThemedDouble
        let coreInsetPx: Double
        let bloomInsetPx: Double
        let referenceSize: WHSize
        let scaleClamp: MinMax
    }

    struct CornerAccent: Decodable {
        let sizePx: Double
        let alpha: ThemedDouble
        let fadeStop: Double
    }

    struct PulseThemeSection: Decodable {
        let oscillators: [Oscillator]
        let frozenBloomAlpha: Double
    }

    struct PulseGradientEntry: Decodable {
        let ci: Int
        let region: Int
        let quad: String
        let w: Double
        let h: Double
        let x: String?
        let y: String?
    }

    struct RingMapEntry: Decodable {
        let region: Int
        let quad: String
    }

    struct Pulse: Decodable {
        let ringMap: [RingMapEntry]
        let innerSizes: [[Double]]
        let innerBloom: [PulseGradientEntry]
        let outerCore: [PulseGradientEntry]
        let outerBloom: [PulseGradientEntry]
        let inner: [String: PulseThemeSection]
        let outside: [String: PulseThemeSection]
        let huePeriod: [String: Double]
        let innerBloomBlurPx: Double
        let innerCornerAccent: CornerAccent
        let outsideConstants: OutsideConstants
    }

    struct DurationDefaults: Decodable {
        let line: Double
        let pulse: Double
        let rotate: Double
    }

    struct Defaults: Decodable {
        let duration: DurationDefaults
        let hueRange: Double
        let lineHueRangeCap: Double
        let brightnessFallback: Double
        let fadeInSeconds: Double
        let fadeOutSeconds: Double
        let rotateHueShiftPeriod: Double
        let lineBloomHueShiftPeriod: Double
        let lineBloomHueRangeBonus: Double
        let monoOpacityMultiplier: Double
        let pulseDriverFps: Double
    }

    let specVersion: String
    let defaults: Defaults
    let sizePresets: [String: SizeConfig]
    let sizeThemePresets: [String: [String: ThemeColors]]
    let palettes: Palettes
    let rotate: Rotate
    let line: Line
    let pulse: Pulse

    /// Decoded once from Resources/beam-spec.json, or nil when it isn't there (Clover:
    /// then there is no beam, rather than a crash).
    static let loaded: BeamSpec? = {
        guard let url = ShaderFiles.resource("beam-spec", "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BeamSpec.self, from: data)
    }()

    /// Only read once `BorderBeams.available` has said the spec is there.
    static var shared: BeamSpec { loaded! }
}

// MARK: - CSS value parsing

/// Simple RGBA color parsed from the spec's CSS color strings.
struct BeamRGBA: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let clear = BeamRGBA(r: 0, g: 0, b: 0, a: 0)

    /// Parses "rgb(r, g, b)", "rgba(r, g, b, a)" or "transparent".
    init?(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s == "transparent" {
            self = .clear
            return
        }
        guard s.hasPrefix("rgb") else { return nil }
        let nums = s
            .drop(while: { $0 != "(" }).dropFirst().dropLast()
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count >= 3 else { return nil }
        r = nums[0] / 255
        g = nums[1] / 255
        b = nums[2] / 255
        a = nums.count > 3 ? nums[3] : 1
    }

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// Parses "33% -7.4%" → (0.33, -0.074).
func parsePercentPair(_ value: String) -> CGPoint {
    let parts = value.split(separator: " ")
    func pct(_ s: Substring) -> CGFloat {
        CGFloat(Double(s.replacingOccurrences(of: "%", with: "")) ?? 0) / 100
    }
    guard parts.count == 2 else { return .zero }
    return CGPoint(x: pct(parts[0]), y: pct(parts[1]))
}

/// Parses "70px 40px" → (70, 40).
func parsePixelPair(_ value: String) -> CGSize {
    let parts = value.split(separator: " ")
    func px(_ s: Substring) -> CGFloat {
        CGFloat(Double(s.replacingOccurrences(of: "px", with: "")) ?? 0)
    }
    guard parts.count == 2 else { return .zero }
    return CGSize(width: px(parts[0]), height: px(parts[1]))
}
