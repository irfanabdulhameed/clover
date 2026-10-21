import AppKit
import CloverCore

/// Everything the clover shows, and what the pointer and the keys are doing to it.
/// Every change is instant: nothing here animates.
@MainActor
final class BloomModel: ObservableObject {
    enum Mode { case drag, click }

    /// What a leaf holds.
    enum Leaf: Equatable {
        case target(Target)
        case more
    }

    /// Keyboard focus: a leaf, or a pill in the More tray.
    enum Focus: Equatable {
        case leaf(Int)
        case pill(Int)
    }

    @Published private(set) var files: [URL] = []
    /// False while a drag hasn't reached the clover yet: the hub shows a placeholder.
    @Published private(set) var hasFiles = false
    @Published private(set) var arrangement = Arrangement(leaves: [], more: [])
    /// What the pointer is over on the clover.
    @Published private(set) var hover: BloomHit = .none
    /// The leaf whose chips are showing.
    @Published private(set) var openLeaf: Int?
    /// The More tray. The controller shows and hides its window.
    @Published private(set) var trayOpen = false {
        didSet { if trayOpen != oldValue { onTrayChange?(trayOpen) } }
    }
    /// What the pointer is over in the tray.
    @Published private(set) var trayHover: TrayHit = .none
    /// The pill whose chips are showing.
    @Published private(set) var openPill: Int?
    @Published private(set) var focus: Focus?
    /// One of the focused leaf's or pill's chips.
    @Published private(set) var focusChip: Int?
    /// True after a key press, until the pointer moves again.
    @Published private(set) var usingKeyboard = false
    /// Hub pictures for the first few files: icons first, thumbnails once loaded.
    @Published private(set) var pictures: [NSImage] = []
    @Published private(set) var thumbnailsLoaded = false

    var mode: Mode = .drag
    /// Rest on a leaf or a pill this long before its chips open, so sweeping doesn't flicker.
    var chipDelay: TimeInterval = 0.08
    /// Rest on More this long, during a drag, to open the tray.
    var moreDelay: TimeInterval = 0.3
    /// Called when the tray opens or closes.
    var onTrayChange: ((Bool) -> Void)?

    private var chipWidthCache: [String: [CGFloat]] = [:]
    private var chipTimer: DispatchWorkItem?
    private var moreTimer: DispatchWorkItem?
    private var thumbnailTask: Task<Void, Never>?
    private(set) var pillWidth: CGFloat = TrayLayout.pillMinWidth

    // MARK: Content

    func reset(mode: Mode) {
        cancelTimers()
        thumbnailTask?.cancel()
        self.mode = mode
        files = []
        hasFiles = false
        arrangement = Arrangement(leaves: [], more: [])
        chipWidthCache = [:]
        clearPointerAndFocus()
        pictures = []
        thumbnailsLoaded = false
    }

    /// The files, and the clover the user arranged for them (`AppModel.arrangement(for:)`).
    func setFiles(_ files: [URL], arrangement: Arrangement) {
        cancelTimers()
        self.files = files
        hasFiles = true
        self.arrangement = arrangement
        chipWidthCache = [:]
        pillWidth = TrayLayout.pillWidth(textWidths: arrangement.more.map { BloomStyle.textWidth($0.title, font: BloomStyle.pillFont) })
        clearPointerAndFocus()
        loadPictures()
    }

    /// The leaves clockwise from 12 o'clock; More last when some targets don't fit.
    var leaves: [Leaf] {
        arrangement.leaves.map(Leaf.target) + (arrangement.more.isEmpty ? [] : [.more])
    }

    var leafCount: Int { arrangement.leaves.count + (arrangement.more.isEmpty ? 0 : 1) }

    var moreIndex: Int? { arrangement.more.isEmpty ? nil : arrangement.leaves.count }

    func target(at leaf: Int) -> Target? {
        arrangement.leaves.indices.contains(leaf) ? arrangement.leaves[leaf] : nil
    }

    func isMore(_ leaf: Int) -> Bool { leaf == moreIndex }

    func pillTarget(_ pill: Int) -> Target? {
        arrangement.more.indices.contains(pill) ? arrangement.more[pill] : nil
    }

    /// Chip widths for a target, measured with the chip font.
    func chipWidths(for target: Target) -> [CGFloat] {
        if let cached = chipWidthCache[target.id] { return cached }
        let widths = target.options.map { option in
            BloomLayout.chipWidth(textWidth: BloomStyle.textWidth(option.title),
                                  isDefault: option.id == target.defaultOption?.id)
        }
        chipWidthCache[target.id] = widths
        return widths
    }

