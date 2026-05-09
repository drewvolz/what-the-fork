// WTFApp/Views/TimelineView.swift
import SwiftUI
import WTFCore

/// Tracks the scroll offset of the timeline's ScrollView.
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

/// Scrollable, zoomable canvas showing the full process tree as a horizontal timeline.
struct TimelineView: View {
    let timeline: Timeline
    @Binding var selectedNode: ProcessNode?
    @Binding var pixelsPerSecond: Double
    var criticalPathIDs: Set<Int> = []
    @State private var scrollOffset: CGPoint = .zero
    @State private var visibleSize: CGSize = .zero
    @State private var scrollProxy: ScrollViewProxy?
    @State private var pinchStartPPS: Double = 100.0  // overwritten at gesture start; initial value is irrelevant
    @State private var isPinching: Bool = false
    @State private var pinchCenterTime: TimeInterval = 0
    @State private var tooltipMeta: TooltipMeta? = nil

    private struct TooltipMeta {
        let node: ProcessNode
        let startOffset: TimeInterval
        let waitTime: TimeInterval
        let onCriticalPath: Bool
    }
    private let rowHeight: CGFloat = 36
    private let rowPadding: CGFloat = 4

    var body: some View {
        let content = GeometryReader { geo in
            scrollContent
                .onAppear { visibleSize = geo.size }
                .onChange(of: geo.size) { visibleSize = $0 }
        }
        .overlayPreferenceValue(TooltipAnchorKey.self) { anchor in
            if let anchor, let meta = tooltipMeta {
                GeometryReader { geo in
                    let nodeRect = geo[anchor]
                    let cardWidth: CGFloat = 220
                    let cardHeight: CGFloat = 160
                    let margin: CGFloat = 8
                    // Prefer above node; clamp to keep card on screen.
                    let rawX = nodeRect.midX - cardWidth / 2
                    let rawY = nodeRect.minY - cardHeight - margin
                    let clampedX = min(max(rawX, margin), geo.size.width - cardWidth - margin)
                    let clampedY = max(rawY, margin)
                    NodeTooltipCard(
                        node: meta.node,
                        startTimeOffset: meta.startOffset,
                        waitTime: meta.waitTime,
                        isOnCriticalPath: meta.onCriticalPath,
                        onDismiss: { tooltipMeta = nil }
                    )
                    .fixedSize()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, y: -2)
                    .position(x: clampedX + cardWidth / 2, y: clampedY + cardHeight / 2)
                }
                .allowsHitTesting(true)
            }
        }
        if #available(macOS 14.0, *) {
            content.gesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isPinching {
                            isPinching = true
                            pinchStartPPS = pixelsPerSecond
                            // Capture center time before zoom changes pps and anchor positions.
                            pinchCenterTime = pixelsPerSecond > 0 && visibleSize.width > 0
                                ? (scrollOffset.x + visibleSize.width / 2) / pixelsPerSecond
                                : 0
                        }
                        pixelsPerSecond = max(10, min(2000, pinchStartPPS * value.magnification))
                    }
                    .onEnded { _ in
                        isPinching = false
                        DispatchQueue.main.async { seekToTime(pinchCenterTime) }
                    }
            )
        } else {
            content
        }
    }

    private var scrollContent: some View {
        ScrollViewReader { innerProxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Background time ruler
                    TimeRulerView(
                        totalDuration: timeline.totalDuration,
                        pixelsPerSecond: pixelsPerSecond
                    )

                    // Process tree rows
                    VStack(alignment: .leading, spacing: rowPadding) {
                        nodeRow(timeline.rootNode, depth: 0)
                    }
                    .padding(.top, 24)  // below ruler
                    .padding(.bottom, 8)

                    // Invisible time anchors for programmatic scrolling (every 0.1s)
                    timeAnchors
                }
                // Trailing margin ensures nodes in the right portion of the viewport
                // are never obscured by the minimap or zoom controls overlays.
                .padding(.trailing, 200)
                // Report scroll offset via preference key
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: CGPoint(
                                x: -geo.frame(in: .named("timeline")).minX,
                                y: -geo.frame(in: .named("timeline")).minY
                            )
                        )
                    }
                )
            }
            .coordinateSpace(name: "timeline")
            .background(Color(nsColor: .controlBackgroundColor))
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            .onAppear { scrollProxy = innerProxy }
            .overlay(alignment: .bottomTrailing) {
                ZoomControlsOverlay(
                    pixelsPerSecond: pixelsPerSecond,
                    totalDuration: timeline.totalDuration,
                    visibleWidth: visibleSize.width,
                    onZoomIn: { performZoom(factor: 1.5) },
                    onZoomOut: { performZoom(factor: 1 / 1.5) },
                    onZoomFit: { zoomFit() }
                )
                .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                MinimapView(
                    timeline: timeline,
                    scrollOffset: scrollOffset,
                    visibleSize: visibleSize,
                    pixelsPerSecond: pixelsPerSecond,
                    criticalPathIDs: criticalPathIDs,
                    onSeek: { fraction in
                        let targetTime = fraction * timeline.totalDuration
                        seekToTime(targetTime)
                    }
                )
                .padding(10)
            }
        }
    }

    // Number of 0.1s anchor steps spanning the full timeline duration.
    private var anchorCount: Int { max(1, Int(ceil(timeline.totalDuration / 0.1))) + 1 }

    /// Invisible anchor views at 0.1-second intervals used by ScrollViewProxy.scrollTo.
    private var timeAnchors: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<anchorCount, id: \.self) { index in
                Color.clear
                    .frame(width: 1, height: 1)
                    .offset(x: CGFloat(Double(index) * 0.1 * pixelsPerSecond), y: 0)
                    .id("t_\(index)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func nodeRow(_ node: ProcessNode, depth: Int, parentEndTime: TimeInterval? = nil, isLastSibling: Bool = false) -> AnyView {
        let waitT = parentEndTime.map { max(0.0, node.startTime - $0) } ?? 0.0
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    // Connector line + tick for non-root rows.
                    if depth > 0 {
                        Canvas { context, size in
                            let connX = CGFloat(depth - 1) * 16 + 8
                            let midY = size.height / 2
                            let vEndY = isLastSibling ? midY : size.height
                            let path = Path { p in
                                // Vertical segment (full height for T-junction, half-height for last-child elbow)
                                p.move(to: CGPoint(x: connX, y: 0))
                                p.addLine(to: CGPoint(x: connX, y: vEndY))
                                // Horizontal tick from connector to indent start
                                p.move(to: CGPoint(x: connX, y: midY))
                                p.addLine(to: CGPoint(x: connX + 8, y: midY))
                            }
                            context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: CGFloat(depth) * 16)
                        Spacer().frame(width: max(0, CGFloat((node.startTime - timeline.startTime) * pixelsPerSecond)))
                        ProcessBoxView(
                            node: node,
                            pixelsPerSecond: pixelsPerSecond,
                            isSelected: selectedNode?.id == node.id,
                            isOnCriticalPath: criticalPathIDs.contains(node.id),
                            startTimeOffset: max(0, node.startTime - timeline.startTime),
                            waitTime: waitT,
                            isTooltipVisible: Binding(
                                get: { tooltipMeta?.node.id == node.id },
                                set: { show in
                                    if show {
                                        tooltipMeta = TooltipMeta(
                                            node: node,
                                            startOffset: max(0, node.startTime - timeline.startTime),
                                            waitTime: waitT,
                                            onCriticalPath: criticalPathIDs.contains(node.id)
                                        )
                                    } else {
                                        tooltipMeta = nil
                                    }
                                }
                            ),
                            onSelect: { selectedNode = node }
                        )
                        Spacer()
                    }
                    .frame(height: rowHeight)
                }

                gapAndRow(node.children, depth: depth + 1, parentEndTime: node.endTime ?? node.startTime)
            }
            .zIndex(selectedNode?.id == node.id ? 100 : 0)
        )
    }

    // MARK: - Zoom helpers

    /// Zoom by `factor` keeping the currently-visible center time at screen center after zoom.
    private func performZoom(factor: Double) {
        let centerTime: TimeInterval
        if pixelsPerSecond > 0 && visibleSize.width > 0 {
            centerTime = (scrollOffset.x + visibleSize.width / 2) / pixelsPerSecond
        } else {
            centerTime = 0
        }
        pixelsPerSecond = max(10, min(2000, pixelsPerSecond * factor))
        DispatchQueue.main.async { seekToTime(centerTime) }
    }

    /// Fit the full build into the visible width, then scroll to the start.
    private func zoomFit() {
        guard timeline.totalDuration > 0, visibleSize.width > 0 else { return }
        pixelsPerSecond = max(10, min(2000, Double(visibleSize.width) / timeline.totalDuration))
        DispatchQueue.main.async { seekToTime(0, anchor: .leading) }
    }

    /// Scroll so that `time` appears at `anchor` position in the viewport (default: center).
    private func seekToTime(_ time: TimeInterval, anchor: UnitPoint = .center) {
        let index = max(0, min(Int((time / 0.1).rounded()), anchorCount - 1))
        withAnimation(.easeOut(duration: 0.15)) {
            scrollProxy?.scrollTo("t_\(index)", anchor: anchor)
        }
    }

    // MARK: - Children with gap overlays

    /// Renders child rows, inserting an IdleGapView between siblings whose gap is ≥ 50ms.
    @ViewBuilder
    private func gapAndRow(_ children: [ProcessNode], depth: Int, parentEndTime: TimeInterval) -> some View {
        ForEach(children.indices, id: \.self) { i in
            nodeRow(children[i], depth: depth, parentEndTime: parentEndTime, isLastSibling: i == children.indices.last)
            if i + 1 < children.count {
                let childEnd = children[i].endTime ?? children[i].startTime
                let gap = children[i + 1].startTime - childEnd
                if gap >= 0.05 {
                    HStack(spacing: 0) {
                        Spacer().frame(width: CGFloat(depth) * 16)
                        Spacer().frame(width: max(0, CGFloat((childEnd - timeline.startTime) * pixelsPerSecond)))
                        IdleGapView(width: min(CGFloat(gap * pixelsPerSecond), visibleSize.width + 200), duration: gap)
                        Spacer()
                    }
                    .frame(height: rowHeight)
                }
            }
        }
    }
}

