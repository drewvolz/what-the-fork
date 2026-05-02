// Sources/WTFCore/SuggestionEngine.swift
import Foundation

public enum SuggestionEngine {

    private static let lowParallelismThreshold = 0.25
    private static let longGapThreshold: TimeInterval = 1.0
    private static let repeatedCommandThreshold = 3

    /// Generate actionable suggestions based on timeline and analysis data.
    public static func generateSuggestions(
        _ timeline: Timeline,
        _ analysis: BuildAnalysis
    ) -> [Suggestion] {
        var suggestions: [Suggestion] = []

        // Low parallelism
        if analysis.parallelismScore < lowParallelismThreshold {
            suggestions.append(Suggestion(
                category: .noParallelism,
                description: "Build is mostly serial (parallelism score: \(String(format: "%.0f%%", analysis.parallelismScore * 100))). Consider using parallel flags (e.g. `make -j`) or switching to a build system that supports parallelism by default.",
                relatedNodes: []
            ))
        }

        // Long gaps
        let longGaps = analysis.gaps.filter { $0.duration >= longGapThreshold }
        if !longGaps.isEmpty {
            let worstGap = longGaps.max { $0.duration < $1.duration }!
            suggestions.append(Suggestion(
                category: .longGap,
                description: "Build had \(longGaps.count) idle gap(s) longer than 1 second. Longest gap was \(String(format: "%.1f", worstGap.duration))s. This may indicate serial dependencies that could be parallelized.",
                relatedNodes: [worstGap.precedingProcess, worstGap.followingProcess].compactMap { $0 }
            ))
        }

        // Repeated identical commands
        let allProcesses = timeline.allProcesses
        let commandGroups = Dictionary(grouping: allProcesses) { $0.commandName }
        for (commandName, nodes) in commandGroups where nodes.count >= repeatedCommandThreshold {
            // Only flag if they share identical args (true redundancy)
            let argGroups = Dictionary(grouping: nodes) { $0.args.joined(separator: " ") }
            for (args, duplicates) in argGroups where duplicates.count >= repeatedCommandThreshold && !args.isEmpty {
                suggestions.append(Suggestion(
                    category: .unnecessaryRepeatedCalls,
                    description: "`\(commandName) \(args)` was called \(duplicates.count) times with identical arguments. Consider caching its output.",
                    relatedNodes: duplicates
                ))
            }
        }

        return suggestions
    }
}
