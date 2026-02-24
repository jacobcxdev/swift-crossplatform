# R4b: Fuse-App Showcase Deep Dive

**Date:** 2026-02-22
**Scope:** Exhaustive investigation of what the fuse-app TCA showcase needs, how to structure it, exact Package.swift changes, feature-by-feature implementation checklist, and Android feasibility assessment.
**Inputs:** R4 (showcase architecture), R8 (parity gaps), R9 (build/packaging), R10 (scope risks), SyncUps reference app, CaseStudies reference, existing fuse-app/fuse-library source, REQUIREMENTS.md (184 requirements), all 17 forks.

---

## 1. Current Fuse-App State (Complete Audit)

### Source Files

| File | Lines | Purpose | TCA Usage |
|------|-------|---------|-----------|
| `FuseApp.swift` | 62 | `FuseAppRootView` (bridge-annotated root), `FuseAppDelegate` (lifecycle hooks) | **None** -- plain SwiftUI + SkipFuse logger |
| `ContentView.swift` | 181 | TabView (Welcome/Home/Settings), WelcomeView, ItemListView, ItemView, SettingsView, PlatformHeartView, HeartComposer | **None** -- vanilla SwiftUI with `@AppStorage`, `@State`, `@Environment(ViewModel.self)` |
| `ViewModel.swift` | 96 | `@Observable` class with `[Item]`, JSON file persistence via `loadItems()`/`saveItems()` | **None** -- manual `@Observable` + `didSet` persistence |
| `skip.yml` | 1 | `skip: mode: 'native'` (Fuse mode) | N/A |

### Existing Tests

| File | Tests | Framework |
|------|-------|-----------|
| `XCSkipTests.swift` | 1 | XCTest -- stub JUnit results for `skip test` parity report |
| `FuseAppViewModelTests.swift` | 6 | XCTest -- `@Observable` ViewModel observation tests (macOS-only) |

### Current Package.swift Dependencies

```swift
dependencies: [
    .package(url: "https://source.skip.tools/skip.git", from: "1.7.2"),
    .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
    .package(path: "../../forks/skip-android-bridge"),
    .package(path: "../../forks/skip-ui"),
]
```

**Missing for TCA:** 13 fork path dependencies not wired. Zero TCA product references.

### Assessment

100% template code. The entire `ContentView.swift` and `ViewModel.swift` must be replaced. `FuseApp.swift` keeps its bridge annotations and delegate structure but needs TCA store wiring. `XCSkipTests.swift` stays (Skip parity infrastructure). `FuseAppViewModelTests.swift` is deleted (ViewModel is replaced by TCA reducers).

---

## 2. Fuse-Library Package.swift (Dependency Reference)

The fuse-library already wires 15 fork path dependencies. The fuse-app needs a similar (but not identical) set. Key differences:

| Aspect | fuse-library | fuse-app (needed) |
|--------|-------------|-------------------|
| UI framework | `skip-fuse` (no UI) | `skip-fuse-ui` (SwiftUI) |
| SkipUI fork | Not wired (commented out) | Already wired |
| TCA | Wired (test targets only) | Needed for FuseApp target |
| Database | Wired (test targets only) | Needed for FuseApp target |
| Test targets | 20 validation targets | Minimal (integration tests) |

---

## 3. Exact Package.swift Diff for Fuse-App

### Current fuse-app Package.swift (complete)

```swift
// swift-tools-version: 6.1
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
```

### Required Package.swift (post-rebuild)

```swift
// swift-tools-version: 6.1
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
```

### Diff Summary

| Change | Detail |
|--------|--------|
| **Added 13 fork path dependencies** | All Point-Free + database forks matching fuse-library's set |
| **Added 2 product dependencies to FuseApp target** | `ComposableArchitecture`, `SQLiteData` |
| **Removed `FuseAppViewModelTests`** | Replaced by `FuseAppIntegrationTests` |
| **Added `FuseAppIntegrationTests`** | macOS-only TestStore integration tests |
| **Transitive resolution forks** | `swift-perception`, `swift-clocks`, `combine-schedulers`, `swift-snapshot-testing`, `swift-structured-queries`, `GRDB.swift` are declared for SPM resolution but not directly imported by FuseApp target |

### Why transitive forks must be declared

SPM resolves dependencies from the root manifest. If fuse-app depends on `swift-composable-architecture` (local fork), and that fork's Package.swift references `swift-navigation` via a remote GitHub URL, SPM needs the local path override declared at the root level to resolve to the fork instead of fetching from GitHub. Without these declarations, SPM would either fetch remote versions (breaking fork changes) or fail on version conflicts.

### Dependency conflicts expected

Per R9, fuse-app will gain ~3 SPM identity conflict warnings (currently has 3 for skip-android-bridge and skip-ui). With all 17 fork paths declared, expect ~20-30 additional identity conflict warnings. These are non-blocking cosmetic warnings per R9 analysis.

---

## 4. Requirements Coverage Analysis

### What the 226 existing fuse-library tests already cover

