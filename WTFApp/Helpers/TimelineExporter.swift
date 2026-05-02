// WTFApp/Helpers/TimelineExporter.swift
import SwiftUI
import WTFCore

/// Renders the full process timeline to a PNG image for export.
@MainActor
enum TimelineExporter {
    /// Maximum width/height in pixels for a single export image dimension.
    private static let maxImageDimension: CGFloat = 16000

    /// Renders the full timeline tree to PNG data at the given zoom level.
    /// If the resulting width would exceed `maxImageDimension`, the zoom is
    /// reduced proportionally.
    static func render(timeline: Timeline, pixelsPerSecond: Double) -> Data? {
        guard timeline.totalDuration > 0 else { return nil }

        // Clamp pps so image width stays manageable.
        let rawWidth = CGFloat(timeline.totalDuration * pixelsPerSecond) + 80
        let scale = rawWidth > maxImageDimension ? maxImageDimension / rawWidth : 1.0
        let effectivePPS = pixelsPerSecond * scale

        let view = ExportableTimelineView(timeline: timeline, pixelsPerSecond: effectivePPS)

        if #available(macOS 13.0, *) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0  // @2x for crisp text
            guard let nsImage = renderer.nsImage else { return nil }
            return nsImage.pngData()
        } else {
            return nil
        }
    }
}

/// A non-scrolling, non-interactive view of the full timeline used for export.
private struct ExportableTimelineView: View {
    let timeline: Timeline
    let pixelsPerSecond: Double

    private let rowHeight: CGFloat = 36
    private let rowPadding: CGFloat = 4

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .controlBackgroundColor)

            TimeRulerView(totalDuration: timeline.totalDuration, pixelsPerSecond: pixelsPerSecond)

            VStack(alignment: .leading, spacing: rowPadding) {
                nodeRow(timeline.rootNode, depth: 0)
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            .padding(.trailing, 20)
        }
        .fixedSize()
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
                        isSelected: false,
                        alwaysShowLabel: true,
                        onSelect: {}
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

// MARK: - NSImage → PNG

private extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}
