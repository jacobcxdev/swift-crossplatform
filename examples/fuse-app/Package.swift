// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "fuse-app",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FuseApp", type: .dynamic, targets: ["FuseApp"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.7.2"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
        // Skip forks
        .package(path: "../../forks/skip-android-bridge"),
        .package(path: "../../forks/skip-ui"),
        // Point-Free foundation forks
        .package(path: "../../forks/xctest-dynamic-overlay"),
        .package(path: "../../forks/swift-case-paths"),
        .package(path: "../../forks/swift-identified-collections"),
        .package(path: "../../forks/swift-custom-dump"),
        // Point-Free core forks
        .package(path: "../../forks/swift-perception"),
        .package(path: "../../forks/swift-clocks"),
        .package(path: "../../forks/combine-schedulers"),
        .package(path: "../../forks/swift-dependencies"),
        .package(path: "../../forks/swift-navigation"),
        .package(path: "../../forks/swift-sharing"),
        .package(path: "../../forks/swift-composable-architecture"),
        // Database forks
        .package(path: "../../forks/swift-snapshot-testing"),
        .package(path: "../../forks/swift-structured-queries"),
        .package(path: "../../forks/GRDB.swift"),
        .package(path: "../../forks/sqlite-data"),
    ],
    targets: [
        .target(name: "FuseApp", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "SkipAndroidBridge", package: "skip-android-bridge"),
            // TCA
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            // Database
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "GRDB", package: "GRDB.swift"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "FuseAppTests", dependencies: [
            "FuseApp",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "FuseAppIntegrationTests", dependencies: [
            "FuseApp",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ]),
    ]
)
