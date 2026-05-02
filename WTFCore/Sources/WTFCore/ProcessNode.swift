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

    /// All descendants (children, grandchildren, etc.) in DFS order.
    public var allDescendants: [ProcessNode] {
        children.flatMap { [$0] + $0.allDescendants }
    }
}
