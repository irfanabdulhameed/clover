import AppKit
import SwiftUI
import CloverCore

extension TriggerKey {
    /// "⇧", "⌥" or "⌃".
    var symbol: String {
        switch self {
        case .shift: "⇧"
        case .option: "⌥"
        case .control: "⌃"
        }
    }
}

/// One command-line engine, for the lists in Home and the Dashboard.
struct EngineInfo: Identifiable, Equatable {
    let name: String
    let path: URL?
    let install: String

    var id: String { name }
    var found: Bool { path != nil }

    /// What the engine is for.
    var purpose: String {
        switch name {
        case "ffmpeg": "Video and audio"
        case "cwebp": "WebP images"
        default: ""
        }
    }

    static func list(from tools: Tools) -> [EngineInfo] {
        tools.status.map { EngineInfo(name: $0.name, path: $0.path, install: $0.install) }
    }
}

/// A borderless button that gets a soft highlight on hover and a stronger one while pressed.
struct HoverButtonStyle: ButtonStyle {
    var hovered: Bool
    var cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hovered ? 0.07 : 0))
            )
            .contentShape(Rectangle())
    }
}

/// A plain button with `HoverButtonStyle`.
struct HoverButton<Label: View>: View {
    var shortcut: KeyboardShortcut?
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(HoverButtonStyle(hovered: hovered))
            .keyboardShortcut(shortcut)
            .onHover { hovered = $0 }
    }
}

/// Copies `text`, then shows a check mark for a moment.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HoverButton(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .help(copied ? "Copied" : "Copy \"\(text)\"")
        .accessibilityLabel(copied ? "Copied" : "Copy command")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
