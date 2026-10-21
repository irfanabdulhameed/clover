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

    /// Moves each item from a temp folder into `directory` under a free name.
    /// One call at a time, so two parallel jobs never pick the same free name and overwrite each other.
    public static func place(_ items: [URL], in directory: URL) throws -> [URL] {
        placeLock.lock()
        defer { placeLock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try items.map { item in
            let destination = freeURL(for: item.lastPathComponent, in: directory)
            try FileManager.default.moveItem(at: item, to: destination)
            return destination
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
