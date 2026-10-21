import Foundation

private let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
private let bsdtar = URL(fileURLWithPath: "/usr/bin/bsdtar")

/// Extracts an archive into a folder.
public struct ArchiveExtractor: Converter {
    public let id = "extract"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        FormatTables.archiveRead.contains(input) ? [Formats.folder] : []
    }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        let fm = FileManager.default
        let name = input.lastPathComponent
        guard fm.fileExists(atPath: input.path) else { throw ConversionError.failed("Couldn't find \(name).") }

        // Everything is unpacked into a scratch folder first, then the result is moved up.
        let scratch = directory.appendingPathComponent(".extract-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        context.progress(0.05)

        // A lone compressed file ("notes.txt.gz", "data.bz2") is not a tar: just decompress it.
        if let tool = Self.singleFileTool(for: input) {
            let output = directory.appendingPathComponent(baseName)
            try await Self.decompress(input, with: tool, to: output)
            context.progress(1)
            return [output]
        }

        try await Self.checkPaths(of: input)
        context.progress(0.15)

        var result: ProcessRunner.Result
        if from == Formats.zip {
            result = try await ProcessRunner.run(ditto, ["-x", "-k", input.path, scratch.path], allowFailure: true)
            if result.status != 0 {
                // ditto is strict about some zips (bad resource-fork entries): start over with bsdtar, which skips those.
                try? fm.removeItem(at: scratch)
                try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
                result = try await ProcessRunner.run(bsdtar, ["-xf", input.path, "--no-mac-metadata", "-C", scratch.path], allowFailure: true)
            }
        } else {
            result = try await ProcessRunner.run(bsdtar, ["-xf", input.path, "-C", scratch.path], allowFailure: true)
        }
        try Task.checkCancellation()
        guard result.status == 0 else { throw Self.error(for: result, name: name) }
        context.progress(0.8)

        let items = try Self.tidy(scratch)
        guard !items.isEmpty else { throw ConversionError.failed("\(name) is empty.") }

        let folder = directory.appendingPathComponent(baseName, isDirectory: true)
        var output: URL
        if items.count == 1, Self.isDirectory(items[0]) {
            // One top-level folder: hand that back, instead of a folder holding a single folder.
            output = directory.appendingPathComponent(items[0].lastPathComponent, isDirectory: true)
            try fm.moveItem(at: items[0], to: output)
        } else {
            output = folder
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for item in items {
                try fm.moveItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent))
            }
        }
        context.progress(1)
        return [output]
    }

    /// The top-level items of an extracted archive, without `__MACOSX` and `.DS_Store`.
    static func tidy(_ folder: URL) throws -> [URL] {
        let fm = FileManager.default
        var items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])
        for item in items where ["__MACOSX", ".DS_Store"].contains(item.lastPathComponent) {
            try? fm.removeItem(at: item)
        }
        items = items.filter { !["__MACOSX", ".DS_Store"].contains($0.lastPathComponent) }
        return items
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// The program that unpacks a single compressed file, or nil when the file is a tar of some kind.
    private static func singleFileTool(for input: URL) -> URL? {
        let name = input.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") || name.hasSuffix(".tar.xz") || name.hasSuffix(".txz")
            || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") || name.hasSuffix(".tbz") { return nil }
        if name.hasSuffix(".gz") { return URL(fileURLWithPath: "/usr/bin/gzip") }
        if name.hasSuffix(".bz2") { return URL(fileURLWithPath: "/usr/bin/bzip2") }
        if name.hasSuffix(".xz") { return Tools.find("xz") ?? URL(fileURLWithPath: "/usr/bin/xz") }
        return nil
    }

    /// `tool -dc input > output`, through the shell only to do the redirect. Paths are passed as arguments.
    private static func decompress(_ input: URL, with tool: URL, to output: URL) async throws {
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw ConversionError.toolMissing(tool.lastPathComponent)
        }
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"),
                                                 ["-c", "\"$1\" -dc -- \"$2\" > \"$3\"", "sh", tool.path, input.path, output.path],
                                                 allowFailure: true)
        guard result.status == 0 else { throw error(for: result, name: input.lastPathComponent) }
    }

    /// Refuses archives with paths that climb out of the folder (`../x`) or start at `/`.
    private static func checkPaths(of input: URL) async throws {
        let listing = try await ProcessRunner.run(bsdtar, ["-tf", input.path], allowFailure: true)
        guard listing.status == 0 else { return } // the extraction reports the real problem
        for line in listing.stdout.split(separator: "\n") {
            if line.hasPrefix("/") || line.split(separator: "/").contains("..") {
                throw ConversionError.failed("\(input.lastPathComponent) has files that point outside their folder, so Clover won't open it.")
            }
        }
    }

    private static func error(for result: ProcessRunner.Result, name: String) -> ConversionError {
        let text = (result.stderr + result.stdout).lowercased()
        if text.contains("passphrase") || text.contains("password") || text.contains("encrypted") {
            return .failed("\(name) is password-protected.")
        }
        return .failed("Couldn't extract \(name). It may be damaged or not an archive.")
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
        let fm = FileManager.default
        guard !inputs.isEmpty else { throw ConversionError.failed("There is nothing to archive.") }
        for input in inputs where !fm.fileExists(atPath: input.path) {
            throw ConversionError.failed("Couldn't find \(input.lastPathComponent).")
        }
        let output = directory.appendingPathComponent("\(baseName).\(to.fileExtension)")

        // Items go in by name, each from its own folder (-C). Two items with the same name get
        // a link under a free name in a staging folder (-H follows links named on the command line).
        let staging = directory.appendingPathComponent(".stage-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        var used = Set<String>()
        var arguments = ["-a", "-cf", output.path, "--exclude", ".DS_Store", "--exclude", "__MACOSX", "--no-mac-metadata", "-H"]
        for input in inputs {
            var parent = input.deletingLastPathComponent()
            var name = input.lastPathComponent
            if used.contains(name.lowercased()) {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                let (base, ext) = OutputPlacer.split(name)
                var n = 2
                var candidate = name
                while used.contains(candidate.lowercased()) {
                    candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
                    n += 1
                }
                name = candidate
                try fm.createSymbolicLink(at: staging.appendingPathComponent(name), withDestinationURL: input)
                parent = staging
            }
            used.insert(name.lowercased())
            arguments += ["-C", parent.path, name]
        }
        context.progress(0.1)

        let result = try await ProcessRunner.run(bsdtar, arguments, allowFailure: true)
        try Task.checkCancellation()
        guard result.status == 0, OutputPlacer.size(of: output) > 0 else {
            let detail = result.stderr.split(separator: "\n").last.map(String.init) ?? ""
            throw ConversionError.failed("Couldn't make the \(to.name) file.\(detail.isEmpty ? "" : " \(detail)")")
        }
        context.progress(1)
        return [output]
    }
}
