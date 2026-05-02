// Sources/WTFCore/GapDetector.swift
import Foundation

public enum GapDetector {

    /// Find idle periods in the build where no processes were running.
    /// - Parameters:
    ///   - timeline: A completed build timeline.
    ///   - threshold: Minimum idle duration (in seconds) to report as a gap. Default 0.1s.
    /// - Returns: Array of GapReport, ordered by start time.
    public static func detectGaps(
        _ timeline: Timeline,
        threshold: TimeInterval = 0.1
    ) -> [GapReport] {
        // Only consider leaf processes (no children) — orchestrators like make/xcodebuild
        // always run the entire build, so including them would eliminate all gaps.
        let processes = timeline.allProcesses.filter { $0.endTime != nil && $0.children.isEmpty }
        guard !processes.isEmpty else { return [] }

        // Collect all (start, end) intervals sorted by start time.
        // All processes here have non-nil endTime (guaranteed by the filter above).
        let intervals = processes
            .map { p -> (TimeInterval, TimeInterval, ProcessNode) in
                return (p.startTime, p.endTime!, p)
            }
            .sorted { $0.0 < $1.0 }

        // Merge overlapping intervals to find continuous "busy" spans
        var mergedIntervals: [(start: TimeInterval, end: TimeInterval)] = []
        for (start, end, _) in intervals {
            if let last = mergedIntervals.last, start <= last.end {
                if end > last.end {
                    mergedIntervals[mergedIntervals.count - 1].end = end
                }
            } else {
                mergedIntervals.append((start, end))
            }
        }

        // Gaps are the spaces between merged intervals
        var gaps: [GapReport] = []
        if mergedIntervals.count < 2 {
            return []
        }
        for i in 0..<(mergedIntervals.count - 1) {
            let gapStart = mergedIntervals[i].end
            let gapEnd = mergedIntervals[i + 1].start
            let duration = gapEnd - gapStart
            guard duration >= threshold else { continue }

            // Find the process that ended most recently before the gap.
            // endTime is non-nil here (guaranteed by the leaf filter).
            let preceding = processes
                .filter { $0.endTime! <= gapStart }
                .max(by: { $0.endTime! < $1.endTime! })

            // Find the process that starts next after the gap
            let following = processes
                .filter { $0.startTime >= gapEnd - 1e-9 }
                .min(by: { $0.startTime < $1.startTime })

            gaps.append(GapReport(
                startTime: gapStart,
                duration: duration,
                precedingProcess: preceding,
                followingProcess: following
            ))
        }

        return gaps
    }
}
