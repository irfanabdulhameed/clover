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

private struct BeamFrozenTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// When set, every beam layer renders one deterministic frame at this
    /// absolute time (seconds) at full opacity, instead of animating from a
    /// `TimelineView` clock.
    ///
    /// This exists so snapshot/parity tests can capture a specific frame —
    /// `ImageRenderer` never fires `onAppear`, so without it the fade would sit
    /// at 0 and every capture would be empty. Not part of the public API.
    var beamFrozenTime: Double? {
        get { self[BeamFrozenTimeKey.self] }
        set { self[BeamFrozenTimeKey.self] = newValue }
    }
}
