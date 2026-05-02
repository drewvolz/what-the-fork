// WTFApp/Models/SessionManager.swift
import Foundation
import Combine
import WTFCore

/// Owns the collection of sessions, one per wtf run. Always keeps at least one session.
final class SessionManager: ObservableObject {
    @Published var sessions: [NamedSession]
    @Published var selectedID: UUID

    private var sessionCancellables: [UUID: AnyCancellable] = [:]

    init() {
        let initial = NamedSession()
        sessions = [initial]
        selectedID = initial.id
        observe(initial)
    }

    /// Creates a new session, starts capture on it, and selects it.
    func addSession(sessionID: String, rootPID: Int) {
        let named = NamedSession()
        sessions.append(named)
        selectedID = named.id
        observe(named)
        named.session.startCapture(sessionID: sessionID, rootPID: rootPID)
    }

    /// Removes a session. Always keeps at least one (inserts a fresh idle session if needed).
    func removeSession(id: UUID) {
        sessionCancellables.removeValue(forKey: id)
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let fresh = NamedSession()
            sessions = [fresh]
            selectedID = fresh.id
            observe(fresh)
        } else if !sessions.contains(where: { $0.id == selectedID }) {
            selectedID = sessions[sessions.count - 1].id
        }
    }

    private func observe(_ named: NamedSession) {
        sessionCancellables[named.id] = named.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
}
