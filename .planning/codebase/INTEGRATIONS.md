# External Integrations

**Analysis Date:** 2026-02-20

## APIs & External Services

**Skip Compiler Infrastructure:**
- Skip Framework - Cross-platform Swift compilation service
  - SDK: `skip` package (1.7.2+)
  - Usage: Entire codebase relies on Skip's `skipstone` plugin for transpilation
  - Config: Invoked via Swift Package plugins in all Package.swift files
  - No explicit API key required; self-hosted at https://source.skip.tools/

**Point-Free Dependencies:**
- No direct API integrations; all Point-Free packages are static libraries and development tools
- Used for: Testing utilities, type-safe navigation, macro support

## Data Storage

**Databases:**
- SQLite 3.46+ (primary persistent storage)
  - Client: GRDB.swift ORM (custom fork in `forks/GRDB.swift`)
  - Extensions: FTS5 (full-text search), SNAPSHOT (change tracking)
  - Platform: System-provided on Darwin (iOS, macOS, tvOS, watchOS); bundled for Android
  - Connection: In-process via GRDB's DatabasePool or DatabaseQueue
  - No external database server required

**File Storage:**
- Local filesystem only
  - iOS: Application Documents/Caches directories
  - macOS: ~/Library/Application Support or standard sandboxed locations
  - Android: App-specific directories via Android scoped storage

**Caching:**
- Not detected - Applications rely on GRDB for persistence

## Authentication & Identity

**Auth Provider:**
- Custom or none
  - No OAuth, third-party auth, or identity services detected
  - Implementation: Likely handled at application level (not in shared library code)

## Monitoring & Observability

**Error Tracking:**
- Not detected - No external error tracking service integration

**Logs:**
- Standard Swift logging via print/os_log
  - No external log aggregation detected
  - Debug output controlled by Debug/Release build configuration

## CI/CD & Deployment

**Hosting:**
- Self-hosted (not a cloud platform)
  - Development: macOS + Xcode
  - Compilation: Skip framework cloud infrastructure for transpilation
  - Distribution: Manual or proprietary distribution not visible in this codebase

**CI Pipeline:**
- Not detected - No GitHub Actions, Jenkins, or similar CI config visible
  - Makefile targets for submodule management suggest manual or scripted workflows
  - Makefile commands: `make status`, `make push-all`, `make pull-all`, `make diff-all`, `make branch-all`

## Environment Configuration

**Required env vars:**
- No `.env` files detected (file is in `.gitignore`)
- Compile-time configuration via Swift Package settings (not runtime environment variables)

**Secrets location:**
- None detected in codebase
- All configuration is code-based via Swift Package manifests

**Build-time Environment Variables:**
- `TARGET_OS_ANDROID` - Conditionally includes Android dependencies (sqlite-data, swift-composable-architecture)
- `SKIP_BRIDGE` - Enables skip-bridge integration for dynamic libraries (skip-ui)
- `SPI_BUILDER` - Enables swift-docc-plugin for documentation on Swift Package Index
- `SQLITE_ENABLE_PREUPDATE_HOOK` - Testing convenience for GRDB pre-update hook (GRDB.swift only)

## Webhooks & Callbacks

**Incoming:**
- Not detected - No webhook endpoints visible

**Outgoing:**
- Not detected - No external callback integrations

## Code Generation & Transpilation

**Skip Compiler:**
- Primary integration: Skip's `skipstone` plugin transforms Swift code to:
  - iOS/macOS (via normal Swift compilation)
  - Android (via Kotlin compilation)
- Invoked: Automatically in build phase for all targets with `.plugin(name: "skipstone", package: "skip")`
- Examples in codebase:
  - `examples/lite-app/Package.swift` line 19
  - `examples/fuse-app/Package.swift` lines 24, 27

**Swift Macros:**
- Compiler plugins for compile-time code generation
  - `@Dependency` macro from swift-dependencies
  - CaseReducer macros from swift-composable-architecture
  - `@EquatableNoop`, `@PreviewProvider` equivalents via custom macros
- No external code generation services

## Dependency Resolution

**Package Index:**
- Swift Package Index (swiftpackageindex.com) - Optional documentation building
  - Integration: `SPI_BUILDER` environment variable enables swift-docc-plugin
  - Used for: Auto-generating API docs on SPI when this package is indexed

**Version Management:**
- All external packages pinned via `Package.resolved` (SPM lockfile)
- Forks managed as git submodules with fixed branches:
  - Branch: `flote/service-app` for all 12 custom forks
  - Ensures deterministic builds and shared architecture vision

## Platform-Specific Integrations

**Android (via Skip):**
- JNI (Java Native Interface) - Bidirectional Swift-to-Java calls
  - SDK: swift-jni, skip-bridge, skip-android-bridge
  - Used in: Any Android-specific functionality or calling Android APIs
- Android NDK - Native compilation for Android ARM/x86 targets
- Gradle - Android build system integration (not visible in this repo, managed by Skip)

**iOS/macOS (Darwin):**
- UIKit/AppKit - Via skip-ui's native bindings
- CoreData - Not used; GRDB/SQLite is the data layer
- CloudKit - Not integrated

**Cross-Platform:**
- OpenCombine - Reactive programming compatibility layer
  - Used in: combine-schedulers, swift-dependencies for cross-platform scheduling

## Network & Communication

**Not Detected:**
- No HTTP client libraries (URLSession integration not visible)
- No networking frameworks integrated
- Likely handled at application level above these shared libraries

## Testing Integrations

**Test Runners:**
- XCTest - Native Swift Testing Framework
  - Invoked: Via `swift test` or Xcode Test action
- Skip Test Framework - Cross-platform test support
  - Usage: All test targets use `.product(name: "SkipTest", package: "skip")`

**Test Utilities:**
- swift-snapshot-testing (custom fork) - Snapshot regression testing
  - Location: `forks/swift-snapshot-testing`
  - Used in: `sqlite-data` package tests

**Mocking & Test Support:**
- swift-dependencies provides `DependenciesTestSupport` for dependency mocking
- combine-schedulers provides test schedulers for async operations
- swift-clocks provides mockable Clock for time-based testing

## Documentation

**API Documentation:**
- Swift-DocC - Apple's documentation system
  - Plugin: `swift-docc-plugin` (optional, from swiftlang)
  - Generation: Via `swift package generate-documentation` command (if enabled)

---

*Integration audit: 2026-02-20*
