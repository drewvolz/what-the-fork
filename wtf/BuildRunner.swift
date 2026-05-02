// wtf/BuildRunner.swift
import Foundation

/// Launches a build command as a child process and returns its PID.
enum BuildRunner {
    /// Spawn the given command and arguments as a child process.
    /// Returns the child PID immediately (does not wait for completion).
    static func launch(command: String, args: [String]) throws -> pid_t {
        let fullPath = command.hasPrefix("/") ? command : try resolveInPATH(command)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: fullPath)
        process.arguments = args
        try process.run()
        return process.processIdentifier
    }

    private static func resolveInPATH(_ command: String) throws -> String {
        let paths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map(String.init) ?? []
        for dir in paths {
            let full = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: full) {
                return full
            }
        }
        throw BuildRunnerError.commandNotFound(command)
    }
}

enum BuildRunnerError: Error, LocalizedError {
    case commandNotFound(String)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let cmd): return "Command not found: \(cmd)"
        }
    }
}
