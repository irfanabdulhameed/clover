import AppKit
import SwiftUI
import CloverCore

/// Colours, type and symbols shared by the bloom and the result chip.
enum BloomStyle {
    /// Each family's hue, used only for its icon, its glow and its lit fill.
    static func hue(_ family: Family, _ scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch family {
        case .image: return rgb(dark ? 0xF5B04A : 0xB86A00)     // amber
        case .video: return rgb(dark ? 0xA88BFA : 0x7547D1)     // violet
        case .audio: return rgb(dark ? 0xF57D9C : 0xC93A64)     // rose
        case .document: return rgb(dark ? 0x6DA2F7 : 0x2767D0)  // blue
        case .archive: return rgb(dark ? 0xA3AFBF : 0x5A6676)   // slate
        case .pdf: return rgb(dark ? 0xF47A6E : 0xC8392F)       // red
        }
    }

    /// Clover green, saved for a finished file.
    static func green(_ scheme: ColorScheme) -> Color {
        rgb(scheme == .dark ? 0x4FD083 : 0x24884C)
    }

    /// The red used for a failure.
    static func failure(_ scheme: ColorScheme) -> Color { hue(.pdf, scheme) }

    /// True for targets that are tools rather than formats: they get a small icon over
    /// their title.
    static func isTool(_ target: Target) -> Bool {
        ["pdf-compress", "pdf-merge", "folder"].contains(target.id)
    }

    /// A small SF Symbol for a leaf.
    static func symbol(for target: Target) -> String {
        switch target.id {
        case "pdf-compress": return "arrow.down.right.and.arrow.up.left"
        case "pdf-merge": return "doc.on.doc"
        case "folder": return "folder"
        default: return symbol(for: target.format.family)
        }
    }

    static func symbol(for family: Family) -> String {
        switch family {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .document: "doc.text"
        case .archive: "archivebox"
        case .pdf: "doc.richtext"
        }
    }

    static let chipFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let hintFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// A slot's title: SF Pro Rounded, bold.
    static let leafFont = rounded(15, weight: .bold)
    /// One step down, for a title its slot can't hold at full size.
    static let leafSmallFont = rounded(14, weight: .bold)

    /// The title's font in a label of `width`: full size when it fits, else one step down.
    static func leafFont(for title: String, width: CGFloat) -> NSFont {
        textWidth(title, font: leafFont) <= width ? leafFont : leafSmallFont
    }
    /// The size capsule on the centre circle.
    static let capsuleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// A pill's title in the More tray.
    static let pillFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    /// The system font in its rounded design.
    static func rounded(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    /// The fresh clover green of the app icon, for a lit slot, chip or pill: lighter at the
    /// top, deeper at the bottom, so white text holds on it.
    static let cloverTop = rgb(0x34BD71)
    static let cloverBottom = rgb(0x1E9A57)
    static var cloverFill: LinearGradient {
        LinearGradient(colors: [cloverTop, cloverBottom], startPoint: .top, endPoint: .bottom)
    }
    /// The glow and ripple around a lit slot.
    static func cloverGlow(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x3FD27F : 0x2DB868) }
    /// The disc's light tint with `LeafStyle.clover`.
    static func discTint(_ scheme: ColorScheme) -> Color {
        rgb(scheme == .dark ? 0x3FC779 : 0x5ACF8C).opacity(scheme == .dark ? 0.16 : 0.20)
    }

    /// Text width in `font`, for laying out chips before they are drawn.
    static func textWidth(_ text: String, font: NSFont = chipFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: 1)
    }
}

/// True while a view is drawn without the clover's own window: into a PNG by the debug
/// commands, or as the still preview in the dashboard. Platform views (blur, drag
/// areas) don't draw there, so flat stand-ins are used instead.
private struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var bloomSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

