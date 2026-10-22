import AppKit
import Carbon

/// Reads which files are selected in Finder, with AppleScript. macOS asks the user once
/// for the Automation permission (Clover → Finder); the reason shown is the
/// `NSAppleEventsUsageDescription` in Info.plist.
@MainActor
enum FinderSelection {
    static let bundleID = "com.apple.finder"

    enum Failure: Error, Equatable {
        /// The user said no, or hasn't been asked and can't be now (-1743, -1744).
        case notPermitted
        case script(Int, String)
    }

    static var finderIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Finder's selection as aliases, turned into POSIX paths. An empty selection gives an
    /// empty list. The timeout keeps a busy Finder from holding Clover up for long.
    static let source = """
    with timeout of 15 seconds
        tell application "Finder" to set chosen to (get selection as alias list)
    end timeout
    set paths to {}
    repeat with chosenItem in chosen
        set end of paths to POSIX path of (contents of chosenItem)
    end repeat
    return paths
    """

    /// Runs the script, on the main thread. Never called by the self-test.
    static func read() -> Result<[URL], Failure> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.script(0, "The script didn't compile."))
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return .failure(failure(from: error)) }
        return .success(urls(from: result))
    }

    /// An AppleScript error dictionary as a `Failure`.
    static func failure(from error: NSDictionary) -> Failure {
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        if number == -1743 || number == -1744 { return .notPermitted }
        return .script(number, message)
    }

    /// File URLs in a script result: a list of POSIX paths, file URLs or aliases, or one of them.
    static func urls(from descriptor: NSAppleEventDescriptor) -> [URL] {
        let items: [NSAppleEventDescriptor]
        switch descriptor.descriptorType {
        case DescType(typeAEList):
            items = descriptor.numberOfItems > 0 ? (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) } : []
        case DescType(typeNull):
            items = []
        default:
            items = [descriptor]
        }
        return items.compactMap(url(from:))
    }

    private static func url(from item: NSAppleEventDescriptor) -> URL? {
        if item.descriptorType == DescType(typeFileURL) { return item.fileURLValue }
        let text = [typeUnicodeText, typeUTF8Text, typeChar].map { DescType($0) }
        if text.contains(item.descriptorType) {
            guard let path = item.stringValue, path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: path)
        }
        // An alias or another file reference.
        return item.coerce(toDescriptorType: DescType(typeFileURL))?.fileURLValue
    }

    private static let explainedKey = "explainedFinderAutomation"

    /// Says once how to let Clover read Finder's selection. Later refusals only beep.
    static func explainPermission() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: explainedKey) else {
            NSSound.beep()
            return
        }
        defaults.set(true, forKey: explainedKey)
        // Out of the event monitor or timer that asked, so the alert runs on its own.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Clover can't see what's selected in Finder"
            alert.informativeText = "To open the clover for the files you select in Finder, turn on Finder under Clover "
                + "in System Settings → Privacy & Security → Automation."
            alert.addButton(withTitle: "Open Automation Settings")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// Holding still on a file and pressing the trigger key. Fed the button, the pointer and
/// the key about 30 times a second after a mouse-down; pure state, so it can be tested.
struct HoldWatch {
    /// Moving this far ends the hold: it is a drag, which the drag path handles.
    static let slop: CGFloat = 4

    let start: CGPoint
    /// The key must go down during the hold. Held already at the mouse-down (a
    /// Shift-click in Finder), it has to come up first.
    private var keyWasDown: Bool

    enum Step: Equatable {
        /// Keep watching.
        case wait
        /// The key just went down: open the clover.
        case fire
        /// The button came up or the pointer moved: stop watching.
        case stop
    }

    init(start: CGPoint, keyDown: Bool) {
        self.start = start
        keyWasDown = keyDown
    }

    mutating func update(buttonDown: Bool, location: CGPoint, keyDown: Bool) -> Step {
        guard buttonDown, hypot(location.x - start.x, location.y - start.y) < HoldWatch.slop else { return .stop }
        defer { keyWasDown = keyDown }
        return keyDown && !keyWasDown ? .fire : .wait
    }
}
