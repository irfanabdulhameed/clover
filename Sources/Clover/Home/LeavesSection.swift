import SwiftUI
import CloverCore

/// The steps behind the leaf editor, apart from the views.
enum LeafEditing {
    /// The three parts of the list.
    enum Group: String {
        case clover, more, hidden

        var title: String {
            switch self {
            case .clover: "On the clover"
            case .more: "In More"
            case .hidden: "Hidden"
            }
        }
    }

    /// Where a target sits: on the clover (1 is 12 o'clock), behind More, or hidden.
    enum Place: Equatable {
        case clover(Int)
        case more
        case hidden

        var group: Group {
            switch self {
            case .clover: .clover
            case .more: .more
            case .hidden: .hidden
            }
        }
    }

    /// A quiet line in the list.
    enum Note: Equatable {
        /// Every visible format fits on the clover, so there is no More leaf.
        case allFit(Int)
        /// Every format is hidden.
        case allHidden
        /// The Hidden part is open but holds nothing.
        case noneHidden
    }

    /// One row of the list: a part's header, a target, or a note. Headers and notes are
    /// fixed; only targets move.
    enum Row: Identifiable, Equatable {
        case header(Group, count: Int)
        case target(Target, Place)
        case note(Note)

        var id: String {
            switch self {
            case .header(let group, _): "header-\(group.rawValue)"
            case .target(let target, _): target.id
            case .note(let note): "note-\(note)"
            }
        }

