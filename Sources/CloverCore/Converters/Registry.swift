import Foundation

/// Every converter and combiner Clover ships with.
public enum Registry {
    public static func converters() -> [any Converter] {
        [ImageIOConverter(), WebPConverter(), SVGConverter(), PDFConverter(), DocumentConverter(), ArchiveExtractor(), FFmpegConverter()]
    }

    public static func combiners() -> [any Combiner] {
        [PDFCombiner(), ArchiveCombiner()]
    }

    public static func makeRouter(tools: Tools = .detect()) -> Router {
        Router(converters: converters(), combiners: combiners(), tools: tools)
    }
}

/// Formats each converter reads and writes, in one place so the bloom and the tests agree.
public enum FormatTables {
    public static let imageIORead: [Format] = [
        Formats.jpg, Formats.png, Formats.heic, Formats.avif, Formats.webp, Formats.tiff, Formats.gif, Formats.bmp,
        Formats.psd, Formats.raw, Formats.ico, Formats.icns, Formats.tga, Formats.exr, Formats.jp2,
    ]
    public static let imageIOWrite: [Format] = [
        Formats.jpg, Formats.png, Formats.heic, Formats.avif, Formats.tiff, Formats.gif, Formats.bmp,
        Formats.ico, Formats.icns, Formats.pdf,
    ]
    /// What cwebp reads.
    public static let webpRead: [Format] = [Formats.png, Formats.jpg, Formats.tiff]
    public static let documentRead: [Format] = [
        Formats.docx, Formats.doc, Formats.rtf, Formats.rtfd, Formats.odt, Formats.html, Formats.txt, Formats.webarchive,
    ]
    public static let documentWrite: [Format] = [Formats.docx, Formats.rtf, Formats.html, Formats.txt, Formats.pdf]
    public static let archiveRead: [Format] = [
        Formats.zip, Formats.tar, Formats.tgz, Formats.gz, Formats.txz, Formats.tbz, Formats.sevenZip, Formats.rar,
    ]
    public static let videoRead: [Format] = [
        Formats.mp4, Formats.mov, Formats.mkv, Formats.webm, Formats.avi, Formats.wmv, Formats.flv, Formats.mpg, Formats.ts, Formats.threegp,
    ]
    public static let videoWrite: [Format] = [Formats.mp4, Formats.mov, Formats.mkv, Formats.webm, Formats.gif, Formats.mp3, Formats.m4a]
    public static let audioRead: [Format] = [
        Formats.mp3, Formats.m4a, Formats.aac, Formats.wav, Formats.flac, Formats.ogg, Formats.opus, Formats.aiff, Formats.wma, Formats.caf,
    ]
    public static let audioWrite: [Format] = [Formats.mp3, Formats.m4a, Formats.wav, Formats.flac, Formats.ogg, Formats.opus, Formats.aiff]
    /// Animated GIF to video.
    public static let gifToVideo: [Format] = [Formats.mp4, Formats.webm]
}
