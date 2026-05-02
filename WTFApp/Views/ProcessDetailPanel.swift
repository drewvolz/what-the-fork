// WTFApp/Views/ProcessDetailPanel.swift
import SwiftUI
import WTFCore

struct ProcessDetailPanel: View {
    let node: ProcessNode?

    var body: some View {
        Group {
            if let node {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow("Command", value: node.command)

                        if !node.args.isEmpty {
                            detailRow("Arguments", value: node.args.joined(separator: " "))
                        }

                        detailRow("PID", value: "\(node.id)")
                        detailRow("Directory", value: node.cwd.isEmpty ? "—" : node.cwd)

                        if let duration = node.duration {
                            detailRow("Duration", value: duration >= 1
                                ? String(format: "%.3fs", duration)
                                : String(format: "%.0fms", duration * 1000))
                        } else {
                            detailRow("Duration", value: "Running…")
                        }

                        if let exitCode = node.exitCode {
                            detailRow("Exit Code", value: "\(exitCode)",
                                      valueColor: exitCode == 0 ? .green : .red)
                        }

                        detailRow("Children", value: "\(node.children.count)")
                    }
                    .padding(12)
                }
            } else {
                Text("Select a process to see details")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
    }
}
