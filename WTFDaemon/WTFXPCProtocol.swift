// WTFDaemon/WTFXPCProtocol.swift
import Foundation

/// The XPC protocol the daemon exposes to the app.
@objc protocol WTFDaemonXPCProtocol {
    /// Start monitoring descendants of the given PID for this session.
    func startSession(id: String, rootPID: Int32, withReply reply: @escaping (Bool) -> Void)
    /// Register a listener for events in the given session.
    func subscribeToSession(id: String, withReply reply: @escaping (NSData?) -> Void)
}
