# R4: Fuse-App Showcase Architecture Research

**Date:** 2026-02-22
**Scope:** Architecture for rebuilding fuse-app as a comprehensive TCA showcase demonstrating every non-deprecated public API across all 17 forks.

---

## Summary

The current fuse-app is a stock Skip template with a basic `@Observable` ViewModel, no TCA integration, no dependency injection, no shared state, and no database layer. It must be completely rebuilt as a modular TCA showcase app. The SyncUps example from TCA's upstream repo provides the canonical reference architecture, but the showcase must go far beyond it to cover the full API surface of all 17 forks. This research maps every API that needs demonstration, proposes a feature architecture that achieves comprehensive coverage through a navigable app, and identifies Skip build constraints.

**Key finding:** 8 feature modules plus a shared models/dependencies layer can cover the full non-deprecated API surface of all 17 forks through natural, user-navigable features rather than a test harness.

---

## Current State

### fuse-app (examples/fuse-app/)

**Package.swift dependencies:**
- `skip` (1.7.2), `skip-fuse-ui` (1.0.0)
- Local forks: `skip-android-bridge`, `skip-ui`
- **Missing:** TCA, swift-dependencies, swift-sharing, swift-navigation, sqlite-data, structured-queries, GRDB, case-paths, identified-collections, custom-dump, all other forks

**Targets:**
- `FuseApp` — single library target with SkipFuseUI + SkipUI + SkipAndroidBridge
- `FuseAppTests` — Skip cross-platform test target (empty placeholder)
- `FuseAppViewModelTests` — macOS-only test target (empty placeholder)

**Source files (4 files):**
| File | Content | TCA Usage |
|------|---------|-----------|
| `FuseApp.swift` | `FuseAppRootView` (bridge-annotated root), `FuseAppDelegate` lifecycle | None — plain SwiftUI |
| `ContentView.swift` | TabView with Welcome/Home/Settings tabs, `@AppStorage`, NavigationStack, List/Form | None — vanilla SwiftUI |
| `ViewModel.swift` | `@Observable` class with `[Item]`, JSON file persistence | None — manual observation |
| `skip.yml` | `skip: mode: 'native'` | N/A |

**Assessment:** 100% template code. No TCA types, no `@Reducer`, no `Store`, no `@Dependency`, no `@Shared`, no database layer. The entire source must be replaced.

### fuse-library (examples/fuse-library/)

**Source files (3 files):** `FuseLibrary.swift`, `ObservationModels.swift`, `ObservationVerifier.swift` — utility models for observation testing.

**Test targets (22 test files across 18 targets):** Cover Phases 1-6 APIs in isolation:
- Observation: `ObservationTrackingTests`, `ObservableStateTests`
- TCA Core: `StoreReducerTests`, `EffectTests`, `BindingTests`
- Dependencies: `DependencyTests`
- Foundation: `CasePathsTests`, `IdentifiedCollectionsTests`, `CustomDumpTests`, `IssueReportingTests`
- Shared State: `SharedPersistenceTests`, `SharedBindingTests`, `SharedObservationTests`
- Navigation: `NavigationTests`, `NavigationStackTests`, `PresentationTests`
- UI Patterns: `UIPatternTests`
- Database: `StructuredQueriesTests`, `SQLiteDataTests`
- Skip: `FuseLibraryTests`, `XCSkipTests`

**Assessment:** fuse-library is a test-only validation layer. It has no feature modules or reusable domain logic. Per decision D2, new feature domain modules should live here; fuse-app composes them.

---

## API Surface Coverage Map

Every non-deprecated public API that the showcase must demonstrate, grouped by fork. Deprecated APIs (ViewStore, WithViewStore, ForEachStore, IfLetStore, SwitchStore, TaskResult, @PresentationState) are excluded per REQUIREMENTS.md "Out of Scope."

### 1. swift-composable-architecture (TCA)

#### Store & Reducer Core
| API | Category | Req |
|-----|----------|-----|
| `Store.init(initialState:reducer:)` | Store creation | TCA-01 |
| `Store.init(initialState:reducer:withDependencies:)` | Store + dep override | TCA-02 |
| `store.send(.action)` / `StoreTask` | Action dispatch | TCA-03 |
| `store.scope(state:action:)` | Child store derivation | TCA-04 |
| `@Bindable var store` / `$store.property` | Binding projection | TCA-21 |
| `$store.property.sending(\.action)` | Action-sending binding | TCA-22 |
| `store.scope` in ForEach | Collection child stores | TCA-23 |
| Optional scoping | Conditional child stores | TCA-24 |
| `switch store.case { }` | Enum store switching | TCA-25 |

