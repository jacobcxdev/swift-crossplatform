# Requirements: Swift Cross-Platform

**Defined:** 2026-02-21
**Core Value:** Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases. Every requirement tests ONE API or pattern on Android.

### OBS: Observation & Reactivity

Bridge-level observation semantics and Swift Observation correctness on Android.

- [x] **OBS-01**: View body evaluation on Android is wrapped with `withObservationTracking`, firing `onChange` exactly once per observation cycle (not once per mutation)
- [x] **OBS-02**: `willSet` calls are suppressed during observation recording -- no per-mutation `MutableStateBacking` counter increments while `isEnabled` is true
- [x] **OBS-03**: A single `MutableStateBacking.update(0)` JNI call triggers exactly one Compose recomposition per observation cycle
- [x] **OBS-04**: Bridge initialization failure is detected and logged -- if `ViewObservation.nativeEnable()` fails, a visible error is produced instead of silent fallback to broken counter path
- [x] **OBS-05**: Nested view hierarchies observe correctly -- parent and child views each maintain their own frame on the `ObservationRecording` stack
- [x] **OBS-06**: ViewModifier bodies participate in observation tracking (not just View bodies)
- [x] **OBS-07**: `ObservationRegistrar` initializes correctly on Android, bridging to `SkipAndroidBridge.Observation.ObservationRegistrar`
- [x] **OBS-08**: `ObservationRegistrar.access(keyPath:)` records property access during observation on Android
- [x] **OBS-09**: `ObservationRegistrar.willSet(keyPath:)` fires correctly on Android; suppressed when `ObservationRecording.isEnabled` is true
- [x] **OBS-10**: `ObservationRegistrar.withMutation(of:keyPath:_:)` wraps mutations with willSet/didSet on Android
- [x] **OBS-11**: `withObservationTracking(_:onChange:)` invokes native `Observation.withObservationTracking` via `ObservationModule` on Android
- [x] **OBS-12**: `@Observable` macro synthesizes correct observation hooks on Android
- [x] **OBS-13**: `@Observable` class property reads in view bodies trigger observation tracking on Android
- [x] **OBS-14**: `@Observable` class property mutations trigger exactly one view update on Android
- [x] **OBS-15**: Bulk mutations in `@Observable` classes coalesce into a single view update on Android
- [x] **OBS-16**: `async` methods in `@Observable` classes execute on the correct actor on Android without deadlock
- [x] **OBS-17**: `@ObservationIgnored` suppresses observation tracking for annotated properties on Android
- [x] **OBS-18**: Optional `@Observable` model held as parent state correctly drives `.sheet`/`.fullScreenCover` presentation on Android
- [x] **OBS-19**: `@Observable` classes implement `Equatable` via object identity (`===`) correctly on Android
- [x] **OBS-20**: Bindings (`$model.property`) in view bodies correctly sync two-way changes with `@Observable` model properties on Android
- [x] **OBS-21**: `ObservationRecording.startRecording()` and `stopAndObserve()` manage per-thread TLS frame stack on Android
- [x] **OBS-22**: `ObservationRecording.recordAccess()` batches multiple property accesses into one trigger per frame on Android
- [x] **OBS-23**: `BridgeObservationSupport.access()` JNI call maps to `MutableStateBacking.access(index)` on Android
- [x] **OBS-24**: `BridgeObservationSupport.triggerSingleUpdate()` fires exactly one Compose recomposition via `Java_update(0)` on Android
- [x] **OBS-25**: `Java_skip_ui_ViewObservation_nativeEnable()` JNI export resolves and sets `isEnabled=true` on Android
- [x] **OBS-26**: `Java_skip_ui_ViewObservation_nativeStartRecording()` JNI export resolves on Android
- [x] **OBS-27**: `Java_skip_ui_ViewObservation_nativeStopAndObserve()` JNI export resolves on Android
- [x] **OBS-28**: `swiftThreadingFatal()` symbol export resolves on Android (workaround for `libswiftObservation.so` loading)
- [x] **OBS-29**: `PerceptionRegistrar` facade delegates to `ObservationRegistrar` on Android (conditional compilation path)
- [x] **OBS-30**: `withPerceptionTracking(_:onChange:)` delegates to `withObservationTracking` on Android

### TCA: Composable Architecture Core

Store, reducers, effects, and composition patterns on Android.

