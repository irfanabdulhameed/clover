import AppKit
import Combine
import SwiftUI
import CloverCore

/// Opens the clover at the pointer, three ways:
///
/// - Drag files and hold the trigger key.
/// - Hold still on a file in Finder and press the trigger key. Moving then starts
///   Finder's own drag onto the clover; letting go without moving leaves it open to click.
/// - Press the global shortcut while Finder is in front: the clover opens for Finder's
///   selection, to click.
///
/// Dragging needs no permission: mouse events are watched with global monitors, the
/// trigger key is read from `NSEvent.modifierFlags`, and a file drag is told apart by
/// the drag pasteboard's change count and types. Its contents are read only by the
/// clover's own window, once the drag is over it. The other two ways read Finder's
/// selection with AppleScript, which macOS asks the user to allow once.
@MainActor
final class BloomController: BloomInteractionDelegate {
    private let model: AppModel
    private let bloom = BloomModel()
    private var panel: BloomPanel?
    private var trayPanel: TrayPanel?
    private var monitors: [Any] = []
    private var drag = DragState.idle
    private var ticker: Timer?
    private var pendingHide: DispatchWorkItem?
    /// Takes the windows away once the drop's carry or the cancel has played.
    private var pendingFinish: DispatchWorkItem?
    private var pendingTrayHide: DispatchWorkItem?
    /// Set while the clover is on screen.
    private var shownMode: BloomModel.Mode?
    /// The clover's centre on screen.
    private var center = NSPoint.zero
    private var screenObserver: NSObjectProtocol?
    /// Opened by a hold in Finder: letting go without a drag turns it to click mode.
    private var openedByHold = false
    /// Tells a new press of the trigger key, which closes the clover, from the one that opened it.
    private var triggerToggle: TriggerToggle?
    /// Closed by the trigger key during a drag: the key must come up before it opens again.
    private var waitForKeyUp = false
    private var hold: HoldWatch?
    private var holdTimer: Timer?
    private let hotkey = BloomHotkey()
    private var hotkeyObserver: AnyCancellable?

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