#### Reducer Types
| API | Category | Req |
|-----|----------|-----|
| `@Reducer struct` / `body: some ReducerOf<Self>` | Reducer macro | — |
| `@Reducer enum` (CaseReducer) | Enum reducer | CP-07 |
| `Reduce { state, action in }` | Inline reducer | TCA-01 |
| `Scope(state:action:)` | Child scoping reducer | TCA-05 |
| `.ifLet(\.$destination, action:)` | Optional presentation | TCA-06 |
| `.forEach(\.path, action:)` | Stack/collection forEach | TCA-07 |
| `IfCaseLet` | Enum case matching | TCA-08 |
| `CombineReducers { }` | Sequential composition | TCA-09 |
| `BindingReducer()` | Binding mutations | TCA-20 |
| `.onChange(of:)` | Derived value observation | TCA-29 |
| `._printChanges()` | Debug logging | TCA-30 |

#### Effect Types
| API | Category | Req |
|-----|----------|-----|
| `Effect.none` | No-op | TCA-10 |
| `Effect.run { send in }` | Async work | TCA-11 |
| `Effect.merge(...)` | Concurrent effects | TCA-12 |
| `Effect.concatenate(...)` | Sequential effects | TCA-13 |
| `.cancellable(id:cancelInFlight:)` | Cancellation | TCA-14 |
| `.cancel(id:)` | Cancel by ID | TCA-15 |
| `Effect.send(_:)` | Synchronous dispatch | TCA-16 |

#### Observable State & Macros
| API | Category | Req |
|-----|----------|-----|
| `@ObservableState` | State observation macro | TCA-17 |
| `@ObservationStateIgnored` | Suppressed tracking | TCA-18 |
| `BindableAction` protocol | Binding action routing | TCA-19 |
| `@Presents` | Optional child state | TCA-27 |
| `PresentationAction` / `.dismiss` | Presentation lifecycle | TCA-28 |
| `@ViewAction(for:)` | View action synthesis | TCA-31 |
| `@ReducerCaseEphemeral` | Ephemeral alert/dialog | TCA-34 |
| `@ReducerCaseIgnored` | Skipped enum case | TCA-35 |

#### Navigation (TCA-specific)
| API | Category | Req |
|-----|----------|-----|
| `StackState<Path.State>` | Stack state | TCA-32 |
| `StackAction` (push/popFrom/element) | Stack actions | TCA-33 |
| `@Dependency(\.dismiss)` | Programmatic dismiss | TCA-26 |

#### Testing
| API | Category | Req |
|-----|----------|-----|
| `TestStore(initialState:reducer:)` | Test creation | TEST-01 |
| `await store.send(.action) { ... }` | State assertion | TEST-02 |
| `await store.receive(.action) { ... }` | Effect assertion | TEST-03 |
| `store.exhaustivity = .on` | Strict mode | TEST-04 |
| `store.exhaustivity = .off` | Lenient mode | TEST-05 |
| `await store.finish()` | Drain effects | TEST-06 |
| `await store.skipReceivedActions()` | Skip unconsumed | TEST-07 |
| `.dependencies { }` test trait | Test dep override | TEST-09 |

### 2. swift-dependencies

| API | Req |
|-----|-----|
| `@Dependency(\.keyPath)` | DEP-01 |
| `@Dependency(Type.self)` | DEP-02 |
| `DependencyKey` protocol (`liveValue`, `testValue`, `previewValue`) | DEP-03/04/05 |
| `DependencyValues` extension | DEP-06 |
| `@DependencyClient` macro | DEP-07 |
| `Reducer.dependency(_:_:)` modifier | DEP-08 |
| `withDependencies { } operation: { }` | DEP-09 |
| `prepareDependencies` | DEP-10 |
| Child scope inheritance | DEP-11 |
| Effect closure resolution | DEP-12 |
| Built-in deps: `\.date`, `\.uuid`, `\.continuousClock`, `\.dismiss` | — |