    func chipFrames(for leaf: Int) -> [CGRect] {
        guard let target = target(at: leaf) else { return [] }
        return BloomLayout.chipFrames(leaf, of: leafCount, widths: chipWidths(for: target))
    }

    // MARK: Tray geometry

    var traySize: CGSize {
        let widest = arrangement.more.map { TrayLayout.chipRowWidth(chipWidths(for: $0)) }.max() ?? 0
        return TrayLayout.size(count: arrangement.more.count, pillWidth: pillWidth, chipRow: widest)
    }

    var pillFrames: [CGRect] {
        TrayLayout.pillFrames(count: arrangement.more.count, pillWidth: pillWidth, trayWidth: traySize.width)
    }

    func pillChipFrames(for pill: Int) -> [CGRect] {
        guard let target = pillTarget(pill) else { return [] }
        let frames = pillFrames
        return TrayLayout.chipFrames(under: frames[pill], widths: chipWidths(for: target), trayWidth: traySize.width)
    }

    // MARK: Pointer on the clover

    /// The pointer moved to `point`, in clover coordinates.
    func pointer(at point: CGPoint) {
        if usingKeyboard { usingKeyboard = false }
        let chips = openLeaf.map { chipFrames(for: $0) } ?? []
        let hit = BloomLayout.hit(point, count: leafCount, open: openLeaf, chips: chips)
        // Back on the clover, off More, closes the tray.
        if trayOpen, hit == .hub || (hit.leaf != nil && hit.leaf != moreIndex) { closeTray() }
        guard hit != hover else { return }
        let oldLeaf = hover.leaf
        hover = hit
        if hit.leaf != oldLeaf { pointerLeafChanged(hit.leaf) }
    }

    func pointerLeft() {
        guard hover != .none else { return }
        hover = .none
        pointerLeafChanged(nil)
    }

    private func pointerLeafChanged(_ leaf: Int?) {
        cancelTimers()
        if leaf != openLeaf { openLeaf = nil }
        guard let leaf else { return }
        if isMore(leaf) {
            guard mode == .drag, !trayOpen else { return }
            schedule(&moreTimer, after: moreDelay) { [weak self] in
                guard let self, self.hover.leaf == leaf, self.isMore(leaf) else { return }
                self.openTray(focusFirst: false)
            }
            return
        }
        guard let target = target(at: leaf), !target.options.isEmpty else { return }
        if chipDelay <= 0 {
            openLeaf = leaf
        } else {
            schedule(&chipTimer, after: chipDelay) { [weak self] in
                guard let self, self.hover.leaf == leaf else { return }
                self.openLeaf = leaf
            }
        }
    }

    // MARK: The tray

    func openTray(focusFirst: Bool) {
        guard moreIndex != nil else { return }
        openLeaf = nil
        trayHover = .none
        openPill = nil
        focusChip = nil
        if focusFirst {
            usingKeyboard = true
            setFocus(.pill(0))
        }
        trayOpen = true
    }

    func closeTray() {
        guard trayOpen else { return }
        trayOpen = false
        trayHover = .none
        openPill = nil
        if case .pill = focus {
            focus = moreIndex.map(Focus.leaf)
            focusChip = nil
        }
    }

    func toggleTray() {
        if trayOpen { closeTray() } else { openTray(focusFirst: usingKeyboard) }
    }

    /// The pointer moved to `point`, in tray coordinates.
    func trayPointer(at point: CGPoint) {
        guard trayOpen else { return }
        if usingKeyboard { usingKeyboard = false }
        let chips = openPill.map { pillChipFrames(for: $0) } ?? []
        let hit = TrayLayout.hit(point, pills: pillFrames, open: openPill, chips: chips, size: traySize)
        guard hit != trayHover else { return }
        let oldPill = trayHover.pill
        trayHover = hit
        if hit.pill != oldPill { trayPillChanged(hit.pill) }
    }

    func trayPointerLeft() {
        guard trayHover != .none else { return }
        trayHover = .none
        trayPillChanged(nil)
    }

    private func trayPillChanged(_ pill: Int?) {
        chipTimer?.cancel()
        chipTimer = nil
        if pill != openPill { openPill = nil }
        guard let pill, let target = pillTarget(pill), !target.options.isEmpty else { return }
        if chipDelay <= 0 {
            openPill = pill
        } else {
            schedule(&chipTimer, after: chipDelay) { [weak self] in
                guard let self, self.trayHover.pill == pill else { return }
                self.openPill = pill
            }
        }
    }

    // MARK: Keyboard

