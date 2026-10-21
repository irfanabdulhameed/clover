import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var hud: ResultHUD!
    private var bloom: BloomController!
    private var home: HomeController!
    private var services: ServicesProvider!

    func applicationDidFinishLaunching(_ notification: Notification) {
        hud = ResultHUD(model: model)
        bloom = BloomController(model: model)
        home = HomeController(model: model, bloom: bloom)
        services = ServicesProvider(bloom: bloom)
        model.onJobStarted = { [weak self] job in self?.hud.show(job) }

        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        home.install()
        bloom.start()
    }

    /// Opening Clover again from Finder or Spotlight while it runs brings up the Dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        home.openDashboard()
        return false
    }
}
