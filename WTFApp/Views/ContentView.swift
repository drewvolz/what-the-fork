// WTFApp/Views/ContentView.swift
import SwiftUI
import WTFCore
// import panels are not needed; SwiftUI will find them in same target

struct ContentView: View {
    @StateObject private var session = BuildSession()
    @State private var selectedNode: ProcessNode?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            Group {
                switch session.state {
                case .idle:
                    idleView

                case .capturing:
                    capturingView

                case .complete:
                    if let timeline = session.timeline {
                        VSplitView {
                            TimelineView(timeline: timeline, selectedNode: $selectedNode)
                                .frame(minHeight: 200)
                            bottomPanel
                                .frame(minHeight: 120, maxHeight: 300)
                        }
                    }

                case .failed(let msg):
                    errorView(msg)
                }
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
    }

    private var toolbarView: some View {
        HStack {
            Image(systemName: "fork.knife")
                .foregroundStyle(.secondary)
            Text("What the Fork")
                .font(.headline)
            Spacer()
            if case .complete = session.state, let analysis = session.analysis {
                Label(
                    String(format: "Parallelism: %.0f%%", analysis.parallelismScore * 100),
                    systemImage: "cpu"
                )
                .foregroundStyle(analysis.parallelismScore < 0.3 ? .red : .secondary)
                .font(.subheadline)
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Run a build with `wtf <command>` to visualize it here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capturingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Capturing build…")
                .foregroundStyle(.secondary)
            if !session.liveEvents.isEmpty {
                Text("\(session.liveEvents.count) events received")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        HSplitView {
            ProcessDetailPanel(node: selectedNode)
                .frame(minWidth: 250)
            if let analysis = session.analysis {
                AnalysisPanel(analysis: analysis)
                    .frame(minWidth: 250)
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // Expected: whatthefork://session/<sessionID>?rootPID=<pid>
        guard
            url.scheme == "whatthefork",
            url.host == "session",
            let sessionID = url.pathComponents.dropFirst().first,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let pidStr = components.queryItems?.first(where: { $0.name == "rootPID" })?.value,
            let rootPID = Int(pidStr)
        else { return }

        session.startCapture(sessionID: sessionID, rootPID: rootPID)
    }
}


