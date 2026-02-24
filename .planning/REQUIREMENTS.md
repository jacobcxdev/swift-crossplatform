# Requirements: Swift Cross-Platform

**Defined:** 2026-02-21
**Core Value:** Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases. Every requirement tests ONE API or pattern on Android.

### OBS: Observation & Reactivity

Bridge-level observation semantics and Swift Observation correctness on Android.

- [ ] **OBS-01**: View body evaluation on Android is wrapped with `withObservationTracking`, firing `onChange` exactly once per observation cycle (not once per mutation)
- [ ] **OBS-02**: `willSet` calls are suppressed during observation recording -- no per-mutation `MutableStateBacking` counter increments while `isEnabled` is true
- [ ] **OBS-03**: A single `MutableStateBacking.update(0)` JNI call triggers exactly one Compose recomposition per observation cycle
- [ ] **OBS-04**: Bridge initialization failure is detected and logged -- if `ViewObservation.nativeEnable()` fails, a visible error is produced instead of silent fallback to broken counter path
- [ ] **OBS-05**: Nested view hierarchies observe correctly -- parent and child views each maintain their own frame on the `ObservationRecording` stack
- [ ] **OBS-06**: ViewModifier bodies participate in observation tracking (not just View bodies)
- [ ] **OBS-07**: `ObservationRegistrar` initializes correctly on Android, bridging to `SkipAndroidBridge.Observation.ObservationRegistrar`
- [ ] **OBS-08**: `ObservationRegistrar.access(keyPath:)` records property access during observation on Android
- [ ] **OBS-09**: `ObservationRegistrar.willSet(keyPath:)` fires correctly on Android; suppressed when `ObservationRecording.isEnabled` is true
- [ ] **OBS-10**: `ObservationRegistrar.withMutation(of:keyPath:_:)` wraps mutations with willSet/didSet on Android
- [ ] **OBS-11**: `withObservationTracking(_:onChange:)` invokes native `Observation.withObservationTracking` via `ObservationModule` on Android
- [ ] **OBS-12**: `@Observable` macro synthesizes correct observation hooks on Android
- [ ] **OBS-13**: `@Observable` class property reads in view bodies trigger observation tracking on Android
- [ ] **OBS-14**: `@Observable` class property mutations trigger exactly one view update on Android
- [ ] **OBS-15**: Bulk mutations in `@Observable` classes coalesce into a single view update on Android
- [ ] **OBS-16**: `async` methods in `@Observable` classes execute on the correct actor on Android without deadlock
- [ ] **OBS-17**: `@ObservationIgnored` suppresses observation tracking for annotated properties on Android
- [ ] **OBS-18**: Optional `@Observable` model held as parent state correctly drives `.sheet`/`.fullScreenCover` presentation on Android
- [ ] **OBS-19**: `@Observable` classes implement `Equatable` via object identity (`===`) correctly on Android
- [ ] **OBS-20**: Bindings (`$model.property`) in view bodies correctly sync two-way changes with `@Observable` model properties on Android
- [ ] **OBS-21**: `ObservationRecording.startRecording()` and `stopAndObserve()` manage per-thread TLS frame stack on Android
- [ ] **OBS-22**: `ObservationRecording.recordAccess()` batches multiple property accesses into one trigger per frame on Android
- [ ] **OBS-23**: `BridgeObservationSupport.access()` JNI call maps to `MutableStateBacking.access(index)` on Android
- [ ] **OBS-24**: `BridgeObservationSupport.triggerSingleUpdate()` fires exactly one Compose recomposition via `Java_update(0)` on Android
- [ ] **OBS-25**: `Java_skip_ui_ViewObservation_nativeEnable()` JNI export resolves and sets `isEnabled=true` on Android
- [ ] **OBS-26**: `Java_skip_ui_ViewObservation_nativeStartRecording()` JNI export resolves on Android
- [ ] **OBS-27**: `Java_skip_ui_ViewObservation_nativeStopAndObserve()` JNI export resolves on Android
- [ ] **OBS-28**: `swiftThreadingFatal()` symbol export resolves on Android (workaround for `libswiftObservation.so` loading)
- [x] **OBS-29**: `PerceptionRegistrar` facade delegates to `ObservationRegistrar` on Android (conditional compilation path)
- [x] **OBS-30**: `withPerceptionTracking(_:onChange:)` delegates to `withObservationTracking` on Android

