import Foundation

/// Computes a time-series of how many processes were running simultaneously.
public enum ConcurrencyComputer {

    /// One data point in the concurrency chart.
    public struct Point: Equatable {
        /// Seconds since build start.
        public let relativeTime: TimeInterval
        /// Number of processes active at this moment.
        public let count: Int

        public init(relativeTime: TimeInterval, count: Int) {
            self.relativeTime = relativeTime
            self.count = count
        }
    }

    /// Compute concurrency samples at regular intervals.
    ///
    /// - Parameters:
    ///   - processes: All processes in the build (from `timeline.allProcesses`).
    ///   - startTime: Absolute build start (from `timeline.startTime`).
    ///   - totalDuration: Total build duration in seconds.
    ///   - bucketSize: Sampling interval in seconds (default 50 ms).
    /// - Returns: Array of `Point` values covering 0 … totalDuration.
    public static func compute(
        processes: [ProcessNode],
        startTime: TimeInterval,
        totalDuration: TimeInterval,
        bucketSize: Double = 0.05
    ) -> [Point] {
        guard totalDuration > 0 else { return [] }

        // Represent each process as (relStart, relEnd).
        let intervals: [(Double, Double)] = processes.compactMap { node in
            guard let end = node.endTime else { return nil }
            let s = node.startTime - startTime
            let e = end - startTime
            guard e > s else { return nil }
            return (s, e)
        }

        let buckets = Int(ceil(totalDuration / bucketSize)) + 1
        var points: [Point] = []
        points.reserveCapacity(buckets)

        for i in 0..<buckets {
            let t = Double(i) * bucketSize
            let count = intervals.count { (s, e) in s <= t && t < e }
            points.append(Point(relativeTime: t, count: count))
        }

        return points
    }

    /// Peak concurrency across all sampled points.
    public static func peak(_ points: [Point]) -> Int {
        points.map(\.count).max() ?? 0
    }
}
