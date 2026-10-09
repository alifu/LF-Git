// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LFCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LFKit", targets: ["LFKit"]),
        .executable(name: "lfgit", targets: ["lfgit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // C11 engine: no Foundation, no third-party dependencies.
        .target(name: "LFCore"),
        // Safe Swift wrapper over the C API, consumed by the app and the CLI.
        .target(
            name: "LFKit",
            dependencies: ["LFCore"]
        ),
        .executableTarget(
            name: "lfgit",
            dependencies: [
                "LFKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "LFCoreTests",
            dependencies: ["LFCore", "LFKit"]
        ),
    ],
    cLanguageStandard: .c11
)