### TCA: Composable Architecture Core

Store, reducers, effects, and composition patterns on Android.

- [ ] **TCA-01**: `Store.init(initialState:reducer:)` initializes with correct initial state on Android
- [ ] **TCA-02**: `Store.init(initialState:reducer:withDependencies:)` -- `prepareDependencies` closure overrides dependencies at construction on Android
- [ ] **TCA-03**: `store.send(.action)` dispatches an action from a view and returns a `StoreTask` on Android
- [ ] **TCA-04**: `store.scope(state:action:)` derives a child store from a parent store on Android
- [ ] **TCA-05**: `Scope(state:action:)` reducer runs child reducer against parent state/action on Android
- [ ] **TCA-06**: `.ifLet(_:action:destination:)` runs child reducer when optional state is non-nil on Android
- [ ] **TCA-07**: `.forEach(_:action:destination:)` runs element reducer for each collection element on Android
- [ ] **TCA-08**: `.ifCaseLet(_:action:)` runs child reducer when enum state matches a specific case on Android
- [ ] **TCA-09**: `CombineReducers { }` builder syntax composes multiple reducers in sequence on Android
- [ ] **TCA-10**: `Effect.none` returns immediately without side effects on Android
- [ ] **TCA-11**: `Effect.run { send in }` executes async work and sends actions back into the store on Android
- [ ] **TCA-12**: `Effect.merge(...)` runs multiple effects concurrently on Android
- [ ] **TCA-13**: `Effect.concatenate(...)` runs effects sequentially in order on Android
- [ ] **TCA-14**: `Effect.cancellable(id:cancelInFlight:)` marks an effect as cancellable on Android
- [ ] **TCA-15**: `Effect.cancel(id:)` cancels in-flight effects by ID on Android
- [ ] **TCA-16**: `Effect.send(_:)` synchronously dispatches an action as an effect on Android
- [ ] **TCA-17**: `@ObservableState` macro synthesizes `_$id`, `_$observationRegistrar`, `_$willModify` on Android
- [ ] **TCA-18**: `@ObservationStateIgnored` suppresses observation tracking for annotated state properties on Android
- [ ] **TCA-19**: `BindableAction` protocol + `case binding(BindingAction<State>)` compiles and routes correctly on Android
- [ ] **TCA-20**: `BindingReducer()` applies binding mutations to state on Android
- [ ] **TCA-21**: `@Bindable var store` -- `$store.property` binding projection reads/writes state through the store on Android
- [ ] **TCA-22**: `$store.property.sending(\.action)` derives a binding that sends a specific action on mutation on Android
- [ ] **TCA-23**: `store.scope(state:action:)` in `ForEach` renders list of child stores on Android
- [ ] **TCA-24**: Optional scoping `store.scope(state: \.child, action: \.child)` renders conditional content on Android
- [ ] **TCA-25**: `switch store.case { }` enum store switching renders correctly on Android (`@Reducer enum` + `.case`)
- [ ] **TCA-26**: `@Dependency(\.dismiss) var dismiss` -- `await dismiss()` causes presenting feature to pop/dismiss on Android
- [ ] **TCA-27**: `@Presents` macro synthesizes property wrapper accessors for optional child state on Android
- [ ] **TCA-28**: `PresentationAction.dismiss` -- parent reducer sets optional child state to `nil` on Android
- [ ] **TCA-29**: `Reducer.onChange(of:_:)` runs nested reducer when a derived value changes on Android
- [ ] **TCA-30**: `Reducer._printChanges()` logs state diffs to console on Android
- [ ] **TCA-31**: `@ViewAction(for:)` macro synthesizes `send(_:)` for view actions on Android
- [ ] **TCA-32**: `StackState<Element>` initializes, appends, and indexes by `StackElementID` on Android
- [ ] **TCA-33**: `StackAction` (`.push`, `.popFrom`, `.element`) routes through `forEach` on Android
- [ ] **TCA-34**: `@ReducerCaseEphemeral` marks enum reducer case as ephemeral (alert/dialog) on Android
- [ ] **TCA-35**: `@ReducerCaseIgnored` skips body synthesis for an enum reducer case on Android

