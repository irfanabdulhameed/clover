import AppKit
import SwiftUI

/// The four-leaf clover mark, drawn in code: four heart-shaped leaves with their tips
/// near the middle, and a short stem. Everything is in a unit box with y pointing up.
enum CloverGlyph {
    /// One heart-shaped leaf. The tip is at the origin, it points along +y and is 1 unit long.
    private static let leaf: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: -0.46, y: 0.6), control1: CGPoint(x: -0.1, y: 0.12), control2: CGPoint(x: -0.46, y: 0.34))
        p.addCurve(to: CGPoint(x: 0, y: 0.66), control1: CGPoint(x: -0.46, y: 1.0), control2: CGPoint(x: -0.06, y: 1.04))
        p.addCurve(to: CGPoint(x: 0.46, y: 0.6), control1: CGPoint(x: 0.06, y: 1.04), control2: CGPoint(x: 0.46, y: 1.0))
        p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: 0.46, y: 0.34), control2: CGPoint(x: 0.1, y: 0.12))
        p.closeSubpath()
        return p
    }()

    private static let center = CGPoint(x: 0.5, y: 0.57)

    /// The four leaves, as one path.
    static func leaves(in rect: CGRect, flipped: Bool = false) -> CGPath {
        let p = CGMutablePath()
        for degrees in [45.0, 135.0, 225.0, 315.0] {
            let angle = degrees * .pi / 180
            let gap = 0.06
            let tip = CGPoint(x: center.x + gap * cos(angle), y: center.y + gap * sin(angle))
            let t = CGAffineTransform(translationX: tip.x, y: tip.y)
                .rotated(by: angle - .pi / 2)
                .scaledBy(x: 0.37, y: 0.37)
            p.addPath(leaf, transform: t)
        }
        var place = unitToRect(rect, flipped: flipped)
        return p.copy(using: &place) ?? p
    }

    /// The stem, as an outline ready to fill.
    static func stem(in rect: CGRect, flipped: Bool = false) -> CGPath {
        // Stroked in a 1000-unit box: CoreGraphics rounds the caps with a fixed tolerance
        // that is too coarse in a unit box.
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 500, y: 520))
        line.addCurve(to: CGPoint(x: 590, y: 70), control1: CGPoint(x: 500, y: 330), control2: CGPoint(x: 555, y: 200))
        let outline = line.copy(strokingWithWidth: 56, lineCap: .round, lineJoin: .round, miterLimit: 1)
        var place = CGAffineTransform(scaleX: 0.001, y: 0.001).concatenating(unitToRect(rect, flipped: flipped))
        return outline.copy(using: &place) ?? outline
    }

    private static func unitToRect(_ rect: CGRect, flipped: Bool) -> CGAffineTransform {
        let w = rect.width
        return flipped
            ? CGAffineTransform(a: w, b: 0, c: 0, d: -w, tx: rect.minX, ty: rect.maxY)
            : CGAffineTransform(a: w, b: 0, c: 0, d: w, tx: rect.minX, ty: rect.minY)
    }

    /// The menu bar image: 18 pt, black, marked as a template so the system tints it.
    /// It is drawn by a handler, so it stays sharp at 1x and 2x.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(leaves(in: rect))
            context.fillPath()
            context.addPath(stem(in: rect))
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clover"
        return image
    }
}

/// The same mark as a SwiftUI shape, for the drop zone.
struct CloverShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        return Path(CloverGlyph.leaves(in: box, flipped: true)).union(Path(CloverGlyph.stem(in: box, flipped: true)))
    }
}
