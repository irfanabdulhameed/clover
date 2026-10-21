#!/bin/bash
# Runs every route the built-in converters (images, WebP, SVG, PDF, documents, archives) offer, on
# sample files made on this Mac. Nothing is downloaded and everything lives in a temp folder that is
# deleted at the end. Prints a pass/fail table; the exit status is 1 when anything failed.
#
#   scripts/check-builtin.sh                 build, then check everything
#   SKIP_BUILD=1 scripts/check-builtin.sh    use the build that is already there
#   ONLY=svg scripts/check-builtin.sh        only samples whose file name contains "svg"
#   KEEP=1 scripts/check-builtin.sh          keep the temp folder (its path is printed)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "${SKIP_BUILD:-0}" != 1 ]; then
  nice -n 10 swift build --product Clover 2>&1 | tail -3 || true
fi
CLOVER="${CLOVER:-$ROOT/.build/debug/Clover}"
[ -x "$CLOVER" ] || { echo "No build at $CLOVER. Run swift build first."; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/clover-check.XXXXXX")"
SAMPLES="$WORK/samples"
CASES="$WORK/cases"
mkdir -p "$SAMPLES" "$CASES"
cleanup() {
  if [ "${KEEP:-0}" = 1 ]; then echo "Kept $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------------------------
# A small Swift tool: draws sample pictures and reopens outputs to check what is really inside.
# ---------------------------------------------------------------------------------------------
cat > "$WORK/tool.swift" <<'SWIFT'
import Foundation
import AppKit
import ImageIO
import PDFKit

func bail(_ message: String) -> Never {
    print("FAIL \(message)")
    exit(1)
}

/// Red square top-left, blue square bottom-right; transparent elsewhere when `alpha`, else yellow.
func draw(width: Int, height: Int, alpha: Bool, space: CGColorSpace) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if !alpha {
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: height - height / 4, width: width / 4, height: height / 4))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: width - width / 4, y: 0, width: width / 4, height: height / 4))
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ path: String, type: String, props: [CFString: Any] = [:]) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    if !CGImageDestinationFinalize(dest) { bail("could not write \(path)") }
}

struct Opened {
    let image: CGImage
    let props: [CFString: Any]
    let type: String
    var orientation: Int { props[kCGImagePropertyOrientation] as? Int ?? 1 }
    var upright: (Int, Int) { orientation >= 5 ? (image.height, image.width) : (image.width, image.height) }
    var hasAlpha: Bool { switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return false; default: return true } }
}

func open(_ path: String) -> Opened? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let type = CGImageSourceGetType(src) as String?,
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return Opened(image: img, props: CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:], type: type)
}

/// r g b a (0...255, not premultiplied) at x,y counted from the top-left of the stored picture.
func pixel(_ o: Opened, _ x: Int, _ y: Int) -> [Int] {
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(o.image, in: CGRect(x: -x, y: -(o.image.height - 1 - y), width: o.image.width, height: o.image.height))
    let a = Int(px[3])
    func s(_ v: UInt8) -> Int { a == 0 ? 0 : min(255, Int(v) * 255 / a) }
    return [s(px[0]), s(px[1]), s(px[2]), a]
}

func list(_ path: String) -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
    p.arguments = ["-tf", path]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try? p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { bail("no command") }

switch command {
case "alpha-png":
    save(draw(width: 240, height: 160, alpha: true, space: CGColorSpace(name: CGColorSpace.sRGB)!), args[1], type: "public.png")

case "oriented-jpg":
    // Stored 200x100 with orientation 6: shows as 100x200. Display P3, with some EXIF.
    save(draw(width: 200, height: 100, alpha: false, space: CGColorSpace(name: CGColorSpace.displayP3)!), args[1], type: "public.jpeg", props: [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "CloverTest"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "hello clover"],
    ])

