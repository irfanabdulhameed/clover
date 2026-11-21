import SwiftUI

/// The Dashboard's first page: drop files to convert, what Clover did this week, the last
/// few conversions, and anything that needs attention.
struct DashboardHome: View {
    let items: [RecentItem]
    let engines: [EngineInfo]
    let trigger: TriggerKey
    let actions: DashboardActions
    /// Shows another page.
    let go: (DashboardSection) -> Void
    /// For renders: a fixed "now", so the week's numbers don't depend on the day.
    var now: Date? = nil

    private static let recentCount = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DropZone(onChoose: actions.chooseFiles, onDrop: actions.filesDropped)
                if !missing.isEmpty { enginesNotice }
                stats
                recent
                about
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: This week

    private struct Week {
        var conversions = 0
        var files = 0
        var saved: Int64 = 0
    }

    private var week: Week {
        let since = (now ?? Date()).addingTimeInterval(-7 * 24 * 3600)
        var week = Week()
        for item in items where item.date >= since {
            week.conversions += 1
            week.files += item.outputs.count
            week.saved += item.bytesIn - item.bytesOut
        }
        return week
    }

    private var stats: some View {
        let w = week
        let saved = w.saved >= 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.headline)
            HStack(spacing: 10) {
                StatTile(value: "\(w.files)", label: w.files == 1 ? "file made" : "files made", symbol: "doc.on.doc")
                StatTile(value: "\(w.conversions)", label: w.conversions == 1 ? "conversion" : "conversions", symbol: "arrow.triangle.2.circlepath")
                StatTile(value: ByteCountFormatter.string(fromByteCount: abs(w.saved), countStyle: .file),
                         label: saved ? "space saved" : "larger than the originals",
                         symbol: saved ? "arrow.down.circle" : "arrow.up.circle")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Recent

    private var homeActions: HomeActions {
        HomeActions(chooseFiles: actions.chooseFiles, filesDropped: actions.filesDropped,
                    reveal: actions.reveal, open: actions.open, remove: actions.remove,
                    clearAll: actions.clearAll, refreshTools: actions.refreshTools,
                    openDashboard: {}, quit: {})
    }

    @ViewBuilder private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.headline)
                Spacer()
                if items.count > Self.recentCount {
                    Button("Show All \(items.count)") { go(.history) }
                        .buttonStyle(.link)
                }
            }
            if items.isEmpty {
                EmptyHint(trigger: trigger)
                    .frame(maxWidth: .infinity)
                    .background(panel)
            } else {
                VStack(spacing: 0) {
                    ForEach(items.prefix(Self.recentCount)) { item in
                        RecentRow(item: item, actions: homeActions)
                    }
                }
                .padding(4)
                .background(panel)
            }
        }
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: Version

    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        return "Clover \(short)"
    }

    private var about: some View {
        HStack(spacing: 8) {
            Text(version)
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Button("Check for Updates", action: actions.checkForUpdates)
                .buttonStyle(.link)
            Spacer()
        }
        .font(.callout)
    }

    // MARK: Attention

    private var missing: [EngineInfo] { engines.filter { !$0.found } }

    private var enginesNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(missing.count == 1 ? "\(missing[0].name) isn't installed" : "\(missing.count) engines aren't installed")
                    .font(.system(size: 13, weight: .semibold))
                Text("Some conversions are off until \(missing.count == 1 ? "it is" : "they are") installed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Show Engines") { go(.general) }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
    }
}

/// One number for the week, with what it counts.
private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        )
        .accessibilityElement(children: .combine)
    }
}
