// WTFDaemon/ESFClient.swift
import Foundation
import EndpointSecurity

/// Subscribes to ESF process events and calls the handler for each event.
/// Must run as root with the `com.apple.developer.endpoint-security.client` entitlement.
final class ESFClient {
    private var client: OpaquePointer?
    private let rootPID: pid_t
    private let onEvent: (ProcessEventData) -> Void

    struct ProcessEventData {
        let type: String         // "fork" | "exec" | "exit"
        let pid: Int
        let ppid: Int
        let timestamp: TimeInterval
        let command: String
        let args: [String]
        let cwd: String
        let exitCode: Int?
    }

    init(rootPID: pid_t, onEvent: @escaping (ProcessEventData) -> Void) {
        self.rootPID = rootPID
        self.onEvent = onEvent
    }

    func start() throws {
        let result = es_new_client(&client) { [weak self] _, message in
            self?.handleMessage(message)
        }

        guard result == ES_NEW_CLIENT_RESULT_SUCCESS else {
            throw ESFError.clientCreationFailed(result)
        }

        let events: [es_event_type_t] = [
            ES_EVENT_TYPE_NOTIFY_FORK,
            ES_EVENT_TYPE_NOTIFY_EXEC,
            ES_EVENT_TYPE_NOTIFY_EXIT,
        ]
        es_subscribe(client!, events, UInt32(events.count))
    }

    func stop() {
        if let c = client {
            es_delete_client(c)
            client = nil
        }
    }

    private func handleMessage(_ message: UnsafePointer<es_message_t>) {
        let msg = message.pointee
        let pid = audit_token_to_pid(msg.process.pointee.audit_token)
        let ppid = msg.process.pointee.ppid

        // Only observe descendants of rootPID
        guard isDescendant(pid: pid) || pid == rootPID else { return }

        let timestamp = TimeInterval(msg.time.tv_sec) + TimeInterval(msg.time.tv_nsec) / 1_000_000_000

        switch msg.event_type {
        case ES_EVENT_TYPE_NOTIFY_FORK:
            let childPID = audit_token_to_pid(msg.event.fork.child.pointee.audit_token)
            let parentCommand = commandPath(from: msg.process.pointee)
            onEvent(ProcessEventData(
                type: "fork",
                pid: Int(childPID),
                ppid: Int(pid),
                timestamp: timestamp,
                command: parentCommand,
                args: [],
                cwd: cwdPath(from: msg.process.pointee),
                exitCode: nil
            ))

        case ES_EVENT_TYPE_NOTIFY_EXEC:
            let execPID = audit_token_to_pid(msg.process.pointee.audit_token)
            let execEvent = msg.event.exec
            let target = execEvent.target.pointee
            let command = commandPath(from: target)
            let args = execArgs(from: execEvent)
            onEvent(ProcessEventData(
                type: "exec",
                pid: Int(execPID),
                ppid: Int(ppid),
                timestamp: timestamp,
                command: command,
                args: args,
                cwd: cwdPath(from: target),
                exitCode: nil
            ))

        case ES_EVENT_TYPE_NOTIFY_EXIT:
            onEvent(ProcessEventData(
                type: "exit",
                pid: Int(pid),
                ppid: Int(ppid),
                timestamp: timestamp,
                command: commandPath(from: msg.process.pointee),
                args: [],
                cwd: "",
                exitCode: Int(msg.event.exit.stat)
            ))

        default:
            break
        }
    }

    // Walks up the process tree to check if `pid` is a descendant of rootPID.
    private var trackedPIDs: Set<pid_t> = []
    private func isDescendant(pid: pid_t) -> Bool {
        return trackedPIDs.contains(pid)
    }

    func registerChild(pid: pid_t) {
        trackedPIDs.insert(pid)
    }

    private func commandPath(from process: es_process_t) -> String {
        let pathPtr = process.executable.pointee.path
        return String(cString: pathPtr.data)
    }

    private func cwdPath(from process: es_process_t) -> String {
        guard let cwdPtr = process.cwd?.pointee else { return "" }
        return String(cString: cwdPtr.path.data)
    }

    private func execArgs(from event: es_event_exec_t) -> [String] {
        let count = es_exec_arg_count(&event)
        return (0..<count).compactMap { i in
            guard let token = es_exec_arg(&event, i) else { return nil }
            return String(cString: token.data)
        }
    }
}

enum ESFError: Error {
    case clientCreationFailed(es_new_client_result_t)
}
