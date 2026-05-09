// WTFApp/Helpers/WindowTabbingConfigurator.swift
import SwiftUI
import AppKit

/// Invisible NSView that configures its host window to prefer tab mode.
/// Apply via .background(WindowTabbingConfigurator()) on any root view.
struct WindowTabbingConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.tabbingMode = .preferred
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
