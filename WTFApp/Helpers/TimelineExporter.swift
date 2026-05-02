// WTFApp/Helpers/TimelineExporter.swift
import Foundation
import WTFCore

/// Renders the full process timeline to an SVG document for export.
/// Pure string-building — no rendering framework, no SwiftUI, no pixel limits.
@MainActor
enum TimelineExporter {

    // MARK: - Public API

    /// Builds an SVG document from the timeline and returns UTF-8 data.
    static func render(timeline: Timeline, pixelsPerSecond: Double) -> Data? {
        guard timeline.totalDuration > 0 else { return nil }

        let rowH: Double    = 28
        let rowGap: Double  = 4
        let rulerH: Double  = 24
        let indent: Double  = 16
        let leftPad: Double = 8
        let rightPad: Double = 20

        var rows: [(node: ProcessNode, depth: Int)] = []
        dfs(timeline.rootNode, depth: 0, into: &rows)

        let svgW = leftPad + timeline.totalDuration * pixelsPerSecond + rightPad
        let svgH = rulerH + Double(rows.count) * (rowH + rowGap) + 8

        var out: [String] = []
        out.reserveCapacity(rows.count * 2 + 20)

        out.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        out.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(svgW.svgPt)\" height=\"\(svgH.svgPt)\">")
        out.append("  <rect width=\"\(svgW.svgPt)\" height=\"\(svgH.svgPt)\" fill=\"#141414\"/>")

        // Time ruler
        let step = tickStep(for: pixelsPerSecond)
        var t = 0.0
        while t <= timeline.totalDuration + step * 0.01 {
            let x = (leftPad + t * pixelsPerSecond).svgPt
            let lx = (leftPad + t * pixelsPerSecond + 2).svgPt
            out.append("  <line x1=\"\(x)\" y1=\"18\" x2=\"\(x)\" y2=\"\(rulerH.svgPt)\" stroke=\"#555\" stroke-width=\"1\"/>")
            out.append("  <text x=\"\(lx)\" y=\"13\" font-family=\"-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif\" font-size=\"9\" fill=\"#888\">\(tickLabel(t))</text>")
            t += step
        }

        // Node rows
        for (i, (node, depth)) in rows.enumerated() {
            let dur = (node.endTime ?? node.startTime + 0.05) - node.startTime
            let x   = leftPad + Double(depth) * indent + (node.startTime - timeline.startTime) * pixelsPerSecond
            let y   = rulerH + Double(i) * (rowH + rowGap)
            let w   = max(4.0, dur * pixelsPerSecond)
            let fill = svgColor(for: node)

            out.append("  <rect x=\"\(x.svgPt)\" y=\"\(y.svgPt)\" width=\"\(w.svgPt)\" height=\"\(rowH.svgPt)\" rx=\"3\" fill=\"\(fill)\"/>")

            // Label truncated to fit inside box (~6.2px per char at font-size 10)
            let maxChars = max(0, Int(w / 6.2) - 1)
            if maxChars >= 2 {
                let raw = w >= 120
                    ? "\(node.commandName) — \(durationLabel(dur))"
                    : node.commandName
                let label = xmlEscape(String(raw.prefix(maxChars)))
                let ty = (y + rowH * 0.68).svgPt
                out.append("  <text x=\"\((x + 4).svgPt)\" y=\"\(ty)\" font-family=\"-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif\" font-size=\"10\" font-weight=\"500\" fill=\"white\">\(label)</text>")
            }
        }

        out.append("</svg>")
        return out.joined(separator: "\n").data(using: .utf8)
    }

    // MARK: - Tree traversal

    private static func dfs(_ node: ProcessNode, depth: Int,
                             into rows: inout [(node: ProcessNode, depth: Int)]) {
        rows.append((node, depth))
        for child in node.children {
            dfs(child, depth: depth + 1, into: &rows)
        }
    }

    // MARK: - Ruler helpers

    private static func tickStep(for pps: Double) -> Double {
        let target = 100.0 / pps
        let steps: [Double] = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60]
        return steps.min { abs($0 - target) < abs($1 - target) } ?? 1
    }

    private static func tickLabel(_ t: Double) -> String {
        if t == 0 { return "0" }
        return t >= 1 ? String(format: "%.0fs", t) : String(format: "%.0fms", t * 1000)
    }

    private static func durationLabel(_ dur: Double) -> String {
        dur >= 1 ? String(format: "%.2fs", dur) : String(format: "%.0fms", dur * 1000)
    }

    // MARK: - SVG utilities

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Color mapping
    // Mirrors ProcessClassifier without importing SwiftUI.

    private static let buildSystems: Set<String> = [
        "make", "gmake", "cmake", "ninja", "cargo", "gradle", "bazel",
        "xcodebuild", "swift", "npm", "yarn", "pnpm", "mvn", "ant", "sbt", "buck2"
    ]
    private static let compilers: Set<String> = [
        "clang", "clang++", "gcc", "g++", "swiftc", "rustc", "cc", "c++",
        "javac", "kotlinc", "scalac", "tsc", "go"
    ]
    private static let linkers:  Set<String> = ["ld", "lld", "gold", "mold", "link"]
    private static let shells:   Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "csh"]

    private static func svgColor(for node: ProcessNode) -> String {
        let name = node.commandName.lowercased()
        if buildSystems.contains(name) { return "#3B82F6" }  // blue
        if compilers.contains(name)    { return "#22C55E" }  // green
        if linkers.contains(name)      { return "#E6B31A" }  // gold
        if shells.contains(name)       { return "#6B7280" }  // gray
        return hashColor(name)
    }

    private static let hashPalette: [String] = [
        "#8C5CF5",  // purple
        "#21B2B2",  // teal
        "#ED6666",  // coral
        "#33A6D9",  // sky blue
        "#ED991A",  // amber
        "#D959B3",  // pink
        "#73CC4D",  // lime
        "#ED8C33",  // orange
    ]

    private static func hashColor(_ name: String) -> String {
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return hashPalette[Int(hash.magnitude) % hashPalette.count]
    }
}

// MARK: - SVG formatting

private extension Double {
    /// Compact SVG coordinate string: integer when whole, 2 decimals otherwise.
    var svgPt: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(format: "%.2f", self)
    }
}
