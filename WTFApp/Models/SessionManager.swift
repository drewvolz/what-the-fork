// WTFApp/Models/SessionManager.swift
import Foundation
import Combine
import WTFCore

final class SessionManager: ObservableObject {
    @Published var sessions: [NamedSession]
    @Published var selectedID: UUID
    let store = SessionStore()

    private var sessionCancellables: [UUID: AnyCancellable] = [:]
    private var completionCancellables: [UUID: AnyCancellable] = [:]

    init() {
        let initial = NamedSession()
        sessions = [initial]
        selectedID = initial.id
        observe(initial)
    }

    func addSession(sessionID: String, rootPID: Int) {
        let named = NamedSession()
        sessions.append(named)
        selectedID = named.id
        observe(named)
        named.session.startCapture(sessionID: sessionID, rootPID: rootPID)
    }

    func removeSession(id: UUID) {
        sessionCancellables.removeValue(forKey: id)
        completionCancellables.removeValue(forKey: id)
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

        completionCancellables[named.id] = named.session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, case .complete = state, !named.isRestored else { return }
                self.store.save(named: named)
            }
    }
}
