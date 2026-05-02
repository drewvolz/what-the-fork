# Tabs, Live Streaming, Node Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-session tabs, live timeline streaming during capture, bigger always-labeled nodes with hash-based colors for "other" processes, and fix export labels.

**Architecture:** Six independent tasks building bottom-up: classifier logic → ProcessBoxView → row heights + minimap color → BuildSession live timer → SessionManager models → ContentView TabView integration.

**Tech Stack:** SwiftUI macOS 13+, Combine, `xcodebuild` for build verification. No new dependencies.

---

### Task 1: Hash-based color in ProcessClassifier

**Files:**
- Modify: `WTFApp/Helpers/ProcessClassifier.swift`

Add `color(for:)` and `hashColor(for:)` static functions to `ProcessClassifier`. The hash uses DJB2 (overflow-safe with `&*` and `&+`) for stable colors across runs.

- [ ] **Step 1: Add the color functions**

Open `WTFApp/Helpers/ProcessClassifier.swift`. After the `classify(_:)` function, add:

```swift
    /// Returns the display color for a node — uses category color for known types,
    /// and a stable hash-derived color for "other" processes.
    static func color(for node: ProcessNode) -> Color {
        let category = classify(node)
        guard category == .other else { return category.color }
        return hashColor(for: node.commandName.lowercased())
    }

    private static func hashColor(for name: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.55, green: 0.36, blue: 0.96),  // purple
            Color(red: 0.13, green: 0.70, blue: 0.70),  // teal
            Color(red: 0.93, green: 0.40, blue: 0.40),  // coral
            Color(red: 0.20, green: 0.65, blue: 0.85),  // sky blue
            Color(red: 0.93, green: 0.60, blue: 0.10),  // amber
            Color(red: 0.85, green: 0.35, blue: 0.70),  // pink
            Color(red: 0.45, green: 0.80, blue: 0.30),  // lime
            Color(red: 0.93, green: 0.55, blue: 0.20),  // orange
        ]
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
```

- [ ] **Step 2: Build to catch syntax errors**

```bash
cd /Users/drew/dev/what-the-fork
xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WTFApp/Helpers/ProcessClassifier.swift
git commit -m "feat: hash-based color for 'other' processes in ProcessClassifier

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: ProcessBoxView — bigger nodes, always-show labels, alwaysShowLabel param

**Files:**
- Modify: `WTFApp/Views/ProcessBoxView.swift`
- Modify: `WTFApp/Views/TimelineView.swift`
- Modify: `WTFApp/Helpers/TimelineExporter.swift`

Remove the `category` parameter (color now computed from `node` directly), increase box height 22→32px, always show the command name, add `alwaysShowLabel` flag for export.

- [ ] **Step 1: Replace ProcessBoxView.swift**

```swift
// WTFApp/Views/ProcessBoxView.swift
import SwiftUI
import WTFCore

/// A single colored box representing a process in the timeline.
struct ProcessBoxView: View {
    let node: ProcessNode
    let pixelsPerSecond: Double
    let isSelected: Bool
    let alwaysShowLabel: Bool
    let onSelect: () -> Void

    init(node: ProcessNode, pixelsPerSecond: Double, isSelected: Bool,
         alwaysShowLabel: Bool = false, onSelect: @escaping () -> Void) {
        self.node = node
        self.pixelsPerSecond = pixelsPerSecond
        self.isSelected = isSelected
        self.alwaysShowLabel = alwaysShowLabel
        self.onSelect = onSelect
    }

    private var width: CGFloat {
        let dur = (node.endTime ?? node.startTime + 0.05) - node.startTime
        return max(CGFloat(dur * pixelsPerSecond), 4)
    }

    var body: some View {
        let color = ProcessClassifier.color(for: node)
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(isSelected ? 1.0 : 0.75))
            .frame(width: width, height: 32)
            .overlay(labelOverlay, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .onTapGesture(perform: onSelect)
            .help("\(node.commandName) — \(formattedDuration)")
    }

    @ViewBuilder
    private var labelOverlay: some View {
        if let label = labelText(for: width) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
    }

    private func labelText(for width: CGFloat) -> String? {
        guard alwaysShowLabel || width >= 8 else { return nil }
        if width >= 120 { return "\(node.commandName) — \(formattedDuration)" }
        return node.commandName
    }

