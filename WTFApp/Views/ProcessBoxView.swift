// WTFApp/Views/ProcessBoxView.swift
import SwiftUI
import WTFCore

// MARK: - Tooltip preference key

struct TooltipAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - Tooltip card

/// Floating detail card shown above a node when the user taps it.
struct NodeTooltipCard: View {
    let node: ProcessNode
    let startTimeOffset: TimeInterval
    let waitTime: TimeInterval
    let isOnCriticalPath: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
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

    private var formattedDuration: String {
        guard let dur = node.duration else { return "…" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }

    private func formatInterval(_ t: TimeInterval) -> String {
        t >= 1 ? String(format: "%.2fs", t) : String(format: "%.0fms", t * 1000)
    }
}

// MARK: - Process box

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

    @Binding var isTooltipVisible: Bool

    init(node: ProcessNode, pixelsPerSecond: Double, isSelected: Bool,
         isOnCriticalPath: Bool = false,
         startTimeOffset: TimeInterval = 0,
         waitTime: TimeInterval = 0,
         isTooltipVisible: Binding<Bool> = .constant(false),
         onSelect: @escaping () -> Void) {
        self.node = node
        self.pixelsPerSecond = pixelsPerSecond
        self.isSelected = isSelected
        self.isOnCriticalPath = isOnCriticalPath
        self.startTimeOffset = startTimeOffset
        self.waitTime = waitTime
        self._isTooltipVisible = isTooltipVisible
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
                .onTapGesture { onSelect(); isTooltipVisible.toggle() }

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
        // Report this box's frame when the tooltip is active so TimelineView can
        // render the card outside the scroll view (avoiding z-order and clip issues).
        .anchorPreference(key: TooltipAnchorKey.self, value: .bounds) {
            isTooltipVisible ? $0 : nil
        }
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
}
