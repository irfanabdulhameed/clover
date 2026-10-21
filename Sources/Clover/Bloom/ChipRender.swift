import AppKit
import SwiftUI
import CloverCore

/// Draws the result chip at fixed moments, to check its timing, blur and landing without
/// waiting for a real conversion. Run with `Clover --render-chip-frames <folder>`; it writes
/// one sheet per motion, light above dark, and checks the curves' numbers first.
///
/// The pictures use the same `ChipPlayback` and `ResultChipView` as the live chip. Live glass
/// never shows in a picture, so they show the frosted stand-in.
@MainActor
enum ChipRender {
    /// One motion: a chip's clock and the moments to draw (seconds since the drop).
    private struct Sequence {
        var name: String
        var playback: ChipPlayback
        var frames: [(label: String, t: Double)]
        var kind = ChipDisplay.Kind.done
        var clover = true
    }

    static func render(into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let failures = runChecks()
        print(failures.isEmpty ? "Checks passed." : "Checks failed:\n" + failures.map { "  " + $0 }.joined(separator: "\n"))

        let thumbnail = sampleThumbnail()
        for sequence in sequences() {
            let state = ResultChipState(display: resultDisplay(sequence.kind))
            state.running = runningDisplay
            state.thumbnail = thumbnail
            state.outputs = [URL(fileURLWithPath: "/tmp/photo.jpg")]
            let sheet = Sheet(sequence: sequence, state: state)
            let renderer = ImageRenderer(content: sheet.environment(\.bloomSnapshot, true))
            renderer.scale = 2
            let file = folder.appendingPathComponent("chip-\(sequence.name).png")
            if let image = renderer.cgImage,
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: file)
                print(file.path)
            } else {
                print("Couldn't draw \(sequence.name).")
            }
        }
    }

    // MARK: Sequences

    private static func sequences() -> [Sequence] {
        let ms: (Double) -> String = { String(format: "%.0f ms", $0 * 1000) }

        // The ring the clover left, picked up at its point and grown into the chip.
        var running = ChipPlayback(reduced: false, ringStart: .zero)
        running.progress(0.55, at: 0.1)
        var offsetRing = ChipPlayback(reduced: false, ringStart: CGSize(width: -70, height: 14))
        offsetRing.progress(0.55, at: 0.1)
        // No clover: born blurred and large, then sharp.
        var born = ChipPlayback(reduced: false, ringStart: nil)
        born.progress(0.4, at: 0.05)

        // Done: the ring closes, the picture flips in one frame and pops, one ripple leaves.
        var done = ChipPlayback(reduced: false, ringStart: .zero)
        done.progress(0.8, at: 0.2)
        done.end(.done, at: 0.5)
        let flip = done.ending?.at ?? 0.68

        var failed = ChipPlayback(reduced: false, ringStart: .zero)
        failed.progress(0.3, at: 0.2)
        failed.end(.failed, at: 0.6)
        let failFlip = failed.ending?.at ?? 0.68

        var undone = done
        undone.end(.undone, at: 3)

        var leaving = done
        leaving.leave(at: 3)

        var reduced = ChipPlayback(reduced: true, ringStart: .zero)
        reduced.progress(0.6, at: 0.1)
        reduced.end(.done, at: 0.5)
        let reducedFlip = reduced.ending?.at ?? 0.53
        var reducedFailed = ChipPlayback(reduced: true, ringStart: .zero)
        reducedFailed.end(.failed, at: 0.5)

        return [
            Sequence(name: "1-entrance", playback: running, frames: [0.30, 0.38, 0.45, 0.55, 0.68].map { (ms($0), $0) }, kind: .running),
            Sequence(name: "2-entrance-clamped", playback: offsetRing, frames: [0.38, 0.45, 0.55, 0.68].map { (ms($0), $0) }, kind: .running),
            Sequence(name: "3-entrance-no-clover", playback: born, frames: [0, 0.04, 0.08, 0.15, 0.4].map { (ms($0), $0) }, kind: .running),
            Sequence(name: "4-done", playback: done,
                     frames: [-0.017, 0, 0.09, 0.25, 0.5, 0.8].map { ("flip " + ($0 < 0 ? "-17 ms" : ms($0)), flip + $0) }),
            Sequence(name: "5-failed", playback: failed,
                     frames: [-0.017, 0, 0.1, 0.2, 0.3, 0.6].map { ("flip " + ($0 < 0 ? "-17 ms" : ms($0)), failFlip + $0) }, kind: .failed),
            // Three swings of 100 ms each: the chip is back in the middle at 100, 200 and 300 ms, so the swings are drawn between.
            Sequence(name: "5b-failed-swings", playback: failed,
                     frames: [0.025, 0.075, 0.125, 0.175, 0.225, 0.275].map { ("flip " + ms($0), failFlip + $0) }, kind: .failed),
            Sequence(name: "6-undone", playback: undone,
                     frames: [0, 0.04, 0.075, 0.15, 0.4].map { ("undo " + ms($0), 3 + $0) }, kind: .undone),
            Sequence(name: "7-exit", playback: leaving,
                     frames: [-0.017, 0.04, 0.08, 0.12, 0.16].map { ("exit " + ($0 < 0 ? "-17 ms" : ms($0)), 3 + $0) }),
            Sequence(name: "8-reduced-motion", playback: reduced,
                     frames: [0.38, 0.4575, 0.52, reducedFlip, reducedFlip + 0.075, reducedFlip + 0.15].map { (ms($0), $0) }),
            Sequence(name: "9-reduced-failed", playback: reducedFailed,
                     frames: [0.4, 0.5, 0.53, 0.6, 0.7].map { (ms($0), $0) }, kind: .failed),
        ]
    }

    // MARK: Drawing

    private struct Sheet: View {
        let sequence: Sequence
        let state: ResultChipState

        var body: some View {
            VStack(spacing: 0) {
                ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                    HStack(spacing: 0) {
                        ForEach(sequence.frames.indices, id: \.self) { i in
                            Tile(sequence: sequence, state: state, label: sequence.frames[i].label,
                                 t: sequence.frames[i].t, scheme: scheme)
                        }
                    }
                }
            }
        }
    }

    private struct Tile: View {
        let sequence: Sequence
        let state: ResultChipState
        let label: String
        let t: Double
        let scheme: ColorScheme

        var body: some View {
            let size = ChipMotion.chipSize
            let m = ChipPanel.margin
            let dark = scheme == .dark
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                ResultChipView(state: state, actions: ChipActions(),
                               values: sequence.playback.values(at: t), clover: sequence.clover)
                    .frame(width: size.width, height: size.height)
                    .frame(width: size.width + m * 2, height: size.height + m * 2)
            }
            .frame(width: size.width + m * 2)
            .background(
                LinearGradient(colors: dark ? [Color(white: 0.10), Color(red: 0.12, green: 0.16, blue: 0.20)]
                                            : [Color(red: 0.86, green: 0.90, blue: 0.94), Color(red: 0.97, green: 0.93, blue: 0.88)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, scheme)
        }
    }

    static var runningDisplay: ChipDisplay {
        ChipDisplay(JobSnapshot(phase: .running, title: "Convert to JPG", formatName: "JPG", family: .image,
                                inputNames: ["IMG_4821.heic"], progress: 0.55))
    }

    static func resultDisplay(_ kind: ChipDisplay.Kind) -> ChipDisplay {
        switch kind {
        case .failed:
            return ChipDisplay(JobSnapshot(phase: .failed("cwebp isn't installed."), title: "Convert to WebP", formatName: "WebP",
                                           family: .image, inputNames: ["photo.png"], finished: 1, total: 1,
                                           failures: [("photo.png", "cwebp isn't installed.")]))
        case .undone:
            return ChipDisplay(JobSnapshot(phase: .undone, title: "Convert to JPG", formatName: "JPG", family: .image,
                                           inputNames: ["IMG_4821.heic"], outputNames: ["photo.jpg"]))
        case .running:
            return runningDisplay
        default:
            return ChipDisplay(JobSnapshot(phase: .done, title: "Convert to JPG", formatName: "JPG", family: .image,
                                           inputNames: ["IMG_4821.heic"], outputNames: ["photo.jpg"], finished: 1, total: 1,
                                           bytesIn: 3_350_000, bytesOut: 1_200_000))
        }
    }

    private static func sampleThumbnail() -> NSImage {
        NSImage(size: NSSize(width: 72, height: 72), flipped: false) { rect in
            NSGradient(starting: .systemTeal, ending: .systemOrange)?.draw(in: rect, angle: 35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 40, y: 40, width: 18, height: 18)).fill()
            return true
        }
    }

    // MARK: Checks

    /// Checks the curves and the clock, which a picture can't show: no overshoot, the 75 %
    /// rule, one pop that never goes under, a shake of three swings, a ring that never goes back.
    private static func runChecks() -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
        let step = 1.0 / 240
        func times(_ from: Double, _ to: Double) -> [Double] { stride(from: from, through: to, by: step).map { $0 } }

        // The curve: 75 % by 47 % of the time, never past 1, only rising.
        let e140 = ChipMotion.out(0.14, over: 0.30)
        check(abs(e140 - 0.75) < 0.02, "75 % of a 300 ms move by 140 ms (got \(e140))")
        check(ChipMotion.out(0.30, over: 0.30) == 1 && ChipMotion.out(0, over: 0.30) == 0, "ends at 0 and 1")
        check(times(0, 0.4).map { ChipMotion.out($0, over: 0.3) }.adjacentPairs().allSatisfy { $0 <= $1 && $1 <= 1 }, "the curve only rises and never passes 1")

        // Ring entrance: width only grows, to 300 and no further; the ring only shrinks; nothing scales.
        let ringed = ChipPlayback(reduced: false, ringStart: CGSize(width: -70, height: 14))
        let grow = times(ringed.appearAt, ringed.appearAt + 0.5).map { ringed.values(at: $0) }
        check(grow.map(\.width).adjacentPairs().allSatisfy { $0 <= $1 + 0.001 }, "the chip only widens")
        check(grow.allSatisfy { $0.width <= ChipMotion.chipSize.width + 0.001 && $0.scale == 1 && $0.blur == 0 }, "no overshoot, no scale, no blur on the ring entrance")
        check(grow.map(\.ringDiameter).adjacentPairs().allSatisfy { $0 >= $1 - 0.001 }, "the ring only shrinks, from 56 to 40")
        check(abs(grow[0].width - ChipMotion.dropRingDiameter) < 0.01 && abs(grow[0].ringDiameter - 56) < 0.01, "starts as the 56 pt ring")
        check(ringed.values(at: ringed.appearAt - 0.01).isHidden, "hidden before the clover has handed over")
        check(!ringed.values(at: ringed.appearAt).isHidden, "there at 380 ms")
        check(grow.map { abs($0.offset.width) }.adjacentPairs().allSatisfy { $0 >= $1 - 0.001 }, "the chip only moves toward its place")
        let w140 = ringed.values(at: ringed.appearAt + 0.14).width
        check(abs((w140 - 56) / (300 - 56) - 0.75) < 0.02, "75 % grown by 140 ms")

        // Blur-born entrance.
        let bornPlay = ChipPlayback(reduced: false, ringStart: nil)
        let born = times(0, 0.5).map { bornPlay.values(at: $0) }
        check(bornPlay.appearAt == 0, "no clover: no wait")
        check(born.map(\.blur).adjacentPairs().allSatisfy { $0 >= $1 - 0.001 } && born[0].blur == ChipMotion.bornBlur, "born blurred, then sharp")
        check(born.map(\.scale).adjacentPairs().allSatisfy { $0 >= $1 - 0.001 } && born.allSatisfy { $0.scale <= ChipMotion.bornScale + 0.001 && $0.scale >= 1 }, "born at 110 %, never under 100 %")
        check(born.map(\.opacity).adjacentPairs().allSatisfy { $0 <= $1 + 0.001 && $1 <= 1 }, "fades in")

        // Done: flip after the ring closes and the chip is grown; pop; one ripple.
        var done = ChipPlayback(reduced: false, ringStart: .zero)
        done.progress(0.5, at: 0.1)
        done.end(.done, at: 0.5)
        let flip = done.ending?.at ?? 0
        check(abs(flip - max(0.5 + ChipMotion.ringClose, 0.38 + ChipMotion.grow)) < 0.0001, "done flips when the ring has closed")
        var fast = ChipPlayback(reduced: false, ringStart: .zero)
        fast.end(.done, at: 0.1)
        check(abs((fast.ending?.at ?? 0) - 0.68) < 0.0001, "a job done before the chip shows waits for it to grow (680 ms)")
        check(done.values(at: flip - 0.001).showsRunning && !done.values(at: flip).showsRunning, "the picture flips in one frame")
        check(done.values(at: flip - 0.001).pop == 1 && abs(done.values(at: flip).pop - 1.08) < 0.0001, "pop starts at 108 %")
        let after = times(flip, flip + 1).map { done.values(at: $0) }
        check(after.map(\.pop).adjacentPairs().allSatisfy { $0 >= $1 - 0.0001 } && after.allSatisfy { $0.pop >= 1 }, "the pop settles to 100 % and never goes under")
        let rippling = after.filter { $0.ripple != nil }
        check(!rippling.isEmpty && rippling.count <= Int(ChipMotion.rippleDuration * 240) + 2, "one ripple of 500 ms")
        check(after.last?.ripple == nil && after.last?.pop == 1, "nothing left moving after a second")
        check(done.values(at: flip + 0.02).textOpacity == 0 && done.values(at: flip + 0.3).textOpacity == 1, "the words come after the flip")
        check(done.isSettled(at: flip + 1.2) && !done.isSettled(at: flip + 0.1), "the clock can stop after the ending")

        // Failed: the Mac's shake. Three swings, 8 pt, 300 ms, dying away.
        let shake = times(0, 0.31).map { ChipMotion.shake($0) }
        let peak = shake.map { abs($0) }.max() ?? 0
        check(abs(peak - ChipMotion.shakeAmplitude) < 0.1, "first swing reaches 8 pt (got \(peak))")
        var crossings = 0
        for pair in Array(shake.dropFirst(2)).adjacentPairs() where pair.0 * pair.1 < 0 { crossings += 1 }
        check(crossings == 5, "three swings cross the middle five times between the ends (got \(crossings))")
        let swings = stride(from: 0.0, to: 0.3, by: 0.1).map { start in times(start, start + 0.1).map { abs(ChipMotion.shake($0)) }.max() ?? 0 }
        check(swings[0] > swings[1] && swings[1] > swings[2], "each swing is smaller")
        check(ChipMotion.shake(0.3) == 0 && ChipMotion.shake(0) == 0 && ChipMotion.shake(0.5) == 0, "still before and after")
        var failed = ChipPlayback(reduced: false, ringStart: .zero)
        failed.end(.failed, at: 0.2)
        let failFlip = failed.ending?.at ?? 0
        check(abs(failFlip - 0.68) < 0.0001, "a failure shows after the chip has grown")
        check(failed.values(at: failFlip + 0.07).offset.width != 0 && failed.values(at: failFlip + 0.4).offset.width == 0, "shakes, then is still")
        check(failed.values(at: failFlip + 0.07).ripple == nil, "a failure has no ripple")

        // The ring never goes back, however the progress is reported.
        var ring = ChipPlayback(reduced: false, ringStart: nil)
        for (t, p) in [(0.1, 0.2), (0.4, 0.6), (0.5, 0.3), (0.9, 0.9), (1.0, 0.5), (1.3, 1.0)] { ring.progress(p, at: t) }
        let fill = times(0, 3).map { ring.displayed(at: $0) }
        check(fill.adjacentPairs().allSatisfy { $0 <= $1 + 0.000001 }, "the ring never goes backwards")
        check(abs(fill.last! - 1) < 0.001, "and gets there")
        check(fill.adjacentPairs().allSatisfy { abs($1 - $0) < 0.03 }, "and never jumps")

        // Exit: faster than the entrance, fades, blurs, shrinks.
        var leaving = done
        leaving.leave(at: 3)
        let exit = times(3, 3.3).map { leaving.values(at: $0) }
        check(exit.map(\.opacity).adjacentPairs().allSatisfy { $0 >= $1 - 0.001 } && (exit.last?.opacity ?? 1) < 0.001, "fades out")
        check((exit.last?.blur ?? 0) > 7.9 && (exit.last?.scale ?? 1) < 0.93, "blurs and shrinks")
        check(ChipMotion.exitDuration < ChipMotion.grow, "exits are faster than entrances")
        check(leaving.values(at: 3 + ChipMotion.exitDuration + 0.001).isHidden, "gone after 160 ms")

        // Undone: a short fade, no pop.
        var undone = done
        undone.end(.undone, at: 3)
        check(undone.values(at: 3).pop == 1 && undone.values(at: 3).textOpacity == 0 && undone.values(at: 3.2).textOpacity == 1, "undone fades its words in, no pop")

        // Reduced motion: only fades. The ring still fills.
        var reduced = ChipPlayback(reduced: true, ringStart: CGSize(width: -70, height: 14))
        reduced.progress(0.6, at: 0.1)
        reduced.end(.failed, at: 0.5)
        reduced.leave(at: 3)
        let calm = times(0, 3.5).map { reduced.values(at: $0) }
        check(calm.allSatisfy { $0.offset == .zero && $0.scale == 1 && $0.blur == 0 && $0.pop == 1 && $0.ripple == nil && $0.textBlur == 0 && $0.width == ChipMotion.chipSize.width },
              "reduced motion: no travel, scale, blur, pop, ripple or shake")
        check(calm.map(\.opacity).max() == 1 && calm.map(\.opacity).min() == 0, "reduced motion: fades")
        var reducedRing = ChipPlayback(reduced: true, ringStart: nil)
        reducedRing.progress(0.5, at: 0.1)
        check((reducedRing.values(at: 1).ringProgress ?? 0) > 0.3, "reduced motion: the ring still fills")

        // Stack: a chip glides to its new place and does not overshoot.
        var slot = ChipPlayback(reduced: false, ringStart: nil, slot: 2)
        slot.setSlot(1, at: 5)
        let glide = times(5, 5.4).map { slot.slot(at: $0) }
        check(glide.first == 2 && abs(glide.last! - 1) < 0.0001 && glide.adjacentPairs().allSatisfy { $0 >= $1 - 0.0001 }, "a chip glides up one place without overshoot")
        return failures
    }
}

private extension Array {
    func adjacentPairs() -> [(Element, Element)] {
        guard count > 1 else { return [] }
        return (1..<count).map { (self[$0 - 1], self[$0]) }
    }
}
