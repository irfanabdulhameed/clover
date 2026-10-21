import AppKit
import SwiftUI
import CloverCore

/// A still picture of the clover for an arrangement, used by the dashboard's leaf editor.
/// Draws the same disc and slots as the live clover, settled, with no pointer, in flat
/// glass so it sits in an ordinary window.
struct CloverPreview: View {
    let arrangement: Arrangement
    /// The file in the middle; nil shows a generic document icon.
    var file: URL? = nil
    /// Highlights one slot, as if hovered, by target id.
    var highlighted: String? = nil

    /// The clover fits this square.
    static let side: CGFloat = 320
    /// The scene it is drawn in before scaling down: the disc and a little air.
    private static let scene = BloomGeometry.discRadius * 2 + 16

    var body: some View {
        let lit = highlighted.flatMap { id in arrangement.leaves.firstIndex { $0.id == id } }
        let model = BloomModel.still(arrangement: arrangement, picture: file.map { Thumbnails.icon(for: $0) }, lit: lit)
        let titles = arrangement.leaves.map(\.title) + (arrangement.more.isEmpty ? [] : ["More"])
        BloomScene(model: model, now: 0, side: CloverPreview.scene)
            .scaleEffect(CloverPreview.side / CloverPreview.scene)
            .frame(width: CloverPreview.side, height: CloverPreview.side)
            .environment(\.bloomSnapshot, true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clover preview: " + titles.joined(separator: ", "))
    }
}
