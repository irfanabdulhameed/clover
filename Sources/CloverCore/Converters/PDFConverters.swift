import Foundation

/// PDF pages to images or text, and PDF to a smaller PDF.
public struct PDFConverter: Converter {
    public let id = "pdfkit"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        input == Formats.pdf ? [Formats.png, Formats.jpg, Formats.txt, Formats.pdf] : []
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("PDF yet")
    }
}

/// Images and PDFs into one PDF, in the order given.
public struct PDFCombiner: Combiner {
    public let id = "pdf-combine"
    public init() {}

    public func canCombine(_ inputs: [Format], into output: Format) -> Bool {
        output == Formats.pdf && !inputs.isEmpty
            && inputs.allSatisfy { $0 == Formats.pdf || FormatTables.imageIORead.contains($0) }
    }

    public func combine(_ inputs: [URL], to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("PDF merging yet")
    }
}
