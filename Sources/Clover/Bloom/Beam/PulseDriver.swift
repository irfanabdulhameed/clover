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

/// Direct port of the web library's `pulseDriver.ts` oscillator math.
///
/// Each oscillator ping-pongs a value between `a` and `b` with a cosine
/// ease-in-out over `period` seconds, offset by `delay` seconds. The web
/// version writes CSS custom properties from a shared 30 fps rAF loop; here the
/// values are sampled per-frame (via `TimelineView`) and fed to the pulse
/// shaders as uniforms.
enum PulseDriver {
    /// Cosine ease-in-out factor in [0, 1]: 0 at phase 0/1, 1 at phase 0.5.
    static func pingPong(_ phase: Double) -> Double {
        (1 - cos(2 * .pi * phase)) / 2
    }

    /// Samples one oscillator at absolute time `t` (seconds).
    static func value(of osc: BeamSpec.Oscillator, at t: Double, durationScale: Double = 1) -> Double {
        let period = osc.period * durationScale
        let delay = osc.delay * durationScale
        let phase = (t - delay) / period
        return osc.a + (osc.b - osc.a) * pingPong(phase)
    }

    /// Samples every oscillator of a pulse section into a `prop → value` table.
    /// `durationScale` is `duration / 2.3` (spec oscillators are emitted at the
    /// default 2.3 s pulse duration; periods scale linearly).
    static func sample(
        _ section: BeamSpec.PulseThemeSection,
        at t: Double,
        durationScale: Double
    ) -> [String: Double] {
        var out: [String: Double] = [:]
        out.reserveCapacity(section.oscillators.count)
        for osc in section.oscillators {
            out[osc.prop] = value(of: osc, at: t, durationScale: durationScale)
        }
        return out
    }

    /// Continuous full-circle hue rotation in degrees (pulse family).
    static func hueDegrees(at t: Double, period: Double) -> Double {
        (t / period).truncatingRemainder(dividingBy: 1) * 360
    }
}
