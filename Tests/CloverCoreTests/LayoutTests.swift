import Foundation
import Testing
@testable import CloverCore

struct LayoutTests {
    let catalog = Catalog(router: Registry.makeRouter(tools: Tools(ffmpeg: URL(fileURLWithPath: "/bin/echo"), cwebp: URL(fileURLWithPath: "/bin/echo"))))

    @Test func sixLeavesThenMore() {
        let targets = catalog.targets(forFormats: [Formats.png])
        #expect(targets.count > 6)
        let plain = LeafArranger.arrange(targets, layout: nil)
        #expect(plain.leaves.count == 5)
        #expect(plain.more.count == targets.count - 5)
        #expect(plain.leaves.first?.id == "jpg")

        let few = LeafArranger.arrange(Array(targets.prefix(6)), layout: nil)
        #expect(few.leaves.count == 6 && few.more.isEmpty)
    }

    @Test func userOrderHiddenAndDefaults() {
        let targets = catalog.targets(forFormats: [Formats.png])
        let layout = LeafLayout(order: ["pdf", "webp"], hidden: ["jpg", "bmp"], defaultOptions: ["webp": "small", "pdf": "nope"])
        let arranged = LeafArranger.arrange(targets, layout: layout)
        #expect(arranged.leaves.map(\.id).prefix(2) == ["pdf", "webp"])
        #expect(!arranged.all.contains { $0.id == "jpg" || $0.id == "bmp" })
        #expect(arranged.leaves[1].defaultOption == Options.small)
        // An option the target doesn't have is ignored.
        #expect(arranged.leaves[0].defaultOption == targets.first { $0.id == "pdf" }?.defaultOption)
    }

    @Test func layoutKeys() {
        #expect(LayoutKey.key(for: [Formats.png, Formats.jpg]) == .image)
        #expect(LayoutKey.key(for: [Formats.png, Formats.mp3]) == .mixed)
        #expect(catalog.allTargets(for: .pdf).map(\.id).contains("pdf-merge"))
        #expect(catalog.allTargets(for: .image).map(\.id).contains("png"))
    }

    @Test func namePattern() {
        var settings = ConversionSettings()
        #expect(settings.name(base: "photo", format: "JPG", option: "Small") == "photo")
        settings.namePattern = "{name} ({format})"
        #expect(settings.name(base: "photo", format: "JPG", option: nil) == "photo (JPG)")
        settings.namePattern = "{name} ({option})"
        #expect(settings.name(base: "photo", format: "JPG", option: nil) == "photo")
        #expect(settings.imageQuality["small"] == 60)
    }
}
