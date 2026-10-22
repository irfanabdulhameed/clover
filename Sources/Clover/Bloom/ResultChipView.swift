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
    /// "Convert to JPG" while it runs: "Converting to JPG…".
    static func inProgress(_ title: String) -> String {
        let convert = "Convert to "
        if title.hasPrefix(convert) { return "Converting to \(title.dropFirst(convert.count))…" }
        switch title {
        case "Merge": return "Merging…"
        case "Extract": return "Extracting…"
        case "Compress": return "Compressing…"
        default: return title + "…"
        }
    }

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
            title = ChipDisplay.inProgress(s.title)
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
    /// What the job says now.
    @Published var display: ChipDisplay
    /// What the job said while it ran. The chip keeps showing it until the result flips in.
    @Published var running: ChipDisplay
    @Published var thumbnail: NSImage?
    @Published var outputs: [URL] = []
    /// True for a moment after Copy: its button shows a checkmark.
    @Published var copied = false
    /// How many times Copy was pressed, so each press pops the checkmark.
    @Published var copies = 0

    init(display: ChipDisplay) {
        self.display = display
        running = display
    }
}

/// What the chip's buttons and body do.
struct ChipActions {
    var cancel: () -> Void = {}
    var undo: () -> Void = {}
    /// Puts the result's files on the clipboard.
    var copy: () -> Void = {}
    var dismiss: () -> Void = {}
    var reveal: () -> Void = {}
    /// The pointer came in or went out.
    var hover: (Bool) -> Void = { _ in }
    /// The chip was clicked, so ⌘Z and Esc are about it.
    var focus: () -> Void = {}
}

/// The result chip: progress while running, then the result.
///
/// `values` says how far along its motion the chip is (see `ChipPlayback`); the default is
/// the chip at rest, which is what the debug sheets draw. `clover` tints the glass with the
/// clover's green, as the leaves are, or leaves it clear.
struct ResultChipView: View {
    @ObservedObject var state: ResultChipState
    let actions: ChipActions
    var values = ChipValues.rest
    var clover = false

    static let size = ChipMotion.chipSize
    /// Space at each end of the chip, between the ring and the words, and before the buttons.
    static let padding: CGFloat = 14
    static let slotGap: CGFloat = 12
    static let buttonsGap: CGFloat = 14
    /// A round button's side, and the space between buttons.
    static let buttonSide: CGFloat = 26
    static let buttonSpacing: CGFloat = 8
    static let undoFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let undoPadding: CGFloat = 12

    /// The width left for a finished chip's name and size, beside Undo, Copy and ✕.
    static var titleRoom: CGFloat {
        let undo = BloomStyle.textWidth("Undo", font: undoFont) + undoPadding * 2
        let buttons = undo + buttonSpacing + buttonSide + buttonSpacing + buttonSide
        return size.width - padding * 2 - ChipMotion.slot - slotGap - buttonsGap - buttons
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.bloomSnapshot) private var snapshot

    var body: some View {
        let v = values
        let d = v.showsRunning ? state.running : state.display
        // A pill, from the moment it leaves the ring: half its height, or half its width
        // while it is narrower. Whole points, so the blur's mask is made only a few times.
        let corner = min(ResultChipView.size.height / 2, (v.width / 2).rounded())
        let shape = RoundedRectangle(cornerRadius: corner, style: .circular)
        ZStack {
            if let age = v.ripple {
                ChipRipple(age: age, width: v.width, color: BloomStyle.green(scheme))
            }
            content(d, v)
                .frame(width: ResultChipView.size.width, height: ResultChipView.size.height, alignment: .leading)
                .frame(width: v.width, height: ResultChipView.size.height, alignment: .leading)
                .clipShape(shape)
                .modifier(ChipGlassModifier(cornerRadius: corner, clover: clover))
                .background {
                    if !snapshot { ChipHoverTracker(onChange: actions.hover) }
                }
        }
        .frame(width: ResultChipView.size.width, height: ResultChipView.size.height)
        .scaleEffect(v.scale)
        .blur(radius: v.blur)
        .opacity(v.opacity)
        .offset(v.offset)
        .allowsHitTesting(!v.isHidden && v.isFullSize && v.opacity > 0.9)
    }

