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

/// Builds the 3x3 color matrix for the CSS filter chain
/// `hue-rotate(θ) brightness(b) saturate(s)` — applied left-to-right, so the
/// composed matrix is `Msaturate × (b · Mhue)`.
///
/// Matrices follow the W3C Filter Effects spec (feColorMatrix `hueRotate` /
/// `saturate`), which is what browsers use — NOT a true HSL rotation. Using the
/// same math keeps native colors identical to the web version.
enum BeamColorMatrix {
    static func hueRotate(degrees: Double) -> [Double] {
        let rad = degrees * .pi / 180
        let c = cos(rad)
        let s = sin(rad)
        return [
            0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928,
            0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283,
            0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072,
        ]
    }

    static func saturate(_ s: Double) -> [Double] {
        [
            0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s,
            0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s,
            0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s,
        ]
    }

    static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 9)
        for row in 0..<3 {
            for col in 0..<3 {
                var sum = 0.0
                for k in 0..<3 {
                    sum += a[row * 3 + k] * b[k * 3 + col]
                }
                out[row * 3 + col] = sum
            }
        }
        return out
    }

    /// Composed matrix for `hue-rotate(hueDegrees) brightness(brightness)
    /// saturate(saturation)` as `Float`s ready for the shader.
    static func composed(hueDegrees: Double, brightness: Double, saturation: Double) -> [Float] {
        let hue = hueRotate(degrees: hueDegrees).map { $0 * brightness }
        return multiply(saturate(saturation), hue).map { Float($0) }
    }
}