case "noise-png":
    // 900x900 noise: flate-compressed images of it are big, JPEG ones are small.
    var bytes = [UInt8](repeating: 255, count: 900 * 900 * 4)
    var seed: UInt64 = 7
    for i in 0..<bytes.count where i % 4 != 3 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        bytes[i] = UInt8(truncatingIfNeeded: seed >> 33) & 0xF0 | 0x08
    }
    let image = CGImage(width: 900, height: 900, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 3600, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: CGDataProvider(data: Data(bytes) as CFData)!,
                        decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    save(image, args[1], type: "public.png")

case "frames":
    // frames <type> <out>: two 64x64 frames, the first red and the second blue (an animated GIF, or a two-page TIFF).
    func solid(_ r: CGFloat, _ b: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: r, green: 0, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return ctx.makeImage()!
    }
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, args[1] as CFString, 2, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (r, b) in [(CGFloat(1), CGFloat(0)), (CGFloat(0), CGFloat(1))] {
        CGImageDestinationAddImage(dest, solid(r, b), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
    }
    if !CGImageDestinationFinalize(dest) { bail("could not write frames") }

case "locked-pdf":
    // args: source.pdf out.pdf
    let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
    if !doc.write(to: URL(fileURLWithPath: args[2]), withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "secret"]) { bail("could not lock") }

case "info":
    guard let o = open(args[1]) else { bail("cannot read \(args[1])") }
    let tiff = o.props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    let exif = o.props[kCGImagePropertyExifDictionary] as? [CFString: Any]
    print("w=\(o.image.width) h=\(o.image.height) orient=\(o.orientation) upright=\(o.upright.0)x\(o.upright.1) alpha=\(o.hasAlpha) space=\(o.image.colorSpace?.name as String? ?? "none") make=\(tiff?[kCGImagePropertyTIFFMake] ?? "-") comment=\(exif?[kCGImagePropertyExifUserComment] ?? "-")")

case "check":
    // check <target-id> <path> [key=value ...]  ->  "OK details" or "FAIL reason"
    let target = args[1], path = args[2]
    var want: [String: String] = [:]
    for a in args.dropFirst(3) {
        let parts = a.split(separator: "=", maxSplits: 1).map(String.init)
        want[parts[0]] = parts.count > 1 ? parts[1] : "1"
    }
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { bail("missing \(path)") }
    var detail: [String] = []
    let imageTypes = ["jpg": "public.jpeg", "png": "public.png", "heic": "public.heic", "avif": "public.avif", "tiff": "public.tiff",
                      "gif": "com.compuserve.gif", "bmp": "com.microsoft.bmp", "webp": "org.webmproject.webp",
                      "ico": "com.microsoft.ico", "icns": "com.apple.icns"]
    if target != "folder" {
        guard !isDir.boolValue else { bail("expected a file, got a folder") }
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size > 0 else { bail("empty file") }
        detail.append("\(size) B")
    }

    if let uti = imageTypes[target] {
        guard let o = open(path) else { bail("does not open as an image") }
        guard o.type == uti else { bail("type is \(o.type), expected \(uti)") }
        detail.append("\(o.image.width)x\(o.image.height)")
        if let v = want["upright"] { guard "\(o.upright.0)x\(o.upright.1)" == v else { bail("upright size \(o.upright.0)x\(o.upright.1), expected \(v)") } }
        if let v = want["orient"] { guard "\(o.orientation)" == v else { bail("orientation \(o.orientation), expected \(v)") } }
        if let v = want["space"] { guard (o.image.colorSpace?.name as String? ?? "").contains(v) else { bail("colour space \(o.image.colorSpace?.name as String? ?? "none"), expected \(v)") } }
        if let v = want["make"] {
            let make = (o.props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String
            guard make == v else { bail("camera make \(make ?? "missing"), expected \(v)") }
        }
        if let v = want["transparent"] {
            let xy = v.split(separator: ",").map { Int($0)! }
            let p = pixel(o, xy[0], xy[1])
            guard p[3] < 12 else { bail("pixel \(v) is not transparent: \(p)") }
        }
        if let v = want["white"] {
            let xy = v.split(separator: ",").map { Int($0)! }
            let p = pixel(o, xy[0], xy[1])
            guard p[0] > 240 && p[1] > 240 && p[2] > 240 && p[3] == 255 else { bail("pixel \(v) is not white: \(p)") }
        }
        if let v = want["red"] {
            let xy = v.split(separator: ",").map { Int($0)! }
            let p = pixel(o, xy[0], xy[1])
            guard p[0] > 190 && p[1] < 90 && p[2] < 90 && p[3] > 200 else { bail("pixel \(v) is not red: \(p)") }
        }
        if want["square"] != nil { guard o.image.width == o.image.height else { bail("not square: \(o.image.width)x\(o.image.height)") } }
        if let v = want["maxside"] { guard max(o.image.width, o.image.height) <= Int(v)! else { bail("larger than \(v) px") } }
        if target == "icns" || target == "ico" {
            let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
            var sizes: [Int] = []
            for i in 0..<CGImageSourceGetCount(src) {
                let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
                let w = p?[kCGImagePropertyPixelWidth] as? Int ?? 0, h = p?[kCGImagePropertyPixelHeight] as? Int ?? 0
                guard w == h else { bail("icon image \(i) is \(w)x\(h), not square") }
                sizes.append(w)
            }
            detail.append("sizes \(sizes.sorted().map(String.init).joined(separator: ","))")
            if let v = want["sizes"] {
                let need = v.split(separator: ",").map { Int($0)! }
                guard need.allSatisfy(sizes.contains) else { bail("icon sizes \(sizes.sorted()), expected \(need)") }
            }
        }
    } else if target == "pdf" || target == "pdf-compress" || target == "pdf-merge" {
        guard let doc = PDFDocument(url: URL(fileURLWithPath: path)), !doc.isLocked else { bail("does not open as a PDF") }
        detail.append("\(doc.pageCount) page(s)")
        if let v = want["pages"] { guard doc.pageCount == Int(v)! else { bail("\(doc.pageCount) pages, expected \(v)") } }
        if let v = want["minpages"] { guard doc.pageCount >= Int(v)! else { bail("\(doc.pageCount) pages, expected at least \(v)") } }
        if let v = want["has"] { guard doc.string?.contains(v) == true else { bail("text \"\(v)\" not found") } }
        if let v = want["size"] {
            let s = doc.page(at: 0)!.bounds(for: .mediaBox).size
            guard "\(Int(s.width))x\(Int(s.height))" == v else { bail("page size \(Int(s.width))x\(Int(s.height)), expected \(v)") }
        }
        if want["colorful"] != nil {
            // Draw page 1 and look for strongly coloured pixels: pictures in the document, not black text.
            let page = doc.page(at: 0)!
            let box = page.bounds(for: .mediaBox)
            let ctx = CGContext(data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: box.size))
            page.draw(with: .mediaBox, to: ctx)
            let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
            var coloured = 0
            for i in 0..<(ctx.width * ctx.height) {
                let r = Int(data[i * 4]), b = Int(data[i * 4 + 2])
                if abs(r - b) > 150 { coloured += 1 }
            }
            guard coloured > 200 else { bail("no picture drawn on page 1 (\(coloured) coloured pixels)") }
            detail.append("picture on page 1")
        }
        if let v = want["page1"] { guard doc.page(at: 0)?.string?.contains(v) == true else { bail("page 1 does not start with \"\(v)\"") } }
        if let v = want["lastpage"] { guard doc.page(at: doc.pageCount - 1)?.string?.contains(v) == true else { bail("last page does not hold \"\(v)\"") } }
    } else if target == "txt" {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else { bail("not UTF-8 text") }
        if let v = want["has"] { guard text.contains(v) else { bail("text \"\(v)\" not found") } }
        guard !text.contains("\u{FFFC}") else { bail("contains attachment characters") }
    } else if target == "docx" || target == "rtf" || target == "html" {
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        switch target {
        case "docx": guard data.prefix(2) == Data("PK".utf8) else { bail("not a zip package") }
        case "rtf": guard String(decoding: data.prefix(6), as: UTF8.self).hasPrefix("{\\rtf") else { bail("not RTF") }
        default: guard String(decoding: data, as: UTF8.self).lowercased().contains("<html") else { bail("not HTML") }
        }
        let type: NSAttributedString.DocumentType = target == "docx" ? .officeOpenXML : target == "rtf" ? .rtf : .html
        // This runs on the main thread, which HTML import needs.
        guard let text = try? NSAttributedString(url: URL(fileURLWithPath: path), options: [.documentType: type], documentAttributes: nil) else {
            bail("does not reopen as \(target)")
        }
        if let v = want["has"] { guard text.string.contains(v) else { bail("text \"\(v)\" not found") } }
    } else if target == "zip" || target == "tgz" {
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        if target == "zip" { guard data.prefix(2) == Data("PK".utf8) else { bail("not a zip") } }
        else { guard data.prefix(2) == Data([0x1f, 0x8b]) else { bail("not gzip") } }
        let entries = list(path)
        guard !entries.isEmpty else { bail("archive lists no entries") }
        detail.append("\(entries.count) entries")
        let names = Set(entries)
        if let v = want["members"] { for m in v.split(separator: ",") where !names.contains(String(m)) { bail("\(m) is not in the archive") } }
        if let v = want["exact"] { guard names == Set(v.split(separator: ",").map(String.init)) else { bail("entries are \(names.sorted()), expected \(v)") } }
        for entry in entries where entry.contains(".DS_Store") || entry.contains("__MACOSX") || entry.split(separator: "/").last?.hasPrefix("._") == true {
            bail("archive holds \(entry)")
        }
    } else if target == "folder" {
        var items = ((try? fm.subpathsOfDirectory(atPath: path)) ?? [])
        if !isDir.boolValue { // a single decompressed file
            guard ((try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0) > 0 else { bail("empty") }
            items = []
        } else {
            guard !items.isEmpty else { bail("empty folder") }
        }
        detail.append(isDir.boolValue ? "\(items.count) items" : "file")
        if let v = want["paths"] { for p in v.split(separator: ",") where !items.contains(String(p)) { bail("\(p) is missing") } }
        if let v = want["top"] {
            let top = ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted()
            guard top == v.split(separator: ",").map(String.init).sorted() else { bail("top level is \(top), expected \(v)") }
        }
        if let v = want["text"] {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8), text.contains(v) else { bail("file text does not hold \"\(v)\"") }
        }
        guard !items.contains(where: { $0.contains("__MACOSX") }) else { bail("__MACOSX was left in") }
    } else {
        bail("don't know how to check target \(target)")
    }
    print("OK \(detail.joined(separator: ", "))")

default:
    bail("unknown command \(command)")
}
SWIFT
echo "Compiling the check tool..."
if ! nice -n 10 swiftc -O "$WORK/tool.swift" -o "$WORK/tool" 2>"$WORK/tool-build.txt"; then
  cat "$WORK/tool-build.txt"; exit 2
