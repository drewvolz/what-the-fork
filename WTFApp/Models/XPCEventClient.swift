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
            DispatchQueue.main.async { self?.onSessionComplete?() }
        }) as? WTFDaemonXPCProtocol else { return }

        proxy.subscribeToSession(id: sessionID) { [weak self] data in
            guard let self else { return }
            if let data = data as Data?, let event = self.decodeEvent(data) {
                DispatchQueue.main.async { self.onEvent?(event) }
                // Immediately re-subscribe for the next event (long-poll pattern)
                self.pollForEvents()
            } else {
                DispatchQueue.main.async { self.onSessionComplete?() }
            }
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
