// Tests/WTFCoreTests/CriticalPathFinderTests.swift
import XCTest
@testable import WTFCore

final class CriticalPathFinderTests: XCTestCase {

    func testSingleNode_returnsSelf() {
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 10)
        let path = CriticalPathFinder.findCriticalPath(root)
        XCTAssertEqual(path.map(\.id), [1])
    }

    func testTwoChildren_longerChildIsOnCriticalPath() {
        let short = ProcessNode(pid: 2, command: "/cc", startTime: 1, endTime: 3)   // 2s
        let long  = ProcessNode(pid: 3, command: "/cc", startTime: 1, endTime: 6)   // 5s
        let root  = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 7, children: [short, long])
        let path = CriticalPathFinder.findCriticalPath(root)
        XCTAssertTrue(path.map(\.id).contains(3))
        XCTAssertFalse(path.map(\.id).contains(2))
    }

    func testDeepChain_allNodesOnPath() {
        // make → clang → ld (serial chain)
        let ld    = ProcessNode(pid: 3, command: "/ld",    startTime: 3, endTime: 5)
        let clang = ProcessNode(pid: 2, command: "/clang", startTime: 1, endTime: 3, children: [ld])
        let make  = ProcessNode(pid: 1, command: "/make",  startTime: 0, endTime: 5, children: [clang])
        let path = CriticalPathFinder.findCriticalPath(make)
        XCTAssertEqual(path.map(\.id), [1, 2, 3])
    }

    func testReturnsNodesInTopDownOrder() {
        let child = ProcessNode(pid: 2, command: "/cc", startTime: 1, endTime: 4)
        let root  = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 5, children: [child])
        let path = CriticalPathFinder.findCriticalPath(root)
        XCTAssertEqual(path.first?.id, 1)
        XCTAssertEqual(path.last?.id, 2)
    }

    func testLaterStartingChild_withLaterEndTime_isOnCriticalPath() {
        // B starts later but ends later — it's the true bottleneck
        let a = ProcessNode(pid: 2, command: "/cc", startTime: 0, endTime: 7)
        let b = ProcessNode(pid: 3, command: "/cc", startTime: 5, endTime: 9)
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: 9, children: [a, b])
        let path = CriticalPathFinder.findCriticalPath(root)
        XCTAssertTrue(path.map(\.id).contains(3), "Child ending latest must be on critical path")
        XCTAssertFalse(path.map(\.id).contains(2))
    }
}
