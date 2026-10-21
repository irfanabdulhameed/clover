import Foundation

/// One petal in the bloom.
public struct Target: Hashable, Sendable, Identifiable {
    public enum Mode: String, Sendable {
        /// One output per input file.
        case each
        /// All inputs into one output (merge, one archive).
        case combine
        /// Decided by the chosen option: `Options.combine` or `Options.each`.
        case byOption
    }

    /// Unique within one bloom: "jpg", "pdf", "pdf-merge", "zip".
    public let id: String
    public let format: Format
    /// Petal label: usually the format name, or a verb ("Compress", "Merge", "Extract").
    public let title: String
    public let options: [Option]
    public let defaultOption: Option?
    public let mode: Mode

    public init(id: String, format: Format, title: String, options: [Option] = [], defaultOption: Option? = nil, mode: Mode = .each) {
        self.id = id
        self.format = format
        self.title = title
        self.options = options
        self.defaultOption = defaultOption ?? options.first
        self.mode = mode
    }

    public func combines(with option: Option?) -> Bool {
        switch mode {
        case .each: false
        case .combine: true
        case .byOption: (option ?? defaultOption)?.id != Options.each.id
        }
    }
}

/// Decides which petals the bloom shows for a set of files.
public final class Catalog: @unchecked Sendable {
    public let router: Router

    public init(router: Router) { self.router = router }

    /// Preferred order of targets. The bloom places them by this order.
    public static let order: [String] = [
        "jpg", "png", "heic", "webp", "avif", "tiff", "gif", "bmp", "ico", "icns",
        "pdf", "pdf-merge", "pdf-compress",
        "mp4", "mov", "webm", "mkv",
        "mp3", "m4a", "wav", "flac", "aiff", "ogg", "opus",
        "docx", "rtf", "html", "txt",
        "zip", "tgz", "folder",
    ]

    public func targets(for urls: [URL]) -> [Target] {
        let formats = urls.compactMap(Formats.detect)
        guard !formats.isEmpty, formats.count == urls.count else {
            // Something unknown in the selection: only archiving works for anything.
            return urls.isEmpty ? [] : archiveTargets(count: urls.count)
        }
        return targets(forFormats: formats)
    }

    public func targets(forFormats formats: [Format]) -> [Target] {
        guard !formats.isEmpty else { return [] }
        let unique = Array(Set(formats))
        let many = formats.count > 1
        var result: [Target] = []

        // Formats every input can reach, or already is (those files are skipped),
        // as long as at least one input really converts.
        let reach = Dictionary(uniqueKeysWithValues: unique.map { ($0, router.reachable(from: $0)) })
        var reachable = Set(reach.values.flatMap { $0 }).filter { candidate in
            unique.allSatisfy { reach[$0]!.contains(candidate) || $0 == candidate }
        }
        // Archiving is offered separately below.
        reachable.subtract([Formats.zip, Formats.tgz])

        let allPDF = unique.allSatisfy { $0 == Formats.pdf }
        let allImagesOrPDF = unique.allSatisfy { $0.family == .image || $0 == Formats.pdf }

        for format in reachable {
            if format == Formats.pdf {
                if allPDF {
                    result.append(Target(id: "pdf-compress", format: format, title: "Compress",
                                         options: [Options.balanced, Options.small], mode: .each))
                    continue
                }
                if many && allImagesOrPDF && router.combiner(for: formats, into: Formats.pdf) != nil {
                    result.append(Target(id: "pdf", format: format, title: "PDF",
                                         options: [Options.combine, Options.each], mode: .byOption))
                    continue
                }
            }
            if format == Formats.folder {
                result.append(Target(id: "folder", format: format, title: "Extract"))
                continue
            }
            let options = Catalog.options(for: format, from: unique)
            result.append(Target(id: format.id, format: format, title: format.name,
                                 options: options.list, defaultOption: options.default))
        }

        if many && allPDF && router.combiner(for: formats, into: Formats.pdf) != nil {
            result.append(Target(id: "pdf-merge", format: Formats.pdf, title: "Merge", mode: .combine))
        }
        result += archiveTargets(count: formats.count)
        return Catalog.sorted(result)
    }

    private func archiveTargets(count: Int) -> [Target] {
        let probe = [Formats.folder]
        var result: [Target] = []
        for format in [Formats.zip, Formats.tgz] where router.combiner(for: probe, into: format) != nil {
            result.append(Target(id: format.id, format: format, title: format.name, mode: .combine))
        }
        return result
    }

    static func sorted(_ targets: [Target]) -> [Target] {
        targets.sorted { a, b in
            let ia = order.firstIndex(of: a.id) ?? order.count
            let ib = order.firstIndex(of: b.id) ?? order.count
            return ia == ib ? a.id < b.id : ia < ib
        }
    }

    /// The chips for a target format.
    public static func options(for output: Format, from inputs: [Format]) -> (list: [Option], default: Option?) {
        switch output.id {
        case "jpg", "heic", "avif", "webp":
            return ([Options.best, Options.balanced, Options.small], Options.balanced)
        case "mp4", "mov", "mkv", "webm":
            return ([Options.original, Options.p1080, Options.p720, Options.small], Options.original)
        case "gif" where inputs.contains(where: { $0.family == .video }):
            return ([Options.large, Options.medium, Options.small], Options.medium)
        case "mp3", "ogg", "opus":
            return ([Options.best, Options.balanced, Options.small], Options.balanced)
        case "m4a":
            return ([Options.best, Options.balanced, Options.small, Options.lossless], Options.balanced)
        default:
            return ([], nil)
        }
    }
}
