// WTFDaemon/ESFClient.swift
import Foundation
import EndpointSecurity

/// Global ESF subscription — started once at daemon launch, reports all
/// system process events. Filtering by session is done by XPCEventServer.
final class ESFClient {
    private var client: OpaquePointer?
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

    init(onEvent: @escaping (ProcessEventData) -> Void) {
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
        NSLog("WTFDaemon: ESF subscription active — listening for all process events")
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
        let timestamp = TimeInterval(msg.time.tv_sec) + TimeInterval(msg.time.tv_nsec) / 1_000_000_000

        switch msg.event_type {
        case ES_EVENT_TYPE_NOTIFY_FORK:
            let childPID = audit_token_to_pid(msg.event.fork.child.pointee.audit_token)
            onEvent(ProcessEventData(
                type: "fork",
                pid: Int(childPID),
                ppid: Int(pid),
                timestamp: timestamp,
                command: commandPath(from: msg.process.pointee),
                args: [],
                cwd: "",
                exitCode: nil
            ))

        case ES_EVENT_TYPE_NOTIFY_EXEC:
            var execEvent = msg.event.exec
            let target = execEvent.target.pointee
            onEvent(ProcessEventData(
                type: "exec",
                pid: Int(pid),
                ppid: Int(ppid),
                timestamp: timestamp,
                command: commandPath(from: target),
                args: execArgs(from: &execEvent),
                cwd: "",
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

    private func commandPath(from process: es_process_t) -> String {
        String(cString: process.executable.pointee.path.data)
    }

    private func execArgs(from event: inout es_event_exec_t) -> [String] {
        let count = es_exec_arg_count(&event)
        return (0..<count).map { i in
            String(cString: es_exec_arg(&event, UInt32(i)).data)
        }
    }
}

enum ESFError: Error {
    case clientCreationFailed(es_new_client_result_t)
}
