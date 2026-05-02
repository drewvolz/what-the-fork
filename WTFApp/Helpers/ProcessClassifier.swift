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
}