- [x] **TCA-01**: `Store.init(initialState:reducer:)` initializes with correct initial state on Android
- [x] **TCA-02**: `Store.init(initialState:reducer:withDependencies:)` -- `prepareDependencies` closure overrides dependencies at construction on Android
- [x] **TCA-03**: `store.send(.action)` dispatches an action from a view and returns a `StoreTask` on Android
- [x] **TCA-04**: `store.scope(state:action:)` derives a child store from a parent store on Android
- [x] **TCA-05**: `Scope(state:action:)` reducer runs child reducer against parent state/action on Android
- [x] **TCA-06**: `.ifLet(_:action:destination:)` runs child reducer when optional state is non-nil on Android
- [x] **TCA-07**: `.forEach(_:action:destination:)` runs element reducer for each collection element on Android
- [x] **TCA-08**: `.ifCaseLet(_:action:)` runs child reducer when enum state matches a specific case on Android
- [x] **TCA-09**: `CombineReducers { }` builder syntax composes multiple reducers in sequence on Android
- [x] **TCA-10**: `Effect.none` returns immediately without side effects on Android
- [x] **TCA-11**: `Effect.run { send in }` executes async work and sends actions back into the store on Android
- [x] **TCA-12**: `Effect.merge(...)` runs multiple effects concurrently on Android
- [x] **TCA-13**: `Effect.concatenate(...)` runs effects sequentially in order on Android
- [x] **TCA-14**: `Effect.cancellable(id:cancelInFlight:)` marks an effect as cancellable on Android
- [x] **TCA-15**: `Effect.cancel(id:)` cancels in-flight effects by ID on Android
- [x] **TCA-16**: `Effect.send(_:)` synchronously dispatches an action as an effect on Android
- [x] **TCA-17**: `@ObservableState` macro synthesizes `_$id`, `_$observationRegistrar`, `_$willModify` on Android
- [x] **TCA-18**: `@ObservationStateIgnored` suppresses observation tracking for annotated state properties on Android
- [x] **TCA-19**: `BindableAction` protocol + `case binding(BindingAction<State>)` compiles and routes correctly on Android
- [x] **TCA-20**: `BindingReducer()` applies binding mutations to state on Android
- [x] **TCA-21**: `@Bindable var store` -- `$store.property` binding projection reads/writes state through the store on Android
- [x] **TCA-22**: `$store.property.sending(\.action)` derives a binding that sends a specific action on mutation on Android
- [x] **TCA-23**: `store.scope(state:action:)` in `ForEach` renders list of child stores on Android
- [x] **TCA-24**: Optional scoping `store.scope(state: \.child, action: \.child)` renders conditional content on Android
- [x] **TCA-25**: `switch store.case { }` enum store switching renders correctly on Android (`@Reducer enum` + `.case`)
- [x] **TCA-26**: `@Dependency(\.dismiss) var dismiss` -- `await dismiss()` causes presenting feature to pop/dismiss on Android
- [x] **TCA-27**: `@Presents` macro synthesizes property wrapper accessors for optional child state on Android
- [x] **TCA-28**: `PresentationAction.dismiss` -- parent reducer sets optional child state to `nil` on Android
- [x] **TCA-29**: `Reducer.onChange(of:_:)` runs nested reducer when a derived value changes on Android
- [x] **TCA-30**: `Reducer._printChanges()` logs state diffs to console on Android
- [x] **TCA-31**: `@ViewAction(for:)` macro synthesizes `send(_:)` for view actions on Android
- [x] **TCA-32**: `StackState<Element>` initializes, appends, and indexes by `StackElementID` on Android
- [x] **TCA-33**: `StackAction` (`.push`, `.popFrom`, `.element`) routes through `forEach` on Android
- [x] **TCA-34**: `@ReducerCaseEphemeral` marks enum reducer case as ephemeral (alert/dialog) on Android
- [x] **TCA-35**: `@ReducerCaseIgnored` skips body synthesis for an enum reducer case on Android

### DEP: Dependencies

Dependency injection and resolution on Android.

- [x] **DEP-01**: `@Dependency(\.keyPath)` resolves a dependency from `DependencyValues` inside a reducer on Android
- [x] **DEP-02**: `@Dependency(Type.self)` resolves a dependency by type conformance on Android
- [x] **DEP-03**: `DependencyKey` protocol -- `liveValue` is used in production context on Android
- [x] **DEP-04**: `DependencyKey.testValue` is used in test context on Android
- [x] **DEP-06**: `DependencyValues` extension with computed property registers a custom dependency on Android
- [x] **DEP-07**: `@DependencyClient` macro generates a client struct with `unimplemented` defaults on Android
- [x] **DEP-08**: `Reducer.dependency(_:_:)` modifier overrides a dependency for a scoped reducer on Android
- [x] **DEP-09**: `withDependencies { } operation: { }` scopes dependency overrides to a closure on Android
- [x] **DEP-10**: `prepareDependencies` closure overrides dependencies before any `@Dependency` access on Android
- [x] **DEP-11**: Child reducer scopes inherit parent dependency context on Android
- [x] **DEP-12**: `@Dependency` in effect closures resolves the correct (potentially overridden) value on Android

### SHR: Shared State

`@Shared` state persistence and cross-feature sharing on Android.

- [x] **SHR-01**: `@Shared(.appStorage("key"))` persists and restores state via UserDefaults on Android
- [x] **SHR-02**: `@Shared(.fileStorage(url))` persists and restores `Codable` state via file system on Android
- [x] **SHR-03**: `@Shared(.inMemory("key"))` shares state in-memory across features within a session on Android
- [x] **SHR-04**: `@Shared` with `SharedKey` extension provides type-safe default values on Android
- [x] **SHR-05**: `$shared` binding projection creates two-way SwiftUI binding on Android
- [x] **SHR-06**: `$shared` binding mutations trigger view recomposition on Android
- [x] **SHR-07**: `$parent.child` keypath projection derives a child `Shared` from parent on Android
- [x] **SHR-08**: `Shared($optional)` unwrapping returns `Shared<T>` when non-nil on Android
- [x] **SHR-09**: `Observations { }` async sequence emits on every `@Shared` mutation on Android
- [x] **SHR-10**: `$shared.publisher` exposes Combine/OpenCombine publisher on Android
- [x] **SHR-11**: `@ObservationIgnored @Shared` prevents double-notification in `@Observable` models on Android
- [x] **SHR-12**: Multiple `@Shared` declarations with same backing store synchronize updates on Android
- [x] **SHR-13**: Child component mutation of `@Shared` parent state is visible in parent on Android
- [x] **SHR-14**: Custom `SharedKey` strategy can be implemented for user-defined persistence backends on Android

### NAV: Navigation

Navigation patterns and presentation lifecycle on Android.

