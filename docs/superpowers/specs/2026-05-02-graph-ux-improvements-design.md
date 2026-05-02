# Build Analyzer Graph UX Improvements

**Date:** 2026-05-02  
**Status:** Approved

## Problem

The build analyzer graph has several friction points that make it awkward to use:

1. **Position loss on zoom** — `pixelsPerSecond` changes but the `ScrollView` doesn't compensate, so content slides away from where the user was looking.
2. **Disorienting minimap navigation** — clicking the minimap scrolls to the `leading` edge of that time position, causing a confusing jump instead of centering the view.
3. **Hierarchy is hard to read** — child rows are indented but have no visual connector lines, making it hard to tell which children belong to which parent at a glance.
4. **Idle time is invisible** — gaps between processes where nothing is happening are not visualized, hiding optimization opportunities.
5. **Hover tooltips lack context** — the current `.help()` string shows only name and duration; there's no way to see start time, category, wait time, or critical path status without clicking.
6. **Minimap doesn't show the critical path** — the minimap's color-coded view doesn't distinguish critical path nodes from others.

## Scope

Approach B: Navigation + Readability. Six targeted improvements across navigation and visual clarity. No new summary panels or keyboard shortcuts (can follow in a future iteration).

## Section 1: Navigation

### 1a — Anchor-preserving zoom

**Current behavior:** `ZoomControlsOverlay` receives `pixelsPerSecond` as a `@Binding` and increments/decrements it directly. The `ScrollView` doesn't compensate, so whatever is at the left edge stays at the left edge while everything else shifts.

**Fix:** Move zoom logic into `TimelineView.scrollContent` (inside the `ScrollViewReader` closure) where it has access to `scrollOffset`, `visibleSize`, and `innerProxy`. `ZoomControlsOverlay` switches from a `@Binding var pixelsPerSecond` to an `onZoomIn`, `onZoomOut`, `onZoomFit` callback pattern.

**Algorithm:**
1. Before zoom: `centerTime = (scrollOffset.x + visibleSize.width / 2) / pixelsPerSecond`
2. Apply new `pixelsPerSecond`
3. Scroll so `centerTime` stays at screen center: find anchor index `= Int((centerTime / 0.1).rounded())`, call `innerProxy.scrollTo("t_\(index)", anchor: .center)`

**Pinch gesture:** Same approach — `MagnifyGesture` moves inside the `ScrollViewReader` so it can fire the same anchor-preserving scroll after each magnification change.

### 1b — Minimap centers viewport on click and drag

**Current behavior:** `onSeek(fraction)` in `TimelineView` uses `anchor: .leading`, so the clicked time snaps to the left edge of the viewport.

**Fix:** Change the `innerProxy.scrollTo` call in the `onSeek` handler to use `anchor: .center`. Both tap and drag use the same code path so both get centered navigation. The minimap's existing `DragGesture(minimumDistance: 0)` already unifies tap and drag into one gesture.

## Section 2: Visual Readability

### 2a — Hierarchy connector lines

**What:** Vertical connector lines + horizontal tick marks drawn alongside indented rows, making the parent→child tree structure scannable without counting indent levels.

**Implementation:** Each non-root row draws its own connector segment — no need to know subtree height. In `TimelineView.nodeRow(_:depth:)`, when `depth > 0`, add a `ZStack` layer behind the row content:
- A 1pt wide vertical `Rectangle` at `x = (depth - 1) * 16 + 8`, spanning the full `rowHeight`. Color: the parent depth's connector color (use `Color.secondary.opacity(0.3)` for simplicity, or `ProcessClassifier.color(for: parentNode).opacity(0.35)` if parent is passed in).
- A 1pt tall horizontal `Rectangle` (tick mark) from `x = (depth - 1) * 16 + 8` to `x = depth * 16`, at `y = rowHeight / 2`.

Since every child row draws its own vertical segment at its parent's indent position, the full connector line emerges naturally without any subtree height calculation.

### 2b — Idle gap shading

