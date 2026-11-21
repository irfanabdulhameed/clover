import SwiftUI

// Timings, rim lumps, spark scatter and front shape ported from Distortion Waves
// (github.com/Jakubantalik/Libraries.dev, packages/distortion-waves), under its MIT License:
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

// The drop's distortion wave, after Distortion Waves by Jakub Antalik (libraries.dev/waves,
// MIT): a band of colour leaves the chosen leaf with a wavy, blurred front and a white
// hairline, the leaves it passes bend and soften, colour gathers on the disc's rim in
// uneven lumps, and sparks fly out with it. The original bends the picture itself in a
// Metal shader; Clover is built without the Metal compiler, so the lens is the leaves
// moving and blurring as the front passes, and the band, rim and sparks are drawn in one
// Canvas. Its timeline is the original's, folded into the drop's first 0.45 s.

extension Motion {
    enum Distort {
        /// On: Irfan asked for the libraries.dev wave on a leaf choice (21 Nov 2026). It is
        /// separate from `Drop.waveEnabled`, the thin outer ring he turned off on 22 Oct.
        static let enabled = true
        /// The front leaves the leaf's middle and crosses the disc on the original's curve,
        /// cubic-bezier(0.22, 1, 0.36, 1), running on a little past the far rim.
        static let start: TimeInterval = 0.02
        static let travel: TimeInterval = 0.62
        static let overshoot: CGFloat = 60
        /// The band is at full strength until this far through the travel, gone by the second.
        static let settleStart = 0.18
        static let settleEnd = 0.62
        /// The wavy front: how far it swells in and out, and how many lobes run round it.
        static let swell: CGFloat = 9
        static let lobes = 3.0
        /// The band of colour: ahead of the front and behind it, and how soft it is.
        static let lead: CGFloat = 16
        static let tail: CGFloat = 70
        static let bandBlur: CGFloat = 10
        static let hairline: CGFloat = 1.5
        /// Colour on the rim, where the front has touched it: lumpy, then cleared.
        static let rimWidth: CGFloat = 9
        static let rimBlur: CGFloat = 4
        static let rimClearAt: TimeInterval = 0.31
        static let rimClear: TimeInterval = 0.14
        /// The leaves the front passes: pushed out, swollen and softened, then back.
        static let bendShift: CGFloat = 4
        static let bendScale: CGFloat = 1.04
        static let bendBlur: CGFloat = 1.6
        static let bendWidth: CGFloat = 46
        /// Sparks: how many, how long each lives, how far they spread.
        static let sparks = 30
        static let sparkLife: TimeInterval = 0.42
        static let sparkSize: CGFloat = 1.9
        static let sparkSpread: CGFloat = 0.72
    }

    /// The front at a moment, or nil before and after it, and with reduce motion. `origin`
    /// is the chosen leaf's middle, relative to the disc's centre.
    static func distortWave(_ e: BloomEvents, now: TimeInterval, origin: CGPoint) -> RippleFront? {
        guard Distort.enabled, let drop = e.drop, !e.reduce else { return nil }
        let since = now - drop.at - Distort.start
        guard since >= 0, since + Distort.start < Distort.rimClearAt + Distort.rimClear else { return nil }
        let x = clamp(since / Distort.travel)
        let reach = waveReach(origin) + Distort.overshoot
        let energy = 1 - smoothstep(Distort.settleStart, Distort.settleEnd, x)
        let rimKept = 1 - smoothstep(0, 1, (since - Distort.rimClearAt + Distort.start) / Distort.rimClear)
        return RippleFront(radius: reach * CGFloat(Distort.ease(x)), energy: energy, rimKept: rimKept,
                           time: since, moved: Distort.ease(x))
    }

    /// How much a leaf at `center` bends as the front passes it: out from the origin,
    /// swollen and soft while the front is on it.
    static func bend(_ center: CGPoint, origin: CGPoint, _ e: BloomEvents, now: TimeInterval) -> Look {
        guard let front = distortWave(e, now: now, origin: origin) else { return .still }
        let dx = center.x - origin.x, dy = center.y - origin.y
        let distance = hypot(dx, dy)
        guard distance > 1 else { return .still }
        let u = (distance - front.radius) / Distort.bendWidth
        let k = CGFloat(exp(-Double(u * u)) * front.energy)
        return Look(scale: 1 + (Distort.bendScale - 1) * k,
                    offset: CGSize(width: dx / distance * Distort.bendShift * k, height: dy / distance * Distort.bendShift * k),
                    blur: Distort.bendBlur * k)
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }
}

