import Foundation

public enum Family: String, Codable, CaseIterable, Sendable {
    case image, pdf, document, video, audio, archive

    public var title: String {
        switch self {
        case .image: "Image"
        case .pdf: "PDF"
        case .document: "Document"
        case .video: "Video"
        case .audio: "Audio"
        case .archive: "Archive"
        }
    }
}

/// A file format Clover knows. `extensions[0]` is the one Clover writes.
public struct Format: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let id: String
    public let name: String
    public let family: Family
    public let extensions: [String]

    public init(id: String, name: String, family: Family, extensions: [String]) {
        self.id = id
        self.name = name
        self.family = family
        self.extensions = extensions
    }

    public var fileExtension: String { extensions.first ?? "" }
    public var description: String { id }
}

public enum Formats {
    // Images
    public static let jpg = Format(id: "jpg", name: "JPG", family: .image, extensions: ["jpg", "jpeg", "jpe", "jfif"])
    public static let png = Format(id: "png", name: "PNG", family: .image, extensions: ["png"])
    public static let heic = Format(id: "heic", name: "HEIC", family: .image, extensions: ["heic", "heif", "hif"])
    public static let avif = Format(id: "avif", name: "AVIF", family: .image, extensions: ["avif"])
    public static let webp = Format(id: "webp", name: "WebP", family: .image, extensions: ["webp"])
    public static let tiff = Format(id: "tiff", name: "TIFF", family: .image, extensions: ["tiff", "tif"])
    public static let gif = Format(id: "gif", name: "GIF", family: .image, extensions: ["gif"])
    public static let bmp = Format(id: "bmp", name: "BMP", family: .image, extensions: ["bmp"])
    public static let psd = Format(id: "psd", name: "PSD", family: .image, extensions: ["psd"])
    public static let raw = Format(id: "raw", name: "RAW", family: .image, extensions: [
        "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2", "rwl", "pef", "srw", "3fr", "fff", "iiq", "erf", "mos", "x3f",
    ])
    public static let ico = Format(id: "ico", name: "ICO", family: .image, extensions: ["ico"])
    public static let icns = Format(id: "icns", name: "ICNS", family: .image, extensions: ["icns"])
    public static let tga = Format(id: "tga", name: "TGA", family: .image, extensions: ["tga"])
    public static let exr = Format(id: "exr", name: "EXR", family: .image, extensions: ["exr"])
    public static let jp2 = Format(id: "jp2", name: "JPEG 2000", family: .image, extensions: ["jp2", "j2k", "jpf", "jpx"])
    public static let svg = Format(id: "svg", name: "SVG", family: .image, extensions: ["svg"])

    // PDF
    public static let pdf = Format(id: "pdf", name: "PDF", family: .pdf, extensions: ["pdf"])

    // Documents
    public static let docx = Format(id: "docx", name: "DOCX", family: .document, extensions: ["docx"])
    public static let doc = Format(id: "doc", name: "DOC", family: .document, extensions: ["doc"])
    public static let rtf = Format(id: "rtf", name: "RTF", family: .document, extensions: ["rtf"])
    public static let rtfd = Format(id: "rtfd", name: "RTFD", family: .document, extensions: ["rtfd"])
    public static let odt = Format(id: "odt", name: "ODT", family: .document, extensions: ["odt"])
    public static let html = Format(id: "html", name: "HTML", family: .document, extensions: ["html", "htm"])
    public static let txt = Format(id: "txt", name: "TXT", family: .document, extensions: ["txt", "text"])
    public static let webarchive = Format(id: "webarchive", name: "Web Archive", family: .document, extensions: ["webarchive"])

    // Video
    public static let mp4 = Format(id: "mp4", name: "MP4", family: .video, extensions: ["mp4", "m4v"])
    public static let mov = Format(id: "mov", name: "MOV", family: .video, extensions: ["mov", "qt"])
    public static let mkv = Format(id: "mkv", name: "MKV", family: .video, extensions: ["mkv"])
    public static let webm = Format(id: "webm", name: "WebM", family: .video, extensions: ["webm"])
    public static let avi = Format(id: "avi", name: "AVI", family: .video, extensions: ["avi"])
    public static let wmv = Format(id: "wmv", name: "WMV", family: .video, extensions: ["wmv", "asf"])
    public static let flv = Format(id: "flv", name: "FLV", family: .video, extensions: ["flv"])
    public static let mpg = Format(id: "mpg", name: "MPEG", family: .video, extensions: ["mpg", "mpeg", "m2v", "vob"])
    public static let ts = Format(id: "ts", name: "MPEG-TS", family: .video, extensions: ["ts", "mts", "m2ts"])
    public static let threegp = Format(id: "3gp", name: "3GP", family: .video, extensions: ["3gp", "3g2"])

