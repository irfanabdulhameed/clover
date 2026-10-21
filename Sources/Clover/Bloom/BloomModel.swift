import AppKit
import CloverCore

/// Everything the clover shows, and what the pointer and the keys are doing to it.
///
/// State changes are instant; each one is also stamped in `events`, and the view draws
/// the motion from those times (`Motion`), so any moment can be drawn.
@MainActor
final class BloomModel: ObservableObject {
    enum Mode { case drag, click }

    /// Open and taking input, carrying a choice to the hub, or folding away.
    enum Phase { case open, dropping, closing }

    /// What a slot holds.
    enum Leaf: Equatable {
        case target(Target)
        case more
    }

    /// Keyboard focus: a slot, or a pill in the More tray.
    enum Focus: Equatable {
        case leaf(Int)
        case pill(Int)
    }

    @Published private(set) var files: [URL] = []
    /// False while a drag hasn't reached the clover yet: the hub shows a placeholder.
    @Published private(set) var hasFiles = false
    @Published private(set) var arrangement = Arrangement(leaves: [], more: [])
    /// What the pointer is over on the clover. Drops go here at once.
    @Published private(set) var hover: BloomHit = .none
    /// The slot the pointer has rested on long enough to light it.
    @Published private(set) var restingLeaf: Int?
    /// The slot whose chips are showing.
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
    /// One of the focused slot's or pill's chips.
    @Published private(set) var focusChip: Int?
    /// True after a key press, until the pointer moves again.
    @Published private(set) var usingKeyboard = false
    /// Hub pictures for the first few files: icons first, thumbnails once loaded.
    @Published private(set) var pictures: [NSImage] = []
    @Published private(set) var thumbnailsLoaded = false
    /// The files' total size, when they are all plain files.
    @Published private(set) var byteCount: Int64?
    @Published private(set) var phase = Phase.open
    /// When things happened, for the motion. Set directly only by the debug renders.
    @Published var events = BloomEvents()
    /// True while something moves: the view's frame clock runs only then.
    @Published private(set) var animating = false
    /// Light glass with a clover-green tint (`LeafStyle.clover`), or clear glass.
    @Published var tinted = true
    /// The point of the tray, as a fraction of its size, that it grows out of: the side
    /// nearest the More slot. Set by the controller when it places the tray.
    var trayAnchor = CGPoint(x: 0.5, y: 0.5)

    var mode: Mode = .drag
    /// Rest on a slot this long before it lights, so a sweep doesn't flicker.
    var hoverDelay: TimeInterval = Motion.Hover.delay
    /// Rest on a slot or a pill this long before its chips open.
    var chipDelay: TimeInterval = Motion.Chips.delay
    /// Rest on More this long, during a drag, to open the tray.
    var moreDelay: TimeInterval = Motion.Tray.delay
    /// Fades only: nothing travels, pops, ripples or blurs.
    var reduceMotion: Bool {
        get { events.reduce }
        set { events.reduce = newValue }
    }
    /// The motion clock, in seconds on `Date`'s reference clock.
    var clock: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    /// Called when the tray opens or closes.
    var onTrayChange: ((Bool) -> Void)?
    /// Called when a slot lights, for the haptic tick.
    var onLight: (() -> Void)?