| Section | Total Reqs | Covered by Tests | Uncovered | Notes |
|---------|-----------|-----------------|-----------|-------|
| OBS (1-30) | 30 | 19 (ObservationTests) | 11 | OBS-25..OBS-28 are JNI exports (Android-only). Others need emulator. |
| TCA (1-16) | 16 | 16 (StoreReducerTests, EffectTests) | 0 | All checked in REQUIREMENTS.md |
| TCA (17-35) | 19 | 19 (ObservableStateTests, BindingTests, NavigationTests, etc.) | 0 | All checked |
| DEP (1-12) | 12 | 12 (DependencyTests) | 0 | All checked |
| SHR (1-14) | 14 | 14 (SharedPersistenceTests, SharedBindingTests, SharedObservationTests) | 0 | All checked |
| NAV (1-16) | 16 | 16 (NavigationTests, NavigationStackTests, PresentationTests) | 0 | Data-layer only |
| CP (1-8) | 8 | 8 (CasePathsTests) | 0 | All checked |
| IC (1-6) | 6 | 6 (IdentifiedCollectionsTests) | 0 | All checked |
| SQL (1-15) | 15 | 15 (StructuredQueriesTests) | 0 | All checked |
| SD (1-12) | 12 | 12 (SQLiteDataTests) | 0 | All checked |
| CD (1-5) | 5 | 5 (CustomDumpTests) | 0 | All checked |
| IR (1-4) | 4 | 4 (IssueReportingTests) | 0 | All checked |
| UI (1-8) | 8 | 8 (UIPatternTests) | 0 | Data-layer only |
| TEST (1-12) | 12 | 0 | 12 | **Phase 7 scope** |
| SPM (1-6) | 6 | 0 | 6 | Build-time verification |
| DOC (1) | 1 | 0 | 1 | Documentation |

**Summary:** 165 of 184 requirements are already covered by unit/integration tests in fuse-library. The remaining 19 are: TEST-01..TEST-12 (Phase 7 testing), SPM-01..SPM-06 (build verification), DOC-01 (documentation).

### Requirements ONLY testable via a running app (not unit tests)

These requirements fundamentally need a running app with a view hierarchy:

| Req | Why it needs a running app |
|-----|---------------------------|
| **TEST-10** | "Integration tests verify observation bridge prevents infinite recomposition on Android emulator" -- requires Compose runtime |
| **TEST-11** | "Stress tests confirm stability under >1000 TCA state mutations/second on Android" -- needs observation pipeline under load |
| **TEST-12** | "A fuse-app example demonstrates full TCA app... on both iOS and Android" -- IS the running app |
| **OBS-01..OBS-06** | View body evaluation, willSet suppression, recomposition count -- require view rendering |
| **OBS-25..OBS-28** | JNI export resolution -- require Android runtime |
| **NAV-01..NAV-08** (rendering) | Data-layer is tested; actual view rendering needs SwiftUI/Compose |
| **UI-01..UI-08** (rendering) | Same -- data flow tested, rendering needs live views |

### Minimum set for TEST-12 (D1 satisfaction)

D1 says "demonstrate every non-deprecated, current, public API of TCA and SQLiteData." R10 recommends capping this. The minimum viable set that proves cross-platform viability while covering the critical integration patterns:

1. **Store + Reducer + Effect** -- Counter (TCA-01, TCA-03, TCA-10, TCA-11)
2. **Composition** -- Parent/child with forEach (TCA-04, TCA-05, TCA-07, TCA-09, TCA-23)
3. **Bindings** -- Two-way binding projection (TCA-19..TCA-22)
4. **Navigation** -- Stack + sheet + alert (NAV-01..NAV-03, NAV-05, NAV-09)
5. **Shared persistence** -- @Shared all three key types (SHR-01..SHR-03)
6. **Database** -- CRUD + observation (SD-01..SD-08, SQL-01, SQL-05, SQL-06)
7. **Dependencies** -- Custom client + injection (DEP-01, DEP-06, DEP-07)

This covers all 5 pillars (TCA core, state management, navigation, persistence, database) with ~45 requirements exercised through natural app usage.

---

## 5. Architecture Deep Dive

### SyncUps Reference Architecture

The canonical SyncUps app from `forks/swift-composable-architecture/Examples/SyncUps/` uses this structure:

```
AppFeature.swift       -- Root coordinator with NavigationStack + @Reducer enum Path
SyncUpsList.swift      -- List feature with @Shared(.syncUps), @Presents Destination, sheet
SyncUpDetail.swift     -- Detail feature with alert, sheet, @Dependency(\.dismiss)
SyncUpForm.swift       -- Form feature with BindableAction, BindingReducer
RecordMeeting.swift    -- Timer feature with continuousClock, cancellation
Meeting.swift          -- Meeting display (pure view, no reducer)
Models.swift           -- Domain models (SyncUp, Attendee, Meeting, Theme)
Dependencies/          -- OpenSettings, SpeechRecognizer dependency clients
```

**Key patterns observed:**

1. **Single NavigationStack at root** -- `AppView` owns the stack, `$store.scope(state: \.path, action: \.path)` drives it
2. **`@Reducer enum Path`** -- Type-safe destinations (`case detail`, `case meeting`, `case record`)
3. **`switch store.case { }`** -- Enum store switching in `destination:` closure
4. **`@Shared` with SharedKey extension** -- `static var syncUps: Self` on `SharedKey` for cross-feature persistence
5. **`$shared.withLock { }`** -- Thread-safe mutation pattern (not direct setter)
6. **Delegate actions** -- Child sends `.delegate(.startMeeting(...))`, parent intercepts via `.path(.element(_, .detail(.delegate(delegateAction))))`
7. **`Shared(value:)` in previews** -- Avoids real persistence for previews/tests
8. **`@Presents` + `.ifLet(\.$destination, action: \.destination)`** -- Sheet/alert presentation
9. **`@Dependency(\.dismiss)`** -- Programmatic dismissal from child features

### CaseStudies Reference Architecture

The CaseStudies app uses a flat `NavigationStack` with `NavigationLink` to each demo. Each demo creates its own `Store` via a `Demo<State, Action, Content>` wrapper. Key difference from SyncUps: no shared state between demos, no cross-feature navigation. This is a showcase pattern (feature catalogue), which is closer to what fuse-app needs.

### Recommended Fuse-App Architecture

