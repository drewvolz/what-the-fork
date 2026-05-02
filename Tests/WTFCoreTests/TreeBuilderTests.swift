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