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

        // Find the child whose subtree has the greatest total duration
        let childPaths = node.children.map { longestPath($0) }
        let longestChild = childPaths.max { pathDuration($0) < pathDuration($1) } ?? []

        return [node] + longestChild
    }

    private static func pathDuration(_ path: [ProcessNode]) -> TimeInterval {
        guard let first = path.first, let last = path.last else { return 0 }
        let end = last.endTime ?? last.startTime
        return end - first.startTime
    }
}