    private var chipWidthCache: [String: [CGFloat]] = [:]
    private var restTimer: DispatchWorkItem?
    private var chipTimer: DispatchWorkItem?
    private var moreTimer: DispatchWorkItem?
    private var quietTimer: DispatchWorkItem?
    private var thumbnailTask: Task<Void, Never>?
    private(set) var pillWidth: CGFloat = TrayLayout.pillMinWidth
    /// Where the pointer last was, on the clover and in the tray, for the chips' order.
    private var pointerPoint: CGPoint?
    private var trayPointerPoint: CGPoint?

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
        byteCount = nil
        phase = .open
        let reduce = events.reduce
        events = BloomEvents()
        events.reduce = reduce
        quietTimer?.cancel()
        animating = false
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
        // The slots unfold now, if the disc is already open.
        if events.openedAt.isFinite { events.slotsAt = clock() }
        loadPictures()
        changed()
    }

    /// A still clover, settled and with no clock, for the dashboard's preview.
    static func still(arrangement: Arrangement, picture: NSImage?, lit: Int?) -> BloomModel {
        let model = BloomModel()
        model.arrangement = arrangement
        model.hasFiles = picture != nil
        model.pictures = picture.map { [$0] } ?? []
        model.restingLeaf = lit
        model.events.lit = lit
        return model
    }

    /// The disc starts to open now.
    func open() {
        phase = .open
        let now = clock()
        events.openedAt = now
        if hasFiles { events.slotsAt = now }
        changed()
    }

    /// The slots clockwise from 12 o'clock; More last when some targets don't fit.
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
        guard phase == .open else { return }
        pointerPoint = point
        if usingKeyboard { usingKeyboard = false }
        let chips = openLeaf.map { chipFrames(for: $0) } ?? []
        let hit = BloomLayout.hit(point, count: leafCount, open: openLeaf, chips: chips)
        // Back on the clover, off More, closes the tray.
        if trayOpen, hit == .hub || (hit.leaf != nil && hit.leaf != moreIndex) { closeTray() }
        guard hit != hover else {
            changed()
            return
        }
        let oldLeaf = hover.leaf
        hover = hit
        if hit.leaf != oldLeaf { pointerLeafChanged(hit.leaf) }
        changed()
    }

    func pointerLeft() {
        guard phase == .open, hover != .none else { return }
        hover = .none
        pointerLeafChanged(nil)
        changed()
    }

    private func pointerLeafChanged(_ leaf: Int?) {
        cancelTimers()
        if leaf != openLeaf { openLeaf = nil }
        // Off the slots, the light goes at once; onto another slot, it moves after a rest.
        guard let leaf else {
            restingLeaf = nil
            return
        }
        if hoverDelay <= 0 {
            restingLeaf = leaf
        } else {
            schedule(&restTimer, after: hoverDelay) { [weak self] in
                guard let self, self.phase == .open, self.hover.leaf == leaf else { return }
                self.restingLeaf = leaf
                self.changed()
            }
        }
        if isMore(leaf) {
            guard mode == .drag, !trayOpen else { return }
            schedule(&moreTimer, after: moreDelay) { [weak self] in
                guard let self, self.phase == .open, self.hover.leaf == leaf, self.isMore(leaf) else { return }
                self.openTray(focusFirst: false)
            }
            return
        }
        guard let target = target(at: leaf), !target.options.isEmpty else { return }
        if chipDelay <= 0 {
            openLeaf = leaf
        } else {
            schedule(&chipTimer, after: chipDelay) { [weak self] in
                guard let self, self.phase == .open, self.hover.leaf == leaf else { return }
                self.openLeaf = leaf
                self.changed()
            }
        }
    }

    // MARK: The tray

    func openTray(focusFirst: Bool) {
        guard phase == .open, moreIndex != nil else { return }
        openLeaf = nil
        trayHover = .none
        openPill = nil
        focusChip = nil
        if focusFirst {
            usingKeyboard = true
            setFocus(.pill(0))
        }
        trayOpen = true
        changed()
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
        changed()
    }

    func toggleTray() {
        if trayOpen { closeTray() } else { openTray(focusFirst: usingKeyboard) }
    }

    /// The pointer moved to `point`, in tray coordinates.
    func trayPointer(at point: CGPoint) {
        guard phase == .open, trayOpen else { return }
        trayPointerPoint = point
        if usingKeyboard { usingKeyboard = false }
        let chips = openPill.map { pillChipFrames(for: $0) } ?? []
        let hit = TrayLayout.hit(point, pills: pillFrames, open: openPill, chips: chips, size: traySize)
        guard hit != trayHover else {
            changed()
            return
        }
        let oldPill = trayHover.pill
        trayHover = hit
        if hit.pill != oldPill { trayPillChanged(hit.pill) }
        changed()
    }

    func trayPointerLeft() {
        guard phase == .open, trayHover != .none else { return }
        trayHover = .none
        trayPillChanged(nil)
        changed()
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
                guard let self, self.phase == .open, self.trayHover.pill == pill else { return }
                self.openPill = pill
                self.changed()
            }
        }
    }

    // MARK: Keyboard

    /// Left and right: the next slot around the clover, or the next pill in the tray.
    func moveFocus(by step: Int) {
        guard phase == .open else { return }
        usingKeyboard = true
        defer { changed() }
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

    /// Tab: every slot, then every pill in the tray (opening it), then back to the first slot.
    func tab(forward: Bool) {
        guard phase == .open else { return }
        let leafStops = arrangement.leaves.indices.map(Focus.leaf)
        let stops = leafStops + arrangement.more.indices.map(Focus.pill)
        guard !stops.isEmpty else { return }
        usingKeyboard = true
        var next = forward ? 0 : stops.count - 1
        if let focus {
            let current: Int? = {
                if case .leaf(let leaf) = focus, isMore(leaf) {
                    // From More, Tab goes into the tray and Shift-Tab back to the last slot.
                    return forward ? leafStops.count - 1 : leafStops.count
                }
                return stops.firstIndex(of: focus)
            }()
            if let current { next = ((current + (forward ? 1 : -1)) % stops.count + stops.count) % stops.count }
        }
        setFocus(stops[next])
        changed()
    }

    /// Up and down: through the focused slot's or pill's chips, then back to it.
    func moveChipFocus(by step: Int) {
        guard phase == .open, let focus, let target = focusedTarget, !target.options.isEmpty else { return }
        usingKeyboard = true
        let n = target.options.count
        // Positions 0..<n are chips, n is the slot or pill itself.
        let current = focusChip ?? n
        let next = ((current + step) % (n + 1) + (n + 1)) % (n + 1)
        focusChip = next == n ? nil : next
        switch focus {
        case .leaf(let leaf): openLeaf = leaf
        case .pill(let pill): openPill = pill
        }
        changed()
    }

    /// Digits 1 to 6: the slot at that place, clockwise from 12 o'clock.
    func focusNumber(_ number: Int) {
        guard phase == .open, number >= 1, number <= leafCount else { return }
        usingKeyboard = true
        setFocus(.leaf(number - 1))
        changed()
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

    /// Where a choice was made, for the drop's motion: the slot that carries it to the hub
    /// and the chip or pill that was chosen.
    var choiceSource: (slot: Int, chip: Int?, pill: Int?)? {
        if usingKeyboard {
            switch focus {
            case .leaf(let leaf)?: return (leaf, focusChip, nil)
            case .pill(let pill)?: return (moreIndex ?? 0, focusChip, pill)
            case nil: return nil
            }
        }
        if let pill = trayHover.pill {
            if case .chip(_, let index) = trayHover { return (moreIndex ?? 0, index, pill) }
            return (moreIndex ?? 0, nil, pill)
        }
        switch hover {
        case .leaf(let leaf): return (leaf, nil, nil)
        case .chip(let leaf, let index): return (leaf, index, nil)
        default: return nil
        }
    }

    // MARK: Drop and cancel

    /// A choice was made: the chosen slot carries it to the hub. Input stops.
    func drop() {
        guard phase == .open else { return }
        let source = choiceSource ?? (events.lit ?? 0, nil, nil)
        cancelTimers()
        phase = .dropping
        events.drop = BloomEvents.Drop(at: clock(), slot: source.slot, chip: source.chip, pill: source.pill)
        changed()
    }

    /// Everything folds into the hub. Input stops.
    func cancel() {
        guard phase == .open else { return }
        cancelTimers()
        phase = .closing
        events.cancelAt = clock()
        changed()
    }

    // MARK: What's lit

    /// The slot drawn lit, from the keyboard or the pointer. More stays lit while its tray is open.
    var litLeaf: Int? {
        if usingKeyboard {
            switch focus {
            case .leaf(let leaf)?: return leaf
            case .pill?: return moreIndex
            case nil: return nil
            }
        }
        if let leaf = restingLeaf { return leaf }
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

    /// The chip drawn lit, on the open slot or the open pill.
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

    /// The capsule on the centre circle: the files' size, or what a drop will make.
    var hint: String {
        guard hasFiles else { return "" }
        if arrangement.all.isEmpty { return "Can't convert" }
        if let pill = litPill, let target = pillTarget(pill) {
            return BloomModel.hint(for: target, option: litChip.flatMap { target.options.indices.contains($0) ? target.options[$0] : nil })
        }
        if let leaf = litLeaf {
            if isMore(leaf) { return "\(arrangement.more.count) more" }
            if let target = target(at: leaf) {
                let option = litChip.flatMap { target.options.indices.contains($0) ? target.options[$0] : nil }
                return BloomModel.hint(for: target, option: option)
            }
        }
        return summary
    }

    /// "2.2 MB", "12 files · 34 MB"; without sizes, "photo.png", "PDF · 12 files", "5 files".
    var summary: String {
        guard hasFiles, !files.isEmpty else { return "" }
        let size = byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        if files.count == 1 { return size ?? files[0].lastPathComponent }
        if let size { return "\(files.count) files · \(size)" }
        let formats = files.compactMap(Formats.detect)
        if formats.count == files.count {
            if Set(formats).count == 1 { return "\(formats[0].name) · \(files.count) files" }
            let families = Set(formats.map(\.family))
            if families.count == 1 { return "\(families.first!.title) · \(files.count) files" }
        }
        return "\(files.count) files"
    }

    /// What the capsule says for a target: its name, with the option when one is chosen.
    static func hint(for target: Target, option: Option?) -> String {
        if let option {
            return target.mode == .byOption ? option.title : "\(target.title) · \(option.title)"
        }
        switch target.id {
        case "pdf-compress": return "Compress PDF"
        case "pdf-merge": return "Merge PDFs"
        case "folder": return "Extract files"
        default: return target.title
        }
    }

    /// More than one file and they aren't all one family.
    var isMixed: Bool {
        Set(files.map { Formats.detect($0)?.family.rawValue ?? "?" }).count > 1
    }

    // MARK: Motion bookkeeping

    /// Stamps what changed since the last call into `events`, and runs or pauses the frame clock.
    private func changed() {
        let now = clock()
        var e = events
        // The lit slot.
        let lit = phase == .open ? litLeaf : e.lit
        if lit != e.lit {
            if let old = e.lit {
                e.unlit = old
                e.unlitAt = now
            }
            if e.lit == nil { e.dimAt = now }
            if lit == nil { e.undimAt = now }
            e.lit = lit
            e.litAt = now
            if let lit {
                e.ripples.removeAll { now - $0.at > Motion.Hover.ripple }
                e.ripples.append(BloomEvents.Ripple(slot: lit, at: now))
                onLight?()
            }
        }
        // The chips beyond a slot, or under a pill.
        if openLeaf != e.chipsLeaf {
            if let old = e.chipsLeaf {
                e.closingLeaf = old
                e.closingAt = now
                e.closingRank = e.chipRank
            }
            e.chipsLeaf = openLeaf
            e.chipsAt = now
            e.chipRank = openLeaf.map { rank(chipFrames(for: $0), near: pointerPoint ?? BloomLayout.leafCenter($0, of: leafCount)) } ?? []
        }
        if openPill != e.pillChips {
            e.pillChips = openPill
            e.pillChipsAt = now
            e.pillChipRank = openPill.map { pill in
                let frames = pillChipFrames(for: pill)
                return rank(frames, near: trayPointerPoint ?? CGPoint(x: frames.first?.minX ?? 0, y: frames.first?.midY ?? 0))
            } ?? []
        }
        let chip = phase == .open ? litChip : e.litChip
        if chip != e.litChip {
            e.litChip = chip
            e.litChipAt = now
        }
        let pill = phase == .open ? litPill : e.litPill
        if pill != e.litPill {
            e.litPill = pill
            e.litPillAt = now
        }
        // The tray.
        if trayOpen, e.trayClosingAt != nil || !e.trayAt.isFinite {
            e.trayAt = now
            e.trayClosingAt = nil
        } else if !trayOpen, e.trayAt.isFinite, e.trayClosingAt == nil {
            e.trayClosingAt = now
        }
        if e != events { events = e }
        updateClock(now: now)
    }

    /// Chip indices ranked by distance from `point`: rank[i] is chip i's turn.
    private func rank(_ frames: [CGRect], near point: CGPoint) -> [Int] {
        let order = frames.indices.sorted {
            BloomLayout.distance(frames[$0].mid, point) < BloomLayout.distance(frames[$1].mid, point)
        }
        var rank = Array(repeating: 0, count: frames.count)
        for (turn, index) in order.enumerated() { rank[index] = turn }
        return rank
    }

    /// Runs the frame clock while anything moves or a lit slot breathes; pauses it after.
    private func updateClock(now: TimeInterval) {
        guard events.openedAt.isFinite else {
            if animating { animating = false }
            return
        }
        let until = Motion.busyUntil(events, count: leafCount)
        let breathing = events.lit != nil && !events.reduce && phase == .open
        let moving = breathing || now < until
        if animating != moving { animating = moving }
        quietTimer?.cancel()
        if !breathing, now < until {
            schedule(&quietTimer, after: until - now + 0.02) { [weak self] in
                guard let self else { return }
                self.updateClock(now: self.clock())
            }
        }
    }

    // MARK: Pictures

    private func loadPictures() {
        thumbnailTask?.cancel()
        let all = files
        let shown = Array(all.prefix(3))
        pictures = shown.map(Thumbnails.icon)
        thumbnailsLoaded = false
        byteCount = nil
        thumbnailTask = Task { [weak self] in
            let bytes = await Task.detached(priority: .userInitiated) { BloomModel.totalSize(all) }.value
            guard let self, !Task.isCancelled, self.files == all else { return }
            self.byteCount = bytes
            for (i, url) in shown.enumerated() {
                let image = await Thumbnails.thumbnail(for: url, side: 128)
                guard !Task.isCancelled, self.files.prefix(3).elementsEqual(shown) else { return }
                if let image, self.pictures.indices.contains(i) { self.pictures[i] = image }
            }
            self.thumbnailsLoaded = true
        }
    }

    /// The total size of plain files, or nil when one is missing or a folder.
    nonisolated static func totalSize(_ files: [URL]) -> Int64? {
        var total: Int64 = 0
        for url in files.prefix(5000) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize else { return nil }
            total += Int64(size)
        }
        return files.count > 5000 ? nil : total
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
        restingLeaf = nil
        openLeaf = nil
        trayOpen = false
        trayHover = .none
        openPill = nil
        focus = nil
        focusChip = nil
        usingKeyboard = false
        pointerPoint = nil
        trayPointerPoint = nil
    }

    private func cancelTimers() {
        restTimer?.cancel()
        restTimer = nil
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
