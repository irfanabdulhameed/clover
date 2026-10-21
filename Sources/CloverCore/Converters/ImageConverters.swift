import Foundation

/// Images through macOS's own image engine (ImageIO).
public struct ImageIOConverter: Converter {
    public let id = "imageio"
    public var cost: Int { 5 }
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        guard FormatTables.imageIORead.contains(input) else { return [] }
        return FormatTables.imageIOWrite.filter { $0 != input }
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("images yet")
    }
}

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
        throw ConversionError.unsupported("WebP yet")
    }
}

/// SVG drawn with WebKit, to PNG or PDF.
public struct SVGConverter: Converter {
    public let id = "svg"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        input == Formats.svg ? [Formats.png, Formats.pdf] : []
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("SVG yet")
    }
}
