// wtf/AppLauncher.swift
import Foundation
import AppKit

/// Opens the WhatTheFork app and passes the session ID and root PID via URL scheme.
enum AppLauncher {
    static let urlScheme = "whatthefork"

    /// URL format: whatthefork://session/<id>?rootPID=<pid>
    static func openApp(sessionID: String, rootPID: pid_t) {
        let urlString = "\(urlScheme)://session/\(sessionID)?rootPID=\(rootPID)"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
