// WTFApp/WhatTheForkApp.swift
import SwiftUI
import AppKit

@main
struct WhatTheForkApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        Window("What the Fork", id: "main") {
            RootView()
                .environmentObject(store)
        }
    }
}
