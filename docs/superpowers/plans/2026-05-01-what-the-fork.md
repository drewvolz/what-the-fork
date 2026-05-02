# What the Fork — macOS Native Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS-native build visualization tool that uses the Endpoint Security Framework to capture process syscalls during a build and displays them as an interactive timeline.

**Architecture:** Three-tier modular design: (1) `WTFCore` — a pure Swift package with all tree-building and analysis logic, fully testable without ESF; (2) `WTFDaemon` — a privileged ESF helper that captures fork/exec/exit events and streams them via XPC; (3) `WhatTheFork.app` — SwiftUI app that visualizes the timeline; (4) `wtf` CLI tool that ties everything together.

**Tech Stack:** Swift 5.9+, SwiftUI, Endpoint Security Framework, ServiceManagement (SMAppService), XPC (NSXPCConnection), XCTest, xcodegen

---

## File Map

```
what-the-fork/
├── Package.swift                            # WTFCore Swift package
├── Sources/WTFCore/
│   ├── ProcessEvent.swift                   # Codable event types
│   ├── ProcessNode.swift                    # Tree node + supporting types
│   ├── Timeline.swift                       # Timeline, BuildAnalysis, Suggestion
│   ├── TreeBuilder.swift                    # buildTree(from:) → ProcessNode
│   ├── ParallelismAnalyzer.swift            # analyzeParallelism(_:) → ParallelismMetrics
│   ├── GapDetector.swift                    # detectGaps(_:threshold:) → [GapReport]
│   ├── CriticalPathFinder.swift             # findCriticalPath(_:) → [ProcessNode]
│   └── SuggestionEngine.swift               # generateSuggestions(_:_:) → [Suggestion]
├── Tests/WTFCoreTests/
│   ├── TreeBuilderTests.swift
│   ├── ParallelismAnalyzerTests.swift
│   ├── GapDetectorTests.swift
│   ├── CriticalPathFinderTests.swift
│   └── SuggestionEngineTests.swift
├── project.yml                              # xcodegen configuration
├── WhatTheFork/                             # Xcode project (generated)
│   ├── WTFDaemon/
│   │   ├── main.swift                       # Entry point; starts XPC server
│   │   ├── ESFClient.swift                  # ESF subscription + PID filtering
│   │   └── XPCEventServer.swift             # NSXPCListener; streams events to app
│   ├── WTFApp/
│   │   ├── WhatTheForkApp.swift             # @main; opens/registers daemon on first launch
│   │   ├── Models/
│   │   │   ├── BuildSession.swift           # ObservableObject; owns Timeline + BuildAnalysis
│   │   │   └── XPCEventClient.swift         # NSXPCConnection to daemon; feeds BuildSession
│   │   ├── Views/
│   │   │   ├── ContentView.swift            # Main window layout
│   │   │   ├── TimelineView.swift           # Canvas-based scrollable timeline
│   │   │   ├── ProcessBoxView.swift         # Box rendering with color + nesting
│   │   │   ├── ProcessDetailPanel.swift     # Selected process details
│   │   │   └── AnalysisPanel.swift          # Metrics + suggestions
│   │   └── Helpers/
│   │       └── ProcessClassifier.swift      # command basename → ProcessCategory
│   └── wtf/
│       ├── main.swift                       # CLI entry point
│       ├── BuildRunner.swift                # Fork build command; return root PID
│       ├── DaemonLauncher.swift             # Connect to XPC daemon; send startSession
│       └── AppLauncher.swift                # Open WhatTheFork.app via NSWorkspace/URL scheme
```

---

## Phase 1: Foundation

### Task 1: Initialize SPM package for WTFCore

