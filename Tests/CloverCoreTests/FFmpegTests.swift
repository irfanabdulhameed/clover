import Foundation
import Testing
@testable import CloverCore

// The first suite builds commands and parses output without running anything.
// The second runs the real ffmpeg when it is installed.

private let allEncoders: Set<String> = [
    "h264_videotoolbox", "libx264", "aac_at", "aac", "libvpx-vp9", "libopus", "libmp3lame", "flac", "alac",
]

private let input = URL(fileURLWithPath: "/tmp/in/clip.mov")
private let output = URL(fileURLWithPath: "/tmp/out/clip.mp4")

private func video(_ codec: String, pixel: String = "yuv420p", width: Int = 1920, height: Int = 1080) -> FFmpegMedia.Video {
    FFmpegMedia.Video(index: 0, codec: codec, pixelFormat: pixel, width: width, height: height)
}

private func audio(_ codec: String, rate: Int = 44_100, channels: Int = 2, bits: Int = 0) -> FFmpegMedia.Audio {
    FFmpegMedia.Audio(index: 1, codec: codec, channels: channels, sampleRate: rate, bitDepth: bits)
}

private func plan(to format: Format, _ quality: String = "original", media: FFmpegMedia,
                  encoders: Set<String> = allEncoders, hardware: Bool = true,
                  settings: ConversionSettings = ConversionSettings()) throws -> FFmpegPlan {
    try FFmpegPlan.make(input: input, output: output.deletingPathExtension().appendingPathExtension(format.fileExtension),
                        to: format, quality: quality, media: media, encoders: encoders, settings: settings,
                        hardwareQuality: hardware)
}

