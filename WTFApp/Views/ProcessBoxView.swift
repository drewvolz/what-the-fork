// WTFApp/Views/ProcessBoxView.swift
import SwiftUI
import WTFCore

/// A single colored box representing a process in the timeline.
struct ProcessBoxView: View {
    let node: ProcessNode
    let pixelsPerSecond: Double
    let isSelected: Bool
    let isOnCriticalPath: Bool
    /// Seconds from build start to this process's start.
    let startTimeOffset: TimeInterval
    /// Seconds this process waited after its parent ended before starting (0 if concurrent).
    let waitTime: TimeInterval
    let onSelect: () -> Void

    @State private var isShowingTooltip = false

    init(node: ProcessNode, pixelsPerSecond: Double, isSelected: Bool,
         isOnCriticalPath: Bool = false,
         startTimeOffset: TimeInterval = 0,
         waitTime: TimeInterval = 0,
         onSelect: @escaping () -> Void) {
        self.node = node
        self.pixelsPerSecond = pixelsPerSecond
        self.isSelected = isSelected
        self.isOnCriticalPath = isOnCriticalPath
        self.startTimeOffset = startTimeOffset
        self.waitTime = waitTime
        self.onSelect = onSelect
    }

    private var width: CGFloat {
        let dur = (node.endTime ?? node.startTime + 0.05) - node.startTime
        return max(CGFloat(dur * pixelsPerSecond), 4)
    }

    var body: some View {
        let color = ProcessClassifier.color(for: node)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(isSelected ? 1.0 : 0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isSelected ? Color.white :
                            isOnCriticalPath ? Color(red: 1.0, green: 0.75, blue: 0.0) : Color.clear,
                            lineWidth: 2
                        )
                )
                .onTapGesture { onSelect(); isShowingTooltip.toggle() }

            // Label: always visible at natural width (never truncated).
            // Wide bars (≥40px): label starts inside bar in white, overflows right.
            // Narrow bars (<40px): label starts just right of the bar in the node color.
            Text(labelString)
                .font(.system(size: width >= 40 ? 10 : 9, weight: .medium))
                .foregroundStyle(width >= 40 ? Color.white : color)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, width >= 40 ? 4 : width + 3)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: 32)
        .popover(isPresented: $isShowingTooltip) {
            tooltipView
        }
    }

    // MARK: - Tooltip

    private var tooltipView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(node.displayName)
                .font(.system(size: 12, weight: .semibold))
                .padding(.bottom, 6)

            Divider()
                .padding(.bottom, 6)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Duration").foregroundStyle(.secondary)
                    Text(formattedDuration).fontWeight(.medium)
                }
                GridRow {
                    Text("Started at").foregroundStyle(.secondary)
                    Text(formatInterval(startTimeOffset))
                }
                GridRow {
                    Text("Category").foregroundStyle(.secondary)
                    Text(ProcessClassifier.classify(node).label)
                }
                if waitTime > 0.001 {
                    GridRow {
                        Text("Waited").foregroundStyle(.secondary)
                        Text(formatInterval(waitTime))
                            .foregroundStyle(.orange)
                    }
                }
                if isOnCriticalPath {
                    GridRow {
                        Text("Critical path").foregroundStyle(.secondary)
                        Label("Yes", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .font(.system(size: 11))
        }
        .padding(10)
        .frame(minWidth: 180)
    }

    // MARK: - Helpers

    private var labelString: String {
        if width >= 120 { return "\(node.displayName) — \(formattedDuration)" }
        return node.displayName
    }

    private var formattedDuration: String {
        guard let dur = node.duration else { return "…" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }

    private func formatInterval(_ t: TimeInterval) -> String {
        t >= 1 ? String(format: "%.2fs", t) : String(format: "%.0fms", t * 1000)
    }
}
