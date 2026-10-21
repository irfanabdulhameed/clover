import Foundation
import ImageIO
import Testing
@testable import CloverCore

// How the settings change results: image quality, output names and the conflict policy.
// The video and audio mappings are tested with the ffmpeg commands in FFmpegTests.swift.

/// Stands in for the Trash, so tests never fill the real one: replaced items move into a folder of its own.
private final class Bin: @unchecked Sendable {
    let folder: URL
    private let lock = NSLock()
    private var count = 0
    var fails = false

    init() { folder = (try? OutputPlacer.makeTempDirectory()) ?? FileManager.default.temporaryDirectory }

    func put(_ url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        if fails { throw CocoaError(.fileWriteNoPermission) }
        count += 1
        try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent("\(count)-\(url.lastPathComponent)"))
    }

    var contents: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}

private func names(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

private func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

private func write(_ content: String, to url: URL) throws {
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func rules(_ pattern: String = "{name}", format: String = "JPG", option: String? = "Balanced",
                   conflict: ConflictPolicy = .addNumber, inputs: [URL] = [], bin: Bin? = nil) -> OutputPlacer.Rules {
    var settings = ConversionSettings()
    settings.namePattern = pattern
    settings.onConflict = conflict
    var result = OutputPlacer.Rules(settings: settings, format: format, option: option, inputs: inputs)
    if let bin { result.trash = { try bin.put($0) } }
    return result
}

// MARK: - Image quality

struct ImageQualityTests {
    @Test func percentsMapToImageIO() {
        let defaults = ConversionSettings()
        #expect(["best", "balanced", "small"].map { ImageKit.quality($0, settings: defaults) } == [0.92, 0.8, 0.6])
        #expect(ImageKit.quality("balanced") == 0.8)
        var settings = ConversionSettings()
        settings.imageQuality = Levels(best: 100, balanced: 50, small: 10)
        #expect(["best", "balanced", "small"].map { ImageKit.quality($0, settings: settings) } == [1, 0.5, 0.1])
        // Out of range values stop at the ends.
        settings.imageQuality = Levels(best: 400, balanced: 50, small: -5)
        #expect(ImageKit.quality("best", settings: settings) == 1 && ImageKit.quality("small", settings: settings) == 0)
        #expect(ImageKit.qualityPercent("balanced", settings: ConversionSettings()) == 80)
    }

    /// A picture of random pixels, so its size shows how hard the encoder compressed it.
    private func noisyPNG(at url: URL) throws {
        let side = 200
        var bytes = (0..<side * side * 4).map { _ in UInt8.random(in: 0...255) }
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        let image = bytes.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func jpgSizeFollowsTheSettings() async throws {
        let dir = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("noise.png")
        try noisyPNG(at: input)

        func size(_ settings: ConversionSettings, _ option: Option) async throws -> Int {
            let work = try OutputPlacer.makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: work) }
            let context = StepContext(option: option, tools: Tools(), settings: settings)
            let made = try await ImageIOConverter().convert(input, from: Formats.png, to: Formats.jpg, into: work, baseName: "noise", context: context)
            return try made[0].resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        var high = ConversionSettings()
        high.imageQuality = Levels(best: 99, balanced: 95, small: 90)
        var low = ConversionSettings()
        low.imageQuality = Levels(best: 30, balanced: 20, small: 5)
        let sharp = try await size(high, Options.balanced)
        let rough = try await size(low, Options.balanced)
        #expect(rough * 2 < sharp)
        // Each chip reads its own percent.
        var mixed = ConversionSettings()
        mixed.imageQuality = Levels(best: 99, balanced: 50, small: 5)
        let best = try await size(mixed, Options.best)
        let small = try await size(mixed, Options.small)
        #expect(small * 2 < best)
    }

    @Test(.enabled(if: Tools.detect().cwebp != nil))
    func webpSizeFollowsTheSettings() async throws {
        let dir = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("noise.png")
        try noisyPNG(at: input)

        func size(percent: Double) async throws -> Int {
            var settings = ConversionSettings()
            settings.imageQuality = Levels(best: percent, balanced: percent, small: percent)
            let work = try OutputPlacer.makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: work) }
            let context = StepContext(option: Options.balanced, tools: Tools.detect(), settings: settings)
            let made = try await WebPConverter().convert(input, from: Formats.png, to: Formats.webp, into: work, baseName: "noise", context: context)
            return try made[0].resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        let sharp = try await size(percent: 95)
        let rough = try await size(percent: 10)
        #expect(rough * 2 < sharp)
    }
}

// MARK: - Naming

struct OutputNamingTests {
    /// Places `name` (a file) into a fresh folder under `rules` and returns the name it got.
    private func placedName(_ name: String, rules: OutputPlacer.Rules, folder: Bool = false) throws -> String {
        let source = try OutputPlacer.makeTempDirectory()
        let destination = try OutputPlacer.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        let item = source.appendingPathComponent(name)
        if folder {
            try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        } else {
            try write("x", to: item)
        }
        return try OutputPlacer.place([item], in: destination, rules: rules)[0].lastPathComponent
    }

    @Test func eachTokenIsReplaced() throws {
        #expect(try placedName("photo.jpg", rules: rules("{name}")) == "photo.jpg")
        #expect(try placedName("photo.jpg", rules: rules("{name} ({format})")) == "photo (JPG).jpg")
        #expect(try placedName("photo.jpg", rules: rules("{name} - {option}")) == "photo - Balanced.jpg")
        #expect(try placedName("photo.jpg", rules: rules("{format} {name} {option}")) == "JPG photo Balanced.jpg")
        #expect(try placedName("photo.jpg", rules: rules("Converted")) == "Converted.jpg")
        #expect(try placedName("photo.jpg", rules: rules("{name} {format} {format}")) == "photo JPG JPG.jpg")
    }

    @Test func noOptionLeavesNoEmptyBrackets() throws {
        #expect(try placedName("notes.txt", rules: rules("{name} ({option})", format: "TXT", option: nil)) == "notes.txt")
        #expect(try placedName("notes.txt", rules: rules("{name} {format}", format: "TXT", option: nil)) == "notes TXT.txt")
    }

    @Test func dotsInTheNameAreKept() throws {
        #expect(try placedName("my.photo.v2.png", rules: rules("{name} ({format})", format: "PNG")) == "my.photo.v2 (PNG).png")
    }

    @Test func doubleExtensionsStayIntact() throws {
        let r = rules("{name} ({format})", format: "TAR.GZ", option: nil)
        #expect(try placedName("Archive.tar.gz", rules: r) == "Archive (TAR.GZ).tar.gz")
        #expect(try placedName("backup.tar.xz", rules: r) == "backup (TAR.GZ).tar.xz")
        #expect(try placedName("Archive.tar.gz", rules: rules("{name}", format: "TAR.GZ")) == "Archive.tar.gz")
        #expect(OutputPlacer.split("Archive.tar.gz") == ("Archive", "tar.gz"))
    }

    @Test func foldersGetThePatternOnTheirWholeName() throws {
        // A folder named "report.v2" has no extension to keep.
        #expect(try placedName("report.v2", rules: rules("{name} ({format})", format: "PNG", option: nil), folder: true) == "report.v2 (PNG)")
        #expect(try placedName("scans", rules: rules("{name} - {option}", format: "JPG", option: "Small"), folder: true) == "scans - Small")
    }

    @Test func combinedResultsFollowThePattern() throws {
        let pdf = rules("{name} ({format})", format: "PDF", option: "One PDF")
        #expect(try placedName("Combined.pdf", rules: pdf) == "Combined (PDF).pdf")
        let zip = rules("{name} {option}", format: "ZIP", option: nil)
        #expect(try placedName("Archive.zip", rules: zip) == "Archive.zip")
    }

    @Test func nameFunctionStaysSafe() {
        var settings = ConversionSettings()
        settings.namePattern = "{format}/{name}: {option}"
        #expect(settings.name(base: "a", format: "JPG", option: "Best") == "JPG-a- Best")
        settings.namePattern = ""
        #expect(settings.name(base: "a", format: "JPG", option: nil) == "a")
    }

    @Test func withoutRulesNamesAreKept() throws {
        let source = try OutputPlacer.makeTempDirectory()
        let destination = try OutputPlacer.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        let item = source.appendingPathComponent("photo.jpg")
        try write("x", to: item)
        #expect(try OutputPlacer.place([item], in: destination)[0].lastPathComponent == "photo.jpg")
    }
}

// MARK: - Name conflicts

struct ConflictPolicyTests {
    private func setUp() throws -> (source: URL, destination: URL, bin: Bin, cleanup: () -> Void) {
        let source = try OutputPlacer.makeTempDirectory()
        let destination = try OutputPlacer.makeTempDirectory()
        let bin = Bin()
        return (source, destination, bin, {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
            bin.remove()
        })
    }

    @Test func addNumberKeepsTheOldFile() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        try write("old", to: destination.appendingPathComponent("photo.jpg"))
        let item = source.appendingPathComponent("photo.jpg")
        try write("new", to: item)

        let placed = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .addNumber, bin: bin))
        #expect(placed[0].lastPathComponent == "photo 2.jpg")
        #expect(text(destination.appendingPathComponent("photo.jpg")) == "old")
        #expect(text(placed[0]) == "new")
        #expect(bin.contents.isEmpty)
    }

    @Test func replaceTrashesTheOlderOutput() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        let old = destination.appendingPathComponent("photo.jpg")
        try write("old", to: old)
        let item = source.appendingPathComponent("photo.jpg")
        try write("new", to: item)

        let placed = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .replace, bin: bin))
        #expect(placed[0].lastPathComponent == "photo.jpg")
        #expect(text(old) == "new")
        #expect(names(in: destination) == ["photo.jpg"])
        // The old file was handed to the Trash, whole.
        #expect(bin.contents == ["1-photo.jpg"])
        #expect(text(bin.folder.appendingPathComponent("1-photo.jpg")) == "old")
    }

    @Test func replaceTrashesAnOlderFolder() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        let old = destination.appendingPathComponent("scans", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try write("old", to: old.appendingPathComponent("a.txt"))
        let item = source.appendingPathComponent("scans", isDirectory: true)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        try write("new", to: item.appendingPathComponent("b.txt"))

        let placed = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .replace, bin: bin))
        #expect(placed[0].lastPathComponent == "scans")
        #expect(names(in: old) == ["b.txt"])
        #expect(bin.contents == ["1-scans"])
    }

    @Test func replaceWithNothingToReplaceJustPlaces() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        let item = source.appendingPathComponent("photo.jpg")
        try write("new", to: item)
        let placed = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .replace, bin: bin))
        #expect(placed[0].lastPathComponent == "photo.jpg" && bin.contents.isEmpty)
    }

    @Test func replaceNeverTouchesAnInput() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        // The result would get the input's own name: it gets a number instead.
        let input = destination.appendingPathComponent("photo.jpg")
        try write("original", to: input)
        let item = source.appendingPathComponent("photo.jpg")
        try write("converted", to: item)

        let placed = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .replace, inputs: [input], bin: bin))
        #expect(placed[0].lastPathComponent == "photo 2.jpg")
        #expect(text(input) == "original")
        #expect(text(placed[0]) == "converted")
        #expect(names(in: destination) == ["photo 2.jpg", "photo.jpg"])
        #expect(bin.contents.isEmpty)
    }

    @Test func replaceNeverTouchesAnInputSpelledAnotherWay() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        let input = destination.appendingPathComponent("Photo.JPG")
        try write("original", to: input)
        // The same file on a case-insensitive disk, and the input reached through a path with a ".." in it.
        let item = source.appendingPathComponent("photo.jpg")
        try write("converted", to: item)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let roundabout = destination.appendingPathComponent("sub/../Photo.JPG")

        _ = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .replace, inputs: [roundabout], bin: bin))
        #expect(text(input) == "original")
        #expect(bin.contents.isEmpty)
    }

    @Test func replaceNeverTrashesAFolderHoldingAnInput() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        let existing = destination.appendingPathComponent("Pics", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let input = existing.appendingPathComponent("a.zip")
        try write("original", to: input)
        let item = source.appendingPathComponent("Pics", isDirectory: true)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        try write("new", to: item.appendingPathComponent("b.txt"))

        let placed = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .replace, inputs: [input], bin: bin))
        #expect(placed[0].lastPathComponent == "Pics 2")
        #expect(text(input) == "original")
        #expect(bin.contents.isEmpty)
    }

    @Test func replaceKeepsEarlierResultsOfTheSameJob() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        // A pattern with no {name} gives every file of a batch the same name: none may replace another.
        let r = rules("Converted", conflict: .replace, bin: bin)
        var placed: [URL] = []
        for n in 1...3 {
            let item = source.appendingPathComponent("file\(n).jpg")
            try write("result \(n)", to: item)
            placed += try OutputPlacer.place([item], in: destination, rules: r)
        }
        #expect(placed.map(\.lastPathComponent) == ["Converted.jpg", "Converted 2.jpg", "Converted 3.jpg"])
        #expect(placed.compactMap(text) == ["result 1", "result 2", "result 3"])
        #expect(bin.contents.isEmpty)
    }

    @Test func replaceFallsBackToANumberWhenTheTrashFails() throws {
        let (source, destination, bin, cleanup) = try setUp()
        defer { cleanup() }
        bin.fails = true
        let old = destination.appendingPathComponent("photo.jpg")
        try write("old", to: old)
        let item = source.appendingPathComponent("photo.jpg")
        try write("new", to: item)

        let placed = try OutputPlacer.place([item], in: destination, rules: rules(conflict: .replace, bin: bin))
        #expect(placed[0].lastPathComponent == "photo 2.jpg")
        #expect(text(old) == "old")
    }

    @Test func parallelJobsStaySafeWhenReplacing() async throws {
        let destination = try OutputPlacer.makeTempDirectory()
        let bin = Bin()
        defer {
            try? FileManager.default.removeItem(at: destination)
            bin.remove()
        }
        // Eight jobs finish at once, each with a result for the same name and its own rules.
        let placed = try await withThrowingTaskGroup(of: URL.self) { group in
            for n in 0..<8 {
                group.addTask {
                    let temp = try OutputPlacer.makeTempDirectory()
                    defer { try? FileManager.default.removeItem(at: temp) }
                    let file = temp.appendingPathComponent("scan.pdf")
                    try "job \(n)".write(to: file, atomically: true, encoding: .utf8)
                    return try OutputPlacer.place([file], in: destination, rules: rules(format: "PDF", conflict: .replace, bin: bin))[0]
                }
            }
            var all: [URL] = []
            for try await url in group { all.append(url) }
            return all
        }
        // Every job got the plain name, in turn; one result is left and the seven before it were trashed.
        #expect(Set(placed.map(\.lastPathComponent)) == ["scan.pdf"])
        #expect(names(in: destination) == ["scan.pdf"])
        #expect(bin.contents.count == 7)
    }
}

