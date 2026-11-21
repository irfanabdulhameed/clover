import SwiftUI

/// The engines: where each command-line tool was found, or how to install it. Two form
/// sections, shown in General.
struct EngineSections: View {
    let engines: [EngineInfo]
    let refresh: () -> Void

    private var summary: String {
        let missing = engines.filter { !$0.found }.count
        switch missing {
        case 0: return "Every engine was found."
        case 1: return "One engine is missing. Install it to unlock what it does."
        default: return "\(missing) engines are missing. Install them to unlock what they do."
        }
    }

    var body: some View {
        Section {
            ForEach(engines) { engine in
                EngineDetail(engine: engine)
            }
            LabeledContent {
                Button("Refresh", action: refresh)
                    .help("Look for the engines again")
            } label: {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Engines")
        } footer: {
            FormFooter("Images, PDFs, documents and archives need no extra tools. Clover looks in /opt/homebrew/bin, /usr/local/bin and /opt/local/bin, then your PATH.")
        }
    }
}

private struct EngineDetail: View {
    let engine: EngineInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: engine.found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(engine.found ? Color.green : Color.orange)
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
