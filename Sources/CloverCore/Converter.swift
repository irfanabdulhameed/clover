import Foundation

/// A choice shown as a chip next to a petal: Best / Balanced / Small, 1080p, One PDF, ...
public struct Option: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum Options {
    public static let best = Option(id: "best", title: "Best")
    public static let balanced = Option(id: "balanced", title: "Balanced")
    public static let small = Option(id: "small", title: "Small")
    public static let lossless = Option(id: "lossless", title: "Lossless")

    public static let original = Option(id: "original", title: "Original")
    public static let p1080 = Option(id: "1080p", title: "1080p")
    public static let p720 = Option(id: "720p", title: "720p")

    public static let large = Option(id: "large", title: "Large")
    public static let medium = Option(id: "medium", title: "Medium")

    /// Many files into one output (one PDF, one archive).
    public static let combine = Option(id: "combine", title: "One PDF")
    /// One output per input file.
    public static let each = Option(id: "each", title: "PDF per file")
}

/// What a converter needs while it runs.
public struct StepContext: Sendable {
    public let option: Option?
    public let tools: Tools
    /// The user's quality and naming choices.
    public let settings: ConversionSettings
    /// Report progress of this step, 0...1. Safe to call from any thread.
    public let progress: @Sendable (Double) -> Void

    public init(option: Option?, tools: Tools, settings: ConversionSettings = ConversionSettings(),
                progress: @escaping @Sendable (Double) -> Void = { _ in }) {
        self.option = option
        self.tools = tools
        self.settings = settings
        self.progress = progress
    }

    /// The option id, falling back to "balanced".
    public var quality: String { option?.id ?? Options.balanced.id }
}

/// Turns one file into another format.
///
/// Contract:
/// - `convert` writes only inside `directory`, a fresh private temp folder, and returns the
///   top-level items it made there (usually one file named `baseName.<ext>`; a folder for
///   results with many files, such as every page of a PDF).
/// - Clover moves those items next to the original afterwards and gives them free names,
///   so converters never pick final names or check for clashes.
/// - Throw `ConversionError` on failure. Check `Task.isCancelled` in long loops;
///   `ProcessRunner` already stops its process when the task is cancelled.
public protocol Converter: Sendable {
    var id: String { get }
    /// Lower is preferred when two converters can do the same thing.
    var cost: Int { get }
    /// Every format this converter can make from `input`. Pure, no file access.
    func outputs(from input: Format) -> [Format]
    /// Whether its engine is present (built-in engines always are).
    func isAvailable(_ tools: Tools) -> Bool
    func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL]
}

/// Turns many files into one output (merge PDFs, images into one PDF, one ZIP).
public protocol Combiner: Sendable {
    var id: String { get }
    func canCombine(_ inputs: [Format], into output: Format) -> Bool
    func isAvailable(_ tools: Tools) -> Bool
    /// Same contract as `Converter.convert`, for many inputs.
    func combine(_ inputs: [URL], to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL]
}

public extension Converter {
    var cost: Int { 10 }
    func isAvailable(_ tools: Tools) -> Bool { true }
}

public extension Combiner {
    func isAvailable(_ tools: Tools) -> Bool { true }
}

public enum ConversionError: LocalizedError, Equatable {
    case unsupported(String)
    case toolMissing(String)
    case failed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupported(let what): "Clover can't convert \(what)."
        case .toolMissing(let tool): "\(tool) isn't installed."
        case .failed(let why): why
        case .cancelled: "Cancelled."
        }
    }
}
