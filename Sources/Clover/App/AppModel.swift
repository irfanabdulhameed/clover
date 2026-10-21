import AppKit
import CloverCore

/// Everything the windows share: engines, routes, settings, jobs and recents.
@MainActor
final class AppModel: ObservableObject {
    let settings = Settings()
    let recents = RecentStore()
    let router: Router
    let service: ConversionService
    @Published private(set) var tools: Tools

    /// Set by the app delegate so the result chip appears for every new job.
    var onJobStarted: ((ConversionJob) -> Void)?

    init() {
        let tools = Tools.detect()
        self.tools = tools
        router = Registry.makeRouter(tools: tools)
        service = ConversionService(router: router)
        service.location = { [settings] in settings.outputLocation }
        service.onFinish = { [recents] job in recents.add(job) }
    }

    var catalog: Catalog { service.catalog }

    /// Looks for ffmpeg and cwebp again, after the user installs one.
    func refreshTools() {
        let found = Tools.detect()
        router.update(tools: found)
        tools = found
    }

    func targets(for files: [URL]) -> [Target] {
        catalog.targets(for: files)
    }

    @discardableResult
    func convert(_ files: [URL], to target: Target, option: Option? = nil) -> ConversionJob {
        let job = service.start(ConversionRequest(inputs: files, target: target, option: option))
        onJobStarted?(job)
        return job
    }
}
