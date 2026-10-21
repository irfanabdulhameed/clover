import AppKit
import SwiftUI
import CloverCore

/// Watches for a file drag with the trigger key held, and shows the bloom at the pointer.
///
/// No permission is needed: mouse events are watched with global monitors, the trigger
/// key is read from `NSEvent.modifierFlags`, and a file drag is told apart by the drag
/// pasteboard's change count and types. Its contents are read only by the bloom's own
/// window, once the drag is over it.
@MainActor
final class BloomController: BloomInteractionDelegate {
    private let model: AppModel
    private let bloom = BloomModel()
    private var panel: BloomPanel?
    private var monitors: [Any] = []
    private var drag = DragState.idle
    private var ticker: Timer?
    private var pendingHide: DispatchWorkItem?
    /// Set while the bloom is on screen.
    private var shownMode: BloomModel.Mode?
    /// The bloom's centre on screen.
    private var center = NSPoint.zero

    private enum DragState: Equatable {
        case idle
        /// The button is down; the drag pasteboard had this change count then.
        case pressed(Int)
        /// A drag of files from another app.
        case files
        /// Some other drag: a window, a text selection.
        case other
    }

    init(model: AppModel) { self.model = model }

    /// Starts watching drags.
    func start() {
        if BloomDebug.run(CommandLine.arguments, model: model) { return }
        makePanel()
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobal(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleLocalDown(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Opens the bloom for files that aren't being dragged (Home drop zone, Finder service).
    /// The user then clicks a petal. `point` is in screen coordinates; nil means the
    /// middle of the screen with the pointer.
    func present(files: [URL], at point: NSPoint?) {
        guard !files.isEmpty else { return }
        makePanel()
        bloom.reset(mode: .click)
        bloom.setFiles(files, targets: model.targets(for: files))
        let screen = BloomController.screen(containing: point ?? NSEvent.mouseLocation)
        let anchor = point ?? NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        show(at: anchor, on: screen, mode: .click)
    }

    // MARK: Drag watching

    private func handleGlobal(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if shownMode == .click { hide() }
            drag = .pressed(NSPasteboard(name: .drag).changeCount)
        case .leftMouseDragged:
            dragged()
        case .leftMouseUp:
            released()
        default:
            break
        }
    }

    /// A press in one of Clover's own windows: its drags never open the bloom.
    private func handleLocalDown(_ event: NSEvent) {
        if drag != .files { drag = .other }
        if shownMode == .click, event.window !== panel { hide() }
    }

    private func dragged() {
        switch drag {
        case .pressed(let count):
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != count else { return }
            if pasteboard.types?.contains(.fileURL) == true {
                drag = .files
                startTicker()
                checkTrigger()
            } else {
                drag = .other
            }
        case .files:
            checkTrigger()
        default:
            break
        }
    }

    /// The pointer may be still while the key goes down, so this also runs on a timer.
    private func checkTrigger() {
        guard drag == .files, shownMode == nil else { return }
        guard NSEvent.modifierFlags.contains(model.settings.triggerKey.flag) else { return }
        let mouse = NSEvent.mouseLocation
        bloom.reset(mode: .drag)
        show(at: mouse, on: BloomController.screen(containing: mouse), mode: .drag)
    }

    private func released() {
        stopTicker()
        let wasFiles = drag == .files
        drag = .idle
        guard wasFiles, shownMode == .drag, let panel else { return }
        if panel.frame.contains(NSEvent.mouseLocation) {
            // A drop on a petal arrives by itself; one anywhere else never does.
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
            pendingHide?.cancel()
            pendingHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        } else {
            hide()
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        // The button came up without a mouse-up reaching us.
        if NSEvent.pressedMouseButtons & 1 == 0 {
            released()
            return
        }
        checkTrigger()
    }

    // MARK: Showing

    private func makePanel() {
        guard panel == nil else { return }
        let panel = BloomPanel()
        let side = BloomGeometry.panelSize
        let container = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        let hosting = NSHostingView(rootView: BloomView(model: bloom))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        let interaction = BloomInteractionView(model: bloom)
        interaction.frame = container.bounds
        interaction.autoresizingMask = [.width, .height]
        interaction.delegate = self
        container.addSubview(hosting)
        container.addSubview(interaction)
        panel.contentView = container
        panel.initialFirstResponder = interaction
        panel.onResignKey = { [weak self] in
            if self?.shownMode == .click { self?.hide() }
        }
        self.panel = panel
    }

    private func show(at anchor: NSPoint, on screen: NSScreen, mode: BloomModel.Mode) {
        guard let panel else { return }
        pendingHide?.cancel()
        let c = BloomLayout.clampedCenter(anchor, bounds: BloomController.extent, visible: screen.visibleFrame)
        center = c
        let side = BloomGeometry.panelSize
        panel.setFrame(NSRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side), display: true)
        panel.allowsKey = mode == .click
        shownMode = mode
        if mode == .click {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.initialFirstResponder)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        pendingHide?.cancel()
        pendingHide = nil
        guard shownMode != nil else { return }
        shownMode = nil
        panel?.allowsKey = false
        panel?.orderOut(nil)
        bloom.reset(mode: .drag)
    }

    // MARK: BloomInteractionDelegate

    func bloomReceivedFiles(_ files: [URL]) {
        bloom.setFiles(files, targets: model.targets(for: files))
    }

    func bloomChose(_ target: Target, option: Option?) {
        let files = bloom.files
        guard !files.isEmpty else { return }
        BloomAnchor.set(center)
        model.convert(files, to: target, option: option)
        // Leave the drop callback before the window goes.
        DispatchQueue.main.async { [weak self] in self?.hide() }
    }

    func bloomDismissed() {
        hide()
    }

    // MARK: Geometry

    /// The most a page can cover, chips included, so the bloom is placed once and
    /// never jumps when the files arrive.
    static let extent: CGRect = {
        let sets: [[Option]] = [
            [Options.original, Options.p1080, Options.p720, Options.small],
            [Options.best, Options.balanced, Options.small, Options.lossless],
            [Options.large, Options.medium, Options.small],
            [Options.combine, Options.each],
        ]
        let widths = sets.map { set in
            set.map { BloomLayout.chipWidth(textWidth: BloomStyle.textWidth($0.title), isDefault: true) }
        }
        return BloomLayout.contentBounds(slots: Array(0..<BloomPlan.slotCount), chipWidths: widths)
    }()

    static func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

/// Where the bloom was when a conversion started from it, so the result chip can
/// appear in the same place.
@MainActor
enum BloomAnchor {
    private static var last: (point: NSPoint, time: Date)?

    static func set(_ point: NSPoint) {
        last = (point, Date())
    }

    /// The point, if a bloom just closed. Used once.
    static func take() -> NSPoint? {
        defer { last = nil }
        guard let last, Date().timeIntervalSince(last.time) < 2 else { return nil }
        return last.point
    }
}