extension Motion.Distort {
    /// cubic-bezier(0.22, 1, 0.36, 1), solved for x by bisection.
    static func ease(_ x: Double) -> Double {
        bezier(x, 0.22, 1, 0.36, 1)
    }

    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func curve(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if curve(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return curve((low + high) / 2, y1, y2)
    }
}

/// The wave at one moment.
struct RippleFront: Equatable {
    /// The front's distance from the leaf's middle.
    var radius: CGFloat
    /// 1 while the band is strong, 0 once it has settled.
    var energy: Double
    /// 1 while the rim keeps its colour, 0 once cleared.
    var rimKept: Double
    /// Seconds since it left.
    var time: Double
    /// How far through its travel, eased: 0 to 1.
    var moved: Double
}

/// The band, rim and sparks, drawn on the disc. `origin` is in the scene; `discScale` is
/// the disc's own scale as it draws in under the ring.
struct DropRippleView: View {
    let origin: CGPoint
    let front: RippleFront
    let side: CGFloat
    var discScale: CGFloat = 1

    @Environment(\.colorScheme) private var scheme
    private typealias R = Motion.Distort

    /// The original's colourful palette, and what runs ahead of the front.
    static let palette: [Color] = [
        rgb(255, 201, 21), rgb(126, 196, 255), rgb(180, 40, 230), rgb(235, 100, 160),
        rgb(255, 176, 122), rgb(154, 160, 255), rgb(127, 217, 238), rgb(255, 201, 21),
    ]
    static let ahead = rgb(255, 122, 182)

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rim = BloomGeometry.discRadius * discScale
            let dark = scheme == .dark
            context.clip(to: Path(ellipseIn: CGRect(x: center.x - rim, y: center.y - rim, width: rim * 2, height: rim * 2)))
            if dark { context.blendMode = .plusLighter }
            let turn = Angle.radians(front.time * 2.2)
            let colours = GraphicsContext.Shading.conicGradient(Gradient(colors: Self.palette), center: origin, angle: turn)

            // The band: the tail behind the front, the brighter body on it, and the lead ahead.
            if front.energy > 0.001 {
                context.drawLayer { band in
                    band.addFilter(.blur(radius: R.bandBlur))
                    let k = front.energy * (dark ? 0.85 : 1)
                    // Fainter the further behind: a wide faint tail, then the body.
                    band.opacity = k * 0.35
                    band.stroke(wavy(front.radius - R.tail * 0.5), with: colours, lineWidth: R.tail)
                    band.opacity = k * 0.9
                    band.stroke(wavy(front.radius - 8), with: colours, lineWidth: 22)
                    band.opacity = k * 0.7
                    band.stroke(wavy(front.radius + R.lead / 2), with: .color(Self.ahead), lineWidth: R.lead)
                }
                // The hairline, split into its colours either side like a lens.
                let line = front.energy
                var fringe = context
                fringe.opacity = line * 0.55
                fringe.stroke(wavy(front.radius + 1.6), with: .color(rgb(255, 80, 160)), lineWidth: R.hairline)
                fringe.stroke(wavy(front.radius - 1.6), with: .color(rgb(80, 200, 255)), lineWidth: R.hairline)
                var hair = context
                hair.opacity = line * (dark ? 0.9 : 1)
                hair.stroke(wavy(front.radius), with: .color(.white.opacity(dark ? 0.95 : 1)), lineWidth: R.hairline)
            }

            // The rim: colour where the front has touched it, in seven uneven lumps.
            if front.rimKept > 0.001 {
                context.drawLayer { edge in
                    edge.addFilter(.blur(radius: R.rimBlur))
                    edge.opacity = front.rimKept * (dark ? 0.85 : 0.95)
                    let segments = 120
                    let perimeter = 2 * Double.pi * Double(rim)
                    for i in 0..<segments {
                        let a0 = Double(i) / Double(segments) * 2 * .pi
                        let a1 = Double(i + 1) / Double(segments) * 2 * .pi
                        let mid = (a0 + a1) / 2
                        let point = CGPoint(x: center.x + rim * CGFloat(cos(mid)), y: center.y + rim * CGFloat(sin(mid)))
                        let touched = hypot(point.x - origin.x, point.y - origin.y)
                        let reached = Motion.smoothstep(-10, 50, Double(front.radius - touched))
                        guard reached > 0.01 else { continue }
                        let width = R.rimWidth * CGFloat(Self.lumpDepth(at: mid * Double(rim), perimeter: perimeter, time: front.time) * reached)
                        let inset = rim - width / 2
                        var arc = Path()
                        arc.addArc(center: center, radius: inset, startAngle: .radians(a0), endAngle: .radians(a1 + 0.01), clockwise: false)
                        edge.stroke(arc, with: colours, lineWidth: width)
                    }
                }
            }

