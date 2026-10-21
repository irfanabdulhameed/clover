import Foundation

/// Video and audio through ffmpeg.
///
/// Each conversion is: probe the file, build the ffmpeg commands as plain data
/// (`FFmpegPlan`, no process involved), then run them and report progress.
public struct FFmpegConverter: Converter {
    public let id = "ffmpeg"
    public init() {}

    public func outputs(from input: Format) -> [Format] {
        if FormatTables.videoRead.contains(input) { return FormatTables.videoWrite.filter { $0 != input } }
        if FormatTables.audioRead.contains(input) { return FormatTables.audioWrite.filter { $0 != input } }
        if input == Formats.gif { return FormatTables.gifToVideo }
        return []
    }

    public func isAvailable(_ tools: Tools) -> Bool { tools.ffmpeg != nil }

    public func convert(_ input: URL, from: Format, to: Format, into directory: URL, baseName: String, context: StepContext) async throws -> [URL] {
        guard let ffmpeg = context.tools.ffmpeg else { throw ConversionError.toolMissing("ffmpeg") }
        let media = try await FFmpegMedia.probe(input, tools: context.tools)
        let encoders = await FFmpegEncoders.available(ffmpeg)
        try Task.checkCancellation()

        let output = directory.appendingPathComponent("\(baseName).\(to.fileExtension)")
        let plan = try FFmpegPlan.make(input: input, output: output, to: to, quality: context.quality,
                                       media: media, encoders: encoders)
        defer { plan.removeScratchFiles() }
        do {
            try await plan.run(ffmpeg: ffmpeg, duration: media.duration, progress: context.progress)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return [output]
    }
}

// MARK: - What is in a file

/// The streams Clover cares about: the first real video stream (not cover art) and the first audio stream.
struct FFmpegMedia: Equatable {
    struct Video: Equatable {
        /// Stream index in the file.
        var index: Int
        /// Whether it is also the first video stream, so `0:v:0` finds it.
        var isFirst = true
        var codec: String
        var pixelFormat = ""
        var width = 0
        var height = 0
    }

    struct Audio: Equatable {
        var index: Int
        var codec: String
        var channels = 2
        var sampleRate = 44_100
        /// 16, 24, 32 for lossless and PCM sources; 0 for lossy ones.
        var bitDepth = 0
    }

    var duration: Double?
    var video: Video?
    var audio: Audio?

    // MARK: ffprobe

    /// Asks ffprobe, and falls back to reading ffmpeg's own banner when ffprobe is missing or fails.
    static func probe(_ input: URL, tools: Tools) async throws -> FFmpegMedia {
        if let ffprobe = tools.ffprobe {
            let result = try await ProcessRunner.run(
                ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", input.path],
                allowFailure: true)
            if result.status == 0, let media = parse(probeJSON: Data(result.stdout.utf8)) { return media }
        }
        guard let ffmpeg = tools.ffmpeg else { throw ConversionError.toolMissing("ffmpeg") }
        let result = try await ProcessRunner.run(ffmpeg, ["-hide_banner", "-nostdin", "-i", input.path], allowFailure: true)
        let media = parse(banner: result.stderr)
        guard media.duration != nil || media.video != nil || media.audio != nil else {
            throw ConversionError.failed(FFmpegErrors.cantRead)
        }
        return media
    }

    private struct ProbeOutput: Decodable {
        struct Stream: Decodable {
            struct Disposition: Decodable { var attachedPic: Int? }
            var index: Int
            var codecType: String?
            var codecName: String?
            var pixFmt: String?
            var width: Int?
            var height: Int?
            var channels: Int?
            var sampleRate: String?
            var bitsPerRawSample: String?
            var bitsPerSample: Int?
            var duration: String?
            var disposition: Disposition?
        }
        struct Format: Decodable { var duration: String? }
        var streams: [Stream]?
        var format: Format?
    }

    /// Reads `ffprobe -print_format json -show_format -show_streams`.
    static func parse(probeJSON data: Data) -> FFmpegMedia? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let output = try? decoder.decode(ProbeOutput.self, from: data) else { return nil }
        let streams = output.streams ?? []
        var media = FFmpegMedia()

