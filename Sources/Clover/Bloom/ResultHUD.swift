import AppKit
import Combine
import QuartzCore
import SwiftUI
import CloverCore

/// The small chip that shows a job's progress and result.
///
/// It appears where the clover was, as the ring the clover left, or at the top right under
/// the menu bar, and several jobs stack in a column. All the chips of a column live in one
/// window. A job that runs long sends the column up under the menu bar icon. It never takes
/// focus by itself: it becomes key only when clicked, so ⌘Z, ⌘C and Esc work then.
@MainActor
final class ResultHUD {
    private let model: AppModel
    let stack = ChipStackState()
    private var panel: ChipPanel?
    private var driver: ChipDriver?
    /// Top-centre of the first chip in the column.
    private var origin: NSPoint?
    private var screen: NSScreen?
    /// The column has moved up under the menu bar icon.
    private var docked = false
    /// The chip that was clicked last: ⌘Z, ⌘C and Esc are about it.
    private weak var focused: ResultChip?
    private var shrinkWork: DispatchWorkItem?
    /// Older finished chips give way beyond this many.
    private let limit = 6
    /// Jobs still running, watched so their files can be shown in Finder when done.
    private var revealWatchers: [UUID: AnyCancellable] = [:]

    private var chips: [ResultChip] { stack.chips }

    init(model: AppModel) { self.model = model }

    func show(_ job: ConversionJob) {
        let anchor = BloomAnchor.take()
        let size = ResultChipView.size
        let fresh = chips.isEmpty || origin == nil || screen == nil
        if fresh {
            let screen = BloomController.screen(containing: anchor ?? NSEvent.mouseLocation)
            self.screen = screen
            origin = anchor.map { NSPoint(x: $0.x, y: $0.y + size.height / 2) }
                ?? ChipStackLayout.cornerOrigin(size: size, visible: screen.visibleFrame)
            docked = false
        }
        if chips.filter({ !$0.isLeaving }).count >= limit, let old = chips.first(where: { $0.job.isFinished && !$0.isLeaving }) {
            old.dismiss()
        }

        // With a clover behind it, the chip is the clover's ring: it starts where the ring was.
        var ringStart: CGSize?
        if fresh, let anchor, let origin, let screen {
            let frame = ChipStackLayout.frames(count: 1, size: size, origin: origin, visible: screen.visibleFrame)[0]
            let room = CGSize(width: size.width / 2 + ChipPanel.margin - ChipMotion.dropRingDiameter / 2,
                              height: size.height / 2 + ChipPanel.margin - ChipMotion.dropRingDiameter / 2)
            ringStart = CGSize(width: min(max(anchor.x - frame.midX, -room.width), room.width),
                               height: min(max(frame.midY - anchor.y, -room.height), room.height))
        }

        let chip = ResultChip(job: job, service: model.service, hud: self, settings: model.settings,
                              slot: chips.count, ringStart: ringStart)
        stack.leafStyle = model.settings.leafStyle
        stack.chips.append(chip)
        let panel = ensurePanel()
        applyLayout()
        panel.orderFrontRegardless()
        if driver == nil, let view = panel.contentView { driver = ChipDriver(stack: stack, view: view) }
        wake()
        watchForReveal(job)
        scheduleDock(for: chip)
    }

    /// Starts the clock if it has stopped.
    func wake() {
        stack.leafStyle = model.settings.leafStyle
        driver?.wake()
    }

    func focus(_ chip: ResultChip) { focused = chip }

    private func undoFocused() {
        (focused ?? chips.last { $0.canUndo })?.undo()
    }

    private func copyFocused() {
        (focused ?? chips.last { $0.canCopy })?.copy()
    }

    private func dismissFocused() {
        (focused ?? chips.last)?.dismiss()
    }

