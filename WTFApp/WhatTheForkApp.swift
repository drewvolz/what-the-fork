// WTFApp/WhatTheForkApp.swift
import SwiftUI
import AppKit

@main
struct WhatTheForkApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var launchQueue = SessionLaunchQueue()
    @StateObject private var restoreQueue = RestoreQueue()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    var body: some Scene {
        WindowGroup(id: "session") {
            ContentView()
                .environmentObject(store)
                .environmentObject(launchQueue)
                .environmentObject(restoreQueue)
        }
    }
}
