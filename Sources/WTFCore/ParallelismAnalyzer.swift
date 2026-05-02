import Foundation

public enum ParallelismAnalyzer {

    /// Compute a parallelism score (0–1) and per-timestamp concurrency data.
    /// - Parameters:
    ///   - timeline: A completed build timeline.
    ///   - cpuCoreCount: Number of CPU cores to normalize against.
    /// - Returns: `ParallelismMetrics` with score and timeline array.
    public static func analyzeParallelism(
        _ timeline: Timeline,
        cpuCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> ParallelismMetrics {
        let processes = timeline.allProcesses.filter { $0.endTime != nil }
        guard !processes.isEmpty, timeline.totalDuration > 0 else {
            return ParallelismMetrics(score: 0, timeline: [])
        }

        // Collect all event timestamps to sample concurrency at each transition
        var timestamps = Set<TimeInterval>()
        for p in processes {
            timestamps.insert(p.startTime)
            if let end = p.endTime { timestamps.insert(end) }
        }
        let sorted = timestamps.sorted()

        var timelinePoints: [(TimeInterval, Int)] = []
        var weightedSum = 0.0
        var totalTime = 0.0

        for i in 0..<(sorted.count - 1) {
            let t = sorted[i]
            let nextT = sorted[i + 1]
            let duration = nextT - t

            let concurrent = processes.filter { node in
                node.startTime <= t && (node.endTime ?? Double.infinity) > t
            }.count

            timelinePoints.append((t, concurrent))
            weightedSum += Double(concurrent) * duration
            totalTime += duration
        }

        let avgConcurrency = totalTime > 0 ? weightedSum / totalTime : 0
        let score = min(avgConcurrency / Double(cpuCoreCount), 1.0)

        return ParallelismMetrics(score: score, timeline: timelinePoints)
    }
}
