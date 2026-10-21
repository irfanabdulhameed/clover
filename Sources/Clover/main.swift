import AppKit

MainActor.assumeIsolated {
    let arguments = Array(CommandLine.arguments.dropFirst())

    if let command = arguments.first, CLI.commands.contains(command) {
        // Headless mode for scripts and tests: no menu bar icon, no windows.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let code = await CLI.run(arguments)
            exit(code)
        }
        dispatchMain()
    } else {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