### DEP: Dependencies

Dependency injection and resolution on Android.

- [ ] **DEP-01**: `@Dependency(\.keyPath)` resolves a dependency from `DependencyValues` inside a reducer on Android
- [ ] **DEP-02**: `@Dependency(Type.self)` resolves a dependency by type conformance on Android
- [ ] **DEP-03**: `DependencyKey` protocol -- `liveValue` is used in production context on Android
- [ ] **DEP-04**: `DependencyKey.testValue` is used in test context on Android
- [ ] **DEP-05**: `DependencyKey.previewValue` is used in preview context on Android
- [ ] **DEP-06**: `DependencyValues` extension with computed property registers a custom dependency on Android
- [ ] **DEP-07**: `@DependencyClient` macro generates a client struct with `unimplemented` defaults on Android
- [ ] **DEP-08**: `Reducer.dependency(_:_:)` modifier overrides a dependency for a scoped reducer on Android
- [ ] **DEP-09**: `withDependencies { } operation: { }` scopes dependency overrides to a closure on Android
- [ ] **DEP-10**: `prepareDependencies` closure overrides dependencies before any `@Dependency` access on Android
- [ ] **DEP-11**: Child reducer scopes inherit parent dependency context on Android
- [ ] **DEP-12**: `@Dependency` in effect closures resolves the correct (potentially overridden) value on Android

### SHR: Shared State

`@Shared` state persistence and cross-feature sharing on Android.

- [ ] **SHR-01**: `@Shared(.appStorage("key"))` persists and restores state via UserDefaults on Android
- [ ] **SHR-02**: `@Shared(.fileStorage(url))` persists and restores `Codable` state via file system on Android
- [ ] **SHR-03**: `@Shared(.inMemory("key"))` shares state in-memory across features within a session on Android
- [ ] **SHR-04**: `@Shared` with `SharedKey` extension provides type-safe default values on Android
- [ ] **SHR-05**: `$shared` binding projection creates two-way SwiftUI binding on Android
- [ ] **SHR-06**: `$shared` binding mutations trigger view recomposition on Android
- [ ] **SHR-07**: `$parent.child` keypath projection derives a child `Shared` from parent on Android
- [ ] **SHR-08**: `Shared($optional)` unwrapping returns `Shared<T>` when non-nil on Android
- [ ] **SHR-09**: `Observations { }` async sequence emits on every `@Shared` mutation on Android
- [ ] **SHR-10**: `$shared.publisher` exposes Combine/OpenCombine publisher on Android
- [ ] **SHR-11**: `@ObservationIgnored @Shared` prevents double-notification in `@Observable` models on Android
- [ ] **SHR-12**: Multiple `@Shared` declarations with same backing store synchronize updates on Android
- [ ] **SHR-13**: Child component mutation of `@Shared` parent state is visible in parent on Android
- [ ] **SHR-14**: Custom `SharedKey` strategy can be implemented for user-defined persistence backends on Android

### NAV: Navigation

Navigation patterns and presentation lifecycle on Android.

- [ ] **NAV-01**: `NavigationStack` with `$store.scope(state: \.path, action: \.path)` renders on Android
- [ ] **NAV-02**: Path append pushes a new destination onto the navigation stack on Android
- [ ] **NAV-03**: Path removeLast pops the top destination from the navigation stack on Android
- [ ] **NAV-04**: `navigationDestination(item:)` with binding pushes destination on Android
- [x] **NAV-05**: `.sheet(item: $store.scope(...))` presents modal content on Android
- [ ] **NAV-06**: `.sheet` `onDismiss` closure fires when sheet is dismissed on Android
- [x] **NAV-07**: `.popover(item: $store.scope(...))` displays popover on Android
- [x] **NAV-08**: `.fullScreenCover(item: $store.scope(...))` presents full-screen content on Android
- [ ] **NAV-09**: `.alert` with `AlertState` renders alert with title, message, and buttons on Android
- [ ] **NAV-10**: Alert buttons with roles (`.destructive`, `.cancel`) render correctly on Android
- [ ] **NAV-11**: `.confirmationDialog` with `ConfirmationDialogState` renders action sheet on Android
- [ ] **NAV-12**: `AlertState.map(_:)` transforms action type on Android
- [ ] **NAV-13**: `ConfirmationDialogState.map(_:)` transforms action type on Android
- [ ] **NAV-14**: Dismissing a presented feature via binding (setting optional to `nil`) closes presentation on Android
- [ ] **NAV-15**: `Binding` subscript with `CaseKeyPath` extracts enum associated value on Android
- [ ] **NAV-16**: Navigation patterns are compatible with iOS 26+ APIs (excluding past deprecations)