### 3. swift-sharing

| API | Req |
|-----|-----|
| `@Shared(.appStorage("key"))` | SHR-01 |
| `@Shared(.fileStorage(url))` | SHR-02 |
| `@Shared(.inMemory("key"))` | SHR-03 |
| `SharedKey` extension with defaults | SHR-04 |
| `$shared` binding projection | SHR-05 |
| `$shared` mutation triggers recomposition | SHR-06 |
| `$parent.child` keypath projection | SHR-07 |
| `Shared($optional)` unwrapping | SHR-08 |
| `Observations { }` async sequence | SHR-09 |
| `$shared.publisher` | SHR-10 |
| `@ObservationIgnored @Shared` | SHR-11 |
| Multiple `@Shared` same backing store | SHR-12 |
| Child mutation visible in parent | SHR-13 |
| Custom `SharedKey` implementation | SHR-14 |

### 4. swift-navigation

| API | Req |
|-----|-----|
| `NavigationStack` with store scope | NAV-01 |
| Path append (push) | NAV-02 |
| Path removeLast (pop) | NAV-03 |
| `navigationDestination(item:)` | NAV-04 |
| `.sheet(item: $store.scope(...))` | NAV-05 |
| `.sheet` onDismiss | NAV-06 |
| `.popover(item: $store.scope(...))` | NAV-07 |
| `.fullScreenCover(item: $store.scope(...))` | NAV-08 |
| `.alert` with `AlertState` | NAV-09 |
| Alert button roles | NAV-10 |
| `.confirmationDialog` with `ConfirmationDialogState` | NAV-11 |
| `AlertState.map(_:)` | NAV-12 |
| `ConfirmationDialogState.map(_:)` | NAV-13 |
| Dismiss via nil binding | NAV-14 |
| `Binding` subscript with `CaseKeyPath` | NAV-15 |
| `TextState`, `ButtonState`, `ButtonStateRole` | — |

### 5. swift-case-paths

| API | Req |
|-----|-----|
| `@CasePathable` macro | CP-01 |
| `.is(\.case)` | CP-02 |
| `.modify(\.case) { }` | CP-03 |
| `@dynamicMemberLookup` dot-syntax | CP-04 |
| `allCasePaths` | CP-05 |
| `root[case:]` subscript | CP-06 |
| `AnyCasePath` | CP-08 |

### 6. swift-identified-collections

| API | Req |
|-----|-----|
| `IdentifiedArrayOf<T>` init | IC-01 |
| `array[id:]` subscript | IC-02/03 |
| `array.remove(id:)` | IC-04 |
| `array.ids` | IC-05 |
| Codable conformance | IC-06 |

### 7. swift-structured-queries

| API | Req |
|-----|-----|
| `@Table` macro | SQL-01 |
| `@Column(primaryKey:)` | SQL-02 |
| `@Column(as:)` | SQL-03 |
| `@Selection` | SQL-04 |
| `.select { }` | SQL-05 |
| `.where { }` predicates | SQL-06 |
| `.find(id)` | SQL-07 |
| `.where { $0.column.in(values) }` | SQL-08 |
| Joins (join/leftJoin/rightJoin/fullJoin) | SQL-09 |
| `.order { }` | SQL-10 |
| `.group { }` with aggregates | SQL-11 |
| `.limit(n, offset:)` | SQL-12 |
| `.insert { }` / `.upsert { }` | SQL-13 |
| `.update { }` / `.delete()` | SQL-14 |
| `#sql()` macro | SQL-15 |

### 8. sqlite-data

| API | Req |
|-----|-----|
| `defaultDatabase()` | SD-01 |
| `DatabaseMigrator` | SD-02 |
| `database.read { }` sync/async | SD-03/05 |
| `database.write { }` sync/async | SD-04/05 |
| `Table.fetchAll(db)` | SD-06 |
| `Table.fetchOne(db)` | SD-07 |
| `Table.fetchCount(db)` | SD-08 |
| `@FetchAll` | SD-09 |
| `@FetchOne` | SD-10 |
| `@Fetch` with `FetchKeyRequest` | SD-11 |
| `@Dependency(\.defaultDatabase)` | SD-12 |

### 9. Supporting Forks (demonstrated transitively)