    /// Left and right: the next leaf around the clover, or the next pill in the tray.
    func moveFocus(by step: Int) {
        usingKeyboard = true
        if case .pill(let pill)? = focus {
            let n = arrangement.more.count
            setFocus(.pill(((pill + step) % n + n) % n))
            return
        }
        let n = leafCount
        guard n > 0 else { return }
        var index = step > 0 ? 0 : n - 1
        if case .leaf(let leaf)? = focus { index = ((leaf + step) % n + n) % n }
        setFocus(.leaf(index))
    }

    /// Tab: every leaf, then every pill in the tray (opening it), then back to the first leaf.
    func tab(forward: Bool) {
        let leafStops = arrangement.leaves.indices.map(Focus.leaf)
        let stops = leafStops + arrangement.more.indices.map(Focus.pill)
        guard !stops.isEmpty else { return }
        usingKeyboard = true
        var next = forward ? 0 : stops.count - 1
        if let focus {
            let current: Int? = {
                if case .leaf(let leaf) = focus, isMore(leaf) {
                    // From More, Tab goes into the tray and Shift-Tab back to the last leaf.
                    return forward ? leafStops.count - 1 : leafStops.count
                }
                return stops.firstIndex(of: focus)
            }()
            if let current { next = ((current + (forward ? 1 : -1)) % stops.count + stops.count) % stops.count }
        }
        setFocus(stops[next])
    }

    /// Up and down: through the focused leaf's or pill's chips, then back to it.
    func moveChipFocus(by step: Int) {
        guard let focus, let target = focusedTarget, !target.options.isEmpty else { return }
        usingKeyboard = true
        let n = target.options.count
        // Positions 0..<n are chips, n is the leaf or pill itself.
        let current = focusChip ?? n
        let next = ((current + step) % (n + 1) + (n + 1)) % (n + 1)
        focusChip = next == n ? nil : next
        switch focus {
        case .leaf(let leaf): openLeaf = leaf
        case .pill(let pill): openPill = pill
        }
    }

    /// Digits 1 to 6: the leaf at that place, clockwise from 12 o'clock.
    func focusNumber(_ number: Int) {
        guard number >= 1, number <= leafCount else { return }
        usingKeyboard = true
        setFocus(.leaf(number - 1))
    }

    /// Return on More opens the tray at its first pill.
    var focusIsMore: Bool {
        if case .leaf(let leaf)? = focus { return isMore(leaf) }
        return false
    }

    /// Esc closes the tray first. Returns false when there was no tray to close.
    func escape() -> Bool {
        guard trayOpen else { return false }
        closeTray()
        return true
    }

    private var focusedTarget: Target? {
        switch focus {
        case .leaf(let leaf)?: target(at: leaf)
        case .pill(let pill)?: pillTarget(pill)
        case nil: nil
        }
    }

    private func setFocus(_ new: Focus) {
        focus = new
        focusChip = nil
        switch new {
        case .leaf(let leaf):
            if trayOpen { closeTray() }
            openPill = nil
            let hasChips = !(target(at: leaf)?.options.isEmpty ?? true)
            openLeaf = hasChips ? leaf : nil
        case .pill(let pill):
            openLeaf = nil
            if !trayOpen { trayOpen = true }
            let hasChips = !(pillTarget(pill)?.options.isEmpty ?? true)
            openPill = hasChips ? pill : nil
        }
    }

    // MARK: Choices

    /// What a drop or a click at `hit` converts to. Nil for More, the hub and empty space.
    func choice(at hit: BloomHit) -> (target: Target, option: Option?)? {
        switch hit {
        case .leaf(let leaf):
            guard let target = target(at: leaf) else { return nil }
            return (target, target.defaultOption)
        case .chip(let leaf, let index):
            guard let target = target(at: leaf), target.options.indices.contains(index) else { return nil }
            return (target, target.options[index])
        default:
            return nil
        }
    }

    /// What a drop or a click on the tray converts to. Nil for the tray's background.
    func trayChoice(at hit: TrayHit) -> (target: Target, option: Option?)? {
        switch hit {
        case .pill(let pill):
            guard let target = pillTarget(pill) else { return nil }
            return (target, target.defaultOption)
        case .chip(let pill, let index):
            guard let target = pillTarget(pill), target.options.indices.contains(index) else { return nil }
            return (target, target.options[index])
        default:
            return nil
        }
    }

