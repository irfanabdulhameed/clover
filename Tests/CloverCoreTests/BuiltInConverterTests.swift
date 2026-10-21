import AppKit
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import CloverCore

/// The converters that use macOS's own engines, run on small files made in a temp folder.
struct BuiltInConverterTests {
    let context = StepContext(option: nil, tools: Tools())

    // MARK: Helpers

    func makeTemp() throws -> URL { try OutputPlacer.makeTempDirectory() }

    func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// A PDF with `pages` Letter pages, each saying "Page n".
    func makePDF(pages: Int, at url: URL) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
        for n in 1...pages {
            pdf.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
            NSString(string: "Page \(n)").draw(at: CGPoint(x: 72, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
            NSGraphicsContext.restoreGraphicsState()
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }

    /// A picture with a red square top-left and a blue one bottom-right. Transparent elsewhere when `alpha`, else yellow.
    func makeImage(width: Int, height: Int, alpha: Bool) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !alpha {
            c.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        c.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        c.fill(CGRect(x: 0, y: height - height / 4, width: width / 4, height: height / 4))
        c.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        c.fill(CGRect(x: width - width / 4, y: 0, width: width / 4, height: height / 4))
        return c.makeImage()!
    }

    func write(_ image: CGImage, to url: URL, type: String, properties: [CFString: Any] = [:]) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Colour of the pixel at (x, y) counted from the top-left of the stored picture: r, g, b, a in 0...255.
    func pixel(_ url: URL, _ x: Int, _ y: Int) -> [Int] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var bytes = [UInt8](repeating: 0, count: 4)
        let c = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        let a = Int(bytes[3])
        func straight(_ v: UInt8) -> Int { a == 0 ? 0 : min(255, Int(v) * 255 / a) }
        return [straight(bytes[0]), straight(bytes[1]), straight(bytes[2]), a]
    }

    func properties(_ url: URL) -> [CFString: Any] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func run(_ tool: String, _ arguments: [String]) async throws {
        try await ProcessRunner.run(URL(fileURLWithPath: tool), arguments)
    }

    // MARK: PDF

    @Test func pageFileNamesArePadded() {
        #expect(PDFConverter.pageFileName(baseName: "scan", index: 0, count: 3, fileExtension: "png") == "scan 01.png")
        #expect(PDFConverter.pageFileName(baseName: "scan", index: 11, count: 12, fileExtension: "jpg") == "scan 12.jpg")
        #expect(PDFConverter.pageFileName(baseName: "scan", index: 4, count: 120, fileExtension: "png") == "scan 005.png")
    }

    @Test func manyPagesMakeANumberedFolder() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("report.pdf")
        makePDF(pages: 12, at: input)
        let out = try makeTemp()
        defer { remove(out) }

        let items = try await PDFConverter().convert(input, from: Formats.pdf, to: Formats.png, into: out, baseName: "report", context: context)
        #expect(items.map(\.lastPathComponent) == ["report"])
        let files = try names(in: items[0])
        #expect(files.count == 12)
        #expect(files.first == "report 01.png")
        #expect(files.last == "report 12.png")
        // 2× of Letter: 144 dpi.
        let size = properties(items[0].appendingPathComponent("report 01.png"))
        #expect(size[kCGImagePropertyPixelWidth] as? Int == 1224)
        #expect(size[kCGImagePropertyPixelHeight] as? Int == 1584)
        // Page content is drawn: the heading is dark on white.
        let source = items[0].appendingPathComponent("report 01.png")
        #expect(pixel(source, 5, 5) == [255, 255, 255, 255])
    }

    @Test func onePageMakesOneFile() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("one.pdf")
        makePDF(pages: 1, at: input)
        let out = try makeTemp()
        defer { remove(out) }

