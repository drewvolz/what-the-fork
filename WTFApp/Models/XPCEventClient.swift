// WTFApp/Models/XPCEventClient.swift
import Foundation
import WTFCore

// Duplicate protocol — matches WTFDaemon/WTFXPCProtocol.swift
@objc protocol WTFDaemonXPCProtocol {
    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void)
    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void)
    func endSession(id: String)
}

/// Connects to the WTFDaemon XPC service and converts raw JSON events into ProcessEvents.
final class XPCEventClient {
    private let sessionID: String
    private var connection: NSXPCConnection?
    var onEvent: ((ProcessEvent) -> Void)?
    var onSessionComplete: (() -> Void)?

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func connect() {
        let conn = NSXPCConnection(machServiceName: "com.whatthefork.daemon")
        conn.remoteObjectInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        conn.resume()
        self.connection = conn
        pollForEvents()
    }

    private func pollForEvents() {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ [weak self] error in
            NSLog("WTFApp: XPC connection error: %@", error.localizedDescription)
            DispatchQueue.main.async { self?.onSessionComplete?() }
        }) as? WTFDaemonXPCProtocol else {
            NSLog("WTFApp: failed to get XPC proxy")
            return
        }

        proxy.subscribeToSession(id: sessionID) { [weak self] data in
            guard let self else { return }
            guard let nsData = data else {
                // Explicit nil from daemon = session ended, all events drained.
                NSLog("WTFApp: received nil — session complete")
                DispatchQueue.main.async { self.onSessionComplete?() }
                return
            }
            // Non-nil data = a real event. Decode and deliver, then keep polling.
            // A decode failure is a skip, NOT a session-end signal.
            if let event = self.decodeEvent(nsData as Data) {
                NSLog("WTFApp: received event type=%@", event.type.rawValue)
                DispatchQueue.main.async { self.onEvent?(event) }
            } else {
                NSLog("WTFApp: WARNING — failed to decode event, skipping")
            }
            self.pollForEvents()
        }
    }

    private func decodeEvent(_ data: Data) -> ProcessEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let typeStr = json["type"] as? String,
            let pid = json["pid"] as? Int,
            let ppid = json["ppid"] as? Int,
            let timestamp = json["timestamp"] as? TimeInterval,
            let command = json["command"] as? String
        else { return nil }

        let eventType: ProcessEvent.EventType
        switch typeStr {
        case "fork":  eventType = .fork
        case "exec":  eventType = .exec
        case "exit":  eventType = .exit
        default:      return nil
        }

        return ProcessEvent(
            type: eventType,
            pid: pid,
            ppid: ppid,
            timestamp: timestamp,
            command: command,
            args: json["args"] as? [String] ?? [],
            cwd: json["cwd"] as? String ?? "",
            exitCode: json["exit_code"] as? Int
        )
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
