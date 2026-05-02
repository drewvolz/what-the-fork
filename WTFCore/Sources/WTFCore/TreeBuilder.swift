// Sources/WTFCore/TreeBuilder.swift
import Foundation

public enum TreeBuilder {

    /// Build a process tree from a flat list of ESF events.
    /// - Parameters:
    ///   - events: All captured events, in any order.
    ///   - rootPID: The PID of the top-level build command.
    /// - Returns: The root ProcessNode with fully nested children.
    public static func buildTree(from events: [ProcessEvent], rootPID: Int) -> ProcessNode {
        // Pass 1: build a node map keyed by PID.
        // Sort by timestamp, then by event type (fork < exec < exit) so that
        // when fork+exec share a timestamp, fork creates the node first and exec
        // correctly overwrites the command with the real executable name.
        var nodes: [Int: ProcessNode] = [:]
        let typeOrder: [ProcessEvent.EventType: Int] = [.fork: 0, .exec: 1, .exit: 2]

        for event in events.sorted(by: {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return (typeOrder[$0.type] ?? 0) < (typeOrder[$1.type] ?? 0)
        }) {
            switch event.type {
            case .fork:
                if nodes[event.pid] == nil {
                    nodes[event.pid] = ProcessNode(
                        pid: event.pid,
                        command: event.command,
                        args: event.args,
                        cwd: event.cwd,
                        startTime: event.timestamp
                    )
                }
            case .exec:
                if var existing = nodes[event.pid] {
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
                } else {
                    // ESF exec notification was missed (arrived before session registration).
                    // Create a best-effort node from the exit event so the root still appears.
                    nodes[event.pid] = ProcessNode(
                        pid: event.pid,
                        command: event.command,
                        args: event.args,
                        cwd: event.cwd,
                        startTime: event.timestamp,
                        endTime: event.timestamp,
                        exitCode: event.exitCode
                    )
                }
            }
        }

        // Pass 2: precompute a parent → sorted-children map.
        var childrenByParent: [Int: [Int]] = [:]
        for event in events where event.type == .fork || event.type == .exec {
            guard event.pid != event.ppid, nodes[event.pid] != nil else { continue }
            if childrenByParent[event.ppid] == nil {
                childrenByParent[event.ppid] = []
            }
            if !childrenByParent[event.ppid]!.contains(event.pid) {
                childrenByParent[event.ppid]!.append(event.pid)
            }
        }

        // Pass 3: recursively assemble tree using the children map.
        func attachChildren(to pid: Int, depth: Int = 0) -> ProcessNode {
            var node = nodes[pid] ?? ProcessNode(pid: pid, command: "unknown", startTime: 0)
            guard depth < 500 else { return node }
            let childPIDs = (childrenByParent[pid] ?? [])
                .compactMap { nodes[$0] }
                .sorted { $0.startTime < $1.startTime }
                .map(\ .id)
            node.children = childPIDs.map { attachChildren(to: $0, depth: depth + 1) }
            return node
        }

        return attachChildren(to: rootPID)
    }
}