**Files:**
- Create: `Package.swift`
- Create: `Sources/WTFCore/.gitkeep`
- Create: `Tests/WTFCoreTests/.gitkeep`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WTFCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WTFCore", targets: ["WTFCore"]),
    ],
    targets: [
        .target(name: "WTFCore", path: "Sources/WTFCore"),
        .testTarget(
            name: "WTFCoreTests",
            dependencies: ["WTFCore"],
            path: "Tests/WTFCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create placeholder source file so SPM finds the target**

```bash
mkdir -p Sources/WTFCore Tests/WTFCoreTests
touch Sources/WTFCore/.gitkeep Tests/WTFCoreTests/.gitkeep
```

- [ ] **Step 3: Verify the package resolves**

Run: `swift package resolve`
Expected: exits 0, no errors

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "chore: initialize WTFCore Swift package"
```

---

### Task 2: WTFCore data types

**Files:**
- Create: `Sources/WTFCore/ProcessEvent.swift`
- Create: `Sources/WTFCore/ProcessNode.swift`
- Create: `Sources/WTFCore/Timeline.swift`

- [ ] **Step 1: Create ProcessEvent.swift**

```swift
import Foundation

/// A single syscall event captured from the Endpoint Security Framework.
public struct ProcessEvent: Codable, Equatable {
    public enum EventType: String, Codable {
        case fork, exec, exit
    }

    public let type: EventType
    public let pid: Int
    public let ppid: Int
    public let timestamp: TimeInterval
    public let command: String
    public let args: [String]
    public let cwd: String
    public let exitCode: Int?

    public init(
        type: EventType,
        pid: Int,
        ppid: Int,
        timestamp: TimeInterval,
        command: String,
        args: [String],
        cwd: String,
        exitCode: Int? = nil
    ) {
        self.type = type
        self.pid = pid
        self.ppid = ppid
        self.timestamp = timestamp
        self.command = command
        self.args = args
        self.cwd = cwd
        self.exitCode = exitCode
    }
}
```

- [ ] **Step 2: Create ProcessNode.swift**

```swift
import Foundation

/// A node in the process tree representing a single process during a build.
public struct ProcessNode: Identifiable, Equatable {
    public let id: Int  // pid

    public var command: String
    public var args: [String]
    public var cwd: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var children: [ProcessNode]
    public var exitCode: Int?

    public init(
        pid: Int,
        command: String,
        args: [String] = [],
        cwd: String = "",
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        children: [ProcessNode] = [],
        exitCode: Int? = nil
    ) {
        self.id = pid
        self.command = command
        self.args = args
        self.cwd = cwd
        self.startTime = startTime
        self.endTime = endTime
        self.children = children
        self.exitCode = exitCode
    }

    /// Duration in seconds. Returns nil if the process has not yet exited.
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end - startTime
    }

    /// The basename of the command path (e.g. "clang" from "/usr/bin/clang").
    public var commandName: String {
        URL(fileURLWithPath: command).lastPathComponent
    }

    /// All descendants (children, grandchildren, etc.) in DFS order.
    public var allDescendants: [ProcessNode] {
        children.flatMap { [$0] + $0.allDescendants }
    }
}
```

- [ ] **Step 3: Create Timeline.swift**

```swift
import Foundation

/// The fully built process tree plus timing metadata for a completed build.
public struct Timeline: Equatable {
    public let rootNode: ProcessNode
    public let startTime: TimeInterval
    public let totalDuration: TimeInterval

    public init(rootNode: ProcessNode, startTime: TimeInterval, totalDuration: TimeInterval) {
        self.rootNode = rootNode
        self.startTime = startTime
        self.totalDuration = totalDuration
    }

    /// All processes in the tree including the root, in DFS order.
    public var allProcesses: [ProcessNode] {
        [rootNode] + rootNode.allDescendants
    }
}

/// Snapshot of CPU core utilization at a point in time.
public struct ParallelismMetrics: Equatable {
    /// 0–1: average ratio of concurrent processes to available CPU cores.
    public let score: Double
    /// Array of (timestamp, concurrentProcessCount) for charting.
    public let timeline: [(TimeInterval, Int)]

    public init(score: Double, timeline: [(TimeInterval, Int)]) {
        self.score = score
        self.timeline = timeline
    }

    public static func == (lhs: ParallelismMetrics, rhs: ParallelismMetrics) -> Bool {
        lhs.score == rhs.score
    }
}

/// An idle period in the build timeline where no processes were running.
public struct GapReport: Equatable {
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let precedingProcess: ProcessNode?
    public let followingProcess: ProcessNode?

    public init(
        startTime: TimeInterval,
        duration: TimeInterval,
        precedingProcess: ProcessNode?,
        followingProcess: ProcessNode?
    ) {
        self.startTime = startTime
        self.duration = duration
        self.precedingProcess = precedingProcess
        self.followingProcess = followingProcess
    }
}

/// An actionable recommendation for improving build speed.
public struct Suggestion: Equatable {
    public enum Category: Equatable {
        case noParallelism
        case unnecessaryRepeatedCalls
        case longGap
        case serialDependencies
    }

    public let category: Category
    public let description: String
    public let relatedNodes: [ProcessNode]

    public init(category: Category, description: String, relatedNodes: [ProcessNode] = []) {
        self.category = category
        self.description = description
        self.relatedNodes = relatedNodes
    }
}

/// Complete analysis results for a finished build.
public struct BuildAnalysis: Equatable {
    public let parallelismScore: Double
    public let gaps: [GapReport]
    public let criticalPath: [ProcessNode]
    public let suggestions: [Suggestion]

    public init(
        parallelismScore: Double,
        gaps: [GapReport],
        criticalPath: [ProcessNode],
        suggestions: [Suggestion]
    ) {
        self.parallelismScore = parallelismScore
        self.gaps = gaps
        self.criticalPath = criticalPath
        self.suggestions = suggestions
    }
}
```

- [ ] **Step 4: Verify the package compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/WTFCore/
git commit -m "feat(WTFCore): add core data types — ProcessEvent, ProcessNode, Timeline"
```

---

## Phase 2: Analysis Engine (TDD)

### Task 3: TreeBuilder — build process tree from events

**Files:**
- Create: `Sources/WTFCore/TreeBuilder.swift`
- Create: `Tests/WTFCoreTests/TreeBuilderTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WTFCoreTests/TreeBuilderTests.swift
import XCTest
@testable import WTFCore

final class TreeBuilderTests: XCTestCase {

    func testSingleProcess_createsRootNode() {
        let events: [ProcessEvent] = [
            .init(type: .exec, pid: 100, ppid: 1, timestamp: 1.0, command: "/bin/bash", args: ["build.sh"], cwd: "/proj"),
            .init(type: .exit, pid: 100, ppid: 1, timestamp: 3.0, command: "/bin/bash", args: [], cwd: "/proj", exitCode: 0),
        ]
        let root = TreeBuilder.buildTree(from: events, rootPID: 100)
        XCTAssertEqual(root.id, 100)
        XCTAssertEqual(root.command, "/bin/bash")
        XCTAssertEqual(root.startTime, 1.0)
        XCTAssertEqual(root.endTime, 3.0)
        XCTAssertEqual(root.exitCode, 0)
        XCTAssertTrue(root.children.isEmpty)
    }

    func testParentChild_nestedCorrectly() {
        let events: [ProcessEvent] = [
            .init(type: .exec, pid: 100, ppid: 1,   timestamp: 0.0, command: "/usr/bin/make",  args: [], cwd: "/proj"),
            .init(type: .fork, pid: 101, ppid: 100,  timestamp: 0.5, command: "/usr/bin/clang", args: ["-O2", "a.c"], cwd: "/proj"),
            .init(type: .exit, pid: 101, ppid: 100,  timestamp: 2.0, command: "/usr/bin/clang", args: [], cwd: "/proj", exitCode: 0),
            .init(type: .exit, pid: 100, ppid: 1,    timestamp: 2.5, command: "/usr/bin/make",  args: [], cwd: "/proj", exitCode: 0),
        ]
        let root = TreeBuilder.buildTree(from: events, rootPID: 100)
        XCTAssertEqual(root.children.count, 1)
        let child = root.children[0]
        XCTAssertEqual(child.id, 101)
        XCTAssertEqual(child.command, "/usr/bin/clang")
        XCTAssertEqual(child.startTime, 0.5)
        XCTAssertEqual(child.endTime, 2.0)
    }

    func testMultipleChildren_allAttachedToParent() {
        let events: [ProcessEvent] = [
            .init(type: .exec, pid: 10, ppid: 1,  timestamp: 0.0, command: "/make", args: [], cwd: "/"),
            .init(type: .fork, pid: 11, ppid: 10, timestamp: 0.1, command: "/cc",   args: ["a.c"], cwd: "/"),
            .init(type: .fork, pid: 12, ppid: 10, timestamp: 0.2, command: "/cc",   args: ["b.c"], cwd: "/"),
            .init(type: .fork, pid: 13, ppid: 10, timestamp: 0.3, command: "/cc",   args: ["c.c"], cwd: "/"),
            .init(type: .exit, pid: 11, ppid: 10, timestamp: 1.0, command: "/cc",   args: [], cwd: "/", exitCode: 0),
            .init(type: .exit, pid: 12, ppid: 10, timestamp: 1.1, command: "/cc",   args: [], cwd: "/", exitCode: 0),
            .init(type: .exit, pid: 13, ppid: 10, timestamp: 1.2, command: "/cc",   args: [], cwd: "/", exitCode: 0),
            .init(type: .exit, pid: 10, ppid: 1,  timestamp: 1.5, command: "/make", args: [], cwd: "/", exitCode: 0),
        ]
        let root = TreeBuilder.buildTree(from: events, rootPID: 10)
        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(Set(root.children.map(\.id)), [11, 12, 13])
    }

    func testExecAfterFork_updatesCommand() {
        // On macOS, fork() creates a process with the parent's command,
        // then exec() replaces it with the real command.
        let events: [ProcessEvent] = [
            .init(type: .exec, pid: 50, ppid: 1,  timestamp: 0.0, command: "/make",  args: [], cwd: "/"),
            .init(type: .fork, pid: 51, ppid: 50, timestamp: 0.1, command: "/make",  args: [], cwd: "/"),
            .init(type: .exec, pid: 51, ppid: 50, timestamp: 0.1, command: "/clang", args: ["-c", "x.c"], cwd: "/"),
            .init(type: .exit, pid: 51, ppid: 50, timestamp: 1.0, command: "/clang", args: [], cwd: "/", exitCode: 0),
            .init(type: .exit, pid: 50, ppid: 1,  timestamp: 1.2, command: "/make",  args: [], cwd: "/", exitCode: 0),
        ]
        let root = TreeBuilder.buildTree(from: events, rootPID: 50)
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.children[0].command, "/clang")
        XCTAssertEqual(root.children[0].args, ["-c", "x.c"])
    }

    func testProcessWithoutExitEvent_hasNilEndTime() {
        // Daemon crash or truncated capture; process endTime should be nil
        let events: [ProcessEvent] = [
            .init(type: .exec, pid: 99, ppid: 1, timestamp: 0.0, command: "/build", args: [], cwd: "/"),
        ]
        let root = TreeBuilder.buildTree(from: events, rootPID: 99)
        XCTAssertNil(root.endTime)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TreeBuilderTests 2>&1 | tail -20`
Expected: Compile error — `TreeBuilder` not found

- [ ] **Step 3: Implement TreeBuilder**

```swift
// Sources/WTFCore/TreeBuilder.swift
import Foundation

public enum TreeBuilder {

    /// Build a process tree from a flat list of ESF events.
    /// - Parameters:
    ///   - events: All captured events, in any order.
    ///   - rootPID: The PID of the top-level build command.
    /// - Returns: The root ProcessNode with fully nested children.
    public static func buildTree(from events: [ProcessEvent], rootPID: Int) -> ProcessNode {
        // Pass 1: build a mutable node map keyed by PID
        var nodes: [Int: ProcessNode] = [:]

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.type {
            case .fork, .exec:
                if var existing = nodes[event.pid] {
                    // exec after fork: update command + args
                    existing.command = event.command
                    existing.args = event.args
                    nodes[event.pid] = existing
                } else {
                    nodes[event.pid] = ProcessNode(
                        pid: event.pid,
                        command: event.command,
                        args: event.args,
                        cwd: event.cwd,
                        startTime: event.timestamp
                    )
                }
            case .exit:
                if var node = nodes[event.pid] {
                    node.endTime = event.timestamp
                    node.exitCode = event.exitCode
                    nodes[event.pid] = node
                }
            }
        }

        // Pass 2: wire parent–child relationships, collecting all child PIDs
        var childPIDs = Set<Int>()
        for event in events where event.type == .fork || event.type == .exec {
            guard event.pid != rootPID, nodes[event.ppid] != nil else { continue }
            childPIDs.insert(event.pid)
        }

        // Pass 3: for each node, collect its children and attach recursively
        func attachChildren(to pid: Int) -> ProcessNode {
            var node = nodes[pid] ?? ProcessNode(pid: pid, command: "unknown", startTime: 0)
            let directChildPIDs = events
                .filter { ($0.type == .fork || $0.type == .exec) && $0.ppid == pid && $0.pid != pid }
                .map(\.pid)
            let uniqueChildPIDs = Array(Set(directChildPIDs))
            node.children = uniqueChildPIDs.map { attachChildren(to: $0) }
                .sorted { $0.startTime < $1.startTime }
            return node
        }

        return attachChildren(to: rootPID)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TreeBuilderTests 2>&1 | tail -20`
Expected: `Test Suite 'TreeBuilderTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/WTFCore/TreeBuilder.swift Tests/WTFCoreTests/TreeBuilderTests.swift
git commit -m "feat(WTFCore): add TreeBuilder with full test coverage"
```

---

### Task 4: ParallelismAnalyzer

**Files:**
- Create: `Sources/WTFCore/ParallelismAnalyzer.swift`
- Create: `Tests/WTFCoreTests/ParallelismAnalyzerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WTFCoreTests/ParallelismAnalyzerTests.swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ParallelismAnalyzerTests 2>&1 | tail -10`
Expected: Compile error — `ParallelismAnalyzer` not found

- [ ] **Step 3: Implement ParallelismAnalyzer**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ParallelismAnalyzerTests 2>&1 | tail -10`
Expected: `Test Suite 'ParallelismAnalyzerTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/WTFCore/ParallelismAnalyzer.swift Tests/WTFCoreTests/ParallelismAnalyzerTests.swift
git commit -m "feat(WTFCore): add ParallelismAnalyzer with test coverage"
```

---

### Task 5: GapDetector

**Files:**
- Create: `Sources/WTFCore/GapDetector.swift`
- Create: `Tests/WTFCoreTests/GapDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GapDetectorTests 2>&1 | tail -10`
Expected: Compile error — `GapDetector` not found

- [ ] **Step 3: Implement GapDetector**

```swift
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
        // Consider all processes with known end times
        let processes = timeline.allProcesses.filter { $0.endTime != nil }
        guard !processes.isEmpty else { return [] }

        // Collect all (start, end) intervals sorted by start time
        let intervals = processes
            .compactMap { p -> (TimeInterval, TimeInterval, ProcessNode)? in
                guard let end = p.endTime else { return nil }
                return (p.startTime, end, p)
            }
            .sorted { $0.0 < $1.0 }

        // Merge overlapping intervals to find continuous "busy" spans
        var mergedIntervals: [(start: TimeInterval, end: TimeInterval)] = []
        for (start, end, _) in intervals {
            if var last = mergedIntervals.last, start <= last.end {
                if end > last.end {
                    mergedIntervals[mergedIntervals.count - 1].end = end
                }
            } else {
                mergedIntervals.append((start, end))
            }
        }

        // Gaps are the spaces between merged intervals
        var gaps: [GapReport] = []
        for i in 0..<(mergedIntervals.count - 1) {
            let gapStart = mergedIntervals[i].end
            let gapEnd = mergedIntervals[i + 1].start
            let duration = gapEnd - gapStart
            guard duration >= threshold else { continue }

            // Find the process that ended most recently before the gap
            let preceding = processes
                .filter { ($0.endTime ?? 0) <= gapStart }
                .max { ($0.endTime ?? 0) < ($1.endTime ?? 0) }

            // Find the process that starts next after the gap
            let following = processes
                .filter { $0.startTime >= gapEnd }
                .min { $0.startTime < $1.startTime }

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GapDetectorTests 2>&1 | tail -10`
Expected: `Test Suite 'GapDetectorTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/WTFCore/GapDetector.swift Tests/WTFCoreTests/GapDetectorTests.swift
git commit -m "feat(WTFCore): add GapDetector with test coverage"
```

---

### Task 6: CriticalPathFinder

**Files:**
- Create: `Sources/WTFCore/CriticalPathFinder.swift`
- Create: `Tests/WTFCoreTests/CriticalPathFinderTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CriticalPathFinderTests 2>&1 | tail -10`
Expected: Compile error — `CriticalPathFinder` not found

- [ ] **Step 3: Implement CriticalPathFinder**

```swift
// Sources/WTFCore/CriticalPathFinder.swift
import Foundation

public enum CriticalPathFinder {

    /// Find the longest-duration dependency chain from root to leaf.
    /// - Parameter root: The root ProcessNode of the tree.
    /// - Returns: Array of ProcessNodes from root → critical leaf, ordered top-down.
    public static func findCriticalPath(_ root: ProcessNode) -> [ProcessNode] {
        return longestPath(root)
    }

    // Returns [root, ..., deepest node on critical path]
    private static func longestPath(_ node: ProcessNode) -> [ProcessNode] {
        guard !node.children.isEmpty else { return [node] }

        // Find the child whose subtree has the greatest total duration
        let childPaths = node.children.map { longestPath($0) }
        let longestChild = childPaths.max { pathDuration($0) < pathDuration($1) } ?? []

        return [node] + longestChild
    }

    private static func pathDuration(_ path: [ProcessNode]) -> TimeInterval {
        guard let first = path.first, let last = path.last else { return 0 }
        let end = last.endTime ?? last.startTime
        return end - first.startTime
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CriticalPathFinderTests 2>&1 | tail -10`
Expected: `Test Suite 'CriticalPathFinderTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/WTFCore/CriticalPathFinder.swift Tests/WTFCoreTests/CriticalPathFinderTests.swift
git commit -m "feat(WTFCore): add CriticalPathFinder with test coverage"
```

---

### Task 7: SuggestionEngine

**Files:**
- Create: `Sources/WTFCore/SuggestionEngine.swift`
- Create: `Tests/WTFCoreTests/SuggestionEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SuggestionEngineTests 2>&1 | tail -10`
Expected: Compile error — `SuggestionEngine` not found

- [ ] **Step 3: Implement SuggestionEngine**

```swift
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
```

- [ ] **Step 4: Run all WTFCore tests to verify everything passes**

Run: `swift test 2>&1 | tail -20`
Expected: All test suites pass, `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/WTFCore/SuggestionEngine.swift Tests/WTFCoreTests/SuggestionEngineTests.swift
git commit -m "feat(WTFCore): add SuggestionEngine — completes analysis engine phase"
```

---

## Phase 3: Xcode Project Setup

### Task 8: Create Xcode project with xcodegen

**Files:**
- Create: `project.yml`
- Create: `WTFDaemon/main.swift` (stub)
- Create: `WTFDaemon/WTFDaemon.entitlements`
- Create: `WTFApp/WhatTheForkApp.swift` (stub)
- Create: `WTFApp/WhatTheFork.entitlements`
- Create: `wtf/main.swift` (stub)

- [ ] **Step 1: Install xcodegen if not present**

Run: `which xcodegen || brew install xcodegen`
Expected: path to xcodegen binary

- [ ] **Step 2: Create project.yml**

```yaml
name: WhatTheFork
options:
  bundleIdPrefix: com.whatthefork
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

packages:
  WTFCore:
    path: .

targets:

  WhatTheFork:
    type: application
    platform: macOS
    sources:
      - path: WTFApp
    dependencies:
      - package: WTFCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.whatthefork.app
        SWIFT_VERSION: 5.9
        MACOSX_DEPLOYMENT_TARGET: 13.0
        CODE_SIGN_ENTITLEMENTS: WTFApp/WhatTheFork.entitlements
    entitlements:
      path: WTFApp/WhatTheFork.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.automation.apple-events: true

  WTFDaemon:
    type: tool
    platform: macOS
    sources:
      - path: WTFDaemon
    dependencies:
      - package: WTFCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.whatthefork.daemon
        SWIFT_VERSION: 5.9
        MACOSX_DEPLOYMENT_TARGET: 13.0
        CODE_SIGN_ENTITLEMENTS: WTFDaemon/WTFDaemon.entitlements
    entitlements:
      path: WTFDaemon/WTFDaemon.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.developer.endpoint-security.client: true

  wtf:
    type: tool
    platform: macOS
    sources:
      - path: wtf
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.whatthefork.cli
        SWIFT_VERSION: 5.9
        MACOSX_DEPLOYMENT_TARGET: 13.0
```

- [ ] **Step 3: Create stub source files so xcodegen has something to find**

```bash
mkdir -p WTFDaemon WTFApp/Models WTFApp/Views WTFApp/Helpers wtf
```

```swift
// WTFDaemon/main.swift
import Foundation
print("WTFDaemon starting...")
```

```swift
// WTFApp/WhatTheForkApp.swift
import SwiftUI

@main
struct WhatTheForkApp: App {
    var body: some Scene {
        WindowGroup {
            Text("What the Fork")
        }
    }
}
```

```swift
// wtf/main.swift
import Foundation
print("wtf: usage: wtf <build-command> [args...]")
```

- [ ] **Step 4: Create entitlements files**

```xml
<!-- WTFDaemon/WTFDaemon.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.endpoint-security.client</key>
    <true/>
</dict>
</plist>
```

```xml
<!-- WTFApp/WhatTheFork.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Generate the Xcode project**

Run: `xcodegen generate`
Expected: `✅ Done` with `WhatTheFork.xcodeproj` created

- [ ] **Step 6: Verify the project builds from command line**

Run: `xcodebuild -project WhatTheFork.xcodeproj -scheme wtf -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Add xcodeproj to .gitignore and commit the rest**

```bash
cat >> .gitignore << 'EOF'
*.xcuserstate
xcuserdata/
DerivedData/
EOF
git add project.yml WTFDaemon/ WTFApp/ wtf/ .gitignore
git commit -m "chore: add xcodegen config + Xcode project stubs for daemon, app, CLI"
```

---

## Phase 4: ESF Daemon

> ⚠️ **ESF Note:** The `com.apple.developer.endpoint-security.client` entitlement requires explicit Apple approval for distribution. For local development, you can run the daemon as root on a machine/VM with SIP disabled (`csrutil disable` in Recovery Mode) — ESF will work without the entitlement. The daemon code is written correctly for production entitlement use; this only affects signing.

### Task 9: ESFClient — subscribe to fork/exec/exit events

**Files:**
- Create: `WTFDaemon/ESFClient.swift`

Note: ESFClient cannot be unit tested without root + ESF entitlement. It is tested manually in Task 16. The design ensures all data transformation logic lives in testable WTFCore instead.

- [ ] **Step 1: Create ESFClient.swift**

```swift
// WTFDaemon/ESFClient.swift
import Foundation
import EndpointSecurity

/// Subscribes to ESF process events and calls the handler for each event.
/// Must run as root with the `com.apple.developer.endpoint-security.client` entitlement.
final class ESFClient {
    private var client: OpaquePointer?
    private let rootPID: pid_t
    private let onEvent: (ProcessEventData) -> Void

    struct ProcessEventData {
        let type: String         // "fork" | "exec" | "exit"
        let pid: Int
        let ppid: Int
        let timestamp: TimeInterval
        let command: String
        let args: [String]
        let cwd: String
        let exitCode: Int?
    }

    init(rootPID: pid_t, onEvent: @escaping (ProcessEventData) -> Void) {
        self.rootPID = rootPID
        self.onEvent = onEvent
    }

    func start() throws {
        let result = es_new_client(&client) { [weak self] _, message in
            self?.handleMessage(message)
        }

        guard result == ES_NEW_CLIENT_RESULT_SUCCESS else {
            throw ESFError.clientCreationFailed(result)
        }

        let events: [es_event_type_t] = [
            ES_EVENT_TYPE_NOTIFY_FORK,
            ES_EVENT_TYPE_NOTIFY_EXEC,
            ES_EVENT_TYPE_NOTIFY_EXIT,
        ]
        es_subscribe(client!, events, UInt32(events.count))
    }

    func stop() {
        if let c = client {
            es_delete_client(c)
            client = nil
        }
    }

    private func handleMessage(_ message: UnsafePointer<es_message_t>) {
        let msg = message.pointee
        let pid = audit_token_to_pid(msg.process.pointee.audit_token)
        let ppid = msg.process.pointee.ppid

        // Only observe descendants of rootPID
        guard isDescendant(pid: pid) || pid == rootPID else { return }

        let timestamp = TimeInterval(msg.time.tv_sec) + TimeInterval(msg.time.tv_nsec) / 1_000_000_000

        switch msg.event_type {
        case ES_EVENT_TYPE_NOTIFY_FORK:
            let childPID = audit_token_to_pid(msg.event.fork.child.pointee.audit_token)
            let parentCommand = commandPath(from: msg.process.pointee)
            onEvent(ProcessEventData(
                type: "fork",
                pid: Int(childPID),
                ppid: Int(pid),
                timestamp: timestamp,
                command: parentCommand,
                args: [],
                cwd: cwdPath(from: msg.process.pointee),
                exitCode: nil
            ))

        case ES_EVENT_TYPE_NOTIFY_EXEC:
            let execPID = audit_token_to_pid(msg.process.pointee.audit_token)
            let execEvent = msg.event.exec
            let target = execEvent.target.pointee
            let command = commandPath(from: target)
            let args = execArgs(from: execEvent)
            onEvent(ProcessEventData(
                type: "exec",
                pid: Int(execPID),
                ppid: Int(ppid),
                timestamp: timestamp,
                command: command,
                args: args,
                cwd: cwdPath(from: target),
                exitCode: nil
            ))

        case ES_EVENT_TYPE_NOTIFY_EXIT:
            onEvent(ProcessEventData(
                type: "exit",
                pid: Int(pid),
                ppid: Int(ppid),
                timestamp: timestamp,
                command: commandPath(from: msg.process.pointee),
                args: [],
                cwd: "",
                exitCode: Int(msg.event.exit.stat)
            ))

        default:
            break
        }
    }

    // Walks up the process tree to check if `pid` is a descendant of rootPID.
    // This is a best-effort heuristic using ppid — sufficient for typical build tools.
    private var trackedPIDs: Set<pid_t> = []
    private func isDescendant(pid: pid_t) -> Bool {
        return trackedPIDs.contains(pid)
    }

    // Call this when a fork event arrives to register the child.
    func registerChild(pid: pid_t) {
        trackedPIDs.insert(pid)
    }

    private func commandPath(from process: es_process_t) -> String {
        let pathPtr = process.executable.pointee.path
        return String(cString: pathPtr.data)
    }

    private func cwdPath(from process: es_process_t) -> String {
        guard let cwdPtr = process.cwd?.pointee else { return "" }
        return String(cString: cwdPtr.path.data)
    }

    private func execArgs(from event: es_event_exec_t) -> [String] {
        let count = es_exec_arg_count(&event)
        return (0..<count).compactMap { i in
            guard let token = es_exec_arg(&event, i) else { return nil }
            return String(cString: token.data)
        }
    }
}

enum ESFError: Error {
    case clientCreationFailed(es_new_client_result_t)
}
```

- [ ] **Step 2: Verify daemon target compiles**

Run: `xcodebuild -project WhatTheFork.xcodeproj -scheme WTFDaemon -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WTFDaemon/ESFClient.swift
git commit -m "feat(daemon): add ESFClient for Endpoint Security Framework integration"
```

---

### Task 10: XPCEventServer — stream events from daemon to app

**Files:**
- Create: `WTFDaemon/WTFXPCProtocol.swift`
- Create: `WTFDaemon/XPCEventServer.swift`
- Modify: `WTFDaemon/main.swift`

- [ ] **Step 1: Create the shared XPC protocol**

This protocol is defined in the daemon but must be duplicated in the app (or extracted to a shared framework). For now, copy it to both targets.

```swift
// WTFDaemon/WTFXPCProtocol.swift
import Foundation

/// The XPC protocol the daemon exposes to the app.
@objc protocol WTFDaemonXPCProtocol {
    /// Start monitoring descendants of the given PID for this session.
    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void)
    /// Register a listener for events in the given session.
    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void)
}
```

- [ ] **Step 2: Create XPCEventServer.swift**

```swift
// WTFDaemon/XPCEventServer.swift
import Foundation

/// NSXPCListener delegate that accepts connections and serves event streams.
final class XPCEventServer: NSObject, NSXPCListenerDelegate {
    static let serviceName = "com.whatthefork.daemon"

    private var activeSessions: [String: ESFClient] = [:]
    private var pendingReplies: [String: [(NSData?) -> Void]] = [:]
    private let queue = DispatchQueue(label: "com.whatthefork.daemon.events", qos: .userInteractive)

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        connection.exportedObject = XPCSessionHandler(server: self)
        connection.resume()
        return true
    }

    func startSession(id: String, rootPID: Int32) {
        let client = ESFClient(rootPID: rootPID) { [weak self] event in
            self?.broadcastEvent(event, sessionID: id)
        }
        activeSessions[id] = client
        try? client.start()
    }

    func addSubscriber(sessionID: String, reply: @escaping (NSData?) -> Void) {
        pendingReplies[sessionID, default: []].append(reply)
    }

    private func broadcastEvent(_ event: ESFClient.ProcessEventData, sessionID: String) {
        guard let replies = pendingReplies[sessionID], !replies.isEmpty else { return }
        let dict: [String: Any] = [
            "type": event.type,
            "pid": event.pid,
            "ppid": event.ppid,
            "timestamp": event.timestamp,
            "command": event.command,
            "args": event.args,
            "cwd": event.cwd,
            "exit_code": event.exitCode as Any,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let nsData = data as NSData
        // Send to first waiting subscriber, rotate queue
        let reply = pendingReplies[sessionID]!.removeFirst()
        reply(nsData)
    }
}

/// The exported XPC object — one per connection.
final class XPCSessionHandler: NSObject, WTFDaemonXPCProtocol {
    private weak var server: XPCEventServer?

    init(server: XPCEventServer) {
        self.server = server
    }

    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void) {
        server?.startSession(id: id, rootPID: rootPID)
        reply(true)
    }

    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void) {
        server?.addSubscriber(sessionID: id, reply: reply)
    }
}
```

- [ ] **Step 3: Update main.swift to start the XPC listener**

```swift
// WTFDaemon/main.swift
import Foundation

