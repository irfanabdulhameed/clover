import Foundation

/// Where finished files go.
public enum OutputLocation: Codable, Equatable, Sendable {
    case besideOriginal
    case folder(URL)
}

public enum OutputPlacer {
    /// Splits "photo.tar.gz" into ("photo", "tar.gz"), and "photo.jpg" into ("photo", "jpg").
    public static func split(_ name: String) -> (base: String, ext: String) {
        let lower = name.lowercased()
        for double in ["tar.gz", "tar.xz", "tar.bz2"] where lower.hasSuffix("." + double) {
            return (String(name.dropLast(double.count + 1)), String(name.suffix(double.count)))
        }
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        return ext.isEmpty ? (name, "") : (String(name.dropLast(ext.count + 1)), ext)
    }

    /// A free URL in `directory` for `name`, the way Finder does it: "photo.jpg",
    /// then "photo 2.jpg", "photo 3.jpg".
    public static func freeURL(for name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        let first = directory.appendingPathComponent(name)
        if !fm.fileExists(atPath: first.path) { return first }
        let (base, ext) = split(name)
        var n = 2
        while true {
            let candidate = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    private static let placeLock = NSLock()

    /// How to name and place one job's results.
    public struct Rules: Sendable {
        public var settings: ConversionSettings
        /// The target format's name, for `{format}`.
        public var format: String
        /// The chosen option's title, for `{option}`.
        public var option: String?
        /// The job's input files. Replacing never touches these, or a folder that holds one.
        public var inputs: [URL]
        /// Paths this job already placed, so a pattern that gives two files one name can't trash the first.
        fileprivate let placed = PlacedPaths()
        /// Moves a replaced item out of the way: to the Trash. Tests swap it for a folder of their own.
        var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

        public init(settings: ConversionSettings, format: String, option: String?, inputs: [URL]) {
            self.settings = settings
            self.format = format
            self.option = option
            self.inputs = inputs
        }
    }

    /// Only touched while `placeLock` is held.
    fileprivate final class PlacedPaths: @unchecked Sendable {
        var paths = Set<String>()
    }

    /// The name a converter's item gets: the pattern replaces the base name and the extension
    /// stays, double extensions included ("Archive.tar.gz" becomes "Archive (TAR.GZ).tar.gz").
    /// A folder gets the pattern on its whole name.
    public static func finalName(for item: URL, rules: Rules) -> String {
        let name = item.lastPathComponent
        let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let (base, ext) = isFolder ? (name, "") : split(name)
        let renamed = rules.settings.name(base: base, format: rules.format, option: rules.option)
        return ext.isEmpty ? renamed : renamed + "." + ext
    }

    /// Moves each item from a temp folder into `directory` under a free name.
    /// One call at a time, so two parallel jobs never pick the same free name and overwrite each other.
    ///
    /// With `rules`, each item is first renamed by the user's name pattern. When the name is taken,
    /// `.addNumber` picks a free one ("photo 2.jpg"); `.replace` moves the old item to the Trash and
    /// takes its name, unless that item is one of the job's inputs (or holds one) or the job placed
    /// it a moment ago, in which case a free name is used as well.
    public static func place(_ items: [URL], in directory: URL, rules: Rules? = nil) throws -> [URL] {
        placeLock.lock()
        defer { placeLock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try items.map { item in
            let name = rules.map { finalName(for: item, rules: $0) } ?? item.lastPathComponent
            let destination = available(name, in: directory, rules: rules)
            try FileManager.default.moveItem(at: item, to: destination)
            rules?.placed.paths.insert(key(destination))
            return destination
        }
    }

    /// Where `name` can go. Call with `placeLock` held.
    private static func available(_ name: String, in directory: URL, rules: Rules?) -> URL {
        let fm = FileManager.default
        let wanted = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: wanted.path) else { return wanted }
        if let rules, rules.settings.onConflict == .replace, !isProtected(wanted, rules: rules),
           (try? rules.trash(wanted)) != nil, !fm.fileExists(atPath: wanted.path) {
            return wanted
        }
        return freeURL(for: name, in: directory)
    }

    /// A path in a form two spellings of the same file share: links resolved, case folded.
    private static func key(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }

    private static func isProtected(_ url: URL, rules: Rules) -> Bool {
        let target = key(url)
        if rules.placed.paths.contains(target) { return true }
        return rules.inputs.contains { input in
            let path = key(input)
            return path == target || path.hasPrefix(target + "/")
        }
    }

    public static func directory(for input: URL, location: OutputLocation) -> URL {
        switch location {
        case .besideOriginal: input.deletingLastPathComponent()
        case .folder(let url): url
        }
    }

    /// A fresh private folder for one conversion step. Removed by the caller.
    public static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clover", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Total size in bytes of a file or folder.
    public static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        var total: Int64 = 0
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in walker {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }
}