        let videos = streams.filter { $0.codecType == "video" }
        if let v = videos.first(where: { $0.disposition?.attachedPic != 1 }) {
            media.video = Video(index: v.index, isFirst: v.index == videos.first?.index, codec: v.codecName ?? "",
                                pixelFormat: v.pixFmt ?? "", width: v.width ?? 0, height: v.height ?? 0)
        }
        if let a = streams.first(where: { $0.codecType == "audio" }) {
            let raw = a.bitsPerRawSample.flatMap { Int($0) } ?? 0
            media.audio = Audio(index: a.index, codec: a.codecName ?? "", channels: a.channels ?? 2,
                                sampleRate: a.sampleRate.flatMap { Int($0) } ?? 44_100,
                                bitDepth: max(raw, a.bitsPerSample ?? 0))
        }
        media.duration = output.format?.duration.flatMap { Double($0) }
            ?? streams.compactMap { $0.duration.flatMap { Double($0) } }.max()
        return media
    }

    // MARK: ffmpeg banner

    /// Reads what `ffmpeg -i file` prints on stderr. Less exact than ffprobe, enough to convert.
    static func parse(banner: String) -> FFmpegMedia {
        var media = FFmpegMedia()
        for rawLine in banner.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Duration:") {
                let value = line.dropFirst("Duration:".count).split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
                if media.duration == nil, let value { media.duration = seconds(fromClock: value) }
            } else if line.hasPrefix("Stream #") {
                parseStream(line, into: &media)
            }
        }
        return media
    }

    static func seconds(fromClock text: String) -> Double? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    private static func parseStream(_ line: String, into media: inout FFmpegMedia) {
        // "Stream #0:1[0x2](und): Audio: aac (LC) (mp4a / 0x6134706d), 44100 Hz, stereo, fltp, 128 kb/s"
        guard let colon = line.firstIndex(of: ":") else { return }
        let afterHash = line[line.index(after: colon)...]
        let index = Int(afterHash.prefix { $0.isNumber }) ?? 0
        let isVideo = line.contains(": Video: ")
        let isAudio = line.contains(": Audio: ")
        guard isVideo || isAudio, let kind = line.range(of: isVideo ? ": Video: " : ": Audio: ") else { return }
        let fields = topLevelFields(String(line[kind.upperBound...]))
        guard let codec = fields.first?.split(separator: " ").first.map(String.init) else { return }

        if isVideo {
            guard media.video == nil, !line.contains("(attached pic)") else { return }
            let pixel = fields.dropFirst().first.map { String($0.prefix { $0 != "(" }) } ?? ""
            var width = 0, height = 0
            for field in fields.dropFirst() {
                let size = field.split(separator: " ").first.map(String.init) ?? ""
                let numbers = size.split(separator: "x").compactMap { Int($0) }
                if numbers.count == 2, size.contains("x") { width = numbers[0]; height = numbers[1]; break }
            }
            media.video = Video(index: index, isFirst: index == 0, codec: codec, pixelFormat: pixel, width: width, height: height)
        } else if media.audio == nil {
            var audio = Audio(index: index, codec: codec)
            for field in fields.dropFirst() {
                if field.hasSuffix(" Hz"), let rate = Int(field.dropLast(3)) { audio.sampleRate = rate }
                switch field {
                case "mono": audio.channels = 1
                case "stereo": audio.channels = 2
                case "quad": audio.channels = 4
                default:
                    if field.hasPrefix("5.1") { audio.channels = 6 }
                    if field.hasPrefix("7.1") { audio.channels = 8 }
                }
                if field.contains("(24 bit)") { audio.bitDepth = 24 }
                else if audio.bitDepth == 0, ["s16", "s16p"].contains(field) { audio.bitDepth = 16 }
                else if audio.bitDepth == 0, ["s32", "s32p"].contains(field), codec.hasPrefix("pcm") { audio.bitDepth = 32 }
            }
            if codec.hasPrefix("pcm_s24") { audio.bitDepth = 24 }
            media.audio = audio
        }
    }

    /// Splits at commas that aren't inside brackets: "yuv420p(tv, bt709), 640x360 [SAR 1:1 DAR 16:9]".
    private static func topLevelFields(_ text: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            default: break
            }
            if character == ",", depth == 0 {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}

// MARK: - Which encoders this ffmpeg has

