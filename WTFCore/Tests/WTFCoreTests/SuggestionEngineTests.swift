// Tests/WTFCoreTests/SuggestionEngineTests.swift
import XCTest
@testable import WTFCore

final class SuggestionEngineTests: XCTestCase {

    private func makeTimeline(children: [ProcessNode], totalDuration: TimeInterval = 10) -> Timeline {
        let root = ProcessNode(pid: 1, command: "/make", startTime: 0, endTime: totalDuration, children: children)
        return Timeline(rootNode: root, startTime: 0, totalDuration: totalDuration)
    }

    func testLowParallelism_suggestsNoParallelism() {
        // 2 serial children on 8-core machine
        let c1 = ProcessNode(pid: 2, command: "/cc", startTime: 0, endTime: 5)
        let c2 = ProcessNode(pid: 3, command: "/cc", startTime: 5, endTime: 10)
        let timeline = makeTimeline(children: [c1, c2])
        let analysis = BuildAnalysis(parallelismScore: 0.15, gaps: [], criticalPath: [], suggestions: [])
        let suggestions = SuggestionEngine.generateSuggestions(timeline, analysis)
        XCTAssertTrue(suggestions.contains { $0.category == .noParallelism })
    }

    func testLongGap_suggestsLongGap() {
        let gap = GapReport(startTime: 2, duration: 2.0, precedingProcess: nil, followingProcess: nil)
        let analysis = BuildAnalysis(parallelismScore: 0.5, gaps: [gap], criticalPath: [], suggestions: [])
        let timeline = makeTimeline(children: [])
        let suggestions = SuggestionEngine.generateSuggestions(timeline, analysis)
        XCTAssertTrue(suggestions.contains { $0.category == .longGap })
    }

    func testRepeatedCommand_suggestsUnnecessaryRepeatedCalls() {
        // Same command run 5 times by the same parent
        let children = (2...6).map { pid in
            ProcessNode(pid: pid, command: "/usr/bin/xcode-select", args: ["-print-path"], startTime: Double(pid), endTime: Double(pid) + 0.1)
        }
        let timeline = makeTimeline(children: children)
        let analysis = BuildAnalysis(parallelismScore: 0.5, gaps: [], criticalPath: [], suggestions: [])
        let suggestions = SuggestionEngine.generateSuggestions(timeline, analysis)
        XCTAssertTrue(suggestions.contains { $0.category == .unnecessaryRepeatedCalls })
    }

    func testGoodBuild_noSuggestions() {
        // High parallelism, no gaps, no repeated commands
        let analysis = BuildAnalysis(parallelismScore: 0.9, gaps: [], criticalPath: [], suggestions: [])
        let children = (2...5).map { ProcessNode(pid: $0, command: "/cc-\($0)", startTime: 0, endTime: 10) }
        let timeline = makeTimeline(children: children)
        let suggestions = SuggestionEngine.generateSuggestions(timeline, analysis)
        XCTAssertTrue(suggestions.isEmpty)
    }
}