// Tests/WTFCoreTests/GapDetectorTests.swift
import XCTest
@testable import WTFCore

final class GapDetectorTests: XCTestCase {

    func testNoGap_whenProcessesOverlap() {
        let child1 = ProcessNode(pid: 2, command: "/cc", startTime: 0.5, endTime: 2.0)
        let child2 = ProcessNode(pid: 3, command: "/cc", startTime: 1.5, endTime: 3.0)
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 4.0, children: [child1, child2])
        let timeline = Timeline(rootNode: root, startTime: 0, totalDuration: 4.0)
        let gaps = GapDetector.detectGaps(timeline, threshold: 0.1)
        XCTAssertTrue(gaps.isEmpty)
    }

    func testGapDetected_betweenSequentialProcesses() {
        // child1 ends at 1.0, child2 starts at 2.0 — 1 second gap
        let child1 = ProcessNode(pid: 2, command: "/cc", startTime: 0.0, endTime: 1.0)
        let child2 = ProcessNode(pid: 3, command: "/ld", startTime: 2.0, endTime: 3.0)
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 3.0, children: [child1, child2])
        let timeline = Timeline(rootNode: root, startTime: 0, totalDuration: 3.0)
        let gaps = GapDetector.detectGaps(timeline, threshold: 0.1)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].startTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(gaps[0].duration, 1.0, accuracy: 0.001)
    }

    func testThreshold_smallGapsIgnored() {
        // 50ms gap should not appear when threshold is 100ms
        let child1 = ProcessNode(pid: 2, command: "/cc", startTime: 0.0, endTime: 1.0)
        let child2 = ProcessNode(pid: 3, command: "/cc", startTime: 1.05, endTime: 2.0)
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 2.0, children: [child1, child2])
        let timeline = Timeline(rootNode: root, startTime: 0, totalDuration: 2.0)
        let gaps = GapDetector.detectGaps(timeline, threshold: 0.1)
        XCTAssertTrue(gaps.isEmpty)
    }

    func testMultipleGaps_allDetected() {
        let c1 = ProcessNode(pid: 2, command: "/cc", startTime: 0.0, endTime: 1.0)
        let c2 = ProcessNode(pid: 3, command: "/cc", startTime: 2.0, endTime: 3.0)
        let c3 = ProcessNode(pid: 4, command: "/ld", startTime: 4.0, endTime: 5.0)
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 5.0, children: [c1, c2, c3])
        let timeline = Timeline(rootNode: root, startTime: 0, totalDuration: 5.0)
        let gaps = GapDetector.detectGaps(timeline, threshold: 0.1)
        XCTAssertEqual(gaps.count, 2)
    }

    func testGap_precedingAndFollowingProcessCorrect() {
        let child1 = ProcessNode(pid: 2, command: "/cc", startTime: 0.0, endTime: 1.0)
        let child2 = ProcessNode(pid: 3, command: "/ld", startTime: 2.0, endTime: 3.0)
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 3.0, children: [child1, child2])
        let timeline = Timeline(rootNode: root, startTime: 0, totalDuration: 3.0)
        let gaps = GapDetector.detectGaps(timeline, threshold: 0.1)
        XCTAssertEqual(gaps[0].precedingProcess?.id, 2)
        XCTAssertEqual(gaps[0].followingProcess?.id, 3)
    }
}
