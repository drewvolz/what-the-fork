// wtf/main.swift
import Foundation

let allArgs = Array(CommandLine.arguments.dropFirst())

guard !allArgs.isEmpty, allArgs[0] != "--help", allArgs[0] != "-h" else {
    print("""
    Usage: wtf <command> [args...]

    Wraps a build command and visualizes its process tree in real time.

    Examples:
      wtf make
      wtf cargo build
      wtf xcodebuild -scheme MyApp build
    """)
    exit(allArgs.isEmpty ? 1 : 0)
}

let command = allArgs[0]
let commandArgs = Array(allArgs.dropFirst())
let sessionID = UUID().uuidString

do {
    let buildPID = try BuildRunner.launch(command: command, args: commandArgs)
    print("wtf: launched \(command) as PID \(buildPID), session \(sessionID)")

    DaemonLauncher.startSession(id: sessionID, rootPID: buildPID)

    AppLauncher.openApp(sessionID: sessionID, rootPID: buildPID)

    var status: Int32 = 0
    waitpid(buildPID, &status, 0)
    let exitCode = (status >> 8) & 0xff

    DaemonLauncher.endSession(id: sessionID)
    print("wtf: build completed with exit code \(exitCode)")

} catch {
    fputs("wtf: \(error.localizedDescription)\n", stderr)
    exit(1)
}