enum FFmpegEncoders {
    /// Encoders ffmpeg lists, remembered per ffmpeg binary.
    static func available(_ ffmpeg: URL) async -> Set<String> {
        if let known = cache.get(ffmpeg.path) { return known }
        guard let result = try? await ProcessRunner.run(ffmpeg, ["-hide_banner", "-encoders"], allowFailure: true) else {
            return assumed
        }
        let names = parse(result.stdout)
        guard !names.isEmpty else { return assumed }
        cache.set(ffmpeg.path, names)
        return names
    }

    /// Used only when the list can't be read.
    static let assumed: Set<String> = ["libx264", "aac", "libvpx-vp9", "libopus", "libmp3lame", "flac", "alac"]

    /// Lines look like " V....D libx264              libx264 H.264 / AVC".
    static func parse(_ text: String) -> Set<String> {
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let words = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard words.count >= 2, words[0].count == 6, "VAS".contains(words[0].first!), words[1] != "=" else { continue }
            names.insert(String(words[1]))
        }
        return names
    }

    private static let cache = EncoderCache()
}

private final class EncoderCache: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [String: Set<String>] = [:]

    func get(_ key: String) -> Set<String>? { lock.lock(); defer { lock.unlock() }; return table[key] }
    func set(_ key: String, _ value: Set<String>) { lock.lock(); table[key] = value; lock.unlock() }
}

// MARK: - Messages

enum FFmpegErrors {
    static let cantRead = "ffmpeg couldn't read this file."
    static let noAudio = "This file has no audio track."
    static let noVideo = "This file has no video track."

    static func cantWrite(_ what: String) -> ConversionError {
        .failed("This copy of ffmpeg can't write \(what).")
    }

    /// A short sentence for the end of ffmpeg's error output.
    static func message(fromStderr stderr: String) -> String {
        let text = stderr.lowercased()
        let known: [(String, String)] = [
            ("no space left", "There isn't enough free disk space."),
            ("permission denied", "Clover isn't allowed to open this file."),
            ("invalid data found", cantRead),
            ("moov atom not found", cantRead),
            ("could not find codec parameters", cantRead),
            ("does not contain any stream", "This file has no audio or video."),
            ("unknown encoder", "This copy of ffmpeg can't write that format."),
            ("encoder not found", "This copy of ffmpeg can't write that format."),
        ]
        for (needle, message) in known where text.contains(needle) { return message }

        // Last line of the output, without its "[h264 @ 0x...]" prefix.
        var last = stderr.split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        while last.hasPrefix("["), let close = last.firstIndex(of: "]") {
            last = last[last.index(after: close)...].trimmingCharacters(in: .whitespaces)
        }
        return last.isEmpty || last.count > 120 ? "ffmpeg couldn't convert this file." : "ffmpeg couldn't convert this file: \(last)"
    }
}

enum FFmpegProgress {
    /// How far a `-progress pipe:1` line says ffmpeg is, 0...1. Nil for lines that say nothing about it.
    static func fraction(from line: String, duration: Double?) -> Double? {
        if line == "progress=end" { return 1 }
        guard let duration, duration > 0 else { return nil }
        // ffmpeg writes microseconds under both names.
        for key in ["out_time_us=", "out_time_ms="] where line.hasPrefix(key) {
            guard let microseconds = Double(line.dropFirst(key.count)) else { return nil }
            return min(max(microseconds / 1_000_000 / duration, 0), 1)
        }
        return nil
    }
}

// MARK: - The commands

/// One ffmpeg run.
struct FFmpegStep: Equatable {
    var arguments: [String]
    /// Tried in order when `arguments` fail: a full re-encode after a failed copy, then software encoders.
    var fallbacks: [[String]] = []
    /// Share of the whole conversion this run covers, 0...1.
    var weight = 1.0
}

/// One way to make the output file: the input flags, filters and codecs that differ between tries.
struct FFmpegAttempt: Equatable {
    var inputFlags: [String] = []
    var filters: [String] = []
    var video: [String] = []
    var audio: [String] = []
}

/// A video or audio codec choice, with what to try if the first one fails.
struct FFmpegCodec: Equatable {
    var arguments: [String]
    var fallback: [String]?

    init(_ arguments: [String], fallback: [String]? = nil) {
        self.arguments = arguments
        self.fallback = fallback
    }
}

/// Every ffmpeg command a conversion needs, built without running anything.
struct FFmpegPlan: Equatable {
    var steps: [FFmpegStep]
    /// Helper files made in the temp folder, such as the GIF palette.
    var scratch: [URL] = []

