// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "fuse-app",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FuseApp", type: .dynamic, targets: ["FuseApp"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "ToggleFeature", targets: ["ToggleFeature"]),
        .library(name: "AlertFeature", targets: ["AlertFeature"]),
        .library(name: "SQLFeature", targets: ["SQLFeature"]),
    ],
    dependencies: [
        .package(path: "../../forks/skip"),
        .package(path: "../../forks/skip-fuse"),
        .package(path: "../../forks/skip-fuse-ui"),
        .package(path: "../../forks/skip-android-bridge"),
        .package(path: "../../forks/skip-ui"),
        .package(path: "../../forks/swift-composable-architecture"),
        .package(path: "../../forks/sqlite-data"),
        .package(path: "../../forks/swift-structured-queries"),
        .package(path: "../../forks/swift-dependencies"),
        .package(url: "https://source.skip.tools/skip-av.git", "0.5.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-kit.git", "0.5.1"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-sql.git", "0.12.1"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-web.git", "0.7.2"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-motion.git", "0.6.1"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-keychain.git", "0.3.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-notify.git", "0.0.0"..<"2.0.0"),
    ],
    targets: [
        // MARK: - Shared
        .target(name: "Shared", dependencies: [
            .product(name: "SkipFuse", package: "skip-fuse"),
        ], path: "Sources/Shared", plugins: [.plugin(name: "skipstone", package: "skip")]),

        // MARK: - Feature Targets
        .target(name: "ToggleFeature", dependencies: [
            "Shared",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
        ], path: "Sources/Features/ToggleFeature", plugins: [.plugin(name: "skipstone", package: "skip")]),

        .target(name: "AlertFeature", dependencies: [
            "Shared",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
        ], path: "Sources/Features/AlertFeature", plugins: [.plugin(name: "skipstone", package: "skip")]),

        .target(name: "SQLFeature", dependencies: [
            "Shared",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "StructuredQueries", package: "swift-structured-queries"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "DependenciesMacros", package: "swift-dependencies"),
        ], path: "Sources/Features/SQLFeature", plugins: [.plugin(name: "skipstone", package: "skip")]),

        // MARK: - App
        .target(name: "FuseApp", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "SkipAndroidBridge", package: "skip-android-bridge"),
            // TCA
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            // Modular features
            "Shared",
            "ToggleFeature",
            "AlertFeature",
            "SQLFeature",
            // Showcase playground dependencies (for unconverted playgrounds)
            .product(name: "SkipAV", package: "skip-av"),
            .product(name: "SkipKit", package: "skip-kit"),
            .product(name: "SkipSQLPlus", package: "skip-sql"),
            .product(name: "SkipWeb", package: "skip-web"),
            .product(name: "SkipMotion", package: "skip-motion"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "SkipNotify", package: "skip-notify"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),

        // MARK: - Tests
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
