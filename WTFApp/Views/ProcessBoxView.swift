// WTFApp/Views/ProcessBoxView.swift
import SwiftUI
import WTFCore

/// A single colored box representing a process in the timeline.
struct ProcessBoxView: View {
    let node: ProcessNode
    let pixelsPerSecond: Double
    let isSelected: Bool
    let isOnCriticalPath: Bool
    let onSelect: () -> Void

    init(node: ProcessNode, pixelsPerSecond: Double, isSelected: Bool,
         isOnCriticalPath: Bool = false,
         onSelect: @escaping () -> Void) {
        self.node = node
        self.pixelsPerSecond = pixelsPerSecond
        self.isSelected = isSelected
        self.isOnCriticalPath = isOnCriticalPath
        self.onSelect = onSelect
    }

    private var width: CGFloat {
        let dur = (node.endTime ?? node.startTime + 0.05) - node.startTime
        return max(CGFloat(dur * pixelsPerSecond), 4)
    }

    private let inlineThreshold: CGFloat = 40

    var body: some View {
        let color = ProcessClassifier.color(for: node)
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(isSelected ? 1.0 : 0.75))
                .frame(width: width, height: 32)
                .overlay(labelOverlay(color: color), alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isSelected ? Color.white :
                            isOnCriticalPath ? Color(red: 1.0, green: 0.75, blue: 0.0) : Color.clear,
                            lineWidth: 2
                        )
                )
                .onTapGesture(perform: onSelect)
                .help("\(node.displayName) — \(formattedDuration)")

            // Overflow label: shown when the bar is too narrow to hold text inside.
            // Mirrors SVG export behavior — label appears to the right in the node's color.
            if width < inlineThreshold {
                Text(node.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 3)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func labelOverlay(color: Color) -> some View {
        if let label = inlineLabelText(for: width) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
    }

    private func inlineLabelText(for width: CGFloat) -> String? {
        guard width >= inlineThreshold else { return nil }
        if width >= 120 { return "\(node.displayName) — \(formattedDuration)" }
        return node.displayName
    }

    private var formattedDuration: String {
        guard let dur = node.duration else { return "…" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }
}
