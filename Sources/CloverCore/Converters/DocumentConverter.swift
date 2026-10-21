import Foundation
import AppKit

/// Text documents through the macOS text system.
public struct DocumentConverter: Converter {
    public let id = "text"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        guard FormatTables.documentRead.contains(input) else { return [] }
        return FormatTables.documentWrite.filter { $0 != input }
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        let text = try await DocumentIO.read(input, as: from)
        try Task.checkCancellation()
        context.progress(0.3)
        let output = directory.appendingPathComponent("\(baseName).\(to.fileExtension)")

        switch to.id {
        case "txt":
            let plain = text.string.replacingOccurrences(of: "\u{FFFC}", with: "")
            try Data(plain.utf8).write(to: output)
        case "pdf":
            try DocumentPDF.write(text, to: output, context: context)
        case "docx", "rtf", "html":
            let type: NSAttributedString.DocumentType = to == Formats.docx ? .officeOpenXML : to == Formats.rtf ? .rtf : .html
            var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
            if to == Formats.html { attributes[.characterEncoding] = String.Encoding.utf8.rawValue }
            let data: Data
            do { data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attributes) } catch {
                throw ConversionError.failed("Couldn't write the \(to.name) file: \(error.localizedDescription)")
            }
            try data.write(to: output)
        default:
            throw ConversionError.unsupported("documents to \(to.name)")
        }
        try Task.checkCancellation()
        context.progress(1)
        return [output]
    }
}

/// Carries attributed text out of the main actor.
private struct Box: @unchecked Sendable { let text: NSAttributedString }

/// Reading documents into attributed text.
enum DocumentIO {
    static func read(_ url: URL, as format: Format) async throws -> NSAttributedString {
        switch format.id {
        case "txt":
            return try readPlain(url)
        case "html", "webarchive":
            // HTML import runs WebKit, which must be driven from the main thread.
            let type: NSAttributedString.DocumentType = format == Formats.html ? .html : .webArchive
            return try await MainActor.run { Box(text: try load(url, type: type, format: format)) }.text
        case "docx": return try load(url, type: .officeOpenXML, format: format)
        case "doc": return try load(url, type: .docFormat, format: format)
        case "rtf": return try load(url, type: .rtf, format: format)
        case "rtfd": return try load(url, type: .rtfd, format: format)
        case "odt": return try load(url, type: .openDocument, format: format)
        default: throw ConversionError.unsupported("\(format.name) documents")
        }
    }

    private static func load(_ url: URL, type: NSAttributedString.DocumentType, format: Format) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if format == Formats.html {
            options[.characterEncoding] = String.Encoding.utf8.rawValue
            options[.timeout] = 10.0
        }
        do {
            return try NSAttributedString(url: url, options: options, documentAttributes: nil)
        } catch {
            throw ConversionError.failed("Couldn't read \(url.lastPathComponent). It may be damaged or password-protected.")
        }
    }

    /// Plain text in whatever encoding it uses, shown in Helvetica 12 like TextEdit.
    private static func readPlain(_ url: URL) throws -> NSAttributedString {
        var encoding = String.Encoding.utf8
        let string: String
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) {
            string = text
        } else if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .macOSRoman) {
            string = text
        } else {
            throw ConversionError.failed("Couldn't read \(url.lastPathComponent).")
        }
        let font = NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
    }
}

/// Lays text out on US Letter pages and draws them into a PDF.
enum DocumentPDF {
    static let page = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 72

    static func write(_ source: NSAttributedString, to url: URL, context: StepContext) throws {
        let storage = NSTextStorage(attributedString: source)
        fitAttachments(in: storage, width: page.width - 2 * margin, height: page.height - 2 * margin)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        // One text container per page, until every glyph has a place.
        let textSize = CGSize(width: page.width - 2 * margin, height: page.height - 2 * margin)
        var containers: [NSTextContainer] = []
        var laidOut = 0
        while containers.isEmpty || laidOut < layout.numberOfGlyphs {
            try Task.checkCancellation()
            let container = NSTextContainer(size: textSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let end = NSMaxRange(layout.glyphRange(for: container))
            containers.append(container)
            guard end > laidOut else { break } // nothing fit: stop rather than loop forever
            laidOut = end
            if containers.count > 5000 { throw ConversionError.failed("This document is too long to turn into a PDF.") }
            context.progress(0.3 + 0.3 * Double(laidOut) / Double(max(layout.numberOfGlyphs, 1)))
        }

        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw ConversionError.failed("Couldn't start the PDF.")
        }
        for (index, container) in containers.enumerated() {
            try Task.checkCancellation()
            let glyphs = layout.glyphRange(for: container)
            pdf.beginPDFPage(nil)
            pdf.saveGState()
            // Text draws top-down: flip the page.
            pdf.translateBy(x: 0, y: page.height)
            pdf.scaleBy(x: 1, y: -1)
            let graphics = NSGraphicsContext(cgContext: pdf, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            // Light appearance, so default text is dark on the white page whatever the Mac is set to.
            (NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
                layout.drawBackground(forGlyphRange: glyphs, at: CGPoint(x: margin, y: margin))
                layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: margin, y: margin))
            }
            NSGraphicsContext.restoreGraphicsState()
            pdf.restoreGState()
            pdf.endPDFPage()
            context.progress(0.6 + 0.4 * Double(index + 1) / Double(containers.count))
        }
        pdf.closePDF()
    }

    /// Pictures in the text get their image loaded and are shrunk to fit inside the margins.
    private static func fitAttachments(in storage: NSTextStorage, width: CGFloat, height: CGFloat) {
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            if attachment.image == nil, let data = attachment.fileWrapper?.regularFileContents {
                attachment.image = NSImage(data: data)
            }
            guard let image = attachment.image else { return }
            var size = attachment.bounds.size == .zero ? image.size : attachment.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = min(1, width / size.width, height / size.height)
            size = CGSize(width: size.width * scale, height: size.height * scale)
            attachment.bounds = CGRect(origin: attachment.bounds.origin, size: size)
        }
    }
}
