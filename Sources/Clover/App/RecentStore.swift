import Foundation
import CloverCore

/// A finished conversion, kept for the Home popover.
struct RecentItem: Codable, Identifiable, Equatable {
    var id = UUID()
    let title: String
    let inputNames: [String]
    let outputs: [URL]
    let bytesIn: Int64
    let bytesOut: Int64
    let date: Date
}

/// The last 30 conversions, stored in UserDefaults.
@MainActor
final class RecentStore: ObservableObject {
    private let key = "recents"
    private let limit = 30
    @Published private(set) var items: [RecentItem] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([RecentItem].self, from: data) {
            items = saved
        }
    }

    func add(_ job: ConversionJob) {
        guard job.state == .done, !job.outputs.isEmpty else { return }
        let item = RecentItem(title: job.title, inputNames: job.request.inputs.map(\.lastPathComponent),
                              outputs: job.outputs, bytesIn: job.bytesIn, bytesOut: job.bytesOut, date: Date())
        items.insert(item, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    /// Drops items whose files are gone (moved, deleted or undone).
    func prune() {
        items.removeAll { item in !item.outputs.contains { FileManager.default.fileExists(atPath: $0.path) } }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
