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
        .package(path: "../../forks/skip"),
        .package(path: "../../forks/skip-fuse-ui"),
        .package(path: "../../forks/skip-android-bridge"),
        .package(path: "../../forks/skip-ui"),
        .package(path: "../../forks/swift-composable-architecture"),
    ],
    targets: [
        .target(name: "FuseApp", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "SkipAndroidBridge", package: "skip-android-bridge"),
            // TCA
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
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
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