    static let common = ["-hide_banner", "-nostdin", "-y", "-v", "error", "-progress", "pipe:1", "-nostats"]

    /// VideoToolbox takes `-q:v` on Apple silicon only; Intel Macs use libx264.
    #if arch(arm64)
    static let hardwareQualityScale = true
    #else
    static let hardwareQualityScale = false
    #endif

    static func make(input: URL, output: URL, to: Format, quality: String, media: FFmpegMedia,
                     encoders: Set<String>, hardwareQuality: Bool = FFmpegPlan.hardwareQualityScale) throws -> FFmpegPlan {
        switch to.family {
        case .audio:
            guard media.audio != nil else { throw ConversionError.failed(FFmpegErrors.noAudio) }
            return try audioPlan(input: input, output: output, to: to, quality: quality, media: media, encoders: encoders)
        case .video:
            guard media.video != nil else { throw ConversionError.failed(FFmpegErrors.noVideo) }
            return try videoPlan(input: input, output: output, to: to, quality: quality, media: media,
                                 encoders: encoders, hardwareQuality: hardwareQuality)
        default:
            guard to == Formats.gif else { throw ConversionError.unsupported("files to \(to.name)") }
            guard media.video != nil else { throw ConversionError.failed(FFmpegErrors.noVideo) }
            return gifPlan(input: input, output: output, quality: quality, media: media)
        }
    }

    // MARK: Option mapping

    /// Longest side limit for the video chips: 1080p, 720p, and "small" (480p). Nil keeps the size.
    static func heightLimit(for quality: String) -> Int? {
        switch quality {
        case "1080p": 1080
        case "720p": 720
        case "small": 480
        default: nil
        }
    }

    /// GIF width for the chips Large, Medium, Small.
    static func gifWidth(for quality: String) -> Int {
        switch quality {
        case "large": 720
        case "small": 320
        default: 480
        }
    }

    /// LAME VBR level: best, balanced, small.
    static func mp3Level(for quality: String) -> String {
        switch quality {
        case "best": "0"
        case "small": "5"
        default: "2"
        }
    }

    /// AAC bitrate for the M4A chips.
    static func m4aBitrate(for quality: String) -> String {
        switch quality {
        case "best": "256k"
        case "small": "128k"
        default: "192k"
        }
    }

    /// Opus bitrate, also used for Ogg when there's no Vorbis encoder.
    static func opusBitrate(for quality: String) -> String {
        switch quality {
        case "best": "160k"
        case "small": "96k"
        default: "128k"
        }
    }

    /// libvorbis quality for the Ogg chips.
    static func vorbisLevel(for quality: String) -> String {
        switch quality {
        case "best": "6"
        case "small": "2"
        default: "4"
        }
    }

    // MARK: Scaling

    /// Scales down so the shorter side is at most `limit` (1080p of a phone video held upright is
    /// 1080 wide), never up, and always to even sizes, which yuv420p needs.
    static func scaleFilter(limit: Int?) -> String {
        guard let limit else { return "scale=w='trunc(iw/2)*2':h='trunc(ih/2)*2'" }
        let w = "if(gte(iw,ih),-2,trunc(min(\(limit),iw)/2)*2)"
        let h = "if(gte(iw,ih),trunc(min(\(limit),ih)/2)*2,-2)"
        return "scale=w='\(w)':h='\(h)'"
    }

    // MARK: Remux

    static func canCopyVideo(_ video: FFmpegMedia.Video, into format: Format) -> Bool {
        let eightBit = ["yuv420p", "yuvj420p"].contains(video.pixelFormat)
        let tenBitOK = eightBit || video.pixelFormat == "yuv420p10le"
        switch format.id {
        case "mp4": return (video.codec == "h264" && eightBit) || (video.codec == "hevc" && tenBitOK)
        case "mov": return (video.codec == "h264" && eightBit) || (video.codec == "hevc" && tenBitOK) || video.codec == "prores"
        case "mkv": return ["h264", "hevc", "vp8", "vp9", "av1", "mpeg4", "mpeg2video", "mpeg1video", "vc1", "theora"].contains(video.codec)
        case "webm": return ["vp8", "vp9", "av1"].contains(video.codec)
        default: return false
        }
    }

