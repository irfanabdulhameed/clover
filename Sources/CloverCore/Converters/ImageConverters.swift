import Foundation
import AppKit
import ImageIO
import WebKit

// MARK: - Shared helpers

/// An image read through ImageIO: the pixels as stored, plus how to turn them upright.
struct LoadedImage {
    let image: CGImage
    /// EXIF orientation, 1...8. The pixels are not rotated yet.
    let orientation: Int
    let properties: [CFString: Any]

    var size: CGSize { CGSize(width: image.width, height: image.height) }
    /// Size once upright.
    var uprightSize: CGSize { orientation >= 5 ? CGSize(width: image.height, height: image.width) : size }
    var hasAlpha: Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
    /// The resolution the file states, if sensible.
    var dpi: Double? {
        guard let value = properties[kCGImagePropertyDPIWidth] as? Double, value >= 1, value <= 2400 else { return nil }
        return value
    }
}

/// Reading, drawing and writing helpers shared by the image, PDF and SVG converters.
enum ImageKit {
    // MARK: Formats

    static let writableTypes: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func typeIdentifier(for format: Format) -> String? {
        switch format.id {
        case "jpg": "public.jpeg"
        case "png": "public.png"
        case "heic": "public.heic"
        case "avif": "public.avif"
        case "tiff": "public.tiff"
        case "gif": "com.compuserve.gif"
        case "bmp": "com.microsoft.bmp"
        case "ico": "com.microsoft.ico"
        case "icns": "com.apple.icns"
        default: nil
        }
    }

    /// Whether this Mac's ImageIO can write the format. PDF is drawn with CoreGraphics.
    static func canWrite(_ format: Format) -> Bool {
        if format == Formats.pdf { return true }
        guard let type = typeIdentifier(for: format) else { return false }
        return writableTypes.contains(type)
    }

    /// 0...1 for a quality option id.
    static func quality(_ id: String) -> Double {
        switch id {
        case "best": 0.92
        case "small": 0.6
        default: 0.8
        }
    }

    // MARK: Reading

