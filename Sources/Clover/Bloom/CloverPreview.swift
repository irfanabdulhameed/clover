import AppKit
import SwiftUI
import CloverCore

/// A still picture of the clover for an arrangement, used by the dashboard's leaf editor.
/// Draws the same leaves as the live clover, at rest, with no pointer, in flat glass
/// so it sits in an ordinary window.
struct CloverPreview: View {
    let arrangement: Arrangement
    /// The file in the middle; nil shows a generic document icon.
    var file: URL? = nil
    /// Highlights one leaf, as if hovered, by target id.
    var highlighted: String? = nil

    @Environment(\.colorScheme) private var scheme

    /// The clover with its glow fits this square.
    static let side: CGFloat = 320

    var body: some View {
        let leaves = arrangement.leaves.map(BloomModel.Leaf.target) + (arrangement.more.isEmpty ? [] : [.more])
        let count = leaves.count
        let lit = highlighted.flatMap { id in arrangement.leaves.firstIndex { $0.id == id } }
        let center = CGPoint(x: CloverPreview.side / 2, y: CloverPreview.side / 2)
        ZStack {
            if let lit {
                LeafGlow(index: lit, count: count, hue: hue(arrangement.leaves[lit]))
                    .position(offset(BloomLayout.leafBounds(lit, of: count).mid, center))
            }
            ForEach(Array(leaves.enumerated()), id: \.offset) { index, leaf in
                LeafView(index: index, count: count, title: title(leaf), symbol: symbol(leaf),
                         hue: leafHue(leaf), state: lit == nil ? .resting : (lit == index ? .lit : .dimmed))
                    .position(offset(BloomLayout.leafBounds(index, of: count).mid, center))
            }
            HubView(pictures: file.map { [Thumbnails.icon(for: $0)] } ?? [], count: 1, hasFiles: file != nil, mixed: false)
                .position(center)
        }
        .frame(width: CloverPreview.side, height: CloverPreview.side)
        .environment(\.bloomSnapshot, true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clover preview: " + leaves.map(title).joined(separator: ", "))
    }

    private func title(_ leaf: BloomModel.Leaf) -> String {
        switch leaf {
        case .target(let target): target.title
        case .more: "More"
        }
    }

    private func symbol(_ leaf: BloomModel.Leaf) -> String {
        switch leaf {
        case .target(let target): BloomStyle.symbol(for: target)
        case .more: "ellipsis"
        }
    }

    private func leafHue(_ leaf: BloomModel.Leaf) -> Color {
        switch leaf {
        case .target(let target): hue(target)
        case .more: Color.secondary
        }
    }

    private func hue(_ target: Target) -> Color {
        BloomStyle.hue(target.format.family, scheme)
    }

    private func offset(_ p: CGPoint, _ center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x, y: center.y + p.y)
    }
}