            // Sparks flying out with the front.
            context.blendMode = dark ? .plusLighter : .normal
            for i in 0..<R.sparks {
                guard let spark = spark(i) else { continue }
                var dot = context
                dot.opacity = spark.opacity
                let d = spark.size
                dot.fill(Path(ellipseIn: CGRect(x: spark.point.x - d / 2, y: spark.point.y - d / 2, width: d, height: d)),
                         with: .color(dark ? .white : Self.palette[i % (Self.palette.count - 1)]))
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Self.rgb(r, g, b) }

    /// A closed front at `radius` from the origin, swelling in and out round its length, as
    /// the original's `bend`.
    private func wavy(_ radius: CGFloat) -> Path {
        var path = Path()
        let r = max(radius, 0.5)
        let swell = R.swell * CGFloat(front.energy) * min(r / 60, 1)
        let steps = 96
        for i in 0...steps {
            let theta = Double(i) / Double(steps) * 2 * .pi
            let s = theta * R.lobes
            let t = front.time * 6
            let bend = 0.62 * sin(s + t * 1.1) + 0.38 * sin(s * 2.1 - t * 1.5 + 1.7)
            let rr = max(r + swell * CGFloat(bend), 0)
            let p = CGPoint(x: origin.x + rr * CGFloat(cos(theta)), y: origin.y + rr * CGFloat(sin(theta)))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// How thick the rim is at `position` along it: the original's seven lumps.
    static func lumpDepth(at position: Double, perimeter: Double, time: Double) -> Double {
        let count = 7
        var depth = 0.25
        for i in 0..<count {
            let fi = Double(i)
            let a = hash(fi, 12.9898, 1.3), b = hash(fi, 78.233, 4.1), c = hash(fi, 39.425, 2.7)
            let centre = perimeter * (fi + 0.35 * a) / Double(count) + time * (-22 + 44 * b) * 3
            let length = perimeter / Double(count) * (0.2 + 0.25 * c)
            let breath = 0.25 * sin(time * (1.1 + 1.2 * a) * 4 + fi * 2.4)
            let height = (0.2 + 2.6 * b) * (1 + breath)
            var d = (position - centre).truncatingRemainder(dividingBy: perimeter)
            if d > perimeter / 2 { d -= perimeter } else if d < -perimeter / 2 { d += perimeter }
            let u = d / length
            depth += height * exp(-u * u) * 0.5
        }
        return min(depth, 1.8)
    }

    private static func hash(_ i: Double, _ a: Double, _ b: Double) -> Double {
        let x = sin(i * a + b) * 43758.5453
        return x - x.rounded(.down)
    }

    /// Spark `i` now, or nil when it has burnt out. Per-spark constants come from the
    /// original's low-discrepancy scatter.
    private func spark(_ index: Int) -> (point: CGPoint, opacity: Double, size: CGFloat)? {
        let i = Double(index + 1)
        func scatter(_ step: Double) -> Double { (i * step).truncatingRemainder(dividingBy: 1) }
        let heading = scatter(0.7548776662) * 2 * .pi
        let pace = 0.35 + 0.72 * scatter(0.8191725134).squareRoot()
        let drift = 10 + 34 * scatter(0.6710436067)
        let sway = 2 + 7 * scatter(0.4142135624)
        let swayRate = 10 + 14 * scatter(0.7320508076)
        let twinkleRate = 30 + 40 * scatter(0.2360679775)
        let phase = scatter(0.6180339887) * 2 * .pi
        let life = R.sparkLife * (0.45 + 0.55 * scatter(0.6457513111))
        let small = scatter(0.5497004779)
        let size = R.sparkSize * CGFloat(0.55 + 0.45 * small * small) * (1 + CGFloat(scatter(0.6055512755)) * 0.4)
        let brightness = 0.4 + 0.6 * scatter(0.6055512755)
        let flying = front.time
        guard flying < life else { return nil }
        let burning = 1 - Motion.smoothstep(life * 0.5, life, flying)
        let twinkle = 0.5 + 0.5 * sin(flying * twinkleRate + phase)
        let edge = 22.0
        let distance = edge + ((Double(front.radius) - edge) * pace * Double(R.sparkSpread) + drift * flying * 3)
        let swaying = sway * sin(swayRate * flying + phase) * min(flying / 0.08, 1)
        let x = origin.x + CGFloat(cos(heading) * distance - sin(heading) * swaying)
        let y = origin.y + CGFloat(sin(heading) * distance + cos(heading) * swaying)
        let born = Motion.smoothstep(0, 0.04, flying)
        return (CGPoint(x: x, y: y), born * burning * brightness * (0.65 + 0.35 * twinkle), size)
    }
}
