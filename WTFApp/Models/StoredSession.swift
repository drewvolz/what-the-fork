// WTFApp/Models/StoredSession.swift
import Foundation
import WTFCore

/// A completed build session persisted to disk.
struct StoredSession: Codable, Identifiable {
    let id: UUID
    let commandName: String
    let duration: TimeInterval
    let parallelismScore: Double
    let timestamp: Date
    let rootPID: Int
    let events: [ProcessEvent]
}
