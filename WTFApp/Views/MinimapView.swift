// WTFApp/Views/MinimapView.swift
import SwiftUI
import WTFCore

/// Floating minimap overlay showing the full timeline at a glance.
/// The purple viewport rectangle shows the currently visible area.
/// Tap to jump to a position; drag to scroll continuously.
struct MinimapView: View {
    let timeline: Timeline
    let scrollOffset: CGPoint
    let visibleSize: CGSize
    let pixelsPerSecond: Double
    /// Set of process IDs on the critical path — rendered with a gold outline.
    var criticalPathIDs: Set<Int> = []
    /// Called with a time fraction [0, 1] when the user taps or drags.
    let onSeek: (Double) -> Void

    private let minimapWidth: CGFloat = 180
    private let minimapHeight: CGFloat = 80

    var body: some View {
        let allNodes = flattenedNodes()
        Canvas { context, size in
            drawNodes(context: context, size: size, allNodes: allNodes)
            drawViewport(context: context, size: size, totalRows: allNodes.count)
        }
        .frame(width: minimapWidth, height: minimapHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let fraction = max(0, min(1, value.location.x / minimapWidth))
                    onSeek(fraction)
                }
        )
    }

    // MARK: - Drawing

    private func flattenedNodes() -> [(node: ProcessNode, row: Int)] {
        var result: [(node: ProcessNode, row: Int)] = []
        flattenNodes(timeline.rootNode, row: 0, into: &result)
        return result
    }

    private func drawNodes(context: GraphicsContext, size: CGSize, allNodes: [(node: ProcessNode, row: Int)]) {
        let totalDuration = timeline.totalDuration
        guard totalDuration > 0 else { return }

        let totalRows = max(1, allNodes.count)

        // First pass: fill all nodes.
        for (node, row) in allNodes {
            let startFraction = (node.startTime - timeline.startTime) / totalDuration
            let duration = (node.endTime ?? node.startTime + 0.05) - node.startTime
            let widthFraction = duration / totalDuration

            let x = CGFloat(startFraction) * size.width
            let w = max(1, CGFloat(widthFraction) * size.width)
            let rowH = size.height / CGFloat(totalRows)
            let y = CGFloat(row) * rowH
            let h = max(1, rowH - 1)

            let rect = CGRect(x: x, y: y, width: w, height: h)
            let nodeColor = ProcessClassifier.color(for: node)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(nodeColor.opacity(0.7)))
        }

        // Second pass: gold outline for critical path nodes.
        guard !criticalPathIDs.isEmpty else { return }
        let goldColor = Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.85)
        for (node, row) in allNodes where criticalPathIDs.contains(node.id) {
            let startFraction = (node.startTime - timeline.startTime) / totalDuration
            let duration = (node.endTime ?? node.startTime + 0.05) - node.startTime
            let widthFraction = duration / totalDuration

            let x = CGFloat(startFraction) * size.width
            let w = max(2, CGFloat(widthFraction) * size.width)
            let rowH = size.height / CGFloat(totalRows)
            let y = CGFloat(row) * rowH
            let h = max(2, rowH - 1)

            let rect = CGRect(x: x, y: y, width: w, height: h)
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 1),
                with: .color(goldColor),
                lineWidth: 1
            )
        }
    }

    private func drawViewport(context: GraphicsContext, size: CGSize, totalRows: Int) {
        guard pixelsPerSecond > 0, timeline.totalDuration > 0 else { return }
        let totalContentWidth = CGFloat(timeline.totalDuration * pixelsPerSecond)
        guard totalContentWidth > 0 else { return }

        // The timeline scrolls primarily horizontally, so the viewport rect spans full height
        // and tracks only the horizontal position. This avoids a tiny indicator stuck at y=0
        // when the content fits vertically (the common case).
        let viewportXFraction = scrollOffset.x / totalContentWidth
        let viewportWidthFraction = visibleSize.width / totalContentWidth
        let x = max(0, viewportXFraction * size.width)
        let w = min(size.width - x, max(20, viewportWidthFraction * size.width))

        let rect = CGRect(x: x, y: 0, width: w, height: size.height)
        context.fill(
            Path(roundedRect: rect, cornerRadius: 2),
            with: .color(.purple.opacity(0.15))
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 2),
            with: .color(.purple.opacity(0.85)),
            lineWidth: 2
        )
    }

    // MARK: - Helpers

    private func flattenNodes(_ node: ProcessNode, row: Int, into result: inout [(node: ProcessNode, row: Int)]) {
        result.append((node, row))
        for child in node.children {
            flattenNodes(child, row: result.count, into: &result)
        }
    }
}