    static func canCopyAudio(_ audio: FFmpegMedia.Audio, into format: Format) -> Bool {
        switch format.id {
        case "mp4": return ["aac", "mp3", "ac3", "eac3", "alac"].contains(audio.codec)
        case "mov": return ["aac", "alac", "mp3", "ac3", "eac3", "pcm_s16le", "pcm_s16be", "pcm_s24le", "pcm_s24be"].contains(audio.codec)
        case "mkv": return ["aac", "mp3", "opus", "vorbis", "flac", "ac3", "eac3", "dts", "alac", "truehd",
                            "pcm_s16le", "pcm_s24le", "pcm_s32le"].contains(audio.codec)
        case "webm": return ["opus", "vorbis"].contains(audio.codec)
        default: return false
        }
    }

    // MARK: Video targets

    static func videoPlan(input: URL, output: URL, to: Format, quality: String, media: FFmpegMedia,
                          encoders: Set<String>, hardwareQuality: Bool) throws -> FFmpegPlan {
        guard let video = media.video else { throw ConversionError.failed(FFmpegErrors.noVideo) }
        let limit = heightLimit(for: quality)
        let small = quality == "small"
        // Only "Original" may copy streams as they are.
        let copyVideo = limit == nil && canCopyVideo(video, into: to)
        let copyAudio = limit == nil && media.audio.map { canCopyAudio($0, into: to) } == true

        // Ways to make the file, best first. A copy can fail on odd sources, so it falls back to a full
        // re-encode, and the hardware encoder falls back to software.
        var attempts: [FFmpegAttempt] = []
        var firstError: Error?
        func add(keepVideo: Bool, keepAudio: Bool, software: Bool) {
            var attempt = FFmpegAttempt()
            do {
                if keepVideo {
                    // Apple players want hvc1 on HEVC in MP4 and MOV.
                    let tag = video.codec == "hevc" && ["mp4", "mov"].contains(to.id) ? ["-tag:v", "hvc1"] : []
                    attempt.video = ["-c:v", "copy"] + tag
                } else {
                    let codec = try encodeVideo(for: to, small: small, encoders: encoders, hardwareQuality: hardwareQuality)
                    attempt.video = software ? (codec.fallback ?? codec.arguments) : codec.arguments
                    attempt.filters = ["-vf", scaleFilter(limit: limit)]
                }
                if let audio = media.audio {
                    if keepAudio {
                        attempt.audio = ["-c:a", "copy"]
                    } else {
                        let codec = try encodeAudio(for: to, small: small, audio: audio, encoders: encoders)
                        attempt.audio = software ? (codec.fallback ?? codec.arguments) : codec.arguments
                    }
                }
                // Some sources (MPEG program streams) arrive without timestamps that MKV and MP4 insist on.
                if keepVideo || keepAudio { attempt.inputFlags = ["-fflags", "+genpts"] }
                if !attempts.contains(attempt) { attempts.append(attempt) }
            } catch {
                firstError = firstError ?? error
            }
        }
        if copyVideo || copyAudio { add(keepVideo: copyVideo, keepAudio: copyAudio, software: false) }
        add(keepVideo: false, keepAudio: false, software: false)
        add(keepVideo: false, keepAudio: false, software: true)
        guard !attempts.isEmpty else { throw firstError ?? ConversionError.failed("ffmpeg couldn't convert this file.") }

        let tail = ["mp4", "mov"].contains(to.id) ? ["-movflags", "+faststart"] : []
        let maps = ["-map", video.isFirst ? "0:v:0?" : "0:\(video.index)", "-map", "0:a:0?", "-map_metadata", "0"]
        return FFmpegPlan(steps: [step(input: input, output: output, before: maps, attempts: attempts, after: tail)])
    }