**Hybrid approach:** Tab-based root (like current fuse-app) with NavigationStack per tab (like SyncUps). This demonstrates both TabView and NavigationStack, which together cover the broadest UI pattern surface.

```
FuseApp.swift              -- Root view, bridge annotations, FuseAppDelegate (KEEP + modify)
AppFeature.swift           -- @Reducer struct with tab enum state
CounterTab/
  CounterFeature.swift     -- Counter reducer + view
TodosTab/
  TodosFeature.swift       -- Todos list reducer + view
  TodoDetailFeature.swift  -- Todo detail with edit sheet + delete alert
NavigationTab/
  ContactsFeature.swift    -- Contacts list with NavigationStack
  ContactDetailFeature.swift -- Contact detail with @Dependency(\.dismiss)
  AddContactFeature.swift  -- Add contact sheet
SettingsTab/
  SettingsFeature.swift    -- Settings with @Shared persistence
DatabaseTab/
  DatabaseFeature.swift    -- SQLiteData CRUD showcase
SharedModels/
  Models.swift             -- Todo, Contact, DatabaseRecord models
  Dependencies.swift       -- Custom dependency clients
  SharedKeys.swift         -- SharedKey extensions for cross-feature state
```

### Feature Modules: In-Target Files vs Separate SPM Targets

**Recommendation: All features as files within the FuseApp target, NOT separate SPM targets.**

Rationale:
- fuse-app is a showcase, not a production app. Modular SPM targets add Package.swift complexity without payoff.
- Skip's `skipstone` plugin processes entire targets. Each new target means another Gradle module, increasing Android build time significantly.
- The SyncUps and CaseStudies reference apps both use a single target with files organized by feature.
- Separate targets would each need their own `skip.yml`, `Resources/`, and plugin declarations.
- Per D2, pure domain features go in fuse-library. But for a showcase app, the features ARE the app -- they exist to demonstrate patterns, not to be reused.

**Exception:** If any feature is genuinely reusable (e.g., `SharedModels`), it could be a separate target. But for Phase 7, keeping everything in FuseApp is the pragmatic choice.

### @Shared Persistence Across Features

SyncUps demonstrates the canonical pattern:

```swift
extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<SyncUp>>.Default {
    static var syncUps: Self {
        Self[.fileStorage(.documentsDirectory.appending(component: "sync-ups.json")), default: []]
    }
}
```

For the fuse-app showcase, define SharedKey extensions in `SharedKeys.swift`:

```swift
// App-wide shared state
extension SharedKey where Self == AppStorageKey<String>.Default {
    static var userName: Self { Self[.appStorage("userName"), default: "Skipper"] }
}

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var appearance: Self { Self[.appStorage("appearance"), default: ""] }
}

extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
    static var todos: Self {
        Self[.fileStorage(.documentsDirectory.appending(component: "todos.json")), default: []]
    }
}

extension SharedKey where Self == InMemoryKey<Int>.Default {
    static var selectedTab: Self { Self[.inMemory("selectedTab"), default: 0] }
}
```

This demonstrates SHR-01 (appStorage), SHR-02 (fileStorage), SHR-03 (inMemory), and SHR-04 (SharedKey extension with defaults) through natural app state.

### SQLiteData/GRDB Integration

**Recommendation: Isolated database tab with app-wide DI.**

The DatabaseFeature tab demonstrates:
- `@Table` model definition with `@Column` customisation
- `DatabaseMigrator` with version migration
- CRUD operations via StructuredQueries
- `@FetchAll` / `@FetchOne` observation for live UI updates
- `@Dependency(\.defaultDatabase)` injection

The database is configured once in the app entry point and injected via TCA's dependency system. Other features do NOT use the database -- they use `@Shared(.fileStorage)` for persistence, demonstrating that TCA persistence and database persistence are complementary approaches.

```swift
// In AppFeature or app entry point
Store(initialState: AppFeature.State()) {
    AppFeature()
} withDependencies: {
    $0.defaultDatabase = .liveValue
}
```

---

## 6. Android-Specific SwiftUI Feasibility

### SkipUI Component Support Audit

| SwiftUI Component | SkipUI Status | Notes |
|-------------------|--------------|-------|
| **TabView** | Supported | Full implementation with NavigationBar, HorizontalPager. `TabView(selection:)` works. |
| **NavigationStack** | Supported | `NavigationStack(path:root:destination:)` implemented. Type-erased implementation. |
| **NavigationLink(state:)** | Supported | Works with NavigationStack path-based routing. |
| **List** | Supported | ForEach, onDelete, onMove all work. |
| **Form** | Supported | Maps to Compose Column with appropriate styling. |
| **TextField** | Supported | Including `.textFieldStyle(.roundedBorder)`. |
| **Toggle** | Supported | Maps to Compose Switch. |
| **Picker** | Supported | Maps to Compose dropdown/dialog. |
| **Button** | Supported | Including `.buttonStyle(.borderless)`. |
| **Image(systemName:)** | Supported | Maps to Material icons. |
| **Label** | Supported | With icon and title. |
| **.sheet(item:)** | Supported | `sheet(item: Binding<Item?>)` and `sheet(isPresented:)` both implemented. `onDismiss` supported. |
| **.fullScreenCover** | Supported | `fullScreenCover(item:)` and `fullScreenCover(isPresented:)` both implemented. |
| **.alert** | Supported | Full implementation with title, message, actions. Multiple overloads. |
| **.confirmationDialog** | Supported | Full implementation with titleVisibility. Maps to Compose AlertDialog with action list. |
| **.popover** | Partial | `popover(isPresented:)` and `popover(item:)` exist in SkipUI but the TCA `Popover.swift` is entirely guarded out on Android (`#if !os(Android)`). SkipUI implements popover as a sheet fallback. |
| **DatePicker** | Supported | Maps to Compose date picker dialog. |
| **TextEditor** | Supported | Maps to Compose TextField with multiline. |
| **.toolbar** | Supported | ToolbarItem with placement. |
| **.navigationTitle** | Supported | Sets Compose TopAppBar title. |
| **.task { }** | Supported | Maps to LaunchedEffect. |
| **withAnimation** | Partial | Basic animations work. Complex spring/timing curves may differ. |
| **.environment()** | Supported | Maps to Compose CompositionLocal. |
| **.preferredColorScheme** | Supported | Maps to Compose MaterialTheme. |

