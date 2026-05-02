// Sources/WTFCore/CriticalPathFinder.swift
import Foundation

public enum CriticalPathFinder {

    /// Find the longest-duration dependency chain from root to leaf.
    /// - Parameter root: The root ProcessNode of the tree.
    /// - Returns: Array of ProcessNodes from root → critical leaf, ordered top-down.
    public static func findCriticalPath(_ root: ProcessNode) -> [ProcessNode] {
        return longestPath(root)
    }

    // Returns [root, ..., deepest node on critical path]
    private static func longestPath(_ node: ProcessNode) -> [ProcessNode] {
        guard !node.children.isEmpty else { return [node] }

        // Find the child whose subtree ends latest in absolute time.
        // Using absolute endTime (not duration) because a child that starts
        // later but finishes later is the true bottleneck.
        let childPaths = node.children.map { longestPath($0) }
        let longestChild = childPaths.max { pathEndTime($0) < pathEndTime($1) } ?? []

        return [node] + longestChild
    }

    // The absolute end time of the last node on a path.
    // Nil endTime (still-running process) falls back to startTime (zero additional duration).
    private static func pathEndTime(_ path: [ProcessNode]) -> TimeInterval {
        guard let last = path.last else { return 0 }
        return last.endTime ?? last.startTime
    }
}
