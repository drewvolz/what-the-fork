// WTFApp/Views/ContentView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WTFCore

struct ContentView: View {
    @StateObject private var manager = SessionManager()
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var launchQueue: SessionLaunchQueue
    @EnvironmentObject var restoreQueue: RestoreQueue
    @Environment(\.openWindow) var openWindow

    @State private var hasStarted = false

    var body: some View {
        SessionView(named: manager.named)
            .background(WindowTabbingConfigurator())
            .navigationTitle(manager.named.label)
            .onAppear {
                guard !hasStarted else { return }
                hasStarted = true
                manager.beginAutoSave(store: store)
                if let req = launchQueue.pending {
                    launchQueue.pending = nil
                    manager.named.session.startCapture(
                        sessionID: req.sessionID,
                        rootPID: req.rootPID
                    )
                } else if let stored = restoreQueue.pending {
                    restoreQueue.pending = nil
                    manager.named.isRestored = true
                    manager.named.session.restore(
                        events: stored.events,
                        rootPID: stored.rootPID
                    )
                }
            }
            .onOpenURL { handleIncomingURL($0) }
    }

    private func handleIncomingURL(_ url: URL) {
        guard
            url.scheme == "whatthefork",
            url.host == "session",
            let sessionID = url.pathComponents.dropFirst().first,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let pidStr = components.queryItems?.first(where: { $0.name == "rootPID" })?.value,
            let rootPID = Int(pidStr)
        else { return }

        launchQueue.pending = (sessionID: sessionID, rootPID: rootPID)
        openWindow(id: "session")
    }
}

// MARK: - Per-session view

struct SessionView: View {
    @ObservedObject var named: NamedSession

    @State private var selectedNode: ProcessNode?
    @State private var isExporting = false
    @State private var pixelsPerSecond: Double = 100.0

    private var criticalPathIDs: Set<Int> {
        Set(named.session.analysis?.criticalPath.map(\.id) ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            Group {
                switch named.session.state {
                case .idle:
                    idleView

                case .capturing:
                    capturingView

                case .complete:
                    if let timeline = named.session.timeline {
                        VSplitView {
                            TimelineView(
                                timeline: timeline,
                                selectedNode: $selectedNode,
                                pixelsPerSecond: $pixelsPerSecond,
                                criticalPathIDs: criticalPathIDs
                            )
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
    }

    // MARK: Toolbar

    private var toolbarView: some View {
        HStack {
            Text("What the Fork")
                .font(.headline)
            Spacer()
            if case .complete = named.session.state, let analysis = named.session.analysis {
                Label(
                    String(format: "Parallelism: %.0f%%", analysis.parallelismScore * 100),
                    systemImage: "cpu"
                )
                .foregroundStyle(analysis.parallelismScore < 0.3 ? .red : .secondary)
                .font(.subheadline)
            }
            if case .complete = named.session.state, named.session.timeline != nil {
                Button(action: exportTimeline) {
                    if isExporting {
                        Label("Exporting…", systemImage: "hourglass")
                            .font(.subheadline)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isExporting)
                .help("Export timeline as PNG")
            }
        }
    }

    // MARK: Content states

    private var idleView: some View {
        SessionHistoryView()
    }

    private var capturingView: some View {
        ZStack {
            if let live = named.session.liveTimeline {
                TimelineView(
                    timeline: live,
                    selectedNode: $selectedNode,
                    pixelsPerSecond: $pixelsPerSecond
                )
                .transition(.opacity)
                .overlay(alignment: .top) {
                    capturingBadge
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Capturing build…")
                        .foregroundStyle(.secondary)
                    if !named.session.liveEvents.isEmpty {
                        Text("\(named.session.liveEvents.count) events received")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: named.session.liveTimeline != nil)
    }

    private var capturingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("Capturing — \(named.session.liveEvents.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .clipShape(Capsule())
        .padding(.top, 30)
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

    // MARK: Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        HSplitView {
            ProcessDetailPanel(node: selectedNode)
                .frame(minWidth: 250)
            if let analysis = named.session.analysis, let timeline = named.session.timeline {
                let concurrencyPoints = ConcurrencyComputer.compute(
                    processes: timeline.allProcesses,
                    startTime: timeline.startTime,
                    totalDuration: timeline.totalDuration
                )
                ConcurrencyChartView(
                    points: concurrencyPoints,
                    totalDuration: timeline.totalDuration,
                    peak: ConcurrencyComputer.peak(concurrencyPoints)
                )
                .frame(minWidth: 150)
                AnalysisPanel(analysis: analysis)
                    .frame(minWidth: 250)
            }
        }
    }

    // MARK: Export

    private func exportTimeline() {
        guard let timeline = named.session.timeline else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            let exportPPS = pixelsPerSecond
            let cpIDs = criticalPathIDs
            guard let svgData = TimelineExporter.render(
                timeline: timeline,
                pixelsPerSecond: exportPPS,
                criticalPathIDs: cpIDs
            ) else { return }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.svg]
            panel.nameFieldStringValue = "build-timeline.svg"
            panel.directoryURL = FileManager.default
                .urls(for: .desktopDirectory, in: .userDomainMask).first
            panel.title = "Export Timeline"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? svgData.write(to: url)
        }
    }
}