### Components to AVOID in showcase

| Component | Reason |
|-----------|--------|
| `Color(.systemBackground)` | UIColor reference; use `Color.primary`/`.secondary` instead |
| `.safeAreaInset` | Limited SkipUI support |
| `Menu` | Limited SkipUI support |
| `LabelStyle` custom | May not transpile correctly |
| `ProgressView` | Supported but with visual differences |
| `.monospacedDigit()` | May not have effect on Android |
| `Text(template:)` | TCA CaseStudies helper, not standard SwiftUI |
| `Tagged<Self, UUID>` | SyncUps uses this; fuse-app should use plain `UUID` to avoid adding the `tagged` dependency |

### NavigationStack via Skip's Type-Erased Implementation

SkipUI's `NavigationStack` uses type-erased `Hashable` path elements internally. The TCA `NavigationStack(path:)` pattern works because:

1. TCA's `$store.scope(state: \.path, action: \.path)` produces a `Binding<Store<StackState<Path.State>, StackAction<Path.State, Path.Action>>>`.
2. The `NavigationStack(path:root:destination:)` overload from swift-navigation (not the stock SwiftUI one) accepts this binding.
3. On Android, SkipUI's NavigationStack implementation manages its own path state via Compose's navigation library.
4. The `destination:` closure receives a scoped store, and `switch store.case { }` provides type-safe routing.

**Known limitation:** Deep-linking (programmatic path manipulation from outside the view hierarchy) works at the data layer but the Compose navigation controller may not animate correctly for multi-push operations (e.g., `path.append(A); path.append(B); path.append(C)` in one action). Single push/pop works reliably.

---

## 7. Build Feasibility

### First `swift build` with all TCA deps

**Expected time:** 60-120 seconds (clean build).

The fuse-app currently builds in ~5s because it has minimal dependencies. Adding ComposableArchitecture (the heaviest fork, ~100 source files plus all transitive deps) will make the first clean build substantial. Incremental builds after initial compilation should be fast (~5-15s for app source changes only).

**Likely issues:**
- SPM identity conflict warnings (~20-30) -- cosmetic, non-blocking
- Possible macro compilation delays (first build compiles @Reducer, @ObservableState, @DependencyClient, @Table macro plugins)

### First `skip android build`

**Expected time:** 5-15 minutes (first build). 1-3 minutes (incremental).

This is the major unknown. Skip's Gradle plugin must:
1. Transpile all Swift source to Kotlin (the FuseApp target)
2. Resolve all fork dependencies via the skipstone plugin
3. Compile Kotlin to JVM bytecode
4. Package as Android APK/AAB

**Likely issues:**
- B4 from reconciled research: GRDB `link "sqlite3"` may fail on Android NDK. Phase 6 fork work should have addressed this via GRDB's built-in SQLite amalgamation, but it has never been tested in an app context.
- P1-3: GRDB/sqlite-data `import Combine` without OpenCombineShim guard -- may fail to compile on Android.
- New Swift modules entering the transpilation pipeline for the first time may surface SkipUI bridging gaps.

### Incremental Build Strategy

**Recommendation: Build feature by feature, not all at once.**

1. Wire Package.swift with all dependencies. Verify `swift build` passes with no source changes (just the existing template code importing ComposableArchitecture).
2. Replace `ContentView.swift` with minimal AppFeature (single tab, counter only). Verify `swift build` + `skip android build`.
3. Add features one at a time. After each feature, verify `swift build`.
4. Run `skip android build` after every 2-3 features to catch Android-specific issues early.
5. Final `skip android build` + `skip test` after all features are complete.

---

## 8. SyncUps Pattern Analysis

### Structure Comparison

| Aspect | SyncUps | Fuse-App Showcase (proposed) |
|--------|---------|------------------------------|
| Root navigation | Single NavigationStack | TabView with NavigationStack per tab |
| Features | 5 (List, Detail, Form, Record, Meeting) | 5-6 (Counter, Todos, Contacts, Settings, Database) |
| Shared state | `@Shared(.syncUps)` fileStorage | Multiple: todos (fileStorage), settings (appStorage), tab (inMemory) |
| Navigation depth | 3 levels (List -> Detail -> Record) | 2 levels per tab (List -> Detail) |
| Presentation | Sheet (add form), Alert (delete, permissions) | Sheet (add/edit), Alert (delete), ConfirmationDialog |
| Dependencies | uuid, date, dismiss, openSettings, speechClient | uuid, date, dismiss, continuousClock, defaultDatabase, custom API client |
| Testing | TestStore per feature (Swift Testing) | TestStore per feature in FuseAppIntegrationTests |

### Patterns to Adopt from SyncUps

1. **`@Shared` with `SharedKey` extension for cross-feature data:**
   ```swift
   extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
       static var todos: Self {
           Self[.fileStorage(.documentsDirectory.appending(component: "todos.json")), default: []]
       }
   }
   ```

2. **`$shared.withLock { }` for mutations:**
   ```swift
   state.$todos.withLock { $0.append(newTodo) }
   // NOT: state.todos.append(newTodo) -- direct setter unavailable
   ```

