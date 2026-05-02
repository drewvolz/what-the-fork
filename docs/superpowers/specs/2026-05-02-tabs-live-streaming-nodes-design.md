# Design: Tabs, Live Streaming, Node Improvements, Color & Export Fix

Date: 2026-05-02  
Status: Approved

## Problem

1. Only one build session is visible at a time — comparing runs requires quitting and re-launching.
2. During capture, a spinner replaces the timeline — no feedback on what's happening.
3. Nodes are too small to read; "other" processes are all the same washed-out gray.
4. Exported PNGs omit node labels because width-based label logic applies even at export zoom.

## Solution Overview

Five improvements shipped as one cohesive change:

1. **Tabs** — each `wtf` run opens a new native macOS tab; all sessions persist in memory.
2. **Live streaming** — a 250ms timer renders a growing partial timeline during capture.
3. **Bigger nodes** — row height 28→36px, box 22→32px, names always visible.
4. **Hash-based color** — "other" processes get a stable color derived from command name.
5. **Export labels** — a flag on `ProcessBoxView` bypasses width thresholds in export.

---

## Feature 1: Tabs

### New types

**`NamedSession`** (`ObservableObject`, `Identifiable`) — wraps a `BuildSession` and a display label.

```swift
final class NamedSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var label: String   // "New Session" | "Capturing…" | commandName | "Error"
    let session: BuildSession
}
```

Label transitions:
- `.idle` → "New Session"
- `.capturing` → "Capturing…"
- `.complete` → root node's `commandName` (e.g. "cargo")
- `.failed` → "Error"

**`SessionManager`** (`ObservableObject`) — owns the sessions array, selected tab ID, and handles URL routing.

```swift
final class SessionManager: ObservableObject {
    @Published var sessions: [NamedSession]
    @Published var selectedID: UUID

    func addSession(sessionID: String, rootPID: Int) -> NamedSession
    func removeSession(id: UUID)   // keeps minimum 1 session
}
```

### ContentView changes

- Replace `@StateObject var session = BuildSession()` with `@StateObject var manager = SessionManager()`.
- Top-level body wraps everything in `TabView(selection: $manager.selectedID)`.
- Each tab renders the existing per-session content (toolbar + timeline/idle/capturing/error views) by reading `named.session` where `named` is the selected `NamedSession`.
- `handleIncomingURL` calls `manager.addSession(sessionID:rootPID:)` which creates the session, starts capture on it, and selects it.

### Tab closing

- Tabs show a close button (standard macOS tab UX via `.tabViewStyle(.automatic)`).
- `SessionManager.removeSession` enforces a minimum of 1 session (inserts a fresh idle session if the last one is removed).

---

## Feature 2: Live Streaming

### BuildSession changes

Add `@Published var liveTimeline: Timeline?`.

During `.capturing`, start a `Timer.publish(every: 0.25, on: .main, in: .common)` stored as an `AnyCancellable`. Each tick:

1. Guard `!liveEvents.isEmpty`, `rootPID != nil`.
2. Call `TreeBuilder.buildTree(from: liveEvents, rootPID: rootPID)`.
3. Compute `totalDuration = max(1.0, (root.endTime ?? Date().timeIntervalSince1970) - root.startTime)`. `startTime` is a Unix `TimeInterval`, so `Date().timeIntervalSince1970` is the correct "now" for in-progress nodes.
4. Publish as `liveTimeline`.

Cancel and nil the timer in `finalize()` and in the `.failed` path.

### ContentView changes

In the `.capturing` case, check `session.liveTimeline`:
- If non-nil: render `TimelineView(timeline: liveTimeline)` with a "⏺ Capturing…" badge overlay.
- If nil (no events yet): render the existing spinner/counter view.

`TimelineView` needs no changes — it accepts a `Timeline` and renders it. Nodes with `endTime == nil` already render as 50ms stubs via `ProcessBoxView`'s existing fallback.

### Animation

`ContentView` wraps the `.capturing` content switch in `.animation(.default, value: session.liveTimeline != nil)` so the transition from spinner to live timeline fades in naturally.

New nodes appearing in `TimelineView` will flicker into view on each 250ms tick — this is acceptable and matches the "streaming" feel. No per-node animation is needed (the ForEach recompute is smooth enough at 250ms).

---

## Feature 3: Bigger Nodes + Always-Show Names

### ProcessBoxView changes

- `height`: 22px → 32px.
- `labelText(for:)` — remove the `nil` return for narrow nodes. New behavior:
  - Any width: show `node.commandName` truncated via SwiftUI's `.lineLimit(1).truncationMode(.tail)`.
  - Width ≥ 120px: show `commandName — duration`.
  - No nil threshold. Every node shows its name.
- Font: keep `.system(size: 10, weight: .medium)`.
- Add `.minimumScaleFactor(0.7)` so very narrow nodes shrink the font rather than clipping.

### TimelineView changes

- `rowHeight`: 28px → 36px.

### TimelineExporter changes

- `ExportableTimelineView.rowHeight`: 28px → 36px (matches live view).

---

## Feature 4: Hash-Based Color for "Other" Processes

### ProcessClassifier changes

Add a static function:

```swift
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

`ProcessCategory.color` for `.other` is kept as `Color(white: 0.75)` (fallback, not used by new callers).

### Call site changes

`ProcessBoxView` and `MinimapView` currently call `ProcessClassifier.classify(node)` then `.color`. Change both to call `ProcessClassifier.color(for: node)` directly.

`TimelineExporter`'s `ExportableTimelineView` uses `ProcessBoxView`, which picks up the change automatically.

`AnalysisPanel` and `ProcessDetailPanel` do not reference `ProcessCategory.color` — no changes needed there.

---

## Feature 5: Export Always Shows Labels

### ProcessBoxView changes

Add parameter `alwaysShowLabel: Bool = false`. When `true`, `labelText(for:)` always returns at least `node.commandName` regardless of width.

```swift
private func labelText(for width: CGFloat) -> String? {
    if alwaysShowLabel || width >= 20 {
        if width >= 120 { return "\(node.commandName) — \(formattedDuration)" }
        return node.commandName
    }
    return nil
}
```

(Note: with Feature 3's "always show name" change, `alwaysShowLabel` primarily affects the export use case where `width >= 120` threshold for duration should still apply but names are forced regardless of pixel width.)

### ExportableTimelineView changes

Pass `alwaysShowLabel: true` to every `ProcessBoxView` call.

---

## Files Changed

| File | Change |
|------|--------|
| `WTFApp/Models/BuildSession.swift` | Add `liveTimeline`, 250ms timer |
| `WTFApp/Models/SessionManager.swift` | **New** — owns sessions array |
| `WTFApp/Models/NamedSession.swift` | **New** — wraps session + label |
| `WTFApp/Views/ContentView.swift` | TabView, per-tab content, live timeline in capturing state |
| `WTFApp/Views/ProcessBoxView.swift` | Height 32px, always-show-name, `alwaysShowLabel` param |
| `WTFApp/Views/TimelineView.swift` | rowHeight 36px |
| `WTFApp/Views/MinimapView.swift` | Switch to `ProcessClassifier.color(for:)` |
| `WTFApp/Helpers/ProcessClassifier.swift` | `color(for:)` + `hashColor(for:)` |
| `WTFApp/Helpers/TimelineExporter.swift` | rowHeight 36px, `alwaysShowLabel: true` |
| `project.yml` | Register new model files |

---

## Out of Scope

- Persisting sessions across app restarts.
- Naming/renaming tabs manually.
- Tab reordering.
