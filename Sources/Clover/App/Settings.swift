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

    init() {
        triggerKey = TriggerKey(rawValue: defaults.string(forKey: "triggerKey") ?? "") ?? .shift
        outputFolder = defaults.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) }
    }

    var outputLocation: OutputLocation {
        outputFolder.map { .folder($0) } ?? .besideOriginal
    }
}
