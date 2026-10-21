import AppKit
import SwiftUI
import CloverCore

/// The bloom: a hub with the files, petals around it and chips beyond the open petal.
/// Positions come from `BloomLayout`, so what is drawn is exactly what is hit-tested.
/// The view takes no clicks itself; `BloomInteractionView` above it does.
struct BloomView: View {
    @ObservedObject var model: BloomModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bloomSnapshot) private var snapshot

    private typealias G = BloomGeometry
    private let side = BloomGeometry.panelSize

    var body: some View {
        let center = side / 2
        let lit = model.litSlot
        ZStack {
            if !snapshot {
                // Nearly invisible, so the window takes drags and clicks across the bloom.
                Circle().fill(Color.black.opacity(0.012)).frame(width: side - 8, height: side - 8)
            }
            ForEach(model.items, id: \.slot) { item in
                petal(item, lit: lit)
                    .position(offset(BloomLayout.petalCenter(item.slot), center))
            }
            if let open = model.openSlot, let target = model.target(at: open) {
                let frames = model.chipFrames(for: open)
                ForEach(Array(zip(target.options.indices, frames)), id: \.0) { index, frame in
                    ChipView(title: target.options[index].title,
                             isDefault: target.options[index].id == target.defaultOption?.id,
                             isLit: model.litChip == index,
                             isFocused: model.usingKeyboard && model.focusChip == index,
                             hue: BloomStyle.hue(target.format.family, scheme))
                        .frame(width: frame.width, height: frame.height)
                        .position(offset(CGPoint(x: frame.midX, y: frame.midY), center))
                }
            }
            HubView(pictures: model.pictures, count: model.files.count, hasFiles: model.hasFiles, mixed: model.isMixed)
                .position(x: center, y: center)
            if !model.hint.isEmpty {
                HintLabel(text: model.hint, maxWidth: model.targets.isEmpty ? 220 : G.hintMaxWidth)
                    .position(x: center, y: center + G.hintCenterY)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func petal(_ item: BloomPlan.Item, lit: Int?) -> some View {
        let state: PetalView.State = {
            if lit == item.slot { return model.usingKeyboard ? .focused : .lit }
            return lit == nil ? .resting : .dimmed
        }()
        switch item.kind {
        case .more:
            PetalView(title: "More", symbol: "ellipsis", hue: Color.secondary, state: state)
        case .target:
            if let target = model.target(at: item.slot) {
                PetalView(title: target.title, symbol: BloomStyle.symbol(for: target),
                          hue: BloomStyle.hue(target.format.family, scheme), state: state)
            }
        }
    }

    private func offset(_ p: CGPoint, _ center: CGFloat) -> CGPoint {
        CGPoint(x: center + p.x, y: center + p.y)
    }
}

/// One glass bubble with a format name and a small icon in its family's hue.
struct PetalView: View {
    enum State { case resting, lit, focused, dimmed }

    let title: String
    let symbol: String
    let hue: Color
    let state: State

    private typealias G = BloomGeometry

    var body: some View {
        let isLit = state == .lit || state == .focused
        let size = isLit ? G.litPetalSize : G.petalSize
        ZStack {
            if isLit {
                // A soft, still glow in the family's hue.
                Circle().fill(hue.opacity(0.42))
                    .frame(width: size + 10, height: size + 10)
                    .blur(radius: 9)
            }
            Glass(cornerRadius: size / 2, tint: isLit ? hue.opacity(0.16) : nil, bright: isLit)
                .frame(width: size, height: size)
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hue)
                    .frame(height: 15)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: size - 6)
            }
            if state == .focused {
                Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: size + 8, height: size + 8)
            }
        }
        .frame(width: G.litPetalSize + 12, height: G.litPetalSize + 12)
        .opacity(state == .dimmed ? 0.5 : 1)
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
