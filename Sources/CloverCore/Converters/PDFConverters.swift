import Foundation
import AppKit
import PDFKit

// MARK: - Shared helpers

enum PDFKitHelper {
    /// Opens a PDF, with clear errors for broken, empty and password-protected files.
    static func open(_ url: URL) throws -> PDFDocument {
        let name = url.lastPathComponent
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.failed("Couldn't open \(name). It may be damaged.")
        }
        if document.isLocked {
            // Some PDFs are "locked" with an empty password.
            _ = document.unlock(withPassword: "")
            if document.isLocked {
                throw ConversionError.failed("\(name) is password-protected. Remove the password first.")
            }
        }
        guard document.pageCount > 0 else { throw ConversionError.failed("\(name) has no pages.") }
        return document
    }

    /// The page's visible area as it shows on screen: crop box, turned by the page's rotation.
    static func uprightSize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        return page.rotationAngle % 180 != 0 ? CGSize(width: box.height, height: box.width) : box.size
    }

    /// Draws one page on white at `scale` pixels per point, shrunk if it would pass `maxSide` pixels.
    /// Returns the image and the scale actually used.
    static func render(_ page: PDFPage, scale: CGFloat, maxSide: CGFloat = 8192) -> (image: CGImage, scale: CGFloat)? {
        guard let ref = page.pageRef else { return nil }
        let size = uprightSize(of: ref)
        guard size.width > 0, size.height > 0 else { return nil }
        let s = min(scale, maxSide / max(size.width, size.height))
        let width = max(1, Int((size.width * s).rounded(.up)))
        let height = max(1, Int((size.height * s).rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: ImageKit.sRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        // getDrawingTransform only fits a page into a rect, it never scales up: scale the context first.
        context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        context.concatenate(ref.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        guard let image = context.makeImage() else { return nil }
        return (image, s)
    }

    /// A one-page PDF of a picture, in memory.
    static func document(forImage url: URL, from format: Format) throws -> PDFDocument {
        let loaded = try ImageKit.load(url, from: format)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ConversionError.failed("Couldn't start the PDF.")
        }
        ImageKit.appendPDFPage(to: context, loaded: loaded, source: url, from: format)
        context.closePDF()
        guard let document = PDFDocument(data: data as Data), document.pageCount == 1 else {
            throw ConversionError.failed("Couldn't make a PDF page from \(url.lastPathComponent).")
        }
        return document
    }
}

// MARK: - PDF

/// PDF pages to images or text, and PDF to a smaller PDF.
public struct PDFConverter: Converter {
    public let id = "pdfkit"
    public init() {}

    static let tooSmallMessage = "This PDF is already as small as Clover can make it."

    public func outputs(from input: Format) -> [Format] {
        input == Formats.pdf ? [Formats.png, Formats.jpg, Formats.txt, Formats.pdf] : []
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        let document = try PDFKitHelper.open(input)
        try Task.checkCancellation()
        switch to.id {
        case "png", "jpg": return try renderPages(document, as: to, into: directory, baseName: baseName, context: context)
        case "txt": return try [extractText(document, into: directory, baseName: baseName)]
        case "pdf": return try [compress(document, input: input, into: directory, baseName: baseName, context: context)]
        default: throw ConversionError.unsupported("PDF to \(to.name)")
        }
    }

    /// The file name for page `index` (0-based) in a folder of `count` pages: "name 01.png".
    static func pageFileName(baseName: String, index: Int, count: Int, fileExtension: String) -> String {
        let digits = max(2, String(count).count)
        let number = String(index + 1)
        return "\(baseName) \(String(repeating: "0", count: max(0, digits - number.count)) + number).\(fileExtension)"
    }

    /// One page gives `baseName.png`; several give a folder `baseName` with one file per page.
    private func renderPages(_ document: PDFDocument, as format: Format, into directory: URL, baseName: String, context: StepContext) throws -> [URL] {
        let count = document.pageCount
        let folder = count > 1 ? directory.appendingPathComponent(baseName, isDirectory: true) : directory
        if count > 1 { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let quality = ImageKit.quality(context.quality, settings: context.settings)
        for index in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = document.page(at: index), let rendered = PDFKitHelper.render(page, scale: 2) else {
                    throw ConversionError.failed("Couldn't draw page \(index + 1).")
                }
                let name = count > 1
                    ? Self.pageFileName(baseName: baseName, index: index, count: count, fileExtension: format.fileExtension)
                    : "\(baseName).\(format.fileExtension)"
                var properties: [CFString: Any] = [
                    kCGImagePropertyDPIWidth: 72 * rendered.scale, kCGImagePropertyDPIHeight: 72 * rendered.scale,
                ]
                if format == Formats.jpg { properties[kCGImageDestinationLossyCompressionQuality] = quality }
                try ImageKit.write(rendered.image, to: folder.appendingPathComponent(name), format: format, properties: properties)
            }
            context.progress(Double(index + 1) / Double(count))
        }
        return [count > 1 ? folder : directory.appendingPathComponent("\(baseName).\(format.fileExtension)")]
    }

    private func extractText(_ document: PDFDocument, into directory: URL, baseName: String) throws -> URL {
        guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.failed("No text found in this PDF. It may be scanned pages.")
        }
        let output = directory.appendingPathComponent("\(baseName).txt")
        try Data(text.utf8).write(to: output)
        return output
    }

    private func compress(_ document: PDFDocument, input: URL, into directory: URL, baseName: String, context: StepContext) throws -> URL {
        let output = directory.appendingPathComponent("\(baseName).pdf")
        if context.quality == Options.small.id {
            try rasterise(document, to: output, context: context)
        } else {
            context.progress(0.1)
            let options: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
            guard document.write(to: output, withOptions: options) else {
                throw ConversionError.failed("Couldn't compress this PDF.")
            }
        }
        try Task.checkCancellation()
        let before = OutputPlacer.size(of: input)
        let after = OutputPlacer.size(of: output)
        guard after > 0, after < before else {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.failed(Self.tooSmallMessage)
        }
        context.progress(1)
        return output
    }

    /// "Small": every page becomes a JPEG at about 110 dpi, quality 0.5. Text is no longer selectable.
    private func rasterise(_ document: PDFDocument, to output: URL, context: StepContext) throws {
        var info: [CFString: Any] = [:]
        if let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String { info[kCGPDFContextTitle] = title }
        if let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String { info[kCGPDFContextAuthor] = author }
        guard let pdf = CGContext(output as CFURL, mediaBox: nil, info as CFDictionary) else {
            throw ConversionError.failed("Couldn't start the PDF.")
        }
        let count = document.pageCount
        for index in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = document.page(at: index), let ref = page.pageRef,
                      let rendered = PDFKitHelper.render(page, scale: 110.0 / 72.0),
                      let jpeg = ImageKit.jpegData(rendered.image, quality: 0.5),
                      let provider = CGDataProvider(data: jpeg as CFData),
                      let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                else { throw ConversionError.failed("Couldn't compress page \(index + 1).") }
                var box = CGRect(origin: .zero, size: PDFKitHelper.uprightSize(of: ref))
                let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                pdf.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
                pdf.draw(image, in: box)
                pdf.endPDFPage()
            }
            context.progress(Double(index + 1) / Double(count))
        }
        pdf.closePDF()
    }
}

