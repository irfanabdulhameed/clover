import SwiftUI

/// A plate behind a part of Home: Liquid Glass on macOS 26, a flat tint before it. The
/// popover itself is already glass, so plates are kept for the two things you aim at:
/// the drop zone and the row under the pointer.
///
/// `tint` colours the glass (the drop zone when files are over it). `fallback` is the flat
/// fill used before macOS 26, which already says hovered and pressed. `lift` is how much
/// darker the glass goes when hovered or pressed, since glass has no fill to change.
struct HomeGlassPlate: View {
    var cornerRadius: CGFloat
    var tint: Color?
    var fallback: Color
    var lift = 0.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let regular = SwiftUI.Glass.regular
            Color.clear
                .glassEffect(tint.map { regular.tint($0) } ?? regular, in: shape)
                .overlay(shape.fill(Color.primary.opacity(lift)))
        } else {
            shape.fill(fallback)
        }
        #else
        shape.fill(fallback)
        #endif
    }
}
