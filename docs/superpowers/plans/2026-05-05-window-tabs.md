# Window Tabs Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-app `TabView` with macOS native window tabs so each session is a real window, restoring from history opens a new tab (not replacing the history list), and native × tab close buttons replace the toolbar xmark.

**Architecture:** `WhatTheForkApp` switches from `Window` to `WindowGroup(id: "session")`. Each window owns one `NamedSession` via a simplified `SessionManager`. Two lightweight `ObservableObject` queues (`SessionLaunchQueue`, `RestoreQueue`) coordinate opening new windows from URL launches and history restores respectively. `SessionStore` is app-level shared state injected as `@EnvironmentObject`.

**Tech Stack:** SwiftUI (macOS 13+), AppKit (`NSWindow.tabbingMode`, `NSViewRepresentable`), Combine

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `WTFApp/Models/SessionLaunchQueue.swift` | **Create** | One-shot queue for CLI URL → new window |
| `WTFApp/Models/RestoreQueue.swift` | **Create** | One-shot queue for history restore → new window |
| `WTFApp/Helpers/WindowTabbingConfigurator.swift` | **Create** | `NSViewRepresentable` that sets `window.tabbingMode = .preferred` |
| `WTFApp/Models/SessionManager.swift` | **Modify** | Shrink to own one `NamedSession`; remove sessions array |
| `WTFApp/WhatTheForkApp.swift` | **Modify** | `Window` → `WindowGroup(id:)`; inject env objects; set tabbing |
| `WTFApp/Views/ContentView.swift` | **Modify** | Remove `TabView`; wire queues; `navigationTitle`; simplify `SessionView` |
| `WTFApp/Views/SessionHistoryView.swift` | **Modify** | Use `@EnvironmentObject`; `onRestore` uses `RestoreQueue` + `openWindow` |

---

### Task 1: Create `SessionLaunchQueue` and `RestoreQueue`

**Files:**
- Create: `WTFApp/Models/SessionLaunchQueue.swift`
- Create: `WTFApp/Models/RestoreQueue.swift`

- [ ] **Step 1: Create `SessionLaunchQueue.swift`**

```swift
// WTFApp/Models/SessionLaunchQueue.swift
import Foundation

/// One-shot queue that carries a pending CLI launch request to the next
/// window that appears. Cleared immediately after the window consumes it.
final class SessionLaunchQueue: ObservableObject {
    @Published var pending: (sessionID: String, rootPID: Int)? = nil
}
```

- [ ] **Step 2: Create `RestoreQueue.swift`**

```swift
// WTFApp/Models/RestoreQueue.swift
import Foundation

/// One-shot queue that carries a pending restore request to the next
/// window that appears. Cleared immediately after the window consumes it.
final class RestoreQueue: ObservableObject {
    @Published var pending: StoredSession? = nil
}
```

- [ ] **Step 3: Register both files in `project.pbxproj`**

Open `WhatTheFork.xcodeproj/project.pbxproj`. Find how other files in `WTFApp/Models/` are registered (PBXFileReference entry, PBXBuildFile entry, Models group children, Sources build phase). Add equivalent entries for `SessionLaunchQueue.swift` and `RestoreQueue.swift`.

- [ ] **Step 4: Build to verify**

```bash
cd /Users/drew/dev/what-the-fork && xcodebuild -scheme WhatTheFork -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add WTFApp/Models/SessionLaunchQueue.swift WTFApp/Models/RestoreQueue.swift WhatTheFork.xcodeproj/project.pbxproj
git commit -m "feat: add SessionLaunchQueue and RestoreQueue for window coordination

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Create `WindowTabbingConfigurator`

**Files:**
- Create: `WTFApp/Helpers/WindowTabbingConfigurator.swift`

- [ ] **Step 1: Create the file**

```swift
// WTFApp/Helpers/WindowTabbingConfigurator.swift
import SwiftUI
import AppKit

/// Invisible NSView that configures its host window to prefer tab mode.
/// Apply via .background(WindowTabbingConfigurator()) on any root view.
struct WindowTabbingConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.tabbingMode = .preferred
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

- [ ] **Step 2: Register in `project.pbxproj`**

Find how other files in `WTFApp/Helpers/` (e.g. `ProcessClassifier.swift`, `TimelineExporter.swift`) are registered. Add equivalent entries for `WindowTabbingConfigurator.swift`.

- [ ] **Step 3: Build to verify**

