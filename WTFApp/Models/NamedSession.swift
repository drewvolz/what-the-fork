// WTFApp/Models/NamedSession.swift
import Foundation
import Combine
import WTFCore

/// Wraps a BuildSession with a display label that reflects the session's current state.
final class NamedSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var label: String = "New Session"
    let session: BuildSession

    private var cancellable: AnyCancellable?

    init() {
        session = BuildSession()
        cancellable = session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle:
                    self.label = "New Session"
                case .capturing:
                    self.label = "Capturing…"
                case .complete:
                    self.label = self.session.timeline?.rootNode.commandName ?? "Complete"
                case .failed:
                    self.label = "Error"
                }
            }
    }

    /// Icon name reflecting the session's current state, for use in tab items.
    var systemImageName: String {
        switch session.state {
        case .idle:      return "circle"
        case .capturing: return "record.circle.fill"
        case .complete:  return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.circle.fill"
        }
    }
}
