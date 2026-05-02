# Node Text Legibility + Timeline Export Design

**Date:** 2026-05-02  
**Status:** Approved (autonomous)

## Problem

1. **Unreadable nodes:** Process boxes can be as narrow as 4px. Text is always rendered regardless of node width, resulting in clipped/invisible labels.
2. **No sharing:** There's no way to export the timeline graph as an image to share or analyze externally.

## Solution 1 — Smart Node Text

Threshold-based label rendering in `ProcessBoxView`:

| Width (px) | Display |
|-----------|---------|
| < 20 | No text (just colored box) |
| 20–60 | First 3 chars of command name (e.g. `rus`) |
| 60–120 | Full command name, truncated with ellipsis |
| ≥ 120 | Command name + duration (e.g. `rustc — 1.2s`) |

The `clippedText(for width:)` helper picks the right string. Text is always `.lineLimit(1)` and padded 3px inside the box.

**Changed file:** `WTFApp/Views/ProcessBoxView.swift`

## Solution 2 — Export Full Timeline to PNG

- **Export button** added to the main toolbar (share icon, `square.and.arrow.up`)
- Renders the entire timeline (all rows × full time span) using macOS `ImageRenderer` (requires macOS 13+)
- Export renders at the **current `pixelsPerSecond`** zoom level so the image matches what the user sees
- A NSSavePanel lets the user choose filename/location; default name `build-timeline.png`
- Max canvas guard: if the rendered image would exceed 32000×32000px, clamp `pixelsPerSecond` for the export

### Export rendering approach

`TimelineExporter` is a standalone struct that takes a `Timeline` and `pixelsPerSecond` and builds a standalone SwiftUI `View` (no scroll, no overlays) rendering the full tree. `ImageRenderer` converts it to `NSImage`, then to PNG data.

The export is triggered via `BuildSession.exportTimeline()` which returns a temporary PNG URL.

**New files:**
- `WTFApp/Helpers/TimelineExporter.swift` — renders full timeline to NSImage

**Changed files:**
- `WTFApp/Views/ContentView.swift` — export button in toolbar, NSSavePanel sheet
- `WTFApp/Views/ProcessBoxView.swift` — smart text thresholds

## Out of Scope

- PDF export
- Copying to clipboard (can add later)
- Selection-based partial export