- [x] **NAV-01**: `NavigationStack` with `$store.scope(state: \.path, action: \.path)` renders on Android
- [x] **NAV-02**: Path append pushes a new destination onto the navigation stack on Android
- [x] **NAV-03**: Path removeLast pops the top destination from the navigation stack on Android
- [x] **NAV-04**: `navigationDestination(item:)` with binding pushes destination on Android
- [x] **NAV-05**: `.sheet(item: $store.scope(...))` presents modal content on Android
- [x] **NAV-06**: `.sheet` `onDismiss` closure fires when sheet is dismissed on Android
- [x] **NAV-07**: `.popover(item: $store.scope(...))` displays popover on Android
- [x] **NAV-08**: `.fullScreenCover(item: $store.scope(...))` presents full-screen content on Android
- [x] **NAV-09**: `.alert` with `AlertState` renders alert with title, message, and buttons on Android
- [x] **NAV-10**: Alert buttons with roles (`.destructive`, `.cancel`) render correctly on Android
- [x] **NAV-11**: `.confirmationDialog` with `ConfirmationDialogState` renders action sheet on Android
- [x] **NAV-12**: `AlertState.map(_:)` transforms action type on Android
- [x] **NAV-13**: `ConfirmationDialogState.map(_:)` transforms action type on Android
- [x] **NAV-14**: Dismissing a presented feature via binding (setting optional to `nil`) closes presentation on Android
- [x] **NAV-15**: `Binding` subscript with `CaseKeyPath` extracts enum associated value on Android

### CP: CasePaths

Enum routing and pattern matching on Android.

- [x] **CP-01**: `@CasePathable` macro generates `AllCasePaths` and `CaseKeyPath` accessors on Android
- [x] **CP-02**: `.is(\.caseName)` returns correct `Bool` for case checking on Android
- [x] **CP-03**: `.modify(\.caseName) { }` mutates associated value in-place on Android
- [x] **CP-04**: `@dynamicMemberLookup` dot-syntax returns `Optional<AssociatedValue>` on Android
- [x] **CP-05**: `allCasePaths` static variable returns collection of all case key paths on Android
- [x] **CP-06**: `root[case: caseKeyPath]` subscript extracts/embeds associated value on Android
- [x] **CP-07**: `@Reducer enum` pattern -- enum reducers synthesize `body` and `scope` on Android
- [x] **CP-08**: `AnyCasePath` with custom embed/extract closures works on Android

### IC: Identified Collections

`IdentifiedArrayOf` correctness on Android.

- [x] **IC-01**: `IdentifiedArrayOf<T>` initializes from array literal on Android
- [x] **IC-02**: `array[id: id]` subscript read returns correct element in O(1) on Android
- [x] **IC-03**: `array[id: id] = nil` subscript write removes element on Android
- [x] **IC-04**: `array.remove(id:)` returns removed element on Android
- [x] **IC-05**: `array.ids` property returns ordered set of all IDs on Android
- [x] **IC-06**: `IdentifiedArrayOf` conforms to `Codable` when element is `Codable` on Android

### SQL: Structured Queries

Type-safe query building via StructuredQueries on Android.

- [x] **SQL-01**: `@Table` macro generates correct table metadata on Android
- [x] **SQL-02**: `@Column(primaryKey:)` custom primary key designation works on Android
- [x] **SQL-03**: `@Column(as:)` custom column representations work on Android
- [x] **SQL-04**: `@Selection` type composition for multi-column grouping works on Android
- [x] **SQL-05**: `Table.select { }` tuple/closure column selection works on Android
- [x] **SQL-06**: `Table.where { }` equality, comparison, and boolean predicates work on Android
- [x] **SQL-07**: `Table.find(id)` primary key lookup works on Android
- [x] **SQL-08**: `Table.where { $0.column.in(values) }` IN/NOT IN operators work on Android
- [x] **SQL-09**: `Table.join()` / `leftJoin()` / `rightJoin()` / `fullJoin()` work on Android
- [x] **SQL-10**: `Table.order { }` ascending/descending/collation ordering works on Android
- [x] **SQL-11**: `Table.group { }` with `count()`/`avg()`/`sum()`/`min()`/`max()` aggregations work on Android
- [x] **SQL-12**: `Table.limit(n, offset:)` pagination works on Android
- [x] **SQL-13**: `Table.insert { }` / `Table.upsert { }` with draft and conflict resolution work on Android
- [x] **SQL-14**: `Table.where(...).update { }` / `Table.find(id).delete()` mutation/deletion work on Android
- [x] **SQL-15**: `#sql()` safe SQL macro with column interpolation works on Android

### SD: SQLiteData & GRDB

Database lifecycle, query execution, and observation on Android.

- [x] **SD-01**: `SQLiteData.defaultDatabase()` initializes database connection on Android
- [x] **SD-02**: `DatabaseMigrator` executes registered migrations on Android
- [x] **SD-03**: `database.read { db in }` executes synchronous read-only transaction on Android
- [x] **SD-04**: `database.write { db in }` executes synchronous write transaction on Android
- [x] **SD-05**: `await database.read { }` / `await database.write { }` async transactions work on Android
- [x] **SD-06**: `Table.fetchAll(db)` returns array of matching rows on Android
- [x] **SD-07**: `Table.fetchOne(db)` returns optional single row on Android
- [x] **SD-08**: `Table.fetchCount(db)` returns integer count on Android
- [x] **SD-09**: `@FetchAll` observation macro triggers view updates when database changes on Android
- [x] **SD-10**: `@FetchOne` observation macro triggers view updates for single-row queries on Android
- [x] **SD-11**: `@Fetch` with `FetchKeyRequest` executes composite multi-query observations on Android
- [x] **SD-12**: `@Dependency(\.defaultDatabase)` injects database into views and models on Android

### CD: Custom Dump

Value dumping, diffing, and assertion utilities on Android.

