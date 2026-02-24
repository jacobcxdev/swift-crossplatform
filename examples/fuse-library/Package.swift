// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "fuse-library",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FuseLibrary", type: .dynamic, targets: ["FuseLibrary"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.7.2"),
        .package(path: "../../forks/skip-fuse"),
        // Foundation library forks (Phase 2)
        .package(path: "../../forks/xctest-dynamic-overlay"),
        .package(path: "../../forks/swift-case-paths"),
        .package(path: "../../forks/swift-identified-collections"),
        .package(path: "../../forks/swift-custom-dump"),
        // Remaining forks (wired for transitive resolution — Skip sandbox compatible via useLocalPackage)
        .package(path: "../../forks/swift-perception"),
        .package(path: "../../forks/swift-clocks"),
        .package(path: "../../forks/combine-schedulers"),
        .package(path: "../../forks/swift-dependencies"),
        .package(path: "../../forks/swift-navigation"),
        .package(path: "../../forks/swift-sharing"),
        .package(path: "../../forks/swift-composable-architecture"),
        .package(path: "../../forks/skip-android-bridge"),
        // Deferred forks (not yet needed — add back when targets use them):
        // .package(path: "../../forks/skip-ui"),              // Phase 4+ (view-level tests)
        // Database forks (Phase 6)
        .package(path: "../../forks/swift-snapshot-testing"),
        .package(path: "../../forks/swift-structured-queries"),
        .package(path: "../../forks/GRDB.swift"),
        .package(path: "../../forks/sqlite-data"),
    ],
    targets: [
        .target(name: "TestUtilities", path: "Tests/TestUtilities"),
        .target(name: "FuseLibrary", dependencies: [
            .product(name: "SkipFuse", package: "skip-fuse")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        // Observation tests (Phase 1 bridge + tracking + Phase 7 bridge/stress)
        .testTarget(name: "ObservationTests", dependencies: [
            "FuseLibrary",
            "TestUtilities",
            .product(name: "SkipTest", package: "skip"),
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        // Foundation library tests (Phase 2)
        .testTarget(name: "FoundationTests", dependencies: [
            "TestUtilities",
            .product(name: "SkipTest", package: "skip"),
            .product(name: "CasePaths", package: "swift-case-paths"),
            .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "IssueReportingTestSupport", package: "xctest-dynamic-overlay"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        // TCA core tests (Phase 3 + 4 state/bindings + Phase 7 TestStore)
        .testTarget(name: "TCATests", dependencies: [
            "TestUtilities",
            .product(name: "SkipTest", package: "skip"),
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        // Sharing tests (Phase 4)
        .testTarget(name: "SharingTests", dependencies: [
            "TestUtilities",
            .product(name: "SkipTest", package: "skip"),
            .product(name: "Sharing", package: "swift-sharing"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        // Navigation tests (Phase 5)
        .testTarget(name: "NavigationTests", dependencies: [
            "TestUtilities",
            .product(name: "SkipTest", package: "skip"),
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        // Database tests (Phase 6)
        .testTarget(name: "DatabaseTests", dependencies: [
            "TestUtilities",
            .product(name: "SkipTest", package: "skip"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