fi
TOOL="$WORK/tool"

# ---------------------------------------------------------------------------------------------
# Sample files
# ---------------------------------------------------------------------------------------------
echo "Making samples..."
S="$SAMPLES"
"$TOOL" alpha-png "$S/alpha.png"
"$TOOL" oriented-jpg "$S/phone.jpg"
"$TOOL" noise-png "$WORK/noise.png"
# an animated GIF and a two-page TIFF: only the first frame (red) may be used
"$TOOL" frames com.compuserve.gif "$S/anim.gif"
"$TOOL" frames public.tiff "$S/multipage.tiff"
# pictures from sips, in the formats it can write
for fmt in jpeg:jpg heic:heic tiff:tiff gif:gif bmp:bmp psd:psd tga:tga jp2:jp2; do
  sips -s format "${fmt%%:*}" "$S/alpha.png" --out "$S/pic.${fmt##*:}" >/dev/null 2>&1 || echo "  (sips could not make pic.${fmt##*:})"
done
# SVG, written by hand
cat > "$S/logo.svg" <<'SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="120" viewBox="0 0 200 120">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f59e0b"/><stop offset="1" stop-color="#ef4444"/></linearGradient></defs>
  <rect x="10" y="10" width="80" height="50" rx="8" fill="url(#g)"/>
  <circle cx="150" cy="85" r="25" fill="#2563eb"/>
  <text x="100" y="112" font-family="Helvetica" font-size="14" text-anchor="middle" fill="#111">Clover sample</text>
