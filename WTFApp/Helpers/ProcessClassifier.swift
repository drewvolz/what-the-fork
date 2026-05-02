// WTFApp/Helpers/ProcessClassifier.swift
import SwiftUI
import WTFCore

/// Maps a process command name to a visual category for color coding.
enum ProcessCategory {
    case buildSystem
    case compiler
    case linker
    case shell
    case other

    var color: Color {
        switch self {
        case .buildSystem: return .blue
        case .compiler:    return .green
        case .linker:      return Color(red: 0.9, green: 0.7, blue: 0.1)  // gold/yellow
        case .shell:       return .gray
        case .other:       return Color(white: 0.75)
        }
    }

    var label: String {
        switch self {
        case .buildSystem: return "Build System"
        case .compiler:    return "Compiler"
        case .linker:      return "Linker"
        case .shell:       return "Shell"
        case .other:       return "Other"
        }
    }
}

enum ProcessClassifier {
    private static let buildSystems: Set<String> = [
        "make", "gmake", "cmake", "ninja", "cargo", "gradle", "bazel",
        "xcodebuild", "swift", "npm", "yarn", "pnpm", "mvn", "ant", "sbt", "buck2"
    ]
    private static let compilers: Set<String> = [
        "clang", "clang++", "gcc", "g++", "swiftc", "rustc", "cc", "c++",
        "javac", "kotlinc", "scalac", "tsc", "go"
    ]
    private static let linkers: Set<String> = [
        "ld", "lld", "gold", "mold", "link"
    ]
    private static let shells: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "csh"
    ]

    static func classify(_ node: ProcessNode) -> ProcessCategory {
        let name = node.commandName.lowercased()
        if buildSystems.contains(name) { return .buildSystem }
        if compilers.contains(name)    { return .compiler }
        if linkers.contains(name)      { return .linker }
        if shells.contains(name)       { return .shell }
        return .other
    }

    /// Returns the display color for a node — uses category color for known types,
    /// and a stable hash-derived color for "other" processes.
    static func color(for node: ProcessNode) -> Color {
        let category = classify(node)
        guard category == .other else { return category.color }
        return hashColor(for: node.commandName.lowercased())
    }

    private static func hashColor(for name: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.55, green: 0.36, blue: 0.96),  // purple
            Color(red: 0.13, green: 0.70, blue: 0.70),  // teal
            Color(red: 0.93, green: 0.40, blue: 0.40),  // coral
            Color(red: 0.20, green: 0.65, blue: 0.85),  // sky blue
            Color(red: 0.93, green: 0.60, blue: 0.10),  // amber
            Color(red: 0.85, green: 0.35, blue: 0.70),  // pink
            Color(red: 0.45, green: 0.80, blue: 0.30),  // lime
            Color(red: 0.93, green: 0.55, blue: 0.20),  // orange
        ]
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[Int(hash.magnitude) % palette.count]
    }
}