        let items = try await PDFConverter().convert(input, from: Formats.pdf, to: Formats.jpg, into: out, baseName: "one", context: context)
        #expect(items.map(\.lastPathComponent) == ["one.jpg"])
        #expect(properties(items[0])[kCGImagePropertyPixelWidth] as? Int == 1224)
    }

    @Test func compressThatCannotShrinkSaysSo() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        // A one-line vector PDF is tiny: turning it into a JPEG page can only make it bigger.
        let input = dir.appendingPathComponent("tiny.pdf")
        makePDF(pages: 1, at: input)
        let out = try makeTemp()
        defer { remove(out) }

        let small = StepContext(option: Options.small, tools: Tools())
        await #expect(throws: ConversionError.failed("This PDF is already as small as Clover can make it.")) {
            try await PDFConverter().convert(input, from: Formats.pdf, to: Formats.pdf, into: out, baseName: "tiny", context: small)
        }
        #expect(try names(in: out).isEmpty)
    }

    @Test func compressShrinksAPDFFullOfPhotos() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        // Noise compresses badly as flate and well enough as JPEG.
        var noise = [UInt8](repeating: 0, count: 1200 * 1200 * 4)
        var seed: UInt64 = 42
        for i in 0..<noise.count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            noise[i] = i % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: seed >> 33) & 0xF0 | 0x08
        }
        let provider = CGDataProvider(data: Data(noise) as CFData)!
        let image = CGImage(width: 1200, height: 1200, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4800,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = dir.appendingPathComponent("noise.png")
        write(image, to: png, type: "public.png")
        let pdf = try makeTemp()
        defer { remove(pdf) }
        let made = try await ImageIOConverter().convert(png, from: Formats.png, to: Formats.pdf, into: pdf, baseName: "noise", context: context)
        let before = OutputPlacer.size(of: made[0])

        for option in [Options.balanced, Options.small] {
            let out = try makeTemp()
            defer { remove(out) }
            let items = try await PDFConverter().convert(made[0], from: Formats.pdf, to: Formats.pdf, into: out, baseName: "noise",
                                                         context: StepContext(option: option, tools: Tools()))
            let after = OutputPlacer.size(of: items[0])
            #expect(after < before, "\(option.id): \(after) is not smaller than \(before)")
            #expect(PDFDocument(url: items[0])?.pageCount == 1)
        }
    }

    @Test func lockedPDFGivesAClearError() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let plain = dir.appendingPathComponent("plain.pdf")
        makePDF(pages: 1, at: plain)
        let locked = dir.appendingPathComponent("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "secret"]))
        let out = try makeTemp()
        defer { remove(out) }
        await #expect(throws: ConversionError.failed("locked.pdf is password-protected. Remove the password first.")) {
            try await PDFConverter().convert(locked, from: Formats.pdf, to: Formats.txt, into: out, baseName: "locked", context: context)
        }
    }

    @Test func pdfToText() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("t.pdf")
        makePDF(pages: 3, at: input)
        let out = try makeTemp()
        defer { remove(out) }
        let items = try await PDFConverter().convert(input, from: Formats.pdf, to: Formats.txt, into: out, baseName: "t", context: context)
        let text = try String(contentsOf: items[0], encoding: .utf8)
        #expect(text.contains("Page 1") && text.contains("Page 3"))
    }

    @Test func mergeKeepsTheOrderGiven() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let a = dir.appendingPathComponent("a.pdf")
        let b = dir.appendingPathComponent("b.pdf")
        makePDF(pages: 2, at: a)
        makePDF(pages: 3, at: b)
        let image = dir.appendingPathComponent("c.png")
        write(makeImage(width: 300, height: 200, alpha: false), to: image, type: "public.png")
        let out = try makeTemp()
        defer { remove(out) }

        let items = try await PDFCombiner().combine([b, image, a], to: Formats.pdf, into: out, baseName: "Combined", context: context)
        #expect(items.map(\.lastPathComponent) == ["Combined.pdf"])
        let merged = PDFDocument(url: items[0])!
        #expect(merged.pageCount == 6)
        #expect(merged.page(at: 0)?.string?.contains("Page 1") == true)
        #expect(merged.page(at: 2)?.string?.contains("Page 3") == true)
        // The picture is page 4, sized like the picture.
        let size = merged.page(at: 3)!.bounds(for: .mediaBox).size
        #expect(Int(size.width) == 300 && Int(size.height) == 200)
        #expect(merged.page(at: 4)?.string?.contains("Page 1") == true)
    }

    // MARK: Images

    @Test func alphaFlattensOnWhiteForJPG() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("alpha.png")
        write(makeImage(width: 240, height: 160, alpha: true), to: input, type: "public.png")
        let out = try makeTemp()
        defer { remove(out) }

        let items = try await ImageIOConverter().convert(input, from: Formats.png, to: Formats.jpg, into: out, baseName: "alpha", context: context)
        let p = pixel(items[0], 120, 80)
        #expect(p[0] > 245 && p[1] > 245 && p[2] > 245 && p[3] == 255, "centre should be white, got \(p)")
        let red = pixel(items[0], 5, 5)
        #expect(red[0] > 200 && red[1] < 80 && red[2] < 80)
    }

    @Test func orientationAndProfileSurvive() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        // Stored 200×100 with orientation 6: it shows as 100×200, turned clockwise.
        let input = dir.appendingPathComponent("phone.jpg")
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let c = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        c.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        c.fill(CGRect(x: 0, y: 75, width: 50, height: 25)) // top-left
        write(c.makeImage()!, to: input, type: "public.jpeg", properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "CloverTest"],
        ])

        // HEIC keeps the tag; PNG has it baked in.
        let heicDir = try makeTemp(), pngDir = try makeTemp()
        defer { remove(heicDir); remove(pngDir) }
        let heic = try await ImageIOConverter().convert(input, from: Formats.jpg, to: Formats.heic, into: heicDir, baseName: "phone", context: context)[0]
        let png = try await ImageIOConverter().convert(input, from: Formats.jpg, to: Formats.png, into: pngDir, baseName: "phone", context: context)[0]

        let heicProps = properties(heic)
        #expect(heicProps[kCGImagePropertyOrientation] as? Int == 6)
        #expect((heicProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String == "CloverTest")
        #expect(heicProps[kCGImagePropertyProfileName] as? String == "Display P3")

        let pngProps = properties(png)
        #expect(pngProps[kCGImagePropertyPixelWidth] as? Int == 100)
        #expect(pngProps[kCGImagePropertyPixelHeight] as? Int == 200)
        #expect(pngProps[kCGImagePropertyProfileName] as? String == "Display P3")
        // A clockwise turn puts the top-left red square at the top-right.
        let topRight = pixel(png, 95, 5)
        #expect(topRight[0] > 200 && topRight[1] < 80)
        let topLeft = pixel(png, 5, 5)
        #expect(topLeft[0] > 200 && topLeft[1] > 200 && topLeft[2] < 120)
    }

    @Test func iconsAreSquareAndComplete() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("logo.png")
        write(makeImage(width: 1200, height: 900, alpha: true), to: input, type: "public.png")
        let out = try makeTemp()
        defer { remove(out) }

        let ico = try await ImageIOConverter().convert(input, from: Formats.png, to: Formats.ico, into: out, baseName: "logo", context: context)[0]
        let icoProps = properties(ico)
        #expect(icoProps[kCGImagePropertyPixelWidth] as? Int == 256)
        #expect(icoProps[kCGImagePropertyPixelHeight] as? Int == 256)
        // The 4:3 picture is padded top and bottom with transparency.
        #expect(pixel(ico, 128, 2)[3] == 0)

        let icns = try await ImageIOConverter().convert(input, from: Formats.png, to: Formats.icns, into: out, baseName: "logo", context: context)[0]
        let source = CGImageSourceCreateWithURL(icns as CFURL, nil)!
        var sizes = Set<Int>()
        for i in 0..<CGImageSourceGetCount(source) {
            let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            #expect(p?[kCGImagePropertyPixelWidth] as? Int == p?[kCGImagePropertyPixelHeight] as? Int)
            sizes.insert(p?[kCGImagePropertyPixelWidth] as? Int ?? 0)
        }
        #expect([16, 32, 64, 128, 256, 512, 1024].allSatisfy(sizes.contains), "got \(sizes.sorted())")
    }

    @Test func imageToPDFIsOnePageTheSizeOfThePicture() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("p.png")
        write(makeImage(width: 320, height: 180, alpha: false), to: input, type: "public.png")
        let out = try makeTemp()
        defer { remove(out) }
        let items = try await ImageIOConverter().convert(input, from: Formats.png, to: Formats.pdf, into: out, baseName: "p", context: context)
        let pdf = PDFDocument(url: items[0])!
        #expect(pdf.pageCount == 1)
        let size = pdf.page(at: 0)!.bounds(for: .mediaBox).size
        #expect(Int(size.width) == 320 && Int(size.height) == 180)
    }

    @Test func avifIsOfferedOnlyWhenThisMacCanWriteIt() {
        let offered = ImageIOConverter().outputs(from: Formats.png).contains(Formats.avif)
        #expect(offered == ImageKit.writableTypes.contains("public.avif"))
        #expect(!ImageIOConverter().outputs(from: Formats.png).contains(Formats.png))
        #expect(ImageIOConverter().outputs(from: Formats.mp4).isEmpty)
    }

    @Test func webpNeedsCwebp() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("w.png")
        write(makeImage(width: 64, height: 64, alpha: true), to: input, type: "public.png")
        let out = try makeTemp()
        defer { remove(out) }
        await #expect(throws: ConversionError.toolMissing("cwebp")) {
            try await WebPConverter().convert(input, from: Formats.png, to: Formats.webp, into: out, baseName: "w", context: context)
        }
        guard let cwebp = Tools.find("cwebp") else { return }
        let real = StepContext(option: Options.small, tools: Tools(cwebp: cwebp))
        let items = try await WebPConverter().convert(input, from: Formats.png, to: Formats.webp, into: out, baseName: "w", context: real)
        #expect(properties(items[0])[kCGImagePropertyPixelWidth] as? Int == 64)
        #expect(pixel(items[0], 32, 32)[3] == 0) // alpha kept (the middle of the picture is transparent)
        #expect(pixel(items[0], 2, 2)[3] == 255) // and the red corner square is solid
    }

    // MARK: SVG

    @Test func svgSizeComesFromWidthHeightThenViewBox() {
        #expect(SVGSize.size(width: "200", height: "120", viewBox: "0 0 10 10").size == CGSize(width: 200, height: 120))
        #expect(SVGSize.size(width: "2in", height: "1in", viewBox: nil).size == CGSize(width: 192, height: 96))
        #expect(SVGSize.size(width: nil, height: nil, viewBox: "0 0 24 12").size == CGSize(width: 24, height: 12))
        #expect(SVGSize.size(width: "100", height: nil, viewBox: "0,0,50,25").size == CGSize(width: 100, height: 50))
        #expect(SVGSize.size(width: "100%", height: "100%", viewBox: nil).size == CGSize(width: 1024, height: 1024))
        #expect(SVGSize.size(width: nil, height: nil, viewBox: nil).explicit == false)
    }

    @Test func svgDrawsToTransparentPNGAndVectorPDF() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let svg = dir.appendingPathComponent("logo.svg")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="60" viewBox="0 0 100 60">
          <rect x="10" y="10" width="40" height="40" fill="#ff0000"/>
          <text x="55" y="40" font-family="Helvetica" font-size="12">Clover</text>
        </svg>
        """.write(to: svg, atomically: true, encoding: .utf8)
        let out = try makeTemp()
        defer { remove(out) }

        let png = try await SVGConverter().convert(svg, from: Formats.svg, to: Formats.png, into: out, baseName: "logo", context: context)[0]
        let props = properties(png)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 120)
        #expect(pixel(png, 2, 2)[3] == 0) // transparent corner
        let red = pixel(png, 40, 40)
        #expect(red[0] > 200 && red[1] < 60 && red[3] == 255)

        let pdf = try await SVGConverter().convert(svg, from: Formats.svg, to: Formats.pdf, into: out, baseName: "logo", context: context)[0]
        let doc = PDFDocument(url: pdf)!
        #expect(doc.pageCount == 1)
        #expect(doc.string?.contains("Clover") == true) // text stayed text
    }

    // MARK: Documents

    @Test func longTextBecomesSeveralLetterPages() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("long.txt")
        let lines = (1...150).map { "Line \($0): the quick brown fox jumps over the lazy dog." }
        try lines.joined(separator: "\n").write(to: input, atomically: true, encoding: .utf8)
        let out = try makeTemp()
        defer { remove(out) }

        let items = try await DocumentConverter().convert(input, from: Formats.txt, to: Formats.pdf, into: out, baseName: "long", context: context)
        let pdf = PDFDocument(url: items[0])!
        #expect(pdf.pageCount >= 3)
        #expect(pdf.page(at: 0)!.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        #expect(pdf.string?.contains("Line 1:") == true && pdf.string?.contains("Line 150:") == true)
    }

    @Test func documentsRoundTripThroughEveryWritableFormat() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let input = dir.appendingPathComponent("memo.txt")
        try "Hello from Clover\nSecond line".write(to: input, atomically: true, encoding: .utf8)
        let converter = DocumentConverter()
        var current = input
        var format = Formats.txt
        for next in [Formats.docx, Formats.rtf, Formats.html, Formats.txt] {
            let out = try makeTemp()
            defer { remove(out) }
            let made = try await converter.convert(current, from: format, to: next, into: out, baseName: "memo", context: context)
            #expect(made.map(\.lastPathComponent) == ["memo.\(next.fileExtension)"])
            // Keep the file: move it into dir under a step name.
            let kept = dir.appendingPathComponent("step-\(next.id).\(next.fileExtension)")
            try FileManager.default.moveItem(at: made[0], to: kept)
            current = kept
            format = next
        }
        let text = try String(contentsOf: current, encoding: .utf8)
        #expect(text.contains("Hello from Clover") && text.contains("Second line"))
    }

    // MARK: Placing results

    @Test func parallelJobsNeverOverwriteEachOther() async throws {
        let dest = try makeTemp()
        defer { remove(dest) }
        // Twenty jobs finish at once, each with a result called "scan.pdf".
        let placed = try await withThrowingTaskGroup(of: URL.self) { group in
            for n in 0..<20 {
                group.addTask {
                    let temp = try OutputPlacer.makeTempDirectory()
                    defer { try? FileManager.default.removeItem(at: temp) }
                    let file = temp.appendingPathComponent("scan.pdf")
                    try "job \(n)".write(to: file, atomically: true, encoding: .utf8)
                    return try OutputPlacer.place([file], in: dest)[0]
                }
            }
            var all: [URL] = []
            for try await url in group { all.append(url) }
            return all
        }
        #expect(Set(placed.map(\.lastPathComponent)).count == 20)
        #expect(try names(in: dest).count == 20)
        let texts = try names(in: dest).map { try String(contentsOf: dest.appendingPathComponent($0), encoding: .utf8) }
        #expect(Set(texts).count == 20)
    }

    // MARK: Archives

    @Test func aSingleTopLevelFolderIsNotNested() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let holiday = dir.appendingPathComponent("Holiday")
        try FileManager.default.createDirectory(at: holiday.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "one".write(to: holiday.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: holiday.appendingPathComponent("sub/two.txt"), atomically: true, encoding: .utf8)

        // A single folder in gives a ZIP whose top level is that folder (like Finder's Compress).
        let zipDir = try makeTemp()
        defer { remove(zipDir) }
        let zip = try await ArchiveCombiner().combine([holiday], to: Formats.zip, into: zipDir, baseName: "photos", context: context)[0]
        #expect(zip.lastPathComponent == "photos.zip")

        let out = try makeTemp()
        defer { remove(out) }
        let items = try await ArchiveExtractor().convert(zip, from: Formats.zip, to: Formats.folder, into: out, baseName: "photos", context: context)
        #expect(items.map(\.lastPathComponent) == ["Holiday"])
        #expect(try names(in: items[0]) == ["one.txt", "sub"])
        #expect(try names(in: out) == ["Holiday"])
    }

    @Test func severalTopLevelItemsGoInAFolderNamedAfterTheArchive() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)
        let tgz = try makeTemp()
        defer { remove(tgz) }
        let archive = try await ArchiveCombiner().combine([a, b], to: Formats.tgz, into: tgz, baseName: "pair", context: context)[0]
        #expect(archive.lastPathComponent == "pair.tar.gz")

        let out = try makeTemp()
        defer { remove(out) }
        let items = try await ArchiveExtractor().convert(archive, from: Formats.tgz, to: Formats.folder, into: out, baseName: "pair", context: context)
        #expect(items.map(\.lastPathComponent) == ["pair"])
        #expect(try names(in: items[0]) == ["a.txt", "b.txt"])
    }

    @Test func macosxFolderIsDropped() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let src = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("Holiday"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: src.appendingPathComponent("__MACOSX/Holiday"), withIntermediateDirectories: true)
        try "x".write(to: src.appendingPathComponent("Holiday/x.txt"), atomically: true, encoding: .utf8)
        try "meta".write(to: src.appendingPathComponent("__MACOSX/Holiday/._x.txt"), atomically: true, encoding: .utf8)
        let archive = dir.appendingPathComponent("mac.tar.gz")
        try await run("/usr/bin/bsdtar", ["-czf", archive.path, "-C", src.path, "Holiday", "__MACOSX"])

        let out = try makeTemp()
        defer { remove(out) }
        let items = try await ArchiveExtractor().convert(archive, from: Formats.tgz, to: Formats.folder, into: out, baseName: "mac", context: context)
        #expect(items.map(\.lastPathComponent) == ["Holiday"])
        #expect(try names(in: out) == ["Holiday"])
    }

    @Test func archivesSkipFinderLeftoversAndKeepSameNamedFiles() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let one = dir.appendingPathComponent("one", isDirectory: true)
        let two = dir.appendingPathComponent("two", isDirectory: true)
        try FileManager.default.createDirectory(at: one.appendingPathComponent("Docs/__MACOSX"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)
        try "a".write(to: one.appendingPathComponent("Docs/a.txt"), atomically: true, encoding: .utf8)
        try "junk".write(to: one.appendingPathComponent("Docs/.DS_Store"), atomically: true, encoding: .utf8)
        try "junk".write(to: one.appendingPathComponent("Docs/__MACOSX/x"), atomically: true, encoding: .utf8)
        try "first".write(to: one.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try "second".write(to: two.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let out = try makeTemp()
        defer { remove(out) }
        let inputs = [one.appendingPathComponent("Docs"), one.appendingPathComponent("note.txt"), two.appendingPathComponent("note.txt")]
        let zip = try await ArchiveCombiner().combine(inputs, to: Formats.zip, into: out, baseName: "Archive", context: context)[0]
        let listing = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/bsdtar"), ["-tf", zip.path]).stdout
        let entries = Set(listing.split(separator: "\n").map(String.init))
        #expect(entries == ["Docs/", "Docs/a.txt", "note.txt", "note 2.txt"])
        #expect(try names(in: out) == ["Archive.zip"]) // no staging folder left behind
    }

    @Test func singleCompressedFileIsJustDecompressed() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let text = dir.appendingPathComponent("notes.txt")
        try "single file".write(to: text, atomically: true, encoding: .utf8)
        try await run("/usr/bin/gzip", ["-k", text.path])
        let out = try makeTemp()
        defer { remove(out) }
        let gz = dir.appendingPathComponent("notes.txt.gz")
        let items = try await ArchiveExtractor().convert(gz, from: Formats.gz, to: Formats.folder, into: out, baseName: "notes.txt", context: context)
        #expect(items.map(\.lastPathComponent) == ["notes.txt"])
        #expect(try String(contentsOf: items[0], encoding: .utf8) == "single file")
    }

    @Test func archiveWithPathsOutsideItsFolderIsRefused() async throws {
        let dir = try makeTemp()
        defer { remove(dir) }
        let work = dir.appendingPathComponent("work/inner", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try "evil".write(to: dir.appendingPathComponent("work/evil.txt"), atomically: true, encoding: .utf8)
        let archive = dir.appendingPathComponent("evil.tar")
        // -P keeps the ".." in the stored name.
        try await run("/usr/bin/bsdtar", ["-cf", archive.path, "-P", "-C", work.path, "../evil.txt"])
        let out = try makeTemp()
        defer { remove(out) }
        await #expect(throws: ConversionError.self) {
            try await ArchiveExtractor().convert(archive, from: Formats.tar, to: Formats.folder, into: out, baseName: "evil", context: context)
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("evil.txt").path))
    }
}
