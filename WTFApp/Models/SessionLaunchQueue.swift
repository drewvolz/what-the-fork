// WTFApp/Models/SessionLaunchQueue.swift
import Foundation

/// One-shot queue that carries a pending CLI launch request to the next
/// window that appears. Cleared immediately after the window consumes it.
@MainActor
final class SessionLaunchQueue: ObservableObject {
    @Published var pending: (sessionID: String, rootPID: Int)? = nil
}
