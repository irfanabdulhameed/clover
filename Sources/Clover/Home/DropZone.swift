import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The dashed target at the top of Home. Drop files on it, or click it to choose files.
struct DropZone: View {
    var forceTargeted = false
    let onChoose: () -> Void
    let onDrop: ([URL]) -> Void
    @State private var dragTargeted = false
    @State private var hovered = false

    private var targeted: Bool { dragTargeted || forceTargeted }

    var body: some View {
        Button(action: onChoose) {
            VStack(spacing: 6) {
                CloverShape()
                    .fill(targeted ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
                Text(targeted ? "Drop to choose a format" : "Drop files to convert")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(targeted ? Color.accentColor : Color.primary)
                Text(targeted ? " " : "or click to choose")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
        }
        .buttonStyle(DropZoneStyle(targeted: targeted, hovered: hovered))
        .onHover { hovered = $0 }
        .onDrop(of: [UTType.fileURL], isTargeted: $dragTargeted) { providers in
            DroppedFiles.load(from: providers, completion: onDrop)
            return true
        }
        .accessibilityLabel("Drop files to convert")
        .accessibilityHint("Choose files to convert")
    }
}

private struct DropZoneStyle: ButtonStyle {
    let targeted: Bool
    let hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .background(
                shape.fill(targeted ? Color.accentColor.opacity(0.14) : Color.primary.opacity(configuration.isPressed ? 0.11 : hovered ? 0.07 : 0.04))
            )
            .overlay(
                shape.strokeBorder(
                    targeted ? Color.accentColor : Color.primary.opacity(0.25),
                    style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: targeted ? [] : [5, 4])
                )
            )
            .contentShape(shape)
    }
}

/// Reads file URLs from dropped item providers, in the order they were dropped.
enum DroppedFiles {
    private final class Slots: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL?]
        init(count: Int) { urls = Array(repeating: nil, count: count) }
        func set(_ url: URL?, at index: Int) { lock.lock(); urls[index] = url; lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls.compactMap { $0 } }
    }

    static func load(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let slots = Slots(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                }
                slots.set(url?.isFileURL == true ? url : nil, at: index)
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = slots.all
            if !urls.isEmpty { completion(urls) }
        }
    }
}