3. **Delegate actions for cross-feature communication:**
   ```swift
   enum Action {
       case delegate(Delegate)
       @CasePathable
       enum Delegate {
           case todoSelected(Shared<Todo>)
       }
   }
   ```

4. **`@Presents` + `@Reducer enum Destination` for presentation:**
   ```swift
   @Reducer
   enum Destination {
       case addTodo(TodoFormFeature)
       @ReducerCaseEphemeral
       case alert(AlertState<Alert>)
       @CasePathable
       enum Alert { case confirmDeletion }
   }
   ```

5. **`Shared(value:)` in tests and previews:**
   ```swift
   TestStore(initialState: TodoDetail.State(todo: Shared(value: .mock))) { ... }
   ```

### Patterns from SyncUps NOT applicable

| Pattern | Reason to skip |
|---------|---------------|
| `Tagged<Self, UUID>` for IDs | Adds `swift-tagged` dependency not in our fork set. Use plain `UUID`. |
| `SpeechRecognizer` dependency | iOS-specific AVFoundation API. Not cross-platform. |
| `openSettings` dependency | iOS-specific `UIApplication.shared.open(URL(...))`. Noted in STATE.md as deferred. |
| `uncheckedUseMainSerialExecutor = true` in tests | Not available on Android. Tests must use effectDidSubscribe fallback. |
| `Duration.formatted(.units())` | May not render identically on Android. Use simple string formatting. |

---

## 9. Feature-by-Feature Implementation Checklist

### Feature 1: AppFeature (Root Coordinator)

**Purpose:** Tab-based root that composes all child features.

