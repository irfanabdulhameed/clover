import AppKit
import SwiftUI
import CloverCore

/// A still picture of the clover for an arrangement, used by the dashboard's leaf editor.
/// Draws the clover exactly as it opens: the same glass (Liquid Glass on macOS 26, frosted
/// before it and in still renders), the chosen tint, the slots with their turned labels and
/// the + More slot, and a hub with a file and its size. The highlighted slot has the
/// hover's bright glass.
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

    /// The size the preview's hub shows, as a file's would.
    static let caption = "2.4 MB"

    /// The glass tint chosen in Feel, so the preview shows the clover as it will be.
    @Environment(\.glassTint) private var tint

    var body: some View {
        let lit = highlighted.flatMap { id in arrangement.leaves.firstIndex { $0.id == id } }
        // Like the live hub with a file: its picture (a plain document when none is given)
        // and its size.
        let picture = Thumbnails.icon(for: file ?? URL(fileURLWithPath: "/Clover preview/document"))
        let model = BloomModel.still(arrangement: arrangement, picture: picture, caption: CloverPreview.caption, lit: lit, tint: tint)
        let titles = arrangement.leaves.map(\.title) + (arrangement.more.isEmpty ? [] : ["More"])
        BloomScene(model: model, now: 0, side: CloverPreview.scene)
            .scaleEffect(CloverPreview.side / CloverPreview.scene)
            .frame(width: CloverPreview.side, height: CloverPreview.side)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clover preview: " + titles.joined(separator: ", "))
    }
}
