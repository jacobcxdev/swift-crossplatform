# Codebase Structure

**Analysis Date:** 2026-02-20

## Directory Layout

```
swift-crossplatform/
├── .planning/                    # GSD planning outputs (this file, ARCHITECTURE.md, CONCERNS.md, etc.)
│   └── codebase/
├── docs/                         # Skip framework documentation (ported from skip.tools)
│   └── skip/                     # Topics: app-development, bridging, testing, modes, debugging, etc.
├── examples/                     # Example applications demonstrating Skip features
│   ├── lite-app/                 # Skip Lite mode app (transpiled Swift → Kotlin)
│   ├── lite-library/             # Skip Lite library package
│   └── fuse-library/             # Skip Fuse mode library (native Swift on Android)
├── forks/                        # Git submodules: 12 Point-Free + Skip framework forks
│   ├── swift-perception/         # Backport of Swift Observation API
│   ├── swift-clocks/             # Clock/timer abstractions for testing
│   ├── swift-composable-architecture/  # TCA state management library
│   ├── swift-dependencies/       # Dependency injection framework
│   ├── swift-custom-dump/        # Enhanced CustomStringConvertible
│   ├── swift-snapshot-testing/   # Snapshot testing utilities
│   ├── swift-structured-queries/ # Type-safe database query builder
│   ├── swift-navigation/         # Navigation state management
│   ├── swift-sharing/            # Shared data across platform boundaries
│   ├── combine-schedulers/       # Async scheduler abstractions
│   ├── GRDB.swift/               # SQLite ORM and query builder
│   ├── sqlite-data/              # SQLite data layer abstractions
│   ├── skip-ui/                  # SwiftUI implementation for Skip (Lite mode)
│   ├── skip-android-bridge/      # Observation registrar + JNI bridge to Compose
│   └── skip-fuse-ui/             # SwiftUI implementation for Fuse mode
├── .gitmodules                   # Submodule definitions (12 repos on jacobcxdev)
├── .gitignore                    # Standard Skip + Xcode + Gradle ignores
├── Makefile                      # Convenience targets: status, push-all, pull-all, diff-all, branch-all
├── observation-architecture-decision.md  # Decision log on observation bridging approach
├── observation-bridge-analysis.md        # Root cause analysis of infinite recomposition
└── whats-next.md                 # Work remaining: fork setup, Kotlin investigation, verification
```

## Directory Purposes

**`.planning/codebase/`:**
- Purpose: GSD framework analysis outputs; consumed by `/gsd:plan-phase` and `/gsd:execute-phase`
- Contains: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md, STACK.md, INTEGRATIONS.md
- Key files: This file (STRUCTURE.md) and ARCHITECTURE.md

**`docs/skip/`:**
- Purpose: Documentation ported from skip.tools; reference material for framework features
- Contains: markdown files covering app-development, bridging, modes, dependencies, testing, debugging, porting
- Key files: `app-development.md` (SwiftUI conventions), `bridging.md` (Skip ↔ Kotlin integration), `modes.md` (Lite vs Fuse)

**`examples/lite-app/`:**
- Purpose: Reference application using Skip Lite mode (transpiled to Kotlin)
- Contains: Package.swift, Sources/ with LiteApp.swift, ContentView.swift, ViewModel.swift; Darwin/ for iOS; Tests/
- Platform-specific: `Darwin/Sources/Main.swift` for iOS app entry point; Android code generated from Swift
- Key files: `Sources/LiteApp/ViewModel.swift` (@Observable state), `Sources/LiteApp/ContentView.swift` (views)

**`examples/lite-library/`:**
- Purpose: Reference library in Lite mode; demonstrates Skip package structure
- Contains: Package.swift, Sources/LiteLibrary/, Tests/; no platform-specific code (pure Skip)
- Key files: `Sources/LiteLibrary/LiteLibrary.swift` (public APIs)

**`examples/fuse-library/`:**
- Purpose: Reference library in Fuse mode (native Swift on Android); demonstrates advanced observation integration
- Contains: Package.swift, Sources/FuseLibrary/, Tests/
- Key files: None yet (under development for observation fix)

