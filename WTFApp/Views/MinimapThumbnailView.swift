// WTFApp/Views/MinimapThumbnailView.swift
import SwiftUI
import WTFCore

/// A fixed-size Canvas rendering of a build timeline — used as a thumbnail
/// in session history rows. No viewport overlay, no gesture.
struct MinimapThumbnailView: View {
    let timeline: Timeline
    var criticalPathIDs: Set<Int> = []

    var body: some View {
        Canvas { context, size in
            drawNodes(context: context, size: size)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func drawNodes(context: GraphicsContext, size: CGSize) {
        let totalDuration = timeline.totalDuration
        guard totalDuration > 0 else { return }

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
            let h = max(1, rowH - 0.5)

            let rect = CGRect(x: x, y: y, width: w, height: h)
            let nodeColor = ProcessClassifier.color(for: node)
            context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(nodeColor.opacity(0.7)))
        }

        guard !criticalPathIDs.isEmpty else { return }
        let goldColor = Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.85)
        for (node, row) in allNodes where criticalPathIDs.contains(node.id) {
            let startFraction = (node.startTime - timeline.startTime) / totalDuration
            let duration = (node.endTime ?? node.startTime + 0.05) - node.startTime
            let widthFraction = duration / totalDuration

            let x = CGFloat(startFraction) * size.width
            let w = max(1, CGFloat(widthFraction) * size.width)
            let rowH = size.height / CGFloat(totalRows)
            let y = CGFloat(row) * rowH
            let h = max(1, rowH - 0.5)

            context.stroke(
                Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 0.5),
                with: .color(goldColor),
                lineWidth: 0.5
            )
        }
    }

    private func flattenNodes(_ node: ProcessNode, row: Int, into result: inout [(node: ProcessNode, row: Int)]) {
        result.append((node, row))
        for child in node.children {
            flattenNodes(child, row: result.count, into: &result)
        }
    }
}
