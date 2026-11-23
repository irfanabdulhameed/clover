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

    /// How much stronger than the original the beam is drawn, so it reads on the frosted
    /// chip (Irfan, 23 Nov 2026: "the border glow is not that visible"). Each layer is
    /// still capped at full opacity by the shader.
    static let strength = 2.4

    /// How strong the beam is `age` seconds after the chip flipped to its result: full
    /// through the first third of the two laps, then down to nothing by their end.
    static func fade(_ age: Double) -> Double {
        let u = min(max(age / duration, 0), 1)
        let x = min(max((u - 1.0 / 3) / (2.0 / 3), 0), 1)
        return 1 - x * x * (3 - 2 * x)
    }
}
