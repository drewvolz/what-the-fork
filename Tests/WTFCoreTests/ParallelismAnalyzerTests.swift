import XCTest
@testable import WTFCore

final class ParallelismAnalyzerTests: XCTestCase {

    private func makeTimeline(rootCommand: String = "/make", processes: [(pid: Int, start: Double, end: Double)]) -> Timeline {
        var children: [ProcessNode] = processes.filter { $0.pid != 1 }.map {
            ProcessNode(pid: $0.pid, command: "/cc", startTime: $0.start, endTime: $0.end)
        }
        let rootProcess = processes.first { $0.pid == 1 }!
        let root = ProcessNode(pid: 1, command: rootCommand, startTime: rootProcess.start, endTime: rootProcess.end, children: children)
        return Timeline(rootNode: root, startTime: rootProcess.start, totalDuration: rootProcess.end - rootProcess.start)
    }

    func testAllSerial_scoreIsLow() {
        // 2 processes running one at a time on an 8-core machine → low score
        let timeline = makeTimeline(processes: [
            (pid: 1,  start: 0, end: 10),
            (pid: 2,  start: 0, end: 5),
            (pid: 3,  start: 5, end: 10),
        ])
        let metrics = ParallelismAnalyzer.analyzeParallelism(timeline, cpuCoreCount: 8)
        // At any point only 2 processes run (root + 1 child). Score = 2/8 = 0.25 average
        XCTAssertLessThan(metrics.score, 0.4)
    }

    func testAllParallel_scoreIsHigh() {
        // 8 processes all running simultaneously on 8-core machine → score near 1
        let children = (2...9).map { pid in
            ProcessNode(pid: pid, command: "/cc", startTime: 0, endTime: 10)
        }
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 10, children: children)
        let timeline = Timeline(rootNode: root, startTime: 0, totalDuration: 10)
        let metrics = ParallelismAnalyzer.analyzeParallelism(timeline, cpuCoreCount: 8)
        // 9 processes (root + 8 children) / 8 cores ≈ 1.0+ (capped or not, but high)
        XCTAssertGreaterThan(metrics.score, 0.8)
    }

    func testTimelineHasEntries() {
        let timeline = makeTimeline(processes: [
            (pid: 1, start: 0, end: 5),
            (pid: 2, start: 0, end: 5),
        ])
        let metrics = ParallelismAnalyzer.analyzeParallelism(timeline, cpuCoreCount: 4)
        XCTAssertFalse(metrics.timeline.isEmpty)
    }

    func testScoreIsClamped_betweenZeroAndOne() {
        // Even with 20 processes on 4 cores, score should be clamped to 1.0
        let children = (2...20).map { ProcessNode(pid: $0, command: "/cc", startTime: 0, endTime: 10) }
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 10, children: children)
        let timeline = Timeline(rootNode: root, startTime: 0, totalDuration: 10)
        let metrics = ParallelismAnalyzer.analyzeParallelism(timeline, cpuCoreCount: 4)
        XCTAssertLessThanOrEqual(metrics.score, 1.0)
        XCTAssertGreaterThanOrEqual(metrics.score, 0.0)
    }
}
