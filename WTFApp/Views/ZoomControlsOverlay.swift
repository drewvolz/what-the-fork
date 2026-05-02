// WTFApp/Views/ZoomControlsOverlay.swift
import SwiftUI

/// Floating zoom control panel shown in the bottom-right corner of the timeline.
/// Zoom actions are delegated via callbacks so the caller can perform anchor-preserving scroll.
struct ZoomControlsOverlay: View {
    let pixelsPerSecond: Double
    let totalDuration: TimeInterval
    let visibleWidth: CGFloat
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomFit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onZoomOut) {
                Image(systemName: "minus")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Zoom out")

            Text(zoomLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .center)

            Button(action: onZoomIn) {
                Image(systemName: "plus")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Zoom in")

            Divider()
                .frame(height: 14)

            Button(action: onZoomFit) {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Fit all")
            .disabled(totalDuration <= 0 || visibleWidth <= 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var zoomLabel: String { String(format: "%.0fpx/s", pixelsPerSecond) }
}