**`forks/`:**
- Purpose: Git submodules of upstream Point-Free libraries and Skip framework forks; all branches synchronized to `flote/service-app`
- Organization: Each fork is a standalone repo; all on `jacobcxdev/` GitHub account
- Sync mechanism: `make pull-all`, `make push-all`, `make branch-all` (Makefile targets)
- Key submodules:
  - **swift-perception/**: Complete backport of Swift Observation (native + Lite compatible)
  - **swift-composable-architecture/**: TCA Store, Reducer, Observable state support
  - **swift-dependencies/**: @Dependency injection macro and DependencyKey protocol
  - **GRDB.swift/**: SQLite query builder (for persistence layer)
  - **skip-android-bridge/**: Critical — observation registrar + JNI bridge (targeted for fix in Task #3)
  - **skip-ui/**: Skip's SwiftUI implementation (Lite mode); has SKIP_BRIDGE conditional for Fuse additions

## Key File Locations

**Entry Points:**

| File | Purpose | Platform |
|------|---------|----------|
| `examples/lite-app/Darwin/Sources/Main.swift` | UIKit/SwiftUI app entry point | iOS |
| `examples/lite-app/Sources/LiteApp/LiteApp.swift` (LiteAppRootView) | Root view structure | Both |
| Generated `.build/plugins/outputs/lite-app/LiteApp/destination/skipstone/...` | Android Compose entry point (generated) | Android |

**Configuration:**

| File | Purpose |
|------|---------|
| `examples/lite-app/Package.swift` | SPM package definition; declares skip, skip-ui dependencies |
| `examples/lite-app/Sources/LiteApp/Skip/skip.yml` | Skip build config (transpiler settings, target versions) |
| `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` | Observation registrar configuration (bridges Swift ↔ Kotlin) |

**Core Logic:**

| File | Purpose |
|------|---------|
| `examples/lite-app/Sources/LiteApp/ViewModel.swift` | @Observable state container, persistence logic |
| `examples/lite-app/Sources/LiteApp/ContentView.swift` | Main view definitions (TabView, ItemListView, ItemView, SettingsView) |
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` | TCA state container (lines 119-125 have registrar setup) |
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/ObservationStateRegistrar.swift` | TCA's observation integration point |

**Testing:**

| File | Purpose |
|------|---------|
| `examples/lite-app/Tests/LiteAppTests/LiteAppTests.swift` | UI snapshot and behavior tests |
| `examples/lite-app/Tests/LiteAppTests/XCSkipTests.swift` | Skip testing infrastructure setup |
| `forks/swift-composable-architecture/Tests/ComposableArchitectureTests/` | TCA reducer and store tests |

**Generated/Build Artifacts:**

| Directory | Purpose | Committed |
|-----------|---------|-----------|
| `.build/plugins/outputs/*/SkipBridgeGenerated/` | Generated JNI bridge code (Swift_composableBody, type marshalling) | No |
| `.build/checkouts/skip-*/` | Resolved package dependencies (fetched by SPM) | No |

## Naming Conventions

**Files:**
- **SwiftUI views:** PascalCase noun (e.g., `ContentView.swift`, `ItemListView.swift`, `ViewModel.swift`)
- **Skip framework files:** CamelCase module name (e.g., `skip-android-bridge`, `skip-ui`)
- **Fork repositories:** kebab-case matching upstream (e.g., `swift-composable-architecture`, `swift-perception`)
- **Package directories:** Match package name (e.g., `Sources/LiteApp/` for package "LiteApp")
- **Test files:** `[TargetName]Tests.swift` or `[Feature].test.swift`; Skip tests use `XCSkipTests.swift` wrapper

**Directories:**
- **Platform-specific:** `Darwin/` (iOS/macOS), `Android/` (Android-only code and resources)
- **Cross-platform source:** `Sources/[PackageName]/` (compiled for all platforms)
- **Build outputs:** `.build/` (ignored, generated at build time)
- **Forks:** `forks/[upstream-name]/` matching original repo naming

**Identifiers:**
- **Variables:** camelCase (e.g., `welcomeName`, `items`, `viewModel`)
- **Types:** PascalCase (e.g., `ViewModel`, `Item`, `ContentTab`)
- **Constants:** UPPER_SNAKE_CASE for module-level constants (e.g., `logger` in LiteApp.swift is lowercase as it's the logger instance)
- **Enums:** PascalCase cases, camelCase raw values (e.g., `enum ContentTab: String { case welcome, home, settings }`)

## Where to Add New Code

**New Feature (E.g., Add Database Integration):**
- Primary code: `examples/lite-app/Sources/LiteApp/` — add new view or ViewModel extension
- Core library code: `forks/sqlite-data/Sources/` or extend GRDB usage in ViewModel
- Tests: `examples/lite-app/Tests/LiteAppTests/` — add test for persistence behavior
- iOS platform-specific: `examples/lite-app/Darwin/Sources/` if needed (rarely)
- Android platform-specific: `examples/lite-app/Android/` (if Kotlin integration needed beyond Skip generation)

**New Component/Module:**
- Create new Swift file in `examples/lite-app/Sources/LiteApp/[ComponentName].swift`
- Follow naming: PascalCase for view struct names, camelCase for property names
- Use `@Observable` for reactive state; use `@Environment` to inject into view hierarchy
- Add corresponding test in `examples/lite-app/Tests/LiteAppTests/[ComponentName]Tests.swift`

**Utilities/Helpers:**
- Shared helpers: `examples/lite-app/Sources/LiteApp/Extensions/` or in the same file as primary use
- Cross-module utilities: Consider whether to add to a fork package (e.g., add to `swift-dependencies` for new DependencyKey)
- Skip-specific utilities: May belong in `forks/skip-android-bridge` if they bridge Swift ↔ Kotlin

**Persistence (Database/Serialization):**
- JSON encoding/decoding: Codable conformance in model struct (see `Item` in ViewModel.swift)
- SQLite queries: Use GRDB via `forks/GRDB.swift/` (currently unused; available for future)
- Local storage: `FileManager` + `URL.applicationSupportDirectory` (current approach in ViewModel.swift saveItems/loadItems)

**Platform-Specific Code:**
- iOS-only: `examples/lite-app/Darwin/Sources/` or `#if !SKIP` in shared source
- Android-only: `examples/lite-app/Android/` or `#if SKIP` in shared source
- Both platforms (different implementations): Use conditional compilation with `#if SKIP` / `#else` / `#endif`