- [x] **CD-01**: `customDump(_:)` outputs structured value representation on Android
- [x] **CD-02**: `String(customDumping:)` creates string from value dump on Android
- [x] **CD-03**: `diff(_:_:)` computes string diff between two values on Android
- [x] **CD-04**: `expectNoDifference(_:_:)` asserts equality with diff output on failure on Android
- [x] **CD-05**: `expectDifference(_:_:operation:changes:)` asserts value changes after operation on Android

### IR: Issue Reporting

Error reporting and handling on Android.

- [x] **IR-01**: `reportIssue(_:)` reports a string message as a runtime issue on Android
- [x] **IR-02**: `reportIssue(_:)` reports a thrown `Error` instance on Android
- [x] **IR-03**: `withErrorReporting { }` synchronous wrapper catches and reports thrown errors on Android
- [x] **IR-04**: `await withErrorReporting { }` async wrapper catches and reports thrown errors on Android

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

- [x] **TEST-01**: `TestStore(initialState:reducer:)` initializes correctly on Android
- [x] **TEST-02**: `await store.send(.action)` with trailing state assertion passes on Android
- [x] **TEST-03**: `await store.receive(.action)` asserts effect-dispatched actions on Android
- [x] **TEST-04**: `store.exhaustivity = .on` (default) fails test on unasserted state changes on Android
- [x] **TEST-05**: `store.exhaustivity = .off` skips unasserted changes without failure on Android
- [x] **TEST-06**: `await store.finish()` waits for all in-flight effects before test ends on Android
- [x] **TEST-07**: `await store.skipReceivedActions()` discards unconsumed received actions on Android
- [x] **TEST-08**: Deterministic async effect execution (alternative to `useMainSerialExecutor`) works on Android
- [x] **TEST-09**: `.dependencies { }` test trait overrides dependencies for a test on Android
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

### VIEWID: View Identity

Compose view identity system ensuring stable composition keys, correct peer remembering, and consistent container identity on Android.

- [x] **VIEWID-01**: ForEach non-lazy Evaluate wraps items in `key(identifier)` for all three iteration paths (indexRange, objects, objectsBinding) on Android
- [x] **VIEWID-02**: @Stable/skippability investigation documented with DEFERRED recommendation and rationale
- [x] **VIEWID-03**: IdentityFeature reducer scaffolding with 8-section acceptance surface in fuse-app Identity tab on Android
- [x] **VIEWID-04**: ForEach produces dual wrapping (IdentityKeyModifier for structural identity + TagModifier(.tag) for selection) in non-lazy paths on Android
- [x] **VIEWID-05**: AnimatedContent contentKey normalized through normalizeKey() — SwiftHashable JNI equality problem bypassed on Android
- [x] **VIEWID-06**: All eager container loops (VStack, HStack, ZStack) use key(identityKey ?? i) with seenKeys duplicate-key guard on Android
- [x] **VIEWID-07**: TagModifier .tag role is pure data annotation (no key() in Render); .id role uses normalizeKey() on Android
- [x] **VIEWID-08**: Picker (5 sites) and TabView (1 site) read selectionTag for selection matching on Android
- [x] **VIEWID-09**: AnimatedContent render loops use key(identityKey ?? i) with seenKeys guard inside AnimatedContent content lambda on Android
- [x] **VIEWID-10**: Transpiler stateVariables.isEmpty guard restructured — mixed @State + let-with-default views get peer remembering codegen on Android
- [x] **VIEWID-11**: Lazy containers (LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, List, Table) use composeBundleNormalizedKey() adapter wrapping normalizeKey() on Android
- [x] **VIEWID-12**: PeerStore parent-scoped peer cache survives LazyColumn composition disposal (scroll-off) for LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, List, and Table on Android
- [x] **VIEWID-13**: PeerStore survives TabView tab switch (NavHost popUpTo with saveState) — peers retained across tab composition disposal on Android
- [x] **VIEWID-14**: RetainedAnimatedItems provides per-item AnimatedVisibility with axis-aware default transitions replacing broken AnimatedContent dual-path on Android

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

Which phases cover which requirements. Updated during roadmap creation. Evidence column added Phase 14 (Android Verification).

