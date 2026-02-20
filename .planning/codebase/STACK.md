# Technology Stack

**Analysis Date:** 2026-02-20

## Languages

**Primary:**
- Swift 5.9–6.1 - Primary language for all packages and applications
- C - SQLite compilation and system-level integration (optional, for custom SQLite builds)

**Secondary:**
- Kotlin/Java - Android bridge and JNI interoperability via swift-jni
- XML - Android build configuration and resources

## Runtime

**Environment:**
- Swift Package Manager (SPM) 5.9–6.1 - Primary build system
- Xcode 14+ (implied by Swift 6.1 support)
- Android NDK + Gradle - Android cross-compilation via Skip framework

**Package Manager:**
- Swift Package Manager (SPM) - Manages all Swift dependencies
- Lockfile: `Package.resolved` (generated, in `.gitignore`)

## Frameworks

**Core:**
- Skip 1.7.2+ - Cross-platform Swift compilation to iOS/Android/macOS
  - Used in: `fuse-app`, `lite-app`, and all Skip-bridged packages
  - Includes `skipstone` plugin for code generation and transpilation
- Composable Architecture (custom fork) - State management and architecture pattern
  - Location: `forks/swift-composable-architecture`
  - Version: Custom flote/service-app branch
  - Used for: Observable state, effect management, reducer pattern

**UI:**
- SkipUI 1.0.0+ - SwiftUI-compatible cross-platform UI framework
  - Source: `https://source.skip.tools/skip-ui.git`
  - Local fork: `forks/skip-ui`
- SkipFuseUI 1.0.0+ - Extended UI components for Fuse framework
  - Used in: `fuse-app` for advanced UI features

**Database:**
- GRDB.swift 6.1+ - SQLite query builder and ORM for Swift
  - Location: `forks/GRDB.swift` (custom flote/service-app branch)
  - Used in: `sqlite-data` package for database access
  - Supports SQLite 3.46+ with FTS5 and snapshot extensions

**Dependency Injection:**
- swift-dependencies (custom fork) - Type-safe dependency injection with macros
  - Location: `forks/swift-dependencies`
  - Branch: flote/service-app
  - Provides: `@Dependency` macro, test support, DI container

**State & Observation:**
- swift-perception (custom fork) - Object change tracking without reflection
  - Location: `forks/swift-perception`
- swift-sharing (custom fork) - Shared state and observation
  - Location: `forks/swift-sharing`

**Navigation:**
- swift-navigation (custom fork) - Type-safe navigation with deep linking
  - Location: `forks/swift-navigation`

**Testing:**
- SkipTest - Skip framework's testing support
  - Used in: All test targets via Skip plugin
  - Plugins: `skipstone` build plugin for test compilation
- swift-snapshot-testing (custom fork) - Snapshot-based testing
  - Location: `forks/swift-snapshot-testing`
  - Used in: `sqlite-data` tests

**Build/Dev:**
- swift-syntax 509.0.0–602.x - AST manipulation and macro support
  - Used by: Dependency injection and Composable Architecture macros
- Combine Schedulers (custom fork) - Testing schedulers for reactive code
  - Location: `forks/combine-schedulers`
- swift-clocks (custom fork) - Mockable clock implementation
  - Location: `forks/swift-clocks`

**Cross-Platform:**
- skip-android-bridge 0.6.1+ - Android-specific bridging and native calls
  - Location: `forks/skip-android-bridge`
  - Provides: JNI integration, Android-specific APIs
- swift-jni 0.3.1+ - Swift bindings for Java Native Interface
  - Source: `https://source.skip.tools/swift-jni.git`
- skip-bridge 0.16.4+ - Bidirectional Swift-to-JVM bridging
  - Source: `https://source.skip.tools/skip-bridge.git`
- swift-android-native 1.4.1+ - Android native API bindings
  - Source: `https://source.skip.tools/swift-android-native.git`

## Key Dependencies

**Critical:**
- skip (1.7.2+) - Core compilation and cross-platform support
  - Why it matters: Enables writing once, running on iOS/macOS/Android
  - Installation: Via SPM from https://source.skip.tools/skip.git

