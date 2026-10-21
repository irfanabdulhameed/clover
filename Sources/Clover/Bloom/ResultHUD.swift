import AppKit
import Combine
import SwiftUI
import CloverCore

/// The small chip that shows a job's progress and result.
///
/// It appears where the bloom was, or at the top right under the menu bar, and
/// several jobs stack in a column. It never takes focus by itself: it becomes key
/// only when clicked, so ⌘Z and Esc work then.
@MainActor
final class ResultHUD {
    private let model: AppModel
    private var chips: [ResultChip] = []
    /// Top-centre of the first chip in the column.
    private var origin: NSPoint?
    private var screen: NSScreen?
    /// Older finished chips give way beyond this many.
    private let limit = 6

    init(model: AppModel) { self.model = model }

    func show(_ job: ConversionJob) {
        let anchor = BloomAnchor.take()
        if chips.isEmpty || origin == nil || screen == nil {
            let screen = BloomController.screen(containing: anchor ?? NSEvent.mouseLocation)
            self.screen = screen
            let size = ResultChipView.size
            origin = anchor.map { NSPoint(x: $0.x, y: $0.y + size.height / 2) }
                ?? ChipStackLayout.cornerOrigin(size: size, visible: screen.visibleFrame)
        }
        if chips.count >= limit, let old = chips.first(where: { $0.job.isFinished }) {
            remove(old)
        }
        let chip = ResultChip(job: job, service: model.service, hud: self)
        chips.append(chip)
        layout()
        chip.panel.orderFrontRegardless()
    }

    func remove(_ chip: ResultChip) {
        chip.close()
        chips.removeAll { $0 === chip }
        if chips.isEmpty {
            origin = nil
            screen = nil
        }
        layout()
    }

    private func layout() {
        guard let origin, let screen else { return }
        let frames = ChipStackLayout.frames(count: chips.count, size: ResultChipView.size, origin: origin,
                                            visible: screen.visibleFrame)
        for (chip, frame) in zip(chips, frames) {
            chip.panel.setFrame(frame.insetBy(dx: -ChipPanel.margin, dy: -ChipPanel.margin), display: true)
        }
    }
}

/// One job's chip: its window, what it shows and when it goes.
@MainActor
final class ResultChip {
    let job: ConversionJob
    let panel: ChipPanel
    private let state: ResultChipState
    private let service: ConversionService
    private weak var hud: ResultHUD?
    private var observer: AnyCancellable?
    private var hideWork: DispatchWorkItem?
    private var lastKind: ChipDisplay.Kind?
    private var hovering = false
    private var hideWhenLeft = false
    private var thumbnailFor: URL?
    private var undoError: String?

    /// How long a finished chip stays.
    static let stay: TimeInterval = 5
    /// How long it stays after the pointer leaves it, once its time is up.
    static let stayAfterHover: TimeInterval = 1.5

    init(job: ConversionJob, service: ConversionService, hud: ResultHUD) {
        self.job = job
        self.service = service
        self.hud = hud
        state = ResultChipState(display: ChipDisplay(JobSnapshot(job)))
        panel = ChipPanel()

        var actions = ChipActions()
        actions.cancel = { [weak self] in self?.cancel() }
        actions.undo = { [weak self] in self?.undo() }
        actions.dismiss = { [weak self] in self?.dismiss() }
        actions.reveal = { [weak self] in self?.reveal() }
        let container = ChipContainerView(content: ResultChipView(state: state, actions: actions))
        container.onHover = { [weak self] in self?.hoverChanged($0) }
        panel.contentView = container
        panel.onUndo = { [weak self] in self?.undo() }
        panel.onDismiss = { [weak self] in self?.dismiss() }

        observer = job.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        refresh()
    }

    func close() {
        hideWork?.cancel()
        observer = nil
        panel.orderOut(nil)
    }

    private func refresh() {
        var display = ChipDisplay(JobSnapshot(job))
        if let undoError, display.kind == .done || display.kind == .partial {
            display.subtitle = undoError
        }
        state.display = display
        state.outputs = job.outputs
        if let first = job.outputs.first, thumbnailFor != first, display.kind == .done || display.kind == .partial {
            thumbnailFor = first
            state.thumbnail = Thumbnails.icon(for: first)
            Task { [weak self] in
                let image = await Thumbnails.thumbnail(for: first, side: 72)
                guard let self, let image, self.thumbnailFor == first else { return }
                self.state.thumbnail = image
            }
        }
        if display.isFinished, display.kind != lastKind {
            // Each new ending (done, then undone) gets its full time on screen.
            scheduleHide(after: ResultChip.stay)
        }
        lastKind = display.kind
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        hideWhenLeft = false
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hovering {
                    self.hideWhenLeft = true
                } else {
                    self.dismiss()
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hoverChanged(_ inside: Bool) {
        hovering = inside
        if !inside && hideWhenLeft { scheduleHide(after: ResultChip.stayAfterHover) }
    }

    private func cancel() {
        service.cancel(job)
    }

    private func undo() {
        guard state.display.canUndo else { return }
        do {
            try service.undo(job)
            undoError = nil
        } catch {
            undoError = "Couldn't move it to the Trash."
            refresh()
        }
    }

    private func dismiss() {
        hud?.remove(self)
    }

    private func reveal() {
        let existing = job.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }
}

/// The chip's window: a clear, non-activating panel that floats over other apps.
final class ChipPanel: NSPanel {
    /// Room around the chip for its shadow.
    static let margin: CGFloat = 10

    var onUndo: (() -> Void)?
    var onDismiss: (() -> Void)?

    init() {
        let size = ResultChipView.size
        let m = ChipPanel.margin
        super.init(contentRect: NSRect(x: 0, y: 0, width: size.width + m * 2, height: size.height + m * 2),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        animationBehavior = .none
    }

    // Key only after a click, never on its own.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "z" {
            onUndo?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// Holds the chip's SwiftUI view and reports the pointer coming and going.
final class ChipContainerView: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    init(content: ResultChipView) {
        let size = ResultChipView.size
        let m = ChipPanel.margin
        super.init(frame: NSRect(x: 0, y: 0, width: size.width + m * 2, height: size.height + m * 2))
        let hosting = FirstClickHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// A hosting view whose buttons work on the first click, without the panel being key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
