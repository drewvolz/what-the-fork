// Tests/WTFCoreTests/IntegrationTests.swift
import XCTest
@testable import WTFCore

final class IntegrationTests: XCTestCase {

    private func loadFixture() throws -> [ProcessEvent] {
        let url = Bundle.module.url(forResource: "cargo_build_events", withExtension: "json",
                                    subdirectory: "Fixtures")
            ?? URL(fileURLWithPath: "Tests/WTFCoreTests/Fixtures/cargo_build_events.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ProcessEvent].self, from: data)
    }

    func testFixture_buildsTreeWithCorrectStructure() throws {
        let events = try loadFixture()
        let root = TreeBuilder.buildTree(from: events, rootPID: 1000)
        XCTAssertEqual(root.id, 1000)
        XCTAssertEqual(root.command, "/usr/bin/cargo")
        XCTAssertEqual(root.children.count, 4)  // rustc x3 + ld
        let commandNames = root.children.map(\.commandName)
        XCTAssertTrue(commandNames.contains("ld"))
        XCTAssertEqual(commandNames.filter { $0 == "rustc" }.count, 3)
    }

    func testFixture_analysisFindsLinkerOnCriticalPath() throws {
        let events = try loadFixture()
        let root = TreeBuilder.buildTree(from: events, rootPID: 1000)
        let criticalPath = CriticalPathFinder.findCriticalPath(root)
        // The ld linker runs last — it should be on the critical path
        XCTAssertTrue(criticalPath.map(\.commandName).contains("ld"))
    }

    func testFixture_noGaps_inConcurrentBuild() throws {
        let events = try loadFixture()
        let root = TreeBuilder.buildTree(from: events, rootPID: 1000)
        guard let end = root.endTime else { XCTFail("root has no endTime"); return }
        let tl = Timeline(rootNode: root, startTime: root.startTime, totalDuration: end - root.startTime)
        let gaps = GapDetector.detectGaps(tl, threshold: 0.5)
        // The two rustc processes run in parallel from 0.1–3.0, no significant gap
        XCTAssertTrue(gaps.isEmpty)
    }

    func testFixture_fullAnalysisPipeline() throws {
        let events = try loadFixture()
        let root = TreeBuilder.buildTree(from: events, rootPID: 1000)
        guard let end = root.endTime else { XCTFail(); return }
        let tl = Timeline(rootNode: root, startTime: root.startTime, totalDuration: end - root.startTime)
        let metrics = ParallelismAnalyzer.analyzeParallelism(tl, cpuCoreCount: 4)
        let gaps = GapDetector.detectGaps(tl)
        let criticalPath = CriticalPathFinder.findCriticalPath(root)
        let analysis = BuildAnalysis(parallelismScore: metrics.score, gaps: gaps, criticalPath: criticalPath, suggestions: [])
        let suggestions = SuggestionEngine.generateSuggestions(tl, analysis)
        // Sanity checks
        XCTAssertGreaterThan(metrics.score, 0)
        XCTAssertLessThanOrEqual(metrics.score, 1.0)
        XCTAssertFalse(criticalPath.isEmpty)
        // This build has decent parallelism — no noParallelism suggestion expected
        XCTAssertFalse(suggestions.contains { $0.category == .noParallelism })
    }
}