/// The value after `key` in an argument list.
private func value(after key: String, in arguments: [String]) -> String? {
    guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

struct FFmpegPlanTests {
    @Test func offersTheRightFormats() {
        let converter = FFmpegConverter()
        let fromMP4 = converter.outputs(from: Formats.mp4)
        #expect(fromMP4.contains(Formats.mov) && fromMP4.contains(Formats.gif) && fromMP4.contains(Formats.mp3))
        #expect(!fromMP4.contains(Formats.mp4))
        #expect(!converter.outputs(from: Formats.mp3).contains(Formats.mp4))
        #expect(converter.outputs(from: Formats.gif) == [Formats.mp4, Formats.webm])
        #expect(converter.outputs(from: Formats.jpg).isEmpty)
    }

    // MARK: Remux

    @Test func copyDecisions() {
        #expect(FFmpegPlan.canCopyVideo(video("h264"), into: Formats.mp4))
        #expect(FFmpegPlan.canCopyVideo(video("hevc", pixel: "yuv420p10le"), into: Formats.mp4))
        #expect(!FFmpegPlan.canCopyVideo(video("h264", pixel: "yuv422p10le"), into: Formats.mp4))
        #expect(!FFmpegPlan.canCopyVideo(video("vp9"), into: Formats.mp4))
        #expect(!FFmpegPlan.canCopyVideo(video("gif", pixel: "bgra"), into: Formats.mkv))
        #expect(FFmpegPlan.canCopyVideo(video("vp9"), into: Formats.webm))
        #expect(FFmpegPlan.canCopyVideo(video("mpeg4"), into: Formats.mkv))
        #expect(FFmpegPlan.canCopyAudio(audio("aac"), into: Formats.mp4))
        #expect(!FFmpegPlan.canCopyAudio(audio("opus"), into: Formats.mp4))
        #expect(FFmpegPlan.canCopyAudio(audio("opus"), into: Formats.webm))
        #expect(!FFmpegPlan.canCopyAudio(audio("aac"), into: Formats.webm))
    }

    @Test func movToMP4OriginalIsACopy() throws {
        let media = FFmpegMedia(duration: 3, video: video("h264"), audio: audio("aac"))
        let p = try plan(to: Formats.mp4, media: media)
        let first = p.steps[0].arguments
        #expect(first.starts(with: ["-hide_banner", "-nostdin", "-y"]))
        #expect(first.contains("-nostats") && value(after: "-progress", in: first) == "pipe:1")
        #expect(value(after: "-c:v", in: first) == "copy" && value(after: "-c:a", in: first) == "copy")
        #expect(!first.contains("-vf"))
        #expect(value(after: "-movflags", in: first) == "+faststart")
        #expect(first.last == "/tmp/out/clip.mp4")
        // If the copy fails, a full re-encode follows.
        #expect(p.steps[0].fallbacks.first.flatMap { value(after: "-c:v", in: $0) } == "h264_videotoolbox")
    }

    @Test func otherOptionsNeverCopy() throws {
        let media = FFmpegMedia(duration: 3, video: video("h264"), audio: audio("aac"))
        for quality in ["1080p", "720p", "small"] {
            let args = try plan(to: Formats.mp4, quality, media: media).steps[0].arguments
            #expect(value(after: "-c:v", in: args) == "h264_videotoolbox")
            #expect(value(after: "-c:a", in: args) == "aac_at")
            #expect(args.contains("-vf"))
        }
    }

    @Test func hevcKeepsAppleTag() throws {
        let media = FFmpegMedia(duration: 3, video: video("hevc", pixel: "yuv420p10le"), audio: audio("aac"))
        let args = try plan(to: Formats.mp4, media: media).steps[0].arguments
        #expect(value(after: "-c:v", in: args) == "copy" && value(after: "-tag:v", in: args) == "hvc1")
    }

    @Test func aviCopiesOnlyWhatFits() throws {
        let media = FFmpegMedia(duration: 3, video: video("mpeg4"), audio: audio("mp3"))
        let args = try plan(to: Formats.mp4, media: media).steps[0].arguments
        #expect(value(after: "-c:v", in: args) == "h264_videotoolbox")
        #expect(value(after: "-c:a", in: args) == "copy")
    }

    // MARK: Video encoding

    @Test func h264Settings() throws {
        let media = FFmpegMedia(duration: 3, video: video("vp9"), audio: audio("opus"))
        let normal = try plan(to: Formats.mp4, media: media)
        let a = normal.steps[0].arguments
        #expect(value(after: "-q:v", in: a) == "55")
        #expect(value(after: "-pix_fmt", in: a) == "yuv420p" && value(after: "-tag:v", in: a) == "avc1")
        #expect(value(after: "-b:a", in: a) == "192k")
        let software = normal.steps[0].fallbacks.last!
        #expect(value(after: "-c:v", in: software) == "libx264" && value(after: "-crf", in: software) == "20")
        #expect(value(after: "-preset", in: software) == "medium" && value(after: "-c:a", in: software) == "aac")

        let small = try plan(to: Formats.mp4, "small", media: media)
        #expect(value(after: "-q:v", in: small.steps[0].arguments) == "35")
        #expect(value(after: "-crf", in: small.steps[0].fallbacks.last!) == "28")
    }

    @Test func noHardwareQualityMeansSoftware() throws {
        let media = FFmpegMedia(duration: 3, video: video("vp9"), audio: audio("opus"))
        let wmv = FFmpegMedia(duration: 3, video: video("wmv2"), audio: audio("wmav2"))
        let p = try plan(to: Formats.mkv, media: wmv, hardware: false)
        #expect(value(after: "-c:v", in: p.steps[0].arguments) == "libx264")
        #expect(value(after: "-tag:v", in: p.steps[0].arguments) == nil)   // MKV has no avc1 tag
        #expect(value(after: "-movflags", in: p.steps[0].arguments) == nil)
        #expect(throws: ConversionError.self) {
            try plan(to: Formats.mp4, media: media, encoders: ["aac"], hardware: false)
        }
    }

    @Test func webm() throws {
        let media = FFmpegMedia(duration: 3, video: video("h264"), audio: audio("aac"))
        let a = try plan(to: Formats.webm, media: media).steps[0].arguments
        #expect(value(after: "-c:v", in: a) == "libvpx-vp9" && value(after: "-crf", in: a) == "32")
        #expect(value(after: "-b:v", in: a) == "0" && value(after: "-row-mt", in: a) == "1")
        #expect(value(after: "-deadline", in: a) == "good" && value(after: "-cpu-used", in: a) == "4")
        #expect(value(after: "-c:a", in: a) == "libopus")
    }

    @Test func scaling() {
        #expect(FFmpegPlan.heightLimit(for: "original") == nil)
        #expect(FFmpegPlan.heightLimit(for: "1080p") == 1080)
        #expect(FFmpegPlan.heightLimit(for: "720p") == 720)
        #expect(FFmpegPlan.heightLimit(for: "small") == 480)
        #expect(FFmpegPlan.heightLimit(for: "balanced") == nil)
        let f = FFmpegPlan.scaleFilter(limit: 720)
        // Shorter side capped at 720, never above the source, always even.
        #expect(f.contains("min(720,ih)") && f.contains("min(720,iw)") && f.contains("/2)*2"))
        #expect(FFmpegPlan.scaleFilter(limit: nil).contains("trunc(iw/2)*2"))
        #expect(!FFmpegPlan.scaleFilter(limit: nil).contains("min("))
    }

    // MARK: GIF

    @Test func gifPlan() throws {
        let media = FFmpegMedia(duration: 3, video: video("h264"), audio: audio("aac"))
        #expect([("large", 720), ("medium", 480), ("small", 320), ("original", 480)].allSatisfy { FFmpegPlan.gifWidth(for: $0.0) == $0.1 })
        let p = try plan(to: Formats.gif, "large", media: media)
        #expect(p.steps.count == 2 && p.scratch.count == 1)
        #expect(p.steps[0].arguments.contains { $0.contains("palettegen") && $0.contains("fps=15") && $0.contains("min(720,iw)") })
        #expect(p.steps[1].arguments.contains { $0.contains("paletteuse") })
        #expect(p.steps.map(\.weight).reduce(0, +) == 1)
        #expect(p.steps[1].arguments.last == "/tmp/out/clip.gif")
    }

    @Test func gifToVideoIsEvenAndYUV420() throws {
        let gif = FFmpegMedia(duration: 2, video: video("gif", pixel: "bgra", width: 321, height: 181), audio: nil)
        let a = try plan(to: Formats.mp4, media: gif).steps[0].arguments
        #expect(a.contains { $0.hasPrefix("scale=") && $0.contains("trunc(iw/2)*2") })
        #expect(value(after: "-pix_fmt", in: a) == "yuv420p")
        #expect(!a.contains("-c:a"))
    }

    // MARK: Audio

    @Test func audioOptionMapping() throws {
        func arguments(_ format: Format, _ quality: String, _ encoders: Set<String> = allEncoders) throws -> [String] {
            try plan(to: format, quality, media: FFmpegMedia(duration: 3, audio: audio("flac")), encoders: encoders).steps[0].arguments
        }
        #expect([("best", "0"), ("balanced", "2"), ("small", "5")].allSatisfy { FFmpegPlan.mp3Quality(for: $0.0) == ["-q:a", $0.1] })
        #expect(value(after: "-q:a", in: try arguments(Formats.mp3, "best")) == "0")
        #expect(value(after: "-b:a", in: try arguments(Formats.m4a, "best")) == "256k")
        #expect(value(after: "-b:a", in: try arguments(Formats.m4a, "balanced")) == "192k")
        #expect(value(after: "-b:a", in: try arguments(Formats.m4a, "small")) == "128k")
        #expect(value(after: "-c:a", in: try arguments(Formats.m4a, "lossless")) == "alac")
        #expect(value(after: "-c:a", in: try arguments(Formats.m4a, "best")) == "aac_at")
        #expect(value(after: "-b:a", in: try arguments(Formats.opus, "best")) == "160k")
        #expect(value(after: "-b:a", in: try arguments(Formats.opus, "balanced")) == "128k")
        #expect(value(after: "-b:a", in: try arguments(Formats.opus, "small")) == "96k")
        #expect(value(after: "-c:a", in: try arguments(Formats.flac, "balanced")) == "flac")
        // No Vorbis encoder: Ogg carries Opus. With one, Ogg carries Vorbis.
        #expect(value(after: "-c:a", in: try arguments(Formats.ogg, "balanced")) == "libopus")
        #expect(value(after: "-c:a", in: try arguments(Formats.ogg, "balanced", allEncoders.union(["libvorbis"]))) == "libvorbis")
        // Without AudioToolbox the built-in AAC encoder is used.
        #expect(value(after: "-c:a", in: try arguments(Formats.m4a, "best", allEncoders.subtracting(["aac_at"]))) == "aac")
    }

    @Test func aacFallsBackToTheBuiltInEncoder() throws {
        let p = try plan(to: Formats.m4a, "best", media: FFmpegMedia(duration: 3, audio: audio("wav")))
        #expect(value(after: "-c:a", in: p.steps[0].arguments) == "aac_at")
        #expect(value(after: "-c:a", in: p.steps[0].fallbacks[0]) == "aac")
    }

    @Test func bitDepthFollowsTheSource() throws {
        func codec(_ format: Format, bits: Int) throws -> String? {
            let media = FFmpegMedia(duration: 3, audio: audio("pcm", bits: bits))
            return value(after: "-c:a", in: try plan(to: format, media: media).steps[0].arguments)
        }
        #expect(try codec(Formats.wav, bits: 16) == "pcm_s16le")
        #expect(try codec(Formats.wav, bits: 24) == "pcm_s24le")
        #expect(try codec(Formats.wav, bits: 0) == "pcm_s16le")      // lossy source
        #expect(try codec(Formats.aiff, bits: 16) == "pcm_s16be")
        #expect(try codec(Formats.aiff, bits: 32) == "pcm_s24be")
        let flac = try plan(to: Formats.flac, media: FFmpegMedia(duration: 3, audio: audio("pcm", bits: 24))).steps[0].arguments
        #expect(value(after: "-bits_per_raw_sample", in: flac) == "24")
    }

    @Test func lossyEncodersGetSafeRatesAndChannels() throws {
        let hires = FFmpegMedia(duration: 3, audio: audio("pcm", rate: 96_000, channels: 6, bits: 24))
        let mp3 = try plan(to: Formats.mp3, media: hires).steps[0].arguments
        #expect(value(after: "-ar", in: mp3) == "48000" && value(after: "-ac", in: mp3) == "2")
        let m4a = try plan(to: Formats.m4a, media: hires).steps[0].arguments
        #expect(value(after: "-ar", in: m4a) == "48000" && value(after: "-ac", in: m4a) == nil)
        let plain = try plan(to: Formats.mp3, media: FFmpegMedia(duration: 3, audio: audio("mp3"))).steps[0].arguments
        #expect(!plain.contains("-ar") && !plain.contains("-ac"))
    }

    @Test func audioOutputsLeaveVideoOut() throws {
        // A video file turned into audio maps only its audio; so does an MP3 with cover art.
        let media = FFmpegMedia(duration: 3, video: video("h264"), audio: audio("aac"))
        let args = try plan(to: Formats.mp3, media: media).steps[0].arguments
        #expect(args.contains("0:a:0?") && !args.contains("0:v:0?") && !args.contains("-c:v"))
        #expect(args.contains("-map_metadata"))
    }

    // MARK: Settings

    @Test func videoQualityMapping() {
        func q(_ percent: Double, small: Bool = false) -> [Int] {
            let v = FFmpegPlan.VideoEncoderQuality(percent: percent, small: small)
            return [v.videoToolbox, v.x264, v.vp9]
        }
        // The default 60% is what Clover has always used.
        #expect(q(60) == [55, 20, 32])
        #expect(q(60, small: true) == [35, 28, 40])
        // Extremes, and values outside 0...100 stop at them.
        #expect(q(0) == [10, 38, 52] && q(-50) == q(0))
        #expect(q(100) == [100, 12, 15] && q(250) == q(100))
        #expect(q(0, small: true) == [1, 46, 60])
        // Higher percent is always better: -q:v up, crf down.
        var last = q(0)
        for percent in stride(from: 5.0, through: 100, by: 5) {
            let now = q(percent)
            #expect(now[0] >= last[0] && now[1] <= last[1] && now[2] <= last[2])
            last = now
        }
    }

    @Test func videoQualityReachesTheEncoders() throws {
        let media = FFmpegMedia(duration: 3, video: video("vp9"), audio: audio("opus"))
        var settings = ConversionSettings()
        settings.videoQuality = 100
        let mp4 = try plan(to: Formats.mp4, media: media, settings: settings).steps[0]
        #expect(value(after: "-q:v", in: mp4.arguments) == "100")
        #expect(value(after: "-crf", in: mp4.fallbacks.last!) == "12")
        let webm = try plan(to: Formats.webm, "720p", media: media, settings: settings).steps[0].arguments
        #expect(value(after: "-crf", in: webm) == "15")
        settings.videoQuality = 0
        let small = try plan(to: Formats.mp4, "small", media: media, settings: settings).steps[0]
        #expect(value(after: "-q:v", in: small.arguments) == "1")
        #expect(value(after: "-crf", in: small.fallbacks.last!) == "46")
    }

    @Test func smallVideoHeightFollowsTheSettings() throws {
        var settings = ConversionSettings()
        settings.smallVideoHeight = 360
        #expect(FFmpegPlan.heightLimit(for: "small", settings: settings) == 360)
        #expect(FFmpegPlan.heightLimit(for: "720p", settings: settings) == 720)
        let media = FFmpegMedia(duration: 3, video: video("h264"), audio: audio("aac"))
        let args = try plan(to: Formats.mp4, "small", media: media, settings: settings).steps[0].arguments
        #expect(args.contains { $0.hasPrefix("scale=") && $0.contains("min(360,iw)") })
    }

    @Test func gifWidthsFollowTheSettings() throws {
        var settings = ConversionSettings()
        settings.gifWidth = Levels(best: 1000, balanced: 600, small: 200)
        #expect([("large", 1000), ("medium", 600), ("small", 200)].allSatisfy { FFmpegPlan.gifWidth(for: $0.0, settings: settings) == $0.1 })
        let media = FFmpegMedia(duration: 3, video: video("h264"), audio: audio("aac"))
        let p = try plan(to: Formats.gif, "small", media: media, settings: settings)
        #expect(p.steps[0].arguments.contains { $0.contains("palettegen") && $0.contains("min(200,iw)") })
    }

    @Test func audioBitratesMapToEachEncoder() {
        let defaults = ConversionSettings()
        // AAC takes the number as it is.
        #expect(["best", "balanced", "small"].map { FFmpegPlan.m4aBitrate(for: $0) } == ["256k", "192k", "128k"])
        #expect(FFmpegPlan.aacBitrate(kbps: 500) == "320k" && FFmpegPlan.aacBitrate(kbps: 8) == "32k")
        // Opus: half the AAC rate plus 32, which keeps the old 160 / 128 / 96.
        #expect(["best", "balanced", "small"].map { FFmpegPlan.opusBitrate(for: $0) } == ["160k", "128k", "96k"])
        #expect(FFmpegPlan.opusKbps(matchingAAC: 320) == 192 && FFmpegPlan.opusKbps(matchingAAC: 0) == 32)
        // Vorbis: one quality step per 32 kbit/s, giving the old 6 / 4 / 2.
        #expect(["best", "balanced", "small"].map { FFmpegPlan.vorbisLevel(for: $0) } == ["6", "4", "2"])
        #expect(FFmpegPlan.vorbisLevel(for: "best", settings: { var s = defaults; s.audioBitrate = Levels(best: 320, balanced: 192, small: 112); return s }()) == "8")
        // MP3: nearest LAME VBR level (V0 245, V2 190, V5 130 ... V9 65) up to 256, then constant bitrate.
        #expect(FFmpegPlan.mp3Quality(kbps: 256) == ["-q:a", "0"])
        #expect(FFmpegPlan.mp3Quality(kbps: 192) == ["-q:a", "2"])
        #expect(FFmpegPlan.mp3Quality(kbps: 128) == ["-q:a", "5"])
        #expect(FFmpegPlan.mp3Quality(kbps: 160) == ["-q:a", "4"])
        #expect(FFmpegPlan.mp3Quality(kbps: 64) == ["-q:a", "9"] && FFmpegPlan.mp3Quality(kbps: 8) == ["-q:a", "9"])
        #expect(FFmpegPlan.mp3Quality(kbps: 320) == ["-b:a", "320k"] && FFmpegPlan.mp3Quality(kbps: 999) == ["-b:a", "320k"])
    }

    @Test func audioBitratesReachTheCommands() throws {
        var settings = ConversionSettings()
        settings.audioBitrate = Levels(best: 320, balanced: 160, small: 64)
        func arguments(_ format: Format, _ quality: String, _ encoders: Set<String> = allEncoders) throws -> [String] {
            try plan(to: format, quality, media: FFmpegMedia(duration: 3, audio: audio("flac")), encoders: encoders, settings: settings).steps[0].arguments
        }
        #expect(value(after: "-b:a", in: try arguments(Formats.m4a, "best")) == "320k")
        #expect(value(after: "-b:a", in: try arguments(Formats.m4a, "small")) == "64k")
        // Lossless stays ALAC whatever the bitrates are.
        #expect(value(after: "-c:a", in: try arguments(Formats.m4a, "lossless")) == "alac")
        #expect(!(try arguments(Formats.m4a, "lossless")).contains("-b:a"))
        #expect(value(after: "-b:a", in: try arguments(Formats.mp3, "best")) == "320k")
        #expect(value(after: "-q:a", in: try arguments(Formats.mp3, "balanced")) == "4")
        #expect(value(after: "-b:a", in: try arguments(Formats.opus, "best")) == "192k")
        #expect(value(after: "-b:a", in: try arguments(Formats.opus, "small")) == "64k")
        #expect(value(after: "-b:a", in: try arguments(Formats.ogg, "balanced")) == "112k")          // Opus in Ogg
        #expect(value(after: "-q:a", in: try arguments(Formats.ogg, "balanced", allEncoders.union(["libvorbis"]))) == "3")
    }

    @Test func audioInsideVideoUsesTheBalancedRate() throws {
        let media = FFmpegMedia(duration: 3, video: video("vp9"), audio: audio("opus"))
        func rates(_ settings: ConversionSettings, _ quality: String = "720p") throws -> [String?] {
            [value(after: "-b:a", in: try plan(to: Formats.mp4, quality, media: media, settings: settings).steps[0].arguments),
             value(after: "-b:a", in: try plan(to: Formats.webm, quality, media: media, settings: settings).steps[0].arguments)]
        }
        #expect(try rates(ConversionSettings()) == ["192k", "128k"])
        #expect(try rates(ConversionSettings(), "small") == ["128k", "96k"])
        var settings = ConversionSettings()
        settings.audioBitrate = Levels(best: 320, balanced: 256, small: 224)
        // Never more than 192.
        #expect(try rates(settings) == ["192k", "128k"])
        #expect(try rates(settings, "small") == ["192k", "128k"])
        settings.audioBitrate = Levels(best: 256, balanced: 96, small: 64)
        #expect(try rates(settings) == ["96k", "80k"])
    }

    // MARK: Missing streams

    @Test func missingStreamsGiveHumanErrors() {
        let silent = FFmpegMedia(duration: 3, video: video("h264"), audio: nil)
        #expect(throws: ConversionError.failed("This file has no audio track.")) { try plan(to: Formats.mp3, media: silent) }
        #expect(throws: ConversionError.failed("This file has no audio track.")) { try plan(to: Formats.m4a, media: silent) }
        let song = FFmpegMedia(duration: 3, video: nil, audio: audio("mp3"))
        #expect(throws: ConversionError.failed("This file has no video track.")) { try plan(to: Formats.mp4, media: song) }
        #expect(throws: ConversionError.failed("This file has no video track.")) { try plan(to: Formats.gif, media: song) }
    }
}

