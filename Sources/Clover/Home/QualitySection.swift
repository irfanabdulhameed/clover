import SwiftUI
import CloverCore

/// Best, Balanced or Small.
enum LevelSlot: String, CaseIterable, Identifiable {
    case best, balanced, small

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Keeps Best at or above Balanced, and Balanced at or above Small, when one of them changes.
enum LevelRules {
    static func set(_ levels: Levels, _ slot: LevelSlot, to value: Double) -> Levels {
        var result = levels
        switch slot {
        case .best:
            result.best = value
            result.balanced = min(result.balanced, result.best)
            result.small = min(result.small, result.balanced)
        case .balanced:
            result.balanced = value
            result.best = max(result.best, result.balanced)
            result.small = min(result.small, result.balanced)
        case .small:
            result.small = value
            result.balanced = max(result.balanced, result.small)
            result.best = max(result.best, result.balanced)
        }
        return result
    }

    static func value(_ levels: Levels, _ slot: LevelSlot) -> Double {
        switch slot {
        case .best: levels.best
        case .balanced: levels.balanced
        case .small: levels.small
        }
    }

    /// The choices for a picker, with the current value added if it isn't one of them
    /// (a setting from an older version, say).
    static func choices(_ base: [Double], including current: Double) -> [Double] {
        base.contains(current) ? base : (base + [current]).sorted()
    }
}

/// Quality: how sharp and how small converted files are.
struct QualitySection: View {
    @Binding var conversion: ConversionSettings

    private static let bitrates: [Double] = [96, 128, 160, 192, 256, 320]
    private static let gifWidths: [Double] = [240, 320, 400, 480, 560, 640, 720, 800, 960]
    private static let videoHeights = [360, 480, 540, 720]

    /// The quality settings as they come out of the box. Naming is kept: it lives in Saving.
    private var defaults: ConversionSettings {
        var fresh = ConversionSettings()
        fresh.namePattern = conversion.namePattern
        fresh.onConflict = conversion.onConflict
        return fresh
    }

    var body: some View {
        Form {
            Section {
                PercentRow(title: "Best", value: levelBinding(\.imageQuality, .best), range: 10...100)
                PercentRow(title: "Balanced", value: levelBinding(\.imageQuality, .balanced), range: 10...100)
                PercentRow(title: "Small", value: levelBinding(\.imageQuality, .small), range: 10...100)
            } header: {
                Text("Images")
            } footer: {
                FormFooter("For JPG, HEIC, AVIF and WebP. Higher keeps more detail and makes bigger files.")
            }

            Section {
                PercentRow(title: "Quality", value: $conversion.videoQuality.rounded, range: 10...100)
            } header: {
                Text("Video")
            } footer: {
                FormFooter("How sharp re-encoded video looks. Higher looks better and makes bigger files.")
            }

            Section {
                Picker("Height", selection: heightBinding) {
                    ForEach(LevelRules.heights(including: conversion.smallVideoHeight), id: \.self) { Text("\($0)p").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Small video")
            } footer: {
                FormFooter("The Small option scales video down to this height. The width follows.")
            }

            Section {
                bitratePicker(.best)
                bitratePicker(.balanced)
                bitratePicker(.small)
            } header: {
                Text("Audio")
            } footer: {
                FormFooter("For MP3, M4A, Opus and OGG, and for audio inside video. Higher sounds better and takes more space.")
            }

            Section {
                widthPicker("Large", .best)
                widthPicker("Medium", .balanced)
                widthPicker("Small", .small)
            } header: {
                Text("GIF")
            } footer: {
                FormFooter("How wide a GIF made from a video is. The height follows.")
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset to Defaults") { conversion = defaults }
                    .disabled(conversion == defaults)
                    .help("Put every quality setting back to how Clover shipped")
            }
        }
    }

    private func bitratePicker(_ slot: LevelSlot) -> some View {
        let current = LevelRules.value(conversion.audioBitrate, slot)
        return Picker(slot.title, selection: levelBinding(\.audioBitrate, slot)) {
            ForEach(LevelRules.choices(Self.bitrates, including: current), id: \.self) { Text("\(Int($0)) kbps").tag($0) }
        }
    }

    private func widthPicker(_ title: String, _ slot: LevelSlot) -> some View {
        let current = LevelRules.value(conversion.gifWidth, slot)
        return Picker(title, selection: levelBinding(\.gifWidth, slot)) {
            ForEach(LevelRules.choices(Self.gifWidths, including: current), id: \.self) { Text("\(Int($0)) px").tag($0) }
        }
    }

    private func levelBinding(_ path: WritableKeyPath<ConversionSettings, Levels>, _ slot: LevelSlot) -> Binding<Double> {
        Binding(
            get: { LevelRules.value(conversion[keyPath: path], slot) },
            set: { conversion[keyPath: path] = LevelRules.set(conversion[keyPath: path], slot, to: $0.rounded()) })
    }

    private var heightBinding: Binding<Int> {
        Binding(get: { conversion.smallVideoHeight }, set: { conversion.smallVideoHeight = $0 })
    }
}

extension LevelRules {
    private static let baseHeights = [360, 480, 540, 720]

    static func heights(including current: Int) -> [Int] {
        baseHeights.contains(current) ? baseHeights : (baseHeights + [current]).sorted()
    }
}

extension Binding where Value == Double {
    /// The same value, rounded to a whole number when it is set.
    var rounded: Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0.rounded() })
    }
}

/// A slider with its value in percent beside it.
private struct PercentRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .frame(minWidth: 140, maxWidth: 280)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(Int(value)) percent")
                Text("\(Int(value)) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}
