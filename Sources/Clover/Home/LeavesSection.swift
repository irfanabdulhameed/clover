import SwiftUI
import CloverCore

/// The steps behind the leaf editor, apart from the views.
enum LeafEditing {
    /// One row of the list: a target, or the "In More" divider.
    enum Row: Identifiable {
        case target(Target)
        case more

        var id: String {
            switch self {
            case .target(let target): target.id
            case .more: "in-more"
            }
        }

        var targetID: String? {
            if case .target(let target) = self { return target.id }
            return nil
        }
    }

    /// Every target in the user's order, hidden ones included. Follows the same order rule
    /// as `LeafArranger`, so the list matches the clover.
    static func ordered(_ targets: [Target], layout: LeafLayout) -> [Target] {
        targets.enumerated().sorted { a, b in
            let ia = layout.order.firstIndex(of: a.element.id) ?? Int.max
            let ib = layout.order.firstIndex(of: b.element.id) ?? Int.max
            return ia == ib ? a.offset < b.offset : ia < ib
        }.map(\.element)
    }

    /// The ordered targets with the "In More" divider after the fifth visible one, but only
    /// when more than six are visible. With six or fewer, everything is a leaf.
    static func rows(_ ordered: [Target], hidden: Set<String>) -> [Row] {
        var rows = ordered.map(Row.target)
        let visible = ordered.filter { !hidden.contains($0.id) }
        guard visible.count > LeafArranger.maxLeaves else { return rows }
        var seen = 0
        for (index, target) in ordered.enumerated() where !hidden.contains(target.id) {
            seen += 1
            if seen == LeafArranger.maxLeaves - 1 {
                rows.insert(.more, at: index + 1)
                break
            }
        }
        return rows
    }

    /// The target ids in their new order after a drag. The divider is only a marker, so it is left out.
    static func moved(_ rows: [Row], from offsets: IndexSet, to destination: Int) -> [String] {
        var list = rows
        list.move(fromOffsets: offsets, toOffset: destination)
        return list.compactMap(\.targetID)
    }

    /// The ids with one moved up or down by a step, for the keyboard and VoiceOver.
    static func shifted(_ ids: [String], _ id: String, by step: Int) -> [String] {
        guard let index = ids.firstIndex(of: id) else { return ids }
        let target = index + step
        guard ids.indices.contains(target) else { return ids }
        var list = ids
        list.swapAt(index, target)
        return list
    }

    /// The layout in its smallest form: the default order and no changes become "no layout".
    static func normalized(_ layout: LeafLayout, defaultOrder: [String]) -> LeafLayout? {
        var result = layout
        if result.order == defaultOrder { result.order = [] }
        return result == LeafLayout() ? nil : result
    }
}

/// Leaves: arrange the clover for each kind of file.
struct LeavesSection: View {
    let catalog: Catalog
    @Binding var layouts: [LayoutKey: LeafLayout]
    @State private var key: LayoutKey
    @State private var selected: String?
    @State private var hovered: String?
    @State private var memo = TargetMemo()

    init(catalog: Catalog, layouts: Binding<[LayoutKey: LeafLayout]>, forced: DashboardForced = DashboardForced()) {
        self.catalog = catalog
        _layouts = layouts
        _key = State(initialValue: forced.leafKey ?? .image)
        _selected = State(initialValue: forced.leafSelected)
        _hovered = State(initialValue: forced.leafHovered)
    }

    /// Finding every target for a kind of file isn't free, so each kind is worked out once.
    private final class TargetMemo {
        var cache: [LayoutKey: [Target]] = [:]

        func targets(_ catalog: Catalog, _ key: LayoutKey) -> [Target] {
            if let hit = cache[key] { return hit }
            let found = catalog.allTargets(for: key)
            cache[key] = found
            return found
        }
    }