**File:** `Sources/FuseApp/AppFeature.swift`

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab = Tab.counter
        var counter = CounterFeature.State()
        var todos = TodosFeature.State()
        var contacts = ContactsFeature.State()
        var settings = SettingsFeature.State()
        var database = DatabaseFeature.State()

        enum Tab: Equatable { case counter, todos, contacts, settings, database }
    }

    enum Action {
        case counter(CounterFeature.Action)
        case todos(TodosFeature.Action)
        case contacts(ContactsFeature.Action)
        case settings(SettingsFeature.Action)
        case database(DatabaseFeature.Action)
        case tabSelected(State.Tab)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.counter, action: \.counter) { CounterFeature() }
        Scope(state: \.todos, action: \.todos) { TodosFeature() }
        Scope(state: \.contacts, action: \.contacts) { ContactsFeature() }
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }
        Scope(state: \.database, action: \.database) { DatabaseFeature() }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
            default:
                return .none
            }
        }
    }
}
```

**Requirements demonstrated:** TCA-02 (withDependencies at root store), TCA-04 (scope), TCA-05 (Scope reducer), TCA-09 (CombineReducers implicit)

**Implementation checklist:**
- [ ] Define `AppFeature` reducer with all child scopes
- [ ] Define `AppView` with TabView and per-tab NavigationStack
- [ ] Wire root Store in `FuseAppRootView` with `withDependencies`
- [ ] Keep bridge annotations (`/* SKIP @bridge */`) on `FuseAppRootView` and `FuseAppDelegate`
- [ ] Verify `swift build` compiles

---

### Feature 2: CounterFeature

**Purpose:** Simplest TCA feature. Entry point for understanding the pattern.

**File:** `Sources/FuseApp/CounterFeature.swift`

**Requirements demonstrated:**
- TCA-01: `Store.init(initialState:reducer:)`
- TCA-03: `store.send(.action)`
- TCA-10: `Effect.none`
- TCA-11: `Effect.run` (async fact fetch)
- TCA-16: `Effect.send` (synchronous dispatch)
- TCA-17: `@ObservableState`
- TCA-19: `BindableAction`
- TCA-20: `BindingReducer()`
- TCA-21: `@Bindable var store`, `$store.count`
- TCA-30: `._printChanges()`
- TCA-31: `@ViewAction(for:)`
- DEP-01: `@Dependency(\.continuousClock)`
- UI-03: `@State` tracking
- UI-04: Single view update per mutation

**Implementation checklist:**
- [ ] Define `CounterFeature` reducer with `@ObservableState`, `BindableAction`, `BindingReducer`
- [ ] Actions: increment, decrement, factButtonTapped, factResponse, reset, binding
- [ ] Effect: `Effect.run` to fetch number fact (mock implementation, no network)
- [ ] View: HStack with +/- buttons, count display, fact display, reset button
- [ ] `@ViewAction(for: CounterFeature.self)` on view
- [ ] `._printChanges()` on reducer
- [ ] Verify view correctly shows count and responds to taps

---

### Feature 3: TodosFeature

**Purpose:** Collection management with shared persistence and child composition.

**File:** `Sources/FuseApp/TodosFeature.swift`

**Requirements demonstrated:**
- TCA-04: `store.scope` for child
- TCA-05: `Scope(state:action:)` child reducer
- TCA-07: `.forEach(\.todos, action: \.todo)`
- TCA-09: `CombineReducers { }`
- TCA-23: `store.scope` in ForEach
- TCA-29: `.onChange(of:)` for stats
- IC-01..IC-06: `IdentifiedArrayOf<Todo>` all operations
- SHR-02: `@Shared(.fileStorage(url))` for todo persistence
- SHR-04: `SharedKey` extension with defaults
- SHR-05: `$shared` binding projection
- SHR-06: `$shared` mutation triggers recomposition
- SHR-07: `$parent.child` keypath projection
- SHR-12: Multiple `@Shared` same backing store
- SHR-13: Child mutation visible in parent
- CP-01..CP-06: `@CasePathable` for filter enum
- UI-08: Multiple buttons in Form

**Implementation checklist:**
- [ ] Define `Todo` model: `struct Todo: Equatable, Identifiable, Codable` with `id: UUID`, `title: String`, `isComplete: Bool`, `createdAt: Date`
- [ ] Define `TodosFeature` reducer with `@Shared(.todos)`, `@Presents` for add sheet
- [ ] Define `TodoRowFeature` child reducer for individual todo toggle/edit
- [ ] `.forEach` composition for todo list
- [ ] `.onChange(of: \.stats)` to track completed count
- [ ] Add/delete/toggle operations using `$todos.withLock { }`
- [ ] Filter: all/active/completed via `@CasePathable enum Filter`
- [ ] View: List with ForEach, swipe-to-delete, toolbar add button
- [ ] Sheet for adding new todo

---

### Feature 4: ContactsFeature (Navigation Showcase)

**Purpose:** Full navigation pattern showcase -- stack, sheets, alerts, dialogs, dismiss.

**File:** `Sources/FuseApp/ContactsFeature.swift`

**Requirements demonstrated:**
- TCA-06: `.ifLet(\.$destination, action:)`
- TCA-08: `.ifCaseLet` (via `@Reducer enum Path`)
- TCA-24: Optional scoping
- TCA-25: `switch store.case { }`
- TCA-26: `@Dependency(\.dismiss)`
- TCA-27: `@Presents`
- TCA-28: `PresentationAction.dismiss`
- TCA-32: `StackState<Path.State>`
- TCA-33: `StackAction` (push/popFrom/element)
- TCA-34: `@ReducerCaseEphemeral`
- TCA-35: `@ReducerCaseIgnored`
- CP-07: `@Reducer enum` pattern
- NAV-01: NavigationStack with store scope
- NAV-02: Path append (push)
- NAV-03: Path removeLast (pop)
- NAV-04: `navigationDestination(item:)`
- NAV-05: `.sheet(item: $store.scope(...))`
- NAV-06: `.sheet` onDismiss
- NAV-08: `.fullScreenCover(item: $store.scope(...))`
- NAV-09: `.alert` with AlertState
- NAV-10: Alert button roles (destructive, cancel)
- NAV-11: `.confirmationDialog` with ConfirmationDialogState
- NAV-14: Dismiss via nil binding
- NAV-15: Binding subscript with CaseKeyPath
- UI-01: Task in action closure
- UI-05: `.sheet(isPresented:)` toggle
- UI-06: `.task { }` modifier

**Implementation checklist:**
- [ ] Define `Contact` model: `id: UUID`, `name: String`, `email: String`
- [ ] Define `ContactsFeature` with `@Reducer enum Path` (detail, edit)
- [ ] Define `ContactDetailFeature` with `@Presents Destination` (alert, editSheet, deleteDialog)
- [ ] Define `AddContactFeature` with form fields and validation
- [ ] `NavigationStack(path: $store.scope(state: \.path, action: \.path))`
- [ ] `switch store.case { }` in destination closure
- [ ] Sheet: add contact form
- [ ] FullScreenCover: contact detail expanded view
- [ ] Alert: delete confirmation with `.destructive` role
- [ ] ConfirmationDialog: action options
- [ ] `@Dependency(\.dismiss)` for child feature dismissal
- [ ] `@ReducerCaseEphemeral` on alert/dialog cases
- [ ] `.task { }` for loading contacts on appear

---

### Feature 5: SettingsFeature

**Purpose:** Shared state persistence showcase -- all SharedKey types plus dependency injection.

**File:** `Sources/FuseApp/SettingsFeature.swift`

**Requirements demonstrated:**
- SHR-01: `@Shared(.appStorage("key"))`
- SHR-02: `@Shared(.fileStorage(url))` (cross-reference with todos)
- SHR-03: `@Shared(.inMemory("key"))`
- SHR-08: `Shared($optional)` unwrapping
- SHR-09: `Observations { }` async sequence (display live mutation count)
- SHR-10: `$shared.publisher`
- SHR-11: `@ObservationIgnored @Shared`
- SHR-14: Custom `SharedKey` implementation
- TCA-18: `@ObservationStateIgnored`
- TCA-22: `$store.property.sending(\.action)`
- DEP-02: `@Dependency(Type.self)`
- DEP-03..DEP-05: `DependencyKey` with liveValue/testValue/previewValue
- DEP-06: `DependencyValues` extension
- DEP-07: `@DependencyClient` macro
- DEP-08: `Reducer.dependency(_:_:)` modifier
- DEP-09: `withDependencies { } operation: { }`
- DEP-10: `prepareDependencies`
- DEP-11: Child scope inheritance
- DEP-12: Effect closure resolution

**Implementation checklist:**
- [ ] `@Shared(.appStorage("userName"))` for display name
- [ ] `@Shared(.appStorage("appearance"))` for color scheme
- [ ] `@Shared(.inMemory("notificationCount"))` for session counter
- [ ] Custom `SharedKey` (e.g., `TimestampKey` that stores last-used timestamp)
- [ ] `@ObservationIgnored @Shared` on a diagnostic field
- [ ] `@ObservationStateIgnored` on a debug-only field
- [ ] `$store.appearance.sending(\.appearanceChanged)` binding
- [ ] `@DependencyClient` for a settings API client
- [ ] View: Form with name field, appearance picker, notification count display, version info

---

### Feature 6: DatabaseFeature

**Purpose:** SQLiteData + StructuredQueries showcase.

**File:** `Sources/FuseApp/DatabaseFeature.swift`

**Requirements demonstrated:**
- SQL-01: `@Table` macro
- SQL-02: `@Column(primaryKey:)`
- SQL-05: `.select { }`
- SQL-06: `.where { }` predicates
- SQL-07: `.find(id)`
- SQL-10: `.order { }`
- SQL-13: `.insert { }` / `.upsert { }`
- SQL-14: `.update { }` / `.delete()`
- SD-01: `defaultDatabase()`
- SD-02: `DatabaseMigrator`
- SD-03..SD-05: sync/async read/write
- SD-06..SD-08: fetchAll, fetchOne, fetchCount
- SD-09..SD-10: `@FetchAll`, `@FetchOne` observation (compile + wire, note Android DynamicProperty limitation)
- SD-12: `@Dependency(\.defaultDatabase)`

**Implementation checklist:**
- [ ] Define `@Table struct Note` with `id`, `title`, `body`, `createdAt`, `category`
- [ ] Define `DatabaseMigrator` with v1 schema creation
- [ ] Define `DatabaseFeature` reducer with CRUD actions
- [ ] `@Dependency(\.defaultDatabase)` injection
- [ ] View: List of notes with add/edit/delete, category filter
- [ ] Display record count via `fetchCount`
- [ ] Wire `@FetchAll` observation for live updates (with documented Android DynamicProperty caveat)

---

### Shared Models and Dependencies

**File:** `Sources/FuseApp/SharedModels.swift`

```swift
// Domain models
struct Todo: Equatable, Identifiable, Codable { ... }
struct Contact: Equatable, Identifiable, Codable, Hashable { ... }

