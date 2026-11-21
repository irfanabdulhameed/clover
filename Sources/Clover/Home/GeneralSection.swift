import SwiftUI

/// General: how Clover moves, feels and sounds, starting at login, updates, and the
/// command-line engines it uses.
struct GeneralSection: View {
    @Binding var motion: MotionPreference
    @Binding var haptics: Bool
    @Binding var completionSound: Bool
    let login: LoginState
    let engines: [EngineInfo]
    let actions: DashboardActions

    var body: some View {
        Form {
            Section {
                Picker("Motion", selection: $motion) {
                    ForEach(MotionPreference.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Haptic taps", isOn: $haptics)
                Toggle("Finish sound", isOn: $completionSound)
                LabeledContent("Preview sound") {
                    Button("Play") { ChipFeedback.playFinishSound(force: true) }
                        .help("Hear the finish sound")
                }
            } header: {
                Text("Feel")
            } footer: {
                FormFooter("Reduced uses fades only; Follow the system uses Reduce motion in System Settings. Haptic taps come on the trackpad when a leaf lights, when you drop and when a conversion finishes. The finish sound plays once per conversion, however many files it holds.")
            }

            startupSection

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Updates") {
                    Button("Check for Updates", action: actions.checkForUpdates)
                        .help("Ask GitHub whether a newer Clover is out")
                }
            } header: {
                Text("Updates")
            } footer: {
                FormFooter("Clover looks for a new version on Wi-Fi or Ethernet and shows what changed before it installs anything.")
            }

            EngineSections(engines: engines, refresh: actions.refreshTools)
        }
        .formStyle(.grouped)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        return (info?["CFBundleVersion"] as? String).map { "\(short) (\($0))" } ?? short
    }

    private var startupSection: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { login.isEnabled }, set: actions.setLaunchAtLogin))
            if let message = login.message {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        if login.needsApproval {
                            Button("Open Login Items…", action: actions.openLoginItems)
                        }
                    }
                }
            } else if !login.inApplications {
                Hint("Clover is running from outside an Applications folder. Move it there for Open at login to work reliably.")
            }
        } header: {
            Text("Startup")
        }
    }
}
