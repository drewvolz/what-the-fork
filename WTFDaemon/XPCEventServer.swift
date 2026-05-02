// WTFDaemon/XPCEventServer.swift
import Foundation

/// NSXPCListener delegate that accepts connections and serves event streams.
final class XPCEventServer: NSObject, NSXPCListenerDelegate {
    static let serviceName = "com.whatthefork.daemon"

    /// Single global ESF client, started at init, always listening.
    private var esfClient: ESFClient!
    /// Sessions that are currently open.
    private var activeSessions: Set<String> = []
    /// Maps each tracked PID → the session it belongs to.
    private var pidToSession: [pid_t: String] = [:]
    /// Pending long-poll reply blocks waiting for the next event.
    private var pendingReplies: [String: [(NSData?) -> Void]] = [:]
    /// Sessions that have ended — late subscribers get immediate nil.
    private var endedSessions: Set<String> = []
    private let queue = DispatchQueue(label: "com.whatthefork.daemon.events", qos: .userInteractive)

    override init() {
        super.init()
        esfClient = ESFClient { [weak self] event in
            self?.routeEvent(event)
        }
        do {
            try esfClient.start()
        } catch {
            NSLog("WTFDaemon: ESF unavailable: %@", error.localizedDescription)
        }
    }

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
            self.activeSessions.insert(id)
            self.pidToSession[pid_t(rootPID)] = id
        }
    }

    func endSession(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            NSLog("WTFDaemon: endSession id=%@", id)
            // Remove PID mappings for this session
            self.pidToSession = self.pidToSession.filter { $0.value != id }
            self.activeSessions.remove(id)
            // Flush all waiting subscribers with nil to signal completion
            let replies = self.pendingReplies.removeValue(forKey: id) ?? []
            NSLog("WTFDaemon: flushing %d pending replies", replies.count)
            replies.forEach { $0(nil) }
            self.endedSessions.insert(id)
        }
    }

    func addSubscriber(sessionID: String, reply: @escaping (NSData?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.endedSessions.contains(sessionID) {
                NSLog("WTFDaemon: late subscriber for ended session %@, resolving immediately", sessionID)
                reply(nil)
            } else {
                self.pendingReplies[sessionID, default: []].append(reply)
            }
        }
    }

    /// Routes an ESF event to the correct session based on the PID map.
    private func routeEvent(_ event: ESFClient.ProcessEventData) {
        queue.async { [weak self] in
            guard let self else { return }

            let pid = pid_t(event.pid)
            let ppid = pid_t(event.ppid)

            // Determine which session this event belongs to.
            // For fork: the child inherits the parent's session.
            var sessionID: String?
            switch event.type {
            case "fork":
                if let parentSession = self.pidToSession[ppid] {
                    self.pidToSession[pid] = parentSession
                    sessionID = parentSession
                }
            case "exec", "exit":
                sessionID = self.pidToSession[pid]
                if event.type == "exit" {
                    self.pidToSession.removeValue(forKey: pid)
                }
            default:
                break
            }

            guard let sessionID else { return }
            self.broadcast(event, to: sessionID)
        }
    }

    private func broadcast(_ event: ESFClient.ProcessEventData, to sessionID: String) {
        guard var replies = pendingReplies[sessionID], !replies.isEmpty else { return }
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
        let reply = replies.removeFirst()
        pendingReplies[sessionID] = replies
        reply(data as NSData)
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