let server = XPCEventServer()
let listener = NSXPCListener(machServiceName: XPCEventServer.serviceName)
listener.delegate = server
listener.resume()

print("WTFDaemon: XPC listener started on \(XPCEventServer.serviceName)")
RunLoop.main.run()
```

- [ ] **Step 4: Verify daemon target compiles**

Run: `xcodebuild -project WhatTheFork.xcodeproj -scheme WTFDaemon -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add WTFDaemon/
git commit -m "feat(daemon): add XPCEventServer — daemon now accepts XPC connections and streams events"
```

---

## Phase 5: CLI Tool

### Task 11: CLI — BuildRunner and AppLauncher

**Files:**
- Create: `wtf/BuildRunner.swift`
- Create: `wtf/DaemonLauncher.swift`
- Create: `wtf/AppLauncher.swift`
- Modify: `wtf/main.swift`

- [ ] **Step 1: Create BuildRunner.swift**

```swift
// wtf/BuildRunner.swift
import Foundation

/// Launches a build command as a child process and returns its PID.
enum BuildRunner {
    /// Fork the given command and arguments as a child process.
    /// Returns the child PID immediately (does not wait for completion).
    static func launch(command: String, args: [String]) throws -> pid_t {
        // Resolve full path if not absolute
        let fullPath: String
        if command.hasPrefix("/") {
            fullPath = command
        } else {
            fullPath = try resolveInPATH(command)
        }

        var pid: pid_t = 0
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)

