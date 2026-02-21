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
        // Override with local forks for observation tracking
        .package(path: "../../forks/skip-android-bridge"),
        .package(path: "../../forks/skip-ui"),
    ],
    targets: [
        .target(name: "FuseApp", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "SkipAndroidBridge", package: "skip-android-bridge"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "FuseAppTests", dependencies: [
            "FuseApp",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "FuseAppViewModelTests", dependencies: [
            "FuseApp",
        ]),
    ]
)
