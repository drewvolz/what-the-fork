// WTFApp/Views/ZoomControlsOverlay.swift
import SwiftUI

/// Floating zoom control panel shown in the bottom-right corner of the timeline.
struct ZoomControlsOverlay: View {
    @Binding var pixelsPerSecond: Double
    let totalDuration: TimeInterval
    let visibleWidth: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Button(action: zoomOut) {
                Image(systemName: "minus")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Zoom out")

            Text(zoomLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .center)

            Button(action: zoomIn) {
                Image(systemName: "plus")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Zoom in")

            Divider()
                .frame(height: 14)

            Button(action: zoomFit) {
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

    private func zoomOut() {
        pixelsPerSecond = max(10, pixelsPerSecond / 1.5)
    }

    private func zoomIn() {
        pixelsPerSecond = min(2000, pixelsPerSecond * 1.5)
    }

    private func zoomFit() {
        guard totalDuration > 0, visibleWidth > 0 else { return }
        pixelsPerSecond = max(10, min(2000, Double(visibleWidth) / totalDuration))
    }
}
