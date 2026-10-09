// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LFCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LFKit", targets: ["LFKit"]),
        .executable(name: "lfgit", targets: ["lfgit"]),
        .executable(name: "lf-bench", targets: ["lf-bench"]),
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
        // All lfgit commands live in a library so they can be unit-tested in-process.
        .target(
            name: "LFGitCLI",
            dependencies: [
                "LFKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "lfgit",
            dependencies: ["LFGitCLI"]
        ),
        .executableTarget(
            name: "lf-bench",
            dependencies: ["LFKit"]
        ),
        // Helpers for the test suites only (temporary directories, a realistic Xcode project generator).
        .target(
            name: "LFTestSupport",
            path: "Sources/LFTestSupport"
        ),
        .testTarget(
            name: "LFCoreTests",
            dependencies: ["LFCore", "LFKit", "LFTestSupport"],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "LFGitCLITests",
            dependencies: ["LFGitCLI", "LFKit", "LFTestSupport"]
        ),
    ],
    cLanguageStandard: .c11
)
