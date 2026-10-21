import AppKit
import SwiftUI
import CloverCore

/// The parts of a job the result chip shows, copied out so fakes can be drawn too.
struct JobSnapshot {
    enum Phase: Equatable {
        case running
        case done
        case failed(String)
        case cancelled
        case undone
    }

    var phase: Phase
    /// "Convert to JPG", "Merge", "Extract".
    var title: String
    /// "JPG", the format being made.
    var formatName: String
    var family: Family
    var inputNames: [String]
    var outputNames: [String]
    var finished: Int
    var total: Int
    var failures: [(file: String, message: String)]
    var skipped: Int
    var bytesIn: Int64
    var bytesOut: Int64
    var progress: Double

    @MainActor
    init(_ job: ConversionJob) {
        switch job.state {
        case .running: phase = .running
        case .done: phase = .done
        case .failed(let message): phase = .failed(message)
        case .cancelled: phase = .cancelled
        case .undone: phase = .undone
        }
        title = job.title
        formatName = job.request.target.format.name
        family = job.request.target.format.family
        inputNames = job.request.inputs.map(\.lastPathComponent)
        outputNames = job.outputs.map(\.lastPathComponent)
        finished = job.finished
        total = job.total
        failures = job.failures
        skipped = job.skipped
        bytesIn = job.bytesIn
        bytesOut = job.bytesOut
        progress = job.progress
    }

    init(phase: Phase, title: String, formatName: String, family: Family, inputNames: [String],
         outputNames: [String] = [], finished: Int = 0, total: Int = 1, failures: [(file: String, message: String)] = [],
         skipped: Int = 0, bytesIn: Int64 = 0, bytesOut: Int64 = 0, progress: Double = 0) {
        self.phase = phase
        self.title = title
        self.formatName = formatName
        self.family = family
        self.inputNames = inputNames
        self.outputNames = outputNames
        self.finished = finished
        self.total = total
        self.failures = failures
        self.skipped = skipped
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.progress = progress
    }
}

/// What the chip says in each state.
struct ChipDisplay: Equatable {
    enum Kind: Equatable {
        case running, done, partial, failed, skipped, cancelled, undone
    }

    var kind: Kind
    var title: String
    var subtitle: String
    var progress: Double
    var family: Family
    /// Every failed file and why, for the tooltip.
    var details = ""

    var canCancel: Bool { kind == .running }
    var canUndo: Bool { kind == .done || kind == .partial }
    var isFinished: Bool { kind != .running }

    init(kind: Kind, title: String, subtitle: String, progress: Double = 1, family: Family) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.family = family
    }

    init(_ s: JobSnapshot) {
        family = s.family
        progress = s.progress
        details = s.failures.map { $0.file.isEmpty ? $0.message : "\($0.file): \($0.message)" }.joined(separator: "\n")
        switch s.phase {
        case .running:
            kind = .running
            title = s.title
            subtitle = s.total > 1 ? "\(s.finished) of \(s.total)" : (s.inputNames.first ?? "")

        case .done where !s.failures.isEmpty:
            kind = .partial
            let converted = max(s.finished - s.failures.count - s.skipped, s.outputNames.isEmpty ? 0 : 1)
            title = "\(converted) converted · \(s.failures.count) failed"
            subtitle = s.failures[0].message

        case .done:
            kind = .done
            let first = s.outputNames.first ?? s.formatName
            title = s.outputNames.count > 1 ? "\(first) and \(s.outputNames.count - 1) more" : first
            var parts = [ChipDisplay.sizeChange(from: s.bytesIn, to: s.bytesOut)].compactMap { $0 }
            if s.skipped > 0 { parts.append("\(s.skipped) already \(s.formatName)") }
            subtitle = parts.joined(separator: " · ")

        case .failed(let message) where s.skipped > 0 && s.failures.isEmpty:
            kind = .skipped
            title = "Already \(s.formatName)"
            subtitle = s.total > 1 || s.inputNames.count > 1
                ? "\(s.skipped) files left as they are"
                : (s.inputNames.first ?? message)

        case .failed(let message):
            kind = .failed
            title = ChipDisplay.couldNot(s.title)
            subtitle = s.failures.count > 1 ? "\(s.failures.count) files failed. \(message)" : message

        case .cancelled:
            kind = .cancelled
            title = "Cancelled"
            subtitle = s.title

        case .undone:
            kind = .undone
            title = "Undone"
            subtitle = s.outputNames.count == 1 ? "\(s.outputNames[0]) moved to the Trash" : "\(s.outputNames.count) files moved to the Trash"
        }
    }

    /// "1.2 MB · 64 % smaller", "3.1 MB · 18 % larger", "2.4 MB · same size".
    static func sizeChange(from bytesIn: Int64, to bytesOut: Int64) -> String? {
        guard bytesOut > 0 else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: bytesOut, countStyle: .file)
        guard bytesIn > 0 else { return size }
        let ratio = Double(bytesOut) / Double(bytesIn)
        let change: String
        if ratio < 0.995 {
            change = "\(Int(((1 - ratio) * 100).rounded())) % smaller"
        } else if ratio <= 1.005 {
            change = "same size"
        } else if ratio < 2 {
            change = "\(Int(((ratio - 1) * 100).rounded())) % larger"
        } else {
            change = String(format: "%.1f× larger", ratio)
        }
        return "\(size) · \(change)"
    }

    /// "Convert to JPG" → "Couldn't convert to JPG"; "Merge" → "Couldn't merge".
    static func couldNot(_ title: String) -> String {
        guard let first = title.first else { return "Couldn't convert" }
        return "Couldn't " + first.lowercased() + title.dropFirst()
    }
}