```bash
cd /Users/drew/dev/what-the-fork && xcodebuild -scheme WhatTheFork -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add WTFApp/Helpers/WindowTabbingConfigurator.swift WhatTheFork.xcodeproj/project.pbxproj
git commit -m "feat: add WindowTabbingConfigurator to enforce tab mode per window

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Simplify `SessionManager`

**Files:**
- Modify: `WTFApp/Models/SessionManager.swift`

`SessionManager` no longer manages an array of sessions. It owns exactly one `NamedSession` and forwards its `objectWillChange` so that `ContentView` (which observes `SessionManager`) re-renders when the session label changes.

- [ ] **Step 1: Replace the entire contents of `WTFApp/Models/SessionManager.swift`**

```swift
// WTFApp/Models/SessionManager.swift
import Foundation
import Combine

final class SessionManager: ObservableObject {
    let named = NamedSession()

    private var namedCancellable: AnyCancellable?
    private var completionCancellable: AnyCancellable?

    init() {
        namedCancellable = named.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Call once per window after the SessionStore environment object is available.
    func beginAutoSave(store: SessionStore) {
        completionCancellable = named.session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, case .complete = state, !self.named.isRestored else { return }
                store.save(named: self.named)
            }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/drew/dev/what-the-fork && xcodebuild -scheme WhatTheFork -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` (ContentView will have compile errors until Task 5 — that's fine; check for Swift compiler errors only in this file for now by building after Task 5).

> **Note:** If you get errors from `ContentView.swift` referencing `manager.sessions`, `manager.selectedID`, or `manager.addSession`, those are expected and will be fixed in Task 5. Focus on ensuring `SessionManager.swift` itself has no errors.

- [ ] **Step 3: Commit**

```bash
git add WTFApp/Models/SessionManager.swift
git commit -m "refactor: SessionManager owns one NamedSession, removes sessions array

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Update `WhatTheForkApp`

**Files:**
- Modify: `WTFApp/WhatTheForkApp.swift`

- [ ] **Step 1: Replace the entire contents of `WTFApp/WhatTheForkApp.swift`**

```swift
// WTFApp/WhatTheForkApp.swift
import SwiftUI
import AppKit

@main
struct WhatTheForkApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var launchQueue = SessionLaunchQueue()
    @StateObject private var restoreQueue = RestoreQueue()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    var body: some Scene {
        WindowGroup(id: "session") {
            ContentView()
                .environmentObject(store)
                .environmentObject(launchQueue)
                .environmentObject(restoreQueue)
        }
    }
}
```

- [ ] **Step 2: Build to verify (may still have ContentView errors — that's OK)**

```bash
cd /Users/drew/dev/what-the-fork && xcodebuild -scheme WhatTheFork -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

If errors are only from `ContentView.swift` (not `WhatTheForkApp.swift`), proceed.

- [ ] **Step 3: Commit**

```bash
git add WTFApp/WhatTheForkApp.swift
git commit -m "feat: switch to WindowGroup with shared store and queue env objects

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Update `SessionHistoryView`

**Files:**
- Modify: `WTFApp/Views/SessionHistoryView.swift`

`SessionHistoryView` stops accepting `store` as a parameter and `onRestore` as a closure. Both come from the environment instead. When restoring, it pushes to `RestoreQueue` and calls `openWindow(id: "session")`.

- [ ] **Step 1: Replace the entire contents of `WTFApp/Views/SessionHistoryView.swift`**

```swift
// WTFApp/Views/SessionHistoryView.swift
import SwiftUI
import WTFCore

/// Replaces the idle screen. Shows all stored sessions as compact rows with
/// minimap thumbnails. Empty state shown when no sessions exist.
struct SessionHistoryView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var restoreQueue: RestoreQueue
    @Environment(\.openWindow) var openWindow

    var body: some View {
        if store.history.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recent Sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Text("\(store.history.count) sessions")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                    ForEach(store.history) { session in
                        SessionHistoryRow(
                            session: session,
                            onRestore: {
                                restoreQueue.pending = session
                                openWindow(id: "session")
                            },
                            onDelete: { store.delete(id: session.id) }
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No sessions yet")
                .foregroundStyle(.secondary)
            Text("Run `wtf <command>` to capture your first build")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct SessionHistoryRow: View {
    let session: StoredSession
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var thumbnailData: (timeline: Timeline, criticalPathIDs: Set<Int>)?

    var body: some View {
        Button(action: onRestore) {
            HStack(spacing: 12) {
                thumbnailView
                    .frame(width: 56, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.commandName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(rowSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(relativeTimestamp)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .contextMenu {
            Button("Delete Session", role: .destructive, action: onDelete)
        }
        .task {
            guard thumbnailData == nil else { return }
            let root = TreeBuilder.buildTree(from: session.events, rootPID: session.rootPID)
            let maxEnd = root.allDescendants.compactMap(\.endTime).max()
            let duration = max(1.0, (maxEnd ?? root.startTime) - root.startTime)
            let tl = Timeline(rootNode: root, startTime: root.startTime, totalDuration: duration)
            let cpIDs = Set(CriticalPathFinder.findCriticalPath(root).map(\.id))
            thumbnailData = (tl, cpIDs)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let (tl, cpIDs) = thumbnailData {
            MinimapThumbnailView(timeline: tl, criticalPathIDs: cpIDs)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        }
    }

    private var rowSubtitle: String {
        let dur = session.duration < 60
            ? String(format: "%.1fs", session.duration)
            : String(format: "%.0fm %.0fs", session.duration / 60, session.duration.truncatingRemainder(dividingBy: 60))
        let pct = String(format: "%.0f%%", session.parallelismScore * 100)
        return "\(dur) · \(pct) parallel"
    }

    private var relativeTimestamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.timestamp) {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            return fmt.string(from: session.timestamp)
        } else if cal.isDateInYesterday(session.timestamp) {
            return "Yesterday"
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE"
            return fmt.string(from: session.timestamp)
        }
    }
}
```

- [ ] **Step 2: Build to verify (may still have ContentView errors)**

```bash
cd /Users/drew/dev/what-the-fork && xcodebuild -scheme WhatTheFork -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add WTFApp/Views/SessionHistoryView.swift
git commit -m "refactor: SessionHistoryView uses env objects, restore opens new window

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Rewrite `ContentView`

**Files:**
- Modify: `WTFApp/Views/ContentView.swift`

This is the largest change. `ContentView` drops `TabView` entirely — it now renders a single `SessionView` for the window's own session. `SessionView` loses `onClose` and the toolbar xmark button, and gets `store` from the environment instead of as a parameter.

- [ ] **Step 1: Replace the entire contents of `WTFApp/Views/ContentView.swift`**

```swift
// WTFApp/Views/ContentView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WTFCore

struct ContentView: View {
    @StateObject private var manager = SessionManager()
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var launchQueue: SessionLaunchQueue
    @EnvironmentObject var restoreQueue: RestoreQueue
    @Environment(\.openWindow) var openWindow

    @State private var hasStarted = false

    var body: some View {
        SessionView(named: manager.named)
            .background(WindowTabbingConfigurator())
            .navigationTitle(manager.named.label)
            .onAppear {
                guard !hasStarted else { return }
                hasStarted = true
                manager.beginAutoSave(store: store)
                if let req = launchQueue.pending {
                    launchQueue.pending = nil
                    manager.named.session.startCapture(
                        sessionID: req.sessionID,
                        rootPID: req.rootPID
                    )
                } else if let stored = restoreQueue.pending {
                    restoreQueue.pending = nil
                    manager.named.isRestored = true
                    manager.named.session.restore(
                        events: stored.events,
                        rootPID: stored.rootPID
                    )
                }
            }
            .onOpenURL { handleIncomingURL($0) }
    }

    private func handleIncomingURL(_ url: URL) {
        guard
            url.scheme == "whatthefork",
            url.host == "session",
            let sessionID = url.pathComponents.dropFirst().first,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let pidStr = components.queryItems?.first(where: { $0.name == "rootPID" })?.value,
            let rootPID = Int(pidStr)
        else { return }

        launchQueue.pending = (sessionID: sessionID, rootPID: rootPID)
        openWindow(id: "session")
    }
}

// MARK: - Per-session view

struct SessionView: View {
    @ObservedObject var named: NamedSession
    @EnvironmentObject var store: SessionStore

    @State private var selectedNode: ProcessNode?
    @State private var isExporting = false
    @State private var pixelsPerSecond: Double = 100.0

    private var criticalPathIDs: Set<Int> {
        Set(named.session.analysis?.criticalPath.map(\.id) ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            Group {
                switch named.session.state {
                case .idle:
                    idleView

                case .capturing:
                    capturingView

                case .complete:
                    if let timeline = named.session.timeline {
                        VSplitView {
                            TimelineView(
                                timeline: timeline,
                                selectedNode: $selectedNode,
                                pixelsPerSecond: $pixelsPerSecond,
                                criticalPathIDs: criticalPathIDs
                            )
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
    }

    // MARK: Toolbar

    private var toolbarView: some View {
        HStack {
            Text("What the Fork")
                .font(.headline)
            Spacer()
            if case .complete = named.session.state, let analysis = named.session.analysis {
                Label(
                    String(format: "Parallelism: %.0f%%", analysis.parallelismScore * 100),
                    systemImage: "cpu"
                )
                .foregroundStyle(analysis.parallelismScore < 0.3 ? .red : .secondary)
                .font(.subheadline)
            }
            if case .complete = named.session.state, named.session.timeline != nil {
                Button(action: exportTimeline) {
                    if isExporting {
                        Label("Exporting…", systemImage: "hourglass")
                            .font(.subheadline)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isExporting)
                .help("Export timeline as PNG")
            }
        }
    }

    // MARK: Content states

    private var idleView: some View {
        SessionHistoryView()
    }

    private var capturingView: some View {
        ZStack {
            if let live = named.session.liveTimeline {
                TimelineView(
                    timeline: live,
                    selectedNode: $selectedNode,
                    pixelsPerSecond: $pixelsPerSecond
                )
                .transition(.opacity)
                .overlay(alignment: .top) {
                    capturingBadge
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Capturing build…")
                        .foregroundStyle(.secondary)
                    if !named.session.liveEvents.isEmpty {
                        Text("\(named.session.liveEvents.count) events received")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: named.session.liveTimeline != nil)
    }

    private var capturingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("Capturing — \(named.session.liveEvents.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .clipShape(Capsule())
        .padding(.top, 30)
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

    // MARK: Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        HSplitView {
            ProcessDetailPanel(node: selectedNode)
                .frame(minWidth: 250)
            if let analysis = named.session.analysis, let timeline = named.session.timeline {
                let concurrencyPoints = ConcurrencyComputer.compute(
                    processes: timeline.allProcesses,
                    startTime: timeline.startTime,
                    totalDuration: timeline.totalDuration
                )
                ConcurrencyChartView(
                    points: concurrencyPoints,
                    totalDuration: timeline.totalDuration,
                    peak: ConcurrencyComputer.peak(concurrencyPoints)
                )
                .frame(minWidth: 150)
                AnalysisPanel(analysis: analysis)
                    .frame(minWidth: 250)
            }
        }
    }

    // MARK: Export

    private func exportTimeline() {
        guard let timeline = named.session.timeline else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            let exportPPS = pixelsPerSecond
            let cpIDs = criticalPathIDs
            guard let svgData = TimelineExporter.render(
                timeline: timeline,
                pixelsPerSecond: exportPPS,
                criticalPathIDs: cpIDs
            ) else { return }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.svg]
            panel.nameFieldStringValue = "build-timeline.svg"
            panel.directoryURL = FileManager.default
                .urls(for: .desktopDirectory, in: .userDomainMask).first
            panel.title = "Export Timeline"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? svgData.write(to: url)
        }
    }
}
```

- [ ] **Step 2: Build to verify — must be clean**

```bash
cd /Users/drew/dev/what-the-fork && xcodebuild -scheme WhatTheFork -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

If there are errors, the most likely causes and fixes:
- `manager.named.label` not updating: ensure `SessionManager` forwards `objectWillChange` (Task 3)
- `SessionHistoryView()` missing env objects: ensure `@EnvironmentObject` declarations match Task 5
- `openWindow(id:)` unavailable: check deployment target is macOS 13.0 in project settings

- [ ] **Step 3: Commit**

```bash
git add WTFApp/Views/ContentView.swift
git commit -m "feat: replace TabView with window tabs, remove toolbar close button

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Integration test + push

- [ ] **Step 1: Run WTFCore regression tests**

```bash
cd /Users/drew/dev/what-the-fork/WTFCore && swift test 2>&1 | tail -5
```

Expected: All 29 tests pass. If any fail, investigate before proceeding.

- [ ] **Step 2: Final build check**

```bash
cd /Users/drew/dev/what-the-fork && xcodebuild -scheme WhatTheFork -configuration Debug build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 3: Push**

```bash
cd /Users/drew/dev/what-the-fork && git push origin main
```

Report: test results, build result, push success.
