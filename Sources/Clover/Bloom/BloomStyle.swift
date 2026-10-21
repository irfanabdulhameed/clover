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

    /// A small SF Symbol for a petal.
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

    /// Text width in `font`, for laying out chips before they are drawn.
    static func textWidth(_ text: String, font: NSFont = chipFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: 1)
    }
}

/// True while a view is drawn into a PNG by the debug commands. Platform views
/// (blur, drag areas) don't draw there, so flat stand-ins are used instead.
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