### CP: CasePaths

Enum routing and pattern matching on Android.

- [ ] **CP-01**: `@CasePathable` macro generates `AllCasePaths` and `CaseKeyPath` accessors on Android
- [ ] **CP-02**: `.is(\.caseName)` returns correct `Bool` for case checking on Android
- [ ] **CP-03**: `.modify(\.caseName) { }` mutates associated value in-place on Android
- [ ] **CP-04**: `@dynamicMemberLookup` dot-syntax returns `Optional<AssociatedValue>` on Android
- [ ] **CP-05**: `allCasePaths` static variable returns collection of all case key paths on Android
- [ ] **CP-06**: `root[case: caseKeyPath]` subscript extracts/embeds associated value on Android
- [ ] **CP-07**: `@Reducer enum` pattern -- enum reducers synthesize `body` and `scope` on Android
- [ ] **CP-08**: `AnyCasePath` with custom embed/extract closures works on Android

### IC: Identified Collections

`IdentifiedArrayOf` correctness on Android.

- [ ] **IC-01**: `IdentifiedArrayOf<T>` initializes from array literal on Android
- [ ] **IC-02**: `array[id: id]` subscript read returns correct element in O(1) on Android
- [ ] **IC-03**: `array[id: id] = nil` subscript write removes element on Android
- [ ] **IC-04**: `array.remove(id:)` returns removed element on Android
- [ ] **IC-05**: `array.ids` property returns ordered set of all IDs on Android
- [ ] **IC-06**: `IdentifiedArrayOf` conforms to `Codable` when element is `Codable` on Android

### SQL: Structured Queries

Type-safe query building via StructuredQueries on Android.

- [ ] **SQL-01**: `@Table` macro generates correct table metadata on Android
- [ ] **SQL-02**: `@Column(primaryKey:)` custom primary key designation works on Android
- [ ] **SQL-03**: `@Column(as:)` custom column representations work on Android
- [ ] **SQL-04**: `@Selection` type composition for multi-column grouping works on Android
- [ ] **SQL-05**: `Table.select { }` tuple/closure column selection works on Android
- [ ] **SQL-06**: `Table.where { }` equality, comparison, and boolean predicates work on Android
- [ ] **SQL-07**: `Table.find(id)` primary key lookup works on Android
- [ ] **SQL-08**: `Table.where { $0.column.in(values) }` IN/NOT IN operators work on Android
- [ ] **SQL-09**: `Table.join()` / `leftJoin()` / `rightJoin()` / `fullJoin()` work on Android
- [ ] **SQL-10**: `Table.order { }` ascending/descending/collation ordering works on Android
- [ ] **SQL-11**: `Table.group { }` with `count()`/`avg()`/`sum()`/`min()`/`max()` aggregations work on Android
- [ ] **SQL-12**: `Table.limit(n, offset:)` pagination works on Android
- [ ] **SQL-13**: `Table.insert { }` / `Table.upsert { }` with draft and conflict resolution work on Android
- [ ] **SQL-14**: `Table.where(...).update { }` / `Table.find(id).delete()` mutation/deletion work on Android
- [ ] **SQL-15**: `#sql()` safe SQL macro with column interpolation works on Android

### SD: SQLiteData & GRDB

Database lifecycle, query execution, and observation on Android.