    /// H.264 for MP4, MOV and MKV; VP9 for WebM.
    static func encodeVideo(for format: Format, small: Bool, encoders: Set<String>, hardwareQuality: Bool) throws -> FFmpegCodec {
        if format == Formats.webm {
            guard encoders.contains("libvpx-vp9") else { throw FFmpegErrors.cantWrite("WebM video") }
            return FFmpegCodec(["-c:v", "libvpx-vp9", "-crf", small ? "40" : "32", "-b:v", "0", "-row-mt", "1",
                                "-deadline", "good", "-cpu-used", "4", "-pix_fmt", "yuv420p"])
        }
        let tag = ["mp4", "mov"].contains(format.id) ? ["-tag:v", "avc1"] : []
        let hardware = FFmpegCodec(["-c:v", "h264_videotoolbox", "-q:v", small ? "35" : "55", "-pix_fmt", "yuv420p"] + tag)
        let software = FFmpegCodec(["-c:v", "libx264", "-crf", small ? "28" : "20", "-preset", "medium", "-pix_fmt", "yuv420p"] + tag)
        let hasHardware = hardwareQuality && encoders.contains("h264_videotoolbox")
        let hasSoftware = encoders.contains("libx264")
        switch (hasHardware, hasSoftware) {
        case (true, true): return FFmpegCodec(hardware.arguments, fallback: software.arguments)
        case (true, false): return hardware
        case (false, true): return software
        case (false, false): throw FFmpegErrors.cantWrite("H.264 video")
        }
    }

    /// Audio inside a video file: AAC for MP4, MOV and MKV; Opus for WebM.
    static func encodeAudio(for format: Format, small: Bool, audio: FFmpegMedia.Audio, encoders: Set<String>) throws -> FFmpegCodec {
        if format == Formats.webm {
            return try opus(bitrate: small ? "96k" : "128k", encoders: encoders)
        }
        return try aac(bitrate: small ? "96k" : "160k", audio: audio, encoders: encoders)
    }

    // MARK: GIF

    static func gifPlan(input: URL, output: URL, quality: String, media: FFmpegMedia) -> FFmpegPlan {
        let width = gifWidth(for: quality)
        let video = media.video
        let source = video?.isFirst == false ? "0:\(video!.index)" : "0:v:0"
        let shape = "fps=15,scale=w='min(\(width),iw)':h=-1:flags=lanczos"
        let palette = output.deletingLastPathComponent()
            .appendingPathComponent(output.deletingPathExtension().lastPathComponent + ".palette.png")

        // Two passes, so ffmpeg never has to hold the whole clip in memory while it picks colours.
        let first = FFmpegStep(
            arguments: common + ["-i", input.path, "-map", source + "?", "-an", "-vf", shape + ",palettegen=stats_mode=diff",
                                 "-frames:v", "1", "-update", "1", palette.path],
            weight: 0.25)
        let second = FFmpegStep(
            arguments: common + ["-i", input.path, "-i", palette.path, "-filter_complex",
                                 "[\(source)]\(shape)[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle",
                                 "-an", "-loop", "0", output.path],
            weight: 0.75)
        return FFmpegPlan(steps: [first, second], scratch: [palette])
    }

    // MARK: Audio targets

    static func audioPlan(input: URL, output: URL, to: Format, quality: String, media: FFmpegMedia,
                          encoders: Set<String>) throws -> FFmpegPlan {
        guard let audio = media.audio else { throw ConversionError.failed(FFmpegErrors.noAudio) }
        // Lossless targets keep 24-bit sources at 24 bits.
        let deep = audio.bitDepth >= 24
        var tail: [String] = []
        let codec: FFmpegCodec

        switch to.id {
        case "mp3":
            guard encoders.contains("libmp3lame") else { throw FFmpegErrors.cantWrite("MP3") }
            codec = FFmpegCodec(["-c:a", "libmp3lame", "-q:a", mp3Level(for: quality), "-id3v2_version", "3"]
                                + lossyExtras(audio, maxChannels: 2))
        case "m4a":
            if quality == "lossless" {
                guard encoders.contains("alac") else { throw FFmpegErrors.cantWrite("Apple Lossless") }
                codec = FFmpegCodec(["-c:a", "alac"])
            } else {
                codec = try aac(bitrate: m4aBitrate(for: quality), audio: audio, encoders: encoders)
            }
            tail = ["-movflags", "+faststart"]
        case "wav":
            codec = FFmpegCodec(["-c:a", deep ? "pcm_s24le" : "pcm_s16le", "-rf64", "auto"])
        case "aiff":
            codec = FFmpegCodec(["-c:a", deep ? "pcm_s24be" : "pcm_s16be", "-write_id3v2", "1"])
        case "flac":
            guard encoders.contains("flac") else { throw FFmpegErrors.cantWrite("FLAC") }
            codec = FFmpegCodec(["-c:a", "flac", "-compression_level", "8"]
                                + (deep ? ["-sample_fmt", "s32", "-bits_per_raw_sample", "24"] : ["-sample_fmt", "s16"]))
        case "ogg":
            // Without a Vorbis encoder, Opus in an Ogg file is the next best thing.
            if encoders.contains("libvorbis") {
                codec = FFmpegCodec(["-c:a", "libvorbis", "-q:a", vorbisLevel(for: quality)] + lossyExtras(audio))
            } else {
                codec = try opus(bitrate: opusBitrate(for: quality), encoders: encoders)
            }
        case "opus":
            codec = try opus(bitrate: opusBitrate(for: quality), encoders: encoders)
        default:
            throw ConversionError.unsupported("files to \(to.name)")
        }

        // Audio only: no cover art or video comes along. Ogg and Opus keep their tags on the stream, so those are read too.
        let maps = ["-map", "0:a:0?", "-map_metadata", "0", "-map_metadata:g", "0:s:a:0"]
        var attempts = [FFmpegAttempt(audio: codec.arguments)]
        if let fallback = codec.fallback { attempts.append(FFmpegAttempt(audio: fallback)) }
        return FFmpegPlan(steps: [step(input: input, output: output, before: maps, attempts: attempts, after: tail)])
    }

