// Sources/WTFCore/TreeBuilder.swift
import Foundation

public enum TreeBuilder {

    /// Build a process tree from a flat list of ESF events.
    /// - Parameters:
    ///   - events: All captured events, in any order.
    ///   - rootPID: The PID of the top-level build command.
    /// - Returns: The root ProcessNode with fully nested children.
    public static func buildTree(from events: [ProcessEvent], rootPID: Int) -> ProcessNode {
        // Pass 1: build a mutable node map keyed by PID
        var nodes: [Int: ProcessNode] = [:]

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.type {
            case .fork, .exec:
                if var existing = nodes[event.pid] {
                    // exec after fork: update command + args
                    existing.command = event.command
                    existing.args = event.args
                    nodes[event.pid] = existing
                } else {
                    nodes[event.pid] = ProcessNode(
                        pid: event.pid,
                        command: event.command,
                        args: event.args,
                        cwd: event.cwd,
                        startTime: event.timestamp
                    )
                }
            case .exit:
                if var node = nodes[event.pid] {
                    node.endTime = event.timestamp
                    node.exitCode = event.exitCode
                    nodes[event.pid] = node
                }
            }
        }

        // Pass 2: wire parent–child relationships, collecting all child PIDs
        var childPIDs = Set<Int>()
        for event in events where event.type == .fork || event.type == .exec {
            guard event.pid != rootPID, nodes[event.ppid] != nil else { continue }
            childPIDs.insert(event.pid)
        }

        // Pass 3: for each node, collect its children and attach recursively
        func attachChildren(to pid: Int) -> ProcessNode {
            var node = nodes[pid] ?? ProcessNode(pid: pid, command: "unknown", startTime: 0)
            let directChildPIDs = events
                .filter { ($0.type == .fork || $0.type == .exec) && $0.ppid == pid && $0.pid != pid }
                .map(\.pid)
            let uniqueChildPIDs = Array(Set(directChildPIDs))
            node.children = uniqueChildPIDs.map { attachChildren(to: $0) }
                .sorted { $0.startTime < $1.startTime }
            return node
        }

        return attachChildren(to: rootPID)
    }
}