## Special Directories

**`.omc/`:**
- Purpose: oh-my-claudecode orchestration state (project memory, session notepad, planning docs)
- Generated: Yes (at session start by `/oh-my-claudecode:omc-setup`)
- Committed: No (git-ignored)

**`.build/`:**
- Purpose: Swift Package Manager build artifacts, compiled products, generated code
- Generated: Yes (by `swift build`, `xcode build`, `skip android build`)
- Committed: No (git-ignored)
- Key subdirectories:
  - `.build/checkouts/` — resolved dependencies
  - `.build/plugins/outputs/` — generated JNI bridges and transpiled Kotlin
  - `.build/repositories/` — workspace state

**`Project.xcworkspace/`:**
- Purpose: Xcode workspace file for IDE integration
- Generated: Yes (by `swift build` or manually in Xcode)
- Committed: No (usually; .xcworkspace is generated)

**`Darwin/`:**
- Purpose: iOS/macOS platform-specific code and resources
- Generated: No (hand-written)
- Committed: Yes
- Contents: `Sources/Main.swift` (app delegate), `Assets.xcassets/` (images, icons)

**`Android/`:**
- Purpose: Android platform-specific resources (currently empty in examples)
- Generated: Partially (Gradle build output)
- Committed: Partially (source files yes, build outputs no)
- Note: Most Android code is generated by Skip transpiler or native Swift compilation

**`docs/skip/`:**
- Purpose: Ported documentation from skip.tools
- Generated: No (reference material)
- Committed: Yes

---

*Structure analysis: 2026-02-20*