    /// Starts watching drags and holds, and registers the shortcut.
    func start() {
        if BloomDebug.run(CommandLine.arguments, model: model) { return }
        makePanel()
        // Clover starts at login, often before every display is set up. When displays
        // change, the floating windows are made again so they open on the right screen.
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
        }
        guard monitors.isEmpty else { return }
        // Leaf outlines and label boxes are measured once, now, not on the first drag.
        DispatchQueue.main.async {
            for count in 1...BloomGeometry.maxLeaves {
                for index in 0..<count {
                    _ = BloomLayout.labelBox(index, of: count)
                    _ = BloomLayout.labelBox(index, of: count, icon: true)
                    _ = SlotView.localPath(index, count)
                }
            }
            // One still frame drawn offscreen warms text, symbol and blur caches, so the
            // first real open doesn't pay for them.
            let still = BloomModel.still(arrangement: Arrangement(leaves: [], more: []), picture: nil, lit: nil)
            let warm = ImageRenderer(content: ZStack {
                BloomScene(model: still, now: 0)
                SlotLabel(title: "JPG", symbol: "ellipsis", hue: .orange, lit: true, width: 80)
                CapsuleLabel(text: "2.2 MB")
                ChipView(title: "Balanced", isDefault: true, isLit: false, isFocused: false, hue: .orange)
                // The wave of light and the ring, so the first choice isn't the first time.
                let side = BloomGeometry.panelSize
                // The distortion wave's shaders, mid-wave, so its first frames don't stall.
                let wave = DistortionWaves.front(at: 0.6, slot: 0, count: 6, in: DistortionWaves.discSize)
                DistortionStage(front: wave.front, source: wave.source) {
                    Circle().fill(Color.white.opacity(0.3)).frame(width: side / 2, height: side / 2)
                }
                ChipRing(progress: 0, diameter: Motion.Drop.ringSide)
            }.environment(\.bloomSnapshot, true))
            _ = warm.cgImage
        }
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
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkeyObserver = model.settings.$hotkey
            .removeDuplicates()
            .sink { [weak self] key in MainActor.assumeIsolated { self?.hotkey.register(key) } }
    }

    /// Opens the clover for files that aren't being dragged (Home drop zone, Finder
    /// service, the shortcut). The user then clicks a leaf. `point` is in screen
    /// coordinates; nil means the middle of the screen with the pointer.
    func present(files: [URL], at point: NSPoint?) {
        guard !files.isEmpty else { return }
        makePanel()
        bloom.reset(mode: .click)
        bloom.setFiles(files, arrangement: model.arrangement(for: files))
        let screen = BloomController.screen(containing: point ?? NSEvent.mouseLocation)
        let anchor = point ?? NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        show(at: anchor, on: screen, mode: .click)
    }

    // MARK: Drag watching

    private func handleGlobal(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if shownMode == .click { dismiss() }
            drag = .pressed(NSPasteboard(name: .drag).changeCount)
            startHold()
        case .leftMouseDragged:
            dragged()
        case .leftMouseUp:
            released()
        default:
            break
        }
    }

    /// A press in one of Clover's own windows: its drags never open the clover.
    private func handleLocalDown(_ event: NSEvent) {
        if drag != .files { drag = .other }
        if shownMode == .click, event.window !== panel, event.window !== trayPanel { dismiss() }
    }

    private func dragged() {
        switch drag {
        case .pressed(let count):
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != count else { return }
            if pasteboard.types?.contains(.fileURL) == true {
                drag = .files
                stopHold()
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
        let down = NSEvent.modifierFlags.contains(model.settings.triggerKey.flag)
        if waitForKeyUp {
            if !down { waitForKeyUp = false }
            return
        }
        guard down else { return }
        let mouse = NSEvent.mouseLocation
        bloom.reset(mode: .drag)
        // The labels must be there when the clover shows, so the dragged files are read
        // from the drag's own pasteboard now, which is instant. (Asking Finder for its
        // selection here waited until the drag ended: Finder is busy running the drag.)
        let files = BloomInteractionView.fileURLs(in: NSPasteboard(name: .drag))
        if !files.isEmpty {
            bloom.setFiles(files, arrangement: model.arrangement(for: files))
        }
        show(at: mouse, on: BloomController.screen(containing: mouse), mode: .drag)
    }

    private func released() {
        stopTicker()
        stopHold()
        let wasFiles = drag == .files
        drag = .idle
        if openedByHold, !wasFiles, shownMode == .drag {
            // Held still and let go: the user clicks a leaf instead.
            switchToClickMode()
            return
        }
        guard wasFiles, shownMode == .drag else { return }
        if isOverClover(NSEvent.mouseLocation) {
            // A drop on a slot or a pill arrives by itself; one anywhere else never does.
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.dismiss() } }
            pendingHide?.cancel()
            pendingHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        } else {
            dismiss()
        }
    }

    private func isOverClover(_ point: NSPoint) -> Bool {
        if let panel, panel.frame.contains(point) { return true }
        if let trayPanel, trayPanel.isVisible, trayPanel.frame.contains(point) { return true }
        return false
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
        pollTrigger()
        checkTrigger()
    }

    /// While the clover is open in drag mode, a new press of the trigger key closes it.
    private func pollTrigger() {
        guard shownMode == .drag, var toggle = triggerToggle else { return }
        let closes = toggle.poll(keyDown: NSEvent.modifierFlags.contains(model.settings.triggerKey.flag))
        triggerToggle = toggle
        if closes { closeByTrigger() }
    }

    /// Closes the clover as Esc does. A drag carries on, and the key must come up before
    /// the clover can open again.
    private func closeByTrigger() {
        waitForKeyUp = true
        dismiss()
    }

    // MARK: Hold and press

    /// After a mouse-down anywhere, watches for the trigger key while the button stays
    /// down and the pointer stays put. Finder is checked only when the key goes down.
    private func startHold() {
        stopHold()
        guard model.settings.holdToOpen, shownMode == nil else { return }
        hold = HoldWatch(start: NSEvent.mouseLocation, keyDown: NSEvent.modifierFlags.contains(model.settings.triggerKey.flag))
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.holdTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func stopHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        hold = nil
    }

    private func holdTick() {
        guard var watch = hold else {
            stopHold()
            return
        }
        let step = watch.update(buttonDown: NSEvent.pressedMouseButtons & 1 != 0, location: NSEvent.mouseLocation,
                                keyDown: NSEvent.modifierFlags.contains(model.settings.triggerKey.flag))
        hold = watch
        switch step {
        case .wait:
            break
        case .stop:
            stopHold()
        case .fire:
            let start = watch.start
            stopHold()
            openFromHold(start: start)
        }
    }

    private func openFromHold(start: NSPoint) {
        guard shownMode == nil, drag != .files, model.settings.holdToOpen, FinderSelection.finderIsFrontmost else { return }
        guard let files = finderSelection(), !files.isEmpty else { return }
        // Finder may answer only once the button is up. If the pointer went somewhere
        // meanwhile, the user has moved on.
        let mouse = NSEvent.mouseLocation
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        guard shownMode == nil, drag != .files, hypot(mouse.x - start.x, mouse.y - start.y) < HoldWatch.slop * 3 else { return }
        bloom.reset(mode: .drag)
        bloom.setFiles(files, arrangement: model.arrangement(for: files))
        show(at: mouse, on: BloomController.screen(containing: mouse), mode: .drag)
        openedByHold = true
        if buttonDown {
            // Polls the trigger key, and notices the button coming up, while it is held.
            startTicker()
        } else {
            switchToClickMode()
        }
    }

    /// Opened by a hold and let go: the window takes keys and clicks pick a leaf.
    private func switchToClickMode() {
        guard let panel, shownMode == .drag else { return }
        openedByHold = false
        shownMode = .click
        bloom.mode = .click
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.initialFirstResponder)
    }

    // MARK: Shortcut

    private func hotkeyPressed() {
        if shownMode != nil {
            dismiss()
            return
        }
        guard FinderSelection.finderIsFrontmost, let files = finderSelection(), !files.isEmpty else {
            NSSound.beep()
            return
        }
        present(files: files, at: NSEvent.mouseLocation)
    }

    /// Finder's selection, or nil when it can't be read. A refused permission is
    /// explained once.
    private func finderSelection() -> [URL]? {
        switch FinderSelection.read() {
        case .success(let files):
            return files
        case .failure(.notPermitted):
            FinderSelection.explainPermission()
            return nil
        case .failure(.script(let number, let message)):
            NSLog("Clover: couldn't read Finder's selection (%d): %@", number, message)
            return nil
        }
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
            if self?.shownMode == .click { self?.dismiss() }
        }
        self.panel = panel

        let tray = TrayPanel()
        let trayContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let trayHosting = NSHostingView(rootView: TrayView(model: bloom))
        trayHosting.sizingOptions = []
        trayHosting.frame = trayContainer.bounds
        trayHosting.autoresizingMask = [.width, .height]
        let trayInteraction = TrayInteractionView(model: bloom)
        trayInteraction.frame = trayContainer.bounds
        trayInteraction.autoresizingMask = [.width, .height]
        trayInteraction.delegate = self
        trayContainer.addSubview(trayHosting)
        trayContainer.addSubview(trayInteraction)
        tray.contentView = trayContainer
        trayPanel = tray
        bloom.onTrayChange = { [weak self] open in self?.trayChanged(open) }
        bloom.onLight = { [weak self] in self?.tick(.alignment) }
    }

    /// A trackpad tick, when haptics are on.
    private func tick(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard model.settings.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func show(at anchor: NSPoint, on screen: NSScreen, mode: BloomModel.Mode) {
        guard let panel else { return }
        pendingHide?.cancel()
        panel.alphaValue = 0
        // A clover still folding away goes at once.
        if pendingFinish != nil { finishHide(keepModel: true) }
        bloom.reduceMotion = model.settings.reduceMotion
        triggerToggle = TriggerToggle(keyDown: NSEvent.modifierFlags.contains(model.settings.triggerKey.flag))
        bloom.tint = model.settings.glassTint
        let c = BloomLayout.clampedCenter(anchor, bounds: BloomController.extent, visible: screen.visibleFrame)
        center = c
        let side = BloomGeometry.panelSize
        let frame = NSRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
        panel.setFrame(frame, display: true)
        panel.allowsKey = mode == .click
        shownMode = mode
        openedByHold = false
        bloom.open()
        if mode == .click {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.initialFirstResponder)
        } else {
            panel.orderFrontRegardless()
        }
        // A window placed while hidden can come up on another display; place it again
        // now that it is on screen.
        if panel.screen != screen || panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        reveal()
    }

    /// Fades the clover's window in, glass and all, with everything already drawn.
    private func reveal() {
        guard let panel, shownMode != nil, panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.Open.fadeIn
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
        }
    }

    /// Displays were added, removed or rearranged: make the floating windows again.
    private func screensChanged() {
        if shownMode != nil { dismiss() }
        panel?.orderOut(nil)
        trayPanel?.orderOut(nil)
        panel = nil
        trayPanel = nil
        makePanel()
    }

    /// Shows the More tray beside the More slot, kept on screen, or lets it fold away.
    private func trayChanged(_ open: Bool) {
        guard let trayPanel else { return }
        pendingTrayHide?.cancel()
        pendingTrayHide = nil
        guard open, shownMode != nil, let more = bloom.moreIndex else {
            guard trayPanel.isVisible, shownMode != nil else {
                trayPanel.orderOut(nil)
                return
            }
            // It shrinks back towards More first, when the tray is animated.
            let close = Motion.trayCloseDuration(reduce: model.settings.reduceMotion)
            guard close > 0 else {
                trayPanel.orderOut(nil)
                return
            }
            let work = DispatchWorkItem { [weak trayPanel] in trayPanel?.orderOut(nil) }
            pendingTrayHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + close, execute: work)
            return
        }
        let screen = BloomController.screen(containing: center)
        let sector = BloomLayout.screenRect(BloomLayout.sectorBounds(more, of: bloom.leafCount), center: center)
        let rect = TrayLayout.frame(size: bloom.traySize, more: sector, clover: center, visible: screen.visibleFrame)
        bloom.trayAnchor = TrayLayout.anchor(tray: rect, more: sector)
        let m = TrayLayout.windowMargin
        trayPanel.setFrame(rect.insetBy(dx: -m, dy: -m), display: true)
        trayPanel.orderFrontRegardless()
    }

    /// Folds the clover into its hub and then hides it: Esc, a release or a click outside.
    private func dismiss() {
        pendingHide?.cancel()
        pendingHide = nil
        openedByHold = false
        guard shownMode != nil else { return }
        shownMode = nil
        panel?.allowsKey = false
        bloom.cancel()
        finish(after: Motion.cancelDuration(reduce: bloom.reduceMotion))
    }

    /// Hides the windows once `delay` has passed.
    private func finish(after delay: TimeInterval) {
        pendingFinish?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.finishHide(keepModel: false) } }
        pendingFinish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Takes the windows away now. `keepModel` leaves the model for a clover opening at once.
    private func finishHide(keepModel: Bool) {
        pendingFinish?.cancel()
        pendingFinish = nil
        pendingTrayHide?.cancel()
        pendingTrayHide = nil
        panel?.orderOut(nil)
        trayPanel?.orderOut(nil)
        if !keepModel { bloom.reset(mode: .drag) }
    }


    // MARK: BloomInteractionDelegate

    func bloomReceivedFiles(_ files: [URL]) {
        bloom.setFiles(files, arrangement: model.arrangement(for: files))
    }

    func bloomChose(_ target: Target, option: Option?) {
        let files = bloom.files
        guard !files.isEmpty, shownMode != nil else { return }
        pendingHide?.cancel()
        pendingHide = nil
        // The chosen slot flashes, the wave rolls across the disc, and the slot gathers to
        // the hub as the progress ring; the result chip takes the ring over at
        // `BloomAnchor` when the panel hides.
        bloom.drop()
        tick(.generic)
        shownMode = nil
        openedByHold = false
        panel?.allowsKey = false
        BloomAnchor.set(center)
        model.convert(files, to: target, option: option)
        // The chip's window shows its ring at the handoff; the clover's stays one frame
        // longer (above it, as the ring the chip starts from), so there is never a frame with no ring.
        finish(after: Motion.Drop.handoff + 1.0 / 60)
    }

    func bloomModifiersChanged(_ flags: NSEvent.ModifierFlags) {
        guard shownMode == .click, var toggle = triggerToggle else { return }
        let closes = toggle.changed(keyDown: flags.contains(model.settings.triggerKey.flag))
        triggerToggle = toggle
        if closes { closeByTrigger() }
    }

    func bloomOtherKey() {
        triggerToggle?.otherKey()
    }

    func bloomDismissed() {
        dismiss()
    }

    // MARK: Geometry

    /// Options with the widest chips, to size the clover's reach.
    static let widestOptions: [[Option]] = [
        [Options.original, Options.p1080, Options.p720, Options.small],
        [Options.best, Options.balanced, Options.small, Options.lossless],
        [Options.large, Options.medium, Options.small],
        [Options.combine, Options.each],
    ]

    /// The most any clover can cover, chips included, so it is placed once and never
    /// jumps when the files arrive. The More tray has its own window and placement.
    static let extent: CGRect = {
        let widths = widestOptions.map { set in
            set.map { BloomLayout.chipWidth(textWidth: BloomStyle.textWidth($0.title), isDefault: true) }
        }
        return (1...BloomGeometry.maxLeaves).reduce(CGRect.null) { bounds, count in
            bounds.union(BloomLayout.contentBounds(count: count, chipWidths: widths))
        }
    }()

    static func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

