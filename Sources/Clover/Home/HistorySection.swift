import AppKit
import SwiftUI

/// The words and numbers in a History row.
enum HistoryFormat {
    /// "3.4 MB → 1.2 MB", and "64 % smaller" under it. The second part is nil when a size is unknown.
    static func sizeChange(_ item: RecentItem) -> (sizes: String, change: String?) {
        let out = ByteCountFormatter.string(fromByteCount: item.bytesOut, countStyle: .file)
        guard item.bytesIn > 0, item.bytesOut > 0 else { return (out, nil) }
        let input = ByteCountFormatter.string(fromByteCount: item.bytesIn, countStyle: .file)
        let change = Double(item.bytesIn - item.bytesOut) / Double(item.bytesIn) * 100
        let percent = Int(abs(change).rounded())
        let words = percent < 1 ? "Same size" : "\(percent) % \(change > 0 ? "smaller" : "larger")"
        return ("\(input) → \(out)", words)
    }

    /// What the conversion was: "Convert to JPG", or "Convert to PNG · 12 files".
    static func what(_ item: RecentItem) -> String {
        let count = max(item.inputNames.count, item.inputs?.count ?? 0)
        return count > 1 ? "\(item.title) · \(count) files" : item.title
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// "Today", "Yesterday", "12 Oct 2026".
    static func day(_ date: Date) -> String { dateFormatter.string(from: date) }

    /// "2:32 PM".
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// "Today, 2:32 PM".
    static func date(_ date: Date) -> String { "\(day(date)), \(time(date))" }

    /// Whether a search matches the item's names, its title or its date.
    static func matches(_ item: RecentItem, _ query: String) -> Bool {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = (item.outputs.map(\.lastPathComponent) + item.inputNames + [item.title, date(item.date)])
            .joined(separator: "\n")
        return words.allSatisfy { haystack.localizedStandardContains($0) }
    }

    /// One sentence for VoiceOver.
    static func spoken(_ item: RecentItem) -> String {
        let name = RecentFormat.outputName(item)
        let more = name.more > 0 ? " and \(name.more) more" : ""
        let size = sizeChange(item)
        return "\(name.first)\(more), \(what(item)), \(size.sizes)\(size.change.map { ", " + $0 } ?? ""), \(date(item.date))"
    }
}

/// History: every conversion Clover has made, newest first.
struct HistorySection: View {
    let items: [RecentItem]
    let actions: DashboardActions
    @State private var query: String
    @State private var selection: UUID?
    @State private var confirmClear = false

    init(items: [RecentItem], actions: DashboardActions, initialQuery: String = "") {
        self.items = items
        self.actions = actions
        _query = State(initialValue: initialQuery)
    }

    private var shown: [RecentItem] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? items : items.filter { HistoryFormat.matches($0, query) }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No conversions yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Files you convert show up here, so you can open them, find them again or convert them once more.")
                }
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ZStack {
                        if shown.isEmpty {
                            ContentUnavailableView.search(text: query)
                        } else {
                            list
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $query, prompt: "Search history")
        .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
            Button("Clear All", role: .destructive, action: actions.clearAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This takes \(items.count) \(items.count == 1 ? "item" : "items") off the list. The converted files stay where they are.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(countText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Clear All…") { confirmClear = true }
                .help("Take every conversion off this list")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var countText: String {
        let total = "\(items.count) \(items.count == 1 ? "conversion" : "conversions")"
        return shown.count == items.count ? total : "\(shown.count) of \(total)"
    }

    // MARK: List

    private var list: some View {
        List(shown, selection: $selection) { item in
            HistoryRow(item: item, actions: actions)
                .tag(item.id)
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: UUID.self) { ids in
            let picked = shown.filter { ids.contains($0.id) }
            if let item = picked.first, picked.count == 1 {
                HistoryMenu(item: item, actions: actions)
            }
        } primaryAction: { ids in
            if let item = shown.first(where: { ids.contains($0.id) }) { actions.open(item) }
        }
        .onDeleteCommand {
            if let item = shown.first(where: { $0.id == selection }) { actions.remove(item) }
        }
    }
}

/// The actions for one conversion, as menu items.
private struct HistoryMenu: View {
    let item: RecentItem
    let actions: DashboardActions

    var body: some View {
        let state = HistoryFiles(item)
        Button("Show in Finder") { actions.reveal(item) }
            .disabled(!state.outputsExist)
        Button("Open") { actions.open(item) }
            .disabled(!state.outputsExist)
        Button("Convert Again") { actions.convertAgain(item) }
            .disabled(!state.canConvertAgain)
        Divider()
        Button("Remove from History") { actions.remove(item) }
    }
}

/// Which of a conversion's files are still on disk.
private struct HistoryFiles {
    let outputsExist: Bool
    let canConvertAgain: Bool

    init(_ item: RecentItem) {
        let fm = FileManager.default
        outputsExist = item.outputs.contains { fm.fileExists(atPath: $0.path) }
        if let inputs = item.inputs, !inputs.isEmpty {
            canConvertAgain = inputs.allSatisfy { fm.fileExists(atPath: $0.path) }
        } else {
            canConvertAgain = false
        }
    }
}

/// One conversion: thumbnail, names, what it was, size change, date and actions.
private struct HistoryRow: View {
    let item: RecentItem
    let actions: DashboardActions

    var body: some View {
        let name = RecentFormat.outputName(item)
        let size = HistoryFormat.sizeChange(item)
        let state = HistoryFiles(item)
        HStack(spacing: 12) {
            ThumbnailView(url: item.outputs.first)
                .opacity(state.outputsExist ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(name.first)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if name.more > 0 {
                        Text(" + \(name.more) more")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(state.outputsExist ? .primary : .secondary)
                Text(state.outputsExist ? HistoryFormat.what(item) : "Moved or deleted")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(size.sizes)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if let change = size.change {
                    Text(change)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .monospacedDigit()
            .frame(width: 122, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(HistoryFormat.day(item.date))
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(HistoryFormat.time(item.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .monospacedDigit()
            .frame(width: 88, alignment: .leading)
            HStack(spacing: 2) {
                IconButton(symbol: "folder", help: "Show in Finder", label: "Show in Finder") { actions.reveal(item) }
                    .disabled(!state.outputsExist)
                IconButton(symbol: "arrow.triangle.2.circlepath", help: state.canConvertAgain ? "Convert again" : "The original files are gone", label: "Convert again") { actions.convertAgain(item) }
                    .disabled(!state.canConvertAgain)
                Menu {
                    HistoryMenu(item: item, actions: actions)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
                .accessibilityLabel("More actions")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(HistoryFormat.spoken(item))
    }
}

/// A small borderless button with just a symbol.
private struct IconButton: View {
    let symbol: String
    let help: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(label)
    }
}