    // Audio
    public static let mp3 = Format(id: "mp3", name: "MP3", family: .audio, extensions: ["mp3"])
    public static let m4a = Format(id: "m4a", name: "M4A", family: .audio, extensions: ["m4a", "m4b"])
    public static let aac = Format(id: "aac", name: "AAC", family: .audio, extensions: ["aac"])
    public static let wav = Format(id: "wav", name: "WAV", family: .audio, extensions: ["wav", "wave"])
    public static let flac = Format(id: "flac", name: "FLAC", family: .audio, extensions: ["flac"])
    public static let ogg = Format(id: "ogg", name: "OGG", family: .audio, extensions: ["ogg", "oga"])
    public static let opus = Format(id: "opus", name: "Opus", family: .audio, extensions: ["opus"])
    public static let aiff = Format(id: "aiff", name: "AIFF", family: .audio, extensions: ["aiff", "aif", "aifc"])
    public static let wma = Format(id: "wma", name: "WMA", family: .audio, extensions: ["wma"])
    public static let caf = Format(id: "caf", name: "CAF", family: .audio, extensions: ["caf"])

    // Archives. `folder` is any plain folder as input, and an extracted folder as output.
    public static let zip = Format(id: "zip", name: "ZIP", family: .archive, extensions: ["zip"])
    public static let tgz = Format(id: "tgz", name: "TAR.GZ", family: .archive, extensions: ["tar.gz", "tgz"])
    public static let tar = Format(id: "tar", name: "TAR", family: .archive, extensions: ["tar"])
    public static let gz = Format(id: "gz", name: "GZ", family: .archive, extensions: ["gz"])
    public static let txz = Format(id: "txz", name: "TAR.XZ", family: .archive, extensions: ["tar.xz", "txz", "xz"])
    public static let tbz = Format(id: "tbz", name: "TAR.BZ2", family: .archive, extensions: ["tar.bz2", "tbz2", "tbz", "bz2"])
    public static let sevenZip = Format(id: "7z", name: "7Z", family: .archive, extensions: ["7z"])
    public static let rar = Format(id: "rar", name: "RAR", family: .archive, extensions: ["rar"])
    public static let folder = Format(id: "folder", name: "Folder", family: .archive, extensions: [""])

    public static let all: [Format] = [
        jpg, png, heic, avif, webp, tiff, gif, bmp, psd, raw, ico, icns, tga, exr, jp2, svg,
        pdf,
        docx, doc, rtf, rtfd, odt, html, txt, webarchive,
        mp4, mov, mkv, webm, avi, wmv, flv, mpg, ts, threegp,
        mp3, m4a, aac, wav, flac, ogg, opus, aiff, wma, caf,
        zip, tgz, tar, gz, txz, tbz, sevenZip, rar, folder,
    ]

    private static let byIDTable: [String: Format] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func byID(_ id: String) -> Format? { byIDTable[id.lowercased()] }

    /// The format of a file on disk, by its extension. Plain folders are `folder`;
    /// packages such as .rtfd are matched by extension first.
    public static func detect(_ url: URL) -> Format? {
        let name = url.lastPathComponent.lowercased()
        // Longest extension first, so "x.tar.gz" is TAR.GZ and not GZ.
        var best: (Format, Int)?
        for format in all where format.id != "folder" {
            for ext in format.extensions where !ext.isEmpty && name.hasSuffix("." + ext) {
                if best == nil || ext.count > best!.1 { best = (format, ext.count) }
            }
        }
        if let best { return best.0 }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return folder
        }
        return nil
    }

    /// The name of `url` without its (possibly double) extension: "photos.tar.gz" → "photos".
    public static func baseName(of url: URL) -> String {
        let name = url.lastPathComponent
        if let format = detect(url), format.id != "folder" {
            let lower = name.lowercased()
            for ext in format.extensions.sorted(by: { $0.count > $1.count }) where !ext.isEmpty && lower.hasSuffix("." + ext) {
                return String(name.dropLast(ext.count + 1))
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
