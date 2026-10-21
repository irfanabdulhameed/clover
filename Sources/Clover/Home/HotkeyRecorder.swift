import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Hotkey {
    /// Carbon's modifier flags, which is what `Hotkey.modifiers` holds.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// How a shortcut reads: modifier symbols in the order macOS shows them, then the key.
    static func display(keyCode: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName(keyCode)
    }

    /// The shortcut for a key press, or nil when it has none of ⌘ ⌃ ⌥ (a bare key or ⇧ alone
    /// would fire every time someone types).
    static func from(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Hotkey? {
        let flags = flags.intersection([.command, .control, .option, .shift])
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let modifiers = carbonModifiers(flags)
        return Hotkey(keyCode: UInt32(keyCode), modifiers: modifiers,
                      display: display(keyCode: UInt32(keyCode), modifiers: modifiers))
    }

    private static let namedKeys: [UInt32: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 71: "Clear", 76: "Enter",
        114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 75: "Keypad /", 78: "Keypad -", 81: "Keypad =",
    ]

    /// "Space", "F5", "A": a name for the key, by its key code.
    static func keyName(_ keyCode: UInt32) -> String {
        if let name = namedKeys[keyCode] { return name }
        return printable(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// The character a key makes on a Latin keyboard layout with no modifiers held.
    private static func printable(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        var dead: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = CFDataGetBytePtr(data).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

/// A button that records a keyboard shortcut. Click it, then type the shortcut: it needs at
/// least one of ⌘ ⌃ ⌥. Esc cancels, Delete turns the shortcut off.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    /// True while it waits for a key press.
    @Binding var isRecording: Bool
    /// True after a press that had none of ⌘ ⌃ ⌥, until the next try.
    @Binding var wasRejected: Bool
    /// For renders: look as if it were waiting for a key.
    var forceRecording = false

    var body: some View {
        RecorderRepresentable(hotkey: hotkey, forceRecording: forceRecording,
                              onCapture: { hotkey = $0 },
                              onRecording: { isRecording = $0; if $0 { wasRejected = false } },
                              onReject: { wasRejected = true })
            .frame(width: 168, height: 24)
            .accessibilityLabel("Shortcut")
            .accessibilityValue(isRecording ? "Waiting for a shortcut" : (hotkey?.display ?? "Off"))
            .accessibilityHint("Click, then press the shortcut you want")
    }
}

private struct RecorderRepresentable: NSViewRepresentable {
    let hotkey: Hotkey?
    let forceRecording: Bool
    let onCapture: (Hotkey?) -> Void
    let onRecording: (Bool) -> Void
    let onReject: () -> Void

    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onCapture = onCapture
        button.onRecording = onRecording
        button.onReject = onReject
        button.forceRecording = forceRecording
        button.hotkey = hotkey
    }
}

/// The recorder's button. It listens with a local event monitor while it waits, so the keys
/// it records (⌘Q, say) are taken before the menu or any other view sees them.
final class RecorderButton: NSButton {
    var onCapture: (Hotkey?) -> Void = { _ in }
    var onRecording: (Bool) -> Void = { _ in }
    var onReject: () -> Void = {}
    var forceRecording = false { didSet { refresh() } }
    var hotkey: Hotkey? { didSet { refresh() } }
    private(set) var isRecording = false { didSet { refresh() } }
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggle)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { stopMonitoring() }

    @objc private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func stop() {
        stopMonitoring()
        guard isRecording else { return }
        isRecording = false
        onRecording(false)
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stop() }
    }

    /// Returns nil to swallow the event.
    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if flags.isEmpty {
                switch Int(event.keyCode) {
                case kVK_Escape:
                    stop()
                    return nil
                case kVK_Delete, kVK_ForwardDelete:
                    stop()
                    onCapture(nil)
                    return nil
                default: break
                }
            }
            if let new = Hotkey.from(keyCode: event.keyCode, flags: flags) {
                stop()
                onCapture(new)
            } else {
                NSSound.beep()
                onReject()
            }
            return nil
        default:
            // A click on the button itself is handled by the button. Any other click ends recording.
            let hit = window?.contentView?.hitTest(event.locationInWindow)
            if hit === self || hit?.isDescendant(of: self) == true { return event }
            stop()
            return event
        }
    }

    private func refresh() {
        let recording = isRecording || forceRecording
        let title: String
        var color = NSColor.labelColor
        if recording {
            title = "Type shortcut…"
            color = .controlAccentColor
        } else if let hotkey {
            title = hotkey.display
        } else {
            title = "Off"
            color = .secondaryLabelColor
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ])
    }
}
