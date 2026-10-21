import AppKit
import SwiftUI
import CloverCore

/// The floating window that holds the bloom: borderless, clear, over everything,
/// on every Space and over full-screen apps. It never activates Clover, and it only
/// takes keys in click mode.
final class BloomPanel: NSPanel {
    /// True in click mode, so arrows, digits, Return and Esc reach the bloom.
    var allowsKey = false
    var onResignKey: (() -> Void)?

    init() {
        let side = BloomGeometry.panelSize
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
        // Set on purpose: the clear parts of the bloom still take drags and clicks.
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// What the bloom's window reports to its controller.
@MainActor
protocol BloomInteractionDelegate: AnyObject {
    /// Files arrived with a drag; the bloom needs their targets.
    func bloomReceivedFiles(_ files: [URL])
    func bloomChose(_ target: Target, option: Option?)
    func bloomDismissed()
}

/// A clear view over the drawn bloom that takes the drag, the pointer and the keys,
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
        let files = BloomInteractionView.fileURLs(in: sender.draggingPasteboard)
        if !files.isEmpty, !model.hasFiles || files != model.files {
            delegate?.bloomReceivedFiles(files)
        }
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        model.pointer(at: bloomPoint(sender.draggingLocation))
        return model.choice(at: model.hover) == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.pointerLeft()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.pointer(at: bloomPoint(sender.draggingLocation))
        return model.choice(at: model.hover) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let choice = model.choice(at: model.hover) else { return false }
        delegate?.bloomChose(choice.target, option: choice.option)
        return true
    }

    /// File URLs from a drag. Read only here, once the drag is over the bloom.
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
        model.pointer(at: bloomPoint(event.locationInWindow))
        downHit = model.hover
    }

    override func mouseDragged(with event: NSEvent) {
        model.pointer(at: bloomPoint(event.locationInWindow))
    }

    override func mouseUp(with event: NSEvent) {
        model.pointer(at: bloomPoint(event.locationInWindow))
        let hit = model.hover
        defer { downHit = nil }
        guard hit == downHit else { return }
        if let slot = hit.slot, model.isMore(slot) {
            model.nextPage()
        } else if let choice = model.choice(at: hit) {
            delegate?.bloomChose(choice.target, option: choice.option)
        } else if hit == .none {
            delegate?.bloomDismissed()
        }
    }

    // MARK: Keys (click mode)

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: // Esc
            delegate?.bloomDismissed()
        case 36, 76: // Return, Enter
            if let slot = model.focusSlot, model.isMore(slot) {
                model.nextPage()
            } else if let choice = model.keyboardChoice {
                delegate?.bloomChose(choice.target, option: choice.option)
            }
        case 48: // Tab
            model.tab(forward: !shift)
        case 123: model.moveFocus(by: -1) // left
        case 124: model.moveFocus(by: 1) // right
        case 125: model.moveChipFocus(by: 1) // down
        case 126: model.moveChipFocus(by: -1) // up
        default:
            if let characters = event.charactersIgnoringModifiers, let digit = Int(characters), (1...8).contains(digit) {
                model.focusNumber(digit)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        delegate?.bloomDismissed()
    }
}
