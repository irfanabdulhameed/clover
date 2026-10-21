import Foundation

/// Extracts an archive into a folder.
public struct ArchiveExtractor: Converter {
    public let id = "extract"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        FormatTables.archiveRead.contains(input) ? [Formats.folder] : []
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("extracting yet")
    }
}

/// Any files and folders into one ZIP or TAR.GZ.
public struct ArchiveCombiner: Combiner {
    public let id = "archive"
    public init() {}

    public func canCombine(_ inputs: [Format], into output: Format) -> Bool {
        output == Formats.zip || output == Formats.tgz
    }

    public func combine(_ inputs: [URL], to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("archiving yet")
    }
}
