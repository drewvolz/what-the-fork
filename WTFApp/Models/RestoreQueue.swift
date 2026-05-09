// WTFApp/Models/RestoreQueue.swift
import Foundation

/// One-shot queue that carries a pending restore request to the next
/// window that appears. Cleared immediately after the window consumes it.
@MainActor
final class RestoreQueue: ObservableObject {
    @Published var pending: StoredSession? = nil
}