| Requirement | Phase | Status | Evidence |
|-------------|-------|--------|----------|
| OBS-01 | Phase 1 | Complete | DIRECT: "Single property mutation triggers exactly one onChange" passes on Android |
| OBS-02 | Phase 1 | Complete | DIRECT: "Bulk mutations on multiple properties coalesce into single onChange" passes on Android |
| OBS-03 | Phase 1 | Complete | DIRECT: "D8-a: Rapid mutations produce single onChange per tracking scope" passes on Android |
| OBS-04 | Phase 1 | Complete | INDIRECT: All 251 observation-dependent tests pass on Android; bridge init succeeds |
| OBS-05 | Phase 1 | Complete | DIRECT: "Nested observation scopes are independent", "D8-b: Parent/child observation scopes fire independently" pass on Android |
| OBS-06 | Phase 1 | Complete | INDIRECT: testSheetPresentation(), testFullScreenCoverPresentation() exercise ViewModifier observation on Android |
| OBS-07 | Phase 1 | Complete | DIRECT: "ObservableState registrar round-trip through Store" passes on Android |
| OBS-08 | Phase 1 | Complete | DIRECT: "Single property mutation triggers exactly one onChange" proves access() recording on Android |
| OBS-09 | Phase 1 | Complete | DIRECT: "Bulk mutations on multiple properties coalesce into single onChange" proves willSet on Android |
| OBS-10 | Phase 1 | Complete | INDIRECT: All mutation tests (bindingReducerAppliesMutations, onChange, etc.) prove withMutation on Android |
| OBS-11 | Phase 1 | Complete | DIRECT: "Single property mutation triggers exactly one onChange" uses withObservationTracking on Android |
| OBS-12 | Phase 1 | Complete | DIRECT: observableStateIdentity(), testNestedObservableGraphMutation() pass on Android |
| OBS-13 | Phase 1 | Complete | DIRECT: "Single property mutation triggers exactly one onChange" proves property read tracking on Android |
| OBS-14 | Phase 1 | Complete | DIRECT: "Single property mutation triggers exactly one onChange" proves single update on Android |
| OBS-15 | Phase 1 | Complete | DIRECT: "Bulk mutations on multiple properties coalesce into single onChange" passes on Android |
| OBS-16 | Phase 1 | Complete | DIRECT: effectRunFromBackgroundThread() passes on Android |
| OBS-17 | Phase 1 | Complete | DIRECT: "@ObservationIgnored suppresses tracking" passes on Android |
| OBS-18 | Phase 1 | Complete | DIRECT: testSheetPresentation(), testFullScreenCoverPresentation() pass on Android |
| OBS-19 | Phase 1 | Complete | INDIRECT: observableStateIdentity() proves identity semantics on Android |
| OBS-20 | Phase 1 | Complete | DIRECT: testBindingProjectionChain(), testDynamicMemberLookupBinding() pass on Android |
| OBS-21 | Phase 1 | Complete | INDIRECT: "Concurrent observation scopes on multiple threads fire independently" proves TLS frame stack on Android |
| OBS-22 | Phase 1 | Complete | DIRECT: "D8-a: Rapid mutations produce single onChange per tracking scope" proves batching on Android |
| OBS-23 | Phase 1 | Complete | INDIRECT: All observation tests pass; BridgeObservationSupport.access() proven by observation chain on Android |
| OBS-24 | Phase 1 | Complete | INDIRECT: "Single property mutation triggers exactly one onChange" proves triggerSingleUpdate on Android |
| OBS-25 | Phase 1 | Complete | INDIRECT: All observation tests pass; nativeEnable JNI export resolves on Android |
| OBS-26 | Phase 1 | Complete | INDIRECT: All observation tests pass; nativeStartRecording JNI export resolves on Android |
| OBS-27 | Phase 1 | Complete | INDIRECT: All observation tests pass; nativeStopAndObserve JNI export resolves on Android |
| OBS-28 | Phase 1 | Complete | INDIRECT: All observation tests pass; swiftThreadingFatal resolves, libswiftObservation.so loads on Android |
| OBS-29 | Phase 12 | Complete | DIRECT: Phase 12 verification tests |
| OBS-30 | Phase 12 | Complete | DIRECT: Phase 12 verification tests |
| SPM-01 | Phase 1 | Complete | DIRECT: skip android build succeeds |
| SPM-02 | Phase 1 | Complete | DIRECT: skip android build succeeds |
| SPM-03 | Phase 1 | Complete | DIRECT: skip android build succeeds |
| SPM-04 | Phase 1 | Complete | DIRECT: skip android build succeeds |
| SPM-05 | Phase 1 | Complete | DIRECT: skip android build succeeds |
| SPM-06 | Phase 1 | Complete | DIRECT: skip android build succeeds |
| CP-01 | Phase 2 | Complete | DIRECT: casePathableGeneratesAccessors() passes on Android |
| CP-02 | Phase 2 | Complete | DIRECT: isCheck() passes on Android |
| CP-03 | Phase 2 | Complete | DIRECT: modifyInPlace() passes on Android |
| CP-04 | Phase 2 | Complete | DIRECT: nestedCasePathable() passes on Android |
| CP-05 | Phase 2 | Complete | DIRECT: allCasePathsCollection() passes on Android |
| CP-06 | Phase 2 | Complete | DIRECT: caseSubscriptAndEmbed() passes on Android |
| CP-07 | Phase 2 | Complete | DIRECT: caseReducerStateConformance() passes on Android |
| CP-08 | Phase 2 | Complete | DIRECT: anyCasePathCustomClosures() passes on Android |
| IC-01 | Phase 2 | Complete | DIRECT: initFromArrayLiteral() passes on Android |
| IC-02 | Phase 2 | Complete | DIRECT: subscriptReadByID() passes on Android |
| IC-03 | Phase 2 | Complete | DIRECT: subscriptWriteNilRemoves() passes on Android |
| IC-04 | Phase 2 | Complete | DIRECT: removeByID() passes on Android |
| IC-05 | Phase 2 | Complete | DIRECT: idsProperty() passes on Android |
| IC-06 | Phase 2 | Complete | DIRECT: codableConformance() passes on Android |
| CD-01 | Phase 2 | Complete | DIRECT: customDumpStructOutput(), customDumpNestedStruct() pass on Android |
| CD-02 | Phase 2 | Complete | DIRECT: stringCustomDumping() passes on Android |
| CD-03 | Phase 2 | Complete | DIRECT: diffDetectsChanges(), diffReturnsNilForEqualValues(), diffEnumChanges() pass on Android |
| CD-04 | Phase 2 | Complete | DIRECT: expectNoDifferencePassesForEqualValues(), expectNoDifferenceFailsForDifferentValues() pass on Android |
| CD-05 | Phase 2 | Complete | DIRECT: expectDifferenceDetectsChanges() passes on Android |
| IR-01 | Phase 2 | Complete | DIRECT: reportIssueStringMessage() passes on Android |
| IR-02 | Phase 2 | Complete | DIRECT: reportIssueErrorInstance() passes on Android |
| IR-03 | Phase 2 | Complete | DIRECT: withErrorReportingSyncCatchesErrors() passes on Android |
| IR-04 | Phase 2 | Complete | DIRECT: withErrorReportingAsyncCatchesErrors() passes on Android |
| TCA-01 | Phase 3 | Complete | DIRECT: storeInitialState(), testStoreInit() pass on Android |
| TCA-02 | Phase 3 | Complete | DIRECT: storeInitWithDependencies() passes on Android |
| TCA-03 | Phase 3 | Complete | DIRECT: storeSendReturnsStoreTask() passes on Android |
| TCA-04 | Phase 3 | Complete | DIRECT: storeScopeDerivesChildStore(), childStoreScoping() pass on Android |
| TCA-05 | Phase 3 | Complete | DIRECT: scopeReducer() passes on Android |
| TCA-06 | Phase 3 | Complete | DIRECT: ifLetReducer() passes on Android |
| TCA-07 | Phase 3 | Complete | DIRECT: forEachReducer(), forEachScoping() pass on Android |
| TCA-08 | Phase 3 | Complete | DIRECT: ifCaseLetReducer() passes on Android |
| TCA-09 | Phase 3 | Complete | DIRECT: combineReducers() passes on Android |
| TCA-10 | Phase 3 | Complete | DIRECT: effectNone() passes on Android |
| TCA-11 | Phase 3 | Complete | DIRECT: effectRunFromBackgroundThread(), effectRunWithDependencies() pass on Android |
| TCA-12 | Phase 3 | Complete | DIRECT: effectMerge() passes on Android |
| TCA-13 | Phase 3 | Complete | DIRECT: effectConcatenate() passes on Android |
| TCA-14 | Phase 3 | Complete | DIRECT: effectCancellable() passes on Android |
| TCA-15 | Phase 3 | Complete | DIRECT: effectCancel(), effectCancelInFlight(), cancelInFlightRapidResend() pass on Android |
| TCA-16 | Phase 3 | Complete | DIRECT: effectSend() passes on Android |
| DEP-01 | Phase 3 | Complete | DIRECT: dependencyKeyPathResolution() passes on Android |
| DEP-02 | Phase 3 | Complete | DIRECT: dependencyTypeResolution() passes on Android |
| DEP-03 | Phase 3 | Complete | DIRECT: liveValueInProductionContext() passes on Android |
| DEP-04 | Phase 3 | Complete | DIRECT: testValueInTestContext() passes on Android |
| DEP-06 | Phase 3 | Complete | DIRECT: customDependencyKeyRegistration() passes on Android |
| DEP-07 | Phase 3 | Complete | DIRECT: dependencyClientUnimplementedReportsIssue() passes on Android |
| DEP-08 | Phase 3 | Complete | DIRECT: reducerDependencyModifier() passes on Android |
| DEP-09 | Phase 3 | Complete | DIRECT: withDependenciesSyncScoping() passes on Android |
| DEP-10 | Phase 3 | Complete | DIRECT: prepareDependencies() passes on Android |
| DEP-11 | Phase 3 | Complete | DIRECT: childReducerInheritsDependencies(), grandchildReducerInheritsDependencies() pass on Android |
| DEP-12 | Phase 3 | Complete | DIRECT: dependencyResolvesInEffectClosure(), dependencyResolvesInMergedEffects() pass on Android |
| TCA-17 | Phase 4 | Complete | DIRECT: observableStateIdentity() passes on Android |
| TCA-18 | Phase 4 | Complete | DIRECT: observationStateIgnored() passes on Android |
| TCA-19 | Phase 4 | Complete | DIRECT: bindableActionCompiles() passes on Android |
| TCA-20 | Phase 4 | Complete | DIRECT: bindingReducerAppliesMutations(), bindingReducerNoopForNonBindingAction() pass on Android |
| TCA-21 | Phase 4 | Complete | DIRECT: storeBindingProjection(), bindingProjectionMultipleMutations() pass on Android |
| TCA-22 | Phase 4 | Complete | DIRECT: sendingBinding(), sendingCancellation() pass on Android |
| TCA-23 | Phase 4 | Complete | DIRECT: forEachIdentityStability(), forEachScoping() pass on Android |
| TCA-24 | Phase 4 | Complete | DIRECT: optionalScoping() passes on Android |
| TCA-25 | Phase 4 | Complete | DIRECT: Phase 13 verification tests |
| TCA-29 | Phase 4 | Complete | DIRECT: onChange() passes on Android |
| TCA-30 | Phase 4 | Complete | DIRECT: printChanges() passes on Android |
| TCA-31 | Phase 4 | Complete | DIRECT: Phase 13 verification tests |
| SHR-01 | Phase 4 | Complete | DIRECT: appStorageString(), appStorageInt(), appStorageBool(), appStorageDouble() and 7 more pass on Android |
| SHR-02 | Phase 4 | Complete | DIRECT: fileStorageRoundTrip() passes on Android |
| SHR-03 | Phase 4 | Complete | DIRECT: inMemorySharing(), inMemoryCrossFeature() pass on Android |
| SHR-04 | Phase 4 | Complete | DIRECT: sharedKeyDefaultValue(), customSharedKeyCompiles() pass on Android |
| SHR-05 | Phase 4 | Complete | DIRECT: sharedBindingProjection() passes on Android |
| SHR-06 | Phase 4 | Complete | DIRECT: sharedBindingMutationTriggersChange() passes on Android |
| SHR-07 | Phase 4 | Complete | DIRECT: sharedKeypathProjection() passes on Android |
| SHR-08 | Phase 4 | Complete | DIRECT: sharedOptionalUnwrapping() passes on Android |
| SHR-09 | Phase 4 | Complete | DIRECT: testPublisherValuesAsyncSequence(), testPublisherAndObservationBothWork() pass on Android via OpenCombine |
| SHR-10 | Phase 4 | Complete | DIRECT: testSharedPublisher(), testSharedPublisherMultipleValues() pass on Android via OpenCombine |
| SHR-11 | Phase 4 | Complete | DIRECT: doubleNotificationPrevention() passes on Android |
| SHR-12 | Phase 4 | Complete | DIRECT: multipleSharedSameKeySynchronize() passes on Android |
| SHR-13 | Phase 4 | Complete | DIRECT: childMutationVisibleInParent(), parentMutationVisibleInChild() pass on Android |
| SHR-14 | Phase 4 | Complete | DIRECT: customSharedKeyCompiles() passes on Android |
| NAV-01 | Phase 5 | Complete | DIRECT: testNavigationStackPush(), testPathViewBindingPush() pass on Android |
| NAV-02 | Phase 5, 15 | Complete | DIRECT: testNavigationStackPush(), pushContactDetail() pass on Android (Phase 15: strengthening to binding-driven push) |
| NAV-03 | Phase 5 | Complete | DIRECT: testNavigationStackPop(), testNavigationStackPopAll(), testStackStateRemoveLast() pass on Android |
| NAV-04 | Phase 5 | Complete | DIRECT: testNavigationDestinationItemBinding() passes on Android |
| NAV-05 | Phase 5 | Complete | DIRECT: Phase 13 presentation parity tests |
| NAV-06 | Phase 5 | Complete | DIRECT: testSheetOnDismissCleanup() passes on Android |
| NAV-07 | Phase 5 | Complete | DIRECT: Phase 13 presentation parity tests |
| NAV-08 | Phase 5 | Complete | DIRECT: Phase 13 presentation parity tests |
| NAV-09 | Phase 5 | Complete | DIRECT: testAlertStateCreation(), testAlertAutoDismissal(), deleteWithAlertConfirmation() pass on Android |
| NAV-10 | Phase 5 | Complete | DIRECT: "ButtonState with destructive role", "ButtonState with cancel role" pass on Android |
| NAV-11 | Phase 5 | Complete | DIRECT: testDialogAutoDismissal(), deleteButtonPresentsConfirmationDialog(), sortConfirmationDialog() pass on Android |
| NAV-12 | Phase 5 | Complete | DIRECT: testAlertStateMap() passes on Android |
| NAV-13 | Phase 5 | Complete | DIRECT: testConfirmationDialogStateMap() passes on Android |
| NAV-14 | Phase 5 | Complete | DIRECT: testDismissViaBindingNil() passes on Android |
| NAV-15 | Phase 5 | Complete | DIRECT: testCaseKeyPathExtraction(), testCaseKeyPathSetterSubscript() pass on Android |
| TCA-26 | Phase 5 | Complete | DIRECT: testDismissDependencyResolvesAndExecutes(), testDismissDependencyWithPresentation(), testDismissViaChildDependency() pass on Android |
| TCA-27 | Phase 5 | Complete | DIRECT: testPresentsOptionalLifecycle() passes on Android |
| TCA-28 | Phase 5 | Complete | DIRECT: testPresentationActionDismissNilsState() passes on Android |
| TCA-32 | Phase 5, 15 | Complete | DIRECT: testStackStateInitAndAppend(), testStackStateRemoveLast() pass on Android (Phase 15: strengthening to binding-driven push) |
| TCA-33 | Phase 5 | Complete | DIRECT: testStackActionForEachRouting() passes on Android |
| TCA-34 | Phase 5 | Complete | DIRECT: testReducerCaseEphemeral() passes on Android |
| TCA-35 | Phase 5 | Complete | DIRECT: testReducerCaseIgnored() passes on Android |
| UI-01 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| UI-02 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| UI-03 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| UI-04 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| UI-05 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| UI-06 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| UI-07 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| UI-08 | Phase 5 | Complete | DIRECT: SwiftUI pattern tests pass on Android emulator |
| SQL-01 | Phase 6 | Complete | DIRECT: tableMacro() passes on Android |
| SQL-02 | Phase 6 | Complete | DIRECT: columnPrimaryKey() passes on Android |
| SQL-03 | Phase 6 | Complete | DIRECT: columnCustomRepresentation() passes on Android |
| SQL-04 | Phase 6 | Complete | DIRECT: selectionTypeComposition() passes on Android |
| SQL-05 | Phase 6 | Complete | DIRECT: selectColumns() passes on Android |
| SQL-06 | Phase 6 | Complete | DIRECT: wherePredicates() passes on Android |
| SQL-07 | Phase 6 | Complete | DIRECT: findById() passes on Android |
| SQL-08 | Phase 6 | Complete | DIRECT: whereInOperator() passes on Android |
| SQL-09 | Phase 6 | Complete | DIRECT: joinOperations() passes on Android |
| SQL-10 | Phase 6 | Complete | DIRECT: orderBy() passes on Android |
| SQL-11 | Phase 6 | Complete | DIRECT: groupByAggregation() passes on Android |
| SQL-12 | Phase 6 | Complete | DIRECT: limitOffset() passes on Android |
| SQL-13 | Phase 6 | Complete | DIRECT: insertAndUpsert() passes on Android |
| SQL-14 | Phase 6 | Complete | DIRECT: updateAndDelete() passes on Android |
| SQL-15 | Phase 6 | Complete | DIRECT: sqlMacro() passes on Android |
| SD-01 | Phase 6 | Complete | DIRECT: databaseInit() passes on Android |
| SD-02 | Phase 6 | Complete | DIRECT: databaseMigrator() passes on Android |
| SD-03 | Phase 6 | Complete | DIRECT: syncRead() passes on Android |
| SD-04 | Phase 6 | Complete | DIRECT: syncWrite() passes on Android |
| SD-05 | Phase 6 | Complete | DIRECT: asyncRead(), asyncWrite() pass on Android |
| SD-06 | Phase 6 | Complete | DIRECT: fetchAll() passes on Android |
| SD-07 | Phase 6 | Complete | DIRECT: fetchOne() passes on Android |
| SD-08 | Phase 6 | Complete | DIRECT: fetchCount() passes on Android |
| SD-09 | Phase 6 | Complete | DIRECT: fetchAllObservation() passes on Android via ValueObservation |
| SD-10 | Phase 6 | Complete | DIRECT: fetchOneObservation() passes on Android via ValueObservation |
| SD-11 | Phase 6 | Complete | DIRECT: fetchCompositeObservation() passes on Android via ValueObservation |
| SD-12 | Phase 6 | Complete | DIRECT: defaultDatabaseDependency() passes on Android |
| TEST-01 | Phase 7 | Complete | DIRECT: testStoreInit(), storeInitialState() pass on Android |
| TEST-02 | Phase 7 | Complete | DIRECT: sendWithStateAssertion() passes on Android |
| TEST-03 | Phase 7 | Complete | DIRECT: receiveEffectAction() passes on Android |
| TEST-04 | Phase 7 | Complete | DIRECT: exhaustivityOnDetectsUnassertedChange() passes on Android |
| TEST-05 | Phase 7 | Complete | DIRECT: exhaustivityOff(), nonExhaustiveReceiveOff() pass on Android |
| TEST-06 | Phase 7 | Complete | DIRECT: finish(), finishWithSlowEffect() pass on Android |
| TEST-07 | Phase 7 | Complete | DIRECT: skipReceivedActions() passes on Android |
| TEST-08 | Phase 7 | Complete | INDIRECT: All async effect tests pass on Android; deterministic execution works via task scheduling |
| TEST-09 | Phase 7 | Complete | DIRECT: builtInDependencyResolution() passes on Android |
| TEST-10 | Phase 11, 17 | Complete | INDIRECT: Android emulator validation (Phase 11); Phase 17: upgrading to direct un-gated Android test |
| TEST-11 | Phase 11, 17 | Complete | INDIRECT: Android emulator validation (Phase 11); Phase 17: upgrading to direct un-gated Android test |
| TEST-12 | Phase 11 | Complete | DIRECT: Android emulator validation (Phase 11) |
| DOC-01 | Phase 7 | Complete | N/A: Documentation requirement |
| VIEWID-01 | Phase 18 | Complete | DIRECT: ForEach non-lazy Evaluate wraps items in `key(identifier)` for all three iteration paths (indexRange, objects, objectsBinding) |
| VIEWID-02 | Phase 18 | Complete | DIRECT: @Stable/skippability investigation documented with DEFERRED recommendation and rationale in compose-view-identity-gap.md |
| VIEWID-03 | Phase 18.1 | Complete | DIRECT: IdentityFeature.swift with 8 section views + IdentityFeatureTests.swift with 10 TCA TestStore tests |
| VIEWID-04 | Phase 18.1 | Complete | DIRECT: ForEach.swift identifiedRenderable/identifiedIteration dual-wrapping |
| VIEWID-05 | Phase 18.1 | Complete | DIRECT: normalizeKey() applied to contentKey in VStack/HStack/ZStack AnimatedContent paths |
| VIEWID-06 | Phase 18.1 | Complete | DIRECT: 10 loop sites across VStack (4), HStack (4), ZStack (2) all use identityKey + seenKeys |
| VIEWID-07 | Phase 18.1 | Complete | DIRECT: AdditionalViewModifiers.swift TagModifier .tag role has no key() wrapping; .id role normalizes via normalizeKey() |
| VIEWID-08 | Phase 18.1 | Complete | DIRECT: Picker.swift (5 sites) + TabView.swift (1 site) use selectionTag |
| VIEWID-09 | Phase 18.1 | Complete | DIRECT: Animated paths in VStack/HStack/ZStack use key(identityKey ?? i) + seenKeys |
| VIEWID-10 | Phase 18.1 | Complete | DIRECT: KotlinBridgeToKotlinVisitor.swift guard restructured; testStateAndLetWithDefaultCombinedCodegen passes |
| VIEWID-11 | Phase 18.1 | Complete | DIRECT: composeBundleNormalizedKey() adapter in ComposeStateSaver.swift; 16 closure sites across 6 lazy container files |
| VIEWID-12 | Phase 18.1 | Complete | DIRECT: PeerStore + LocalPeerStoreItemKey in LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, List, Table |
| VIEWID-13 | Phase 18.1 | Complete | DIRECT: Manual LocalPeerStoreItemKey for standalone views + app-level TabView PeerStore from Plan 10 |
| VIEWID-14 | Phase 18.1 | Complete | DIRECT: RetainedAnimatedItems per-item AnimatedVisibility replaces AnimatedContent dual-path |

**Coverage:**
- v1 requirements: 193 total
- Sections: OBS (30), TCA (35), DEP (11), SHR (14), NAV (15), CP (8), IC (6), SQL (15), SD (12), CD (5), IR (4), UI (8), TEST (12), SPM (6), DOC (1), VIEWID (14)
- Mapped to phases: 196
- Unmapped: 0
- **Complete (evidence-backed):** 196/196
- **Pending/Unverified:** 0/196

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-03-02 -- VIEWID-13 marked complete (manual LocalPeerStoreItemKey fix); 196/196 complete*
