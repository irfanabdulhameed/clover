import Foundation

/// Which leaf layout applies to a set of files: one per family, plus one for mixed sets.
public enum LayoutKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case image, pdf, document, video, audio, archive, mixed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .image: "Images"
        case .pdf: "PDF"
        case .document: "Documents"
        case .video: "Video"
        case .audio: "Audio"
        case .archive: "Archives"
        case .mixed: "Mixed files"
        }
    }

    public static func key(for formats: [Format]) -> LayoutKey {
        let families = Set(formats.map(\.family))
        guard families.count == 1, let family = families.first else { return .mixed }
        return LayoutKey(rawValue: family.rawValue) ?? .mixed
    }
}

/// The user's arrangement of the clover for one kind of file.
public struct LeafLayout: Codable, Equatable, Sendable {
    /// Target ids in the user's order. Targets not listed follow, in `Catalog.order`.
    public var order: [String]
    /// Target ids never shown.
    public var hidden: Set<String>
    /// Target id → option id used when dropping on the leaf itself.
    public var defaultOptions: [String: String]

    public init(order: [String] = [], hidden: Set<String> = [], defaultOptions: [String: String] = [:]) {
        self.order = order
        self.hidden = hidden
        self.defaultOptions = defaultOptions
    }
}

/// What the clover shows: the leaves, and the rest behind "More".
public struct Arrangement: Sendable, Equatable {
    public let leaves: [Target]
    /// Empty when everything fits on the clover. When not empty, the clover shows a
    /// "More" leaf as its last leaf.
    public let more: [Target]

    public init(leaves: [Target], more: [Target]) {
        self.leaves = leaves
        self.more = more
    }

    public var all: [Target] { leaves + more }
}

public enum LeafArranger {
    /// The clover has at most six leaves. With more targets, five leaves plus "More".
    public static let maxLeaves = 6

    public static func arrange(_ targets: [Target], layout: LeafLayout?) -> Arrangement {
        let layout = layout ?? LeafLayout()
        let visible = targets
            .filter { !layout.hidden.contains($0.id) }
            .map { applyDefault(to: $0, layout: layout) }
        let ordered = visible.enumerated().sorted { a, b in
            let ia = layout.order.firstIndex(of: a.element.id) ?? Int.max
            let ib = layout.order.firstIndex(of: b.element.id) ?? Int.max
            return ia == ib ? a.offset < b.offset : ia < ib
        }.map(\.element)
        if ordered.count <= maxLeaves {
            return Arrangement(leaves: ordered, more: [])
        }
        return Arrangement(leaves: Array(ordered.prefix(maxLeaves - 1)), more: Array(ordered.dropFirst(maxLeaves - 1)))
    }

    static func applyDefault(to target: Target, layout: LeafLayout) -> Target {
        guard let optionID = layout.defaultOptions[target.id],
              let option = target.options.first(where: { $0.id == optionID }) else { return target }
        return Target(id: target.id, format: target.format, title: target.title,
                      options: target.options, defaultOption: option, mode: target.mode)
    }
}

public extension Catalog {
    /// Every target any file of this kind can get, for the leaf editor. One file per
    /// format, plus the many-file targets (Merge, One PDF).
    func allTargets(for key: LayoutKey) -> [Target] {
        let formats: [Format]
        switch key {
        case .mixed:
            return targets(forFormats: [Formats.png, Formats.mp3])
        default:
            formats = Formats.all.filter { $0.family.rawValue == key.rawValue }
        }
        var seen = Set<String>()
        var result: [Target] = []
        for format in formats {
            for target in targets(forFormats: [format]) + targets(forFormats: [format, format]) where seen.insert(target.id).inserted {
                result.append(target)
            }
        }
        return Catalog.sorted(result)
    }
}
