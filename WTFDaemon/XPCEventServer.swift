// WTFDaemon/XPCEventServer.swift
import Foundation

/// NSXPCListener delegate that accepts connections and serves event streams.
final class XPCEventServer: NSObject, NSXPCListenerDelegate {
    static let serviceName = "com.whatthefork.daemon"

    private var activeSessions: [String: ESFClient] = [:]
    private var pendingReplies: [String: [(NSData?) -> Void]] = [:]
    private let queue = DispatchQueue(label: "com.whatthefork.daemon.events", qos: .userInteractive)

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        connection.exportedObject = XPCSessionHandler(server: self)
        connection.resume()
        return true
    }

    func startSession(id: String, rootPID: Int32) {
        let client = ESFClient(rootPID: rootPID) { [weak self] event in
            self?.broadcastEvent(event, sessionID: id)
        }
        activeSessions[id] = client
        try? client.start()
    }

    func endSession(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            // Flush all waiting subscribers with nil to signal completion
            let replies = self.pendingReplies.removeValue(forKey: id) ?? []
            replies.forEach { $0(nil) }
            self.activeSessions.removeValue(forKey: id)
        }
    }

    func addSubscriber(sessionID: String, reply: @escaping (NSData?) -> Void) {
        pendingReplies[sessionID, default: []].append(reply)
    }

    private func broadcastEvent(_ event: ESFClient.ProcessEventData, sessionID: String) {
        guard let replies = pendingReplies[sessionID], !replies.isEmpty else { return }
        let dict: [String: Any] = [
            "type": event.type,
            "pid": event.pid,
            "ppid": event.ppid,
            "timestamp": event.timestamp,
            "command": event.command,
            "args": event.args,
            "cwd": event.cwd,
            "exit_code": event.exitCode as Any,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let nsData = data as NSData
        // Send to first waiting subscriber, rotate queue
        let reply = pendingReplies[sessionID]!.removeFirst()
        reply(nsData)
    }
}

/// The exported XPC object — one per connection.
final class XPCSessionHandler: NSObject, WTFDaemonXPCProtocol {
    private weak var server: XPCEventServer?

    init(server: XPCEventServer) {
        self.server = server
    }

    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void) {
        server?.startSession(id: id, rootPID: rootPID)
        reply(true)
    }

    func endSession(id: String) {
        server?.endSession(id: id)
    }

    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void) {
        server?.addSubscriber(sessionID: id, reply: reply)
    }
}
