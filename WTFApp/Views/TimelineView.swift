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
    @State private var pixelsPerSecond: Double = 100.0
    @State private var scrollOffset: CGPoint = .zero
    @State private var visibleSize: CGSize = .zero
    private let rowHeight: CGFloat = 36
    private let rowPadding: CGFloat = 4

    var body: some View {
        let content = GeometryReader { geo in
            scrollContent
                .onAppear { visibleSize = geo.size }
                .onChange(of: geo.size) { visibleSize = $0 }
        }
        if #available(macOS 14.0, *) {
            content.gesture(MagnifyGesture()
                .onChanged { value in
                    pixelsPerSecond = max(10, min(2000, pixelsPerSecond * value.magnification))
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
            .overlay(alignment: .bottomTrailing) {
                ZoomControlsOverlay(
                    pixelsPerSecond: $pixelsPerSecond,
                    totalDuration: timeline.totalDuration,
                    visibleWidth: visibleSize.width
                )
                .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                MinimapView(
                    timeline: timeline,
                    scrollOffset: scrollOffset,
                    visibleSize: visibleSize,
                    pixelsPerSecond: pixelsPerSecond,
                    onSeek: { fraction in
                        let targetTime = fraction * timeline.totalDuration
                        let index = Int((targetTime / 0.1).rounded())
                        let clamped = max(0, min(index, anchorCount - 1))
                        withAnimation(.easeOut(duration: 0.15)) {
                            innerProxy.scrollTo("t_\(clamped)", anchor: .leading)
                        }
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

    private func nodeRow(_ node: ProcessNode, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Spacer().frame(width: CGFloat(depth) * 16)
                    Spacer().frame(width: max(0, CGFloat((node.startTime - timeline.startTime) * pixelsPerSecond)))
                    ProcessBoxView(
                        node: node,
                        pixelsPerSecond: pixelsPerSecond,
                        isSelected: selectedNode?.id == node.id,
                        onSelect: { selectedNode = node }
                    )
                    Spacer()
                }
                .frame(height: rowHeight)

                ForEach(node.children, id: \.id) { child in
                    nodeRow(child, depth: depth + 1)
                }
            }
        )
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