// SharedKey extensions
extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
    static var todos: Self { ... }
}
extension SharedKey where Self == AppStorageKey<String>.Default {
    static var userName: Self { ... }
    static var appearance: Self { ... }
}
extension SharedKey where Self == InMemoryKey<Int>.Default {
    static var selectedTab: Self { ... }
}
```

**File:** `Sources/FuseApp/AppDependencies.swift`

```swift
// Custom dependency client
@DependencyClient
struct NumberFactClient: Sendable {
    var fetch: @Sendable (Int) async throws -> String
}

extension NumberFactClient: DependencyKey {
    static let liveValue = Self(
        fetch: { number in "The number \(number) is interesting!" }
    )
    static let testValue = Self()
    static let previewValue = Self(
        fetch: { number in "Preview fact for \(number)" }
    )
}

extension DependencyValues {
    var numberFact: NumberFactClient {
        get { self[NumberFactClient.self] }
        set { self[NumberFactClient.self] = newValue }
    }
}
```

---

## 10. File Structure Summary

```
examples/fuse-app/Sources/FuseApp/
  FuseApp.swift              -- Root view + delegate (MODIFIED from template)
  AppFeature.swift            -- Root coordinator reducer + tab view
  CounterFeature.swift        -- Counter reducer + view
  TodosFeature.swift          -- Todos list + row reducer + views
  ContactsFeature.swift       -- Navigation showcase reducer + views
  SettingsFeature.swift       -- Settings + shared state reducer + view
  DatabaseFeature.swift       -- Database CRUD reducer + view
  SharedModels.swift           -- Todo, Contact models + SharedKey extensions
  AppDependencies.swift        -- NumberFactClient, database setup
  Resources/                   -- (existing)
  Skip/skip.yml                -- (existing, unchanged)

examples/fuse-app/Tests/
  FuseAppTests/
    XCSkipTests.swift          -- (existing, unchanged)
  FuseAppIntegrationTests/
    CounterFeatureTests.swift  -- TestStore tests for counter
    TodosFeatureTests.swift    -- TestStore tests for todos
    ContactsFeatureTests.swift -- TestStore tests for contacts
    AppFeatureTests.swift      -- Integration tests for root coordinator
```

**Total new files:** 9 source files + 4 test files = 13 files
**Total deleted files:** 2 (ContentView.swift, ViewModel.swift) + 1 test (FuseAppViewModelTests/)
**Total modified files:** 2 (FuseApp.swift, Package.swift)

---

## 11. TestStore Integration Tests

Each feature gets a corresponding test file in `FuseAppIntegrationTests`. These demonstrate TEST-01..TEST-09.

**Pattern (from SyncUps):**

```swift
import ComposableArchitecture
import Testing
@testable import FuseApp

@MainActor
struct CounterFeatureTests {
    // TEST-01: TestStore init
    @Test func initialization() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }
        // Verify initial state
        #expect(store.state.count == 0)
    }

    // TEST-02: send with state assertion
    @Test func increment() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }
        await store.send(.incrementButtonTapped) {
            $0.count = 1
        }
    }

    // TEST-03: receive effect action
    @Test func factRequest() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        } withDependencies: {
            $0.numberFact.fetch = { _ in "Test fact" }
        }
        await store.send(.factButtonTapped) {
            $0.isLoading = true
        }
        await store.receive(\.factResponse.success) {
            $0.isLoading = false
            $0.fact = "Test fact"
        }
    }

    // TEST-04: exhaustivity on (default)
    @Test func exhaustivityOn() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }
        // store.exhaustivity is .on by default -- any unasserted state change fails
        await store.send(.incrementButtonTapped) {
            $0.count = 1  // Must assert ALL changes
        }
    }

    // TEST-05: exhaustivity off
    @Test func exhaustivityOff() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }
        store.exhaustivity = .off
        await store.send(.incrementButtonTapped)
        // No assertion needed -- non-exhaustive mode
    }

    // TEST-06: finish waits for effects
    @Test func finish() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        } withDependencies: {
            $0.numberFact.fetch = { _ in "Fact" }
        }
        await store.send(.factButtonTapped) { $0.isLoading = true }
        await store.receive(\.factResponse.success) {
            $0.isLoading = false
            $0.fact = "Fact"
        }
        await store.finish()
    }

    // TEST-09: .dependencies test trait
    @Test(.dependencies { $0.numberFact.fetch = { _ in "Overridden" } })
    func dependenciesTrait() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }
        await store.send(.factButtonTapped) { $0.isLoading = true }
        await store.receive(\.factResponse.success) {
            $0.isLoading = false
            $0.fact = "Overridden"
        }
    }
}
```

**Note on Android:** These tests use Swift Testing (`@Test`) not XCTest. They go in a non-skipstone target (`FuseAppIntegrationTests` has no `skipstone` plugin), so they run on macOS only. Android TestStore validation is covered by the separate 07-01 plan in fuse-library.

---

## 12. Risk Assessment and Mitigations

### Risk 1: Package.swift resolution failure (HIGH)

Adding 13 new fork path dependencies to fuse-app may cause SPM resolution conflicts beyond cosmetic warnings.

**Mitigation:** Wire dependencies incrementally. Add 3-4 at a time and run `swift package resolve` after each batch. Start with the leaf dependencies (xctest-dynamic-overlay, swift-case-paths, swift-identified-collections) before the heavy ones (swift-composable-architecture, sqlite-data).

### Risk 2: Skip Android build failure with TCA (HIGH)

The fuse-app has never been built for Android with TCA dependencies. ComposableArchitecture has ~100 source files, many with `#if !os(Android)` guards that may interact unexpectedly with Skip's transpiler.

