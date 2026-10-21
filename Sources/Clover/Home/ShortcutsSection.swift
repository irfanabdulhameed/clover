import SwiftUI

/// Shortcuts: the drag key, hold to open, and the keyboard shortcut.
struct ShortcutsSection: View {
    @Binding var triggerKey: TriggerKey
    @Binding var holdToOpen: Bool
    @Binding var hotkey: Hotkey?
    var forceRecording = false
    var forceRejected = false
    @State private var isRecording = false
    @State private var wasRejected = false

    private var showsRejection: Bool { (wasRejected && isRecording) || forceRejected }

    var body: some View {
        Form {
            Section {
                Picker("Trigger key", selection: $triggerKey) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Drag")
            } footer: {
                FormFooter("Hold this key while you drag a file to open the clover.")
            }

            Section {
                Toggle("Hold a file and press \(triggerKey.symbol) to open the clover", isOn: $holdToOpen)
            } header: {
                Text("Hold")
            } footer: {
                FormFooter("Press and hold on a file in Finder, then press \(triggerKey.symbol).")
            }

            Section {
                LabeledContent("Shortcut") {
                    HStack(spacing: 8) {
                        HotkeyRecorder(hotkey: $hotkey, isRecording: $isRecording, wasRejected: $wasRejected,
                                       forceRecording: forceRecording)
                        Button("Reset") { hotkey = .standard }
                            .disabled(hotkey == .standard)
                            .help("Go back to \(Hotkey.standard.display)")
                    }
                }
            } header: {
                Text("Keyboard")
            } footer: {
                FormFooter(recorderHint, tint: showsRejection ? .orange : nil)
            }

            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("The first time, macOS asks to let Clover control Finder. That's how it knows which files are selected.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// What the shortcut line says right now.
    private var recorderHint: String {
        if isRecording || forceRecording {
            return showsRejection
                ? "That needs ⌘, ⌃ or ⌥ as well. Esc cancels, Delete turns the shortcut off."
                : "Press the shortcut you want, with ⌘, ⌃ or ⌥. Esc cancels, Delete turns it off."
        }
        if let hotkey {
            return "Select files in Finder, then press \(hotkey.display) to open the clover for them."
        }
        return "The shortcut is off. Click it and type one to turn it on."
    }
}
