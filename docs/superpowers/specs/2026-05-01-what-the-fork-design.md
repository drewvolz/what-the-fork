# What the Fork — macOS Native Version Design

**Date:** 2026-05-01  
**Author:** Drew (with Claude)  
**Status:** Approved

## Overview

A macOS-native rebuild of [What the Fork](https://danielchasehooper.com/posts/syscall-build-snooping/) by Daniel Chase Hooper. The tool captures process syscalls during a build and visualizes the full process tree as an interactive timeline — enabling developers to identify build inefficiencies (serial work that could be parallel, idle gaps, redundant steps, etc.).

Built from scratch using Swift, SwiftUI, and Apple's Endpoint Security Framework (ESF).

---

## Architecture

The system uses a three-tier modular design:

```
User: wtf make
   ↓
CLI tool (wtf) — launches build, starts capture daemon, opens/feeds app
   ↓
ESF Capture Daemon (privileged) — intercepts fork/exec/exit syscalls
   ↓
wtf-core Framework — builds process tree, computes analysis
   ↓
SwiftUI App — interactive timeline visualization + analysis panels
```

This separation allows:
- The CLI and daemon to work without the UI (scriptable, CI-friendly)
- The analysis framework to be tested independently
- The app to be a pure visualization/interaction layer

---

## Component 1: ESF Capture Daemon

A privileged helper tool that uses Apple's Endpoint Security Framework to observe process lifecycle events.

**Events captured:**
- `ES_EVENT_TYPE_NOTIFY_FORK` — process forked
- `ES_EVENT_TYPE_NOTIFY_EXEC` — process exec'd (command replaced)
- `ES_EVENT_TYPE_NOTIFY_EXIT` — process exited

**Output:** JSON-encoded event stream written to a Unix domain socket or pipe.

**Event schema:**
```json
{
  "type": "fork" | "exec" | "exit",
  "pid": 12345,
  "ppid": 12344,
  "timestamp": 1234567890.123456,
  "command": "/usr/bin/clang",
  "args": ["-O2", "main.c"],
  "cwd": "/Users/drew/myproject",
  "exit_code": 0
}
```

**Entitlements required:**
- `com.apple.developer.endpoint-security.client`
- Must run as root or with System Integrity Protection considerations
- Requires Full Disk Access (user prompt)

**Lifecycle:**
- Daemon is registered as a privileged helper tool via `SMAppService` (modern replacement for deprecated `SMJobBless`), launched on demand by the CLI
- Daemon scope-filters to only observe descendants of the root build PID (avoids capturing unrelated system processes)
- Daemon self-terminates when root build PID exits

---

## Component 2: wtf-core Framework

A pure Swift package (no UIKit/AppKit/SwiftUI dependencies) that consumes the event stream, builds the process tree, and performs analysis.

**Key types:**

```swift
struct ProcessEvent {
    enum EventType { case fork, exec, exit }
    let type: EventType
    let pid: Int
    let ppid: Int
    let timestamp: TimeInterval
    let command: String
    let args: [String]
    let cwd: String
    let exitCode: Int?
}

struct ProcessNode: Identifiable {
    let id: Int  // pid
    var command: String
    var args: [String]
    var cwd: String
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var children: [ProcessNode]
    var exitCode: Int?
}

struct Timeline {
    let rootNode: ProcessNode
    let totalDuration: TimeInterval
    let startTime: TimeInterval
}

struct BuildAnalysis {
    let parallelismScore: Double      // 0–1, avg CPU cores in use / total cores
    let gaps: [GapReport]             // idle periods > 100ms with no active processes
    let criticalPath: [ProcessNode]   // longest-duration dependency chain
    let suggestions: [Suggestion]     // actionable recommendations
}

struct GapReport {
    let startTime: TimeInterval
    let duration: TimeInterval
    let precedingProcess: ProcessNode?
    let followingProcess: ProcessNode?
}

struct Suggestion {
    enum Category { case noParallelism, unnecessaryRepeatedCalls, longGap, serialDependencies }
    let category: Category
    let description: String
    let relatedNodes: [ProcessNode]
}
```

**Key functions:**
- `buildTree(from events: [ProcessEvent]) -> ProcessNode` — constructs the process tree
- `analyzeParallelism(_ timeline: Timeline) -> ParallelismMetrics` — calculates CPU utilization at each point in time
- `detectGaps(_ timeline: Timeline, threshold: TimeInterval) -> [GapReport]` — finds idle periods
- `findCriticalPath(_ tree: ProcessNode) -> [ProcessNode]` — identifies the longest sequential chain
- `generateSuggestions(_ timeline: Timeline, _ analysis: BuildAnalysis) -> [Suggestion]` — pattern-matches known anti-patterns

---

## Component 3: CLI Tool (`wtf`)

A Swift command-line tool installed to `/usr/local/bin/wtf`.

**Usage:**
```
wtf <command> [args...]
wtf -x           # launches/builds frontmost Xcode project
```

**Behavior:**
1. Forks the given command as a child process
2. Launches the ESF daemon (with privilege escalation if needed) scoped to that child
3. Opens (or activates) the SwiftUI app
4. Streams events from daemon → app via XPC (using `NSXPCConnection`)
5. When build completes, signals app to finalize and display results

**IPC with app:** XPC with a typed Swift protocol — chosen over raw sockets for type safety, lifecycle management, and integration with macOS entitlements model.

---

## Component 4: SwiftUI App

A macOS app that displays the build timeline and analysis results.

**Main window layout:**
```
┌─────────────────────────────────────────────────────┐
│  Toolbar: Command, Duration, Parallelism Score       │
├─────────────────────────────────────────────────────┤
│                                                      │
│  TimelineView (main canvas)                          │
│  - Horizontally scrollable, pinch-to-zoom            │
│  - Process boxes colored by type                     │
│  - Nested child processes indented vertically        │
│  - Live updating during capture                      │
│                                                      │
├─────────────────────────────────────────────────────┤
│  ProcessDetailPanel (selected process)               │
│  - Duration, PID, exit code                          │
│  - Working directory                                 │
│  - Full command + arguments                          │
│  - Parent/children count                             │
├─────────────────────────────────────────────────────┤
│  AnalysisPanel (collapsible)                         │
│  - Parallelism chart                                 │
│  - Gap list                                          │
│  - Suggestions                                       │
└─────────────────────────────────────────────────────┘
```

**Process color coding:**
- Build system (make, cmake, cargo, gradle, etc.) — blue
- Compiler (clang, gcc, swiftc, rustc) — green
- Linker (ld, lld) — yellow
- Shell/scripts — gray
- Other/unknown — light gray

**Interaction:**
- Click a process box to select it (shows detail panel)
- Scroll/zoom the timeline
- Hover to see tooltip with command name and duration

**State:**
- `BuildSession` — top-level observable object, drives all views
- Contains `Timeline`, `BuildAnalysis`, connection status
- Live update via Combine as events stream in from CLI/daemon

---

## Error Handling

- **ESF permissions denied:** Show clear onboarding message explaining Full Disk Access + entitlements; link to System Settings
- **Build command not found:** Show error in app before starting
- **Daemon crash:** App shows "capture lost" state with partial data
- **Build exits non-zero:** Still display timeline (failed builds are often more interesting to analyze)

---

## Distribution

- Distributed as a `.dmg` or via Homebrew tap
- CLI tool installed to `/usr/local/bin` via installer script or Homebrew formula
- App requires macOS 13+ (Ventura) for modern SwiftUI features
- Code signing required for ESF (Apple Developer account + entitlement approval)

---

## Testing Strategy

- **Unit tests for wtf-core:** Test tree construction, parallelism analysis, gap detection, suggestion generation with synthetic event streams — no ESF required
- **Integration tests:** Use recorded event streams from real builds as fixtures
- **UI tests:** Snapshot tests for timeline rendering
- **Manual testing:** Run against real builds (make, cargo, npm, xcodebuild)

---

## Out of Scope (for now)

- Linux/Windows support (macOS-native only)
- Saving/loading past build sessions (future feature)
- Remote/CI capture (future feature)
- Plugin system for custom analyzers