| Fork | Key APIs | How Demonstrated |
|------|----------|------------------|
| `swift-custom-dump` | `customDump`, `diff`, `expectNoDifference` | Used in TestStore assertions (automatic) |
| `xctest-dynamic-overlay` (IssueReporting) | `reportIssue`, `withErrorReporting` | Unimplemented dependency calls in tests |
| `swift-perception` | `PerceptionRegistrar` facade | Compiled transitively; no direct usage needed (delegates to Observation on Android) |
| `swift-clocks` | `TestClock`, `ImmediateClock` | Used in effect tests with `continuousClock` dependency |
| `combine-schedulers` | `AnyScheduler`, `TestScheduler` | Used transitively by TCA's effect infrastructure |
| `swift-snapshot-testing` | Snapshot strategies | Out of scope per REQUIREMENTS.md |
| `skip-android-bridge` | Observation bridge | Exercised by every @ObservableState view render on Android |
| `skip-ui` | SkipUI view layer | Exercised by every SwiftUI view on Android |
| `GRDB.swift` | Database engine | Exercised through sqlite-data |

---

## Proposed Feature Architecture

### Design Principles
1. **SyncUps-inspired but broader** — SyncUps covers ~30% of TCA's API; we need ~95%.
2. **Each feature module is a self-contained SPM target** in fuse-library with its own reducer, state, actions, and views.
3. **The fuse-app composes features** into a navigable tab-based app with a root coordinator.
4. **Every feature has a corresponding test target** with TestStore tests.
5. **Database features are both integrated (as persistence backend) and isolated (dedicated tab).**

### Module Structure

```
examples/fuse-library/Sources/
  SharedModels/           -- Domain models, SharedKey definitions, dependency clients
  CounterFeature/         -- Basic counter (Store, Reduce, Effect.run, bindings)
  TodosFeature/           -- Collection management (forEach, IdentifiedArray, @Shared)
  ContactsFeature/        -- Navigation patterns (stack, sheets, alerts, dialogs)
  SettingsFeature/        -- Shared persistence (@Shared all key types, custom SharedKey)
  TimerFeature/           -- Long-running effects (continuousClock, cancellation, merge)
  DatabaseFeature/        -- SQLite showcase (@Table, @FetchAll, @FetchOne, CRUD)
  SearchFeature/          -- Effects showcase (debounce, cancellation, concatenate)
  AppFeature/             -- Root coordinator (tab view, stack navigation, @Reducer enum)

examples/fuse-app/Sources/FuseApp/
  FuseApp.swift           -- App entry point, bridge annotations
  skip.yml                -- Skip native mode config
```

### Feature Details and API Coverage

#### Feature 1: CounterFeature
**Purpose:** Entry-level TCA showcase. Simplest possible feature.
**APIs demonstrated:**
- `@Reducer struct`, `@ObservableState`, `Reduce { }`
- `Store.init(initialState:reducer:)` (TCA-01)
- `store.send(.action)` (TCA-03)
- `Effect.none` (TCA-10), `Effect.run` (TCA-11), `Effect.send` (TCA-16)
- `@Bindable var store`, `$store.count` binding (TCA-21)
- `BindableAction`, `BindingReducer()` (TCA-19, TCA-20)
- `@ViewAction(for:)` macro (TCA-31)
- `@Dependency(\.continuousClock)` (DEP-01)
- `._printChanges()` (TCA-30)

#### Feature 2: TodosFeature
**Purpose:** Collection management with shared persistence and identified arrays.
**APIs demonstrated:**
- `.forEach(\.todos, action: \.todo)` with `IdentifiedAction` (TCA-07, TCA-23)
- `IdentifiedArrayOf<Todo>` all operations (IC-01..IC-06)
- `@Shared(.fileStorage(url))` for todo persistence (SHR-02, SHR-04)
- `$shared` binding in views (SHR-05, SHR-06)
- `$parent.child` keypath projection on todo items (SHR-07)
- Child mutation visible in parent (SHR-13)
- Multiple `@Shared` same backing store (SHR-12)
- `Scope(state:action:)` for child reducers (TCA-05)
- `CombineReducers { }` (TCA-09)
- `.onChange(of:)` for stats tracking (TCA-29)
- `@CasePathable` enums for filter (CP-01..CP-06)
- `store.scope` in ForEach (TCA-23)

