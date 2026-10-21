import SwiftUI

/// The engines list at the bottom of Home: each tool is found (a check mark) or missing
/// (with the command that installs it, and a copy button).
struct EnginesSection: View {
    let engines: [EngineInfo]
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Engines")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HoverButton(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .help("Look for the engines again")
                .accessibilityLabel("Refresh engines")
            }
            ForEach(engines) { engine in
                EngineLine(engine: engine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct EngineLine: View {
    let engine: EngineInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: engine.found ? "checkmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(engine.found ? Color.secondary : Color.orange)
                .frame(width: 14)
                .padding(.trailing, 2)
                .accessibilityLabel(engine.found ? "Found" : "Not installed")
            Text(engine.name)
                .font(.system(size: 12, weight: .medium))
            if engine.found {
                Spacer()
            } else {
                Text("not installed ·")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(engine.install)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                CopyButton(text: engine.install)
            }
        }
        .frame(height: 22)
    }
}