**Mitigation:** Build incrementally. First verify `skip android build` works with the existing template code plus TCA dependencies (import but don't use). Then add features one by one.

### Risk 3: SQLite linker failure on Android (HIGH)

B4 from reconciled research. GRDB's `link "sqlite3"` may fail because Android NDK doesn't ship libsqlite3.

**Mitigation:** Verify via `skip android sdk path` search for sqlite3. If absent, the DatabaseFeature can be excluded from the first Android build and addressed separately.

### Risk 4: Scope creep from D1 (MEDIUM)

D1 says "every non-deprecated, current, public API." This is technically impossible in a single app -- some APIs are testing-only (TestStore), some are build-time (SPM), some need Android runtime (OBS bridge). The showcase should demonstrate the user-facing API surface, not the testing/build infrastructure.

**Mitigation:** Define TEST-12 as "demonstrates the 5 pillars (TCA core, state, navigation, persistence, database) through a navigable app." The 226 existing tests provide exhaustive API coverage. The app proves integration, not individual API correctness.

### Risk 5: @Shared no-op notifications on Android (MEDIUM)

Per R8, `@Shared(.fileStorage)` and `@Shared(.appStorage)` change notifications are no-ops on Android. The showcase app will work (TCA's Compose recomposition handles in-app changes) but external changes are invisible.

**Mitigation:** Document in showcase README. Test write-then-read path. Don't rely on cross-process notification in the showcase.

---

## 13. Recommendations

### R1: Keep features as files, not separate SPM targets

All 7 feature files (AppFeature, Counter, Todos, Contacts, Settings, Database, SharedModels) go in the single FuseApp target. No new SPM library targets. This avoids Skip/Gradle module explosion and keeps Package.swift manageable.

### R2: Build incrementally, verify at each step

1. Package.swift wiring (verify `swift package resolve`)
2. Empty TCA import (verify `swift build`)
3. AppFeature + CounterFeature (verify `swift build` + `skip android build`)
4. Add TodosFeature (verify `swift build`)
5. Add ContactsFeature (verify `swift build`)
6. Add SettingsFeature (verify `swift build`)
7. Add DatabaseFeature (verify `swift build` + `skip android build`)
8. Final `skip test` pass

### R3: Use SyncUps patterns, not CaseStudies patterns

SyncUps is the canonical modern TCA reference. CaseStudies is a flat showcase without real composition. The fuse-app should follow SyncUps' delegate action pattern, `@Shared` SharedKey extension pattern, and `@Reducer enum` navigation pattern.

### R4: Skip popover, use sheet fallback

The TCA `Popover.swift` is entirely excluded on Android. The showcase should use `.sheet` where SyncUps would use `.popover`. Skip rendering of NAV-07 (popover) is documented as "renders as sheet on Android."

### R5: Database feature is isolated, not integrated

The DatabaseFeature gets its own tab. It does NOT serve as the persistence backend for other features. Todos use `@Shared(.fileStorage)`, settings use `@Shared(.appStorage)`. This keeps the demo clear and avoids coupling database + TCA complexity.

### R6: Test files use Swift Testing, not XCTest

Follow SyncUps' pattern: `@MainActor struct FeatureTests` with `@Test` functions. Swift Testing's `#expect` is cleaner than `XCTAssert*` and works well with TestStore's async API. Note: `uncheckedUseMainSerialExecutor = true` is NOT available on Android, so these tests run macOS-only in `FuseAppIntegrationTests`.

### R7: Timeline estimate

| Step | Duration |
|------|----------|
| Package.swift wiring + resolve verification | 3-5 min |
| CounterFeature + AppFeature + FuseApp.swift modification | 5-8 min |
| TodosFeature | 5-8 min |
| ContactsFeature (most complex) | 8-12 min |
| SettingsFeature | 5-7 min |
| DatabaseFeature | 5-8 min |
| Integration tests (4 test files) | 5-8 min |
| `swift build` + `skip android build` verification | 5-10 min |
| **Total estimated** | **40-65 min** |

This aligns with R10's estimate of ~30 min for the showcase plan (07-03), noting R10 assumes TestStore tests are in a separate plan (07-01).

---

*Research completed: 2026-02-22*
*Data sources: SyncUps example app, CaseStudies example app, fuse-app source, fuse-library Package.swift, REQUIREMENTS.md, R4, R8, R9, R10, SkipUI source (TabView, Navigation, Presentation)*
