import AppKit
import Combine
import SwiftUI

/// How big the Dashboard window is.
enum DashboardSize {
    static let standard = NSSize(width: 860, height: 580)
    static let minimum = NSSize(width: 760, height: 500)
}

/// The one Dashboard window. It is made the first time and brought to the front after that.
/// While it is open, Clover shows in the Dock and in ⌘-Tab.
@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let bloom: BloomController
    private let login = LaunchAtLogin()
    private let navigator = DashboardNavigator()
    private(set) lazy var window: NSWindow = makeWindow()
    private var titleObserver: AnyCancellable?
    private let checkForUpdates: () -> Void

    init(model: AppModel, bloom: BloomController, checkForUpdates: @escaping () -> Void) {
        self.model = model
        self.bloom = bloom
        self.checkForUpdates = checkForUpdates
    }

    /// Shows the window in front, creating it the first time. `section` picks what it shows.
    func show(section: DashboardSection? = nil) {
        if let section { navigator.section = section }
        model.recents.prune()
        login.refresh()
        Self.installMainMenuIfNeeded()
        if window.isMiniaturized { window.deminiaturize(nil) }
        DockPresence.show(.dashboard)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DockPresence.hide(.dashboard)
    }

    private func makeWindow() -> NSWindow {
        let root = DashboardRoot(model: model, login: login, navigator: navigator, actions: makeActions())
        let window = Self.makeWindow(content: root)
        window.delegate = self
        // The title follows the section.
        window.title = navigator.section.title
        titleObserver = navigator.$section.sink { [weak window] section in window?.title = section.title }
        if !window.setFrameUsingName("CloverDashboard") { window.center() }
        window.setFrameAutosaveName("CloverDashboard")
        return window
    }

    /// A Dashboard-sized window around some content. Also used by the renders.
    static func makeWindow<Content: View>(content: Content) -> NSWindow {
        let host = NSHostingController(rootView: content)
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(DashboardSize.standard)
        window.contentMinSize = DashboardSize.minimum
        return window
    }

    // MARK: Actions

    private func makeActions() -> DashboardActions {
        DashboardActions(
            chooseFiles: { [weak self] in self?.chooseFiles() },
            filesDropped: { [weak self] files in
                // The pointer is where the files were dropped, so the clover opens right there.
                MainActor.assumeIsolated { self?.bloom.present(files: files, at: NSEvent.mouseLocation) }
            },
            reveal: { [weak self] item in
                guard let files = self?.existingOutputs(of: item), !files.isEmpty else { return }
                NSWorkspace.shared.activateFileViewerSelecting(files)
            },
            open: { [weak self] item in
                guard let files = self?.existingOutputs(of: item) else { return }
                for file in files { NSWorkspace.shared.open(file) }
            },
            convertAgain: { [weak self] item in
                guard let inputs = item.inputs, !inputs.isEmpty,
                      inputs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
                self?.bloom.present(files: inputs, at: nil)
            },
            remove: { [model] item in model.recents.remove(item) },
            clearAll: { [model] in model.recents.clear() },
            refreshTools: { [model] in model.refreshTools() },
            setLaunchAtLogin: { [login] on in login.setEnabled(on) },
            openLoginItems: { [login] in login.openLoginItemsSettings() },
            checkForUpdates: checkForUpdates)
    }

    /// Home's drop zone, clicked: choose files in a sheet, then the clover opens over the window.
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose the files to convert."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let frame = self.window.frame
                self.bloom.present(files: panel.urls, at: NSPoint(x: frame.midX, y: frame.midY))
            }
        }
    }

    private func existingOutputs(of item: RecentItem) -> [URL] {
        let files = item.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if files.isEmpty { model.recents.prune() }
        return files
    }

    // MARK: Menu

    /// Clover has no menu bar of its own, so a text field would ignore ⌘V, ⌘C and ⌘A. This
    /// gives the window the usual Edit and Window menus. They stay out of sight.
    private static func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Quit Clover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: app, title: "Clover")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: windowMenu, title: "Window")

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