    private var formattedDuration: String {
        guard let dur = node.duration else { return "…" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }
}
```

- [ ] **Step 2: Fix TimelineView call site — remove `category:` argument**

In `WTFApp/Views/TimelineView.swift`, find the `ProcessBoxView(` call inside `nodeRow` and change it to:

```swift
ProcessBoxView(
    node: node,
    pixelsPerSecond: pixelsPerSecond,
    isSelected: selectedNode?.id == node.id,
    onSelect: { selectedNode = node }
)
```

- [ ] **Step 3: Fix TimelineExporter call site — remove `category:`, add `alwaysShowLabel: true`**

In `WTFApp/Helpers/TimelineExporter.swift`, find the `ProcessBoxView(` call inside `ExportableTimelineView.nodeRow` and change it to:

```swift
ProcessBoxView(
    node: node,
    pixelsPerSecond: pixelsPerSecond,
    isSelected: false,
    alwaysShowLabel: true,
    onSelect: {}
)
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add WTFApp/Views/ProcessBoxView.swift WTFApp/Views/TimelineView.swift \
        WTFApp/Helpers/TimelineExporter.swift
git commit -m "feat: bigger nodes (32px), always show label, alwaysShowLabel for export

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Row heights + MinimapView color

**Files:**
- Modify: `WTFApp/Views/TimelineView.swift`
- Modify: `WTFApp/Helpers/TimelineExporter.swift`
- Modify: `WTFApp/Views/MinimapView.swift`

- [ ] **Step 1: Update TimelineView rowHeight 28→36**

In `WTFApp/Views/TimelineView.swift`, change:
```swift
private let rowHeight: CGFloat = 28
```
to:
```swift
private let rowHeight: CGFloat = 36
```

- [ ] **Step 2: Update TimelineExporter rowHeight 28→36**

In `WTFApp/Helpers/TimelineExporter.swift`, inside `ExportableTimelineView`, change:
```swift
private let rowHeight: CGFloat = 28
```
to:
```swift
private let rowHeight: CGFloat = 36
```

- [ ] **Step 3: Update MinimapView to use ProcessClassifier.color(for:)**

In `WTFApp/Views/MinimapView.swift`, find:
```swift
let category = ProcessClassifier.classify(node)
context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(category.color.opacity(0.7)))
```
Replace with:
```swift
let nodeColor = ProcessClassifier.color(for: node)
context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(nodeColor.opacity(0.7)))
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add WTFApp/Views/TimelineView.swift WTFApp/Helpers/TimelineExporter.swift \
        WTFApp/Views/MinimapView.swift
git commit -m "feat: row height 36px, minimap uses hash-based colors

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: BuildSession — live timeline via 250ms timer

**Files:**
- Modify: `WTFApp/Models/BuildSession.swift`

- [ ] **Step 1: Replace BuildSession.swift**

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
    @Published var liveTimeline: Timeline?
    @Published var analysis: BuildAnalysis?
    @Published var liveEvents: [ProcessEvent] = []
    @Published private(set) var rootPID: Int?

    private var xpcClient: XPCEventClient?
    private var liveTimer: AnyCancellable?

    func startCapture(sessionID: String, rootPID: Int) {
        xpcClient?.disconnect()
        self.rootPID = rootPID
        state = .capturing
        liveEvents = []
        liveTimeline = nil

        let client = XPCEventClient(sessionID: sessionID)
        client.onEvent = { [weak self] event in
            self?.liveEvents.append(event)
        }
        client.onSessionComplete = { [weak self] in
            self?.finalize()
        }
        xpcClient = client
        client.connect()

        liveTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateLiveTimeline() }
    }

    private func updateLiveTimeline() {
        guard case .capturing = state, let rootPID else { return }
        guard !liveEvents.isEmpty else { return }
        let root = TreeBuilder.buildTree(from: liveEvents, rootPID: rootPID)
        let now = Date().timeIntervalSince1970
        let duration = max(1.0, (root.endTime ?? now) - root.startTime)
        liveTimeline = Timeline(rootNode: root, startTime: root.startTime, totalDuration: duration)
    }

    private func finalize() {
        liveTimer?.cancel()
        liveTimer = nil
        liveTimeline = nil

        guard let rootPID else {
            state = .failed("No session started")
            return
        }

        guard !liveEvents.isEmpty else {
            state = .failed("No events received — is SIP disabled? See README.")
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

- [ ] **Step 2: Build**

```bash
xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add WTFApp/Models/BuildSession.swift
git commit -m "feat: live timeline streaming via 250ms timer during capture

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: NamedSession + SessionManager

**Files:**
- Create: `WTFApp/Models/NamedSession.swift`
- Create: `WTFApp/Models/SessionManager.swift`

Auto-discovered by xcodegen (project uses `path: WTFApp`).

- [ ] **Step 1: Create NamedSession.swift**

```swift
// WTFApp/Models/NamedSession.swift
import Foundation
import Combine
import WTFCore

/// Wraps a BuildSession with a display label that reflects the session's current state.
final class NamedSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var label: String = "New Session"
    let session: BuildSession

    private var cancellable: AnyCancellable?

    init() {
        session = BuildSession()
        cancellable = session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle:
                    self.label = "New Session"
                case .capturing:
                    self.label = "Capturing…"
                case .complete:
                    self.label = self.session.timeline?.rootNode.commandName ?? "Complete"
                case .failed:
                    self.label = "Error"
                }
            }
    }

    /// Icon name reflecting the session's current state, for use in tab items.
    var systemImageName: String {
        switch session.state {
        case .idle:      return "circle"
        case .capturing: return "record.circle.fill"
        case .complete:  return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.circle.fill"
        }
    }
}
```

- [ ] **Step 2: Create SessionManager.swift**

```swift
// WTFApp/Models/SessionManager.swift
import Foundation
import WTFCore

/// Owns the collection of sessions, one per wtf run. Always keeps at least one session.
final class SessionManager: ObservableObject {
    @Published var sessions: [NamedSession]
    @Published var selectedID: UUID

    init() {
        let initial = NamedSession()
        sessions = [initial]
        selectedID = initial.id
    }

    /// Creates a new session, starts capture on it, and selects it.
    func addSession(sessionID: String, rootPID: Int) {
        let named = NamedSession()
        sessions.append(named)
        selectedID = named.id
        named.session.startCapture(sessionID: sessionID, rootPID: rootPID)
    }

    /// Removes a session. Always keeps at least one (inserts a fresh idle session if needed).
    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let fresh = NamedSession()
            sessions = [fresh]
            selectedID = fresh.id
        } else if !sessions.contains(where: { $0.id == selectedID }) {
            selectedID = sessions[sessions.count - 1].id
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add WTFApp/Models/NamedSession.swift WTFApp/Models/SessionManager.swift
git commit -m "feat: NamedSession and SessionManager for multi-session tab support

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: ContentView — TabView + live streaming during capture

**Files:**
- Modify: `WTFApp/Views/ContentView.swift`

Split into `ContentView` (TabView shell + URL routing) and `SessionView` (per-session content). Live timeline renders during `.capturing` state.

- [ ] **Step 1: Replace ContentView.swift**

```swift
// WTFApp/Views/ContentView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WTFCore

struct ContentView: View {
    @StateObject private var manager = SessionManager()

    var body: some View {
        TabView(selection: $manager.selectedID) {
            ForEach(manager.sessions) { named in
                SessionView(named: named, onClose: {
                    manager.removeSession(id: named.id)
                })
                .tabItem {
                    Label(named.label, systemImage: named.systemImageName)
                }
                .tag(named.id)
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
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

        manager.addSession(sessionID: sessionID, rootPID: rootPID)
    }
}

// MARK: - Per-session view

struct SessionView: View {
    @ObservedObject var named: NamedSession
    let onClose: () -> Void

    @State private var selectedNode: ProcessNode?
    @State private var isExporting = false

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
    }

    // MARK: Toolbar

    private var toolbarView: some View {
        HStack {
            Image(systemName: "fork.knife")
                .foregroundStyle(.secondary)
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
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .disabled(isExporting)
                .help("Export timeline as PNG")
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close this session")
        }
    }

    // MARK: Content states

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
        ZStack {
            if let live = named.session.liveTimeline {
                TimelineView(timeline: live, selectedNode: $selectedNode)
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
            if let analysis = named.session.analysis {
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
            let exportPPS = min(200.0, max(50.0, 2000.0 / max(1, timeline.totalDuration)))
            guard let pngData = TimelineExporter.render(timeline: timeline, pixelsPerSecond: exportPPS) else { return }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "build-timeline.png"
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            panel.title = "Export Timeline"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? pngData.write(to: url)
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project WhatTheFork.xcodeproj -scheme WhatTheFork -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **`

If there are errors about `BuildSession.State` pattern matching in closures, add `systemImageName` to `NamedSession` (already included in Task 5 Step 1) and ensure `ContentView` uses `named.systemImageName`.

- [ ] **Step 3: Run and smoke-test**

```bash
# Kill old instance if running
pgrep WhatTheFork | xargs kill 2>/dev/null; sleep 1
open build/DerivedData/Build/Products/Debug/WhatTheFork.app
```

Verify:
- App opens with one "New Session" tab
- Run `wtf sleep 3` in terminal — new tab appears, live timeline streams in
- After sleep, tab label changes to "sleep", final timeline shows
- First "New Session" tab still present
- Export button visible, produces PNG with readable labels
- Close (✕) button removes tab; minimum 1 tab enforced

- [ ] **Step 4: Commit**

```bash
git add WTFApp/Views/ContentView.swift
git commit -m "feat: TabView multi-session UI with live streaming timeline during capture

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Verification Checklist

- [ ] `wtf cargo build` opens a new tab and shows nodes streaming in live
- [ ] Running a second `wtf` command adds a second tab; first tab retained
- [ ] All nodes ≥8px show their command name at 36px row height
- [ ] "other" processes have distinct colors (python, node, etc. not all gray)
- [ ] Export PNG has all labels visible regardless of node width
- [ ] Minimap shows hashed colors matching the timeline nodes
- [ ] Close button removes tab; minimum 1 tab enforced
