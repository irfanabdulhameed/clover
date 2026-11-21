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

import SwiftUI

/// Size/type preset for the border beam effect.
///
/// Rotate family (traveling/spinning beam): `.sm`, `.md`, `.line`.
/// Pulse family (breathing glow, no rotation): `.pulseOutside`, `.pulseInner`.
enum BeamSize: String, CaseIterable, Sendable {
    case sm
    case md
    case line
    case pulseOutside = "pulse-outside"
    case pulseInner = "pulse-inner"

    var isPulse: Bool { self == .pulseOutside || self == .pulseInner }
}

/// Theme mode for adapting beam colors to the background.
enum BeamTheme: String, CaseIterable, Sendable {
    case dark
    case light
    /// Follows the SwiftUI `colorScheme` environment.
    case auto
}

/// Color variant for the beam effect.
enum BeamColorVariant: String, CaseIterable, Sendable {
    case colorful
    case mono
    case ocean
    case sunset
}
