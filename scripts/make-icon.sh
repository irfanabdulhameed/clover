#!/bin/bash
# Draws Clover's app icon and writes Resources/Clover.icns.
#   ./scripts/make-icon.sh                       write the .icns
#   ICONSET_DIR=/some/folder ./scripts/make-icon.sh   also keep the PNGs, to look at them
#
# The icon is drawn in code at every size (so small sizes stay crisp), using the same
# clover shape as the menu bar icon (Sources/Clover/Home/CloverGlyph.swift).
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha,
    ])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

/// A superellipse: the rounded-square shape macOS icons use, with corners that ease in.
func squircle(_ rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(x: rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / n), c),
                            y: rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / n), s))
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// Draws the icon on a 1024 x 1024 canvas, scaled to `size` pixels.
func drawIcon(size: Int) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    // Shadow settings are measured in pixels, not in the scaled drawing units.
    let k = CGFloat(size) / 1024
    context.scaleBy(x: k, y: k)

    // The body is 824 pt inside the 1024 canvas, as in Apple's icon grid.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    // Soft shadow under the body.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 30 * k, color: color(0x0B3D22, 0.32))
    context.setFillColor(color(0x2FB36C))
    context.addPath(shape)
    context.fillPath()
    context.restoreGState()

    // Green gradient, light at the top.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(
        gradient([(0, color(0xA4EDA9)), (0.5, color(0x5BD48B)), (1, color(0x23A862))]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // A broad soft light from the top, and a little depth at the bottom edge.
    context.drawRadialGradient(
        gradient([(0, color(0xFFFFFF, 0.34)), (1, color(0xFFFFFF, 0))]),
        startCenter: CGPoint(x: 430, y: 930), startRadius: 0,
        endCenter: CGPoint(x: 430, y: 930), endRadius: 620, options: [])
    context.drawLinearGradient(
        gradient([(0, color(0x0A5A2C, 0.0)), (1, color(0x0A5A2C, 0.22))]),
        start: CGPoint(x: 512, y: 330), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // A thin light edge along the top, fading out toward the bottom.
    context.saveGState()
    context.addPath(shape)
    context.setLineWidth(5)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([(0, color(0xFFFFFF, 0.65)), (0.45, color(0xFFFFFF, 0.08)), (1, color(0xFFFFFF, 0.0))]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // The clover: white, lit from above, with a soft green shadow.
    // A bigger mark at small sizes, so it still reads.
    let markSide: CGFloat = size <= 64 ? 700 : 612
    let box = CGRect(x: 512 - markSide / 2, y: 512 - markSide / 2 + 6, width: markSide, height: markSide)
    let leaves = CloverGlyph.leaves(in: box)
    let stem = CloverGlyph.stem(in: box)
    let white = gradient([(0, color(0xFFFFFF)), (1, color(0xDDF7E6))])

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16 * k), blur: 26 * k, color: color(0x0B5A2C, 0.36))
    context.setFillColor(color(0xFFFFFF))
    context.addPath(leaves)
    context.addPath(stem)
    context.fillPath()
    context.restoreGState()

    for part in [leaves, stem] {
        context.saveGState()
        context.addPath(part)
        context.clip()
        context.drawLinearGradient(white, start: CGPoint(x: 512, y: box.maxY), end: CGPoint(x: 512, y: box.minY), options: [])
        context.restoreGState()
    }

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path)") }
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in sizes {
    writePNG(drawIcon(size: entry.pixels), to: folder.appendingPathComponent(entry.name + ".png"))
}
SWIFT

swiftc -O -o "$WORK/make-icon" "$WORK/main.swift" Sources/Clover/Home/CloverGlyph.swift
"$WORK/make-icon" "$WORK/Clover.iconset"
mkdir -p Resources
iconutil -c icns "$WORK/Clover.iconset" -o Resources/Clover.icns

if [ -n "${ICONSET_DIR:-}" ]; then
  mkdir -p "$ICONSET_DIR"
  cp "$WORK/Clover.iconset/"*.png "$ICONSET_DIR/"
fi
echo "Wrote Resources/Clover.icns"