    static func orientation(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 1 }
        return props[kCGImagePropertyOrientation] as? Int ?? 1
    }

    /// Reads the main image: the first frame of a GIF or a multi-page TIFF, the largest
    /// size in an ICO or ICNS.
    static func load(_ url: URL, from format: Format) throws -> LoadedImage {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConversionError.failed("Couldn't open \(name). It may be damaged.")
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw ConversionError.failed("\(name) has no image in it.") }
        var index = CGImageSourceGetPrimaryImageIndex(source)
        if format == Formats.ico || format == Formats.icns {
            var best = -1
            for i in 0..<count {
                let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
                let w = p?[kCGImagePropertyPixelWidth] as? Int ?? 0
                let h = p?[kCGImagePropertyPixelHeight] as? Int ?? 0
                if w * h > best { best = w * h; index = i }
            }
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
            throw ConversionError.failed("Couldn't read the picture in \(name).")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let orientation = min(max(props[kCGImagePropertyOrientation] as? Int ?? 1, 1), 8)
        return LoadedImage(image: image, orientation: orientation, properties: props)
    }

    // MARK: Drawing

    /// Maps an image of `w`×`h` pixels (origin bottom-left) to its upright position.
    static func orientationTransform(_ orientation: Int, width w: CGFloat, height h: CGFloat) -> CGAffineTransform {
        switch orientation {
        case 2: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 6: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case 7: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 8: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        default: .identity
        }
    }

    static func sRGB() -> CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB() }

    /// A bitmap context in the image's own RGB colour space when possible, so profiles survive.
    static func makeContext(width: Int, height: Int, like image: CGImage, alpha: CGImageAlphaInfo) -> CGContext? {
        if let space = image.colorSpace, space.model == .rgb,
           let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: space, bitmapInfo: alpha.rawValue) {
            return context
        }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB(), bitmapInfo: alpha.rawValue)
    }

    /// Draws the image into a new `width`×`height` bitmap, inside `fit` (y up), optionally
    /// turned upright and on a solid background. Without a background the rest is transparent,
    /// unless `keepAlpha` is false, which gives a bitmap with no alpha channel at all.
    static func render(_ loaded: LoadedImage, upright: Bool, width: Int, height: Int, fit: CGRect, background: CGColor?, keepAlpha: Bool = true) throws -> CGImage {
        let alpha: CGImageAlphaInfo = background == nil && keepAlpha ? .premultipliedLast : .noneSkipLast
        guard let context = makeContext(width: width, height: height, like: loaded.image, alpha: alpha) else {
            throw ConversionError.failed("This picture is too large or in a format Clover can't redraw.")
        }
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let o = upright ? loaded.orientation : 1
        let source = upright ? loaded.uprightSize : loaded.size
        let transform = orientationTransform(o, width: loaded.size.width, height: loaded.size.height)
            .concatenating(CGAffineTransform(scaleX: fit.width / source.width, y: fit.height / source.height))
            .concatenating(CGAffineTransform(translationX: fit.minX, y: fit.minY))
        context.interpolationQuality = .high
        context.concatenate(transform)
        context.draw(loaded.image, in: CGRect(origin: .zero, size: loaded.size))
        guard let result = context.makeImage() else {
            throw ConversionError.failed("Couldn't redraw the picture.")
        }
        return result
    }

    /// The picture on a square canvas of `side` pixels, scaled to fit, centred, transparent around.
    static func square(_ loaded: LoadedImage, side: Int) throws -> CGImage {
        let size = loaded.uprightSize
        let scale = min(CGFloat(side) / size.width, CGFloat(side) / size.height)
        let w = size.width * scale
        let h = size.height * scale
        let fit = CGRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h)
        return try render(loaded, upright: true, width: side, height: side, fit: fit, background: nil)
    }

    // MARK: Writing

    /// Metadata worth carrying over to formats that can hold it.
    static func metadata(of loaded: LoadedImage, keepOrientation: Bool, format: Format) -> [CFString: Any] {
        var out: [CFString: Any] = [:]
        guard ["jpg", "png", "heic", "avif", "tiff"].contains(format.id) else { return out }
        let p = loaded.properties
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            guard var dict = p[key] as? [CFString: Any] else { continue }
            if key == kCGImagePropertyExifDictionary {
                dict[kCGImagePropertyExifPixelXDimension] = nil
                dict[kCGImagePropertyExifPixelYDimension] = nil
            }
            out[key] = dict
        }
        if let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            var kept: [CFString: Any] = [:]
            for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware, kCGImagePropertyTIFFDateTime,
                        kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFCopyright, kCGImagePropertyTIFFImageDescription,
                        kCGImagePropertyTIFFHostComputer] {
                if let value = tiff[key] { kept[key] = value }
            }
            if !kept.isEmpty { out[kCGImagePropertyTIFFDictionary] = kept }
        }
        if let dpi = p[kCGImagePropertyDPIWidth] { out[kCGImagePropertyDPIWidth] = dpi }
        if let dpi = p[kCGImagePropertyDPIHeight] { out[kCGImagePropertyDPIHeight] = dpi }
        if keepOrientation && loaded.orientation != 1 { out[kCGImagePropertyOrientation] = loaded.orientation }
        return out
    }

    static func write(_ image: CGImage, to url: URL, format: Format, properties: [CFString: Any]) throws {
        guard let type = typeIdentifier(for: format), writableTypes.contains(type) else {
            throw ConversionError.failed("This Mac can't write \(format.name) files.")
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw ConversionError.failed("Couldn't start the \(format.name) file.")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failed("Couldn't write the \(format.name) file.")
        }
    }

    /// An image stream for a PDF page. JPEG data passes straight through, so photos stay small.
    static func pdfImage(for loaded: LoadedImage, source: URL, from format: Format) -> CGImage {
        if !loaded.hasAlpha {
            if format == Formats.jpg, let provider = CGDataProvider(url: source as CFURL),
               let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
               jpeg.width == loaded.image.width, jpeg.height == loaded.image.height {
                return jpeg
            }
            let lossy: Set<String> = ["heic", "avif", "jp2", "webp", "raw"]
            if lossy.contains(format.id), let data = jpegData(loaded.image, quality: 0.92),
               let provider = CGDataProvider(data: data as CFData),
               let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                return jpeg
            }
        }
        return loaded.image
    }

    static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Starts a PDF page the size of the picture and draws it upright.
    static func appendPDFPage(to context: CGContext, loaded: LoadedImage, source: URL, from format: Format) {
        // 72 dpi unless the file says otherwise; PDF pages stay under 14400 points.
        var k = 72.0 / (loaded.dpi ?? 72.0)
        let upright = loaded.uprightSize
        k = min(k, 14400 / max(upright.width, upright.height))
        var box = CGRect(x: 0, y: 0, width: upright.width * k, height: upright.height * k)
        let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
        context.interpolationQuality = .high
        context.concatenate(orientationTransform(loaded.orientation, width: loaded.size.width, height: loaded.size.height)
            .concatenating(CGAffineTransform(scaleX: k, y: k)))
        context.draw(pdfImage(for: loaded, source: source, from: format), in: CGRect(origin: .zero, size: loaded.size))
        context.endPDFPage()
    }
}