    /// What Return converts to.
    var keyboardChoice: (target: Target, option: Option?)? {
        switch focus {
        case .leaf(let leaf)?:
            if let focusChip { return choice(at: .chip(leaf: leaf, index: focusChip)) }
            return choice(at: .leaf(leaf))
        case .pill(let pill)?:
            if let focusChip { return trayChoice(at: .chip(pill: pill, index: focusChip)) }
            return trayChoice(at: .pill(pill))
        case nil:
            return nil
        }
    }

    // MARK: What's lit

    /// The leaf drawn lit, from the keyboard or the pointer. More stays lit while its tray is open.
    var litLeaf: Int? {
        if usingKeyboard {
            switch focus {
            case .leaf(let leaf)?: return leaf
            case .pill?: return moreIndex
            case nil: return nil
            }
        }
        if let leaf = hover.leaf { return leaf }
        return trayOpen ? moreIndex : nil
    }

    /// The pill drawn lit.
    var litPill: Int? {
        if usingKeyboard {
            if case .pill(let pill)? = focus { return pill }
            return nil
        }
        return trayHover.pill
    }

    /// The chip drawn lit, on the open leaf or the open pill.
    var litChip: Int? {
        if usingKeyboard { return focusChip }
        if case .chip(_, let index) = hover { return index }
        if case .chip(_, let index) = trayHover { return index }
        return nil
    }

    var focusedLeaf: Int? {
        guard usingKeyboard, case .leaf(let leaf)? = focus else { return nil }
        return leaf
    }

    var focusedPill: Int? {
        guard usingKeyboard, case .pill(let pill)? = focus else { return nil }
        return pill
    }

    /// The line under the hub.
    var hint: String {
        guard hasFiles else { return "" }
        if arrangement.all.isEmpty { return "Clover can't convert these" }
        if let pill = litPill, let target = pillTarget(pill) {
            return BloomModel.hint(for: target, option: litChip.flatMap { target.options.indices.contains($0) ? target.options[$0] : nil })
        }
        if let leaf = litLeaf {
            if isMore(leaf) { return "\(arrangement.more.count) more formats" }
            if let target = target(at: leaf) {
                let option = litChip.flatMap { target.options.indices.contains($0) ? target.options[$0] : nil }
                return BloomModel.hint(for: target, option: option)
            }
        }
        return summary
    }

    /// "photo.png", "PDF · 12 files", "Image · 3 files", "5 files".
    var summary: String {
        guard hasFiles, !files.isEmpty else { return "" }
        if files.count == 1 { return files[0].lastPathComponent }
        let formats = files.compactMap(Formats.detect)
        if formats.count == files.count {
            if Set(formats).count == 1 { return "\(formats[0].name) · \(files.count) files" }
            let families = Set(formats.map(\.family))
            if families.count == 1 { return "\(families.first!.title) · \(files.count) files" }
        }
        return "\(files.count) files"
    }

    static func hint(for target: Target, option: Option?) -> String {
        if let option {
            return target.mode == .byOption ? option.title : "\(target.title) · \(option.title)"
        }
        switch target.id {
        case "pdf-compress": return "Compress PDF"
        case "pdf-merge": return "Merge PDFs"
        case "folder": return "Extract files"
        default: return "Convert to \(target.title)"
        }
    }

    /// More than one file and they aren't all one family.
    var isMixed: Bool {
        Set(files.map { Formats.detect($0)?.family.rawValue ?? "?" }).count > 1
    }

    // MARK: Pictures

    private func loadPictures() {
        thumbnailTask?.cancel()
        let shown = Array(files.prefix(3))
        pictures = shown.map(Thumbnails.icon)
        thumbnailsLoaded = false
        thumbnailTask = Task { [weak self] in
            for (i, url) in shown.enumerated() {
                let image = await Thumbnails.thumbnail(for: url, side: 96)
                guard let self, !Task.isCancelled, self.files.prefix(3).elementsEqual(shown) else { return }
                if let image, self.pictures.indices.contains(i) { self.pictures[i] = image }
            }
            self?.thumbnailsLoaded = true
        }
    }

    /// Waits for thumbnails, at most `timeout` seconds. For the debug renders.
    func waitForThumbnails(timeout: TimeInterval) async {
        let end = Date().addingTimeInterval(timeout)
        while !thumbnailsLoaded && Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: Helpers

    private func clearPointerAndFocus() {
        hover = .none
        openLeaf = nil
        trayOpen = false
        trayHover = .none
        openPill = nil
        focus = nil
        focusChip = nil
        usingKeyboard = false
    }

    private func cancelTimers() {
        chipTimer?.cancel()
        chipTimer = nil
        moreTimer?.cancel()
        moreTimer = nil
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { body() } }
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
