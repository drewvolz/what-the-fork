// wtf/main.swift
import Foundation

let allArgs = Array(CommandLine.arguments.dropFirst())

guard !allArgs.isEmpty, allArgs[0] != "--help", allArgs[0] != "-h" else {
    print("""
    Usage: wtf <command> [args...]

    Wraps a build command and visualizes its process tree in real time.
    Press Ctrl+C to stop capturing early (useful for long-running apps).

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
    print("wtf: press Ctrl+C to stop capturing")

    DaemonLauncher.startSession(id: sessionID, rootPID: buildPID)
    AppLauncher.openApp(sessionID: sessionID, rootPID: buildPID)

    // Handle Ctrl+C: end the session cleanly rather than abandoning it.
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler {
        print("\nwtf: stopping capture...")
        kill(buildPID, SIGTERM)
        DaemonLauncher.endSession(id: sessionID)
        print("wtf: capture stopped")
        exit(0)
    }
    signal(SIGINT, SIG_IGN)
    sigintSource.resume()

    // Wait for child on a background thread so main RunLoop can process signals.
    DispatchQueue.global().async {
        var status: Int32 = 0
        waitpid(buildPID, &status, 0)
        let exitCode = (status >> 8) & 0xff

        DispatchQueue.main.async {
            sigintSource.cancel()
            DaemonLauncher.endSession(id: sessionID)
            print("wtf: build completed with exit code \(exitCode)")
            exit(0)
        }
    }

    RunLoop.main.run()

} catch {
    fputs("wtf: \(error.localizedDescription)\n", stderr)
    exit(1)
}