// MARK: - ImageIO

/// Images through macOS's own image engine (ImageIO).
public struct ImageIOConverter: Converter {
    public let id = "imageio"
    public var cost: Int { 5 }
    public init() {}

    /// Everything in the table that this Mac's ImageIO can really write (AVIF depends on the macOS version).
    public func outputs(from input: Format) -> [Format] {
        guard FormatTables.imageIORead.contains(input) else { return [] }
        return FormatTables.imageIOWrite.filter { $0 != input && ImageKit.canWrite($0) }
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        let loaded = try ImageKit.load(input, from: from)
        try Task.checkCancellation()
        context.progress(0.1)
        let output = directory.appendingPathComponent("\(baseName).\(to.fileExtension)")

        switch to.id {
        case "pdf":
            guard let pdf = CGContext(output as CFURL, mediaBox: nil, nil) else {
                throw ConversionError.failed("Couldn't start the PDF.")
            }
            ImageKit.appendPDFPage(to: pdf, loaded: loaded, source: input, from: from)
            pdf.closePDF()

        case "ico":
            // ImageIO writes only the standard icon sizes: take the smallest one that holds the picture, at most 256.
            let largest = Int(max(loaded.uprightSize.width, loaded.uprightSize.height).rounded(.up))
            let side = [16, 24, 32, 48, 64, 128, 256].first { $0 >= largest } ?? 256
            try ImageKit.write(try ImageKit.square(loaded, side: side), to: output, format: to, properties: [:])

        case "icns":
            // Icon sizes 16 to 1024 as 1x and 2x pairs (ImageIO takes 144 dpi to mean "2x"), up to the picture's own size.
            let largest = Int(max(loaded.uprightSize.width, loaded.uprightSize.height))
            var entries: [(pixels: Int, dpi: Double)] = [
                (16, 72), (32, 144), (32, 72), (64, 144), (128, 72), (256, 144), (256, 72), (512, 144), (512, 72), (1024, 144),
            ].filter { $0.pixels <= largest }
            if entries.isEmpty { entries = [(16, 72)] }
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "com.apple.icns" as CFString, entries.count, nil) else {
                throw ConversionError.failed("Couldn't start the ICNS file.")
            }
            var drawn: [Int: CGImage] = [:]
            for entry in entries {
                try Task.checkCancellation()
                let image = try drawn[entry.pixels] ?? ImageKit.square(loaded, side: entry.pixels)
                drawn[entry.pixels] = image
                CGImageDestinationAddImage(destination, image,
                                           [kCGImagePropertyDPIWidth: entry.dpi, kCGImagePropertyDPIHeight: entry.dpi] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ConversionError.failed("Couldn't write the ICNS file.") }

        default:
            // JPEG, HEIC and TIFF carry the orientation as a tag. The rest get it baked in (ImageIO writes no tag for AVIF).
            let keepsTag = ["jpg", "heic", "tiff"].contains(to.id)
            let bake = loaded.orientation != 1 && !keepsTag
            // JPEG and BMP have no real transparency: flatten on white.
            let flatten = loaded.hasAlpha && (to == Formats.jpg || to == Formats.bmp)
            var image = loaded.image
            if bake || flatten {
                let size = bake ? loaded.uprightSize : loaded.size
                image = try ImageKit.render(loaded, upright: bake, width: Int(size.width), height: Int(size.height),
                                            fit: CGRect(origin: .zero, size: size),
                                            background: flatten ? CGColor(gray: 1, alpha: 1) : nil, keepAlpha: loaded.hasAlpha)
            }
            var properties = ImageKit.metadata(of: loaded, keepOrientation: keepsTag, format: to)
            if ["jpg", "heic", "avif"].contains(to.id) {
                properties[kCGImageDestinationLossyCompressionQuality] = ImageKit.quality(context.quality)
            }
            if to == Formats.tiff {
                var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
                tiff[kCGImagePropertyTIFFCompression] = 5 // LZW
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
            try ImageKit.write(image, to: output, format: to, properties: properties)
        }

        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw ConversionError.failed("Couldn't write the \(to.name) file.")
        }
        context.progress(1)
        return [output]
    }
}

// MARK: - WebP