// MARK: - Idle gap

/// Hatched amber strip shown between sibling processes with a gap ≥ 50ms.
private struct IdleGapView: View {
    let width: CGFloat
    let duration: TimeInterval

    var body: some View {
        Canvas { context, size in
            // Diagonal hatch lines at 45°, 6pt spacing.
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += 6
            }
            context.stroke(path, with: .color(Color.orange.opacity(0.18)), lineWidth: 1)
        }
        .frame(width: max(4, width), height: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    Color.orange.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
        )
        .help(duration >= 1
              ? String(format: "Idle: %.2fs", duration)
              : String(format: "Idle: %.0fms", duration * 1000))
    }
}

/// Thin ruler showing time markers above the timeline.
struct TimeRulerView: View {
    let totalDuration: TimeInterval
    let pixelsPerSecond: Double

    var body: some View {
        Canvas { context, size in
            let step = tickStep(for: pixelsPerSecond)
            var t = 0.0
            while t <= totalDuration {
                let x = t * pixelsPerSecond
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 18))
                    p.addLine(to: CGPoint(x: x, y: 24))
                }
                context.stroke(path, with: .color(.secondary), lineWidth: 1)
                let label = t >= 1 ? String(format: "%.0fs", t) : String(format: "%.0fms", t * 1000)
                if #available(macOS 14.0, *) {
    context.draw(Text(label).font(.system(size: 9)).foregroundStyle(.secondary),
                 at: CGPoint(x: x + 2, y: 9))
} else {
    context.draw(Text(label).font(.system(size: 9)),
                 at: CGPoint(x: x + 2, y: 9))
}
                t += step
            }
        }
        .frame(width: CGFloat(totalDuration * pixelsPerSecond + 80), height: 24)
    }

    private func tickStep(for pps: Double) -> TimeInterval {
        // Choose a tick interval that gives roughly 80-150px between ticks
        let targetInterval = 100.0 / pps
        let steps: [TimeInterval] = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60]
        return steps.min { abs($0 - targetInterval) < abs($1 - targetInterval) } ?? 1
    }
}
