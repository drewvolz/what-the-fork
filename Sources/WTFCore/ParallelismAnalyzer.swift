// Sources/WTFCore/ParallelismAnalyzer.swift
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
        guard cpuCoreCount > 0 else {
            return ParallelismMetrics(score: 0, timeline: [])
        }

        let processes = timeline.allProcesses.filter { $0.endTime != nil }
        guard !processes.isEmpty, timeline.totalDuration > 0 else {
            return ParallelismMetrics(score: 0, timeline: [])
        }

        // Build a sweep-line event list: +1 at start, -1 at end of each process.
        // This gives O(N log N) overall (one sort) rather than O(N²).
        struct SweepEvent {
            let time: TimeInterval
            let delta: Int  // +1 for start, -1 for end
        }

        var sweepEvents: [SweepEvent] = []
        sweepEvents.reserveCapacity(processes.count * 2)
        for p in processes {
            sweepEvents.append(SweepEvent(time: p.startTime, delta: +1))
            sweepEvents.append(SweepEvent(time: p.endTime!, delta: -1))
        }
        // Sort by time; process ends before starts at the same timestamp so
        // a process that ends exactly when another starts is not double-counted.
        sweepEvents.sort {
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.delta < $1.delta  // -1 (end) before +1 (start)
        }

        var timelinePoints: [(TimeInterval, Int)] = []
        var weightedSum = 0.0
        var totalTime = 0.0
        var concurrent = 0
        var lastTime: TimeInterval = sweepEvents.first!.time

        for event in sweepEvents {
            if event.time > lastTime {
                let duration = event.time - lastTime
                timelinePoints.append((lastTime, concurrent))
                weightedSum += Double(concurrent) * duration
                totalTime += duration
                lastTime = event.time
            }
            concurrent += event.delta
        }

        let avgConcurrency = totalTime > 0 ? weightedSum / totalTime : 0
        let score = min(max(avgConcurrency / Double(cpuCoreCount), 0.0), 1.0)

        return ParallelismMetrics(score: score, timeline: timelinePoints)
    }
}