</svg>
SVG
cat > "$S/icon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#16a34a"/></svg>
SVG
# documents, from one HTML page
{
  echo '<html><head><meta charset="utf-8"><title>Clover sample</title></head><body><h1>Clover sample document</h1>'
  for i in $(seq 1 60); do
    echo "<p>Paragraph $i. The quick brown fox jumps over the lazy dog, past the old stone wall by the river, with <b>bold words</b> and <i>italic words</i> for a while.</p>"
  done
  echo '<ul><li>One</li><li>Two</li></ul></body></html>'
} > "$S/sample.html"
for fmt in docx doc rtf rtfd odt webarchive txt; do
  textutil -convert "$fmt" "$S/sample.html" -output "$S/sample.$fmt" 2>/dev/null || echo "  (textutil could not make sample.$fmt)"
done
# a document with a picture in it (900 px wide: wider than the text area, so it has to be shrunk)
mkdir -p "$WORK/doc"; cp "$S/alpha.png" "$WORK/doc/alpha.png"
echo '<html><body><p>Clover picture document</p><img src="alpha.png" width="900"><p>After the picture.</p></body></html>' > "$WORK/doc/withimage.html"
textutil -convert rtfd "$WORK/doc/withimage.html" -output "$S/withimage.rtfd" 2>/dev/null || echo "  (textutil could not make withimage.rtfd)"
# PDFs: a text one made by Clover itself from the RTF (several pages), a picture one from sips, a photo-like one
"$CLOVER" convert pdf "$S/sample.rtf" >/dev/null 2>&1 && mv "$S/sample.pdf" "$S/multi.pdf"
sips -s format pdf "$S/alpha.png" --out "$S/onepage.pdf" >/dev/null 2>&1
"$CLOVER" convert pdf "$WORK/noise.png" >/dev/null 2>&1 && mv "$WORK/noise.pdf" "$S/photos.pdf"
"$TOOL" locked-pdf "$S/onepage.pdf" "$S/locked.pdf"
# a file that only pretends to be a picture
head -c 3000 /dev/urandom > "$S/broken.png"
# archives, from a folder
TREE="$WORK/tree"
mkdir -p "$TREE/Holiday/sub" "$TREE/Other"
echo "one" > "$TREE/Holiday/one.txt"; echo "two" > "$TREE/Holiday/sub/two.txt"; echo "o" > "$TREE/Other/o.txt"; echo "f" > "$TREE/f.txt"
xattr -w com.example.test hello "$TREE/Holiday/one.txt" 2>/dev/null
( cd "$TREE" && ditto -c -k --sequesterRsrc --keepParent Holiday "$S/Holiday.zip" )
( cd "$TREE" && tar czf "$S/Holiday.tar.gz" Holiday )
( cd "$TREE" && tar cf "$S/flat.tar" f.txt Other && tar cjf "$S/flat.tar.bz2" f.txt Other && tar cJf "$S/flat.tar.xz" f.txt Other )
( cd "$TREE" && zip -qr "$S/flat.zip" f.txt Other )
echo "single file text" > "$WORK/notes.txt" && gzip -c "$WORK/notes.txt" > "$S/notes.txt.gz"
# the plain folder, with Finder leftovers inside that archiving must leave out
echo "junk" > "$TREE/Holiday/.DS_Store"
mkdir -p "$TREE/Holiday/__MACOSX" && echo "junk" > "$TREE/Holiday/__MACOSX/x"
cp -R "$TREE/Holiday" "$S/Holiday"
# the phone picture as HEIC and TIFF, made by Clover: they keep the orientation tag, so they test reading it back
for t in heic tiff; do
  mkdir -p "$WORK/seed2"; cp "$S/phone.jpg" "$WORK/seed2/phone.jpg"
  out="$("$CLOVER" convert "$t" "$WORK/seed2/phone.jpg" 2>/dev/null | head -1)"
  [ -n "$out" ] && mv "$out" "$S/phone.$t"
