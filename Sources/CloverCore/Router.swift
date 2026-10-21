import Foundation

/// One step of a route: run `converter` to make `output`.
public struct RouteStep: Sendable {
    public let converter: any Converter
    public let output: Format
}

/// Finds how to get from one format to another, in at most two steps.
///
/// Two-step routes go through a pivot, and only where the result is worth having:
/// images through PNG (HEIC → PNG → WebP, SVG → PNG → JPG) and documents through
/// PDF (DOCX → PDF → JPG). Direct routes always win.
public final class Router: @unchecked Sendable {
    public let converters: [any Converter]
    public let combiners: [any Combiner]
    public private(set) var tools: Tools

    public init(converters: [any Converter], combiners: [any Combiner], tools: Tools) {
        self.converters = converters
        self.combiners = combiners
        self.tools = tools
    }

    public func update(tools: Tools) { self.tools = tools }

    private var available: [any Converter] { converters.filter { $0.isAvailable(tools) } }

    public func route(from input: Format, to output: Format) -> [RouteStep]? {
        let usable = available
        let direct = usable
            .filter { $0.outputs(from: input).contains(output) }
            .min { $0.cost < $1.cost }
        if let direct { return [RouteStep(converter: direct, output: output)] }

        guard let pivot = Router.pivot(for: input), pivot != output, pivot != input else { return nil }
        guard let first = usable.filter({ $0.outputs(from: input).contains(pivot) }).min(by: { $0.cost < $1.cost }),
              let second = usable.filter({ $0.outputs(from: pivot).contains(output) }).min(by: { $0.cost < $1.cost })
        else { return nil }
        // A document turned into a PDF should not come back out as another document.
        if input.family == .document && output.family == .document { return nil }
        if output == pivot { return nil }
        return [RouteStep(converter: first, output: pivot), RouteStep(converter: second, output: output)]
    }

    /// Every format reachable from `input`, excluding `input` itself unless a converter
    /// makes it on purpose (PDF → PDF compresses).
    public func reachable(from input: Format) -> Set<Format> {
        let usable = available
        var result = Set(usable.flatMap { $0.outputs(from: input) })
        if let pivot = Router.pivot(for: input), result.contains(pivot) || usable.contains(where: { $0.outputs(from: input).contains(pivot) }) {
            for format in usable.flatMap({ $0.outputs(from: pivot) }) {
                if input.family == .document && format.family == .document { continue }
                if format == input || format == pivot { continue }
                result.insert(format)
            }
        }
        return result
    }

    public func combiner(for inputs: [Format], into output: Format) -> (any Combiner)? {
        combiners.first { $0.isAvailable(tools) && $0.canCombine(inputs, into: output) }
    }

    static func pivot(for input: Format) -> Format? {
        switch input.family {
        case .image: input == Formats.png ? nil : Formats.png
        case .document: Formats.pdf
        default: nil
        }
    }
}