        var targetID: String? {
            if case .target(let target, _) = self { return target.id }
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

    /// How many visible targets sit on the clover: all of them up to six, else five and More.
    static func cloverCount(visible: Int) -> Int {
        visible > LeafArranger.maxLeaves ? LeafArranger.maxLeaves - 1 : visible
    }

    /// The list: "On the clover" with its leaves, "In More" when more than six are
    /// visible (or a note that everything fits), and "Hidden", whose rows show only when
    /// `showHidden`. It is one list underneath, so a drag can cross the parts.
    static func rows(_ ordered: [Target], hidden: Set<String>, showHidden: Bool) -> [Row] {
        let visible = ordered.filter { !hidden.contains($0.id) }
        let hiddenTargets = ordered.filter { hidden.contains($0.id) }
        let onClover = cloverCount(visible: visible.count)
        var rows: [Row] = [.header(.clover, count: onClover)]
        if visible.isEmpty { rows.append(.note(.allHidden)) }
        for (index, target) in visible.prefix(onClover).enumerated() {
            rows.append(.target(target, .clover(index + 1)))
        }
        if visible.count > onClover {
            rows.append(.header(.more, count: visible.count - onClover))
            rows += visible.dropFirst(onClover).map { .target($0, .more) }
        } else if !visible.isEmpty {
            rows.append(.note(.allFit(visible.count)))
        }
        rows.append(.header(.hidden, count: hiddenTargets.count))
        if showHidden {
            rows += hiddenTargets.map { .target($0, .hidden) }
            if hiddenTargets.isEmpty { rows.append(.note(.noneHidden)) }
        }
        return rows
    }

    /// After a drag, read from where every row landed: the new order (visible ones first,
    /// then hidden ones) and which are hidden. A row dropped under "Hidden" is hidden; one
    /// dragged out of it is shown. `folded` are hidden ids not in the list (Hidden closed).
    /// Nil when the drag would hide every format.
    static func moved(_ rows: [Row], from offsets: IndexSet, to destination: Int, folded: [String]) -> (order: [String], hidden: Set<String>)? {
        var list = rows
        list.move(fromOffsets: offsets, toOffset: destination)
        var shown: [String] = []
        var hidden: [String] = []
        var inHidden = false
        for row in list {
            switch row {
            case .header(let group, _): inHidden = group == .hidden
            case .target(let target, _): if inHidden { hidden.append(target.id) } else { shown.append(target.id) }
            case .note: break
            }
        }
        hidden += folded.filter { !hidden.contains($0) && !shown.contains($0) }
        guard !shown.isEmpty else { return nil }
        return (shown + hidden, Set(hidden))
    }

    /// Where each target sits now.
    static func places(_ ordered: [Target], hidden: Set<String>) -> [String: Place] {
        let visible = ordered.filter { !hidden.contains($0.id) }
        let onClover = cloverCount(visible: visible.count)
        var places: [String: Place] = [:]
        for (index, target) in visible.enumerated() { places[target.id] = index < onClover ? .clover(index + 1) : .more }
        for target in ordered where hidden.contains(target.id) { places[target.id] = .hidden }
        return places
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

    /// Honest notes for targets that only some files of this kind get: "from GIF" for a
    /// target only one or two formats make, "several files" for one that needs more than
    /// one file (Merge, One PDF).
    static func notes(_ catalog: Catalog, key: LayoutKey, targets: [Target]) -> [String: String] {
        guard key != .mixed else { return [:] }
        let formats = Formats.all.filter { $0.family.rawValue == key.rawValue }
        var makers: [String: [Format]] = [:]
        for format in formats {
            for target in catalog.targets(forFormats: [format]) { makers[target.id, default: []].append(format) }
        }
        var notes: [String: String] = [:]
        for target in targets {
            let from = makers[target.id] ?? []
            if from.isEmpty {
                notes[target.id] = "several files"
            } else if from.count < formats.count, from.count <= 2 {
                notes[target.id] = "from " + from.map(\.name).joined(separator: ", ")
            }
        }
        return notes
    }
}

/// Leaves: arrange the clover for each kind of file. A segmented control picks the kind;
/// the live clover sits on a soft backdrop beside a list in three parts: the leaves on the
/// clover, the formats in More, and the hidden ones.
struct LeavesSection: View {
    let catalog: Catalog
    @Binding var layouts: [LayoutKey: LeafLayout]
    @Binding var glassTint: GlassTint
    /// No wave on the preview when motion is reduced.
    var reduceMotion = false
    @State private var key: LayoutKey
    @State private var selected: String?
    @State private var hovered: String?
    @State private var showHidden: Bool
    @State private var confirmingReset = false
    @State private var memo = TargetMemo()

    init(catalog: Catalog, layouts: Binding<[LayoutKey: LeafLayout]>, glassTint: Binding<GlassTint>,
         reduceMotion: Bool = false, forced: DashboardForced = DashboardForced()) {
        self.catalog = catalog
        _layouts = layouts
        _glassTint = glassTint
        self.reduceMotion = reduceMotion
        _key = State(initialValue: forced.leafKey ?? .image)
        _selected = State(initialValue: forced.leafSelected)
        _hovered = State(initialValue: forced.leafHovered)
        _showHidden = State(initialValue: forced.leafShowHidden)
    }

    /// Finding every target for a kind of file, and its notes, isn't free, so each kind is
    /// worked out once.
    private final class TargetMemo {
        var targets: [LayoutKey: [Target]] = [:]
        var notes: [LayoutKey: [String: String]] = [:]

        func targets(_ catalog: Catalog, _ key: LayoutKey) -> [Target] {
            if let hit = targets[key] { return hit }
            let found = catalog.allTargets(for: key)
            targets[key] = found
            return found
        }

        func notes(_ catalog: Catalog, _ key: LayoutKey) -> [String: String] {
            if let hit = notes[key] { return hit }
            let found = LeafEditing.notes(catalog, key: key, targets: targets(catalog, key))
            notes[key] = found
            return found
        }
    }

    private var layout: LeafLayout { layouts[key] ?? LeafLayout() }
    private var allTargets: [Target] { memo.targets(catalog, key) }
    private var ordered: [Target] { LeafEditing.ordered(allTargets, layout: layout) }
    private var rows: [LeafEditing.Row] { LeafEditing.rows(ordered, hidden: layout.hidden, showHidden: showHidden) }
    private var places: [String: LeafEditing.Place] { LeafEditing.places(ordered, hidden: layout.hidden) }
    private var visibleCount: Int { ordered.filter { !layout.hidden.contains($0.id) }.count }
    private var arrangement: Arrangement { LeafArranger.arrange(allTargets, layout: layout) }

    /// The list keeps at least this much room; the preview takes the rest, up to 300 pt.
    private static let listMinWidth: CGFloat = 300
    private static let previewMaxWidth: CGFloat = 300
    private static let previewMinWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GeometryReader { proxy in
                let column = min(LeavesSection.previewMaxWidth,
                                 max(LeavesSection.previewMinWidth, proxy.size.width - LeavesSection.listMinWidth - 18))
                HStack(alignment: .top, spacing: 18) {
                    previewColumn(width: column)
                    list
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: key) { _, _ in
            selected = nil
            hovered = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            // Labels when they fit; icons with tooltips at the narrowest window.
            ViewThatFits(in: .horizontal) {
                kindPicker(labels: true)
                kindPicker(labels: false)
            }
            Spacer(minLength: 8)
            Button {
                confirmingReset = true
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(layout == LeafLayout())
            .help("Put the \(key.title.lowercased()) clover back as it was")
            .popover(isPresented: $confirmingReset, arrowEdge: .bottom) {
                ResetConfirmation(kind: key.title, onReset: {
                    layouts[key] = nil
                    selected = nil
                    confirmingReset = false
                }, onCancel: { confirmingReset = false })
            }
        }
    }

    private func kindPicker(labels: Bool) -> some View {
        KindSegments(selection: $key, showsLabels: labels)
            .fixedSize()
    }

    static func symbol(for key: LayoutKey) -> String {
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

    static func shortTitle(for key: LayoutKey) -> String {
        switch key {
        case .image: "Images"
        case .pdf: "PDF"
        case .document: "Docs"
        case .video: "Video"
        case .audio: "Audio"
        case .archive: "Archives"
        case .mixed: "Mixed"
        }
    }

    // MARK: Preview

    private func previewColumn(width: CGFloat) -> some View {
        let side = width - 28
        return VStack(spacing: 10) {
            ZStack {
                PreviewBackdrop()
                CloverPreview(arrangement: arrangement, highlighted: hovered ?? selected,
                              playsWave: !reduceMotion,
                              onLeaf: { id in
                                  guard let id else { return }
                                  selected = id
                              },
                              onHover: { id in hovered = id })
                    .frame(width: CloverPreview.side, height: CloverPreview.side)
                    .scaleEffect(side / CloverPreview.side)
                    .frame(width: side, height: side)
            }
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Preview of the clover for \(key.title)")
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width)
                .accessibilityLabel(caption)
            VStack(alignment: .leading, spacing: 6) {
                Text("Glass tint")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                // Full size when it fits, smaller swatches in the narrowest window.
                ViewThatFits(in: .horizontal) {
                    TintPicker(tint: $glassTint)
                    TintPicker(tint: $glassTint, compact: true)
                }
                .frame(width: width, alignment: .leading)
            }
            .padding(.top, 6)
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width)
    }

    /// One line about the hovered or selected leaf, or the whole clover.
    private var caption: String {
        guard let id = hovered ?? selected, let target = ordered.first(where: { $0.id == id }), let place = places[id] else {
            let counts = rows.compactMap { row -> String? in
                guard case .header(let group, let count) = row, count > 0 else { return nil }
                switch group {
                case .clover: return "\(count) on the clover"
                case .more: return "\(count) in More"
                case .hidden: return "\(count) hidden"
                }
            }
            return counts.joined(separator: " · ")
        }
        var parts = [target.title]
        switch place {
        case .clover(let position): parts.append("leaf \(position)")
        case .more: parts.append("in More")
        case .hidden: parts.append("hidden")
        }
        if place != .hidden, target.options.count > 1, let option = currentOption(for: target) {
            parts.append("drops as \(option.title)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: List

    private var list: some View {
        let notes = memo.notes(catalog, key)
        let hiddenIDs = layout.hidden
        let canHideMore = visibleCount > 1
        return ScrollViewReader { proxy in
            List(selection: $selected) {
                ForEach(rows) { row in
                    switch row {
                    case .header(let group, let count):
                        GroupHeader(group: group, count: count, expanded: showHidden) {
                            withAnimation(.easeOut(duration: 0.18)) { showHidden.toggle() }
                        }
                        .moveDisabled(true)
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                    case .target(let target, let place):
                        LeafRowView(
                            target: target,
                            place: place,
                            note: notes[target.id],
                            canHide: canHideMore || hiddenIDs.contains(target.id),
                            option: currentOption(for: target),
                            onHidden: { setHidden($0, for: target) },
                            onOption: { setOption($0, for: target) })
                        .tag(target.id)
                        .id(target.id)
                        .onHover { inside in
                            if inside { hovered = target.id } else if hovered == target.id { hovered = nil }
                        }
                        .contextMenu { rowMenu(for: target) }
                        .accessibilityAction(named: "Move Up") { shift(target, by: -1) }
                        .accessibilityAction(named: "Move Down") { shift(target, by: 1) }
                    case .note(let note):
                        NoteRow(note: note, onShowAll: { update { $0.hidden = [] } })
                            .moveDisabled(true)
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                    }
                }
                .onMove { offsets, destination in
                    let folded = showHidden ? [] : ordered.filter { hiddenIDs.contains($0.id) }.map(\.id)
                    guard let result = LeafEditing.moved(rows, from: offsets, to: destination, folded: folded) else { return }
                    update { layout in
                        layout.order = result.order
                        layout.hidden = result.hidden
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .onChange(of: selected) { _, id in
                // A leaf picked in the preview: show its row.
                guard let id else { return }
                if places[id] == .hidden, !showHidden { showHidden = true }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
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

    /// The order as the list shows it: visible ones, then hidden ones.
    private var listedIDs: [String] {
        let visible = ordered.filter { !layout.hidden.contains($0.id) }
        let hidden = ordered.filter { layout.hidden.contains($0.id) }
        return (visible + hidden).map(\.id)
    }

    private func shift(_ target: Target, by step: Int) {
        let ids = LeafEditing.shifted(listedIDs, target.id, by: step)
        update { $0.order = ids }
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

// MARK: - Parts

/// A soft, wallpaper-like backdrop for the preview, so its glass has something to show.
private struct PreviewBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark
                           ? [Color(red: 0.16, green: 0.21, blue: 0.32), Color(red: 0.22, green: 0.18, blue: 0.32), Color(red: 0.30, green: 0.19, blue: 0.27)]
                           : [Color(red: 0.80, green: 0.87, blue: 0.96), Color(red: 0.89, green: 0.86, blue: 0.95), Color(red: 0.97, green: 0.89, blue: 0.84)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(dark ? 0.08 : 0.35), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.25, y: 0.2), startRadius: 0, endRadius: 220)
        }
    }
}

/// A part's header in the list: its name, its count, and for Hidden a disclosure chevron.
private struct GroupHeader: View {
    let group: LeafEditing.Group
    let count: Int
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if group == .hidden {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
            }
            Text(group.title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .padding(.top, group == .clover ? 0 : 6)
        .contentShape(Rectangle())
        .onTapGesture { if group == .hidden { onToggle() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.title), \(count)")
        .accessibilityAddTraits(group == .hidden ? .isButton : .isHeader)
        .accessibilityHint(group == .hidden ? (expanded ? "Hides the hidden formats" : "Shows the hidden formats") : "")
        .help(group == .hidden ? (expanded ? "Fold the hidden formats away" : "Show the hidden formats") : "")
    }
}

/// A quiet line in the list.
private struct NoteRow: View {
    let note: LeafEditing.Note
    let onShowAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if note == .allHidden {
                Button("Show All", action: onShowAll)
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        // Under the names, except the everything-hidden message, which needs the room.
        .padding(.leading, note == .allHidden ? 4 : 60)
        .padding(.vertical, 4)
    }

    private var text: String {
        switch note {
        case .allFit(let count): count == 1 ? "Only this one is on the clover." : "All \(count) fit on the clover, so there is no More leaf."
        case .allHidden: "Every format is hidden, so these files get an empty clover."
        case .noneHidden: "Nothing hidden. Drag a row here, or use its eye, to hide it."
        }
    }
}

/// The Reset confirmation, as a small popover under the button.
private struct ResetConfirmation: View {
    let kind: String
    let onReset: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reset the \(kind.lowercased()) clover?")
                .font(.headline)
            Text("Every format goes back to its first place, hidden ones come back, and drops use their usual option.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Reset", role: .destructive, action: onReset)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 290)
    }
}

/// One target in the list: grip, position on the clover, family icon, name and note, the
/// option a drop uses, and the eye.
private struct LeafRowView: View {
    let target: Target
    let place: LeafEditing.Place
    let note: String?
    let canHide: Bool
    let option: Option?
    let onHidden: (Bool) -> Void
    let onOption: (Option) -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.backgroundProminence) private var prominence

    /// The option menu's column, the same width on every row so they line up.
    static let optionWidth: CGFloat = 84

    private var isHidden: Bool { place == .hidden }
    /// On a selected row the list's accent fills it: colours go white.
    private var onAccent: Bool { prominence == .increased }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 11)
                .opacity(hovering ? 1 : 0)
                .accessibilityHidden(true)
            // A hidden row dims its content; its eye, which brings it back, stays clear.
            HStack(spacing: 7) {
                PositionBadge(place: place, onAccent: onAccent)
                Image(systemName: BloomStyle.symbol(for: target))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(onAccent ? Color.white : BloomStyle.hue(target.format.family, scheme))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                // The title never shortens; the note gives way first.
                Text(target.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                if let detail {
                    // Shown whole or not at all: a lone "…" says nothing.
                    ViewThatFits(in: .horizontal) {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .padding(.leading, -3)
                }
            }
            .opacity(isHidden ? 0.5 : 1)
            Spacer(minLength: 2)
            optionMenu
                .frame(width: LeafRowView.optionWidth, alignment: .trailing)
            Button {
                onHidden(!isHidden)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!canHide)
            .help(!canHide ? "Keep at least one leaf on the clover" : isHidden ? "Show \(target.title) on the clover" : "Hide \(target.title) from the clover")
            .accessibilityLabel(isHidden ? "Show \(target.title)" : "Hide \(target.title)")
        }
        .frame(height: 34)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    /// The honest note ("from GIF", "several files"), or the format when the title is a
    /// verb ("Compress" makes a PDF).
    private var detail: String? {
        note ?? (target.title != target.format.name ? target.format.name : nil)
    }

    @ViewBuilder private var optionMenu: some View {
        if target.options.count > 1, let option {
            Menu {
                ForEach(target.options) { choice in
                    Button {
                        onOption(choice)
                    } label: {
                        if choice == option { Label(choice.title, systemImage: "checkmark") } else { Text(choice.title) }
                    }
                }
            } label: {
                Text(option.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(hovering && !isHidden ? 0.07 : 0))
            )
            .disabled(isHidden)
            .help("Drops as \(option.title): what a file dropped straight on this leaf uses")
            .accessibilityLabel("Drop on \(target.title) uses \(option.title)")
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private var accessibilityText: String {
        var text = target.title
        if let detail { text += ", \(detail)" }
        switch place {
        case .clover(let position): text += ", leaf \(position) on the clover"
        case .more: text += ", in More"
        case .hidden: text += ", hidden"
        }
        return text
    }
}

/// A leaf's place on the clover, 1 to 6; an empty slot of the same width for the rest, so
/// the columns line up.
private struct PositionBadge: View {
    let place: LeafEditing.Place
    let onAccent: Bool

    var body: some View {
        ZStack {
            if case .clover(let position) = place {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(onAccent ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.14))
                Text("\(position)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(onAccent ? Color.white : Color.accentColor)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// The file kinds as the Mac's own segmented control: each segment a symbol and a short
/// label, or the symbol alone (with its name as a tooltip) where labels don't fit.
private struct KindSegments: NSViewRepresentable {
    @Binding var selection: LayoutKey
    let showsLabels: Bool

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = LayoutKey.allCases.count
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        let symbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        for (index, key) in LayoutKey.allCases.enumerated() {
            let image = NSImage(systemSymbolName: LeavesSection.symbol(for: key), accessibilityDescription: key.title)?
                .withSymbolConfiguration(symbol)
            control.setImage(image, forSegment: index)
            control.setImageScaling(.scaleNone, forSegment: index)
            if showsLabels { control.setLabel(LeavesSection.shortTitle(for: key), forSegment: index) }
            control.setToolTip(key.title, forSegment: index)
        }
        control.setAccessibilityLabel("Kind of file")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if let index = LayoutKey.allCases.firstIndex(of: selection), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    final class Coordinator: NSObject {
        var selection: Binding<LayoutKey>

        init(selection: Binding<LayoutKey>) { self.selection = selection }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard LayoutKey.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = LayoutKey.allCases[sender.selectedSegment]
        }
    }
}
