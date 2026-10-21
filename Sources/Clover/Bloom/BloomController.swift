import AppKit

/// Watches for a file drag with the trigger key held, and shows the bloom at the pointer.
@MainActor
final class BloomController {
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    /// Starts watching drags.
    func start() {}

    /// Opens the bloom for files that aren't being dragged (Home drop zone, Finder service).
    /// The user then clicks a petal. `point` is in screen coordinates; nil means the
    /// middle of the screen with the pointer.
    func present(files: [URL], at point: NSPoint?) {}
}