done
# derived pictures: WebP, AVIF, ICO and ICNS made by Clover from the PNG become inputs too
for t in webp avif ico icns; do
  mkdir -p "$WORK/seed"; cp "$S/alpha.png" "$WORK/seed/seed.png"
  out="$("$CLOVER" convert "$t" "$WORK/seed/seed.png" 2>/dev/null | head -1)"
  [ -n "$out" ] && mv "$out" "$S/pic.$t"
done
# EXR from sips. Camera RAW can't be made here: it goes through the same ImageIO reader as the rest.
sips -s format exr "$S/alpha.png" --out "$S/pic.exr" >/dev/null 2>&1 || rm -f "$S/pic.exr"

# ---------------------------------------------------------------------------------------------
# Running and checking
# ---------------------------------------------------------------------------------------------
PASS=0; FAIL=0; ROWS=()
CASE_N=0
record() { # status input route note
  local status="$1"
  if [ "$status" = PASS ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
  ROWS+=("$(printf '%-5s %-24s %-22s %s' "$@")")
}

# Expectations for an image output, from what the source is.
image_expectations() { # input-name target
  local name="$1" target="$2" exp=() info
  info="$("$TOOL" info "$SAMPLES/$name" 2>/dev/null)"
  local upright; upright="$(echo "$info" | sed -n 's/.*upright=\([0-9x]*\).*/\1/p')"
  # ImageIO can't open SVG; icon files hold several sizes and the tool reads the first one.
  case "$name" in
    logo.svg) upright=400x240 ;;
    icon.svg) upright=48x48 ;;
    pic.ico|pic.icns) upright= ;;
  esac
  case "$target" in
    ico) exp+=(square maxside=256) ;;
    icns) exp+=(square) ;;
    *) [ -n "$upright" ] && exp+=("upright=$upright") ;;
  esac
  case "$name:$target" in
    alpha.png:jpg|alpha.png:bmp) exp+=(white=120,80) ;;
    alpha.png:png|alpha.png:tiff|alpha.png:heic|alpha.png:avif|alpha.png:webp) exp+=(transparent=120,80 red=30,20) ;;
    alpha.png:ico) exp+=(transparent=128,2) ;;
    alpha.png:icns) exp+=(sizes=16,32,64,128) ;;
    logo.svg:png) exp+=(transparent=2,2) ;;
    icon.svg:png) exp+=(transparent=1,1) ;;
  esac
  case "$name" in
    phone.jpg|phone.heic|phone.tiff)
      # Stored 200x100 with orientation 6, Display P3, camera make "CloverTest". The red square is stored
      # top-left. JPEG, HEIC and TIFF keep the orientation tag, so it stays there; the others have the picture
      # turned upright, which moves the red square to the top right.
      case "$target" in
        jpg|heic|tiff) exp+=(orient=6 make=CloverTest space=DisplayP3 red=25,12) ;;
        png) exp+=(orient=1 make=CloverTest space=DisplayP3 red=88,12) ;;
        avif|webp) exp+=(orient=1 space=DisplayP3 red=88,12) ;;
        gif|bmp) exp+=(orient=1 red=88,12) ;;
      esac ;;
    anim.gif|multipage.tiff) exp+=(red=10,10) ;; # first frame only
  esac
  echo "${exp[@]}"
}