// MARK: - Merge

/// Images and PDFs into one PDF, in the order given.
public struct PDFCombiner: Combiner {
    public let id = "pdf-combine"
    public init() {}

    public func canCombine(_ inputs: [Format], into output: Format) -> Bool {
        output == Formats.pdf && !inputs.isEmpty
            && inputs.allSatisfy { $0 == Formats.pdf || FormatTables.imageIORead.contains($0) }
    }

    public func combine(_ inputs: [URL], to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        let merged = PDFDocument()
        // The pages are copies that may still point into their source documents: keep those alive until the file is written.
        var sources: [PDFDocument] = []
        for (index, url) in inputs.enumerated() {
            try Task.checkCancellation()
            guard let format = Formats.detect(url) else { throw ConversionError.unsupported(url.lastPathComponent) }
            let source: PDFDocument
            if format == Formats.pdf {
                source = try PDFKitHelper.open(url)
            } else if FormatTables.imageIORead.contains(format) {
                source = try PDFKitHelper.document(forImage: url, from: format)
            } else {
                throw ConversionError.unsupported(url.lastPathComponent)
            }
            sources.append(source)
            for pageIndex in 0..<source.pageCount {
                guard let page = source.page(at: pageIndex)?.copy() as? PDFPage else {
                    throw ConversionError.failed("Couldn't read page \(pageIndex + 1) of \(url.lastPathComponent).")
                }
                merged.insert(page, at: merged.pageCount)
            }
            context.progress(Double(index + 1) / Double(inputs.count + 1))
        }
        try Task.checkCancellation()
        let output = directory.appendingPathComponent("\(baseName).pdf")
        guard merged.pageCount > 0, merged.write(to: output) else {
            throw ConversionError.failed("Couldn't write the merged PDF.")
        }
        withExtendedLifetime(sources) {}
        context.progress(1)
        return [output]
    }
}
