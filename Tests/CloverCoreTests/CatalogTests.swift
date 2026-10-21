import Foundation
import Testing
@testable import CloverCore

struct CatalogTests {
    let tools = Tools(ffmpeg: URL(fileURLWithPath: "/bin/echo"), ffprobe: nil, cwebp: URL(fileURLWithPath: "/bin/echo"))

    @Test func detect() {
        #expect(Formats.detect(URL(fileURLWithPath: "/x/Photo.JPEG")) == Formats.jpg)
        #expect(Formats.detect(URL(fileURLWithPath: "/x/a.tar.gz")) == Formats.tgz)
        #expect(Formats.detect(URL(fileURLWithPath: "/x/a.gz")) == Formats.gz)
        #expect(Formats.baseName(of: URL(fileURLWithPath: "/x/photos.tar.gz")) == "photos")
        #expect(Formats.detect(URL(fileURLWithPath: "/nope/unknown.xyz")) == nil)
    }

    @Test func freeName() throws {
        let dir = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(OutputPlacer.freeURL(for: "a.jpg", in: dir).lastPathComponent == "a.jpg")
        FileManager.default.createFile(atPath: dir.appendingPathComponent("a.jpg").path, contents: Data())
        #expect(OutputPlacer.freeURL(for: "a.jpg", in: dir).lastPathComponent == "a 2.jpg")
        FileManager.default.createFile(atPath: dir.appendingPathComponent("a 2.jpg").path, contents: Data())
        #expect(OutputPlacer.freeURL(for: "a.jpg", in: dir).lastPathComponent == "a 3.jpg")
        #expect(OutputPlacer.split("x.tar.gz").ext == "tar.gz")
    }

    @Test func routes() {
        let router = Registry.makeRouter(tools: tools)
        #expect(router.route(from: Formats.png, to: Formats.jpg)?.count == 1)
        #expect(router.route(from: Formats.heic, to: Formats.webp)?.map(\.output) == [Formats.png, Formats.webp])
        #expect(router.route(from: Formats.docx, to: Formats.jpg)?.map(\.output) == [Formats.pdf, Formats.jpg])
        #expect(router.route(from: Formats.jpg, to: Formats.txt) == nil)
        #expect(router.route(from: Formats.mp3, to: Formats.jpg) == nil)
        // Without cwebp there's no WebP, and without ffmpeg no video.
        let bare = Registry.makeRouter(tools: Tools())
        #expect(bare.route(from: Formats.png, to: Formats.webp) == nil)
        #expect(bare.route(from: Formats.mp4, to: Formats.mov) == nil)
    }

    @Test func targets() {
        let catalog = Catalog(router: Registry.makeRouter(tools: tools))
        let png = catalog.targets(forFormats: [Formats.png]).map(\.id)
        #expect(png.first == "jpg")
        #expect(png.contains("webp"))
        #expect(!png.contains("png"))
        #expect(png.contains("zip"))

        let pdfs = catalog.targets(forFormats: [Formats.pdf, Formats.pdf]).map(\.id)
        #expect(pdfs.contains("pdf-merge"))
        #expect(pdfs.contains("pdf-compress"))

        let images = catalog.targets(forFormats: [Formats.png, Formats.jpg])
        #expect(images.first { $0.id == "pdf" }?.mode == .byOption)

        let videos = catalog.targets(forFormats: [Formats.mp4, Formats.mov]).map(\.id)
        #expect(videos.contains("mp4") && videos.contains("mov"))

        let mixed = catalog.targets(forFormats: [Formats.png, Formats.mp3]).map(\.id)
        #expect(Set(mixed) == ["zip", "tgz"])

        #expect(catalog.targets(forFormats: [Formats.zip]).map(\.id).contains("folder"))
        let jpg = catalog.targets(forFormats: [Formats.png]).first { $0.id == "jpg" }
        #expect(jpg?.defaultOption == Options.balanced)
    }
}