- [ ] **SD-01**: `SQLiteData.defaultDatabase()` initializes database connection on Android
- [ ] **SD-02**: `DatabaseMigrator` executes registered migrations on Android
- [ ] **SD-03**: `database.read { db in }` executes synchronous read-only transaction on Android
- [ ] **SD-04**: `database.write { db in }` executes synchronous write transaction on Android
- [ ] **SD-05**: `await database.read { }` / `await database.write { }` async transactions work on Android
- [ ] **SD-06**: `Table.fetchAll(db)` returns array of matching rows on Android
- [ ] **SD-07**: `Table.fetchOne(db)` returns optional single row on Android
- [ ] **SD-08**: `Table.fetchCount(db)` returns integer count on Android
- [ ] **SD-09**: `@FetchAll` observation macro triggers view updates when database changes on Android
- [ ] **SD-10**: `@FetchOne` observation macro triggers view updates for single-row queries on Android
- [ ] **SD-11**: `@Fetch` with `FetchKeyRequest` executes composite multi-query observations on Android
- [ ] **SD-12**: `@Dependency(\.defaultDatabase)` injects database into views and models on Android

### CD: Custom Dump

Value dumping, diffing, and assertion utilities on Android.

- [ ] **CD-01**: `customDump(_:)` outputs structured value representation on Android
- [ ] **CD-02**: `String(customDumping:)` creates string from value dump on Android
- [ ] **CD-03**: `diff(_:_:)` computes string diff between two values on Android
- [ ] **CD-04**: `expectNoDifference(_:_:)` asserts equality with diff output on failure on Android
- [ ] **CD-05**: `expectDifference(_:_:operation:changes:)` asserts value changes after operation on Android

### IR: Issue Reporting

Error reporting and handling on Android.

- [ ] **IR-01**: `reportIssue(_:)` reports a string message as a runtime issue on Android
- [ ] **IR-02**: `reportIssue(_:)` reports a thrown `Error` instance on Android
- [ ] **IR-03**: `withErrorReporting { }` synchronous wrapper catches and reports thrown errors on Android
- [ ] **IR-04**: `await withErrorReporting { }` async wrapper catches and reports thrown errors on Android

### UI: SwiftUI Patterns

Modern SwiftUI patterns used by TCA apps on Android.

- [x] **UI-01**: `Task { await method() }` in action closures executes async work without blocking recomposition on Android
- [x] **UI-02**: Custom `Binding` extensions via dynamic member lookup derive bindings correctly on Android
- [x] **UI-03**: `@State` variables initialized at view declaration are correctly tracked on Android
- [x] **UI-04**: State mutations in action closures trigger view body re-evaluation exactly once on Android
- [x] **UI-05**: `.sheet(isPresented:)` opens/dismisses correctly when backing binding changes on Android
- [x] **UI-06**: `.task { }` modifier executes async work on view appearance on Android
- [x] **UI-07**: Nested `@Observable` object graphs maintain correct observation semantics on Android
- [x] **UI-08**: Multiple buttons in a Form each trigger independent action closures on Android

### TEST: Testing & Developer Experience

Test infrastructure and project deliverables.

- [ ] **TEST-01**: `TestStore(initialState:reducer:)` initializes correctly on Android
- [ ] **TEST-02**: `await store.send(.action)` with trailing state assertion passes on Android
- [ ] **TEST-03**: `await store.receive(.action)` asserts effect-dispatched actions on Android
- [ ] **TEST-04**: `store.exhaustivity = .on` (default) fails test on unasserted state changes on Android
- [ ] **TEST-05**: `store.exhaustivity = .off` skips unasserted changes without failure on Android
- [ ] **TEST-06**: `await store.finish()` waits for all in-flight effects before test ends on Android
- [ ] **TEST-07**: `await store.skipReceivedActions()` discards unconsumed received actions on Android
- [ ] **TEST-08**: Deterministic async effect execution (alternative to `useMainSerialExecutor`) works on Android
- [ ] **TEST-09**: `.dependencies { }` test trait overrides dependencies for a test on Android
- [x] **TEST-10**: Integration tests verify observation bridge prevents infinite recomposition on Android emulator
- [x] **TEST-11**: Stress tests confirm stability under >1000 TCA state mutations/second on Android
- [x] **TEST-12**: A fuse-app example demonstrates full TCA app (store, reducer, effects, navigation, persistence) on both iOS and Android

### SPM: Build & Compilation

Package configuration and cross-compilation on Android.