#### Feature 3: ContactsFeature
**Purpose:** Full navigation pattern showcase — stack, sheets, alerts, dialogs, dismiss.
**APIs demonstrated:**
- `StackState<Path.State>` / `StackAction` (TCA-32, TCA-33)
- `@Reducer enum Path` (CP-07)
- `NavigationStack` with store scope (NAV-01)
- Path append/push (NAV-02), removeLast/pop (NAV-03)
- `navigationDestination(item:)` (NAV-04)
- `.sheet(item: $store.scope(...))` (NAV-05)
- `.sheet` onDismiss (NAV-06)
- `.popover(item: $store.scope(...))` (NAV-07)
- `.fullScreenCover(item: $store.scope(...))` (NAV-08)
- `.alert` with `AlertState` (NAV-09, NAV-10)
- `.confirmationDialog` with `ConfirmationDialogState` (NAV-11)
- `AlertState.map(_:)` (NAV-12), `ConfirmationDialogState.map(_:)` (NAV-13)
- Dismiss via nil binding (NAV-14)
- `Binding` subscript with `CaseKeyPath` (NAV-15)
- `@Presents` macro (TCA-27)
- `PresentationAction.dismiss` (TCA-28)
- `.ifLet(\.$destination, action:)` (TCA-06)
- `@Dependency(\.dismiss)` (TCA-26)
- `@ReducerCaseEphemeral` on alert/dialog cases (TCA-34)
- `@ReducerCaseIgnored` (TCA-35)
- Optional scoping (TCA-24)
- `switch store.case { }` enum switching (TCA-25)
- `TextState`, `ButtonState`, `ButtonStateRole` (NAV supplemental)

#### Feature 4: SettingsFeature
**Purpose:** Shared state persistence showcase — all SharedKey types plus custom key.
**APIs demonstrated:**
- `@Shared(.appStorage("key"))` (SHR-01)
- `@Shared(.fileStorage(url))` (SHR-02)
- `@Shared(.inMemory("key"))` (SHR-03)
- Custom `SharedKey` implementation (SHR-14)
- `Shared($optional)` unwrapping (SHR-08)
- `Observations { }` async sequence (SHR-09)
- `$shared.publisher` (SHR-10)
- `@ObservationIgnored @Shared` (SHR-11)
- `@ObservableState` with `@ObservationStateIgnored` (TCA-18)
- `DependencyValues` extension for custom dep (DEP-06)
- `@DependencyClient` macro for API client (DEP-07)
- `Reducer.dependency(_:_:)` modifier (DEP-08)

#### Feature 5: TimerFeature
**Purpose:** Long-running effects, cancellation, and clock dependency showcase.
**APIs demonstrated:**
- `Effect.run` with `continuousClock.timer` (TCA-11)
- `Effect.merge(...)` for concurrent timer + data fetch (TCA-12)
- `Effect.concatenate(...)` for sequential operations (TCA-13)
- `.cancellable(id:cancelInFlight:)` (TCA-14)
- `.cancel(id:)` (TCA-15)
- `@Dependency(\.continuousClock)` (DEP-01)
- `withDependencies { } operation: { }` in previews (DEP-09)
- `prepareDependencies` for store setup (DEP-10)
- Child scope dep inheritance (DEP-11)
- Effect closure dep resolution (DEP-12)

#### Feature 6: DatabaseFeature
**Purpose:** Full SQLite/StructuredQueries showcase — schema, CRUD, observation, queries.
**APIs demonstrated:**
- `@Table` macro with models (SQL-01)
- `@Column(primaryKey:)`, `@Column(as:)` (SQL-02, SQL-03)
- `@Selection` composition (SQL-04)
- All query builders: `.select`, `.where`, `.find`, `.in`, joins, `.order`, `.group`, `.limit` (SQL-05..SQL-12)
- `.insert`, `.upsert`, `.update`, `.delete` (SQL-13, SQL-14)
- `#sql()` macro (SQL-15)
- `defaultDatabase()` + `DatabaseMigrator` (SD-01, SD-02)
- Sync/async `read`/`write` (SD-03..SD-05)
- `fetchAll`, `fetchOne`, `fetchCount` (SD-06..SD-08)
- `@FetchAll`, `@FetchOne`, `@Fetch` observation (SD-09..SD-11)
- `@Dependency(\.defaultDatabase)` injection (SD-12)