# Runs one conversion in a fresh folder and checks it.
#   run_route <label> <target> <option|-> <expect> <inputs...>
# expect: "ok" (default checks), "fail:<text>" (must fail with that text), or "ok:<extra check args>"
run_route() {
  local label="$1" target="$2" option="$3" expect="$4"; shift 4
  CASE_N=$((CASE_N + 1))
  local dir="$CASES/$CASE_N"; mkdir -p "$dir"
  local inputs=()
  mkdir -p "$dir/in"
  for src in "$@"; do
    cp -R "$src" "$dir/in/"
    inputs+=("$dir/in/$(basename "$src")")
  done
  local args=(convert "$target"); [ "$option" != "-" ] && args+=(--option "$option")
  local must_shrink=0
  case "$expect" in *must-shrink*) must_shrink=1; expect="${expect//must-shrink/}" ;; esac

  # Before: what is in the input folder, and a checksum of every input file.
  ls -A "$dir/in" | sort > "$dir/before.txt"
  find "$dir/in" -type f -print0 | xargs -0 shasum > "$dir/sums.txt" 2>/dev/null
  rm -rf "$WORK/tmp"; mkdir -p "$WORK/tmp"
  local out status
  out="$(TMPDIR="$WORK/tmp" nice -n 10 "$CLOVER" "${args[@]}" "${inputs[@]}" 2>"$dir/stderr.txt")"; status=$?
  local err; err="$(cat "$dir/stderr.txt")"
  local route="$target"; [ "$option" != "-" ] && route="$target:$option"

  # The input must be untouched, nothing may be left in the temp folder, and the only new things
  # beside the input are the files the CLI says it made.
  local problem=""
  shasum -c "$dir/sums.txt" >/dev/null 2>&1 || problem="an input file was changed or removed"
  [ -z "$(find "$WORK/tmp" -mindepth 2 2>/dev/null | head -1)" ] || problem="temp files were left behind: $(find "$WORK/tmp" -mindepth 2 | head -1)"
  ls -A "$dir/in" | sort > "$dir/after.txt"
  local new made
  new="$(comm -13 "$dir/before.txt" "$dir/after.txt")"
  made="$(printf '%s\n' "$out" | while IFS= read -r p; do [ -n "$p" ] && basename "$p"; done | sort)"
  [ "$new" = "$made" ] || problem="new files beside the input ($(echo $new)) don't match the printed outputs ($(echo $made))"
  if [ -n "$problem" ]; then record FAIL "$label" "$route" "$problem"; return; fi

  case "$expect" in
    fail:*)
      if [ $status -ne 0 ] && echo "$err" | grep -qi "${expect#fail:}"; then
        record PASS "$label" "$route" "refused as expected: ${err#failed *: }"
      else
        record FAIL "$label" "$route" "expected a failure mentioning \"${expect#fail:}\", got status $status: $err $out"
      fi
      return ;;
  esac

  if [ $status -ne 0 ]; then
    # Compressing a PDF that can't get smaller is an honest answer, not a bug.
    if [ "$target" = pdf-compress ] && [ $must_shrink = 0 ] && echo "$err" | grep -q "already as small as Clover can make it"; then
      record PASS "$label" "$route" "declined: already as small as it can be"
    else
      record FAIL "$label" "$route" "status $status: $err"
    fi
    return
  fi
  [ -n "$out" ] || { record FAIL "$label" "$route" "no output path printed"; return; }
  if [ "$target" = pdf-compress ] && [ "$(stat -f %z "$out")" -ge "$(stat -f %z "${inputs[0]}")" ]; then
    record FAIL "$label" "$route" "compressed file is not smaller than the original"; return
  fi

  local extra=()
  [ "$expect" != ok ] && read -r -a extra <<< "${expect#ok:}"
  local result="" bad=0 count=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    count=$((count + 1))
    local file_target="$target"
    case "$target" in pdf-compress|pdf-merge) file_target=pdf ;; esac
    # A folder of page pictures, one check per picture.
    if [ -d "$path" ] && { [ "$target" = png ] || [ "$target" = jpg ]; }; then
      local pages="${PAGES_EXPECTED:-0}" n=0 base; base="$(basename "$path")"
      for f in "$path"/*; do
        n=$((n + 1))
        r="$("$TOOL" check "$target" "$f" "${extra[@]}" 2>&1)" || { bad=1; result="$r ($(basename "$f"))"; break; }
        echo "$(basename "$f")" | grep -Eq "^$base [0-9]{2,}\.$target\$" || { bad=1; result="bad page name $(basename "$f")"; break; }
      done
      [ $bad = 0 ] && [ "$pages" -gt 0 ] && [ "$n" -ne "$pages" ] && { bad=1; result="$n page files, expected $pages"; }
      [ $bad = 0 ] && result="$n page files"
    else
      result="$("$TOOL" check "$file_target" "$path" "${extra[@]}" 2>&1)" || bad=1
    fi
    [ $bad = 1 ] && break
  done <<< "$out"
  if [ $bad = 1 ]; then
    record FAIL "$label" "$route" "${result#FAIL }"
  else
    record PASS "$label" "$route" "${result#OK }"
  fi
}

# Every target (and every option) the catalog offers for one sample.
all_routes() { # sample-name [extra expectation words]
  local name="$1" file="$SAMPLES/$1"
  local lines; lines="$("$CLOVER" targets "$file" 2>/dev/null)"
  while IFS=$'\t' read -r id title opts; do
    [ -n "$id" ] || continue
    case "$id" in zip|tgz) continue ;; esac # archiving is checked with many inputs below
    case "$id" in mp4|mov|mkv|webm|mp3|m4a|wav|flac|aiff|ogg|opus) continue ;; esac # ffmpeg's routes aren't part of this check
    local expect=ok
    case "$id" in
      jpg|png|heic|avif|tiff|gif|bmp|webp|ico|icns)
        case "$name" in
          *.pdf) expect=ok ;;
          *) expect="ok:$(image_expectations "$name" "$id")" ;;
        esac ;;
    esac
    case "$name:$id" in
      logo.svg:pdf) expect="ok:pages=1 has=Clover size=200x120" ;;
      pic.ico:pdf|pic.icns:pdf) expect="ok:pages=1" ;;
      pic.*:pdf|alpha.png:pdf) expect="ok:pages=1 size=240x160" ;;
      onepage.pdf:txt|photos.pdf:txt) expect="fail:No text found" ;; # pictures only: nothing to read
      phone.*:pdf) expect="ok:pages=1 size=100x200" ;;
      anim.gif:pdf|multipage.tiff:pdf) expect="ok:pages=1 size=64x64" ;;
      withimage.*:pdf) expect="ok:pages=1 colorful has=Clover" ;; # the picture is drawn, shrunk to fit the page
      withimage.*:txt|withimage.*:docx|withimage.*:rtf|withimage.*:html) expect="ok:has=Clover" ;;
      sample.*:pdf) expect="ok:minpages=3 has=Paragraph" ;;
      sample.*:jpg|sample.*:png) expect=ok ;;
      sample.*:txt|sample.*:docx|sample.*:rtf|sample.*:html) expect="ok:has=Paragraph" ;;
      multi.pdf:txt) expect="ok:has=Paragraph" ;;
      multi.pdf:pdf-compress) expect="ok:minpages=3 has=Paragraph" ;;
      photos.pdf:pdf-compress) expect="ok:pages=1 must-shrink" ;; # a PDF full of photo data: both options must really shrink it
      onepage.pdf:pdf-compress) expect="ok:pages=1" ;;
      Holiday.zip:folder|Holiday.tar.gz:folder) expect="ok:top=one.txt,sub paths=sub/two.txt" ;;
      flat.*:folder) expect="ok:top=f.txt,Other paths=Other/o.txt" ;;
      notes.txt.gz:folder) expect="ok:text=single" ;;
    esac
    PAGES_EXPECTED=0
    case "$name" in multi.pdf) PAGES_EXPECTED="$(ls_pages "$file")" ;; esac
    if [ -z "$opts" ]; then
      run_route "$name" "$id" - "$expect" "$file"
    else
      for o in $opts; do
        o="${o#[}"; o="${o%]}"
        run_route "$name" "$id" "$o" "$expect" "$file"
      done
    fi
  done <<< "$lines"
}

ls_pages() { "$TOOL" check pdf "$1" 2>/dev/null | sed -n 's/.*, \([0-9]*\) page(s).*/\1/p; s/.* \([0-9]*\) page(s).*/\1/p' | head -1; }