    // MARK: Shared pieces

    static func aac(bitrate: String, audio: FFmpegMedia.Audio, encoders: Set<String>) throws -> FFmpegCodec {
        let settings = ["-b:a", bitrate] + lossyExtras(audio)
        // AudioToolbox's encoder sounds best, and the built-in one is the safety net.
        switch (encoders.contains("aac_at"), encoders.contains("aac")) {
        case (true, true): return FFmpegCodec(["-c:a", "aac_at"] + settings, fallback: ["-c:a", "aac"] + settings)
        case (true, false): return FFmpegCodec(["-c:a", "aac_at"] + settings)
        case (false, true): return FFmpegCodec(["-c:a", "aac"] + settings)
        case (false, false): throw FFmpegErrors.cantWrite("AAC audio")
        }
    }

    static func opus(bitrate: String, encoders: Set<String>) throws -> FFmpegCodec {
        guard encoders.contains("libopus") else { throw FFmpegErrors.cantWrite("Opus audio") }
        return FFmpegCodec(["-c:a", "libopus", "-b:a", bitrate, "-vbr", "on"])
    }

    /// Lossy encoders get at most 48 kHz (some refuse more), and MP3 at most stereo.
    static func lossyExtras(_ audio: FFmpegMedia.Audio, maxChannels: Int? = nil) -> [String] {
        var arguments: [String] = []
        if audio.sampleRate > 48_000 { arguments += ["-ar", "48000"] }
        if let maxChannels, audio.channels > maxChannels { arguments += ["-ac", "\(maxChannels)"] }
        return arguments
    }

    /// One step: the same input and stream choices, with one command per attempt.
    static func step(input: URL, output: URL, before: [String], attempts: [FFmpegAttempt], after: [String]) -> FFmpegStep {
        let commands = attempts.map { attempt -> [String] in
            var all: [String] = common
            all += attempt.inputFlags
            all += ["-i", input.path]
            all += before
            all += attempt.filters
            all += attempt.video
            all += attempt.audio
            all += after
            all.append(output.path)
            return all
        }
        return FFmpegStep(arguments: commands[0], fallbacks: Array(commands.dropFirst()))
    }

    // MARK: Running

    /// Runs the steps in order, reporting 0...1 over the whole plan.
    func run(ffmpeg: URL, duration: Double?, progress: @escaping @Sendable (Double) -> Void) async throws {
        var done = 0.0
        for step in steps {
            let start = done
            let weight = step.weight
            let report: @Sendable (String) -> Void = { line in
                if let fraction = FFmpegProgress.fraction(from: line, duration: duration) {
                    progress(start + weight * fraction)
                }
            }
            var last: ProcessRunner.Result?
            for command in [step.arguments] + step.fallbacks {
                let result = try await ProcessRunner.run(ffmpeg, command, allowFailure: true, onLine: report)
                last = result
                if result.status == 0 { break }
            }
            guard let last, last.status == 0 else {
                throw ConversionError.failed(FFmpegErrors.message(fromStderr: last?.stderr ?? ""))
            }
            done += weight
            progress(min(done, 1))
        }
    }

    func removeScratchFiles() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
    }
}