/// WebP output through cwebp (Homebrew `webp`), because macOS can't write WebP.
public struct WebPConverter: Converter {
    public let id = "cwebp"
    public var cost: Int { 20 }
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        FormatTables.webpRead.contains(input) ? [Formats.webp] : []
    }

    public func isAvailable(_ tools: Tools) -> Bool { tools.cwebp != nil }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        guard let cwebp = context.tools.cwebp else { throw ConversionError.toolMissing("cwebp") }
        let quality: Int
        switch context.quality {
        case "best": quality = 92
        case "small": quality = 60
        default: quality = 80
        }

        // cwebp ignores the EXIF orientation and is picky about TIFF. Hand it a PNG
        // (same pixels, upright, same profile) in those cases.
        let work = directory.appendingPathComponent(".work-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var source = input
        if from == Formats.tiff || (from == Formats.jpg && ImageKit.orientation(of: input) != 1) {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let loaded = try ImageKit.load(input, from: from)
            let size = loaded.uprightSize
            let image = loaded.orientation == 1 ? loaded.image
                : try ImageKit.render(loaded, upright: true, width: Int(size.width), height: Int(size.height),
                                      fit: CGRect(origin: .zero, size: size), background: nil, keepAlpha: loaded.hasAlpha)
            source = work.appendingPathComponent("source.png")
            try ImageKit.write(image, to: source, format: Formats.png, properties: [:])
        }
        context.progress(0.2)

        let output = directory.appendingPathComponent("\(baseName).webp")
        try await ProcessRunner.run(cwebp, ["-quiet", "-mt", "-q", String(quality), "-metadata", "icc", source.path, "-o", output.path])
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw ConversionError.failed("cwebp didn't make a file.")
        }
        context.progress(1)
        return [output]
    }
}

// MARK: - SVG

/// SVG drawn with WebKit, to PNG or PDF.
public struct SVGConverter: Converter {
    public let id = "svg"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        input == Formats.svg ? [Formats.png, Formats.pdf] : []
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        let data: Data
        do { data = try Data(contentsOf: input) } catch {
            throw ConversionError.failed("Couldn't read \(input.lastPathComponent).")
        }
        let intrinsic = try SVGSize.intrinsic(of: data)
        context.progress(0.1)
        let output = directory.appendingPathComponent("\(baseName).\(to.fileExtension)")

        if to == Formats.pdf {
            let pdf = try await SVGRenderer.pdf(svg: data, size: intrinsic.size, checkLoaded: intrinsic.explicit)
            try pdf.write(to: output)
        } else {
            // 2×, but never more than 8192 pixels on a side.
            let scale = min(2, 8192 / max(intrinsic.size.width, intrinsic.size.height))
            let image = try await SVGRenderer.png(svg: data, size: intrinsic.size, scale: scale, checkLoaded: intrinsic.explicit)
            try ImageKit.write(image, to: output, format: Formats.png,
                               properties: [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale])
        }
        try Task.checkCancellation()
        context.progress(1)
        return [output]
    }
}

/// The size an SVG draws at: width and height, else the viewBox, else 1024.
enum SVGSize {
    static func intrinsic(of data: Data) throws -> (size: CGSize, explicit: Bool) {
        let reader = RootReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        _ = parser.parse()
        // A file that breaks after its <svg> tag still draws in most cases; one with no <svg> tag never does.
        guard let root = reader.attributes, reader.name?.lowercased().hasSuffix("svg") == true else {
            throw ConversionError.failed("This SVG file is damaged or isn't an SVG.")
        }
        return size(width: root["width"], height: root["height"], viewBox: root["viewBox"])
    }

    static func size(width: String?, height: String?, viewBox: String?) -> (size: CGSize, explicit: Bool) {
        let w = length(width)
        let h = length(height)
        let box = viewBox.flatMap { text -> CGSize? in
            let parts = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" || $0 == "\n" }).compactMap { Double($0) }
            return parts.count == 4 && parts[2] > 0 && parts[3] > 0 ? CGSize(width: parts[2], height: parts[3]) : nil
        }
        var result: CGSize
        // True when width and height are both stated, so WebKit certainly reports a size for the picture.
        var explicit = false
        switch (w, h, box) {
        case let (w?, h?, _):
            result = CGSize(width: w, height: h)
            explicit = true
        case let (w?, nil, box?): result = CGSize(width: w, height: w * box.height / box.width)
        case let (nil, h?, box?): result = CGSize(width: h * box.width / box.height, height: h)
        case let (w?, nil, nil): result = CGSize(width: w, height: w)
        case let (nil, h?, nil): result = CGSize(width: h, height: h)
        case let (nil, nil, box?): result = box
        default: result = CGSize(width: 1024, height: 1024)
        }
        result = CGSize(width: max(1, result.width.rounded(.up)), height: max(1, result.height.rounded(.up)))
        return (result, explicit)
    }