- GRDB.swift (6.1+) - Database persistence
  - Why it matters: SQLite ORM with advanced query building and migration
  - Defines SQLite extensions: FTS5, SNAPSHOT

- swift-composable-architecture (custom) - Redux-style state management
  - Why it matters: Enforces unidirectional data flow, testability, and strong typing

**Infrastructure:**
- swift-collections 1.1.0+ - Efficient ordered/indexed collections
- swift-case-paths 1.5.4+ - Type-safe case path manipulation for enums
- swift-concurrency-extras 1.2.0+ - Structured concurrency helpers
- swift-identified-collections 1.1.0+ - Uniquely identified collection types
- xctest-dynamic-overlay 1.3.0+ - XCTest fallbacks at runtime
- swift-custom-dump 1.3.2+ - Custom debugging dump output
- OpenCombine 0.14.0+ - Combine compatibility layer for cross-platform
- swift-tagged 0.10.0+ - Tagged types for domain-driven design (sqlite-data only)
- swift-structured-queries (custom) - Type-safe SQL query building
  - Location: `forks/swift-structured-queries`

## Configuration

**Environment:**
- SPM is configured entirely via `Package.swift` files in each package
- No traditional `.env` files; configuration is compile-time via Swift settings
- Platform-specific: iOS 13–17, macOS 10.15–14, tvOS 13+, watchOS 6–9, Android (via Skip)

**Build:**
- `Package.swift` - Primary build manifest (all packages)
  - Example: `examples/lite-app/Package.swift`, `examples/fuse-app/Package.swift`
- `.xcconfig` files - Xcode build settings (optional, in forks like GRDB.swift)
  - Example: `examples/lite-app/Darwin/LiteApp.xcconfig`
- `Makefile` - Convenience targets for submodule management
  - Commands: `make status`, `make push-all`, `make pull-all`, `make diff-all`

**Swift Settings:**
- Strict Concurrency enforcement (Swift 6): `.enableExperimentalFeature("StrictConcurrency")`
- Language features: `.enableUpcomingFeature("ExistentialAny")`, `.enableUpcomingFeature("InferSendableFromCaptures")`
- SQLite: `.define("SQLITE_ENABLE_FTS5")`, `.define("SQLITE_ENABLE_SNAPSHOT")`

## Platform Requirements

**Development:**
- macOS 10.15+ (minimum from dependencies)
- Xcode 14+ (for Swift 5.9–6.1 support)
- Swift 5.9–6.1 toolchain
- Git (for submodule management)
- Android SDK + NDK (for Android targeting)
- Gradle (implied for Android builds)

**Production:**
- **iOS:** 13.0+ (minimum across all packages)
- **macOS:** 10.15+ (minimum from composable-architecture)
- **tvOS:** 13.0+
- **watchOS:** 6.0+
- **Android:** Target specified via Skip framework (API level 21+ typical)
- **visionOS:** 1.0+ (GRDB.swift support)

**Database:**
- SQLite 3.46+ (configured in GRDB with FTS5 and SNAPSHOT extensions)
- System-provided SQLite on Darwin platforms
- Custom SQLite available via GRDBSQLite system library target

## External Package Sources

**Skip Ecosystem (https://source.skip.tools/):**
- skip, skip-ui, skip-fuse-ui, skip-foundation, skip-model, skip-lib, skip-unit, skip-bridge, skip-android-bridge, swift-jni, swift-android-native

**Point-Free (https://github.com/pointfreeco/):**
- swift-case-paths, swift-concurrency-extras, swift-identified-collections, swift-macro-testing, swift-tagged, xctest-dynamic-overlay, swift-docc-plugin

**Apple (https://github.com/apple/):**
- swift-collections, swift-docc-plugin, swift-syntax

**OpenCombine (https://github.com/OpenCombine/):**
- OpenCombine

**Swift Lang (https://github.com/swiftlang/):**
- swift-docc-plugin, swift-syntax

**Custom Forks (jacobcxdev):**
- 12 forked packages on flote/service-app branch for unified cross-platform architecture
- Location: `forks/` directory with git submodules

---

*Stack analysis: 2026-02-20*
