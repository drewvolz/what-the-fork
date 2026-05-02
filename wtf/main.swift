// wtf/main.swift
import Foundation

let args = CommandLine.arguments.dropFirst()

guard !args.isEmpty else {
    fputs("Usage: wtf <command> [args...]\n", stderr)
    exit(1)
}

let command = String(args[0])
let commandArgs = Array(args.dropFirst())
let sessionID = UUID().uuidString

do {
    let buildPID = try BuildRunner.launch(command: command, args: commandArgs)
    print("wtf: launched \(command) as PID \(buildPID), session \(sessionID)")

    try DaemonLauncher.startSession(id: sessionID, rootPID: buildPID)

    AppLauncher.openApp(sessionID: sessionID, rootPID: buildPID)

    var status: Int32 = 0
    waitpid(buildPID, &status, 0)
    let exitCode = (status >> 8) & 0xff
    print("wtf: build completed with exit code \(exitCode)")

} catch {
    fputs("wtf: \(error.localizedDescription)\n", stderr)
    exit(1)
}
