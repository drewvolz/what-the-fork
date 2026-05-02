// WTFApp/Models/BuildSession.swift
import Foundation
import Combine
import WTFCore

/// Top-level state object that drives all views. Receives events from the XPC client,
/// builds the live process tree, and computes analysis when the build completes.
final class BuildSession: ObservableObject {
    enum State {
        case idle
        case capturing
        case complete
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var timeline: Timeline?
    @Published var analysis: BuildAnalysis?
    @Published var liveEvents: [ProcessEvent] = []
    @Published private(set) var rootPID: Int?

    private var xpcClient: XPCEventClient?

    /// Start receiving events for a session.
    func startCapture(sessionID: String, rootPID: Int) {
        self.rootPID = rootPID
        state = .capturing
        liveEvents = []

        let client = XPCEventClient(sessionID: sessionID)
        client.onEvent = { [weak self] event in
            self?.liveEvents.append(event)
        }
        client.onSessionComplete = { [weak self] in
            self?.finalize()
        }
        xpcClient = client
        client.connect()
    }

    private func finalize() {
        guard let rootPID else {
            state = .failed("No session started")
            return
        }

        guard !liveEvents.isEmpty else {
            // ESF may be unavailable (SIP enabled) — transition to complete with empty data
            state = .failed("No events received — is SIP disabled? See README.")
            return
        }

        let root = TreeBuilder.buildTree(from: liveEvents, rootPID: rootPID)
        guard let rootEnd = root.endTime else {
            state = .failed("Root process did not exit cleanly")
            return
        }

        let tl = Timeline(
            rootNode: root,
            startTime: root.startTime,
            totalDuration: rootEnd - root.startTime
        )

        let metrics = ParallelismAnalyzer.analyzeParallelism(tl)
        let gaps = GapDetector.detectGaps(tl)
        let criticalPath = CriticalPathFinder.findCriticalPath(root)
        let buildAnalysis = BuildAnalysis(
            parallelismScore: metrics.score,
            gaps: gaps,
            criticalPath: criticalPath,
            suggestions: []
        )
        let suggestions = SuggestionEngine.generateSuggestions(tl, buildAnalysis)
        let finalAnalysis = BuildAnalysis(
            parallelismScore: metrics.score,
            gaps: gaps,
            criticalPath: criticalPath,
            suggestions: suggestions
        )

        timeline = tl
        analysis = finalAnalysis
        state = .complete
        xpcClient?.disconnect()
    }
}
