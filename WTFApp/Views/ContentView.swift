// WTFApp/Views/ContentView.swift
import SwiftUI
import WTFCore

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
                    if !session.liveEvents.isEmpty, let partialRoot = partialTimeline {
                        TimelineView(timeline: partialRoot, selectedNode: $selectedNode)
                    } else {
                        capturingView
                    }

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
            Text("Capturing build...")
                .foregroundStyle(.secondary)
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

    // Build a partial timeline from live events for live preview
    private var partialTimeline: Timeline? {
        guard let rootPID = session.rootPID,
              let firstEvent = session.liveEvents.first else { return nil }
        let root = TreeBuilder.buildTree(from: session.liveEvents, rootPID: rootPID)
        let now = Date().timeIntervalSince1970
        let duration = now - firstEvent.timestamp
        return Timeline(rootNode: root, startTime: firstEvent.timestamp, totalDuration: max(duration, 0.1))
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

// Placeholder stubs — replaced by full implementations in Task 14
struct ProcessDetailPanel: View {
    let node: ProcessNode?
    var body: some View { EmptyView() }
}

struct AnalysisPanel: View {
    let analysis: BuildAnalysis
    var body: some View { EmptyView() }
}