/// Where the clover was when a conversion started from it, so the result chip can
/// appear in the same place: the hub's centre on screen. The clover's carry ends there
/// `Motion.Drop.handoff` (550 ms) after the drop, as the chip's own `ChipRing`, at
/// `Motion.Drop.ringSide`, on the hub's glass; the chip starts as that ring.
@MainActor
enum BloomAnchor {
    private static var last: (point: NSPoint, time: Date)?

    static func set(_ point: NSPoint) {
        last = (point, Date())
    }

    /// The point, if a clover just closed. Used once.
    static func take() -> NSPoint? {
        defer { last = nil }
        guard let last, Date().timeIntervalSince(last.time) < Motion.Drop.handoff + 1.5 else { return nil }
        return last.point
    }
}

/// Tells a new press of the trigger key from the press that opened the clover: a new press
/// closes it, as Esc does. The key must have come up since the clover opened.
///
/// In drag mode the key is polled and a new press closes on the way down. In click mode
/// the clover's window has the keys, so it closes on the way up of a clean tap: a press
/// with another key in it (Shift-Tab, say) is not a tap.
struct TriggerToggle: Equatable {
    /// The key has come up since the clover opened, so its next press is a new one.
    private(set) var armed: Bool
    /// Click mode: a new press is down, with no other key pressed since.
    private(set) var tapping = false

    /// `keyDown`: whether the key is down as the clover opens; usually it is, having opened it.
    init(keyDown: Bool) { armed = !keyDown }

    /// Drag mode, polled. True when a new press goes down: close.
    mutating func poll(keyDown: Bool) -> Bool {
        guard keyDown else {
            armed = true
            tapping = false
            return false
        }
        guard armed else { return false }
        armed = false
        return true
    }

    /// Click mode: the key went down or up. True when a new press comes up as a clean tap.
    mutating func changed(keyDown: Bool) -> Bool {
        if keyDown {
            tapping = armed
            armed = false
            return false
        }
        armed = true
        defer { tapping = false }
        return tapping
    }

    /// Another key was pressed while the trigger key was down: not a tap.
    mutating func otherKey() { tapping = false }
}