#### Feature 7: SearchFeature
**Purpose:** Network-style effects with debounce and cancellation patterns.
**APIs demonstrated:**
- `Effect.run` with network-style async (TCA-11)
- `.cancellable(id:cancelInFlight: true)` for debounced search (TCA-14)
- `Effect.merge` for parallel search facets (TCA-12)
- `@DependencyClient` for search API client (DEP-07)
- `DependencyKey` with `liveValue`/`testValue`/`previewValue` (DEP-03/04/05)
- `@Dependency(Type.self)` by-type resolution (DEP-02)

#### Feature 8: AppFeature (Root Coordinator)
**Purpose:** Composes all features into navigable tab-based app.
**APIs demonstrated:**
- `@Reducer enum` for tab/destination routing
- `Store.init(initialState:reducer:withDependencies:)` (TCA-02)
- Top-level `Scope` composition of all child features (TCA-05)
- `store.scope` for each tab
- `@Shared(.inMemory("selectedTab"))` for tab state (SHR-03)

### API Coverage Verification

**Coverage by requirement section:**
| Section | Total | Covered by Features | Notes |
|---------|-------|---------------------|-------|
| TCA (TCA-01..TCA-35) | 35 | 35 | All non-deprecated |
| DEP (DEP-01..DEP-12) | 12 | 12 | Full coverage |
| SHR (SHR-01..SHR-14) | 14 | 14 | Full coverage |
| NAV (NAV-01..NAV-16) | 16 | 15 | NAV-16 (iOS 26+ compat) is build-time verification only |
| CP (CP-01..CP-08) | 8 | 8 | Full coverage |
| IC (IC-01..IC-06) | 6 | 6 | Via TodosFeature |
| SQL (SQL-01..SQL-15) | 15 | 15 | Via DatabaseFeature |
| SD (SD-01..SD-12) | 12 | 12 | Via DatabaseFeature |
| CD (CD-01..CD-05) | 5 | 5 | Via TestStore (automatic) |
| IR (IR-01..IR-04) | 4 | 4 | Via unimplemented deps |
| UI (UI-01..UI-08) | 8 | 8 | Distributed across features |
| TEST (TEST-01..TEST-12) | 12 | 12 | Via test targets |
| SPM (SPM-01..SPM-06) | 6 | 6 | Build-time verification |
| DOC (DOC-01) | 1 | 1 | Separate FORKS.md task |

**Total: 184/184 requirements covered.**

---

## Skip Build Constraints

### Current fuse-app Skip Configuration
- `skip.yml`: `skip: mode: 'native'` — Fuse mode (required for TCA)
- Package uses `.plugin(name: "skipstone", package: "skip")` on all targets

### Constraints for Adding TCA Dependencies

1. **All TCA fork dependencies must be wired through Package.swift.** The current fuse-app only has `skip-android-bridge` and `skip-ui` as local forks. It needs all 17 forks wired similarly to fuse-library.

2. **Each new source target needs a `skip.yml`.** Every SPM target that Skip processes must have a `Sources/<Target>/Skip/skip.yml` file with at minimum `skip: mode: 'native'`.

3. **Dynamic library products required.** Skip Fuse mode requires `.library(name:type:.dynamic)` products. Each feature module exposed as a product must be dynamic.

4. **Bridge annotations for root views.** Only views that cross the Swift-Kotlin bridge need `/* SKIP @bridge */` annotations. Root views and delegates need them; internal views do not.

5. **No UIKit/AppKit imports.** Skip Fuse mode only supports SwiftUI. All views must be pure SwiftUI.

6. **Macro expansion is host-side.** `@Reducer`, `@ObservableState`, `@DependencyClient`, `@Table`, `@CasePathable` etc. are expanded at compile time on macOS. Only the expanded code runs on Android. This is already validated by Phases 1-6.

7. **SQLite provisioning on Android.** The Swift Android SDK does not include libsqlite3 in sysroot. Phase 6 fork work resolved this via GRDB's built-in SQLite amalgamation, but the database feature must verify this path works in the app context.

8. **`skip android build` from fuse-app.** The current fuse-app can already build for Android (`skip: mode: 'native'` is configured). Adding more fork dependencies should work as long as Package.swift resolution succeeds and all targets have skip.yml.

