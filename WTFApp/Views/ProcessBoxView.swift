// WTFApp/Views/ProcessBoxView.swift
import SwiftUI
import WTFCore

/// A single colored box representing a process in the timeline.
struct ProcessBoxView: View {
    let node: ProcessNode
    let pixelsPerSecond: Double
    let isSelected: Bool
    let isOnCriticalPath: Bool
    let alwaysShowLabel: Bool
    let onSelect: () -> Void

    init(node: ProcessNode, pixelsPerSecond: Double, isSelected: Bool,
         isOnCriticalPath: Bool = false, alwaysShowLabel: Bool = false,
         onSelect: @escaping () -> Void) {
        self.node = node
        self.pixelsPerSecond = pixelsPerSecond
        self.isSelected = isSelected
        self.isOnCriticalPath = isOnCriticalPath
        self.alwaysShowLabel = alwaysShowLabel
        self.onSelect = onSelect
    }

    private var width: CGFloat {
        let dur = (node.endTime ?? node.startTime + 0.05) - node.startTime
        return max(CGFloat(dur * pixelsPerSecond), 4)
    }

    var body: some View {
        let color = ProcessClassifier.color(for: node)
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(isSelected ? 1.0 : 0.75))
            .frame(width: width, height: 32)
            .overlay(labelOverlay, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        isSelected ? Color.white :
                        isOnCriticalPath ? Color(red: 1.0, green: 0.75, blue: 0.0) : Color.clear,
                        lineWidth: isSelected ? 2 : 2
                    )
            )
            .onTapGesture(perform: onSelect)
            .help("\(node.displayName) — \(formattedDuration)")
    }

    @ViewBuilder
    private var labelOverlay: some View {
        if let label = labelText(for: width) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
    }

    private func labelText(for width: CGFloat) -> String? {
        guard alwaysShowLabel || width >= 8 else { return nil }
        if width >= 120 { return "\(node.displayName) — \(formattedDuration)" }
        return node.displayName
    }

    private var formattedDuration: String {
        guard let dur = node.duration else { return "…" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }
}
