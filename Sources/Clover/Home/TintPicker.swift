import SwiftUI

/// The glass tint: none, the preset swatches, and a colour well for any colour. The chosen
/// one has a ring.
struct TintPicker: View {
    @Binding var tint: GlassTint
    /// Smaller swatches, closer together, for a narrow column.
    var compact = false
    /// The colour last picked in the well, kept while a preset is chosen.
    @State private var lastCustom: UInt32 = 0x4AA3A2

    var body: some View {
        HStack(spacing: compact ? 3 : 6) {
            swatch(.none)
            ForEach(GlassTint.Preset.allCases) { preset in
                swatch(.preset(preset))
            }
            ColorPicker("Custom colour", selection: custom, supportsOpacity: false)
                .labelsHidden()
                .padding(2)
                .overlay {
                    if case .custom = tint {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .help("Any colour")
                .accessibilityLabel("Custom colour")
        }
    }

    private var side: CGFloat { compact ? 16 : 18 }

    private func swatch(_ choice: GlassTint) -> some View {
        let chosen = tint == choice
        return Button {
            tint = choice
        } label: {
            ZStack {
                if let rgb = choice.rgb {
                    Circle().fill(BloomStyle.rgb(rgb))
                } else {
                    // None: clear glass, crossed out.
                    Circle().fill(Color(nsColor: .textBackgroundColor))
                    Rectangle().fill(Color.red.opacity(0.8)).frame(width: 1.5, height: side).rotationEffect(.degrees(45))
                }
                Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .padding(compact ? 2 : 3)
            .overlay {
                if chosen { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice == .none ? "No tint" : choice.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The well's colour: the custom tint when chosen, else the last one picked.
    private var custom: Binding<Color> {
        Binding(get: {
            if case .custom(let rgb) = tint { return BloomStyle.rgb(rgb) }
            return BloomStyle.rgb(lastCustom)
        }, set: { colour in
            let rgb = TintPicker.rgb(of: colour)
            lastCustom = rgb
            tint = .custom(rgb)
        })
    }

    /// A colour as 0xRRGGBB in sRGB.
    static func rgb(of colour: Color) -> UInt32 {
        guard let c = NSColor(colour).usingColorSpace(.sRGB) else { return 0x808080 }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }
}