/// What the chip shows, updated by its controller.
@MainActor
final class ResultChipState: ObservableObject {
    @Published var display: ChipDisplay
    @Published var thumbnail: NSImage?
    @Published var outputs: [URL] = []

    init(display: ChipDisplay) { self.display = display }
}

/// What the chip's buttons and body do.
struct ChipActions {
    var cancel: () -> Void = {}
    var undo: () -> Void = {}
    var dismiss: () -> Void = {}
    var reveal: () -> Void = {}
}

/// The result chip: progress while running, then the result.
struct ResultChipView: View {
    @ObservedObject var state: ResultChipState
    let actions: ChipActions

    static let size = CGSize(width: 300, height: 56)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.bloomSnapshot) private var snapshot

    var body: some View {
        let d = state.display
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                leading(d)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(d.subtitle)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(d.details)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay {
                if !snapshot && d.isFinished && !state.outputs.isEmpty && d.kind != .undone {
                    DragOutArea(urls: state.outputs, image: state.thumbnail, onClick: actions.reveal)
                }
            }
            trailing(d)
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(width: ResultChipView.size.width, height: ResultChipView.size.height)
        .background(Glass(cornerRadius: 16, bright: true))
    }

    @ViewBuilder
    private func leading(_ d: ChipDisplay) -> some View {
        let hue = BloomStyle.hue(d.family, scheme)
        switch d.kind {
        case .running:
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.001, min(d.progress, 1)))
                    .stroke(hue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: BloomStyle.symbol(for: d.family))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hue)
            }
            .padding(3)
        case .done, .partial:
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = state.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                        .frame(width: 36, height: 36)
                } else {
                    RoundedRectangle(cornerRadius: 7).fill(hue.opacity(0.14))
                        .overlay(Image(systemName: BloomStyle.symbol(for: d.family)).foregroundStyle(hue))
                }
                badge(d.kind == .done ? "checkmark" : "exclamationmark",
                      color: d.kind == .done ? BloomStyle.green(scheme) : BloomStyle.hue(.image, scheme))
                    .offset(x: 4, y: 4)
            }
        case .failed:
            symbolDisc("exclamationmark", color: BloomStyle.failure(scheme))
        case .skipped:
            symbolDisc("checkmark", color: .secondary)
        case .cancelled:
            symbolDisc("xmark", color: .secondary)
        case .undone:
            symbolDisc("trash", color: .secondary)
        }
    }

    @ViewBuilder
    private func trailing(_ d: ChipDisplay) -> some View {
        HStack(spacing: 4) {
            if d.canUndo {
                Button("Undo", action: actions.undo)
                    .buttonStyle(ChipTextButtonStyle())
                    .help("Move the result to the Trash (⌘Z)")
            }
            if d.canCancel {
                Button(action: actions.cancel) { Image(systemName: "xmark") }
                    .buttonStyle(ChipIconButtonStyle())
                    .help("Cancel")
                    .accessibilityLabel("Cancel")
            } else {
                Button(action: actions.dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(ChipIconButtonStyle())
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
            }
        }
    }

    private func badge(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.25))
    }

    private func symbolDisc(_ symbol: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.14))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(2)
    }
}

/// A round icon button: resting, hovered, pressed.
struct ChipIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.18 : (hovering ? 0.10 : 0.05))))
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}

/// A small capsule text button: resting, hovered, pressed.
struct ChipTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.20 : (hovering ? 0.13 : 0.07))))
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

/// The chip's body: a click shows the files in Finder, a drag takes them out.
struct DragOutArea: NSViewRepresentable {
    var urls: [URL]
    var image: NSImage?
    var onClick: () -> Void

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) {
        view.urls = urls
        view.image = image
        view.onClick = onClick
    }
}

final class DragOutView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var image: NSImage?
    var onClick: () -> Void = {}
    private var downPoint: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !urls.isEmpty else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        downPoint = nil
        let origin = convert(start, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let picture = (index == 0 ? image : nil) ?? Thumbnails.icon(for: url)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(NSRect(x: origin.x - 18 + offset, y: origin.y - 18 - offset, width: 36, height: 36),
                                  contents: picture)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if downPoint != nil { onClick() }
        downPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic] : .copy
    }
}
