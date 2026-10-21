import AppKit
import Carbon

/// Marks Clover's shortcut among hot-key events: "Clvr".
private let hotkeySignature: OSType = 0x436C_7672

/// The global shortcut that opens the clover for Finder's selection. Carbon's
/// `RegisterEventHotKey` needs no permission; the press arrives on the main thread.
@MainActor
final class BloomHotkey {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// The shortcut now registered; nil when off or when registering failed.
    private(set) var registered: Hotkey?

    /// Replaces the shortcut. nil turns it off.
    func register(_ hotkey: Hotkey?) {
        unregister()
        guard let hotkey else { return }
        installHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: hotkeySignature, id: 1)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Clover: couldn't register the shortcut %@ (%d)", hotkey.display, status)
            return
        }
        hotKeyRef = ref
        registered = hotkey
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registered = nil
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == hotkeySignature else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<BloomHotkey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotkey.onPress?() }
            return noErr
        }, 1, &spec, context, &handlerRef)
    }
}