    /// Shows a job's new files in Finder once it is done, when the user asked for that.
    private func watchForReveal(_ job: ConversionJob) {
        revealWatchers[job.id] = job.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak job] _ in
                MainActor.assumeIsolated {
                    guard let self, let job, job.isFinished else { return }
                    self.revealWatchers[job.id] = nil
                    guard ResultHUD.shouldReveal(job.state, outputs: job.outputs,
                                                 enabled: self.model.settings.revealAfterConverting) else { return }
                    let existing = job.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
                    if !existing.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(existing) }
                }
            }
    }

    /// Only a job that made files, and only when "Show in Finder after converting" is on.
    static func shouldReveal(_ state: ConversionJob.State, outputs: [URL], enabled: Bool) -> Bool {
        enabled && state == .done && !outputs.isEmpty
    }

    func remove(_ chip: ResultChip) {
        chip.close()
        guard chips.contains(where: { $0 === chip }) else { return }
        stack.chips.removeAll { $0 === chip }
        if chips.isEmpty {
            closePanel()
            return
        }
        for (index, other) in chips.enumerated() { other.setSlot(index) }
        applyLayout(holdShrink: true)
        wake()
    }

    // MARK: Window

    private func ensurePanel() -> ChipPanel {
        if let panel { return panel }
        let panel = ChipPanel()
        let hosting = FirstClickHostingView(rootView: ChipStackView(stack: stack))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onUndo = { [weak self] in self?.undoFocused() }
        panel.onCopy = { [weak self] in self?.copyFocused() }
        panel.onDismiss = { [weak self] in self?.dismissFocused() }
        self.panel = panel
        return panel
    }

    private func closePanel() {
        shrinkWork?.cancel()
        driver?.stop()
        driver = nil
        panel?.orderOut(nil)
        origin = nil
        screen = nil
        docked = false
        focused = nil
    }

    /// Where the window goes for the chips now in the column, and which way the column grows.
    private func targetFrame() -> NSRect? {
        guard let origin, let screen, !chips.isEmpty else { return nil }
        let frames = ChipStackLayout.frames(count: chips.count, size: ResultChipView.size, origin: origin,
                                            visible: screen.visibleFrame)
        stack.downward = frames.count < 2 || frames[1].minY < frames[0].minY
        let all = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        return all.insetBy(dx: -ChipPanel.margin, dy: -ChipPanel.margin)
    }

    /// Sizes the window for the column. When a chip has left, the window shrinks only after
    /// the others have glided to their places.
    private func applyLayout(holdShrink: Bool = false) {
        guard let panel, let target = targetFrame() else { return }
        shrinkWork?.cancel()
        if holdShrink && target.height < panel.frame.height - 0.5 {
            panel.setFrame(panel.frame.union(target), display: true)
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel, let target = self.targetFrame() else { return }
                    panel.setFrame(target, display: true)
                }
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + ChipMotion.reflowDuration + 0.05, execute: work)
        } else {
            panel.setFrame(target, display: true)
        }
    }

    // MARK: Docking under the menu bar icon

    private func scheduleDock(for chip: ResultChip) {
        DispatchQueue.main.asyncAfter(deadline: .now() + ChipMotion.dockAfter) { [weak self, weak chip] in
            MainActor.assumeIsolated {
                guard let self, let chip else { return }
                self.dock(because: chip)
            }
        }
    }

    /// A job that runs long sends the whole column up under the menu bar icon, where it waits.
    /// Nothing travels with reduced motion, and a chip never crosses to another display.
    private func dock(because chip: ResultChip) {
        guard !docked, !model.settings.reduceMotion, !chip.job.isFinished, !chip.isLeaving,
              chips.contains(where: { $0 === chip }), let panel, let screen,
              let icon = HomeController.statusIconFrame(),
              BloomController.screen(containing: NSPoint(x: icon.midX, y: icon.midY)) == screen
        else { return }
        docked = true
        origin = NSPoint(x: icon.midX, y: icon.minY - 6)
        guard let target = targetFrame() else { return }
        shrinkWork?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ChipMotion.dockDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(target, display: true)
        }
    }
}

// MARK: - What the window draws

/// What the stack's window draws: the chips, and the clock that moves them.
@MainActor
final class ChipStackState: ObservableObject {
    @Published var chips: [ResultChip] = []
    /// True while anything moves. The view then redraws every frame, reading the time
    /// from `CACurrentMediaTime`; when false the timeline pauses.
    @Published var animating = false
    /// The column grows downward from the first chip, or upward when there is no room below.
    @Published var downward = true
    @Published var leafStyle = LeafStyle.clover
}

