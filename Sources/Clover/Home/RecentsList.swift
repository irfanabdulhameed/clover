import AppKit
import SwiftUI
import CloverCore

/// The "Recent" header and the list under it.
struct RecentsSection: View {
    let items: [RecentItem]
    let actions: HomeActions
    var forceHoverRow: UUID?

    static let rowHeight: CGFloat = 52
    private let visibleRows = 5

    /// Five rows fit; with more, half of the next row shows so it's clear the list scrolls.
    private var listHeight: CGFloat {
        let rows = CGFloat(min(items.count, visibleRows)) + (items.count > visibleRows ? 0.5 : 0)
        return rows * Self.rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HoverButton(action: actions.clearAll) {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                }
                .accessibilityLabel("Clear all recent conversions")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 2)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        RecentRow(item: item, actions: actions, forceHover: item.id == forceHoverRow)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: listHeight)
        }
    }
}

/// One finished conversion: thumbnail, output name, size change and time.
/// Click to show in Finder. Drag to take the files out. Right-click for more.
struct RecentRow: View {
    let item: RecentItem
    let actions: HomeActions
    var forceHover = false
    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        let name = RecentFormat.outputName(item)
        HStack(spacing: 10) {
            ThumbnailView(url: item.outputs.first)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(name.first)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if name.more > 0 {
                        Text(" + \(name.more) more")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.system(size: 13, weight: .medium))
                Text(RecentFormat.sizeLine(item))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(RecentFormat.relativeTime(item.date))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: RecentsSection.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(pressed ? 0.14 : (hovered || forceHover) ? 0.07 : 0))
        )
        .overlay(RowInteraction(item: item, actions: actions, hovered: $hovered, pressed: $pressed))
        .help(item.outputs.first?.path ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecentFormat.spoken(item))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Show in Finder") { actions.reveal(item) }
        .accessibilityAction(named: "Open") { actions.open(item) }
        .accessibilityAction(named: "Remove from List") { actions.remove(item) }
    }
}

/// A transparent AppKit layer over a row. It handles what SwiftUI can't: dragging several
/// files out at once, a native context menu, and press and hover feedback.
private struct RowInteraction: NSViewRepresentable {
    let item: RecentItem
    let actions: HomeActions
    @Binding var hovered: Bool
    @Binding var pressed: Bool

    func makeNSView(context: Context) -> RowInteractionView { RowInteractionView() }

    func updateNSView(_ view: RowInteractionView, context: Context) {
        view.item = item
        view.actions = actions
        view.setHovered = { hovered = $0 }
        view.setPressed = { pressed = $0 }
    }
}

final class RowInteractionView: NSView, NSDraggingSource {
    var item: RecentItem?
    var actions: HomeActions = .none
    var setHovered: (Bool) -> Void = { _ in }
    var setPressed: (Bool) -> Void = { _ in }
    private var mouseDownEvent: NSEvent?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        setPressed(true)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        setPressed(false)
        if bounds.contains(convert(event.locationInWindow, from: nil)), let item { actions.reveal(item) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let item else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard hypot(dx, dy) > 4 else { return }
        mouseDownEvent = nil
        setPressed(false)

        let files = item.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
        let stacked = files.prefix(4).enumerated().map { index, url -> NSDraggingItem in
            let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = Thumbnailer.shared.cached(url)?.image ?? Thumbnailer.icon(for: url)
            let origin = convert(start.locationInWindow, from: nil)
            dragItem.setDraggingFrame(NSRect(x: origin.x - 18 + CGFloat(index) * 4, y: origin.y - 18 - CGFloat(index) * 4, width: 36, height: 36), contents: icon)
            return dragItem
        }
        // The rest of the files travel too, without their own drag image.
        let others = files.dropFirst(4).map { url -> NSDraggingItem in
            let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            dragItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 1, height: 1), contents: nil)
            return dragItem
        }
        beginDraggingSession(with: stacked + others, event: start, source: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item else { return nil }
        setPressed(false)
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Show in Finder") { [actions] in actions.reveal(item) })
        menu.addItem(ActionMenuItem("Open") { [actions] in actions.open(item) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Remove from List") { [actions] in actions.remove(item) })
        menu.addItem(ActionMenuItem("Clear All") { [actions] in actions.clearAll() })
        return menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move] : .copy
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
