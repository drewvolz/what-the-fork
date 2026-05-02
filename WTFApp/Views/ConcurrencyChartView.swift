// WTFApp/Views/ConcurrencyChartView.swift
import SwiftUI
import WTFCore

/// Filled area chart showing how many processes ran simultaneously over time.
/// X axis matches the timeline's time scale; Y axis is active process count.
struct ConcurrencyChartView: View {
    let points: [ConcurrencyComputer.Point]
    let totalDuration: TimeInterval
    let peak: Int

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard points.count >= 2, peak > 0 else { return }

                let w = size.width
                let h = size.height
                let chartH = h - 20  // leave bottom margin for axis labels

                func xFor(_ t: TimeInterval) -> CGFloat {
                    CGFloat(t / totalDuration) * w
                }
                func yFor(_ count: Int) -> CGFloat {
                    chartH - CGFloat(count) / CGFloat(peak) * chartH
                }

                // Build filled path
                var path = Path()
                path.move(to: CGPoint(x: xFor(points[0].relativeTime), y: chartH))
                for p in points {
                    path.addLine(to: CGPoint(x: xFor(p.relativeTime), y: yFor(p.count)))
                }
                path.addLine(to: CGPoint(x: xFor(points.last!.relativeTime), y: chartH))
                path.closeSubpath()

                ctx.fill(path, with: .color(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.35)))

                // Build stroke path (top edge only)
                var stroke = Path()
                stroke.move(to: CGPoint(x: xFor(points[0].relativeTime), y: yFor(points[0].count)))
                for p in points.dropFirst() {
                    stroke.addLine(to: CGPoint(x: xFor(p.relativeTime), y: yFor(p.count)))
                }
                ctx.stroke(stroke, with: .color(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.5))

                // Axis baseline
                let baseline = Path { p in
                    p.move(to: CGPoint(x: 0, y: chartH))
                    p.addLine(to: CGPoint(x: w, y: chartH))
                }
                ctx.stroke(baseline, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1))
            }
            .overlay(alignment: .topLeading) {
                Text("Peak: \(peak)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 2)
            }
            .overlay(alignment: .bottomLeading) {
                Text("Concurrency")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.bottom, 2)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
