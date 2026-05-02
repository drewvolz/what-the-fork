// WTFApp/Views/AnalysisPanel.swift
import SwiftUI
import WTFCore

public struct AnalysisPanel: View {
    let analysis: BuildAnalysis

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Parallelism score
                VStack(alignment: .leading, spacing: 4) {
                    Label("Parallelism", systemImage: "cpu")
                        .font(.headline)
                    ProgressView(value: analysis.parallelismScore)
                        .tint(scoreColor)
                    Text(String(format: "%.0f%% average CPU utilization", analysis.parallelismScore * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Gaps
                if !analysis.gaps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Idle Gaps", systemImage: "clock.badge.exclamationmark")
                            .font(.headline)
                        ForEach(analysis.gaps.indices, id: \.self) { i in
                            let gap = analysis.gaps[i]
                            HStack {
                                Image(systemName: "pause.circle")
                                    .foregroundStyle(.orange)
                                Text(String(format: "%.1fs gap after %@",
                                            gap.duration,
                                            gap.precedingProcess?.commandName ?? "unknown"))
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                // Suggestions
                if !analysis.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Suggestions", systemImage: "lightbulb")
                            .font(.headline)
                        ForEach(analysis.suggestions.indices, id: \.self) { i in
                            suggestionRow(analysis.suggestions[i])
                        }
                    }
                }

                if analysis.gaps.isEmpty && analysis.suggestions.isEmpty {
                    Label("No issues found!", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var scoreColor: Color {
        switch analysis.parallelismScore {
        case 0.6...: return .green
        case 0.3...: return .yellow
        default:     return .red
        }
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: suggestionIcon(suggestion.category))
                .foregroundStyle(.orange)
                .frame(width: 20)
            Text(suggestion.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func suggestionIcon(_ category: Suggestion.Category) -> String {
        switch category {
        case .noParallelism:            return "arrow.left.arrow.right"
        case .unnecessaryRepeatedCalls: return "repeat.circle"
        case .longGap:                  return "clock.badge.exclamationmark"
        case .serialDependencies:       return "arrow.right"
        }
    }
}
