// wtf/BuildRunner.swift
import Foundation
import Darwin

/// Launches a build command as a child process and returns its PID.
enum BuildRunner {
    /// Spawn the given command and arguments as a child process, initially suspended
    /// (SIGSTOP). The caller must send SIGCONT after registering the session with the
    /// daemon so that fork events for any children are captured from the start.
    static func launch(command: String, args: [String]) throws -> pid_t {
        let fullPath = command.hasPrefix("/") ? command : try resolveInPATH(command)
        return try spawnSuspended(path: fullPath, args: args)
    }

    /// Spawns the process in a suspended state using posix_spawn +
    /// POSIX_SPAWN_START_SUSPENDED so no user code runs before SIGCONT is sent.
    private static func spawnSuspended(path: String, args: [String]) throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_START_SUSPENDED))

        // Build null-terminated argv / envp arrays.
        let allArgs = [path] + args
        var cArgs: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.compactMap { $0 }.forEach { free($0) } }

        var cEnv: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") }
        cEnv.append(nil)
        defer { cEnv.compactMap { $0 }.forEach { free($0) } }

        var pid: pid_t = 0
        let ret: Int32 = cArgs.withUnsafeBufferPointer { argsBuf in
            cEnv.withUnsafeBufferPointer { envBuf in
                posix_spawn(
                    &pid, path, nil, &attr,
                    UnsafeMutablePointer(mutating: argsBuf.baseAddress!),
                    UnsafeMutablePointer(mutating: envBuf.baseAddress!)
                )
            }
        }
        guard ret == 0 else { throw BuildRunnerError.spawnFailed(ret) }
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
    case spawnFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let cmd): return "Command not found: \(cmd)"
        case .spawnFailed(let code): return "posix_spawn failed with errno \(code)"
        }
    }
}
