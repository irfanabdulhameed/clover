import AppKit

/// Clover lives in the menu bar. While one of its windows is open, the Dashboard or the
/// update window, it also shows in the Dock and in ⌘-Tab like an ordinary app, with its own
/// icon; when the last of them closes it goes back to the menu bar only. The clover and the
/// result chip never change this, and never make Clover the active app.
@MainActor
enum DockPresence {
    enum Window: Hashable {
        case dashboard, update
    }

    private(set) static var open: Set<Window> = []

    static func show(_ window: Window) {
        let first = open.isEmpty
        open.insert(window)
        guard first else { return }
        // An app that starts as menu bar only can come up with a blank Dock tile: set the icon first.
        if let icon = Bundle.main.image(forResource: "Clover") { NSApp.applicationIconImage = icon }
        NSApp.setActivationPolicy(.regular)
    }

    static func hide(_ window: Window) {
        guard open.remove(window) != nil, open.isEmpty else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
