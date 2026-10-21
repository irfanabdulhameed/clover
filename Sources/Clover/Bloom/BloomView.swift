import AppKit
import SwiftUI
import CloverCore

/// The clover: a hub with the files, heart-shaped leaves around it and chips beyond the
/// open leaf. Shapes and positions come from `BloomLayout`, so what is drawn is exactly
/// what is hit-tested. The view takes no clicks itself; `BloomInteractionView` above it does.
struct BloomView: View {
    @ObservedObject var model: BloomModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bloomSnapshot) private var snapshot

    private typealias G = BloomGeometry
    private let side = BloomGeometry.panelSize

    var body: some View {
        let center = CGPoint(x: side / 2, y: side / 2)
        let lit = model.litLeaf
        let count = model.leafCount
        ZStack {
            if !snapshot {
                // Nearly invisible, so the window takes drags and clicks across the clover.
                Circle().fill(Color.black.opacity(0.012)).frame(width: side - 8, height: side - 8)
            }
            // The lit leaf's glow, under every leaf, so it shows only around it.
            if let lit, lit < count {
                LeafGlow(index: lit, count: count, hue: hue(of: lit))
                    .position(offset(BloomLayout.leafBounds(lit, of: count).mid, center))
            }
            ForEach(Array(model.leaves.enumerated()), id: \.offset) { index, leaf in
                LeafView(index: index, count: count, title: title(of: leaf), symbol: symbol(of: leaf),
                         hue: hue(of: index), state: state(of: index, lit: lit))
                    .position(offset(BloomLayout.leafBounds(index, of: count).mid, center))
            }
            if let open = model.openLeaf, let target = model.target(at: open) {
                let frames = model.chipFrames(for: open)
                ForEach(Array(zip(target.options.indices, frames)), id: \.0) { index, frame in
                    ChipView(title: target.options[index].title,
                             isDefault: target.options[index].id == target.defaultOption?.id,
                             isLit: model.litChip == index,
                             isFocused: model.usingKeyboard && model.focusChip == index,
                             hue: BloomStyle.hue(target.format.family, scheme))
                        .frame(width: frame.width, height: frame.height)
                        .position(offset(frame.mid, center))
                }
            }
            HubView(pictures: model.pictures, count: model.files.count, hasFiles: model.hasFiles, mixed: model.isMixed)
                .position(center)
            if !model.hint.isEmpty {
                HintLabel(text: model.hint, maxWidth: model.arrangement.all.isEmpty ? 220 : G.hintMaxWidth)
                    .position(x: center.x, y: center.y + G.hintCenterY)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    private func state(of index: Int, lit: Int?) -> LeafView.State {
        // The ring sits on the leaf until one of its chips takes the focus.
        if lit == index { return model.focusedLeaf == index && model.focusChip == nil ? .focused : .lit }
        return lit == nil ? .resting : .dimmed
    }

    private func title(of leaf: BloomModel.Leaf) -> String {
        switch leaf {
        case .target(let target): target.title
        case .more: "More"
        }
    }

    private func symbol(of leaf: BloomModel.Leaf) -> String {
        switch leaf {
        case .target(let target): BloomStyle.symbol(for: target)
        case .more: "ellipsis"
        }
    }

    private func hue(of index: Int) -> Color {
        guard let target = model.target(at: index) else { return Color.secondary }
        return BloomStyle.hue(target.format.family, scheme)
    }

    private func offset(_ p: CGPoint, _ center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x, y: center.y + p.y)
    }
}

extension CGRect {
    var mid: CGPoint { CGPoint(x: midX, y: midY) }
}

/// One heart-shaped glass leaf, its point towards the hub, with an upright icon and title
/// in its broad part. Its frame is the leaf's bounding box.
struct LeafView: View {
    enum State { case resting, lit, focused, dimmed }

    let index: Int
    let count: Int
    let title: String
    let symbol: String
    let hue: Color
    let state: State

    var body: some View {
        let bounds = BloomLayout.leafBounds(index, of: count)
        let key = "leaf \(index) of \(count)"
        let local = LeafView.localPath(index, count)
        let label = BloomLayout.labelBox(index, of: count)
        let isLit = state == .lit || state == .focused
        ZStack(alignment: .topLeading) {
            PathGlass(path: local, key: key, tint: isLit ? hue.opacity(0.16) : nil, bright: isLit)
            LeafLabel(title: title, symbol: symbol, hue: hue, width: label.width)
                .frame(width: label.width, height: label.height)
                .offset(x: label.minX - bounds.minX, y: label.minY - bounds.minY)
            if state == .focused {
                let ring = PathOutset.outset(local, by: 3, key: key)
                Path(ring).stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .opacity(state == .dimmed ? 0.5 : 1)
    }

    /// The leaf's outline moved so its bounding box starts at the origin.
    static func localPath(_ index: Int, _ count: Int) -> CGPath {
        let bounds = BloomLayout.leafBounds(index, of: count)
        var shift = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        let path = BloomLayout.leafPath(index, of: count)
        return path.copy(using: &shift) ?? path
    }
}

/// The soft, still glow in a family's hue around a lit leaf.
struct LeafGlow: View {
    let index: Int
    let count: Int
    let hue: Color

    var body: some View {
        let bounds = BloomLayout.leafBounds(index, of: count)
        Path(LeafView.localPath(index, count))
            .fill(hue.opacity(0.42))
            .frame(width: bounds.width, height: bounds.height)
            .blur(radius: 9)
    }
}

/// A leaf's icon over its title, both upright.
struct LeafLabel: View {
    let title: String
    let symbol: String
    let hue: Color
    let width: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hue)
                .frame(height: 16)
            Text(title)
                .font(Font(BloomStyle.leafFont))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: width)
        }
    }
}

