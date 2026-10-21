import AppKit
import CloverCore

/// Everything the bloom shows, and what the pointer and the keys are doing to it.
/// Every change is instant: nothing here animates.
@MainActor
final class BloomModel: ObservableObject {
    enum Mode { case drag, click }

    @Published private(set) var files: [URL] = []
    /// False while a drag hasn't reached the bloom yet: the hub shows a placeholder.
    @Published private(set) var hasFiles = false
    @Published private(set) var targets: [Target] = []
    @Published private(set) var plan = BloomPlan(targetIDs: [])
    @Published private(set) var page = 0
    /// What the pointer is over.
    @Published private(set) var hover: BloomHit = .none
    /// The petal whose chips are showing.
    @Published private(set) var openSlot: Int?
    /// Keyboard focus: a petal, and maybe one of its chips.
    @Published private(set) var focusSlot: Int?
    @Published private(set) var focusChip: Int?
    /// True after a key press, until the pointer moves again.
    @Published private(set) var usingKeyboard = false
    /// Hub pictures for the first few files: icons first, thumbnails once loaded.
    @Published private(set) var pictures: [NSImage] = []
    @Published private(set) var thumbnailsLoaded = false

    var mode: Mode = .drag
    /// Rest on a petal this long before its chips open, so sweeping doesn't flicker.
    var chipDelay: TimeInterval = 0.08
    /// Rest on More this long, during a drag, to turn the page.
    var moreDelay: TimeInterval = 0.3

    private var byID: [String: Target] = [:]
    private var chipWidths: [String: [CGFloat]] = [:]
    private var chipTimer: DispatchWorkItem?
    private var moreTimer: DispatchWorkItem?
    /// More turns the page once per visit.
    private var moreArmed = true
    private var thumbnailTask: Task<Void, Never>?

    // MARK: Content

    func reset(mode: Mode) {
        cancelTimers()
        thumbnailTask?.cancel()
        self.mode = mode
        files = []
        hasFiles = false
        targets = []
        byID = [:]
        chipWidths = [:]
        plan = BloomPlan(targetIDs: [])
        page = 0
        clearPointerAndFocus()
        pictures = []
        thumbnailsLoaded = false
    }

    func setFiles(_ files: [URL], targets: [Target]) {
        cancelTimers()
        let ordered = BloomModel.ordered(targets, files: files)
        self.files = files
        hasFiles = true
        self.targets = ordered
        byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        chipWidths = [:]
        plan = BloomPlan(targetIDs: ordered.map(\.id))
        page = 0
        clearPointerAndFocus()
        loadPictures()
    }