- [x] **SPM-01**: `Context.environment["TARGET_OS_ANDROID"]` conditional flag enables Android-specific dependencies at SPM evaluation on Android
- [x] **SPM-02**: `type: .dynamic` library products generate dynamic frameworks via Skip's Fuse mode on Android
- [x] **SPM-03**: `.plugin(name: "skipstone", package: "skip")` processes targets via Skip code generation on Android
- [x] **SPM-04**: `.macro()` targets with SwiftSyntax dependencies compile for Android macro expansion
- [x] **SPM-05**: `.package(path: "...")` local fork overrides resolve correctly on Android
- [x] **SPM-06**: `swiftLanguageModes` and `swiftSettings` with `.define()` propagate to Android builds

### DOC: Documentation

- [x] **DOC-01**: FORKS.md documents every fork: original upstream version, commits ahead, key changes, rationale, and upstream PR candidates

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Fork Releases

- **REL-01**: Tagged stable releases on all jacobcxdev forks with semantic versioning
- **REL-02**: Automated upstream tracking (GitHub Actions monitoring upstream releases)
- **REL-03**: CI pipeline running tests on both iOS simulator and Android emulator

### Upstream Contributions

- **UPS-01**: PR to skip-tools demonstrating observation bridge fix (gated behind SKIP_BRIDGE)
- **UPS-02**: GitHub Discussion on Point-Free org documenting Android support strategy
- **UPS-03**: PR to swift-composable-architecture for Android platform support

### TCA 2.0

