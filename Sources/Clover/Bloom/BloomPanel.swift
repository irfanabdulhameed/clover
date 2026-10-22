import AppKit
import SwiftUI
import CloverCore

/// The floating window that holds the clover: borderless, clear, over everything,
/// on every Space and over full-screen apps. It never activates Clover, and it only
/// takes keys in click mode.
final class BloomPanel: NSPanel {
    /// True in click mode, so arrows, digits, Return and Esc reach the clover.
    var allowsKey = false
    var onResignKey: (() -> Void)?

    init(side: CGFloat = BloomGeometry.panelSize) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        // Set on purpose: the clear parts of the clover still take drags and clicks.
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// What the clover's windows report to their controller.
@MainActor
protocol BloomInteractionDelegate: AnyObject {
    /// Files arrived with a drag; the clover needs their arrangement.
    func bloomReceivedFiles(_ files: [URL])
    func bloomChose(_ target: Target, option: Option?)
    func bloomDismissed()
    /// Click mode: the modifier keys changed, or another key was pressed (for the trigger
    /// key's new press, which closes the clover).
    func bloomModifiersChanged(_ flags: NSEvent.ModifierFlags)
    func bloomOtherKey()
}

/// A clear view over the drawn clover that takes the drag, the pointer and the keys,
/// and hit-tests them with `BloomLayout`.
final class BloomInteractionView: NSView {
    let model: BloomModel
    weak var delegate: BloomInteractionDelegate?
    private var tracking: NSTrackingArea?
    private var downHit: BloomHit?

    init(model: BloomModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func bloomPoint(_ windowPoint: NSPoint) -> CGPoint {
        BloomLayout.bloomPoint(fromView: convert(windowPoint, from: nil), panelSize: bounds.width)
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard model.phase == .open else { return [] }
        let files = BloomInteractionView.fileURLs(in: sender.draggingPasteboard)
        if !files.isEmpty, !model.hasFiles || files != model.files {
            delegate?.bloomReceivedFiles(files)
        }
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard model.phase == .open else { return [] }
        model.pointer(at: bloomPoint(sender.draggingLocation))
        return model.choice(at: model.hover) == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.pointerLeft()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard model.phase == .open else { return false }
        model.pointer(at: bloomPoint(sender.draggingLocation))
        return model.choice(at: model.hover) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard model.phase == .open, let choice = model.choice(at: model.hover) else { return false }
        // A quick press at the drop point starts the choice, like a click on glass.
        if let target = BloomModel.pressTarget(model.hover) {
            model.quickPress(target, at: bloomPoint(sender.draggingLocation))
        }
        delegate?.bloomChose(choice.target, option: choice.option)
        return true
    }

    /// File URLs from a drag. Read only here, once the drag is over the clover.
    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        return objects.compactMap { ($0 as? NSURL)?.filePathURL ?? ($0 as? URL) }
    }

