import AppKit
import ServiceManagement

/// "Open at login", through the system's login item service.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    /// Why the last change didn't work, in words the user can act on.
    @Published private(set) var message: String?

    private let service = SMAppService.mainApp

    init() { status = service.status }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    /// True when Clover runs from an Applications folder, where login items are reliable.
    var isInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let folders = NSSearchPathForDirectoriesInDomains(.applicationDirectory, [.localDomainMask, .userDomainMask], true)
        return folders.contains { path.hasPrefix($0 + "/") }
    }

    /// Reads the system's state again. Call it when the app comes to the front, because the
    /// user may have changed the setting in System Settings.
    func refresh() {
        status = service.status
        if status == .enabled { message = nil }
    }

    func setEnabled(_ on: Bool) {
        message = nil
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            message = failureMessage(error, enabling: on)
        }
        status = service.status
        if on, status == .requiresApproval {
            message = "macOS needs your approval. Turn Clover on in System Settings, under General, Login Items."
        }
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func failureMessage(_ error: Error, enabling: Bool) -> String {
        let action = enabling ? "turn on" : "turn off"
        var text = "Couldn't \(action) Open at login."
        if !isInApplications {
            text += " Move Clover to your Applications folder, open it from there, and try again."
        }
        let detail = error.localizedDescription
        if !detail.isEmpty { text += " (\(detail))" }
        return text
    }
}
