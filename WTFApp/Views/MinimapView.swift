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
    /// Called with a time fraction [0, 1] when the user taps or drags.
    let onSeek: (Double) -> Void

    private let minimapWidth: CGFloat = 180
    private let minimapHeight: CGFloat = 80

    var body: some View {
        Canvas { context, size in
            drawNodes(context: context, size: size)
            drawViewport(context: context, size: size)
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

    private func drawNodes(context: GraphicsContext, size: CGSize) {
        let totalDuration = timeline.totalDuration
        guard totalDuration > 0 else { return }

        // Collect all nodes with their flat row index for vertical positioning.
        var allNodes: [(node: ProcessNode, row: Int)] = []
        flattenNodes(timeline.rootNode, row: 0, into: &allNodes)
        let totalRows = max(1, allNodes.count)

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
    }

    private func drawViewport(context: GraphicsContext, size: CGSize) {
        guard pixelsPerSecond > 0, timeline.totalDuration > 0 else { return }
        let totalContentWidth = CGFloat(timeline.totalDuration * pixelsPerSecond)
        guard totalContentWidth > 0 else { return }

        let viewportXFraction = scrollOffset.x / totalContentWidth
        let viewportWidthFraction = visibleSize.width / totalContentWidth

        let x = max(0, viewportXFraction * size.width)
        let w = min(size.width - x, max(4, viewportWidthFraction * size.width))

        let rect = CGRect(x: x, y: 0, width: w, height: size.height)
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 2),
            with: .color(.purple.opacity(0.8)),
            lineWidth: 1.5
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: 2),
            with: .color(.purple.opacity(0.08))
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