echo "Running every route on every sample..."
for file in "$SAMPLES"/*; do
  name="$(basename "$file")"
  [ -n "${ONLY:-}" ] && ! echo "$name" | grep -q "$ONLY" && continue
  case "$name" in
    broken.png|locked.pdf) continue ;; # checked on purpose below
  esac
  [ -d "$file" ] && continue # the plain folder is an input for archiving, below
  all_routes "$name"
done

if [ -z "${ONLY:-}" ] || echo "many broken locked archive" | grep -q "$ONLY"; then
echo "Running the combine routes and the refusals..."
# Many files into one
run_route "3 pictures" pdf combine "ok:pages=3" "$SAMPLES/alpha.png" "$SAMPLES/pic.jpg" "$SAMPLES/phone.jpg"
run_route "3 pictures" pdf each ok "$SAMPLES/alpha.png" "$SAMPLES/pic.jpg" "$SAMPLES/phone.jpg"
run_route "pdf + picture" pdf combine "ok:pages=$(( $(ls_pages "$SAMPLES/multi.pdf") + 1 ))" "$SAMPLES/multi.pdf" "$SAMPLES/phone.jpg"
run_route "2 pdfs" pdf-merge - "ok:pages=$(( $(ls_pages "$SAMPLES/multi.pdf") + 1 )) page1=Clover" "$SAMPLES/multi.pdf" "$SAMPLES/onepage.pdf"
run_route "folder+files" zip - "ok:members=Holiday/,Holiday/one.txt,Holiday/sub/two.txt,alpha.png,sample.txt" "$SAMPLES/Holiday" "$SAMPLES/alpha.png" "$SAMPLES/sample.txt"
run_route "folder+files" tgz - "ok:members=Holiday/,Holiday/one.txt,alpha.png" "$SAMPLES/Holiday" "$SAMPLES/alpha.png" "$SAMPLES/sample.txt"
run_route "one folder" zip - "ok:exact=Holiday/,Holiday/one.txt,Holiday/sub/,Holiday/sub/two.txt" "$SAMPLES/Holiday"
run_route "one folder" tgz - "ok:members=Holiday/one.txt" "$SAMPLES/Holiday"
run_route "mixed files" zip - "ok:members=alpha.png,multi.pdf,logo.svg" "$SAMPLES/alpha.png" "$SAMPLES/multi.pdf" "$SAMPLES/logo.svg"
# Big batches (they run several at a time)
run_route "8 documents" pdf - "ok:minpages=3 has=Paragraph" "$SAMPLES/sample.docx" "$SAMPLES/sample.rtf" "$SAMPLES/sample.odt" "$SAMPLES/sample.doc" \
  "$SAMPLES/sample.txt" "$SAMPLES/sample.html" "$SAMPLES/sample.webarchive" "$SAMPLES/sample.rtfd"
run_route "12 pictures" jpg best ok "$SAMPLES/alpha.png" "$SAMPLES/pic.heic" "$SAMPLES/pic.tiff" "$SAMPLES/pic.gif" "$SAMPLES/pic.bmp" "$SAMPLES/pic.psd" \
  "$SAMPLES/pic.tga" "$SAMPLES/pic.jp2" "$SAMPLES/phone.jpg" "$SAMPLES/pic.webp" "$SAMPLES/pic.avif" "$SAMPLES/logo.svg"
run_route "6 pictures" webp small ok "$SAMPLES/alpha.png" "$SAMPLES/pic.heic" "$SAMPLES/pic.tiff" "$SAMPLES/phone.jpg" "$SAMPLES/pic.psd" "$SAMPLES/logo.svg"
# Refusals
run_route "broken.png" jpg best "fail:broken.png" "$SAMPLES/broken.png"
run_route "locked.pdf" png - "fail:password" "$SAMPLES/locked.pdf"
run_route "locked.pdf" txt - "fail:password" "$SAMPLES/locked.pdf"
run_route "locked.pdf" pdf-compress small "fail:password" "$SAMPLES/locked.pdf"
fi

# The same sample converted twice must not touch or overwrite the first result.
if [ -z "${ONLY:-}" ]; then
  mkdir -p "$CASES/twice"; cp "$SAMPLES/alpha.png" "$CASES/twice/"
  before="$(shasum "$CASES/twice/alpha.png" | cut -d' ' -f1)"
  "$CLOVER" convert jpg "$CASES/twice/alpha.png" >/dev/null 2>&1; "$CLOVER" convert jpg "$CASES/twice/alpha.png" >/dev/null 2>&1
  after="$(shasum "$CASES/twice/alpha.png" | cut -d' ' -f1)"
  if [ "$before" = "$after" ] && [ -f "$CASES/twice/alpha.jpg" ] && [ -f "$CASES/twice/alpha 2.jpg" ]; then
    record PASS "alpha.png" "jpg x2" "input untouched, second result named \"alpha 2.jpg\""
  else
    record FAIL "alpha.png" "jpg x2" "input changed or second result missing"
  fi
fi

echo
printf '%-5s %-24s %-22s %s\n' STATUS INPUT ROUTE DETAIL
printf '%s\n' "${ROWS[@]}"
echo
echo "Passed: $PASS   Failed: $FAIL   (of $((PASS + FAIL)))"
[ "$FAIL" -eq 0 ]
