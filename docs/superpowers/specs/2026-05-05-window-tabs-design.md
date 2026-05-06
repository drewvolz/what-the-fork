# Window Tabs Migration Design

**Date:** 2026-05-05  
**Status:** Approved

## Problem

Two related issues with the current in-app `TabView` approach:

1. **History list disappears on restore** — clicking a session row in `SessionHistoryView` calls `restore()` on the *current* `NamedSession`, transitioning that tab from `.idle` to `.complete`. The history list vanishes because the tab showing it is now showing the restored session.

2. **No native tab close buttons** — the current xmark button is shoehorned into the toolbar next to Export. macOS tabs are expected to be closeable from the tab strip itself.

## Solution

Replace the in-app `TabView` with macOS native window tabs. Each session is a full window; `NSWindow.allowsAutomaticWindowTabbing = true` plus `tabbingMode = .preferred` ensures new windows open as tabs in the existing window rather than floating. The native tab bar provides × close buttons for free.

---

## Section 1: Architecture

### From `Window` → `WindowGroup`

`WhatTheForkApp` changes from a hardcoded `Window` to a `WindowGroup`. Each window instance owns exactly one session.

```swift
@main
struct WhatTheForkApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var launchQueue = SessionLaunchQueue()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(launchQueue)
        }
        .commands {
            // Remove "New Window" shortcut to avoid confusion (new sessions come from wtf CLI)
            CommandGroup(replacing: .newItem) { }
        }
    }
}
```

### Tabbing Mode

Set on the `WindowGroup` scene using the `.defaultSize` modifier chain, and enforced per-window via a `NSWindow` delegate helper:

```swift
// Force new windows to open as tabs, not floaters
NSWindow.allowsAutomaticWindowTabbing = true
// Per-window: set tabbingMode = .preferred in an NSViewRepresentable helper
```

Users can still drag tabs out into separate windows (standard macOS behavior, same as Safari/Xcode). We don't block this.

### `SessionManager` simplified

`SessionManager` shrinks from managing an array of sessions to owning exactly one `NamedSession` + watching its state for auto-save:

```swift
final class SessionManager: ObservableObject {
    let named = NamedSession()
    // store injected via @EnvironmentObject, not owned here
    private var completionCancellable: AnyCancellable?

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

`sessionCancellables` dict and `sessions` array are deleted entirely.

### `ContentView` simplified

No `TabView`, no `ForEach` over sessions. Just one `SessionView` for the window's own session:

```swift
struct ContentView: View {
    @StateObject private var manager = SessionManager()
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var launchQueue: SessionLaunchQueue

    var body: some View {
        SessionView(named: manager.named, store: store)
            .onAppear { manager.beginAutoSave(store: store) }
            .onOpenURL { handleIncomingURL($0) }
    }
}
```

`onOpenURL` is retained for the `whatthefork://` URL scheme but now opens a new window (tab) instead of appending to a session array.

---

## Section 2: URL Handler → New Window

### Problem

With `WindowGroup`, we can't directly pass data into a new window from an external URL without a coordination mechanism.

### Solution: `SessionLaunchQueue`

A lightweight `@EnvironmentObject` singleton acting as a one-shot queue:

```swift
final class SessionLaunchQueue: ObservableObject {
    @Published var pending: (sessionID: String, rootPID: Int)? = nil
}
```

**URL received** → push onto queue:
```swift
// In ContentView.handleIncomingURL:
launchQueue.pending = (sessionID: sessionID, rootPID: rootPID)
openWindow(id: "session")  // opens a new window (tab)
```

**New window appears** → pop from queue:
```swift
// In ContentView.onAppear:
if let req = launchQueue.pending {
    launchQueue.pending = nil
    manager.named.session.startCapture(sessionID: req.sessionID, rootPID: req.rootPID)
}
```

This is a simple first-come-first-served queue. Since the `wtf` CLI only ever opens one session at a time, races are not a concern in practice.

> **Note:** `openWindow(id:)` requires the `WindowGroup` to have an `id:` parameter (e.g., `WindowGroup(id: "session") { ... }`).

---

## Section 3: Restore from History

### Before (broken)

`idleView` called `restore()` on the current `NamedSession`, replacing the history list with the restored timeline in the same tab.

### After

`SessionHistoryView`'s `onRestore` closure:
1. Pushes the stored session into a `RestoreQueue` (similar to `SessionLaunchQueue`)
2. Opens a new window with `openWindow(id: "session")`
3. The new window's `onAppear` pops from the queue and calls `manager.named.session.restore()`

The idle window remains idle, history list intact.

```swift
// RestoreQueue — separate from SessionLaunchQueue to avoid type conflicts
final class RestoreQueue: ObservableObject {
    @Published var pending: StoredSession? = nil
}
```

Both queues are `@StateObject` at app level and injected as `@EnvironmentObject`.

---

## Section 4: Tab Close

### Before

Custom xmark button in the toolbar of each `SessionView`.

### After

The native macOS tab bar provides × on each tab. The toolbar close button is removed. No code required beyond the `WindowGroup` migration.

The window's close action (⌘W / × button) calls the OS-level window close, which SwiftUI handles automatically for `WindowGroup` windows. No `onClose` callback needed.

### `SessionView` changes

- Remove `let onClose: () -> Void` parameter
- Remove the toolbar xmark `Button`
- Remove `let store: SessionStore` parameter (now `@EnvironmentObject`)

---

## Section 5: Tab Title

`navigationTitle` on `ContentView` wires to the window title, which the macOS tab bar displays automatically:

```swift
// In ContentView:
.navigationTitle(manager.named.label)
```

Since `manager.named.label` is `@Published` and `SessionManager` forwards `objectWillChange`, the tab title updates live as the session progresses — consistent with the fix from the previous sprint.

---

## Section 6: Files Changed

| File | Change |
|------|--------|
| `WhatTheForkApp.swift` | `Window` → `WindowGroup`, add `SessionStore` + queue `@StateObject`s |
| `WTFApp/Models/SessionManager.swift` | Remove sessions array; own one `NamedSession`; `beginAutoSave(store:)` |
| `WTFApp/Models/SessionLaunchQueue.swift` | New — one-shot URL-launch queue |
| `WTFApp/Models/RestoreQueue.swift` | New — one-shot restore queue |
| `WTFApp/Views/ContentView.swift` | Remove `TabView`; wire queues; add `navigationTitle` |
| `WTFApp/Views/SessionView.swift` (or `ContentView.swift`) | Remove `onClose`, remove toolbar xmark, use `@EnvironmentObject store` |
| `WTFApp/Views/SessionHistoryView.swift` | `onRestore` opens new window via `RestoreQueue` |

---

## Out of Scope

- Preventing tab detach (macOS standard behavior; not blocked)
- Persisting window layout across restarts
- Multi-window session history (each window shows the same shared `SessionStore`)