- **TCA2-01**: Migration path from TCA 1.x forks to TCA 2.0 when released
- **TCA2-02**: Remove OpenCombine dependency (TCA 2.0 eliminates Combine)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Skip Lite mode TCA support | Counter-based observation fundamentally incompatible with TCA mutation frequency |
| App-level observation wrappers | Fix must be at bridge level (skip-android-bridge/skip-ui), not in TCA or app code |
| KMP interop | This is a Swift-first effort; Kotlin Multiplatform is a separate ecosystem |
| Production applications | This repo produces framework tools, not end-user apps |
| UIKit navigation patterns | SwiftUI-only; UIKit bridging is not in scope |
| Animation parity | Focus on correctness first; animation fidelity is a polish concern |
| ~~Swift Perception backport on Android~~ | ~~Native `libswiftObservation.so` ships with Android Swift SDK; no backport needed~~ **RESCOPED to Phase 12** — TCA depends on `Perceptible` conformances and `WithPerceptionTracking` which are NOT in `libswiftObservation.so` |
| Automated fork rebasing | Manual upstream sync is sufficient for v1; automation is v2 |
| Snapshot testing on Android | Not used by TestStore or TCA testing infrastructure |
| Deprecated TCA APIs | ViewStore, WithViewStore, @PresentationState, TaskResult, ForEachStore, IfLetStore, SwitchStore -- use modern equivalents |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| OBS-01 | Phase 1 | Pending |
| OBS-02 | Phase 1 | Pending |
| OBS-03 | Phase 1 | Pending |
| OBS-04 | Phase 1 | Pending |
| OBS-05 | Phase 1 | Pending |
| OBS-06 | Phase 1 | Pending |
| OBS-07 | Phase 1 | Pending |
| OBS-08 | Phase 1 | Pending |
| OBS-09 | Phase 1 | Pending |
| OBS-10 | Phase 1 | Pending |
| OBS-11 | Phase 1 | Pending |
| OBS-12 | Phase 1 | Pending |
| OBS-13 | Phase 1 | Pending |
| OBS-14 | Phase 1 | Pending |
| OBS-15 | Phase 1 | Pending |
| OBS-16 | Phase 1 | Pending |
| OBS-17 | Phase 1 | Pending |
| OBS-18 | Phase 1 | Pending |
| OBS-19 | Phase 1 | Pending |
| OBS-20 | Phase 1 | Pending |
| OBS-21 | Phase 1 | Pending |
| OBS-22 | Phase 1 | Pending |
| OBS-23 | Phase 1 | Pending |
| OBS-24 | Phase 1 | Pending |
| OBS-25 | Phase 1 | Pending |
| OBS-26 | Phase 1 | Pending |
| OBS-27 | Phase 1 | Pending |
| OBS-28 | Phase 1 | Pending |
| OBS-29 | Phase 12 | Complete |
| OBS-30 | Phase 12 | Complete |
| SPM-01 | Phase 1 | Complete |
| SPM-02 | Phase 1 | Complete |
| SPM-03 | Phase 1 | Complete |
| SPM-04 | Phase 1 | Complete |
| SPM-05 | Phase 1 | Complete |
| SPM-06 | Phase 1 | Complete |
| CP-01 | Phase 2 | Pending |
| CP-02 | Phase 2 | Pending |
| CP-03 | Phase 2 | Pending |
| CP-04 | Phase 2 | Pending |
| CP-05 | Phase 2 | Pending |
| CP-06 | Phase 2 | Pending |
| CP-07 | Phase 2 | Pending |
| CP-08 | Phase 2 | Pending |
| IC-01 | Phase 2 | Pending |
| IC-02 | Phase 2 | Pending |
| IC-03 | Phase 2 | Pending |
| IC-04 | Phase 2 | Pending |
| IC-05 | Phase 2 | Pending |
| IC-06 | Phase 2 | Pending |
| CD-01 | Phase 2 | Pending |
| CD-02 | Phase 2 | Pending |
| CD-03 | Phase 2 | Pending |
| CD-04 | Phase 2 | Pending |
| CD-05 | Phase 2 | Pending |
| IR-01 | Phase 2 | Pending |
| IR-02 | Phase 2 | Pending |
| IR-03 | Phase 2 | Pending |
| IR-04 | Phase 2 | Pending |
| TCA-01 | Phase 3 | Pending |
| TCA-02 | Phase 3 | Pending |
| TCA-03 | Phase 3 | Pending |
| TCA-04 | Phase 3 | Pending |
| TCA-05 | Phase 3 | Pending |
| TCA-06 | Phase 3 | Pending |
| TCA-07 | Phase 3 | Pending |
| TCA-08 | Phase 3 | Pending |
| TCA-09 | Phase 3 | Pending |
| TCA-10 | Phase 3 | Pending |
| TCA-11 | Phase 3 | Pending |
| TCA-12 | Phase 3 | Pending |
| TCA-13 | Phase 3 | Pending |
| TCA-14 | Phase 3 | Pending |
| TCA-15 | Phase 3 | Pending |
| TCA-16 | Phase 3 | Pending |
| DEP-01 | Phase 3 | Pending |
| DEP-02 | Phase 3 | Pending |
| DEP-03 | Phase 3 | Pending |
| DEP-04 | Phase 3 | Pending |
| DEP-05 | Phase 3 | Pending |
| DEP-06 | Phase 3 | Pending |
| DEP-07 | Phase 3 | Pending |
| DEP-08 | Phase 3 | Pending |
| DEP-09 | Phase 3 | Pending |
| DEP-10 | Phase 3 | Pending |
| DEP-11 | Phase 3 | Pending |
| DEP-12 | Phase 3 | Pending |
| TCA-17 | Phase 4 | Pending |
| TCA-18 | Phase 4 | Pending |
| TCA-19 | Phase 4 | Pending |
| TCA-20 | Phase 4 | Pending |
| TCA-21 | Phase 4 | Pending |
| TCA-22 | Phase 4 | Pending |
| TCA-23 | Phase 4 | Pending |
| TCA-24 | Phase 4 | Pending |
| TCA-25 | Phase 4 | Pending |
| TCA-29 | Phase 4 | Pending |
| TCA-30 | Phase 4 | Pending |
| TCA-31 | Phase 4 | Pending |
| SHR-01 | Phase 4 | Pending |
| SHR-02 | Phase 4 | Pending |
| SHR-03 | Phase 4 | Pending |
| SHR-04 | Phase 4 | Pending |
| SHR-05 | Phase 4 | Pending |
| SHR-06 | Phase 4 | Pending |
| SHR-07 | Phase 4 | Pending |
| SHR-08 | Phase 4 | Pending |
| SHR-09 | Phase 4 | Pending |
| SHR-10 | Phase 4 | Pending |
| SHR-11 | Phase 4 | Pending |
| SHR-12 | Phase 4 | Pending |
| SHR-13 | Phase 4 | Pending |
| SHR-14 | Phase 4 | Pending |
| NAV-01 | Phase 5 | Pending |
| NAV-02 | Phase 5 | Pending |
| NAV-03 | Phase 5 | Pending |
| NAV-04 | Phase 5 | Pending |
| NAV-05 | Phase 5 | Complete |
| NAV-06 | Phase 5 | Pending |
| NAV-07 | Phase 5 | Complete |
| NAV-08 | Phase 5 | Complete |
| NAV-09 | Phase 5 | Pending |
| NAV-10 | Phase 5 | Pending |
| NAV-11 | Phase 5 | Pending |
| NAV-12 | Phase 5 | Pending |
| NAV-13 | Phase 5 | Pending |
| NAV-14 | Phase 5 | Pending |
| NAV-15 | Phase 5 | Pending |
| NAV-16 | Phase 5 | Pending |
| TCA-26 | Phase 5 | Pending |
| TCA-27 | Phase 5 | Pending |
| TCA-28 | Phase 5 | Pending |
| TCA-32 | Phase 5 | Pending |
| TCA-33 | Phase 5 | Pending |
| TCA-34 | Phase 5 | Pending |
| TCA-35 | Phase 5 | Pending |
| UI-01 | Phase 5 | Complete |
| UI-02 | Phase 5 | Complete |
| UI-03 | Phase 5 | Complete |
| UI-04 | Phase 5 | Complete |
| UI-05 | Phase 5 | Complete |
| UI-06 | Phase 5 | Complete |
| UI-07 | Phase 5 | Complete |
| UI-08 | Phase 5 | Complete |
| SQL-01 | Phase 6 | Pending |
| SQL-02 | Phase 6 | Pending |
| SQL-03 | Phase 6 | Pending |
| SQL-04 | Phase 6 | Pending |
| SQL-05 | Phase 6 | Pending |
| SQL-06 | Phase 6 | Pending |
| SQL-07 | Phase 6 | Pending |
| SQL-08 | Phase 6 | Pending |
| SQL-09 | Phase 6 | Pending |
| SQL-10 | Phase 6 | Pending |
| SQL-11 | Phase 6 | Pending |
| SQL-12 | Phase 6 | Pending |
| SQL-13 | Phase 6 | Pending |
| SQL-14 | Phase 6 | Pending |
| SQL-15 | Phase 6 | Pending |
| SD-01 | Phase 6 | Pending |
| SD-02 | Phase 6 | Pending |
| SD-03 | Phase 6 | Pending |
| SD-04 | Phase 6 | Pending |
| SD-05 | Phase 6 | Pending |
| SD-06 | Phase 6 | Pending |
| SD-07 | Phase 6 | Pending |
| SD-08 | Phase 6 | Pending |
| SD-09 | Phase 6 | Pending |
| SD-10 | Phase 6 | Pending |
| SD-11 | Phase 6 | Pending |
| SD-12 | Phase 6 | Pending |
| TEST-01 | Phase 7 | Pending |
| TEST-02 | Phase 7 | Pending |
| TEST-03 | Phase 7 | Pending |
| TEST-04 | Phase 7 | Pending |
| TEST-05 | Phase 7 | Pending |
| TEST-06 | Phase 7 | Pending |
| TEST-07 | Phase 7 | Pending |
| TEST-08 | Phase 7 | Pending |
| TEST-09 | Phase 7 | Pending |
| TEST-10 | Phase 11 | Complete |
| TEST-11 | Phase 11 | Complete |
| TEST-12 | Phase 11 | Complete |
| DOC-01 | Phase 7 | Complete |

**Coverage:**
- v1 requirements: 184 total
- Sections: OBS (30), TCA (35), DEP (12), SHR (14), NAV (16), CP (8), IC (6), SQL (15), SD (12), CD (5), IR (4), UI (8), TEST (12), SPM (6), DOC (1)
- Mapped to phases: 184
- Unmapped: 0
- **Verified (Android evidence):** 17/184 (UI-01..08, SPM-01..06, DOC-01, TEST-10, TEST-11)
- **Pending re-verification:** 167/184 (reset per v1.0-MILESTONE-AUDIT.md revised audit)

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-02-24 -- TEST-10/TEST-11 verified complete via Android emulator evidence (253 tests passing); 17/184 verified total*