    /// A CSS length in pixels. Percentages mean "no size".
    static func length(_ text: String?) -> Double? {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty, !t.hasSuffix("%") else { return nil }
        let units: [(String, Double)] = [("px", 1), ("pt", 4.0 / 3), ("pc", 16), ("in", 96), ("cm", 96 / 2.54), ("mm", 96 / 25.4), ("em", 16), ("ex", 8)]
        var factor = 1.0
        for (unit, value) in units where t.hasSuffix(unit) {
            t = String(t.dropLast(unit.count))
            factor = value
            break
        }
        guard let number = Double(t.trimmingCharacters(in: .whitespaces)), number > 0 else { return nil }
        return number * factor
    }

    private final class RootReader: NSObject, XMLParserDelegate {
        var name: String?
        var attributes: [String: String]?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if attributes == nil {
                name = elementName
                attributes = attributeDict
            }
        }
    }
}

/// Draws SVG files with an offscreen WKWebView. Needs the app run loop, which the app and
/// the command-line mode both have.
@MainActor
private enum SVGRenderer {
    static func png(svg: Data, size: CGSize, scale: CGFloat, checkLoaded: Bool) async throws -> CGImage {
        let view = try await load(svg: svg, size: size, checkLoaded: checkLoaded)
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.snapshotWidth = NSNumber(value: Double(size.width * scale))
        config.afterScreenUpdates = true
        let snapshot = try await view.takeSnapshot(configuration: config)
        guard let cg = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ConversionError.failed("Couldn't draw this SVG.")
        }
        // The snapshot may come back at the screen's scale: bring it to exactly 2×.
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        if cg.width == width && cg.height == height { return cg }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: ImageKit.sRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.failed("Couldn't draw this SVG.")
        }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { throw ConversionError.failed("Couldn't draw this SVG.") }
        return resized
    }

    static func pdf(svg: Data, size: CGSize, checkLoaded: Bool) async throws -> Data {
        let view = try await load(svg: svg, size: size, checkLoaded: checkLoaded)
        let config = WKPDFConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        return try await view.pdf(configuration: config)
    }

    /// The SVG goes in as an `<img>`: WebKit then draws it with no scripts and no outside files.
    private static func load(svg: Data, size: CGSize, checkLoaded: Bool) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        // Transparent page, so the PNG keeps its transparency.
        if view.responds(to: Selector(("_setDrawsBackground:"))) || view.responds(to: Selector(("setDrawsBackground:"))) {
            view.setValue(false, forKey: "drawsBackground")
        }
        let waiter = LoadWaiter()
        view.navigationDelegate = waiter
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;background:transparent;overflow:hidden}
        img{display:block;width:\(Int(size.width))px;height:\(Int(size.height))px}
        </style></head><body><img src="data:image/svg+xml;base64,\(svg.base64EncodedString())"></body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
        try await waiter.wait(seconds: 30)
        view.navigationDelegate = nil

        // Wait for the picture itself, and notice one WebKit couldn't draw.
        let script = """
        const i = document.images[0];
        if (i && i.decode) { try { await i.decode(); } catch (e) {} }
        return !!i && i.complete && i.naturalWidth > 0;
        """
        let drawn = (try? await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool
        if checkLoaded && drawn == false { throw ConversionError.failed("Couldn't draw this SVG. It may use features WebKit doesn't support.") }
        return view
    }
}

/// Waits for a WKWebView to finish loading, with a timeout and cancellation.
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func wait(seconds: Double) async throws {
        let timer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.finish(.failure(ConversionError.failed("Drawing the SVG took too long.")))
        }
        defer { timer.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (next: CheckedContinuation<Void, Error>) in
                if let result { next.resume(with: result) } else { continuation = next }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(ConversionError.cancelled)) }
        }
    }

    private func finish(_ outcome: Result<Void, Error>) {
        guard result == nil else { return }
        result = outcome
        continuation?.resume(with: outcome)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(ConversionError.failed("Couldn't draw this SVG.")))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(ConversionError.failed("Couldn't draw this SVG.")))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(ConversionError.failed("The SVG drawing engine stopped. Try again.")))
    }
}
