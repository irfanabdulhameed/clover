import AppKit
import CloverCore

/// The small chip that shows a job's progress and result.
@MainActor
final class ResultHUD {
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func show(_ job: ConversionJob) {}
}