/// The column of chips, each at its place in the stack.
struct ChipStackView: View {
    @ObservedObject var stack: ChipStackState

    var body: some View {
        let align: Alignment = stack.downward ? .top : .bottom
        let step = ChipMotion.chipSize.height + ChipStackLayout.gap
        ChipGlassContainer {
            // The same frame clock the clover uses. A display link tied to this window
            // didn't run, which froze chips half way through their entrance.
            TimelineView(.animation(minimumInterval: nil, paused: !stack.animating)) { _ in
                let now = CACurrentMediaTime()
                ZStack(alignment: align) {
                    ForEach(stack.chips) { chip in
                        let t = now - chip.born
                        ResultChipView(state: chip.state, actions: chip.actions,
                                       values: chip.playback.values(at: t), clover: stack.leafStyle == .clover)
                            .offset(y: CGFloat(chip.playback.slot(at: t)) * step * (stack.downward ? 1 : -1))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
            .padding(ChipPanel.margin)
        }
    }
}

/// Keeps the chips' timeline running while anything moves, and pauses it once everything
/// has settled. It only checks; the drawing follows SwiftUI's animation timeline.
@MainActor
final class ChipDriver: NSObject {
    private let stack: ChipStackState
    private var timer: Timer?

    init(stack: ChipStackState, view: NSView) {
        self.stack = stack
        super.init()
    }

    func wake() {
        stack.animating = true
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stack.animating = false
    }

    private func check() {
        let now = CACurrentMediaTime()
        if stack.chips.allSatisfy({ $0.playback.isSettled(at: now - $0.born) }) {
            timer?.invalidate()
            timer = nil
            stack.animating = false
        }
    }
}

// MARK: - One chip

/// One job's chip: what it shows, its motion and when it goes.
@MainActor
final class ResultChip: Identifiable {
    let job: ConversionJob
    let state: ResultChipState
    private(set) var actions = ChipActions()
    private(set) var playback: ChipPlayback
    /// When the chip was made, which is the moment of the drop.
    let born = CACurrentMediaTime()
    private let service: ConversionService
    private let settings: Settings
    private weak var hud: ResultHUD?
    private var observer: AnyCancellable?
    private var hideWork: DispatchWorkItem?
    /// Turns the Copy button's checkmark back into its icon.
    private var copyWork: DispatchWorkItem?
    private var lastKind: ChipDisplay.Kind?
    private var hovering = false
    private var hideWhenLeft = false
    private var thumbnailFor: URL?
    /// A finished result waiting for its picture before it shows.
    private var pendingEnding: ChipDisplay.Kind?
    private var undoError: String?
    private var celebrated = false
    private(set) var isLeaving = false

    let id: UUID
    var canUndo: Bool { state.display.canUndo }
    var canCopy: Bool { state.display.canUndo && !state.outputs.isEmpty }

    /// The longest the loader waits for the result's picture.
    static let pictureWait: TimeInterval = 1.0
    /// How long a finished chip stays.
    static let stay: TimeInterval = 5
    /// How long it stays after the pointer leaves it, once its time is up.
    static let stayAfterHover: TimeInterval = 1.5

    init(job: ConversionJob, service: ConversionService, hud: ResultHUD, settings: Settings, slot: Int, ringStart: CGSize?) {
        self.job = job
        id = job.id
        self.service = service
        self.hud = hud
        self.settings = settings
        state = ResultChipState(display: ChipDisplay(JobSnapshot(job)))
        playback = ChipPlayback(reduced: settings.reduceMotion, ringStart: ringStart, slot: slot)

        actions.cancel = { [weak self] in self?.cancel() }
        actions.undo = { [weak self] in self?.undo() }
        actions.copy = { [weak self] in self?.copy() }
        actions.dismiss = { [weak self] in self?.dismiss() }
        actions.reveal = { [weak self] in self?.reveal() }
        actions.hover = { [weak self] in self?.hoverChanged($0) }
        actions.focus = { [weak self] in
            guard let self else { return }
            self.hud?.focus(self)
        }

        observer = job.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        refresh()
    }

    /// Seconds since the drop.
    private func time() -> Double { CACurrentMediaTime() - born }

    func close() {
        hideWork?.cancel()
        copyWork?.cancel()
        observer = nil
    }

    func setSlot(_ index: Int) {
        playback.setSlot(index, at: time())
    }

    private func refresh() {
        let t = time()
        var display = ChipDisplay(JobSnapshot(job))
        if let undoError, display.kind == .done || display.kind == .partial {
            display.subtitle = undoError
        }
        state.display = display
        state.outputs = job.outputs
        if display.kind == .running {
            state.running = display
            playback.progress(display.progress, at: t)
        }
        if display.isFinished, display.kind != lastKind {
            let kind = display.kind
            if (kind == .done || kind == .partial), playback.ending == nil, let first = job.outputs.first {
                // Keep the loader until the result's picture is ready (at most a second),
                // then show the whole result at once.
                thumbnailFor = first
                pendingEnding = kind
                Task { [weak self] in
                    let image = await Thumbnails.thumbnail(for: first, side: 72)
                    guard let self, self.thumbnailFor == first else { return }
                    if let image { self.state.thumbnail = image }
                    self.endWhenReady()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + ResultChip.pictureWait) { [weak self] in
                    MainActor.assumeIsolated { self?.endWhenReady() }
                }
            } else {
                end(kind)
            }
        }
        lastKind = display.kind
        hud?.wake()
    }

    /// Shows the waiting result, once: when its picture has loaded or the wait is over.
    private func endWhenReady() {
        guard let kind = pendingEnding else { return }
        pendingEnding = nil
        if state.thumbnail == nil, let first = thumbnailFor { state.thumbnail = Thumbnails.icon(for: first) }
        end(kind)
        hud?.wake()
    }

    private func end(_ kind: ChipDisplay.Kind) {
        let t = time()
        // Each new ending (done, then undone) gets its full time on screen.
        let firstEnding = playback.ending == nil
        playback.end(kind, at: t)
        let flip = max((playback.ending?.at ?? t) - t, 0)
        scheduleHide(after: flip + ResultChip.stay)
        if firstEnding { scheduleFinish(after: flip, kind: kind) }
    }

    /// The tap and the sound come with the flip, once per job whatever its size.
    private func scheduleFinish(after delay: Double, kind: ChipDisplay.Kind) {
        guard kind == .done || kind == .partial else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.celebrated else { return }
                self.celebrated = true
                if self.settings.haptics { ChipFeedback.tick() }
                if kind == .done && self.settings.completionSound { ChipFeedback.playFinishSound() }
            }
        }
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

    func undo() {
        guard state.display.canUndo else { return }
        do {
            try service.undo(job)
            undoError = nil
        } catch {
            undoError = "Couldn't move it to the Trash."
            refresh()
        }
    }

    /// Puts the result's files on the clipboard as files, so they paste into Finder, Mail or
    /// a chat, and shows a checkmark on the Copy button for a moment.
    func copy() {
        guard canCopy else { return }
        let existing = job.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(existing.map { $0 as NSURL })
        state.copied = true
        state.copies += 1
        copyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.state.copied = false } }
        copyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ChipMotion.copiedHold, execute: work)
    }

    /// Fades, blurs and shrinks away, then leaves the column.
    func dismiss() {
        guard !isLeaving else { return }
        isLeaving = true
        hideWork?.cancel()
        let t = time()
        if t < playback.appearAt {
            hud?.remove(self)
            return
        }
        playback.leave(at: t)
        hud?.wake()
        let wait = playback.reduced ? ChipMotion.reducedFade : ChipMotion.exitDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.02) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hud?.remove(self)
            }
        }
    }

    private func reveal() {
        let existing = job.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }
}

// MARK: - The window

/// The stack's window: a clear, non-activating panel that floats over other apps.
final class ChipPanel: NSPanel {
    /// Room around the chips for their shadow, the shake and the ripple.
    static let margin: CGFloat = 30

    var onUndo: (() -> Void)?
    var onCopy: (() -> Void)?
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

    /// Set by a click on a chip. Without it AppKit would hand the chips key status
    /// when another Clover window closes.
    private var clicked = false

    // Key only after a click, never on its own.
    override var canBecomeKey: Bool { clicked }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { clicked = true }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        clicked = false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "z" {
            onUndo?()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// A hosting view whose buttons work on the first click, without the panel being key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
