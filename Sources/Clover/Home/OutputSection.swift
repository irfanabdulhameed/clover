import AppKit
import SwiftUI
import CloverCore

/// Output: where converted files go, what they are called, and what happens after.
struct OutputSection: View {
    @Binding var conversion: ConversionSettings
    @Binding var outputFolder: URL?
    @Binding var revealAfterConverting: Bool
    let login: LoginState
    let actions: DashboardActions

    private enum Place: Hashable { case besideOriginal, folder }

    private static let tokens = ["{name}", "{format}", "{option}"]
    private static let defaultPattern = ConversionSettings().namePattern

    var body: some View {
        Form {
            whereSection
            nameSection
            conflictSection
            afterSection
            startupSection
        }
        .formStyle(.grouped)
    }

    // MARK: Where files go

    private var placeBinding: Binding<Place> {
        Binding(
            get: { outputFolder == nil ? .besideOriginal : .folder },
            set: { place in
                switch place {
                case .besideOriginal: outputFolder = nil
                case .folder: if outputFolder == nil { chooseFolder() }
                }
            })
    }

    private var whereSection: some View {
        Section {
            Picker("Save to", selection: placeBinding) {
                Text("Beside the original").tag(Place.besideOriginal)
                Text("A folder").tag(Place.folder)
            }
            .pickerStyle(.radioGroup)

            if let folder = outputFolder {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text((folder.path as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder.path)
                        Button("Choose…", action: chooseFolder)
                        Button("Reset") { outputFolder = nil }
                            .help("Save next to each original again")
                    }
                }
            }
        } header: {
            Text("Where files go")
        } footer: {
            FormFooter(outputFolder == nil
                 ? "Each converted file is saved in the same folder as the file it came from."
                 : "Every converted file is saved in this folder.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Clover saves converted files."
        panel.directoryURL = outputFolder
        let apply: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { outputFolder = url }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }

    // MARK: Names

    private var example: String {
        conversion.name(base: "IMG_0042", format: "JPG", option: "Small") + ".jpg"
    }

    private var nameSection: some View {
        Section {
            LabeledContent("Name") {
                HStack(spacing: 8) {
                    TextField("Name", text: $conversion.namePattern)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .font(.system(size: 12, design: .monospaced))
                        .labelsHidden()
                        .frame(maxWidth: 280)
                        .accessibilityLabel("Name pattern")
                    Button("Reset") { conversion.namePattern = Self.defaultPattern }
                        .disabled(conversion.namePattern == Self.defaultPattern)
                }
            }
            LabeledContent("Add") {
                HStack(spacing: 6) {
                    ForEach(Self.tokens, id: \.self) { token in
                        Button {
                            insert(token)
                        } label: {
                            Text(token).font(.system(size: 11, design: .monospaced))
                        }
                        .controlSize(.small)
                        .help("Add \(token) to the name")
                    }
                }
            }
            LabeledContent("Example") {
                Text(example)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("Example: \(example)")
            }
        } header: {
            Text("File names")
        } footer: {
            FormFooter("{name} is the original name, {format} the new format and {option} the quality choice, such as Small. The extension is added for you.")
        }
    }

    /// Puts a token where the cursor is. When the field isn't being edited, it goes on the end.
    private func insert(_ token: String) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
            editor.insertText(token, replacementRange: editor.selectedRange())
        } else {
            conversion.namePattern += token
        }
    }

    // MARK: Name taken

    private var conflictSection: some View {
        Section {
            Picker("Use", selection: $conversion.onConflict) {
                Text("Add a number").tag(ConflictPolicy.addNumber)
                Text("Replace the older file").tag(ConflictPolicy.replace)
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("If the name is taken")
        } footer: {
            FormFooter(conversion.onConflict == .addNumber
                 ? "The new file becomes IMG_0042 2.jpg, the way Finder does it. The original is never replaced."
                 : "The older converted file goes to the Trash and the new one takes its name. The original is never replaced.")
        }
    }

    // MARK: After converting

    private var afterSection: some View {
        Section {
            Toggle("Show in Finder after converting", isOn: $revealAfterConverting)
        } header: {
            Text("After converting")
        } footer: {
            FormFooter("Opens the folder with the new files selected.")
        }
    }

    // MARK: Startup

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