    private func content(_ d: ChipDisplay, _ v: ChipValues) -> some View {
        HStack(spacing: ResultChipView.buttonsGap) {
            HStack(spacing: ResultChipView.slotGap) {
                leading(d, v)
                    .frame(width: ChipMotion.slot, height: ChipMotion.slot)
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(d.subtitle)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(d.details)
                }
                .opacity(v.textOpacity)
                .blur(radius: v.textBlur)
                .scaleEffect(v.textScale, anchor: .leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay {
                if !snapshot && d.isFinished && !state.outputs.isEmpty && d.kind != .undone && v.isFullSize {
                    DragOutArea(urls: state.outputs, image: state.thumbnail, onClick: actions.reveal, onPress: actions.focus)
                }
            }
            trailing(d, v)
                .opacity(v.controlsOpacity)
        }
        .padding(.horizontal, ResultChipView.padding)
    }

    @ViewBuilder
    private func leading(_ d: ChipDisplay, _ v: ChipValues) -> some View {
        let hue = BloomStyle.hue(d.family, scheme)
        switch d.kind {
        case .running:
            // The ring the clover left at its hub. Until there is progress to show, the
            // Mac's own spinner turns inside it; then the kind of file sits in the ring.
            let progress = v.ringProgress ?? d.progress
            ZStack {
                ChipRing(progress: progress, diameter: v.ringDiameter)
                if progress < 0.03 && !snapshot {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: BloomStyle.symbol(for: d.family))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(hue)
                        .opacity(v.textOpacity)
                        .blur(radius: v.textBlur)
                }
            }
        case .done, .partial:
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = state.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .frame(width: 40, height: 40)
                } else {
                    RoundedRectangle(cornerRadius: 7).fill(hue.opacity(0.14))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: BloomStyle.symbol(for: d.family)).foregroundStyle(hue))
                        .frame(width: 40, height: 40)
                }
                badge(d.kind == .done ? "checkmark" : "exclamationmark",
                      color: d.kind == .done ? BloomStyle.green(scheme) : BloomStyle.hue(.image, scheme))
                    .offset(x: 2, y: 4)
            }
            .scaleEffect(v.pop)
        case .failed:
            symbolDisc("exclamationmark", color: BloomStyle.failure(scheme)).scaleEffect(v.pop)
        case .skipped:
            symbolDisc("checkmark", color: .secondary).scaleEffect(v.pop)
        case .cancelled:
            symbolDisc("xmark", color: .secondary).scaleEffect(v.pop)
        case .undone:
            symbolDisc("trash", color: .secondary)
        }
    }

    @ViewBuilder
    private func trailing(_ d: ChipDisplay, _ v: ChipValues) -> some View {
        HStack(spacing: ResultChipView.buttonSpacing) {
            if d.canUndo {
                Button("Undo") { actions.focus(); actions.undo() }
                    .buttonStyle(ChipTextButtonStyle())
                    .help("Move the result to the Trash (⌘Z)")
            }
            if d.canUndo && !state.outputs.isEmpty {
                // Copies the files, to paste in Finder, Mail or a chat. A checkmark answers
                // for a moment: a one-frame flip and a small pop, as every state change.
                Button { actions.focus(); actions.copy() } label: {
                    CopyGlyph(copied: state.copied, copies: state.copies, reduced: v.reduced)
                }
                .buttonStyle(ChipIconButtonStyle())
                .help(state.copied ? "Copied" : (state.outputs.count > 1 ? "Copy the files" : "Copy the file"))
                .accessibilityLabel(state.copied ? "Copied" : "Copy")
            }
            if d.canCancel {
                Button { actions.focus(); actions.cancel() } label: { Image(systemName: "xmark") }
                    .buttonStyle(ChipIconButtonStyle())
                    .help("Cancel")
                    .accessibilityLabel("Cancel")
            } else {
                Button { actions.focus(); actions.dismiss() } label: { Image(systemName: "xmark") }
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
        .frame(width: 36, height: 36)
    }
}

/// Reports the pointer coming and going over the chip, even while Clover is not the front
/// app. It lets every click through.
struct ChipHoverTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onChange = onChange
    }

    final class TrackerView: NSView {
        var onChange: (Bool) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
    }
}

/// The Copy button's icon: two sheets, or a green checkmark for a moment after a copy. The
/// checkmark comes in one frame at 108 % and settles, like the chip's own result.
struct CopyGlyph: View {
    let copied: Bool
    let copies: Int
    var reduced = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if copied {
                Image(systemName: "checkmark").foregroundStyle(BloomStyle.green(scheme))
            } else {
                Image(systemName: "doc.on.doc")
            }
        }
        .keyframeAnimator(initialValue: CGFloat(1), trigger: copies) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(reduced ? 1 : ChipMotion.popScale)
                LinearKeyframe(1, duration: ChipMotion.popDuration,
                               timingCurve: .bezier(startControlPoint: UnitPoint(x: 0.16, y: 1),
                                                    endControlPoint: UnitPoint(x: 0.3, y: 1)))
            }
        }
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: ResultChipView.buttonSide, height: ResultChipView.buttonSide)
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
                .font(Font(ResultChipView.undoFont))
                .foregroundStyle(.primary)
                .padding(.horizontal, ResultChipView.undoPadding)
                .frame(height: ResultChipView.buttonSide)
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
    var onPress: () -> Void = {}

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) {
        view.urls = urls
        view.image = image
        view.onClick = onClick
        view.onPress = onPress
    }
}

final class DragOutView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var image: NSImage?
    var onClick: () -> Void = {}
    var onPress: () -> Void = {}
    private var downPoint: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        onPress()
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
