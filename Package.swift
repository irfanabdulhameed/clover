// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clover",
    platforms: [.macOS(.v14)],
    targets: [
        // Formats, routes, converters and jobs. No UI.
        .target(name: "CloverCore"),
        // The menu bar app, the bloom and the command-line mode.
        .executableTarget(name: "Clover", dependencies: ["CloverCore"]),
        .testTarget(name: "CloverCoreTests", dependencies: ["CloverCore"]),
    ]
)