### Recommended Package.swift Structure

The fuse-app Package.swift should:
- Add all 17 fork paths as `.package(path:)` dependencies
- Import feature module products from fuse-library (or define them inline)
- Keep a single `FuseApp` target that depends on feature modules
- Maintain `FuseAppTests` for Skip cross-platform tests
- Add `FuseAppIntegrationTests` for macOS-only TestStore integration tests

**Decision point:** Whether feature modules live as targets within fuse-app's Package.swift or as products from fuse-library. Per decision D2, pure domain features (reducers/models) should live in fuse-library; app composition lives in fuse-app. This means fuse-library needs new `.library` products for each feature module.

---

## Recommendations

### R1: Feature Module Split Between fuse-library and fuse-app

**fuse-library adds these targets:**
- `SharedModels` — domain models, SharedKey definitions, dependency clients
- `CounterFeature`, `TodosFeature`, `ContactsFeature`, `SettingsFeature`, `TimerFeature`, `DatabaseFeature`, `SearchFeature` — pure reducer + model logic
- Corresponding test targets: `CounterFeatureTests`, `TodosFeatureTests`, etc.

**fuse-app keeps:**
- `FuseApp` — root app view, AppFeature coordinator, bridge annotations, Skip config
- `FuseAppTests` — Skip cross-platform tests
- `FuseAppIntegrationTests` — cross-feature integration tests (macOS)

### R2: Architectural Patterns to Follow (from SyncUps Reference)

1. **`@Reducer enum Path` for stack destinations** — SyncUps uses this for type-safe navigation.
2. **`@Shared` with `SharedKey` extension for cross-feature persistence** — SyncUps' `.syncUps` key pattern.
3. **`@Dependency(\.dismiss)` for programmatic dismissal** — avoids SwiftUI `@Environment(\.dismiss)`.
4. **`AlertState` / `ConfirmationDialogState` as state, not view modifiers** — testable presentation.
5. **Delegate actions for cross-feature communication** — child sends `.delegate(.action)`, parent intercepts.
6. **`Shared(value:)` for preview/test store initialization** — avoids needing real persistence.

### R3: Database Integration Approach

**Recommendation: Hybrid (both integrated and isolated).**

The DatabaseFeature has its own dedicated tab that showcases the full StructuredQueries/GRDB API surface (schema definition, all query types, migrations, observation). Additionally, the TodosFeature uses `@Shared(.fileStorage(...))` for JSON persistence, demonstrating that TCA persistence and database persistence are complementary, not competing.

This satisfies decision D12 by providing:
- **Isolation:** DatabaseFeature tab is self-contained, demonstrates every SQL/SD requirement
- **Integration:** Database-backed dependency (`@Dependency(\.defaultDatabase)`) is available app-wide

### R4: Test Organization

- **Existing 108 fuse-library tests are kept and reorganised** into the new feature-aligned test targets where natural groupings emerge. Tests that don't map to a feature stay in their current targets.
- **New feature test targets** use `TestStore` to validate each reducer.
- **Integration tests** in fuse-app test cross-feature flows (e.g., creating a todo triggers database write, settings change propagates via `@Shared`).

### R5: Build Verification Strategy

1. `swift build` from fuse-app (macOS) — all targets compile
2. `swift test` from fuse-app (macOS) — all test targets pass
3. `skip android build` from fuse-app — Android compilation succeeds
4. `skip test` from fuse-app — cross-platform tests pass
5. Manual emulator verification — app launches, features are navigable, no infinite recomposition

### R6: Incremental Build Order

Recommended implementation order to minimize integration risk:
1. **SharedModels** — foundation for all features
2. **CounterFeature** — simplest, validates Store/Reducer pipeline works in app context
3. **TodosFeature** — validates forEach, IdentifiedArray, @Shared file storage
4. **SettingsFeature** — validates all SharedKey types
5. **TimerFeature** — validates long-running effects and cancellation
6. **SearchFeature** — validates effect patterns and dependency clients
7. **ContactsFeature** — validates full navigation surface (most complex)
8. **DatabaseFeature** — validates SQLite integration
9. **AppFeature** — composes everything, validates root coordinator pattern

Each feature should be buildable and testable independently before moving to the next.