        var argv = ([fullPath] + args).map { strdup($0) }
        argv.append(nil)

        let envp = ProcessInfo.processInfo.environment
            .map { "\($0.key)=\($0.value)" }
            .map { strdup($0) }
        var envpArr = envp
        envpArr.append(nil)

        let ret = posix_spawn(&pid, fullPath, &fileActions, nil, argv, envpArr)

        argv.compactMap { $0 }.forEach { free($0) }
        envp.compactMap { $0 }.forEach { free($0) }
        posix_spawn_file_actions_destroy(&fileActions)

        guard ret == 0 else {
            throw BuildRunnerError.spawnFailed(errno: ret)
        }
        return pid
    }

    private static func resolveInPATH(_ command: String) throws -> String {
        let paths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map(String.init) ?? []
        for dir in paths {
            let full = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: full) {
                return full
            }
        }
        throw BuildRunnerError.commandNotFound(command)
    }
}

enum BuildRunnerError: Error, LocalizedError {
    case commandNotFound(String)
    case spawnFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let cmd): return "Command not found: \(cmd)"
        case .spawnFailed(let e): return "posix_spawn failed with errno \(e)"
        }
    }
}
```

- [ ] **Step 2: Create DaemonLauncher.swift**

```swift
// wtf/DaemonLauncher.swift
import Foundation

