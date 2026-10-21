import Foundation

/// External command-line engines Clover can use when they are installed.
public struct Tools: Sendable, Equatable {
    public var ffmpeg: URL?
    public var ffprobe: URL?
    public var cwebp: URL?

    public init(ffmpeg: URL? = nil, ffprobe: URL? = nil, cwebp: URL? = nil) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.cwebp = cwebp
    }

    /// Looks in Homebrew's folders and on PATH. Apps opened from Finder get a short PATH,
    /// so the Homebrew folders are checked explicitly.
    public static func detect() -> Tools {
        Tools(ffmpeg: find("ffmpeg"), ffprobe: find("ffprobe"), cwebp: find("cwebp"))
    }

    public static func find(_ name: String) -> URL? {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        for dir in dirs {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// For the engine list in Home and Settings.
    public var status: [(name: String, path: URL?, install: String)] {
        [
            ("ffmpeg", ffmpeg, "brew install ffmpeg"),
            ("cwebp", cwebp, "brew install webp"),
        ]
    }
}

/// Runs a command-line tool and waits for it.
public enum ProcessRunner {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    /// Runs `executable` with `arguments`. Each line of standard output goes to `onLine`
    /// as it arrives (used for ffmpeg's progress). Cancelling the calling task stops the
    /// process. Throws `ConversionError.failed` with the end of stderr when the exit
    /// status isn't 0, unless `allowFailure` is set.
    @discardableResult
    public static func run(
        _ executable: URL,
        _ arguments: [String],
        currentDirectory: URL? = nil,
        allowFailure: Bool = false,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let collector = OutputCollector(onLine: onLine)
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.appendOut(data) }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.appendErr(data) }
        }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: ConversionError.failed("Couldn't start \(executable.lastPathComponent): \(error.localizedDescription)"))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        collector.appendOut(out.fileHandleForReading.readDataToEndOfFile())
        collector.appendErr(err.fileHandleForReading.readDataToEndOfFile())
        collector.flush()

        if Task.isCancelled { throw ConversionError.cancelled }
        let result = Result(status: status, stdout: collector.stdout, stderr: collector.stderr)
        if status != 0 && !allowFailure {
            let tail = result.stderr.split(separator: "\n").suffix(3).joined(separator: " ")
            throw ConversionError.failed("\(executable.lastPathComponent) failed: \(tail.isEmpty ? "exit \(status)" : tail)")
        }
        return result
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var pending = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        outData.append(data)
        var lines: [String] = []
        if onLine != nil {
            pending += String(decoding: data, as: UTF8.self)
            while let range = pending.range(of: "\n") {
                lines.append(String(pending[..<range.lowerBound]))
                pending.removeSubrange(..<range.upperBound)
            }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func appendErr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        errData.append(data)
        // Keep only the last 64 KB; ffmpeg can be chatty.
        if errData.count > 65_536 { errData = errData.suffix(65_536) }
        lock.unlock()
    }

    func flush() {
        lock.lock()
        let rest = pending
        pending = ""
        lock.unlock()
        if !rest.isEmpty { onLine?(rest) }
    }

    var stdout: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }
    var stderr: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }
}
