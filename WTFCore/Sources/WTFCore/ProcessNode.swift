import Foundation

/// A node in the process tree representing a single process during a build.
public struct ProcessNode: Identifiable, Equatable {
    public let id: Int  // pid

    public var command: String
    public var args: [String]
    public var cwd: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var children: [ProcessNode]
    public var exitCode: Int?

    public init(
        pid: Int,
        command: String,
        args: [String] = [],
        cwd: String = "",
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        children: [ProcessNode] = [],
        exitCode: Int? = nil
    ) {
        self.id = pid
        self.command = command
        self.args = args
        self.cwd = cwd
        self.startTime = startTime
        self.endTime = endTime
        self.children = children
        self.exitCode = exitCode
    }

    /// Duration in seconds. Returns nil if the process has not yet exited.
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end - startTime
    }

    /// The basename of the command path (e.g. "clang" from "/usr/bin/clang").
    public var commandName: String {
        URL(fileURLWithPath: command).lastPathComponent
    }

    /// A human-readable display name that enriches the raw command name where possible.
    ///
    /// - For `rustc`: extracts `--crate-name <name>` from args (e.g. "serde", "tokio").
    /// - For `clang`/`gcc` family: extracts the basename of the first non-flag source file.
    /// - All other commands: falls back to `commandName`.
    public var displayName: String {
        switch commandName.lowercased() {
        case "rustc":
            if let idx = args.firstIndex(of: "--crate-name"), args.indices.contains(idx + 1) {
                return args[idx + 1]
            }
        case "clang", "clang++", "cc", "c++", "gcc", "g++":
            let sourceExts: Set<String> = ["c", "cc", "cpp", "cxx", "m", "mm", "s"]
            if let src = args.first(where: { arg in
                !arg.hasPrefix("-") &&
                sourceExts.contains(URL(fileURLWithPath: arg).pathExtension.lowercased())
            }) {
                return URL(fileURLWithPath: src).deletingPathExtension().lastPathComponent
            }
        default:
            break
        }
        return commandName
    }

    /// All descendants (children, grandchildren, etc.) in DFS order.
    public var allDescendants: [ProcessNode] {
        children.flatMap { [$0] + $0.allDescendants }
    }
}
