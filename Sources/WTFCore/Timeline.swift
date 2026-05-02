import Foundation

/// The fully built process tree plus timing metadata for a completed build.
public struct Timeline: Equatable {
    public let rootNode: ProcessNode
    public let startTime: TimeInterval
    public let totalDuration: TimeInterval

    public init(rootNode: ProcessNode, startTime: TimeInterval, totalDuration: TimeInterval) {
        self.rootNode = rootNode
        self.startTime = startTime
        self.totalDuration = totalDuration
    }

    /// All processes in the tree including the root, in DFS order.
    public var allProcesses: [ProcessNode] {
        [rootNode] + rootNode.allDescendants
    }
}

/// Snapshot of CPU core utilization at a point in time.
public struct ParallelismMetrics: Equatable {
    /// 0–1: average ratio of concurrent processes to available CPU cores.
    public let score: Double
    /// Array of (timestamp, concurrentProcessCount) for charting.
    public let timeline: [(TimeInterval, Int)]

    public init(score: Double, timeline: [(TimeInterval, Int)]) {
        self.score = score
        self.timeline = timeline
    }

    public static func == (lhs: ParallelismMetrics, rhs: ParallelismMetrics) -> Bool {
        lhs.score == rhs.score
    }
}

/// An idle period in the build timeline where no processes were running.
public struct GapReport: Equatable {
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let precedingProcess: ProcessNode?
    public let followingProcess: ProcessNode?

    public init(
        startTime: TimeInterval,
        duration: TimeInterval,
        precedingProcess: ProcessNode?,
        followingProcess: ProcessNode?
    ) {
        self.startTime = startTime
        self.duration = duration
        self.precedingProcess = precedingProcess
        self.followingProcess = followingProcess
    }
}

/// An actionable recommendation for improving build speed.
public struct Suggestion: Equatable {
    public enum Category: Equatable {
        case noParallelism
        case unnecessaryRepeatedCalls
        case longGap
        case serialDependencies
    }

    public let category: Category
    public let description: String
    public let relatedNodes: [ProcessNode]

    public init(category: Category, description: String, relatedNodes: [ProcessNode] = []) {
        self.category = category
        self.description = description
        self.relatedNodes = relatedNodes
    }
}

/// Complete analysis results for a finished build.
public struct BuildAnalysis: Equatable {
    public let parallelismScore: Double
    public let gaps: [GapReport]
    public let criticalPath: [ProcessNode]
    public let suggestions: [Suggestion]

    public init(
        parallelismScore: Double,
        gaps: [GapReport],
        criticalPath: [ProcessNode],
        suggestions: [Suggestion]
    ) {
        self.parallelismScore = parallelismScore
        self.gaps = gaps
        self.criticalPath = criticalPath
        self.suggestions = suggestions
    }
}