**What:** Amber hatched overlay on time regions (≥ 50ms) between sibling processes or after a parent starts before its first child starts. Reveals hidden wait time.

**Implementation:** In `nodeRow(_:depth:)`, change the children loop from `ForEach` to an explicit iteration over `node.children.indices` so adjacent siblings are available for gap calculation:
```
for i in node.children.indices {
    let child = node.children[i]
    let nextSibling = i + 1 < node.children.count ? node.children[i + 1] : nil
    // render child row
    // if nextSibling exists and gap >= 0.05s, render IdleGapView
}
```
- `gap = nextSibling.startTime - (child.endTime ?? child.startTime)` 
- If `gap >= 0.05`, insert an `IdleGapView(width: gap * pixelsPerSecond)` after the child row — a private struct with a Canvas drawing diagonal amber lines at 45°, 4pt spacing, opacity 0.15, with a 1pt amber dashed border at 0.25 opacity.

### 2c — Rich hover tooltip

**What:** A floating card that appears when hovering over a `ProcessBoxView`, showing: process name, duration, start time (relative to build start), category, wait time before starting, and whether it's on the critical path.

**Implementation:**
- Add `@State private var isHovered = false` to `ProcessBoxView`.
- Add `.onHover { isHovered = $0 }` to the outer `ZStack`.
- When `isHovered`, show a `.popover(isPresented:)` or an `.overlay` tooltip card anchored to the top of the box.
- Use a `popover` approach (edge: .top) for automatic positioning. The popover contains a `VStack` with a `Grid` of label-value pairs.
- New data needed in `ProcessBoxView`: `startTime` (relative to build start) and `waitTime` (time between parent end and this node's start, or 0 if concurrent). Pass these from `TimelineView.nodeRow`.

**Tooltip fields:**
| Field | Source |
|---|---|
| Name | `node.displayName` |
| Duration | `node.duration` |
| Started at | `node.startTime - timeline.startTime` |
| Category | `ProcessClassifier.classify(node).label` |
| Waited | gap from previous sibling end or parent start |
| Critical path | `criticalPathIDs.contains(node.id)` |

### 2d — Minimap critical path overlay

**What:** Critical path nodes get a gold outline in the minimap, matching the timeline's gold border. Lets you see the hot path even when zoomed far in.

**Implementation:** Add `var criticalPathIDs: Set<Int> = []` parameter to `MinimapView`. In `drawNodes(context:size:)`, after drawing the fill, add a second pass: for nodes whose `id` is in `criticalPathIDs`, stroke a 1pt gold border with `opacity(0.8)`. Update `TimelineView` to pass `criticalPathIDs` through.

## Changed Files

| File | Change |
|------|--------|
| `WTFApp/Views/TimelineView.swift` | Move zoom logic inside `ScrollViewReader`; anchor-preserving zoom + pinch; minimap seek uses `.center` anchor; pass `criticalPathIDs` to minimap; pass timing context to `ProcessBoxView` |
| `WTFApp/Views/ZoomControlsOverlay.swift` | Replace `@Binding var pixelsPerSecond` with `onZoomIn`, `onZoomOut`, `onZoomFit` callbacks; display label becomes read-only `let` |
| `WTFApp/Views/MinimapView.swift` | Add `criticalPathIDs` param; gold outline pass in `drawNodes` |
| `WTFApp/Views/ProcessBoxView.swift` | Add `startTimeOffset`, `waitTime`, `isOnCriticalPath` params; `onHover` + popover tooltip |

### New Supporting Types / Helpers

| Symbol | Where | Purpose |
|--------|-------|---------|
| `IdleGapView` | `TimelineView.swift` (private struct) | Renders hatched amber rectangle for a given gap width |
| Connector line drawing | `TimelineView.nodeRow()` | Inline `Canvas` or `Rectangle` overlays for tree guides |

## Out of Scope

- Build Health summary panel (can be a follow-up)
- Keyboard navigation between nodes
- Vertical scroll indicator in minimap
- Zoom toward cursor position (anchor to screen center is sufficient for now)
