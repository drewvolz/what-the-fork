// WTFDaemon/XPCEventServer.swift
import Foundation

/// NSXPCListener delegate that accepts connections and serves event streams.
final class XPCEventServer: NSObject, NSXPCListenerDelegate {
    static let serviceName = "com.whatthefork.daemon"

    private var activeSessions: [String: ESFClient] = [:]
    private var pendingReplies: [String: [(NSData?) -> Void]] = [:]
    /// Sessions that ended before the app subscribed — immediately resolve any late subscriber.
    private var endedSessions: Set<String> = []
    private let queue = DispatchQueue(label: "com.whatthefork.daemon.events", qos: .userInteractive)

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        connection.exportedObject = XPCSessionHandler(server: self)
        connection.resume()
        return true
    }

    func startSession(id: String, rootPID: Int32) {
        queue.async { [weak self] in
            guard let self else { return }
            NSLog("WTFDaemon: startSession id=%@ rootPID=%d", id, rootPID)
            let client = ESFClient(rootPID: rootPID) { [weak self] event in
                self?.broadcastEvent(event, sessionID: id)
            }
            self.activeSessions[id] = client
            try? client.start()
        }
    }

    func endSession(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            NSLog("WTFDaemon: endSession id=%@", id)
            let replies = self.pendingReplies.removeValue(forKey: id) ?? []
            NSLog("WTFDaemon: flushing %d pending replies", replies.count)
            replies.forEach { $0(nil) }
            self.activeSessions.removeValue(forKey: id)
            // Mark as ended so late subscribers get an immediate nil
            self.endedSessions.insert(id)
        }
    }

    func addSubscriber(sessionID: String, reply: @escaping (NSData?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.endedSessions.contains(sessionID) {
                // Session already ended — immediately signal completion
                NSLog("WTFDaemon: late subscriber for ended session %@, resolving immediately", sessionID)
                reply(nil)
            } else {
                self.pendingReplies[sessionID, default: []].append(reply)
            }
        }
    }

    private func broadcastEvent(_ event: ESFClient.ProcessEventData, sessionID: String) {
        queue.async { [weak self] in
            guard let self,
                  var replies = self.pendingReplies[sessionID], !replies.isEmpty else { return }
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
            let reply = replies.removeFirst()
            self.pendingReplies[sessionID] = replies
            reply(nsData)
        }
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
