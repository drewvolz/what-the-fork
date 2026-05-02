// wtf/DaemonLauncher.swift
import Foundation

/// Connects to the WTFDaemon XPC service and registers a monitoring session.
/// Non-fatal: if the daemon isn't running, prints a warning and continues.
enum DaemonLauncher {

    static func startSession(id: String, rootPID: pid_t) {
        let connection = NSXPCConnection(machServiceName: "com.whatthefork.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        connection.resume()

        let sema = DispatchSemaphore(value: 0)
        var connected = false

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            sema.signal()
        } as? WTFDaemonXPCProtocol

        proxy?.startSession(id: id, rootPID: Int32(rootPID)) { success in
            connected = success
            sema.signal()
        }

        // Short timeout — don't block the build waiting for daemon
        if sema.wait(timeout: .now() + 2) == .timedOut || !connected {
            fputs("wtf: daemon not running — install it with: ./scripts/install-daemon.sh\n", stderr)
        }
    }

    /// Notify the daemon that the build is complete so the app can finalize.
    static func endSession(id: String) {
        let connection = NSXPCConnection(machServiceName: "com.whatthefork.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in } as? WTFDaemonXPCProtocol
        proxy?.endSession(id: id)
        // Brief pause to let the one-way XPC message dispatch before we exit
        Thread.sleep(forTimeInterval: 0.2)
        connection.invalidate()
    }
}

// Duplicate protocol declaration for CLI target (no shared framework yet)
@objc protocol WTFDaemonXPCProtocol {
    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void)
    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void)
    func endSession(id: String)
}