    // MARK: Pointer (click mode)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard model.mode == .click else { return }
        model.pointer(at: bloomPoint(event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) {
        guard model.mode == .click else { return }
        model.pointerLeft()
    }

    override func mouseDown(with event: NSEvent) {
        let point = bloomPoint(event.locationInWindow)
        model.pointer(at: point)
        downHit = model.hover
        // The slot or chip under the button reacts like a pressed glass button.
        if let target = BloomModel.pressTarget(model.hover) { model.pressDown(target, at: point) }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = bloomPoint(event.locationInWindow)
        model.pointer(at: point)
        if downHit != nil { model.pressMoved(over: BloomModel.pressTarget(model.hover), at: point) }
    }

    override func mouseUp(with event: NSEvent) {
        guard model.phase == .open else { return }
        model.pointer(at: bloomPoint(event.locationInWindow))
        let hit = model.hover
        defer { downHit = nil }
        // The choice is made on release, over the target the button went down on.
        let released = model.pressUp(over: BloomModel.pressTarget(hit))
        guard hit == downHit else { return }
        if let leaf = hit.leaf, model.isMore(leaf) {
            if released { model.toggleTray() }
        } else if let choice = model.choice(at: hit) {
            if released { delegate?.bloomChose(choice.target, option: choice.option) }
        } else if hit == .none {
            delegate?.bloomDismissed()
        }
    }

    // MARK: Keys (click mode)

    override func flagsChanged(with event: NSEvent) {
        delegate?.bloomModifiersChanged(event.modifierFlags)
        super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        delegate?.bloomOtherKey()
        guard model.phase == .open else { return }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: // Esc
            if !model.escape() { delegate?.bloomDismissed() }
        case 36, 76: // Return, Enter
            if model.focusIsMore {
                model.openTray(focusFirst: true)
            } else if let choice = model.keyboardChoice {
                // A quick press from the focused slot's middle starts the choice.
                if let press = model.keyboardPress { model.quickPress(press.target, at: press.point) }
                delegate?.bloomChose(choice.target, option: choice.option)
            }
        case 48: // Tab
            model.tab(forward: !shift)
        case 123: model.moveFocus(by: -1) // left
        case 124: model.moveFocus(by: 1) // right
        case 125: model.moveChipFocus(by: 1) // down
        case 126: model.moveChipFocus(by: -1) // up
        default:
            if let characters = event.charactersIgnoringModifiers, let digit = Int(characters),
               (1...BloomGeometry.maxLeaves).contains(digit) {
                model.focusNumber(digit)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if !model.escape() { delegate?.bloomDismissed() }
    }
}

// MARK: - More tray

/// The More tray's own window, beside the More leaf. It never takes keys: they keep
/// going to the clover's window, which steers the tray through the model.
final class TrayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A clear view over the drawn tray that takes the drag and the pointer, and hit-tests
/// them with `TrayLayout`.
final class TrayInteractionView: NSView {
    let model: BloomModel
    weak var delegate: BloomInteractionDelegate?
    private var tracking: NSTrackingArea?
    private var downHit: TrayHit?

    init(model: BloomModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Window point to tray coordinates.
    private func trayPoint(_ windowPoint: NSPoint) -> CGPoint {
        let p = convert(windowPoint, from: nil)
        return CGPoint(x: p.x - TrayLayout.windowMargin, y: p.y - TrayLayout.windowMargin)
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard model.phase == .open else { return [] }
        model.trayPointer(at: trayPoint(sender.draggingLocation))
        return model.trayChoice(at: model.trayHover) == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.trayPointerLeft()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard model.phase == .open else { return false }
        model.trayPointer(at: trayPoint(sender.draggingLocation))
        return model.trayChoice(at: model.trayHover) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard model.phase == .open, let choice = model.trayChoice(at: model.trayHover) else { return false }
        if let target = BloomModel.pressTarget(model.trayHover) {
            model.quickPress(target, at: trayPoint(sender.draggingLocation))
        }
        delegate?.bloomChose(choice.target, option: choice.option)
        return true
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard model.mode == .click else { return }
        model.trayPointer(at: trayPoint(event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) {
        guard model.mode == .click else { return }
        model.trayPointerLeft()
    }

    override func mouseDown(with event: NSEvent) {
        let point = trayPoint(event.locationInWindow)
        model.trayPointer(at: point)
        downHit = model.trayHover
        if let target = BloomModel.pressTarget(model.trayHover) { model.pressDown(target, at: point) }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = trayPoint(event.locationInWindow)
        model.trayPointer(at: point)
        if downHit != nil { model.pressMoved(over: BloomModel.pressTarget(model.trayHover), at: point) }
    }

    override func mouseUp(with event: NSEvent) {
        guard model.phase == .open else { return }
        model.trayPointer(at: trayPoint(event.locationInWindow))
        let hit = model.trayHover
        defer { downHit = nil }
        let released = model.pressUp(over: BloomModel.pressTarget(hit))
        guard released, hit == downHit, let choice = model.trayChoice(at: hit) else { return }
        delegate?.bloomChose(choice.target, option: choice.option)
    }
}