/// A small glass capsule with one option. The default option carries a dot.
struct ChipView: View {
    let title: String
    let isDefault: Bool
    let isLit: Bool
    let isFocused: Bool
    let hue: Color

    var body: some View {
        let lit = isLit || isFocused
        ZStack {
            Glass(cornerRadius: BloomGeometry.chipHeight / 2, tint: lit ? hue.opacity(0.20) : nil, bright: lit)
            HStack(spacing: 4) {
                if isDefault {
                    Circle().fill(hue).frame(width: 5, height: 5)
                }
                Text(title)
                    .font(Font(BloomStyle.chipFont))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if isFocused {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
            }
        }
    }
}

/// The centre: the file's thumbnail, or a small stack with a count for many files.
struct HubView: View {
    let pictures: [NSImage]
    let count: Int
    let hasFiles: Bool
    let mixed: Bool

    @Environment(\.colorScheme) private var scheme
    private typealias G = BloomGeometry

    var body: some View {
        ZStack {
            Glass(cornerRadius: G.hubSize / 2, bright: true)
                .frame(width: G.hubSize, height: G.hubSize)
            if !hasFiles || pictures.isEmpty {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
            } else if pictures.count == 1 {
                picture(pictures[0], side: 44)
            } else {
                stack
            }
            if count > 1 {
                Text(count < 1000 ? "\(count)" : "999+")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(scheme == .dark ? Color(white: 0.92) : Color(white: 0.18)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0 : 0.6), lineWidth: 0.75))
                    .offset(x: 25, y: -25)
            }
        }
        .frame(width: G.hubSize + 24, height: G.hubSize + 24)
    }

    /// Up to three cards fanned behind each other. Mixed files show their different icons.
    private var stack: some View {
        ZStack {
            ForEach(Array(pictures.prefix(3).enumerated().reversed()), id: \.offset) { index, image in
                let angle: Double = index == 0 ? 0 : (index == 1 ? -10 : 10)
                picture(image, side: 34)
                    .rotationEffect(.degrees(angle))
                    .offset(x: index == 0 ? 0 : (index == 1 ? -10 : 10), y: index == 0 ? 3 : -2)
            }
        }
    }

    private func picture(_ image: NSImage, side: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
    }
}

/// The hint on the hub's lower edge: what the files are, or what a drop will do.
struct HintLabel: View {
    let text: String
    let maxWidth: CGFloat

    var body: some View {
        let width = min(BloomStyle.textWidth(text, font: BloomStyle.hintFont) + 16, maxWidth)
        Text(text)
            .font(Font(BloomStyle.hintFont))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 8)
            .frame(width: width, height: BloomGeometry.hintHeight)
            .background(Glass(cornerRadius: BloomGeometry.hintHeight / 2, shadow: false))
    }
}

// MARK: - More tray

/// The More tray: a glass panel of pills, one per target that isn't on a leaf, with the
/// hovered pill's chips just under it. Drawn in its own window, `TrayLayout.windowMargin`
/// in from the window's edges.
struct TrayView: View {
    @ObservedObject var model: BloomModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let m = TrayLayout.windowMargin
        let size = model.traySize
        let frames = model.pillFrames
        ZStack(alignment: .topLeading) {
            Glass(cornerRadius: TrayLayout.cornerRadius, bright: true)
                .frame(width: size.width, height: size.height)
            ForEach(Array(model.arrangement.more.enumerated()), id: \.offset) { index, target in
                if frames.indices.contains(index) {
                    PillView(title: target.title, symbol: BloomStyle.symbol(for: target),
                             hue: BloomStyle.hue(target.format.family, scheme),
                             isLit: model.litPill == index, isFocused: model.focusedPill == index && model.focusChip == nil)
                        .frame(width: frames[index].width, height: frames[index].height)
                        .offset(x: frames[index].minX, y: frames[index].minY)
                }
            }
            if let open = model.openPill, let target = model.pillTarget(open) {
                let chips = model.pillChipFrames(for: open)
                ForEach(Array(zip(target.options.indices, chips)), id: \.0) { index, frame in
                    ChipView(title: target.options[index].title,
                             isDefault: target.options[index].id == target.defaultOption?.id,
                             isLit: model.litChip == index,
                             isFocused: model.usingKeyboard && model.focusChip == index,
                             hue: BloomStyle.hue(target.format.family, scheme))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: size.width, height: size.height + TrayLayout.overhang, alignment: .topLeading)
        .padding(m)
        .allowsHitTesting(false)
    }
}

/// One target in the More tray: an icon in its family's hue and its title.
struct PillView: View {
    let title: String
    let symbol: String
    let hue: Color
    let isLit: Bool
    let isFocused: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lit = isLit || isFocused
        let dark = scheme == .dark
        ZStack {
            Capsule().fill(dark ? Color.white.opacity(0.07) : Color.white.opacity(0.45))
            if lit { Capsule().fill(hue.opacity(dark ? 0.26 : 0.18)) }
            Capsule().strokeBorder(dark ? Color.white.opacity(lit ? 0.30 : 0.12) : Color.black.opacity(lit ? 0.14 : 0.07),
                                   lineWidth: 0.75)
            HStack(spacing: TrayLayout.iconGap) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hue)
                    .frame(width: TrayLayout.iconWidth)
                Text(title)
                    .font(Font(BloomStyle.pillFont))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, TrayLayout.pillPadding)
            if isFocused {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
            }
        }
    }
}
