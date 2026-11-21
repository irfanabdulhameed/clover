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
    /// Highlights one slot, as if hovered, by target id. A target in More lights More.
    var highlighted: String? = nil
    /// A click on a leaf plays the drop's distortion wave from it.
    var playsWave = false
    /// A click on a leaf, with its target id (More gives its first target); nil off the leaves.
    var onLeaf: ((String?) -> Void)? = nil
    /// The pointer moved onto a leaf, or off them (nil).
    var onHover: ((String?) -> Void)? = nil

    @State private var lastHover: String?
    /// The last click on a leaf: which leaf and when, for the wave.
    @State private var wave: (slot: Int, at: TimeInterval)?

    /// The clover fits this square.
    static let side: CGFloat = 320
    /// The scene it is drawn in before scaling down: the disc and a little air.
    private static let scene = BloomGeometry.discRadius * 2 + 16

    /// The size the preview's hub shows, as a file's would.
    static let caption = "2.4 MB"

    /// The glass tint chosen on the Clover page, so the preview shows the clover as it will be.
    @Environment(\.glassTint) private var tint

    var body: some View {
        let lit = highlighted.flatMap { id in
            arrangement.leaves.firstIndex { $0.id == id } ?? (arrangement.more.contains { $0.id == id } ? arrangement.leaves.count : nil)
        }
        // Like the live hub with a file: its picture (a plain document when none is given)
        // and its size.
        let picture = Thumbnails.icon(for: file ?? URL(fileURLWithPath: "/Clover preview/document"))
        let model = BloomModel.still(arrangement: arrangement, picture: picture, caption: CloverPreview.caption, lit: lit, tint: tint)
        let titles = arrangement.leaves.map(\.title) + (arrangement.more.isEmpty ? [] : ["More"])
        ZStack {
            if let wave, DistortionWaves.available {
                // Seen through the drop's distortion wave, from the clicked leaf.
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate - wave.at
                    let size = CGSize(width: CloverPreview.scene, height: CloverPreview.scene)
                    let w = DistortionWaves.front(at: max(t, 0), slot: wave.slot, count: count, in: size)
                    DistortionStage(front: w.front, source: w.source, style: CloverPreview.waveStyle, freezeKey: wave.at) {
                        BloomScene(model: model, now: 0, side: CloverPreview.scene)
                    }
                }
            } else {
                BloomScene(model: model, now: 0, side: CloverPreview.scene)
            }
        }
            .scaleEffect(CloverPreview.side / CloverPreview.scene)
            .frame(width: CloverPreview.side, height: CloverPreview.side)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                if playsWave, let slot = slot(at: point) {
                    let at = Date().timeIntervalSinceReferenceDate
                    wave = (slot, at)
                    DispatchQueue.main.asyncAfter(deadline: .now() + DistortionWaves.style.duration) {
                        if wave?.at == at { wave = nil }
                    }
                }
                onLeaf?(target(at: point))
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard let onHover else { return }
                let id: String?
                switch phase {
                case .active(let point): id = target(at: point)
                case .ended: id = nil
                }
                if id != lastHover {
                    lastHover = id
                    onHover(id)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clover preview: " + titles.joined(separator: ", "))
    }

    private var count: Int { arrangement.leaves.count + (arrangement.more.isEmpty ? 0 : 1) }

    /// The leaf under a point of the preview, found with the clover's own hit-testing.
    private func slot(at point: CGPoint) -> Int? {
        let scale = CloverPreview.scene / CloverPreview.side
        let clover = CGPoint(x: (point.x - CloverPreview.side / 2) * scale, y: (point.y - CloverPreview.side / 2) * scale)
        guard case .leaf(let index) = BloomLayout.hit(clover, count: count, open: nil, chips: []) else { return nil }
        return index
    }

    /// The target under a point of the preview.
    private func target(at point: CGPoint) -> String? {
        guard let index = slot(at: point) else { return nil }
        return index < arrangement.leaves.count ? arrangement.leaves[index].id : arrangement.more.first?.id
    }
}

extension CloverPreview {
    /// The wave in the preview's square: its rim on the preview's disc.
    static var waveStyle: DistortionWaveStyle {
        var style = DistortionWaves.style
        style.cornerRadius = scene / 2
        return style
    }
}
