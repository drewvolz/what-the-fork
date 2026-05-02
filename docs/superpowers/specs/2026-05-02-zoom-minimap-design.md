# Zoom Controls + Minimap Design

**Date:** 2026-05-02  
**Status:** Approved

## Problem

The timeline can display 1000+ events spanning seconds to minutes. At the default 100px/s zoom there's no easy way to:
- Zoom in/out without a trackpad pinch gesture
- Know where you are in a large timeline
- Jump to a different area quickly

## Solution

Two floating overlay panels on the timeline:

1. **Zoom controls** — bottom-right corner
2. **Minimap** — top-right corner

## Zoom Controls Overlay

A semi-transparent pill/panel floating over the bottom-right of the `ScrollView`:

- `−` button: divide `pixelsPerSecond` by 1.5 (clamp to 10)
- `+` button: multiply `pixelsPerSecond` by 1.5 (clamp to 2000)
- Label: current zoom expressed as `px/s` (e.g. `100px/s`)
- `⊡ Fit` button: sets `pixelsPerSecond = visibleWidth / totalDuration`

Background: `.regularMaterial` with rounded corners. Always visible.

## Minimap Overlay

A ~180×80pt panel floating over the top-right of the `ScrollView`:

- Canvas rendering of all process nodes at micro scale
- Nodes color-coded by `ProcessCategory` (same palette as timeline)
- Purple-outlined viewport rectangle showing the currently visible area
- **Click** anywhere → timeline scrolls so that time position is centered
- **Drag** the viewport rect → continuously scrolls the timeline
- Background: `.regularMaterial` with rounded corners. Always visible.

## Scroll State Tracking

To position the viewport rectangle in the minimap:

- Name the scroll coordinate space `"timeline"`
- Place a background `GeometryReader` inside the scroll content that reports its frame origin via a `PreferenceKey` (`ScrollOffsetPreferenceKey`)
- `scrollOffset: CGPoint` state in `TimelineView` updated via `.onPreferenceChange`
- `visibleSize: CGSize` captured by a `GeometryReader` wrapping the `ScrollView`

For programmatic scroll (minimap click/drag → scroll timeline):

- Wrap `ScrollView` in `ScrollViewReader`
- Place invisible anchor `Color.clear` views tagged with `id: "t_\(index)"` at 0.1s intervals across the full timeline width
- Minimap tap/drag gesture computes `targetFraction`, finds `closestAnchorIndex`, calls `proxy.scrollTo("t_\(index)", anchor: .leading)`

## New Files

| File | Purpose |
|------|---------|
| `WTFApp/Views/ZoomControlsOverlay.swift` | –/+/Fit buttons, reads pixelsPerSecond |
| `WTFApp/Views/MinimapView.swift` | Canvas minimap + viewport rect + drag gesture |

## Changed Files

| File | Change |
|------|--------|
| `WTFApp/Views/TimelineView.swift` | Add ScrollViewReader, PreferenceKey scroll tracking, GeometryReader for visibleSize, overlay both new views |

## Out of Scope

- Keyboard shortcuts for zoom (can add later)
- Minimap zoom (it's always full-fit)
- Vertical scroll indicator in minimap