struct FFmpegParsingTests {
    @Test func progressLines() {
        #expect(FFmpegProgress.fraction(from: "out_time_us=1500000", duration: 3) == 0.5)
        #expect(FFmpegProgress.fraction(from: "out_time_ms=1500000", duration: 3) == 0.5)
        #expect(FFmpegProgress.fraction(from: "out_time_us=9000000", duration: 3) == 1)
        #expect(FFmpegProgress.fraction(from: "out_time_us=-9223372036854775807", duration: 3) == 0)
        #expect(FFmpegProgress.fraction(from: "out_time_us=N/A", duration: 3) == nil)
        #expect(FFmpegProgress.fraction(from: "out_time_us=1500000", duration: nil) == nil)
        #expect(FFmpegProgress.fraction(from: "frame=42", duration: 3) == nil)
        #expect(FFmpegProgress.fraction(from: "progress=end", duration: nil) == 1)
    }

    @Test func ffprobeJSON() throws {
        let json = """
        {"streams": [
          {"index": 0, "codec_type": "video", "codec_name": "mjpeg", "pix_fmt": "yuvj420p", "width": 600, "height": 600,
           "disposition": {"attached_pic": 1}},
          {"index": 1, "codec_type": "audio", "codec_name": "flac", "sample_fmt": "s32", "sample_rate": "48000",
           "channels": 2, "bits_per_raw_sample": "24", "bits_per_sample": 0, "duration": "3.000000"}],
         "format": {"duration": "3.012000", "format_name": "flac"}}
        """
        let media = try #require(FFmpegMedia.parse(probeJSON: Data(json.utf8)))
        #expect(media.video == nil)                    // cover art isn't video
        #expect(media.audio == FFmpegMedia.Audio(index: 1, codec: "flac", channels: 2, sampleRate: 48_000, bitDepth: 24))
        #expect(media.duration == 3.012)

        let movie = """
        {"streams": [{"index": 0, "codec_type": "video", "codec_name": "h264", "pix_fmt": "yuv420p", "width": 1920, "height": 1080},
                     {"index": 1, "codec_type": "audio", "codec_name": "aac", "sample_rate": "44100", "channels": 2}],
         "format": {"duration": "10.5"}}
        """
        let parsed = try #require(FFmpegMedia.parse(probeJSON: Data(movie.utf8)))
        #expect(parsed.video?.codec == "h264" && parsed.video?.width == 1920 && parsed.video?.isFirst == true)
        #expect(parsed.audio?.bitDepth == 0)           // lossy
        #expect(FFmpegMedia.parse(probeJSON: Data("nonsense".utf8)) == nil)
    }