    /// The family's own formats first (Extract first for archives), then the rest,
    /// each group in the catalog's order.
    static func ordered(_ targets: [Target], files: [URL]) -> [Target] {
        let families = Set(files.compactMap { Formats.detect($0)?.family })
        let main = families.count == 1 ? families.first : nil
        func rank(_ target: Target) -> Int {
            if target.id == "folder" { return 0 }
            if let main, target.format.family == main { return 1 }
            return 2
        }
        return targets.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    var items: [BloomPlan.Item] { plan.items(onPage: page) }
    var slots: [Int] { items.map(\.slot) }
    var pageCount: Int { plan.pageCount }

    func item(at slot: Int) -> BloomPlan.Item? { items.first { $0.slot == slot } }

    func target(at slot: Int) -> Target? {
        guard case .target(let id)? = item(at: slot)?.kind else { return nil }
        return byID[id]
    }

    func isMore(_ slot: Int) -> Bool { item(at: slot)?.kind == .more }

    /// Chip widths for a target, measured with the chip font.
    func chipWidths(for target: Target) -> [CGFloat] {
        if let cached = chipWidths[target.id] { return cached }
        let widths = target.options.map { option in
            BloomLayout.chipWidth(textWidth: BloomStyle.textWidth(option.title),
                                  isDefault: option.id == target.defaultOption?.id)
        }
        chipWidths[target.id] = widths
        return widths
    }

    func chipFrames(for slot: Int) -> [CGRect] {
        guard let target = target(at: slot) else { return [] }
        return BloomLayout.chipFrames(slot: slot, widths: chipWidths(for: target))
    }

    // MARK: Pointer

    /// The pointer moved to `point`, in bloom coordinates.
    func pointer(at point: CGPoint) {
        if usingKeyboard { usingKeyboard = false }
        let chips = openSlot.map { chipFrames(for: $0) } ?? []
        let hit = BloomLayout.hit(point, slots: slots, open: openSlot, chips: chips)
        guard hit != hover else { return }
        let oldSlot = hover.slot
        hover = hit
        if hit.slot != oldSlot { pointerSlotChanged(hit.slot) }
    }

    func pointerLeft() {
        guard hover != .none else { return }
        hover = .none
        pointerSlotChanged(nil)
    }

    private func pointerSlotChanged(_ slot: Int?) {
        cancelTimers()
        if slot != openSlot { openSlot = nil }
        guard let slot else {
            moreArmed = true
            return
        }
        if isMore(slot) {
            guard mode == .drag, moreArmed else { return }
            schedule(&moreTimer, after: moreDelay) { [weak self] in
                guard let self, self.hover.slot == slot, self.isMore(slot) else { return }
                self.moreArmed = false
                self.nextPage()
            }
            return
        }
        moreArmed = true
        guard let target = target(at: slot), !target.options.isEmpty else { return }
        if chipDelay <= 0 {
            openSlot = slot
        } else {
            schedule(&chipTimer, after: chipDelay) { [weak self] in
                guard let self, self.hover.slot == slot else { return }
                self.openSlot = slot
            }
        }
    }

    func nextPage() {
        guard pageCount > 1 else { return }
        page = (page + 1) % pageCount
        openSlot = nil
        focusChip = nil
        focusSlot = usingKeyboard ? items.first?.slot : nil
        if let focusSlot { openChips(for: focusSlot) }
    }

    func previousPage() {
        guard pageCount > 1 else { return }
        page = (page + pageCount - 1) % pageCount
        openSlot = nil
        focusChip = nil
        focusSlot = usingKeyboard ? items.last?.slot : nil
        if let focusSlot { openChips(for: focusSlot) }
    }

    // MARK: Keyboard

    /// Arrow keys: the next petal around the ring.
    func moveFocus(by step: Int) {
        let items = self.items
        guard !items.isEmpty else { return }
        usingKeyboard = true
        let n = items.count
        var index = step > 0 ? 0 : n - 1
        if let focusSlot, let i = items.firstIndex(where: { $0.slot == focusSlot }) {
            index = ((i + step) % n + n) % n
        }
        setFocus(items[index].slot)
    }

    /// Tab: the next petal, and past the last one, the next page.
    func tab(forward: Bool) {
        let ring = items.filter { $0.kind != .more }
        guard !ring.isEmpty else { return }
        usingKeyboard = true
        guard let focusSlot, let i = ring.firstIndex(where: { $0.slot == focusSlot }) else {
            setFocus((forward ? ring.first : ring.last)!.slot)
            return
        }
        let next = i + (forward ? 1 : -1)
        if ring.indices.contains(next) {
            setFocus(ring[next].slot)
        } else if pageCount > 1 {
            if forward { nextPage() } else { previousPage() }
            let ring = items.filter { $0.kind != .more }
            if let slot = (forward ? ring.first : ring.last)?.slot { setFocus(slot) }
        } else {
            setFocus((forward ? ring.first : ring.last)!.slot)
        }
    }

    /// Up and down: through the focused petal's chips, then back to the petal.
    func moveChipFocus(by step: Int) {
        guard let focusSlot, let target = target(at: focusSlot), !target.options.isEmpty else { return }
        usingKeyboard = true
        let n = target.options.count
        // Positions 0..<n are chips, n is the petal itself.
        let current = focusChip ?? n
        let next = ((current + step) % (n + 1) + (n + 1)) % (n + 1)
        focusChip = next == n ? nil : next
        openSlot = focusSlot
    }

    /// Digits 1 to 8: the petal at that place, clockwise from 12 o'clock.
    func focusNumber(_ number: Int) {
        let items = self.items
        guard items.indices.contains(number - 1) else { return }
        usingKeyboard = true
        setFocus(items[number - 1].slot)
    }

    private func setFocus(_ slot: Int) {
        focusSlot = slot
        focusChip = nil
        openChips(for: slot)
    }

    private func openChips(for slot: Int) {
        let hasChips = !(target(at: slot)?.options.isEmpty ?? true)
        openSlot = hasChips ? slot : nil
    }

    // MARK: Choices

    /// What a drop or a click at `hit` converts to. Nil for More, the hub and empty space.
    func choice(at hit: BloomHit) -> (target: Target, option: Option?)? {
        switch hit {
        case .petal(let slot):
            guard let target = target(at: slot) else { return nil }
            return (target, target.defaultOption)
        case .chip(let slot, let index):
            guard let target = target(at: slot), target.options.indices.contains(index) else { return nil }
            return (target, target.options[index])
        default:
            return nil
        }
    }

    /// What Return converts to.
    var keyboardChoice: (target: Target, option: Option?)? {
        guard let focusSlot else { return nil }
        if let focusChip { return choice(at: .chip(slot: focusSlot, index: focusChip)) }
        return choice(at: .petal(slot: focusSlot))
    }

    // MARK: What's lit

    /// The petal drawn lit, from the keyboard or the pointer.
    var litSlot: Int? { usingKeyboard ? focusSlot : hover.slot }

    /// The chip drawn lit.
    var litChip: Int? {
        if usingKeyboard { return focusChip }
        if case .chip(_, let index) = hover { return index }
        return nil
    }

    /// The line under the hub.
    var hint: String {
        guard hasFiles else { return "" }
        if targets.isEmpty { return "Clover can't convert these" }
        if let slot = litSlot {
            if isMore(slot) { return "Page \((page + 1) % pageCount + 1) of \(pageCount)" }
            if let target = target(at: slot) {
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
        openSlot = nil
        focusSlot = nil
        focusChip = nil
        usingKeyboard = false
        moreArmed = true
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
