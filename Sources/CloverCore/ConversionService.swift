import Foundation
import Combine

public struct ConversionRequest: Sendable {
    public let inputs: [URL]
    public let target: Target
    public let option: Option?

    public init(inputs: [URL], target: Target, option: Option? = nil) {
        self.inputs = inputs
        self.target = target
        self.option = option ?? target.defaultOption
    }
}

/// One drop on a petal: one or many files converting to one target.
@MainActor
public final class ConversionJob: ObservableObject, Identifiable {
    public enum State: Equatable {
        case running
        case done
        case failed(String)
        case cancelled
        case undone
    }

    public let id = UUID()
    public let request: ConversionRequest
    public let started = Date()
    @Published public internal(set) var state: State = .running
    /// 0...1 over the whole job.
    @Published public internal(set) var progress: Double = 0
    /// Files finished so far, out of `total`.
    @Published public internal(set) var finished = 0
    public let total: Int
    @Published public internal(set) var outputs: [URL] = []
    /// Per-file errors in a batch that otherwise worked.
    @Published public internal(set) var failures: [(file: String, message: String)] = []
    /// Files already in the target format, left alone.
    @Published public internal(set) var skipped = 0
    @Published public internal(set) var bytesIn: Int64 = 0
    @Published public internal(set) var bytesOut: Int64 = 0

    var task: Task<Void, Never>?
    var fractions: [Int: Double] = [:]

    init(request: ConversionRequest) {
        self.request = request
        self.total = request.target.combines(with: request.option) ? 1 : request.inputs.count
    }

    /// "Convert to JPG", "Merge", "Extract".
    public var title: String {
        let t = request.target
        return t.title == t.format.name ? "Convert to \(t.title)" : t.title
    }

    public var isFinished: Bool { state != .running }
}

/// Runs conversions, a few at a time per kind of work.
@MainActor
public final class ConversionService: ObservableObject {
    public let router: Router
    public let catalog: Catalog
    public var location: () -> OutputLocation
    /// The user's quality and naming choices, read when each job starts.
    public var settings: () -> ConversionSettings = { ConversionSettings() }
    @Published public private(set) var jobs: [ConversionJob] = []
    /// Called on the main thread when a job ends in any state.
    public var onFinish: ((ConversionJob) -> Void)?

    private let limits: [Family: AsyncLimiter] = [
        .image: AsyncLimiter(6), .pdf: AsyncLimiter(4), .document: AsyncLimiter(4),
        .video: AsyncLimiter(2), .audio: AsyncLimiter(4), .archive: AsyncLimiter(2),
    ]

    public init(router: Router, location: @escaping () -> OutputLocation = { .besideOriginal }) {
        self.router = router
        self.catalog = Catalog(router: router)
        self.location = location
    }

    @discardableResult
    public func start(_ request: ConversionRequest) -> ConversionJob {
        let job = ConversionJob(request: request)
        jobs.insert(job, at: 0)
        job.bytesIn = request.inputs.reduce(0) { $0 + OutputPlacer.size(of: $1) }
        job.task = Task { [weak self] in
            guard let self else { return }
            await self.run(job)
        }
        return job
    }

    public func cancel(_ job: ConversionJob) {
        job.task?.cancel()
    }

    /// Moves the job's results to the Trash.
    public func undo(_ job: ConversionJob) throws {
        for url in job.outputs where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        job.state = .undone
    }

    /// Waits for a job to end. Used by the command-line mode and tests.
    public func wait(_ job: ConversionJob) async {
        await job.task?.value
    }

    private func run(_ job: ConversionJob) async {
        let request = job.request
        let tools = router.tools
        let limiter = limits[request.target.format.family] ?? AsyncLimiter(2)
        let location = self.location()
        let settings = self.settings()

        if request.target.combines(with: request.option) {
            await combine(job, tools: tools, settings: settings, limiter: limiter, location: location)
        } else {
            let router = self.router
            await withTaskGroup(of: Void.self) { group in
                for (index, input) in request.inputs.enumerated() {
                    group.addTask {
                        await limiter.run {
                            await ConversionService.convertOne(job, index: index, input: input, router: router, tools: tools, settings: settings, location: location)
                        }
                    }
                }
            }
        }

        if Task.isCancelled {
            job.state = .cancelled
        } else if job.outputs.isEmpty {
            let already = job.skipped > 0 && job.failures.isEmpty
            job.state = .failed(already ? "Already \(request.target.format.name)." : job.failures.first?.message ?? "Nothing was converted.")
        } else {
            job.state = .done
        }
        job.progress = 1
        job.bytesOut = job.outputs.reduce(0) { $0 + OutputPlacer.size(of: $1) }
        onFinish?(job)
    }