/// Frosted glass in a circle or a rounded rectangle, lit from the top: the system blur,
/// a hairline lighter rim and a soft shadow. `tint` fills it with colour when lit.
struct Glass: View {
    var cornerRadius: CGFloat
    var tint: Color? = nil
    /// A brighter rim, for lit parts.
    var bright = false
    var shadow = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.bloomSnapshot) private var snapshot

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        ZStack {
            if snapshot {
                shape.fill(scheme == .dark ? Color(white: 0.17).opacity(0.86) : Color(white: 0.97).opacity(0.80))
            } else {
                VisualEffectBlur(cornerRadius: cornerRadius)
                // A thin veil keeps text readable over busy backgrounds.
                shape.fill(scheme == .dark ? Color.black.opacity(0.10) : Color.white.opacity(0.18))
            }
            if let tint { shape.fill(tint) }
            shape.strokeBorder(rim, lineWidth: 0.75)
        }
        .background {
            if shadow {
                shape.fill(Color.black.opacity(scheme == .dark ? 0.32 : 0.16))
                    .blur(radius: 5)
                    .offset(y: 2.5)
            }
        }
    }

    private var rim: LinearGradient {
        let dark = scheme == .dark
        let top = Color.white.opacity(dark ? (bright ? 0.42 : 0.26) : (bright ? 0.95 : 0.80))
        let bottom = dark ? Color.white.opacity(bright ? 0.12 : 0.06) : Color.black.opacity(bright ? 0.10 : 0.08)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// `NSVisualEffectView` blurring what is behind the window, masked to a rounded shape.
struct VisualEffectBlur: NSViewRepresentable {
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.maskImage = VisualEffectBlur.mask(cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.material != material { view.material = material }
        view.maskImage = VisualEffectBlur.mask(cornerRadius)
    }

    private static var masks: [CGFloat: NSImage] = [:]

    /// A stretchable rounded-rectangle mask; a circle when the view is square.
    static func mask(_ radius: CGFloat) -> NSImage {
        if let cached = masks[radius] { return cached }
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        masks[radius] = image
        return image
    }
}

/// A path grown outward by `distance`, for a focus ring that follows a slot's outline.
enum PathOutset {
    private static var cache: [String: CGPath] = [:]

    static func outset(_ path: CGPath, by distance: CGFloat, key: String) -> CGPath {
        let fullKey = "\(key)@\(distance)"
        if let cached = cache[fullKey] { return cached }
        let band = path.copy(strokingWithWidth: distance * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let grown = path.union(band)
        cache[fullKey] = grown
        return grown
    }
}

// MARK: - Liquid Glass

/// How the clover's glass is made. `defaults write io.github.irfanabdulhameed.clover
/// bloomGlass layered` (or `classic`) switches it, for checking how the glass samples
/// what is behind the window; the default is the system's Liquid Glass.
enum GlassMode: String {
    /// macOS 26 Liquid Glass alone.
    case native
    /// Liquid Glass over the behind-window blur.
    case layered
    /// The frosted look from before macOS 26: the behind-window blur, a veil and a lit rim.
    case classic

    static let current: GlassMode = {
        let stored = GlassMode(rawValue: UserDefaults.standard.string(forKey: "bloomGlass") ?? "") ?? .native
        guard stored != .classic else { return .classic }
        if #available(macOS 26, *) { return supported ? stored : .classic }
        return .classic
    }()

    /// True when this build has the macOS 26 glass.
    static var supported: Bool {
        #if canImport(SwiftUI, _version: 7.0)
        return true
        #else
        return false
        #endif
    }
}

/// The clover's glass in a circle or a rounded rectangle: Liquid Glass on macOS 26, with
/// the frosted `Glass` before it and in still pictures. `tint` colours the glass lightly.
struct LiquidGlass: View {
    var cornerRadius: CGFloat
    var tint: Color? = nil
    var bright = false
    var shadow = true

    @Environment(\.bloomSnapshot) private var snapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if snapshot || GlassMode.current == .classic {
            ZStack {
                Glass(cornerRadius: cornerRadius, bright: bright, shadow: shadow)
                if let tint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .circular).fill(tint.opacity(0.6))
                }
            }
        } else {
            native
        }
    }

    @ViewBuilder private var native: some View {
        #if canImport(SwiftUI, _version: 7.0)
        if #available(macOS 26, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
            ZStack {
                if GlassMode.current == .layered { VisualEffectBlur(cornerRadius: cornerRadius) }
                Color.clear.glassEffect(SwiftUI.Glass.regular.tint(tint), in: shape)
            }
        } else {
            Glass(cornerRadius: cornerRadius, tint: tint, bright: bright, shadow: shadow)
        }
        #else
        Glass(cornerRadius: cornerRadius, tint: tint, bright: bright, shadow: shadow)
        #endif
    }
}

/// Puts the clover's glass behind a view. On macOS 26 the glass is applied to the view
/// itself, so its content always draws on top of its own glass. (A separate glass view
/// next to the content, inside a glass container, drew over the text: chips came out as
/// empty pills.) Before macOS 26 and in still pictures it is the frosted `LiquidGlass`.
struct GlassBehind: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color? = nil
    var bright = false

    @Environment(\.bloomSnapshot) private var snapshot

    func body(content: Content) -> some View {
        if snapshot || GlassMode.current == .classic {
            content.background(LiquidGlass(cornerRadius: cornerRadius, tint: tint, bright: bright))
        } else {
            native(content)
        }
    }

    @ViewBuilder private func native(_ content: Content) -> some View {
        #if canImport(SwiftUI, _version: 7.0)
        if #available(macOS 26, *) {
            content.glassEffect(SwiftUI.Glass.regular.tint(tint),
                                in: RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
        } else {
            content.background(LiquidGlass(cornerRadius: cornerRadius, tint: tint, bright: bright))
        }
        #else
        content.background(LiquidGlass(cornerRadius: cornerRadius, tint: tint, bright: bright))
        #endif
    }
}

extension View {
    func glassBehind(cornerRadius: CGFloat, tint: Color? = nil, bright: Bool = false) -> some View {
        modifier(GlassBehind(cornerRadius: cornerRadius, tint: tint, bright: bright))
    }
}

/// Holds the clover's glass. It used to be a glass container, so neighbouring pieces could
/// merge like liquid; the container drew its merged glass over the chips' text, so it is
/// off until the motion pass, where the merge belongs.
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    @Environment(\.bloomSnapshot) private var snapshot

    var body: some View {
        #if canImport(SwiftUI, _version: 7.0)
        content()
        #else
        content()
        #endif
    }
}
