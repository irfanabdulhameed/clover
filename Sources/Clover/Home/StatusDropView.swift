import AppKit

/// A transparent view over the menu bar button. It accepts dropped files and handles the
/// clicks itself (left click, right click, control-click), because a view that takes
/// drops would otherwise take the button's mouse events too.
final class StatusDropView: NSView {
    var onLeftClick: () -> Void = {}
    var onRightClick: () -> Void = {}
    var onDrop: ([URL]) -> Void = { _ in }
    private weak var button: NSStatusBarButton?
    private var pressStartedHere = false

    init(button: NSStatusBarButton) {
        self.button = button
        super.init(frame: button.bounds)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick()
            return
        }
        pressStartedHere = true
        button?.highlight(true)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressStartedHere else { return }
        pressStartedHere = false
        button?.highlight(false)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onLeftClick() }
    }

    override func rightMouseUp(with event: NSEvent) { onRightClick() }

    // MARK: Drops

    private func files(in info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !files(in: sender).isEmpty else { return [] }
        button?.highlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { button?.highlight(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { button?.highlight(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.highlight(false)
        let urls = files(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
