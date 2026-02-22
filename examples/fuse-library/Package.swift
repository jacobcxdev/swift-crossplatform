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
        .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0"),
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
        // .package(path: "../../forks/swift-snapshot-testing"), // Phase 6 (database)
        // .package(path: "../../forks/swift-structured-queries"), // Phase 6 (database)
        // .package(path: "../../forks/GRDB.swift"),            // Phase 6 (database)
        // .package(path: "../../forks/sqlite-data"),           // Phase 6 (database)
    ],
    targets: [
        .target(name: "FuseLibrary", dependencies: [
            .product(name: "SkipFuse", package: "skip-fuse")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "FuseLibraryTests", dependencies: [
            "FuseLibrary",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "ObservationTrackingTests", dependencies: [
            "FuseLibrary",
        ]),
        .testTarget(name: "CasePathsTests", dependencies: [
            .product(name: "CasePaths", package: "swift-case-paths"),
        ]),
        .testTarget(name: "IdentifiedCollectionsTests", dependencies: [
            .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        ]),
        .testTarget(name: "CustomDumpTests", dependencies: [
            .product(name: "CustomDump", package: "swift-custom-dump"),
        ]),
        .testTarget(name: "IssueReportingTests", dependencies: [
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "IssueReportingTestSupport", package: "xctest-dynamic-overlay"),
        ]),
        .testTarget(name: "StoreReducerTests", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),
        .testTarget(name: "EffectTests", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),
        .testTarget(name: "DependencyTests", dependencies: [
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "DependenciesMacros", package: "swift-dependencies"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),
        .testTarget(name: "ObservableStateTests", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),
        .testTarget(name: "BindingTests", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),
        .testTarget(name: "SharedPersistenceTests", dependencies: [
            .product(name: "Sharing", package: "swift-sharing"),
        ]),
        .testTarget(name: "SharedBindingTests", dependencies: [
            .product(name: "Sharing", package: "swift-sharing"),
        ]),
        .testTarget(name: "SharedObservationTests", dependencies: [
            .product(name: "Sharing", package: "swift-sharing"),
        ]),
        .testTarget(name: "NavigationTests", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),
    ]
)
