// wtf/DaemonLauncher.swift
import Foundation

/// Connects to the WTFDaemon XPC service and registers a monitoring session.
enum DaemonLauncher {

    static func startSession(id: String, rootPID: pid_t) throws {
        let connection = NSXPCConnection(machServiceName: "com.whatthefork.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            fputs("wtf: daemon connection error: \(error)\n", stderr)
        } as? WTFDaemonXPCProtocol

        let sema = DispatchSemaphore(value: 0)
        proxy?.startSession(id: id, rootPID: Int32(rootPID)) { success in
            if !success {
                fputs("wtf: daemon failed to start session\n", stderr)
            }
            sema.signal()
        }
        sema.wait()
    }
}

// Duplicate protocol declaration for CLI target (no shared framework yet)
@objc protocol WTFDaemonXPCProtocol {
    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void)
    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void)
}
