import SwiftUI
import CloverCore

/// A still picture of the clover for an arrangement, used by the dashboard's leaf editor.
/// Draws the same leaves as the live clover, at rest, with no pointer.
struct CloverPreview: View {
    let arrangement: Arrangement
    /// The file in the middle; nil shows a generic document icon.
    var file: URL? = nil
    /// Highlights one leaf, as if hovered, by target id.
    var highlighted: String? = nil

    var body: some View {
        // Placeholder until the clover-leaf drawing lands; same size as the real one.
        ZStack {
            Circle().fill(.quaternary).frame(width: 72, height: 72)
            ForEach(Array(arrangement.leaves.enumerated()), id: \.offset) { index, target in
                let count = arrangement.leaves.count + (arrangement.more.isEmpty ? 0 : 1)
                let angle = Double(index) / Double(max(count, 1)) * 2 * .pi - .pi / 2
                Text(target.title).font(.caption.bold())
                    .offset(x: cos(angle) * 90, y: sin(angle) * 90)
            }
        }
        .frame(width: 320, height: 320)
    }
}
