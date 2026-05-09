// WTFApp/Models/SessionManager.swift
import Foundation
import Combine

final class SessionManager: ObservableObject {
    let named = NamedSession()

    private var namedCancellable: AnyCancellable?
    private var completionCancellable: AnyCancellable?

    init() {
        namedCancellable = named.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Call once per window after the SessionStore environment object is available.
    func beginAutoSave(store: SessionStore) {
        completionCancellable = named.session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, case .complete = state, !self.named.isRestored else { return }
                store.save(named: self.named)
            }
    }
}
