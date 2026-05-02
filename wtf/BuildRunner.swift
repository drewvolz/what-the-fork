// wtf/BuildRunner.swift
import Foundation

/// Launches a build command as a child process and returns its PID.
enum BuildRunner {
    /// Fork the given command and arguments as a child process.
    /// Returns the child PID immediately (does not wait for completion).
    static func launch(command: String, args: [String]) throws -> pid_t {
        let fullPath: String
        if command.hasPrefix("/") {
            fullPath = command
        } else {
            fullPath = try resolveInPATH(command)
        }

        var pid: pid_t = 0
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)

        var argv = ([fullPath] + args).map { strdup($0) }
        argv.append(nil)

        let envp = ProcessInfo.processInfo.environment
            .map { "\($0.key)=\($0.value)" }
            .map { strdup($0) }
        var envpArr = envp
        envpArr.append(nil)

        let ret = posix_spawn(&pid, fullPath, &fileActions, nil, argv, envpArr)

        argv.compactMap { $0 }.forEach { free($0) }
        envp.compactMap { $0 }.forEach { free($0) }
        posix_spawn_file_actions_destroy(&fileActions)

        guard ret == 0 else {
            throw BuildRunnerError.spawnFailed(errno: ret)
        }
        return pid
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
    case spawnFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let cmd): return "Command not found: \(cmd)"
        case .spawnFailed(let e): return "posix_spawn failed with errno \(e)"
        }
    }
}