// MARK: - Through the service

@MainActor
struct ServiceNamingTests {
    private func makeJob(_ settings: ConversionSettings, inputs: [URL], target: Target, option: Option? = nil) async -> ConversionJob {
        let service = ConversionService(router: Registry.makeRouter(tools: Tools()))
        service.settings = { settings }
        let job = service.start(ConversionRequest(inputs: inputs, target: target, option: option))
        await service.wait(job)
        return job
    }

    private func makePNG(at url: URL) throws {
        let context = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private let jpg = Target(id: "jpg", format: Formats.jpg, title: "JPG", options: [Options.best, Options.balanced, Options.small], defaultOption: Options.balanced)

    @Test func resultsAreNamedByThePattern() async throws {
        let dir = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("photo.png")
        try makePNG(at: input)
        var settings = ConversionSettings()
        settings.namePattern = "{name} ({format}, {option})"

        let job = await makeJob(settings, inputs: [input], target: jpg, option: Options.small)
        #expect(job.state == .done)
        #expect(job.outputs.map(\.lastPathComponent) == ["photo (JPG, Small).jpg"])
        #expect(names(in: dir) == ["photo (JPG, Small).jpg", "photo.png"])
    }

    @Test func defaultSettingsKeepTheOldNames() async throws {
        let dir = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("photo.png")
        try makePNG(at: input)

        let first = await makeJob(ConversionSettings(), inputs: [input], target: jpg)
        let second = await makeJob(ConversionSettings(), inputs: [input], target: jpg)
        #expect(first.outputs.map(\.lastPathComponent) == ["photo.jpg"])
        #expect(second.outputs.map(\.lastPathComponent) == ["photo 2.jpg"])
    }
}
