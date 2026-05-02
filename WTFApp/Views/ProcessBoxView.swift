// WTFApp/Views/ProcessBoxView.swift
import SwiftUI
import WTFCore

/// A single colored box representing a process in the timeline.
struct ProcessBoxView: View {
    let node: ProcessNode
    let category: ProcessCategory
    let pixelsPerSecond: Double
    let isSelected: Bool
    let onSelect: () -> Void

    private var width: CGFloat {
        let dur = (node.endTime ?? node.startTime + 0.05) - node.startTime
        return max(CGFloat(dur * pixelsPerSecond), 4)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(category.color.opacity(isSelected ? 1.0 : 0.75))
            .frame(width: width, height: 22)
            .overlay(
                Text(node.commandName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 3),
                alignment: .leading
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .onTapGesture(perform: onSelect)
            .help("\(node.commandName) — \(formattedDuration)")
    }

    private var formattedDuration: String {
        guard let dur = node.duration else { return "running" }
        return dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }
}
