import AppKit
import SwiftUI
import CloverCore

/// A line of explanation under a setting.
private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The General tab: trigger key, open at login, and where converted files go.
struct GeneralSettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var login: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                Picker("Trigger key", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.segmented)
                Hint("Hold this key while you drag a file to open Clover's ring of formats.")
            }

            Section {
                Toggle("Open at login", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                if let message = login.message {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            if login.needsApproval {
                                Button("Open Login Items…") { login.openLoginItemsSettings() }
                            }
                        }
                    }
                } else if !login.isInApplications {
                    Hint("Clover is running from outside an Applications folder. Move it there for Open at login to work reliably.")
                }
            }

            Section {
                LabeledContent("Save converted files") {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(locationText)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(settings.outputFolder?.path ?? "Next to each original file")
                        HStack {
                            Button("Choose Folder…", action: chooseFolder)
                            Button("Reset") { settings.outputFolder = nil }
                                .disabled(settings.outputFolder == nil)
                        }
                    }
                }
                Hint("Converted files never replace the original.")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }

    private var locationText: String {
        guard let folder = settings.outputFolder else { return "Beside the original" }
        return (folder.path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Clover saves converted files."
        panel.directoryURL = settings.outputFolder
        let apply: (NSApplication.ModalResponse) -> Void = { [settings] response in
            if response == .OK, let url = panel.url { settings.outputFolder = url }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }
}

/// The Engines tab: where each command-line tool was found, or how to install it.
struct EnginesSettingsRoot: View {
    @ObservedObject var model: AppModel

    var body: some View {
        EnginesSettingsView(engines: EngineInfo.list(from: model.tools), refresh: model.refreshTools)
    }
}

struct EnginesSettingsView: View {
    let engines: [EngineInfo]
    let refresh: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(engines) { engine in
                    EngineDetail(engine: engine)
                }
                Hint("Images, PDFs, documents and archives need no extra tools. Clover looks in /opt/homebrew/bin, /usr/local/bin and /opt/local/bin, then your PATH.")
            }
            Section {
                Button("Refresh", action: refresh)
            }
        }
        .formStyle(.grouped)
    }
}

private struct EngineDetail: View {
    let engine: EngineInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: engine.found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(engine.found ? Color.secondary : Color.orange)
                    .accessibilityLabel(engine.found ? "Found" : "Not installed")
                Text(engine.name).font(.headline)
                Text(engine.purpose).foregroundStyle(.secondary)
                Spacer()
            }
            if let path = engine.path {
                Text(path.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                HStack(spacing: 4) {
                    Text("Not installed. In Terminal, run")
                        .foregroundStyle(.secondary)
                    Text(engine.install)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    CopyButton(text: engine.install)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The About tab.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© 2026 Irfan Abdul Hameed"
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text("Clover").font(.system(size: 22, weight: .semibold))
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("Drag a file, hold a key, drop it on a format.")
                .font(.callout)
                .padding(.top, 8)
            Text("Everything happens on this Mac. Nothing is uploaded.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(copyright).font(.caption).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }
}
