import Foundation

/// Video and audio through ffmpeg.
public struct FFmpegConverter: Converter {
    public let id = "ffmpeg"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        if FormatTables.videoRead.contains(input) { return FormatTables.videoWrite.filter { $0 != input } }
        if FormatTables.audioRead.contains(input) { return FormatTables.audioWrite.filter { $0 != input } }
        if input == Formats.gif { return FormatTables.gifToVideo }
        return []
    }

    public func isAvailable(_ tools: Tools) -> Bool { tools.ffmpeg != nil }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        throw ConversionError.unsupported("video and audio yet")
    }
}
