import Foundation

/// Text documents through the macOS text system.
public struct DocumentConverter: Converter {
    public let id = "text"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        guard FormatTables.documentRead.contains(input) else { return [] }
        return FormatTables.documentWrite.filter { $0 != input }
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("documents yet")
    }
}