    private nonisolated static func convertOne(_ job: ConversionJob, index: Int, input: URL, router: Router, tools: Tools, settings: ConversionSettings, location: OutputLocation) async {
        let request = job.request
        guard !Task.isCancelled else { return }
        var temps: [URL] = []
        defer { temps.forEach { try? FileManager.default.removeItem(at: $0) } }
        do {
            guard let from = Formats.detect(input) else { throw ConversionError.unsupported(input.lastPathComponent) }
            if from == request.target.format && router.route(from: from, to: from) == nil {
                // Already in this format: nothing to do for this file.
                await MainActor.run {
                    job.skipped += 1
                    job.finished += 1
                    job.report(index: index, fraction: 1)
                }
                return
            }
            guard let steps = router.route(from: from, to: request.target.format) else {
                throw ConversionError.unsupported("\(from.name) to \(request.target.format.name)")
            }
            let baseName = Formats.baseName(of: input)
            var current = input
            var currentFormat = from
            var items: [URL] = []
            for (i, step) in steps.enumerated() {
                let temp = try OutputPlacer.makeTempDirectory()
                temps.append(temp)
                let share = 1.0 / Double(steps.count)
                let context = StepContext(option: request.option, tools: tools, settings: settings) { p in
                    let fraction = (Double(i) + min(max(p, 0), 1)) * share
                    Task { @MainActor in job.report(index: index, fraction: fraction) }
                }
                items = try await step.converter.convert(current, from: currentFormat, to: step.output,
                                                         into: temp, baseName: baseName, context: context)
                try Task.checkCancellation()
                if i < steps.count - 1 {
                    guard items.count == 1 else { throw ConversionError.failed("Unexpected output from \(step.converter.id).") }
                    current = items[0]
                    currentFormat = step.output
                }
            }
            let placed = try OutputPlacer.place(items, in: OutputPlacer.directory(for: input, location: location))
            await MainActor.run {
                job.outputs += placed
                job.finished += 1
                job.report(index: index, fraction: 1)
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? ConversionError) == .cancelled { return }
            let message = error.localizedDescription
            await MainActor.run {
                job.failures.append((input.lastPathComponent, message))
                job.finished += 1
                job.report(index: index, fraction: 1)
            }
        }
    }

    private func combine(_ job: ConversionJob, tools: Tools, settings: ConversionSettings, limiter: AsyncLimiter, location: OutputLocation) async {
        let request = job.request
        let formats = request.inputs.map { Formats.detect($0) ?? Formats.folder }
        guard let combiner = router.combiner(for: formats, into: request.target.format) else {
            job.failures.append(("", ConversionError.unsupported("these files to \(request.target.format.name)").localizedDescription))
            return
        }
        let baseName: String
        if request.inputs.count == 1 {
            baseName = Formats.baseName(of: request.inputs[0])
        } else {
            baseName = request.target.format == Formats.pdf ? "Combined" : "Archive"
        }
        let destination = OutputPlacer.directory(for: request.inputs[0], location: location)
        let outcome: Result<[URL], Error> = await limiter.run {
            var temp: URL?
            defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
            do {
                let dir = try OutputPlacer.makeTempDirectory()
                temp = dir
                let context = StepContext(option: request.option, tools: tools, settings: settings) { p in
                    Task { @MainActor in job.report(index: 0, fraction: p) }
                }
                let items = try await combiner.combine(request.inputs, to: request.target.format,
                                                       into: dir, baseName: baseName, context: context)
                try Task.checkCancellation()
                return .success(try OutputPlacer.place(items, in: destination))
            } catch {
                return .failure(error)
            }
        }
        switch outcome {
        case .success(let placed):
            job.outputs += placed
            job.finished = 1
        case .failure(let error):
            if Task.isCancelled || error is CancellationError || (error as? ConversionError) == .cancelled { return }
            job.failures.append(("", error.localizedDescription))
        }
    }
}

extension ConversionJob {
    func report(index: Int, fraction: Double) {
        fractions[index] = max(fractions[index] ?? 0, fraction)
        let sum = fractions.values.reduce(0, +)
        progress = min(sum / Double(max(total, 1)), 1)
    }
}

/// Lets at most `limit` tasks run the body at once.
public actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(_ limit: Int) { self.limit = max(1, limit) }

    public func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        await acquire()
        let result = await body()
        release()
        return result
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
