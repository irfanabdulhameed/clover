import AppKit
import SwiftUI

/// The menu bar icon and its Home popover.
@MainActor
final class HomeController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let bloom: BloomController
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private lazy var dashboard = DashboardWindowController(model: model, bloom: bloom, checkForUpdates: checkForUpdates)
    private let checkForUpdates: () -> Void

    /// Where the menu bar icon is on screen, for a result chip that waits under it. nil until the icon exists.
    static var statusIconFrame: () -> NSRect? = { nil }

    init(model: AppModel, bloom: BloomController, checkForUpdates: @escaping () -> Void) {
        self.model = model
        self.bloom = bloom
        self.checkForUpdates = checkForUpdates
        super.init()
    }

    /// The flags that draw pictures and quit instead of starting the app.
    static let renderFlags = ["--render-home", "--render-chip-frames", "--render-dashboard"]
    static var isRender: Bool { renderFlags.contains { CommandLine.arguments.contains($0) } }

    /// Puts the icon in the menu bar. With `--render-home <folder>`, `--render-dashboard <folder>` or
    /// `--render-chip-frames <folder>` it draws pictures into the folder instead, and quits.
    func install() {
        if let folder = Self.argument(after: "--render-home") {
            Task { await HomeRender.renderHome(into: URL(fileURLWithPath: folder)); exit(0) }
            return
        }
        if let folder = Self.argument(after: "--render-chip-frames") {
            Task { await ChipRender.render(into: URL(fileURLWithPath: folder)); exit(0) }
            return
        }
        if let folder = Self.argument(after: "--render-dashboard") {
            Task { await DashboardRender.render(into: URL(fileURLWithPath: folder)); exit(0) }
            return
        }
        // The clover's debug commands draw and quit; no icon meanwhile.
        if BloomDebug.isCommand(CommandLine.arguments) { return }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "CloverStatusItem"
        if let button = item.button {
            button.image = CloverGlyph.menuBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Clover"
            button.target = self
            button.action = #selector(statusButtonPressed)
            // Clicks and drops are handled by a view laid over the button.
            let overlay = StatusDropView(button: button)
            overlay.onLeftClick = { [weak self] in self?.togglePopover() }
            overlay.onRightClick = { [weak self] in self?.showMenu() }
            overlay.onDrop = { [weak self] files in self?.present(files, at: self?.pointBelowIcon()) }
            button.addSubview(overlay)
        }
        statusItem = item
        HomeController.statusIconFrame = { [weak item] in item?.button?.window?.frame }
    }

    /// Opens the Dashboard, for the menu and for other parts of the app.
    func openDashboard(section: DashboardSection? = nil) {
        popover.performClose(nil)
        dashboard.show(section: section)
    }

    // MARK: Menu bar item

    /// Reached by the accessibility "press" action. Real clicks go through `StatusDropView`.
    @objc private func statusButtonPressed() { togglePopover() }

    private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showMenu() {
        guard let item = statusItem, let button = item.button else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Dashboard…", key: ",") { [weak self] in self?.openDashboard() })
        menu.addItem(ActionMenuItem("Check for Updates…") { [weak self] in self?.checkForUpdates() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Quit Clover", key: "q") { NSApp.terminate(nil) })
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    // MARK: Popover

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        model.recents.prune()
        let host = NSHostingController(rootView: HomeRoot(model: model, actions: makeActions()))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        host.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        // Let go of the content after the click that closed the popover has finished.
        DispatchQueue.main.async { [popover] in
            if !popover.isShown { popover.contentViewController = nil }
        }
    }

    private func makeActions() -> HomeActions {
        HomeActions(
            chooseFiles: { [weak self] in self?.chooseFiles() },
            filesDropped: { [weak self] files in
                MainActor.assumeIsolated {
                    // The pointer is where the files were dropped, so the bloom opens right there.
                    self?.popover.performClose(nil)
                    self?.present(files, at: NSEvent.mouseLocation)
                }
            },
            reveal: { [weak self] item in self?.reveal(item) },
            open: { [weak self] item in self?.open(item) },
            remove: { [model] item in model.recents.remove(item) },
            clearAll: { [model] in model.recents.clear() },
            refreshTools: { [model] in model.refreshTools() },
            openDashboard: { [weak self] in self?.openDashboard() },
            quit: { NSApp.terminate(nil) })
    }

    // MARK: Actions

    /// Asks for files, then opens the bloom for them.
    private func chooseFiles() {
        popover.performClose(nil)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose the files to convert."
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            MainActor.assumeIsolated { self?.present(panel.urls, at: self?.pointBelowIcon()) }
        }
    }

    private func present(_ files: [URL], at point: NSPoint?) {
        guard !files.isEmpty else { return }
        bloom.present(files: files, at: point)
    }

    /// A spot under the menu bar icon, far enough down that the whole bloom fits.
    private func pointBelowIcon() -> NSPoint? {
        guard let frame = statusItem?.button?.window?.frame else { return nil }
        return NSPoint(x: frame.midX, y: frame.minY - 150)
    }

    private func existingFiles(of item: RecentItem) -> [URL] {
        let files = item.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if files.isEmpty { model.recents.prune() }
        return files
    }

    private func reveal(_ item: RecentItem) {
        let files = existingFiles(of: item)
        guard !files.isEmpty else { return }
        popover.performClose(nil)
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    private func open(_ item: RecentItem) {
        let files = existingFiles(of: item)
        guard !files.isEmpty else { return }
        popover.performClose(nil)
        for file in files { NSWorkspace.shared.open(file) }
    }

    private static func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
