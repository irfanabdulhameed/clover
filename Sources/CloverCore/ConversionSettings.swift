import Foundation

/// Values for the Best / Balanced / Small options.
public struct Levels: Codable, Equatable, Sendable {
    public var best: Double
    public var balanced: Double
    public var small: Double

    public init(best: Double, balanced: Double, small: Double) {
        self.best = best
        self.balanced = balanced
        self.small = small
    }

    /// The value for an option id, falling back to `balanced`.
    public subscript(optionID: String?) -> Double {
        switch optionID {
        case "best", "large": best
        case "small": small
        default: balanced
        }
    }
}

/// What to do when the output name is already taken.
public enum ConflictPolicy: String, Codable, CaseIterable, Sendable {
    /// "photo 2.jpg", the way Finder does it.
    case addNumber
    /// Move the old file to the Trash and use the name. Never applies to an input file.
    case replace
}

/// User choices that change how files are converted and named.
public struct ConversionSettings: Codable, Equatable, Sendable {
    /// JPG, HEIC, AVIF and WebP quality in percent.
    public var imageQuality = Levels(best: 92, balanced: 80, small: 60)
    /// Video quality in percent for re-encoded video (higher is better and larger).
    public var videoQuality: Double = 60
    /// Height of the "Small" video option.
    public var smallVideoHeight: Int = 480
    /// Lossy audio bitrate in kbit/s (MP3, M4A, Opus, OGG, and audio inside video).
    public var audioBitrate = Levels(best: 256, balanced: 192, small: 128)
    /// GIF width in pixels when made from video (Large / Medium / Small).
    public var gifWidth = Levels(best: 720, balanced: 480, small: 320)
    /// Output file name. `{name}` is the original name, `{format}` the new format's name,
    /// `{option}` the chosen option. The extension is added after.
    public var namePattern = "{name}"
    public var onConflict = ConflictPolicy.addNumber

    public init() {}

    /// Applies `namePattern`: ("photo", "JPG", "Small") → "photo (JPG)".
    public func name(base: String, format: String, option: String?) -> String {
        var result = namePattern
            .replacingOccurrences(of: "{name}", with: base)
            .replacingOccurrences(of: "{format}", with: format)
            .replacingOccurrences(of: "{option}", with: option ?? "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        // A pattern like "{name} ({option})" with no option leaves "photo ()".
        result = result.replacingOccurrences(of: " ()", with: "").replacingOccurrences(of: "()", with: "")
        return result.isEmpty ? base : result
    }
}
