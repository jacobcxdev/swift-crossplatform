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
        .package(path: "../../forks/skip-fuse-ui"),
        .package(path: "../../forks/skip-android-bridge"),
        .package(path: "../../forks/skip-ui"),
        .package(path: "../../forks/swift-composable-architecture"),
        .package(path: "../../forks/swift-dependencies"),
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
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "TestUtilities", path: "Tests/TestUtilities"),
        .testTarget(name: "FuseAppTests", dependencies: [
            "FuseApp",
            "TestUtilities",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "FuseAppIntegrationTests", dependencies: [
            "FuseApp",
            "TestUtilities",
            .product(name: "SkipTest", package: "skip"),
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "SQLiteData", package: "sqlite-data"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
