// WTFApp/Models/SessionStore.swift
import Foundation
import WTFCore

/// Persists completed sessions as JSON files under
/// ~/Library/Application Support/WhatTheFork/sessions/.
final class SessionStore: ObservableObject {
    @Published var history: [StoredSession] = []

    private let sessionsDirectory: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        sessionsDirectory = appSupport
            .appendingPathComponent("WhatTheFork/sessions")
        try? FileManager.default.createDirectory(
            at: sessionsDirectory,
            withIntermediateDirectories: true
        )
        load()
    }

    func save(named: NamedSession) {
        guard
            case .complete = named.session.state,
            let commandName = named.session.timeline?.rootNode.commandName,
            let duration = named.session.timeline?.totalDuration,
            let rootPID = named.session.rootPID,
            let parallelismScore = named.session.analysis?.parallelismScore
        else { return }

        let stored = StoredSession(
            id: UUID(),
            commandName: commandName,
            duration: duration,
            parallelismScore: parallelismScore,
            timestamp: Date(),
            rootPID: rootPID,
            events: named.session.liveEvents
        )

        let url = sessionsDirectory.appendingPathComponent("\(stored.id).json")
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url)
        history.insert(stored, at: 0)
    }

    func delete(id: UUID) {
        let url = sessionsDirectory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
        history.removeAll { $0.id == id }
    }

    private func load() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        history = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(StoredSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.timestamp > $1.timestamp }
    }
}
