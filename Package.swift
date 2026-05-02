// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WTFCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WTFCore", targets: ["WTFCore"]),
    ],
    targets: [
        .target(name: "WTFCore", path: "Sources/WTFCore"),
        .testTarget(
            name: "WTFCoreTests",
            dependencies: ["WTFCore"],
            path: "Tests/WTFCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
