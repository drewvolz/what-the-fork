// WTFApp/Helpers/TimelineExporter.swift
import SwiftUI
import WTFCore

/// Renders the full process timeline to a PNG image for export.
@MainActor
enum TimelineExporter {
    /// Maximum width/height in pixels for a single export image dimension.
    private static let maxImageDimension: CGFloat = 16000

    /// Renders the full timeline tree to PNG data at the given zoom level.
    /// Scales both width and height to fit within `maxImageDimension` at @2x,
    /// so large graphs with many nodes don't silently fail.
    static func render(timeline: Timeline, pixelsPerSecond: Double) -> Data? {
        guard timeline.totalDuration > 0 else { return nil }

        let baseRowHeight: CGFloat = 36
        let rowPadding: CGFloat = 4
        let nodeCount = CGFloat(countNodes(timeline.rootNode))

        // Natural content dimensions before any scaling.
        let naturalWidth = CGFloat(timeline.totalDuration * pixelsPerSecond) + 80
        let naturalHeight = nodeCount * (baseRowHeight + rowPadding) + 32

        // Budget per dimension: maxImageDimension is the pixel limit; at @2x
        // the logical content must fit within half that.
        let budget = maxImageDimension / 2.0
        let scaleW = naturalWidth  > budget ? budget / naturalWidth  : 1.0
        let scaleH = naturalHeight > budget ? budget / naturalHeight : 1.0
        let fitScale = min(scaleW, scaleH)

        let effectivePPS = pixelsPerSecond * fitScale
        let effectiveRowHeight = baseRowHeight * fitScale

        let view = ExportableTimelineView(
            timeline: timeline,
            pixelsPerSecond: effectivePPS,
            rowHeight: effectiveRowHeight
        )

        if #available(macOS 13.0, *) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0  // @2x for crisp text
            // Use cgImage directly — NSImage.cgImage(forProposedRect:) drops
            // pixel data when called on an ImageRenderer-backed NSImage.
            guard let cgImage = renderer.cgImage else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            return bitmap.representation(using: .png, properties: [:])
        } else {
            return nil
        }
    }

    private static func countNodes(_ node: ProcessNode) -> Int {
        node.children.reduce(1) { $0 + countNodes($1) }
    }
}

/// A non-scrolling, non-interactive view of the full timeline used for export.
/// Uses a flat ForEach instead of recursive AnyView to keep SwiftUI layout O(n)
/// rather than O(n²) for large process trees.
private struct ExportableTimelineView: View {
    let timeline: Timeline
    let pixelsPerSecond: Double
    let rowHeight: CGFloat

    private let rowPadding: CGFloat = 4

    init(timeline: Timeline, pixelsPerSecond: Double, rowHeight: CGFloat = 36) {
        self.timeline = timeline
        self.pixelsPerSecond = pixelsPerSecond
        self.rowHeight = rowHeight
    }

    var body: some View {
        let rows = flatRows
        ZStack(alignment: .topLeading) {
            Color(nsColor: .controlBackgroundColor)

            TimeRulerView(totalDuration: timeline.totalDuration, pixelsPerSecond: pixelsPerSecond)

            VStack(alignment: .leading, spacing: rowPadding) {
                ForEach(rows, id: \.node.id) { row in
                    HStack(spacing: 0) {
                        Spacer().frame(width: CGFloat(row.depth) * 16)
                        Spacer().frame(width: max(0, CGFloat((row.node.startTime - timeline.startTime) * pixelsPerSecond)))
                        ProcessBoxView(
                            node: row.node,
                            pixelsPerSecond: pixelsPerSecond,
                            isSelected: false,
                            alwaysShowLabel: true,
                            onSelect: {}
                        )
                        Spacer()
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            .padding(.trailing, 20)
        }
        .fixedSize()
    }

    // MARK: - Flat layout helpers

    private struct FlatRow {
        let node: ProcessNode
        let depth: Int
    }

    private var flatRows: [FlatRow] {
        var result: [FlatRow] = []
        flatten(timeline.rootNode, depth: 0, into: &result)
        return result
    }

    private func flatten(_ node: ProcessNode, depth: Int, into result: inout [FlatRow]) {
        result.append(FlatRow(node: node, depth: depth))
        for child in node.children {
            flatten(child, depth: depth + 1, into: &result)
        }
    }
}


