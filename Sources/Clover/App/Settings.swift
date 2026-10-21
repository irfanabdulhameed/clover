import AppKit
import CloverCore

/// The key held while dragging that opens the bloom.
enum TriggerKey: String, CaseIterable, Identifiable {
    case shift, option, control

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shift: "Shift ⇧"
        case .option: "Option ⌥"
        case .control: "Control ⌃"
        }
    }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .option: .option
        case .control: .control
        }
    }
}

/// A global keyboard shortcut. `modifiers` uses Carbon's flags (cmdKey, optionKey, ...).
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// How it reads in the UI, e.g. "⌃⌥Space".
    var display: String

    /// ⌃⌥Space: free in Finder and in most apps.
    static let standard = Hotkey(keyCode: 49, modifiers: 0x1000 | 0x0800, display: "⌃⌥Space")
}

/// User settings, stored in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var triggerKey: TriggerKey {
        didSet { defaults.set(triggerKey.rawValue, forKey: "triggerKey") }
    }

    /// nil means "beside the original".
    @Published var outputFolder: URL? {
        didSet { defaults.set(outputFolder?.path, forKey: "outputFolder") }
    }

    /// Press and hold on a file in Finder, then press the trigger key, to open the clover.
    @Published var holdToOpen: Bool {
        didSet { defaults.set(holdToOpen, forKey: "holdToOpen") }
    }

    /// Opens the clover for the files selected in Finder. nil turns it off.
    @Published var hotkey: Hotkey? {
        didSet { save(hotkey, "hotkey") }
    }

    /// Show the result in Finder after converting.
    @Published var revealAfterConverting: Bool {
        didSet { defaults.set(revealAfterConverting, forKey: "revealAfterConverting") }
    }

    /// The user's clover for each kind of file.
    @Published var layouts: [LayoutKey: LeafLayout] {
        didSet { save(layouts, "layouts") }
    }

    /// Quality and naming choices.
    @Published var conversion: ConversionSettings {
        didSet { save(conversion, "conversion") }
    }

    init() {
        triggerKey = TriggerKey(rawValue: defaults.string(forKey: "triggerKey") ?? "") ?? .shift
        outputFolder = defaults.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) }
        holdToOpen = defaults.object(forKey: "holdToOpen") as? Bool ?? true
        hotkey = defaults.object(forKey: "hotkey") == nil ? .standard : Settings.load(Hotkey.self, "hotkey")
        revealAfterConverting = defaults.bool(forKey: "revealAfterConverting")
        layouts = Settings.load([LayoutKey: LeafLayout].self, "layouts") ?? [:]
        conversion = Settings.load(ConversionSettings.self, "conversion") ?? ConversionSettings()
    }

    func layout(for key: LayoutKey) -> LeafLayout {
        layouts[key] ?? LeafLayout()
    }

    /// Stores a value as JSON. Storing nil keeps the key with an empty value, so a
    /// turned-off hotkey stays off instead of coming back as the standard one.
    private func save<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.set(Data(), forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    var outputLocation: OutputLocation {
        outputFolder.map { .folder($0) } ?? .besideOriginal
    }
}
