import SwiftUI

/// Shown in Home before the first conversion: how to use Clover, with a small drawing of the gesture.
struct EmptyHint: View {
    let trigger: TriggerKey

    var body: some View {
        VStack(spacing: 10) {
            GestureDrawing(trigger: trigger)
            Text("Hold \(trigger.symbol) while you drag any file")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Clover opens a ring of formats around your pointer. Drop on one to convert.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A key cap, a plus, and a file with a ring of format bubbles around it.
private struct GestureDrawing: View {
    let trigger: TriggerKey

    /// One hue per file family, as in the bloom: images, video, audio, documents, archives.
    private let hues: [Color] = [.orange, .purple, .pink, .blue, .gray]

    var body: some View {
        HStack(spacing: 14) {
            KeyCap(symbol: trigger.symbol)
            Text("+")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            ring
        }
        .frame(height: 84)
        .accessibilityHidden(true)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 66, height: 66)
            ForEach(0..<hues.count, id: \.self) { i in
                RingDot(color: hues[i], index: i, count: hues.count)
            }
            FileSheet()
                .frame(width: 22, height: 28)
            Image(systemName: "cursorarrow")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.primary)
                .offset(x: 10, y: 14)
        }
        .frame(width: 84, height: 84)
    }
}

/// One format bubble on the ring.
private struct RingDot: View {
    let color: Color
    let index: Int
    let count: Int

    var body: some View {
        let angle: Double = Double(index) / Double(count) * 2 * Double.pi - Double.pi / 2
        let x: CGFloat = 33 * CGFloat(cos(angle))
        let y: CGFloat = 33 * CGFloat(sin(angle))
        Circle()
            .fill(color.opacity(0.85))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75))
            .frame(width: 14, height: 14)
            .offset(x: x, y: y)
    }
}

private struct KeyCap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1.5)
    }
}

/// A sheet of paper with a folded corner.
private struct FileSheet: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let fold: CGFloat = 7
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 2))
                    p.addQuadCurve(to: CGPoint(x: 2, y: 0), control: .zero)
                    p.addLine(to: CGPoint(x: w - fold, y: 0))
                    p.addLine(to: CGPoint(x: w, y: fold))
                    p.addLine(to: CGPoint(x: w, y: h - 2))
                    p.addQuadCurve(to: CGPoint(x: w - 2, y: h), control: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 2, y: h))
                    p.addQuadCurve(to: CGPoint(x: 0, y: h - 2), control: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(Color.primary.opacity(0.2))
                Path { p in
                    p.move(to: CGPoint(x: w - fold, y: 0))
                    p.addLine(to: CGPoint(x: w - fold, y: fold))
                    p.addLine(to: CGPoint(x: w, y: fold))
                    p.closeSubpath()
                }
                .fill(Color.primary.opacity(0.34))
            }
        }
    }
}
