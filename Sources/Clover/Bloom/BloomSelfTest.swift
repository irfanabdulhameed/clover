import AppKit
import CloverCore

/// Checks the bloom's slot plan, geometry, hit-testing, edge clamping, model and chip
/// texts. Run with `Clover --bloom-selftest`; exits 1 on any failure.
@MainActor
enum BloomSelfTest {
    private static var failures = 0
    private static var checks = 0

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL \(message())")
        }
    }

    static func run(model: AppModel) async -> Int32 {
        plan()
        geometry()
        hitTesting()
        clamping()
        chipStack()
        await bloomModel(model)
        chipTexts()
        print("\(checks - failures) of \(checks) checks passed")
        return failures == 0 ? 0 : 1
    }

    private typealias G = BloomGeometry

    // MARK: Slots

    private static func slotMap(_ items: [BloomPlan.Item]) -> [Int: String] {
        var map: [Int: String] = [:]
        for item in items {
            switch item.kind {
            case .target(let id): map[item.slot] = id
            case .more: map[item.slot] = "more"
            }
        }
        return map
    }

    private static func plan() {
        // A PNG: twelve targets, two pages.
        let png = BloomPlan(targetIDs: ["jpg", "heic", "webp", "avif", "tiff", "gif", "bmp", "ico", "icns", "pdf", "zip", "tgz"])
        expect(png.pageCount == 2, "png has 2 pages, got \(png.pageCount)")
        let p0 = slotMap(png.items(onPage: 0))
        expect(p0 == [0: "jpg", 1: "heic", 2: "webp", 3: "avif", 4: "pdf", 5: "more", 6: "zip", 7: "tiff"], "png page 0: \(p0)")
        let p1 = slotMap(png.items(onPage: 1))
        expect(p1 == [0: "gif", 1: "bmp", 2: "ico", 3: "icns", 4: "tgz", 5: "more"], "png page 1: \(p1)")

        // Exactly eight: one page, no More, ZIP still at 9 o'clock.
        let video = BloomPlan(targetIDs: ["mov", "webm", "mkv", "gif", "mp3", "m4a", "zip", "tgz"])
        expect(video.pageCount == 1, "video has 1 page")
        let v = slotMap(video.items(onPage: 0))
        expect(v[6] == "zip" && !v.values.contains("more") && v.count == 8, "video slots: \(v)")

        // A PDF: Compress at 6, ZIP at 9.
        let pdf = slotMap(BloomPlan(targetIDs: ["pdf-compress", "jpg", "png", "txt", "zip", "tgz"]).items(onPage: 0))
        expect(pdf == [0: "jpg", 1: "png", 2: "txt", 3: "tgz", 4: "pdf-compress", 6: "zip"], "pdf slots: \(pdf)")

        // Many PDFs: Merge wins 6 o'clock, Compress fills a free slot.
        let pdfs = slotMap(BloomPlan(targetIDs: ["png", "pdf-merge", "pdf-compress", "zip"]).items(onPage: 0))
        expect(pdfs[4] == "pdf-merge" && pdfs[6] == "zip" && pdfs[1] == "pdf-compress", "pdfs slots: \(pdfs)")

        // Archives only (mixed or unknown files).
        let mixed = slotMap(BloomPlan(targetIDs: ["zip", "tgz"]).items(onPage: 0))
        expect(mixed == [0: "tgz", 6: "zip"], "mixed slots: \(mixed)")

        let empty = BloomPlan(targetIDs: [])
        expect(empty.pageCount == 1 && empty.items(onPage: 0).isEmpty, "empty plan has one empty page")

        // Many targets: every id once, no slot twice on a page, More on every page.
        let many = (0..<30).map { "t\($0)" } + ["pdf", "zip"]
        let big = BloomPlan(targetIDs: many)
        var seen: [String] = []
        for page in big.pages {
            let slots = page.map(\.slot)
            expect(Set(slots).count == slots.count, "no slot twice on a page")
            expect(page.contains { $0.kind == .more && $0.slot == BloomPlan.moreSlot }, "More at 7:30 on every page")
            expect(page.count <= BloomPlan.slotCount, "at most 8 per page")
            for case .target(let id) in page.map(\.kind) { seen.append(id) }
        }
        expect(seen.sorted() == many.sorted(), "every target placed once")
        expect(big.place(of: "pdf")! == (0, 4) && big.place(of: "zip")! == (0, 6), "pdf and zip on page 1 at 6 and 9")
    }

    // MARK: Geometry

    static let optionSets: [[String]] = [
        ["Best", "Balanced", "Small"],
        ["Original", "1080p", "720p", "Small"],
        ["Best", "Balanced", "Small", "Lossless"],
        ["Large", "Medium", "Small"],
        ["One PDF", "PDF per file"],
        ["Balanced", "Small"],
    ]

    static func widths(_ titles: [String]) -> [CGFloat] {
        titles.enumerated().map { i, title in
            BloomLayout.chipWidth(textWidth: BloomStyle.textWidth(title), isDefault: i == 1)
        }
    }

    private static func geometry() {
        expect(BloomLayout.petalCenter(0) == CGPoint(x: 0, y: -100), "12 o'clock is up")
        expect(BloomLayout.petalCenter(2) == CGPoint(x: 100, y: 0), "3 o'clock is right")
        expect(BloomLayout.petalCenter(4) == CGPoint(x: 0, y: 100), "6 o'clock is down")
        expect(BloomLayout.petalCenter(6) == CGPoint(x: -100, y: 0), "9 o'clock is left")
        expect(BloomLayout.petalCenter(1) == CGPoint(x: 71, y: -71), "1:30 is up right")

        // Petals don't touch each other or the hub, even when lit.
        for a in 0..<8 {
            let b = (a + 1) % 8
            let gap = BloomLayout.distance(BloomLayout.petalCenter(a), BloomLayout.petalCenter(b)) - G.litPetalSize
            expect(gap > 8, "petals \(a) and \(b) have room, gap \(gap)")
            let hubGap = BloomLayout.distance(.zero, BloomLayout.petalCenter(a)) - G.hubSize / 2 - G.litPetalSize / 2
            expect(hubGap > 20, "petal \(a) clears the hub")
            // Hit circles don't overlap, so a point is never on two petals.
            let hitGap = BloomLayout.distance(BloomLayout.petalCenter(a), BloomLayout.petalCenter(b)) - G.petalHitRadius * 2
            expect(hitGap > 0, "hit circles \(a) and \(b) apart")
        }

        let half = G.panelSize / 2
        let panel = CGRect(x: -half, y: -half, width: G.panelSize, height: G.panelSize)
        for slot in 0..<8 {
            for titles in optionSets {
                let frames = BloomLayout.chipFrames(slot: slot, widths: widths(titles))
                expect(frames.count == titles.count, "one frame per chip")
                for (i, frame) in frames.enumerated() {
                    expect(panel.insetBy(dx: G.glowMargin / 2, dy: G.glowMargin / 2).contains(frame),
                           "slot \(slot) chip \(titles[i]) inside the panel: \(frame)")
                    for other in 0..<8 {
                        let c = BloomLayout.petalCenter(other)
                        let nearest = CGPoint(x: min(max(c.x, frame.minX), frame.maxX), y: min(max(c.y, frame.minY), frame.maxY))
                        let clearance = BloomLayout.distance(nearest, c) - G.litPetalSize / 2
                        expect(clearance >= 4, "slot \(slot) chip \(titles[i]) clears petal \(other) (\(clearance))")
                    }
                    expect(BloomLayout.distance(.zero, CGPoint(x: frame.midX, y: frame.midY)) > G.petalRadius,
                           "chips sit beyond the petals")
                    if i > 0 {
                        let prev = frames[i - 1]
                        let apart = max(frame.minX - prev.maxX, prev.minX - frame.maxX, frame.minY - prev.maxY, prev.minY - frame.maxY)
                        expect(apart >= G.chipGap - 1, "slot \(slot) chips \(i - 1),\(i) apart by \(apart)")
                        // Reading order: left to right, or top to bottom when stacked.
                        let t = BloomLayout.across(slot)
                        let step = (frame.midX - prev.midX) * t.dx + (frame.midY - prev.midY) * t.dy
                        expect(step > 0 && (t.dx > 0 || t.dy > 0), "slot \(slot) chips read in order")
                    }
                }
            }
        }

        let extent = BloomController.extent
        expect(panel.contains(extent), "worst-case content \(extent) fits the panel")
        expect(extent.width > 2 * (G.petalRadius + G.petalSize / 2), "extent covers the petals")
    }

    // MARK: Hit-testing

    private static func hitTesting() {
        let slots = Array(0..<8)
        for slot in slots {
            let c = BloomLayout.petalCenter(slot)
            expect(BloomLayout.hit(c, slots: slots, open: nil, chips: []) == .petal(slot: slot), "centre of petal \(slot)")
            let edge = CGPoint(x: c.x + G.petalSize / 2 - 1, y: c.y)
            expect(BloomLayout.hit(edge, slots: slots, open: nil, chips: []) == .petal(slot: slot), "edge of petal \(slot)")
        }
        expect(BloomLayout.hit(.zero, slots: slots, open: nil, chips: []) == .hub, "hub")
        expect(BloomLayout.hit(CGPoint(x: 300, y: 0), slots: slots, open: nil, chips: []) == .none, "far away")
        // Midway between two petals on the ring is nothing.
        let between = CGPoint(x: 100 * sin(CGFloat.pi / 8), y: -100 * cos(CGFloat.pi / 8))
        expect(BloomLayout.hit(between, slots: slots, open: nil, chips: []) == .none, "between petals 0 and 1")
        // An empty slot doesn't react.
        expect(BloomLayout.hit(BloomLayout.petalCenter(3), slots: [0, 4, 6], open: nil, chips: []) == .none, "empty slot")

        for slot in slots {
            let chips = BloomLayout.chipFrames(slot: slot, widths: widths(["Best", "Balanced", "Small"]))
            for (i, frame) in chips.enumerated() {
                let mid = CGPoint(x: frame.midX, y: frame.midY)
                expect(BloomLayout.hit(mid, slots: slots, open: slot, chips: chips) == .chip(slot: slot, index: i),
                       "chip \(i) of open petal \(slot)")
                expect(BloomLayout.hit(mid, slots: slots, open: nil, chips: []) == .none, "closed chips don't react")
            }
            // The gap between the petal and its chips keeps the petal.
            let r = BloomLayout.radial(slot)
            // Just past the petal's reach, short of the chips.
            let gapPoint = CGPoint(x: r.dx * (G.petalRadius + G.petalHitRadius + 0.5),
                                   y: r.dy * (G.petalRadius + G.petalHitRadius + 0.5))
            expect(BloomLayout.hit(gapPoint, slots: slots, open: slot, chips: chips) == .petal(slot: slot),
                   "gap to chips keeps petal \(slot) open")
            // Between two chips also keeps it.
            if chips.count > 1 {
                let a = chips[0], b = chips[1]
                let mid = CGPoint(x: (a.midX + b.midX) / 2, y: (a.midY + b.midY) / 2)
                let hit = BloomLayout.hit(mid, slots: slots, open: slot, chips: chips)
                expect(hit.slot == slot, "between chips of \(slot) stays on it: \(hit)")
            }
            // Beyond the chips is nothing.
            let far = CGPoint(x: r.dx * 230, y: r.dy * 230)
            expect(BloomLayout.hit(far, slots: slots, open: slot, chips: chips) == .none, "beyond chips of \(slot)")
            // A neighbouring petal wins over the open petal's band.
            let next = (slot + 1) % 8
            expect(BloomLayout.hit(BloomLayout.petalCenter(next), slots: slots, open: slot, chips: chips) == .petal(slot: next),
                   "neighbour \(next) over open \(slot)")
        }

        // View to bloom coordinates: the view's y points up.
        let h = G.panelSize / 2
        expect(BloomLayout.bloomPoint(fromView: CGPoint(x: h, y: h)) == .zero, "panel centre is the hub")
        expect(BloomLayout.bloomPoint(fromView: CGPoint(x: h, y: h + 100)) == CGPoint(x: 0, y: -100), "up in the view is 12 o'clock")
    }

    // MARK: Screen edges

    private static func clamping() {
        let bounds = BloomController.extent
        func fits(_ c: CGPoint, _ visible: CGRect) -> Bool {
            let onScreen = CGRect(x: c.x + bounds.minX, y: c.y - bounds.maxY, width: bounds.width, height: bounds.height)
            return visible.insetBy(dx: -0.5, dy: -0.5).contains(onScreen)
        }
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let middle = CGPoint(x: 700, y: 420)
        expect(BloomLayout.clampedCenter(middle, bounds: bounds, visible: main) == middle, "middle stays put")
        let screens: [(String, CGRect, [CGPoint])] = [
            ("main", main, [CGPoint(x: 3, y: 3), CGPoint(x: 1437, y: 872), CGPoint(x: 3, y: 870), CGPoint(x: 1439, y: 1), CGPoint(x: 720, y: 870)]),
            ("right display", CGRect(x: 1440, y: -200, width: 1920, height: 1055), [CGPoint(x: 1441, y: 400), CGPoint(x: 3359, y: -199)]),
            ("left display", CGRect(x: -1728, y: 0, width: 1728, height: 1092), [CGPoint(x: -1, y: 1091), CGPoint(x: -1727, y: 5)]),
        ]
        for (name, visible, points) in screens {
            for p in points {
                let c = BloomLayout.clampedCenter(p, bounds: bounds, visible: visible)
                expect(fits(c, visible), "\(name): bloom at \(p) moved to \(c) fits \(visible)")
                expect(c.x == c.x.rounded() && c.y == c.y.rounded(), "whole points")
            }
        }
        // Near the left edge only x moves.
        let left = BloomLayout.clampedCenter(CGPoint(x: 10, y: 420), bounds: bounds, visible: main)
        expect(left.y == 420 && left.x == (-bounds.minX).rounded(), "left edge moves x only: \(left)")
        // A screen smaller than the bloom centres it.
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 300)
        expect(BloomLayout.clampedCenter(CGPoint(x: 5, y: 5), bounds: bounds, visible: tiny) == CGPoint(x: 150, y: 150), "tiny screen")
    }

    private static func chipStack() {
        let size = CGSize(width: 300, height: 56)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frames = ChipStackLayout.frames(count: 3, size: size, origin: CGPoint(x: 720, y: 500), visible: visible)
        expect(frames.count == 3, "three chips")
        expect(frames[0].maxY == 500 && frames[0].midX == 720, "first chip hangs from the origin")
        expect(frames[1].maxY < frames[0].minY && frames[2].maxY < frames[1].minY, "chips stack downward")
        expect(frames.allSatisfy { visible.contains($0) }, "chips on screen")
        let low = ChipStackLayout.frames(count: 3, size: size, origin: CGPoint(x: 720, y: 90), visible: visible)
        expect(low[1].minY > low[0].maxY, "near the bottom they stack upward")
        expect(low.allSatisfy { visible.contains($0) }, "low chips on screen")
        let corner = ChipStackLayout.cornerOrigin(size: size, visible: visible)
        let top = ChipStackLayout.frames(count: 2, size: size, origin: corner, visible: visible)
        expect(top[0].maxX == visible.maxX - 12 && top[0].maxY == visible.maxY - 12, "top right under the menu bar")
        let edge = ChipStackLayout.frames(count: 1, size: size, origin: CGPoint(x: 1430, y: 870), visible: visible)
        expect(visible.contains(edge[0]), "a chip at the edge is pulled in")
    }

    // MARK: Model

    private static func bloomModel(_ app: AppModel) async {
        let png = URL(fileURLWithPath: "/nonexistent/photo.png")
        let m = BloomModel()
        m.chipDelay = 0
        m.reset(mode: .click)
        let targets = app.targets(for: [png])
        m.setFiles([png], targets: targets)
        expect(m.target(at: 0)?.id == "jpg", "JPG at 12 for a PNG")
        expect(m.target(at: 4)?.id == "pdf", "PDF at 6 for a PNG")
        expect(m.target(at: 6)?.id == "zip", "ZIP at 9 for a PNG")
        expect(m.hint == "photo.png", "one file's hint is its name")

        m.pointer(at: BloomLayout.petalCenter(0))
        expect(m.hover == .petal(slot: 0) && m.openSlot == 0, "resting on JPG opens its chips")
        expect(m.hint == "Convert to JPG", "hint for JPG: \(m.hint)")
        expect(m.choice(at: m.hover).map { "\($0.target.id) \($0.option?.id ?? "-")" } == "jpg balanced", "petal drop uses the default")
        let chips = m.chipFrames(for: 0)
        m.pointer(at: CGPoint(x: chips[2].midX, y: chips[2].midY))
        expect(m.hover == .chip(slot: 0, index: 2), "on the Small chip")
        expect(m.choice(at: m.hover)?.option?.id == "small", "chip drop uses its option")
        expect(m.hint == "JPG · Small", "chip hint: \(m.hint)")
        m.pointer(at: .zero)
        expect(m.openSlot == nil && m.hover == .hub, "back on the hub closes the chips")
        expect(m.hint == "photo.png", "hint back to the file")

        // The rest delay: chips wait, then open.
        m.chipDelay = 0.05
        m.pointer(at: BloomLayout.petalCenter(1))
        expect(m.openSlot == nil, "chips wait before opening")
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(m.openSlot == 1, "chips open after resting")
        m.chipDelay = 0

        // More turns the page by click, and by resting on it during a drag.
        expect(m.pageCount == 2 && m.isMore(5), "a PNG has two pages with More")
        m.nextPage()
        expect(m.page == 1 && m.target(at: 0)?.id == "gif", "page two starts with GIF: \(m.target(at: 0)?.id ?? "-")")
        m.nextPage()
        expect(m.page == 0, "More cycles back")
        m.mode = .drag
        m.moreDelay = 0.05
        m.pointer(at: BloomLayout.petalCenter(5))
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(m.page == 1, "resting on More turns the page")
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(m.page == 1, "and only once until the pointer leaves")
        m.pointer(at: .zero)
        m.pointer(at: BloomLayout.petalCenter(5))
        try? await Task.sleep(nanoseconds: 150_000_000)
        expect(m.page == 0, "coming back turns it again")
        m.mode = .click

        // Keyboard.
        m.pointerLeft()
        m.moveFocus(by: 1)
        expect(m.focusSlot == 0 && m.litSlot == 0 && m.usingKeyboard, "arrow focuses 12 o'clock first")
        m.moveFocus(by: -1)
        expect(m.focusSlot == 7, "left goes counter-clockwise: \(m.focusSlot ?? -1)")
        m.focusNumber(1)
        m.moveChipFocus(by: 1)
        expect(m.keyboardChoice.map { "\($0.target.id) \($0.option?.id ?? "-")" } == "jpg best", "down onto the first chip")
        m.moveChipFocus(by: -1)
        expect(m.focusChip == nil && m.keyboardChoice?.option?.id == "balanced", "up back to the petal")
        m.focusNumber(5)
        expect(m.focusSlot == 4 && m.keyboardChoice?.target.id == "pdf", "5 is 6 o'clock here")
        m.focusNumber(8)
        m.tab(forward: true)
        expect(m.page == 1, "Tab past the last petal turns the page")
        m.pointer(at: BloomLayout.petalCenter(0))
        expect(!m.usingKeyboard && m.litSlot == 0, "the pointer takes over from the keys")

        // Many files, mixed files, nothing to do.
        let twelve = (1...12).map { URL(fileURLWithPath: "/nonexistent/IMG_\($0).png") }
        m.setFiles(twelve, targets: app.targets(for: twelve))
        expect(m.summary == "PNG · 12 files", "twelve PNGs: \(m.summary)")
        if let pdf = m.target(at: 4) {
            expect(pdf.id == "pdf" && pdf.mode == .byOption, "many images make one PDF or many")
            m.pointer(at: BloomLayout.petalCenter(4))
            let frames = m.chipFrames(for: 4)
            m.pointer(at: CGPoint(x: frames[0].midX, y: frames[0].midY))
            expect(m.hint == "One PDF", "byOption chip hint: \(m.hint)")
        } else {
            expect(false, "twelve PNGs have a PDF petal")
        }
        let mixed = [URL(fileURLWithPath: "/nonexistent/a.png"), URL(fileURLWithPath: "/nonexistent/b.mp3")]
        m.setFiles(mixed, targets: app.targets(for: mixed))
        expect(m.isMixed && m.summary == "2 files", "mixed summary: \(m.summary)")
        expect(m.target(at: 6)?.id == "zip", "mixed files still get ZIP at 9")
        let zip = URL(fileURLWithPath: "/nonexistent/stuff.zip")
        m.setFiles([zip], targets: app.targets(for: [zip]))
        expect(m.target(at: 0)?.id == "folder", "a ZIP offers Extract at 12")
        m.setFiles([png], targets: [])
        expect(m.hint == "Clover can't convert these" && m.items.isEmpty, "no targets: hub only")
        m.reset(mode: .drag)
        expect(!m.hasFiles && m.hint.isEmpty && m.items.isEmpty, "a drag not yet over the bloom shows the hub only")
    }

    // MARK: Chip texts

    private static func chipTexts() {
        func display(_ s: JobSnapshot) -> ChipDisplay { ChipDisplay(s) }
        let batch = display(JobSnapshot(phase: .running, title: "Convert to JPG", formatName: "JPG", family: .image,
                                        inputNames: Array(repeating: "a.png", count: 12), finished: 7, total: 12))
        expect(batch.kind == .running && batch.subtitle == "7 of 12" && batch.canCancel, "batch: \(batch.subtitle)")
        let done = display(JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                       inputNames: ["photo.png"], outputNames: ["photo.jpg"], finished: 1,
                                       bytesIn: 3_333_333, bytesOut: 1_200_000))
        expect(done.title == "photo.jpg" && done.subtitle == "1.2 MB · 64 % smaller" && done.canUndo, "done: \(done.subtitle)")
        expect(ChipDisplay.sizeChange(from: 1_000_000, to: 1_380_000) == "1.4 MB · 38 % larger", "larger")
        expect(ChipDisplay.sizeChange(from: 1_000_000, to: 1_001_000)?.hasSuffix("same size") == true, "same size")
        let partial = display(JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                          inputNames: [], outputNames: Array(repeating: "x.jpg", count: 9), finished: 12, total: 12,
                                          failures: [("a", "bad"), ("b", "bad"), ("c", "bad")]))
        expect(partial.kind == .partial && partial.title == "9 converted · 3 failed", "partial: \(partial.title)")
        let skipped = display(JobSnapshot(phase: .failed("Already JPG."), title: "Convert to JPG", formatName: "JPG",
                                          family: .image, inputNames: ["photo.jpg"], finished: 1, skipped: 1))
        expect(skipped.kind == .skipped && skipped.title == "Already JPG" && !skipped.canUndo, "skipped: \(skipped.title)")
        let failed = display(JobSnapshot(phase: .failed("Clover can't convert images yet."), title: "Convert to JPG",
                                         formatName: "JPG", family: .image, inputNames: ["photo.png"], finished: 1,
                                         failures: [("photo.png", "Clover can't convert images yet.")]))
        expect(failed.kind == .failed && failed.title == "Couldn't convert to JPG"
               && failed.subtitle == "Clover can't convert images yet.", "failed: \(failed.title)")
        expect(ChipDisplay.couldNot("Merge") == "Couldn't merge", "couldn't merge")
        let undone = display(JobSnapshot(phase: .undone, title: "Convert to JPG", formatName: "JPG", family: .image,
                                         inputNames: ["photo.png"], outputNames: ["photo.jpg"]))
        expect(undone.kind == .undone && undone.subtitle == "photo.jpg moved to the Trash", "undone")
        let cancelled = display(JobSnapshot(phase: .cancelled, title: "Convert to MP4", formatName: "MP4", family: .video,
                                            inputNames: ["trip.mov"]))
        expect(cancelled.kind == .cancelled && !cancelled.canUndo && !cancelled.canCancel, "cancelled")
    }
}
