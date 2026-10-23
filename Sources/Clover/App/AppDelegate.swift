import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var hud: ResultHUD!
    private var bloom: BloomController!
    private var home: HomeController!
    private var services: ServicesProvider!
    private var updates: UpdateController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The updater's debug commands run on their own and quit.
        if UpdateDebug.run(CommandLine.arguments) { return }
        updates = UpdateController(reduceMotion: { [model] in model.settings.reduceMotion })
        hud = ResultHUD(model: model)
        bloom = BloomController(model: model)
        home = HomeController(model: model, bloom: bloom, checkForUpdates: { [weak self] in self?.updates.checkManually() })
        services = ServicesProvider(bloom: bloom)
        model.onJobStarted = { [weak self] job in self?.hud.show(job) }

        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        home.install()
        bloom.start()
        // Pictures and self-tests never check for updates.
        if !HomeController.isRender && !BloomDebug.isCommand(CommandLine.arguments) { updates.start() }
    }

    /// Opening Clover again from Finder, Spotlight or its Dock icon while it runs brings up the Dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        home?.openDashboard()
        return false
    }
}