/// Connects to the WTFDaemon XPC service and registers a monitoring session.
enum DaemonLauncher {

    static func startSession(id: String, rootPID: pid_t) throws {
        let connection = NSXPCConnection(machServiceName: "com.whatthefork.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            fputs("wtf: daemon connection error: \(error)\n", stderr)
        } as? WTFDaemonXPCProtocol

        let sema = DispatchSemaphore(value: 0)
        proxy?.startSession(id: id, rootPID: Int32(rootPID)) { success in
            if !success {
                fputs("wtf: daemon failed to start session\n", stderr)
            }
            sema.signal()
        }
        sema.wait()
    }
}

// Duplicate protocol declaration for CLI target (no shared framework yet)
@objc protocol WTFDaemonXPCProtocol {
    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void)
    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void)
}
```

- [ ] **Step 3: Create AppLauncher.swift**

```swift
// wtf/AppLauncher.swift
import Foundation
import AppKit

/// Opens the WhatTheFork app and passes the session ID via URL scheme.
enum AppLauncher {
    static let urlScheme = "whatthefork"

    /// Opens the app with the session ID encoded in a custom URL.
    /// URL format: whatthefork://session/<id>
    static func openApp(sessionID: String) {
        let urlString = "\(urlScheme)://session/\(sessionID)"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Update main.swift — full CLI entry point**

```swift
// wtf/main.swift
import Foundation

// Parse arguments
let args = CommandLine.arguments.dropFirst()

guard !args.isEmpty else {
    fputs("Usage: wtf <command> [args...]\n", stderr)
    exit(1)
}

let command = String(args[0])
let commandArgs = Array(args.dropFirst())

let sessionID = UUID().uuidString

do {
    // 1. Launch the build
    let buildPID = try BuildRunner.launch(command: command, args: commandArgs)
    print("wtf: launched \(command) as PID \(buildPID), session \(sessionID)")

    // 2. Tell the daemon to start monitoring
    try DaemonLauncher.startSession(id: sessionID, rootPID: buildPID)

    // 3. Open the app
    AppLauncher.openApp(sessionID: sessionID)

    // 4. Wait for build to finish
    var status: Int32 = 0
    waitpid(buildPID, &status, 0)
    let exitCode = Int(WEXITSTATUS(status))
    print("wtf: build completed with exit code \(exitCode)")

} catch {
    fputs("wtf: \(error.localizedDescription)\n", stderr)
    exit(1)
}
```

- [ ] **Step 5: Verify CLI target compiles**

Run: `xcodebuild -project WhatTheFork.xcodeproj -scheme wtf -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add wtf/
git commit -m "feat(cli): add wtf CLI — launches builds, connects to daemon, opens app"
```

---

## Phase 6: SwiftUI App

### Task 12: ProcessClassifier and BuildSession model

**Files:**
- Create: `WTFApp/Helpers/ProcessClassifier.swift`
- Create: `WTFApp/Models/BuildSession.swift`
- Create: `WTFApp/Models/XPCEventClient.swift`

- [ ] **Step 1: Create ProcessClassifier.swift**

```swift
// WTFApp/Helpers/ProcessClassifier.swift
import SwiftUI

/// Maps a process command name to a visual category for color coding.
enum ProcessCategory {
    case buildSystem
    case compiler
    case linker
    case shell
    case other

    var color: Color {
        switch self {
        case .buildSystem: return .blue
        case .compiler:    return .green
        case .linker:      return Color(red: 0.9, green: 0.7, blue: 0.1)  // gold/yellow
        case .shell:       return .gray
        case .other:       return Color(white: 0.75)
        }
    }

    var label: String {
        switch self {
        case .buildSystem: return "Build System"
        case .compiler:    return "Compiler"
        case .linker:      return "Linker"
        case .shell:       return "Shell"
        case .other:       return "Other"
        }
    }
}

enum ProcessClassifier {
    private static let buildSystems: Set<String> = [
        "make", "gmake", "cmake", "ninja", "cargo", "gradle", "bazel",
        "xcodebuild", "swift", "npm", "yarn", "pnpm", "mvn", "ant", "sbt", "buck2"
    ]
    private static let compilers: Set<String> = [
        "clang", "clang++", "gcc", "g++", "swiftc", "rustc", "cc", "c++",
        "javac", "kotlinc", "scalac", "tsc", "go"
    ]
    private static let linkers: Set<String> = [
        "ld", "lld", "gold", "mold", "link"
    ]
    private static let shells: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "csh"
    ]

    static func classify(_ node: ProcessNode) -> ProcessCategory {
        let name = node.commandName.lowercased()
        if buildSystems.contains(name) { return .buildSystem }
        if compilers.contains(name)    { return .compiler }
        if linkers.contains(name)      { return .linker }
        if shells.contains(name)       { return .shell }
        return .other
    }
}
```

- [ ] **Step 2: Create XPCEventClient.swift**

```swift
// WTFApp/Models/XPCEventClient.swift
import Foundation
import WTFCore

// Duplicate protocol — matches WTFDaemon/WTFXPCProtocol.swift
@objc protocol WTFDaemonXPCProtocol {
    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void)
    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void)
}

/// Connects to the WTFDaemon XPC service and converts raw JSON events into ProcessEvents.
final class XPCEventClient {
    private let sessionID: String
    private var connection: NSXPCConnection?
    var onEvent: ((ProcessEvent) -> Void)?
    var onSessionComplete: (() -> Void)?

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func connect() {
        let conn = NSXPCConnection(machServiceName: "com.whatthefork.daemon")
        conn.remoteObjectInterface = NSXPCInterface(with: WTFDaemonXPCProtocol.self)
        conn.resume()
        self.connection = conn
        pollForEvents()
    }

    private func pollForEvents() {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ [weak self] error in
            DispatchQueue.main.async { self?.onSessionComplete?() }
        }) as? WTFDaemonXPCProtocol else { return }

        proxy.subscribeToSession(id: sessionID) { [weak self] data in
            guard let self else { return }
            if let data = data as Data?, let event = self.decodeEvent(data) {
                DispatchQueue.main.async { self.onEvent?(event) }
                // Immediately re-subscribe for the next event (long-poll pattern)
                self.pollForEvents()
            } else {
                DispatchQueue.main.async { self.onSessionComplete?() }
            }
        }
    }

    private func decodeEvent(_ data: Data) -> ProcessEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let typeStr = json["type"] as? String,
            let pid = json["pid"] as? Int,
            let ppid = json["ppid"] as? Int,
            let timestamp = json["timestamp"] as? TimeInterval,
            let command = json["command"] as? String
        else { return nil }

        let eventType: ProcessEvent.EventType
        switch typeStr {
        case "fork":  eventType = .fork
        case "exec":  eventType = .exec
        case "exit":  eventType = .exit
        default:      return nil
        }

        return ProcessEvent(
            type: eventType,
            pid: pid,
            ppid: ppid,
            timestamp: timestamp,
            command: command,
            args: json["args"] as? [String] ?? [],
            cwd: json["cwd"] as? String ?? "",
            exitCode: json["exit_code"] as? Int
        )
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
```

- [ ] **Step 3: Create BuildSession.swift**

```swift
// WTFApp/Models/BuildSession.swift
import Foundation
import Combine
import WTFCore

/// Top-level state object that drives all views. Receives events from the XPC client,
/// builds the live process tree, and computes analysis when the build completes.
final class BuildSession: ObservableObject {
    enum State {
        case idle
        case capturing
        case complete
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var timeline: Timeline?
    @Published var analysis: BuildAnalysis?
    @Published var liveEvents: [ProcessEvent] = []
    @Published private(set) var rootPID: Int?

    private var xpcClient: XPCEventClient?

    /// Start receiving events for a session.
    func startCapture(sessionID: String, rootPID: Int) {
        self.rootPID = rootPID
        state = .capturing
        liveEvents = []

        let client = XPCEventClient(sessionID: sessionID)
        client.onEvent = { [weak self] event in
            self?.liveEvents.append(event)
        }
        client.onSessionComplete = { [weak self] in
            self?.finalize()
        }
        xpcClient = client
        client.connect()
    }

    private func finalize() {
        guard let rootPID, !liveEvents.isEmpty else {
            state = .failed("No events received")
            return
        }

        let root = TreeBuilder.buildTree(from: liveEvents, rootPID: rootPID)
        guard let rootEnd = root.endTime else {
            state = .failed("Root process did not exit cleanly")
            return
        }

        let tl = Timeline(
            rootNode: root,
            startTime: root.startTime,
            totalDuration: rootEnd - root.startTime
        )

        let metrics = ParallelismAnalyzer.analyzeParallelism(tl)
        let gaps = GapDetector.detectGaps(tl)
        let criticalPath = CriticalPathFinder.findCriticalPath(root)
        let buildAnalysis = BuildAnalysis(
            parallelismScore: metrics.score,
            gaps: gaps,
            criticalPath: criticalPath,
            suggestions: []
        )
        let suggestions = SuggestionEngine.generateSuggestions(tl, buildAnalysis)
        let finalAnalysis = BuildAnalysis(
            parallelismScore: metrics.score,
            gaps: gaps,
            criticalPath: criticalPath,
            suggestions: suggestions
        )

        timeline = tl
        analysis = finalAnalysis
        state = .complete
        xpcClient?.disconnect()
    }
}
```

- [ ] **Step 4: Verify app target compiles**

Run: `xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add WTFApp/
git commit -m "feat(app): add ProcessClassifier, XPCEventClient, BuildSession model"
```

---

### Task 13: TimelineView — scrollable canvas with nested process boxes

**Files:**
- Modify: `WTFApp/WhatTheForkApp.swift`
- Create: `WTFApp/Views/ContentView.swift`
- Create: `WTFApp/Views/ProcessBoxView.swift`
- Create: `WTFApp/Views/TimelineView.swift`

- [ ] **Step 1: Create ProcessBoxView.swift**

```swift
// WTFApp/Views/ProcessBoxView.swift
import SwiftUI
import WTFCore

/// A single colored box representing a process in the timeline.
struct ProcessBoxView: View {
    let node: ProcessNode
    let category: ProcessCategory
    let pixelsPerSecond: Double
    let isSelected: Bool
    let onSelect: () -> Void

    private var width: CGFloat {
        let dur = (node.endTime ?? node.startTime + 0.05) - node.startTime
        return max(CGFloat(dur * pixelsPerSecond), 4)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(category.color.opacity(isSelected ? 1.0 : 0.75))
            .frame(width: width, height: 22)
            .overlay(
                Text(node.commandName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 3),
                alignment: .leading
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .onTapGesture(perform: onSelect)
            .help("\(node.commandName) — \(formattedDuration)")
    }

    private var formattedDuration: String {
        guard let dur = node.duration else { return "running" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }
}
```

- [ ] **Step 2: Create TimelineView.swift**

```swift
// WTFApp/Views/TimelineView.swift
import SwiftUI
import WTFCore

/// Scrollable, zoomable canvas showing the full process tree as a horizontal timeline.
struct TimelineView: View {
    let timeline: Timeline
    @Binding var selectedNode: ProcessNode?
    @State private var pixelsPerSecond: Double = 100.0
    private let rowHeight: CGFloat = 28
    private let rowPadding: CGFloat = 4

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                // Background time ruler
                TimeRulerView(
                    totalDuration: timeline.totalDuration,
                    pixelsPerSecond: pixelsPerSecond
                )

                // Process tree rows
                VStack(alignment: .leading, spacing: rowPadding) {
                    nodeRow(timeline.rootNode, depth: 0)
                }
                .padding(.top, 24)  // below ruler
                .padding(.bottom, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .gesture(MagnifyGesture()
            .onChanged { value in
                pixelsPerSecond = max(10, min(2000, pixelsPerSecond * value.magnification))
            }
        )
        .onScrollGeometryChange(for: CGFloat.self) { geo in geo.contentSize.width } action: { _, _ in }
    }

    @ViewBuilder
    private func nodeRow(_ node: ProcessNode, depth: Int) -> some View {
        HStack(spacing: 0) {
            // Indent to show tree depth
            Spacer()
                .frame(width: CGFloat(depth) * 16)

            // Horizontal offset from build start
            Spacer()
                .frame(width: CGFloat((node.startTime - timeline.startTime) * pixelsPerSecond))

            ProcessBoxView(
                node: node,
                category: ProcessClassifier.classify(node),
                pixelsPerSecond: pixelsPerSecond,
                isSelected: selectedNode?.id == node.id,
                onSelect: { selectedNode = node }
            )

            Spacer()
        }
        .frame(height: rowHeight)

        ForEach(node.children) { child in
            nodeRow(child, depth: depth + 1)
        }
    }
}

/// Thin ruler showing time markers above the timeline.
struct TimeRulerView: View {
    let totalDuration: TimeInterval
    let pixelsPerSecond: Double

    var body: some View {
        Canvas { context, size in
            let step = tickStep(for: pixelsPerSecond)
            var t = 0.0
            while t <= totalDuration {
                let x = t * pixelsPerSecond
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 18))
                    p.addLine(to: CGPoint(x: x, y: 24))
                }
                context.stroke(path, with: .color(.secondary), lineWidth: 1)
                let label = t >= 1 ? String(format: "%.0fs", t) : String(format: "%.0fms", t * 1000)
                context.draw(Text(label).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x + 2, y: 9))
                t += step
            }
        }
        .frame(width: CGFloat(totalDuration * pixelsPerSecond + 80), height: 24)
    }

    private func tickStep(for pps: Double) -> TimeInterval {
        // Choose a tick interval that gives roughly 80-150px between ticks
        let targetInterval = 100.0 / pps
        let steps: [TimeInterval] = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60]
        return steps.min { abs($0 - targetInterval) < abs($1 - targetInterval) } ?? 1
    }
}
```

- [ ] **Step 3: Create ContentView.swift**

```swift
// WTFApp/Views/ContentView.swift
import SwiftUI
import WTFCore

struct ContentView: View {
    @StateObject private var session = BuildSession()
    @State private var selectedNode: ProcessNode?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            Group {
                switch session.state {
                case .idle:
                    idleView

                case .capturing:
                    if !session.liveEvents.isEmpty, let partialRoot = partialTimeline {
                        TimelineView(timeline: partialRoot, selectedNode: $selectedNode)
                    } else {
                        capturingView
                    }

                case .complete:
                    if let timeline = session.timeline {
                        VSplitView {
                            TimelineView(timeline: timeline, selectedNode: $selectedNode)
                                .frame(minHeight: 200)
                            bottomPanel
                                .frame(minHeight: 120, maxHeight: 300)
                        }
                    }

                case .failed(let msg):
                    errorView(msg)
                }
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
    }

    private var toolbarView: some View {
        HStack {
            Image(systemName: "fork.knife")
                .foregroundStyle(.secondary)
            Text("What the Fork")
                .font(.headline)
            Spacer()
            if case .complete = session.state, let analysis = session.analysis {
                Label(
                    String(format: "Parallelism: %.0f%%", analysis.parallelismScore * 100),
                    systemImage: "cpu"
                )
                .foregroundStyle(analysis.parallelismScore < 0.3 ? .red : .secondary)
                .font(.subheadline)
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Run a build with `wtf <command>` to visualize it here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capturingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Capturing build...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        HSplitView {
            ProcessDetailPanel(node: selectedNode)
                .frame(minWidth: 250)
            if let analysis = session.analysis {
                AnalysisPanel(analysis: analysis)
                    .frame(minWidth: 250)
            }
        }
    }

    // Build a partial timeline from live events for live preview
    private var partialTimeline: Timeline? {
        guard let rootPID = session.rootPID,
              let firstEvent = session.liveEvents.first else { return nil }
        let root = TreeBuilder.buildTree(from: session.liveEvents, rootPID: rootPID)
        let now = Date().timeIntervalSince1970
        let duration = now - firstEvent.timestamp
        return Timeline(rootNode: root, startTime: firstEvent.timestamp, totalDuration: max(duration, 0.1))
    }

    private func handleIncomingURL(_ url: URL) {
        // Expected: whatthefork://session/<sessionID>?rootPID=<pid>
        guard
            url.scheme == "whatthefork",
            url.host == "session",
            let sessionID = url.pathComponents.dropFirst().first,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let pidStr = components.queryItems?.first(where: { $0.name == "rootPID" })?.value,
            let rootPID = Int(pidStr)
        else { return }

        session.startCapture(sessionID: sessionID, rootPID: rootPID)
    }
}
```

- [ ] **Step 4: Update AppLauncher.swift in the CLI to include rootPID in the URL**

Edit `wtf/AppLauncher.swift` to include the root PID so the app knows which PID to use as the tree root:

```swift
// wtf/AppLauncher.swift
import Foundation
import AppKit

enum AppLauncher {
    static let urlScheme = "whatthefork"

    static func openApp(sessionID: String, rootPID: pid_t) {
        let urlString = "\(urlScheme)://session/\(sessionID)?rootPID=\(rootPID)"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

Edit `wtf/main.swift` line calling `AppLauncher.openApp` to pass rootPID:
```swift
    AppLauncher.openApp(sessionID: sessionID, rootPID: buildPID)
```

- [ ] **Step 5: Register URL scheme in app's Info.plist**

Add to project.yml under the `WhatTheFork` target's `info` section:

```yaml
  WhatTheFork:
    # ... existing config ...
    info:
      path: WTFApp/Info.plist
      properties:
        CFBundleURLTypes:
          - CFBundleURLSchemes:
              - whatthefork
            CFBundleURLName: com.whatthefork.app
```

Then regenerate: `xcodegen generate`

- [ ] **Step 6: Verify app compiles**

Run: `xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add WTFApp/Views/ wtf/ project.yml
git commit -m "feat(app): add TimelineView, ProcessBoxView, ContentView with URL scheme handling"
```

---

### Task 14: ProcessDetailPanel and AnalysisPanel

**Files:**
- Create: `WTFApp/Views/ProcessDetailPanel.swift`
- Create: `WTFApp/Views/AnalysisPanel.swift`

- [ ] **Step 1: Create ProcessDetailPanel.swift**

```swift
// WTFApp/Views/ProcessDetailPanel.swift
import SwiftUI
import WTFCore

struct ProcessDetailPanel: View {
    let node: ProcessNode?

    var body: some View {
        Group {
            if let node {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow("Command", value: node.command)

                        if !node.args.isEmpty {
                            detailRow("Arguments", value: node.args.joined(separator: " "))
                        }

                        detailRow("PID", value: "\(node.id)")
                        detailRow("Directory", value: node.cwd.isEmpty ? "—" : node.cwd)

                        if let duration = node.duration {
                            detailRow("Duration", value: duration >= 1
                                ? String(format: "%.3fs", duration)
                                : String(format: "%.0fms", duration * 1000))
                        } else {
                            detailRow("Duration", value: "Running…")
                        }

                        if let exitCode = node.exitCode {
                            detailRow("Exit Code", value: "\(exitCode)",
                                      valueColor: exitCode == 0 ? .green : .red)
                        }

                        detailRow("Children", value: "\(node.children.count)")
                    }
                    .padding(12)
                }
            } else {
                Text("Select a process to see details")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
    }
}
```

- [ ] **Step 2: Create AnalysisPanel.swift**

```swift
// WTFApp/Views/AnalysisPanel.swift
import SwiftUI
import WTFCore

struct AnalysisPanel: View {
    let analysis: BuildAnalysis
    @State private var isExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Parallelism score
                VStack(alignment: .leading, spacing: 4) {
                    Label("Parallelism", systemImage: "cpu")
                        .font(.headline)
                    ProgressView(value: analysis.parallelismScore)
                        .tint(scoreColor)
                    Text(String(format: "%.0f%% average CPU utilization", analysis.parallelismScore * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Gaps
                if !analysis.gaps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Idle Gaps", systemImage: "clock.badge.exclamationmark")
                            .font(.headline)
                        ForEach(analysis.gaps.indices, id: \.self) { i in
                            let gap = analysis.gaps[i]
                            HStack {
                                Image(systemName: "pause.circle")
                                    .foregroundStyle(.orange)
                                Text(String(format: "%.1fs gap after %@",
                                            gap.duration,
                                            gap.precedingProcess?.commandName ?? "unknown"))
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                // Suggestions
                if !analysis.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Suggestions", systemImage: "lightbulb")
                            .font(.headline)
                        ForEach(analysis.suggestions.indices, id: \.self) { i in
                            suggestionRow(analysis.suggestions[i])
                        }
                    }
                }

                if analysis.gaps.isEmpty && analysis.suggestions.isEmpty {
                    Label("No issues found!", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var scoreColor: Color {
        switch analysis.parallelismScore {
        case 0.6...: return .green
        case 0.3...: return .yellow
        default:     return .red
        }
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: suggestionIcon(suggestion.category))
                .foregroundStyle(.orange)
                .frame(width: 20)
            Text(suggestion.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func suggestionIcon(_ category: Suggestion.Category) -> String {
        switch category {
        case .noParallelism:          return "arrow.left.arrow.right"
        case .unnecessaryRepeatedCalls: return "repeat.circle"
        case .longGap:                return "clock.badge.exclamationmark"
        case .serialDependencies:     return "arrow.right"
        }
    }
}
```

- [ ] **Step 3: Verify full app compiles**

Run: `xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all unit tests**

Run: `swift test 2>&1 | tail -20`
Expected: All WTFCore tests pass.

- [ ] **Step 5: Commit**

```bash
git add WTFApp/Views/ProcessDetailPanel.swift WTFApp/Views/AnalysisPanel.swift
git commit -m "feat(app): add ProcessDetailPanel and AnalysisPanel — UI complete"
```

---

## Phase 7: Integration Testing + README

### Task 15: Integration test with fixture data

**Files:**
- Create: `Tests/WTFCoreTests/IntegrationTests.swift`
- Create: `Tests/WTFCoreTests/Fixtures/cargo_build_events.json`

- [ ] **Step 1: Create a realistic fixture event stream**

```bash
mkdir -p Tests/WTFCoreTests/Fixtures
```

```json
[
  {"type":"exec","pid":1000,"ppid":999,"timestamp":0.0,"command":"/usr/bin/cargo","args":["build"],"cwd":"/proj","exit_code":null},
  {"type":"fork","pid":1001,"ppid":1000,"timestamp":0.1,"command":"/usr/bin/rustc","args":["--crate-name","lib","src/lib.rs"],"cwd":"/proj","exit_code":null},
  {"type":"fork","pid":1002,"ppid":1000,"timestamp":0.1,"command":"/usr/bin/rustc","args":["--crate-name","dep","dep/src/lib.rs"],"cwd":"/proj","exit_code":null},
  {"type":"exit","pid":1002,"ppid":1000,"timestamp":2.5,"command":"/usr/bin/rustc","args":[],"cwd":"/proj","exit_code":0},
  {"type":"fork","pid":1003,"ppid":1000,"timestamp":2.5,"command":"/usr/bin/rustc","args":["--crate-name","main","src/main.rs"],"cwd":"/proj","exit_code":null},
  {"type":"exit","pid":1001,"ppid":1000,"timestamp":3.0,"command":"/usr/bin/rustc","args":[],"cwd":"/proj","exit_code":0},
  {"type":"exit","pid":1003,"ppid":1000,"timestamp":4.2,"command":"/usr/bin/rustc","args":[],"cwd":"/proj","exit_code":0},
  {"type":"fork","pid":1004,"ppid":1000,"timestamp":4.2,"command":"/usr/bin/ld","args":["-o","target/debug/proj"],"cwd":"/proj","exit_code":null},
  {"type":"exit","pid":1004,"ppid":1000,"timestamp":4.8,"command":"/usr/bin/ld","args":[],"cwd":"/proj","exit_code":0},
  {"type":"exit","pid":1000,"ppid":999,"timestamp":5.0,"command":"/usr/bin/cargo","args":[],"cwd":"/proj","exit_code":0}
]
```

- [ ] **Step 2: Write integration tests**

```swift
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
```

- [ ] **Step 3: Update Package.swift to include test resources**

```swift
// Package.swift — update the testTarget to include resources
.testTarget(
    name: "WTFCoreTests",
    dependencies: ["WTFCore"],
    path: "Tests/WTFCoreTests",
    resources: [.copy("Fixtures")]
)
```

- [ ] **Step 4: Run all tests including integration**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass including `IntegrationTests`

- [ ] **Step 5: Commit**

```bash
git add Tests/ Package.swift
git commit -m "test: add integration tests with cargo build fixture"
```

---

### Task 16: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
# What the Fork 🍴

A macOS-native tool that visualizes your build process as an interactive timeline, so you can spot slowdowns, serial bottlenecks, and wasted work.

Named after the `fork()` syscall.

## Usage

```bash
wtf make
wtf cargo build
wtf npm run build
wtf xcodebuild
```

Launches the app, which updates live as your build runs.

## How It Works

`wtf` uses Apple's [Endpoint Security Framework](https://developer.apple.com/documentation/endpointsecurity) to intercept `fork`, `exec`, and `exit` syscalls during your build, then reconstructs the full process tree and analyzes it for inefficiencies.

## Building

Requirements:
- macOS 13+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

```bash
git clone https://github.com/you/what-the-fork
cd what-the-fork
xcodegen generate
open WhatTheFork.xcodeproj
```

> **ESF Note:** The daemon requires the `com.apple.developer.endpoint-security.client` entitlement, which must be approved by Apple for distribution. For local development, you can run on a machine with SIP disabled.

## Running Tests

```bash
swift test
```

## Architecture

- `WTFCore/` — Pure Swift package: tree building, parallelism analysis, gap detection, suggestions
- `WTFDaemon/` — Privileged helper: ESF subscription, XPC event server
- `WTFApp/` — SwiftUI app: timeline visualization, analysis panels
- `wtf/` — CLI tool: launches builds, connects daemon and app

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage, architecture, and build instructions"
```

---

## Done

All phases complete. The project now has:
- ✅ Fully tested `WTFCore` analysis engine (tree building, parallelism, gaps, critical path, suggestions)
- ✅ ESF daemon that captures process lifecycle events via XPC
- ✅ `wtf` CLI tool that ties everything together
- ✅ SwiftUI app with live-updating timeline, process detail, and analysis panels
- ✅ Integration tests with a realistic fixture build
- ✅ README
