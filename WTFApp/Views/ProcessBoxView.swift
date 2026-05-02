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
                .onTapGesture(perform: onSelect)

            // Label: always visible at natural width (never truncated).
            // Wide bars (≥40px): label starts inside bar in white, overflows right.
            // Narrow bars (<40px): label starts just right of the bar in the node color.
            // Matches SVG export behavior (clip-path="url(none)").
            Text(labelString)
                .font(.system(size: width >= 40 ? 10 : 9, weight: .medium))
                .foregroundStyle(width >= 40 ? Color.white : color)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, width >= 40 ? 4 : width + 3)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: 32)
        .help("\(node.displayName) — \(formattedDuration)")
    }

    private var labelString: String {
        if width >= 120 { return "\(node.displayName) — \(formattedDuration)" }
        return node.displayName
    }

    private var formattedDuration: String {
        guard let dur = node.duration else { return "…" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }
}