    private var layout: LeafLayout { layouts[key] ?? LeafLayout() }
    private var allTargets: [Target] { memo.targets(catalog, key) }
    private var ordered: [Target] { LeafEditing.ordered(allTargets, layout: layout) }
    private var rows: [LeafEditing.Row] { LeafEditing.rows(ordered, hidden: layout.hidden) }
    private var visibleCount: Int { ordered.filter { !layout.hidden.contains($0.id) }.count }
    private var arrangement: Arrangement { LeafArranger.arrange(allTargets, layout: layout) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GeometryReader { proxy in
                let previewWidth = min(320, max(210, proxy.size.width * 0.46))
                HStack(alignment: .top, spacing: 20) {
                    preview(width: previewWidth)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        list
                        Text("The menu on a row sets what happens when you drop a file straight on that leaf.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: key) { _, _ in
            selected = nil
            hovered = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Clover for", selection: $key) {
                ForEach(LayoutKey.allCases) { item in
                    Label(item.title, systemImage: Self.symbol(for: item)).tag(item)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Spacer()
            Button("Reset to Default") {
                layouts[key] = nil
                selected = nil
            }
            .disabled(layout == LeafLayout())
            .help("Put the leaves back in their original order")
        }
    }

    private static func symbol(for key: LayoutKey) -> String {
        switch key {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .document: "doc.text"
        case .video: "film"
        case .audio: "waveform"
        case .archive: "archivebox"
        case .mixed: "square.stack"
        }
    }

    /// What the list means right now.
    private var summary: String {
        if visibleCount > LeafArranger.maxLeaves {
            return "The first \(LeafArranger.maxLeaves - 1) sit on the clover. The other \(visibleCount - LeafArranger.maxLeaves + 1) are in More. Drag a row to reorder."
        }
        if visibleCount == 1 { return "Only one format sits on the clover." }
        return "All \(visibleCount) formats sit on the clover. Drag a row to reorder."
    }

    // MARK: Preview

    private func preview(width: CGFloat) -> some View {
        let scale = width / 320
        return CloverPreview(arrangement: arrangement, highlighted: hovered ?? selected)
            .frame(width: 320, height: 320)
            .scaleEffect(scale)
            .frame(width: width, height: width)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .accessibilityLabel("Preview of the clover for \(key.title)")
    }

    // MARK: List

    private var list: some View {
        let hiddenIDs = layout.hidden
        return List(selection: $selected) {
            ForEach(rows) { row in
                switch row {
                case .target(let target):
                    LeafRowView(
                        target: target,
                        isHidden: hiddenIDs.contains(target.id),
                        canHide: visibleCount > 1 || hiddenIDs.contains(target.id),
                        option: currentOption(for: target),
                        onHidden: { setHidden($0, for: target) },
                        onOption: { setOption($0, for: target) })
                    .tag(target.id)
                    .onHover { inside in
                        if inside { hovered = target.id } else if hovered == target.id { hovered = nil }
                    }
                    .contextMenu { rowMenu(for: target) }
                    .accessibilityAction(named: "Move Up") { shift(target, by: -1) }
                    .accessibilityAction(named: "Move Down") { shift(target, by: 1) }
                case .more:
                    MoreDivider()
                        .moveDisabled(true)
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                }
            }
            .onMove { offsets, destination in
                setOrder(LeafEditing.moved(rows, from: offsets, to: destination))
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: false))
        .frame(minHeight: 120, maxHeight: CGFloat(rows.count) * 38 + 4)
    }

    @ViewBuilder private func rowMenu(for target: Target) -> some View {
        let hidden = layout.hidden.contains(target.id)
        Button("Move Up") { shift(target, by: -1) }
        Button("Move Down") { shift(target, by: 1) }
        Divider()
        Button(hidden ? "Show on Clover" : "Hide from Clover") { setHidden(!hidden, for: target) }
            .disabled(!hidden && visibleCount <= 1)
    }

    // MARK: Changes

    /// Applies a change to this kind's layout, and stores nothing when it is back to the default.
    private func update(_ change: (inout LeafLayout) -> Void) {
        var new = layout
        change(&new)
        layouts[key] = LeafEditing.normalized(new, defaultOrder: allTargets.map(\.id))
    }

    private func setOrder(_ ids: [String]) {
        update { $0.order = ids }
    }

    private func shift(_ target: Target, by step: Int) {
        setOrder(LeafEditing.shifted(ordered.map(\.id), target.id, by: step))
    }

    private func setHidden(_ hide: Bool, for target: Target) {
        update { layout in
            if hide { layout.hidden.insert(target.id) } else { layout.hidden.remove(target.id) }
        }
    }

    /// The option a drop straight on the leaf uses: the user's pick, or the target's own default.
    private func currentOption(for target: Target) -> Option? {
        if let id = layout.defaultOptions[target.id], let option = target.options.first(where: { $0.id == id }) {
            return option
        }
        return target.defaultOption
    }

    private func setOption(_ option: Option, for target: Target) {
        update { layout in
            if option.id == target.defaultOption?.id {
                layout.defaultOptions[target.id] = nil
            } else {
                layout.defaultOptions[target.id] = option.id
            }
        }
    }
}

/// One target in the list: grip, name, default option and the eye.
private struct LeafRowView: View {
    let target: Target
    let isHidden: Bool
    let canHide: Bool
    let option: Option?
    let onHidden: (Bool) -> Void
    let onOption: (Option) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                Text(target.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if target.title != target.format.name {
                    Text(target.format.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .opacity(isHidden ? 0.45 : 1)
            Spacer(minLength: 6)
            if target.options.count > 1, let option {
                Picker("Default for \(target.title)", selection: Binding(get: { option }, set: onOption)) {
                    ForEach(target.options) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
                .disabled(isHidden)
                .help("What a drop straight on this leaf uses")
            }
            Button {
                onHidden(!isHidden)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(isHidden ? .tertiary : .secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!canHide)
            .help(!canHide ? "Keep at least one leaf on the clover" : isHidden ? "Show \(target.title) on the clover" : "Hide \(target.title) from the clover")
            .accessibilityLabel(isHidden ? "Show \(target.title)" : "Hide \(target.title)")
        }
        .frame(height: 30)
        .accessibilityElement(children: .contain)
    }
}

/// The line between the leaves and the formats behind More.
private struct MoreDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Text("In More")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            line
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Formats below this line are in More")
    }

    private var line: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.25))
            .frame(height: 1)
    }
}
