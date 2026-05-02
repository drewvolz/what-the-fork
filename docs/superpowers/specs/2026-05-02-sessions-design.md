# Sessions Design Spec

**Date:** 2026-05-02  
**Status:** Approved

## Problem

1. Tab titles don't update away from "New Session" until focus is lost and regained — a SwiftUI reactivity bug.
2. Sessions are ephemeral — once the app quits, all build history is lost. Users want to revisit past builds.

## Scope

- Fix tab title update latency (bug fix)
- Add persistent session history with minimap previews, accessible from the idle screen

---

## Feature 1: Tab Title Fix

### Root Cause

`ContentView` observes `SessionManager` but not individual `NamedSession` objects. SwiftUI only re-evaluates `tabItem` labels when the enclosing view body re-runs. Since `ContentView` doesn't subscribe to each session's `objectWillChange`, label changes on individual sessions are invisible to the tab bar until an unrelated re-render occurs (e.g., focus change).

### Fix

In `SessionManager`, subscribe to each `NamedSession.objectWillChange` and forward it to `SessionManager.objectWillChange`. When any session label changes, the manager fires, `ContentView` re-renders, and all `tabItem` labels re-evaluate immediately.

**Implementation:** One `AnyCancellable` per session, stored in a `[UUID: AnyCancellable]` dict in `SessionManager`. Subscriptions are added in `init()` and `addSession()`, removed in `removeSession()`.

---

## Feature 2: Saved Sessions

### Goals

- Every completed session is automatically saved to disk
- Sessions persist across app restarts, building up history over time
- The idle screen becomes the sessions browser (compact list rows with minimap previews)
- Users can reopen any past session and delete ones they no longer need

### Data Model

**`StoredSession`** — `Codable, Identifiable` struct:

```swift
struct StoredSession: Codable, Identifiable {
    let id: UUID
    let commandName: String       // e.g. "cargo build"
    let duration: TimeInterval    // total build seconds
    let parallelismScore: Double  // for display in the row
    let timestamp: Date
    let rootPID: Int
    let events: [ProcessEvent]    // full event log for re-analysis
}
```

> Note: `ProcessEvent` must conform to `Codable`. Add conformance in WTFCore if not already present.

**Storage location:** `~/Library/Application Support/WhatTheFork/sessions/{uuid}.json`  
**Retention:** Unlimited — all sessions are kept. Users delete manually.

### `SessionStore`

`ObservableObject` owned by `SessionManager`:

- `@Published var history: [StoredSession]` — loaded on init, sorted newest-first
- `save(named: NamedSession)` — called automatically on `.complete` transition; encodes to JSON and writes to disk; prepends to `history`
- `delete(id: UUID)` — removes file from disk and drops from `history`

On init, scans the sessions directory and decodes all JSON files. Missing or malformed files are skipped silently.

### Auto-Save Trigger

`SessionManager` observes each `NamedSession`'s session state via Combine. On `.complete` transition, it calls `store.save(named:)`. No user action required.

### Restoring a Session

`BuildSession` gains a `restore(events: [ProcessEvent], rootPID: Int)` method:
- Sets `self.liveEvents = events` and `self.rootPID = rootPID`
- Calls the existing `finalize()` logic
- Tab transitions `.idle` → `.complete` with the historical data

### UI: Idle Screen Redesign

The existing idle "waiting for wtf" screen is replaced with a sessions browser.

**With history — compact list rows:**
- Section header: "Recent Sessions" + count
- Each row: `[minimap thumbnail] [command name] [duration · parallelism%] [timestamp]`
- Minimap thumbnail: a live mini `MinimapView` (56×36pt) rendered from the stored events via `TreeBuilder` + `CriticalPathFinder`; uses existing `MinimapView` with a fixed small frame
- Most recent row has a slightly elevated background to draw the eye
- Click row → calls `restore()` on the current tab's session, transitioning it to `.complete`
- Right-click row → context menu with "Delete Session" action

**Empty state (no history):**
- `timer` SF Symbol (large, secondary color)
- "No sessions yet"
- "Run `wtf <command>` to capture your first build"

**Hint text in toolbar** (idle state only):  
`Run wtf <command> to start a new session`

### New View: `SessionHistoryView`

Extracted as a standalone SwiftUI view:
- Takes `store: SessionStore` and `onRestore: (StoredSession) -> Void`
- Renders the list or empty state
- Each row is a `SessionHistoryRow` view

### Files Changed

| File | Change |
|------|--------|
| `WTFCore/Sources/WTFCore/ProcessEvent.swift` | Add `Codable` conformance if missing |
| `WTFApp/Models/SessionStore.swift` | New — persistence layer |
| `WTFApp/Models/StoredSession.swift` | New — codable value type |
| `WTFApp/Models/SessionManager.swift` | Own `SessionStore`; forward session `objectWillChange`; auto-save on complete |
| `WTFApp/Models/BuildSession.swift` | Add `restore(events:rootPID:)` method |
| `WTFApp/Views/SessionHistoryView.swift` | New — idle screen sessions browser |
| `WTFApp/Views/ContentView.swift` | Replace `idleView` with `SessionHistoryView`; pass `store` and restore callback |

---

## Out of Scope

- Manual session naming / renaming
- Exporting or sharing sessions
- Session search or filtering
- Capping history size (unlimited for now)