    @Test func ffmpegBanner() {
        let banner = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'a.mp4':
          Metadata:
            major_brand     : isom
          Duration: 00:01:02.50, start: 0.000000, bitrate: 1234 kb/s
          Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709, progressive), 1280x720 [SAR 1:1 DAR 16:9], 1100 kb/s, 30 fps, 30 tbr, 15360 tbn (default)
          Stream #0:1[0x2](und): Audio: aac (LC) (mp4a / 0x6134706d), 48000 Hz, 5.1(side), fltp, 128 kb/s (default)
        At least one output file must be specified
        """
        let media = FFmpegMedia.parse(banner: banner)
        #expect(media.duration == 62.5)
        #expect(media.video == FFmpegMedia.Video(index: 0, isFirst: true, codec: "h264", pixelFormat: "yuv420p", width: 1280, height: 720))
        #expect(media.audio == FFmpegMedia.Audio(index: 1, codec: "aac", channels: 6, sampleRate: 48_000, bitDepth: 0))
        #expect(FFmpegMedia.parse(banner: "x.mp4: Invalid data found when processing input").video == nil)
    }

    @Test func encoderList() {
        let text = """
        Encoders:
         V..... = Video
         ------
         V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)
         A....D flac                 FLAC (Free Lossless Audio Codec)
         A..... aac_at               aac (AudioToolbox) (codec aac)
        """
        #expect(FFmpegEncoders.parse(text) == ["libx264", "flac", "aac_at"])
    }

    @Test func humanErrors() {
        #expect(FFmpegErrors.message(fromStderr: "x.mp4: Invalid data found when processing input\n") == "ffmpeg couldn't read this file.")
        #expect(FFmpegErrors.message(fromStderr: "[mov,mp4 @ 0x1] moov atom not found") == "ffmpeg couldn't read this file.")
        #expect(FFmpegErrors.message(fromStderr: "Error writing output: No space left on device") == "There isn't enough free disk space.")
        #expect(FFmpegErrors.message(fromStderr: "[h264 @ 0x1] weird thing happened") == "ffmpeg couldn't convert this file: weird thing happened")
        #expect(FFmpegErrors.message(fromStderr: "") == "ffmpeg couldn't convert this file.")
    }
}

/// Runs the real ffmpeg. Skipped when it isn't installed.
@Suite(.serialized)
struct FFmpegRunTests {
    static let tools = Tools.detect()
    static let installed = tools.ffmpeg != nil && tools.ffprobe != nil

    private func makeClip(seconds: Int, size: String, in directory: URL) async throws -> URL {
        let clip = directory.appendingPathComponent("clip.mp4")
        try await ProcessRunner.run(Self.tools.ffmpeg!, [
            "-hide_banner", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=\(size):rate=30:duration=\(seconds)",
            "-f", "lavfi", "-i", "sine=duration=\(seconds)", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
            "-c:a", "aac", clip.path,
        ])
        return clip
    }

    @Test(.enabled(if: FFmpegRunTests.installed))
    func convertsAndReportsProgress() async throws {
        let directory = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try await makeClip(seconds: 2, size: "320x180", in: directory)
        let work = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: work) }

        let seen = Locked<[Double]>([])
        let context = StepContext(option: Options.balanced, tools: Self.tools) { p in seen.update { $0.append(p) } }
        let made = try await FFmpegConverter().convert(clip, from: Formats.mp4, to: Formats.mp3, into: work, baseName: "clip", context: context)
        #expect(made.map(\.lastPathComponent) == ["clip.mp3"])
        let size = try made[0].resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 0)
        let values = seen.value
        #expect(!values.isEmpty && values.allSatisfy { (0...1).contains($0) })
        #expect(values.last == 1)
        #expect(values == values.sorted())
    }

    @Test(.enabled(if: FFmpegRunTests.installed))
    func probesWithoutFFprobeAndRejectsGarbage() async throws {
        let directory = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try await makeClip(seconds: 2, size: "320x180", in: directory)

        let noProbe = Tools(ffmpeg: Self.tools.ffmpeg, ffprobe: nil)
        let media = try await FFmpegMedia.probe(clip, tools: noProbe)
        #expect(abs((media.duration ?? 0) - 2) < 0.2)
        #expect(media.video?.codec == "h264" && media.video?.width == 320 && media.audio?.codec == "aac")

        let garbage = directory.appendingPathComponent("garbage.mp4")
        try Data(repeating: 7, count: 5_000).write(to: garbage)
        for tools in [Self.tools, noProbe] {
            await #expect(throws: ConversionError.failed("ffmpeg couldn't read this file.")) {
                try await FFmpegMedia.probe(garbage, tools: tools)
            }
        }
    }

    @Test(.enabled(if: FFmpegRunTests.installed))
    func cancellationStopsFFmpegAndLeavesNothing() async throws {
        let directory = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A minute of video that takes VP9 well over the 1.5 s before the cancel.
        let clip = try await makeClip(seconds: 60, size: "1280x720", in: directory)
        let work = try OutputPlacer.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: work) }

        let context = StepContext(option: Options.original, tools: Self.tools)
        let started = Date()
        let task = Task {
            try await FFmpegConverter().convert(clip, from: Formats.mp4, to: Formats.webm, into: work, baseName: "clip", context: context)
        }
        try await Task.sleep(for: .seconds(1.5))
        task.cancel()
        let outcome = await task.result
        #expect(throws: (any Error).self) { try outcome.get() }
        #expect(Date().timeIntervalSince(started) < 8)
        #expect((try FileManager.default.contentsOfDirectory(atPath: work.path)).isEmpty)

        // No ffmpeg is still working on this folder.
        let check = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-f", work.path], allowFailure: true)
        #expect(check.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

/// A value guarded by a lock, for progress callbacks that may arrive from any thread.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func update(_ body: (inout Value) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}
