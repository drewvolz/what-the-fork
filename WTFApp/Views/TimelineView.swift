// WTFApp/Views/TimelineView.swift
import SwiftUI
import WTFCore

/// Scrollable, zoomable canvas showing the full process tree as a horizontal timeline.
struct TimelineView: View {
    let timeline: Timeline
    @Binding var selectedNode: ProcessNode?
    @State private var pixelsPerSecond: Double = 100.0
    private let rowHeight: CGFloat = 28
    private let rowPadding: CGFloat = 4

    var body: some View {
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
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        if #available(macOS 14.0, *) {
            self.gesture(MagnifyGesture()
                .onChanged { value in
                    pixelsPerSecond = max(10, min(2000, pixelsPerSecond * value.magnification))
                }
            )
        } else {
            self
        }
    }

    @ViewBuilder
private func nodeRow(_ node: ProcessNode, depth: Int) -> AnyView {
    let row = HStack(spacing: 0) {
        Spacer().frame(width: CGFloat(depth) * 16)
        Spacer().frame(width: CGFloat((node.startTime - timeline.startTime) * pixelsPerSecond))
        ProcessBoxView(
            node: node,
            category: ProcessClassifier.classify(node),
            pixelsPerSecond: pixelsPerSecond,
            isSelected: selectedNode?.id == node.id,
            onSelect: { selectedNode = node }
        )
        Spacer()
    }
    .frame(height: rowHeight)
    let children = node.children.map { child in nodeRow(child, depth: depth + 1) }
    return AnyView(VStack(alignment: .leading, spacing: 0) {
        row
        ForEach(Array(children.enumerated()), id: \ .offset) { $0.element }
    })
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
