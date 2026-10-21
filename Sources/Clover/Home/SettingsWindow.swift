import AppKit
import SwiftUI

/// The one Settings window. Tabs in the toolbar, like other Mac apps' settings.
@MainActor
final class SettingsWindowController: NSObject {
    private let model: AppModel
    private let login = LaunchAtLogin()
    private(set) lazy var window: NSWindow = makeWindow()

    init(model: AppModel) { self.model = model }

    /// Shows the window in front, creating it the first time.
    func show() {
        login.refresh()
        let isNew = !window.isVisible
        if isNew { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Selects a tab by index: 0 General, 1 Engines, 2 About.
    func select(tab index: Int) {
        (window.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = index
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(item("General", symbol: "gearshape", height: 335,
                                 GeneralSettingsView(settings: model.settings, login: login)))
        tabs.addTabViewItem(item("Engines", symbol: "wrench.and.screwdriver", height: 310,
                                 EnginesSettingsRoot(model: model)))
        tabs.addTabViewItem(item("About", symbol: "info.circle", height: 300, AboutView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = "General"
        return window
    }

    private func item<Content: View>(_ label: String, symbol: String, height: CGFloat, _ content: Content) -> NSTabViewItem {
        let host = NSHostingController(rootView: content.frame(width: 480, height: height))
        host.sizingOptions = [.preferredContentSize]
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
