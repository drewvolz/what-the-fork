import Foundation

/// A single syscall event captured from the Endpoint Security Framework.
public struct ProcessEvent: Codable, Equatable {
    public enum EventType: String, Codable {
        case fork, exec, exit
    }

    public let type: EventType
    public let pid: Int
    public let ppid: Int
    public let timestamp: TimeInterval
    public let command: String
    public let args: [String]
    public let cwd: String
    public let exitCode: Int?

    public init(
        type: EventType,
        pid: Int,
        ppid: Int,
        timestamp: TimeInterval,
        command: String,
        args: [String],
        cwd: String,
        exitCode: Int? = nil
    ) {
        self.type = type
        self.pid = pid
        self.ppid = ppid
        self.timestamp = timestamp
        self.command = command
        self.args = args
        self.cwd = cwd
        self.exitCode = exitCode
    }
}
