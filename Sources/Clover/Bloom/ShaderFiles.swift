import SwiftUI

/// Finds Clover's compiled shaders and their data: in the app's Resources, or, for a
/// debug run from .build, in the source tree's Resources folder, found up from the binary.
/// The shaders are compiled by .github/workflows/shaders.yml, since the Command Line
/// Tools have no Metal compiler.
enum ShaderFiles {
    static func resource(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let d = dir else { break }
            let url = d.appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    static func library(_ name: String) -> ShaderLibrary? {
        resource(name, "metallib").map { ShaderLibrary(url: $0) }
    }
}

/// The border beam on a finished result chip: libraries.dev/beam's Rotate family, Large
/// (`md`), Colorful, going twice round the chip while it fades from full to nothing
/// (Irfan, 21 Nov 2026).
enum BorderBeams {
    nonisolated(unsafe) static let library: ShaderLibrary? = ShaderFiles.library("BorderBeam")

    static var available: Bool { library != nil && BeamSpec.loaded != nil }

    /// Two laps of the beam, at its own speed.
    static let laps = 2.0
    static var duration: Double { laps * (BeamSpec.loaded?.defaults.duration.rotate ?? 1.96) }

    /// How strong the beam is `age` seconds after the chip flipped to its result: 1 to 0
    /// over the two laps, on CSS `ease`, as the original fades.
    static func fade(_ age: Double) -> Double {
        1 - BeamAnimation.cssEase(min(max(age / duration, 0), 1))
    }
}
