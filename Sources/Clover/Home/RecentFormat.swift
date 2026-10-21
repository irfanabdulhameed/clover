import Foundation
import CloverCore

/// The words in a Recent row.
enum RecentFormat {
    /// The first output's name, and how many more outputs there are: ("photo.jpg", 11).
    static func outputName(_ item: RecentItem) -> (first: String, more: Int) {
        let first = item.outputs.first?.lastPathComponent ?? item.title
        return (first, max(0, item.outputs.count - 1))
    }

    /// "1.2 MB · 64 % smaller".
    static func sizeLine(_ item: RecentItem) -> String {
        let size = ByteCountFormatter.string(fromByteCount: item.bytesOut, countStyle: .file)
        guard item.bytesIn > 0, item.bytesOut > 0 else { return size }
        let change = Double(item.bytesIn - item.bytesOut) / Double(item.bytesIn) * 100
        let percent = Int(abs(change).rounded())
        if percent < 1 { return "\(size) · same size" }
        return "\(size) · \(percent) % \(change > 0 ? "smaller" : "larger")"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        f.unitsStyle = .short
        return f
    }()

    /// "Just now", "5 min. ago", "yesterday".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 45 { return "Just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// One sentence for VoiceOver.
    static func spoken(_ item: RecentItem) -> String {
        let name = outputName(item)
        let more = name.more > 0 ? " and \(name.more) more" : ""
        return "\(name.first)\(more), \(sizeLine(item)), \(relativeTime(item.date))"
    }
}
