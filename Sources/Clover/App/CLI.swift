import Foundation
import CloverCore

/// Headless commands, for scripts and tests:
///   Clover --version
///   Clover tools
///   Clover targets <file>...
///   Clover convert <target-id> [--option <option-id>] <file>...
@MainActor
enum CLI {
    static let commands: Set<String> = ["--version", "tools", "targets", "convert"]

    static func run(_ arguments: [String]) async -> Int32 {
        if arguments.first == "--version" {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "development build"
            print("Clover \(version)" + ((info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""))
            return 0
        }
        let tools = Tools.detect()
        let router = Registry.makeRouter(tools: tools)
        let service = ConversionService(router: router)

        switch arguments.first {
        case "tools":
            for tool in tools.status {
                print("\(tool.name)\t\(tool.path?.path ?? "missing (\(tool.install))")")
            }
            return 0

        case "targets":
            let files = arguments.dropFirst().map { URL(fileURLWithPath: $0) }
            for target in service.catalog.targets(for: files) {
                let options = target.options.map { $0.id == target.defaultOption?.id ? "[\($0.id)]" : $0.id }
                print("\(target.id)\t\(target.title)\t\(options.joined(separator: " "))")
            }
            return 0

        case "convert":
            var rest = Array(arguments.dropFirst())
            guard !rest.isEmpty else { return usage() }
            let targetID = rest.removeFirst()
            var optionID: String?
            if let i = rest.firstIndex(of: "--option"), i + 1 < rest.count {
                optionID = rest[i + 1]
                rest.removeSubrange(i...(i + 1))
            }
            let files = rest.map { URL(fileURLWithPath: $0) }
            guard !files.isEmpty else { return usage() }
            let targets = service.catalog.targets(for: files)
            guard let target = targets.first(where: { $0.id == targetID }) else {
                FileHandle.standardError.write("No target \"\(targetID)\" for these files. Try: \(targets.map(\.id).joined(separator: " "))\n".data(using: .utf8)!)
                return 2
            }
            let option = optionID.flatMap { id in target.options.first { $0.id == id } }
            if optionID != nil && option == nil {
                FileHandle.standardError.write("No option \"\(optionID!)\" for \(target.id). Try: \(target.options.map(\.id).joined(separator: " "))\n".data(using: .utf8)!)
                return 2
            }
            let job = service.start(ConversionRequest(inputs: files, target: target, option: option))
            await service.wait(job)
            for url in job.outputs { print(url.path) }
            for failure in job.failures {
                FileHandle.standardError.write("failed \(failure.file): \(failure.message)\n".data(using: .utf8)!)
            }
            return job.state == .done && job.failures.isEmpty ? 0 : 1

        default:
            return usage()
        }
    }

    private static func usage() -> Int32 {
        print("Usage: Clover --version | tools | targets <file>... | convert <target-id> [--option <id>] <file>...")
        return 2
    }
}
