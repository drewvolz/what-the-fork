// WTFDaemon/XPCEventServer.swift
import Foundation
import Darwin

/// NSXPCListener delegate that accepts connections and serves event streams.
final class XPCEventServer: NSObject, NSXPCListenerDelegate {
    static let serviceName = "com.whatthefork.daemon"

    /// Single global ESF client, started at init, always listening.
    private var esfClient: ESFClient!
    /// Sessions that are currently open.
    private var activeSessions: Set<String> = []
    /// Maps each tracked PID → the session it belongs to.
    private var pidToSession: [pid_t: String] = [:]
    /// Maps each session → its root PID (the process directly launched by `wtf`).
    private var sessionRootPID: [String: pid_t] = [:]
    /// Sessions where endSession was called but whose root PID hasn't exited via ESF yet.
    /// We hold off flushing nil until the EXIT event arrives so subscribers see it.
    private var endingSessionIDs: Set<String> = []
    /// Events queued for a session when no subscriber is currently waiting.
    private var bufferedEvents: [String: [NSData]] = [:]
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

    func startSession(id: String, rootPID: Int32, reply: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self else { reply(false); return }
            NSLog("WTFDaemon: startSession id=%@ rootPID=%d", id, rootPID)
            self.activeSessions.insert(id)
            self.sessionRootPID[id] = pid_t(rootPID)
            self.pidToSession[pid_t(rootPID)] = id

            // Synthesize an exec event for the root process. The real ESF NOTIFY_EXEC
            // often arrives before startSession is called (timing race), so we generate
            // one from proc_pidpath to guarantee subscribers always see a start entry.
            let cmdPath = Self.commandPath(for: pid_t(rootPID))
            let synthetic = ESFClient.ProcessEventData(
                type: "exec",
                pid: Int(rootPID),
                ppid: 0,
                timestamp: Date().timeIntervalSince1970,
                command: cmdPath,
                args: [],
                cwd: "",
                exitCode: nil
            )
            NSLog("WTFDaemon: synthetic exec for rootPID=%d cmd=%@", rootPID, cmdPath)
            self.enqueue(synthetic, to: id)
            // Reply only after pidToSession is set so the CLI's SIGCONT fires after
            // the daemon is guaranteed to track the root PID's children.
            reply(true)
        }
    }

    private static func commandPath(for pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "unknown"
    }

    func endSession(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            NSLog("WTFDaemon: endSession id=%@", id)
            self.activeSessions.remove(id)
            // If the root PID hasn't exited via ESF yet, defer the nil-flush until
            // its EXIT event arrives (so subscribers see the exit event first).
            if let rootPID = self.sessionRootPID[id], self.pidToSession[rootPID] != nil {
                NSLog("WTFDaemon: deferring finalize for %@ — waiting for ESF exit of pid %d", id, rootPID)
                self.endingSessionIDs.insert(id)
            } else {
                self.finalizeSession(id)
            }
        }
    }

    /// Marks the session as ended and drains any pending subscribers.
    /// Does NOT clear bufferedEvents — addSubscriber will drain the buffer
    /// so late-arriving events are not lost for fast-completing processes.
    private func finalizeSession(_ id: String) {
        pidToSession = pidToSession.filter { $0.value != id }
        sessionRootPID.removeValue(forKey: id)
        endingSessionIDs.remove(id)
        endedSessions.insert(id)
        let replies = pendingReplies.removeValue(forKey: id) ?? []
        NSLog("WTFDaemon: finalizing session %@ — %d buffered events, flushing %d pending replies",
              id, bufferedEvents[id]?.count ?? 0, replies.count)
        // Drain buffered events to any waiting subscribers; fire nil only when buffer is empty.
        for reply in replies {
            if var buffered = bufferedEvents[id], !buffered.isEmpty {
                let data = buffered.removeFirst()
                bufferedEvents[id] = buffered.isEmpty ? nil : buffered
                reply(data)
            } else {
                reply(nil)
            }
        }
    }

    func addSubscriber(sessionID: String, reply: @escaping (NSData?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            // Always drain the buffer first — even for ended sessions — so late subscribers
            // see all buffered events before receiving the nil terminator.
            if var buffered = self.bufferedEvents[sessionID], !buffered.isEmpty {
                let data = buffered.removeFirst()
                self.bufferedEvents[sessionID] = buffered.isEmpty ? nil : buffered
                NSLog("WTFDaemon: replaying buffered event to new subscriber for session %@", sessionID)
                reply(data)
            } else if self.endedSessions.contains(sessionID) {
                NSLog("WTFDaemon: buffer empty, session ended %@ — resolving with nil", sessionID)
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
                    NSLog("WTFDaemon: fork pid=%d ppid=%d → session %@", pid, ppid, parentSession)
                }
            case "exec":
                sessionID = self.pidToSession[pid]
                if let sid = sessionID {
                    NSLog("WTFDaemon: exec pid=%d cmd=%@ → session %@", pid, event.command, sid)
                }
            case "exit":
                sessionID = self.pidToSession.removeValue(forKey: pid)
                NSLog("WTFDaemon: exit pid=%d → session=%@", pid, sessionID ?? "untracked")
                // If this exit completes a deferred endSession, finalize now.
                if let sid = sessionID, self.endingSessionIDs.contains(sid) {
                    self.enqueue(event, to: sid)
                    self.finalizeSession(sid)
                    return
                }
            default:
                break
            }

            guard let sessionID else { return }
            self.enqueue(event, to: sessionID)
        }
    }

    /// Sends an event to a waiting subscriber, or buffers it if none is ready.
    private func enqueue(_ event: ESFClient.ProcessEventData, to sessionID: String) {
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

        if var replies = pendingReplies[sessionID], !replies.isEmpty {
            NSLog("WTFDaemon: sent type=%@ pid=%d → session %@", event.type, event.pid, sessionID)
            let reply = replies.removeFirst()
            pendingReplies[sessionID] = replies
            reply(nsData)
        } else {
            NSLog("WTFDaemon: buffered type=%@ pid=%d for session %@", event.type, event.pid, sessionID)
            bufferedEvents[sessionID, default: []].append(nsData)
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
        server?.startSession(id: id, rootPID: rootPID, reply: reply)
    }

    func endSession(id: String) {
        server?.endSession(id: id)
    }

    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void) {
        server?.addSubscriber(sessionID: id, reply: reply)
    }
}

