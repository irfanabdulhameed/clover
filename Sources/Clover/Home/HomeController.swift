import AppKit

/// The menu bar icon and its Home popover.
@MainActor
final class HomeController {
    private let model: AppModel
    private let bloom: BloomController

    init(model: AppModel, bloom: BloomController) {
        self.model = model
        self.bloom = bloom
    }

    func install() {}
}
