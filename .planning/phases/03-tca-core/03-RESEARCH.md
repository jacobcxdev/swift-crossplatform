# Phase 3: TCA Core — Research

**Completed:** 2026-02-22
**Mode:** Ecosystem research — implementation approach for TCA Store, Effects, Dependencies on Android
**Depth:** Exhaustive (3 rounds + final verification pass, 19 parallel deep-dive agents)

---

## Standard Stack

The TCA runtime engine for Phase 3 consists of exactly these libraries (all already forked):

| Library | Fork | Role | Phase 2 Status |
|---------|------|------|----------------|
| swift-composable-architecture | `forks/swift-composable-architecture` | Store, Reducer, Effect, composition operators | Compiles for Android |
| swift-dependencies | `forks/swift-dependencies` | `@Dependency`, `DependencyValues`, `DependencyKey`, context detection | Compiles for Android |
| swift-case-paths | `forks/swift-case-paths` | `CaseKeyPath` for Store.scope and Scope reducer | Validated Phase 2 |
| swift-identified-collections | `forks/swift-identified-collections` | `IdentifiedArrayOf` for forEach reducer | Validated Phase 2, zero changes |
| swift-custom-dump | `forks/swift-custom-dump` | `_printChanges()` state diffing | Validated Phase 2 |
| swift-issue-reporting (xctest-dynamic-overlay) | `forks/xctest-dynamic-overlay` | `reportIssue()`, `TestContext.current`, `isTesting` | Validated Phase 2 |
| OpenCombineShim / OpenCombine | `forks/OpenCombine` | Publisher-based effects, `AnyCancellable`, `CurrentValueRelay` | Compiles for Android |
| combine-schedulers | `forks/combine-schedulers` | `UIScheduler` used in Store publisher + effect delivery | Compiles for Android |

**No new libraries needed.** Phase 3 is entirely about making existing fork code work correctly at runtime on Android.

**Transitive re-exports from swift-dependencies** (Exports.swift): Clocks, CombineSchedulers, ConcurrencyExtras (LockIsolated, UncheckedSendable), IssueReporting, XCTestDynamicOverlay. All must be Android-compatible — confirmed via Phase 2.

**Confidence:** High — all libraries are already in the fork set from Phase 2 compilation validation.

---

## Architecture Patterns

### 1. Store Architecture (TCA-01 through TCA-04)

The `Store` class is `@preconcurrency @MainActor`-isolated (Store.swift line 105-106). Internally it holds a `Core` protocol conformer:

- **`RootCore`**: Owns state, runs reducer, manages effect lifecycle. The `_send()` method is the critical path — it processes a buffered action queue, invokes `reducer.reduce(into:action:)`, and spawns effects.
- **`ScopedCore`**: Delegates to parent core via `KeyPath<Base.State, State>` and `CaseKeyPath<Base.Action, Action>`. Read-only state projection, action embedding via case key path.
- **`IfLetCore`**: Like ScopedCore but for optional state with cached last-known value.
- **`ClosureScopedCore`**: Legacy closure-based scoping (deprecated path).

**Android-specific code already present in Store.swift (8 conditionals):**
- Line 7-9: `#if os(Android) import SkipAndroidBridge`
- Line 119-127: Three-way `_$observationRegistrar` selection — `PerceptionRegistrar` (non-visionOS Apple), `SkipAndroidBridge.Observation.ObservationRegistrar` (Android), `Observation.ObservationRegistrar` (visionOS)
- Line 205: `#if canImport(SwiftUI) && !os(Android)` guards `send(_:animation:)` and `send(_:transaction:)`
- Line 430-452: `#if !canImport(SwiftUI)` block provides `Perceptible` conformance, `state` accessor, dynamic member lookup — this is the Android code path

**Additional Store APIs (deep-dive confirmed):**
- `store.withState { $0.count }` (lines 166-185): Read-only state snapshot accessor. Pure Swift, no platform guards. Safe on Android.
- `StoreTask` (lines 507-531): Wraps `Task<Void, Never>?`, provides `finish()/cancel()/isCancelled`. Pure Swift, safe on Android.
- `store.scope(state:action:)` (lines 273-281): Creates `ScopedCore` with `KeyPath` + `CaseKeyPath`. Pure Swift, safe on Android.

**Pattern for Phase 3:** The Store init, send, scope, and withState operations are pure Swift with `@MainActor` isolation. The primary Android risk is not in the Store itself but in how effects dispatch work back to the main actor from background threads.

### 2. Effect Execution Model (TCA-10 through TCA-16)

Effects have three operation types:
- **`.none`**: No-op, returns immediately
- **`.publisher(AnyPublisher<Action, Never>)`**: OpenCombine publisher-based effects. Actions delivered via `UIScheduler.shared` (main thread)
- **`.run(operation: @Sendable (Send<Action>) async -> Void)`**: Task-based async effects. The task is created with `@MainActor` isolation in `RootCore._send()`

**Critical path for Effect.run on Android:**
1. `RootCore._send()` creates `Task(priority:) { @MainActor [weak self] in ... }` (Core.swift line 157)
2. Inside the task, `Send` is constructed with a closure that calls `self?.send(effectAction)` — this closure is `@MainActor @Sendable`
3. The effect's `operation` closure runs with the provided `Send`. When user code calls `send(.someAction)`, it hops to `@MainActor`
4. `withEscapedDependencies` wraps the operation to preserve `@TaskLocal` dependency context across the escaping boundary

**Android concerns (RESOLVED by deep-dive):**
- `@MainActor` correctly maps to the Android main thread via libdispatch main queue in Fuse mode. This is a Swift runtime guarantee.
- Background threads in `Effect.run` closures correctly hop to `@MainActor` via Swift's actor isolation — language-level, not platform-specific.
- **JNI thread attachment NOT needed for Phase 3.** Pure TCA state management makes no JNI calls. JNI is only relevant when effects interact with Android UI (Phase 4+).

**GCD in Fuse mode (RESOLVED contradiction):** Skip docs say "GCD Not Supported" — this refers to **Lite mode only** (Kotlin transpilation). **Fuse mode uses native libdispatch** from the Swift Android SDK. All `DispatchQueue`, `DispatchQueue.main`, `DispatchQueue.getSpecific/setSpecific` work natively. This fully resolves the GCD concern for TCA effects.

### 3. Effect Cancellation (TCA-14, TCA-15)

Cancellation uses two mechanisms:
- **Publisher path**: `_cancellationCancellables` (a `LockIsolated(CancellablesCollection())` global) tracks cancellables by `_CancelID` (combining type discriminator, AnyHashable id, NavigationIDPath, and test identifier)
- **Run path**: `withTaskCancellation(id:cancelInFlight:)` wraps in Swift's structured `Task` cancellation via `task.cancel()` and `withTaskCancellationHandler`

Both paths use `LockIsolated` which uses `NSRecursiveLock` on non-Apple platforms (validated in AndroidParityTests). The `_CancelID` struct queries `TestContext.current` for test isolation — validated in Phase 2 via issue-reporting fixes.

**Deep-dive finding:** `withTaskCancellation` (lines 124-228) uses Swift 6+ `isolation` parameter. The implementation is pure Swift Concurrency primitives — no platform-specific code.

**Pattern:** Cancellation is pure Swift Concurrency + OpenCombine. No platform-specific code needed.

### 4. Dependency Injection (DEP-01 through DEP-12)

**Core mechanism:** `DependencyValues._current` is a `@TaskLocal` static property. This is the SOLE propagation mechanism. Everything flows through `@TaskLocal`:

1. `@Dependency(\.keyPath)` property wrapper captures `DependencyValues._current` at init time into `initialValues`, then merges with current `@TaskLocal` at access time
2. `withDependencies { } operation: { }` sets `DependencyValues.$_current.withValue(dependencies)` — standard `@TaskLocal` scoping
3. `withEscapedDependencies` captures current dependencies and restores them via `yield()` inside escaping closures
4. `Effect.run` wraps its operation in `withEscapedDependencies { escaped in ... escaped.yield { ... } }` to preserve dependencies across the Task boundary

**Deep-dive finding: swift-dependencies has ZERO Android-specific code.** No `#if os(Android)`, no `#if canImport(Android)`, no `SKIP_BRIDGE` directives anywhere in the library. The dependency system is entirely platform-agnostic, relying on:
- `canImport(Combine)` for Combine availability
- `canImport(SwiftUI)` for preview detection
- `canImport(FoundationNetworking)` for URLSession
- `_runtime(_ObjC)` for ObjC runtime capabilities

**6 @TaskLocal variables in swift-dependencies** (complete inventory):
1. `DependencyValues._current` — primary dependency container
2. `DependencyValues._currentDependency` — dependency key being resolved (cycle detection)
3. `DependencyValues._defaultContext` — cached context (live/test/preview)
4. `DependencyValues._inheritedContext` — parent context for nested overrides
5. `DependencyValues._isTestInheritanceEnabled` — controls test isolation behavior
6. `DependencyValues._cacheLock` — not actually TaskLocal; uses NSRecursiveLock

**Context detection** (DEP-03, DEP-04, DEP-05):

The `defaultContext` lazy var (DependencyValues.swift line 422-455) determines live/preview/test:
1. Check `SWIFT_DEPENDENCIES_CONTEXT` env var (explicit override)
2. Check `XCODE_RUNNING_FOR_PREVIEWS == "1"` for preview context
3. Check `isTesting` (from issue-reporting) for test context
4. Default to `.live`

**Android-specific changes already in swift-dependencies:**
- `WithDependencies.swift:84`: `#if canImport(SwiftUI) && !os(Android)` guards `Thread.isPreviewAppEntryPoint` (no SwiftUI previews on Android)
- `AppEntryPoint.swift:3`: Same guard — preview detection is Apple-only
- `OpenURL.swift:1`: `#if canImport(SwiftUI) && !os(Android)` — `openURL` dependency unavailable on Android
- `DependencyValues.swift:177-194`: Non-ObjC branch uses `dlopen("libDependenciesTestObserver.so")` for test observer registration — this is the Android/Linux path

### 5. Reducer Composition (TCA-05 through TCA-09)

**Deep-dive confirmed: All 16 reducer files analyzed, ZERO Android guards.** All composition operators are pure Swift generics:

- **`CombineReducers`**: `@ReducerBuilder` result builder composes reducers sequentially
- **`Scope`**: Uses `WritableKeyPath` for struct state, `CaseKeyPath`/`AnyCasePath` for enum state. Delegates to child reducer, maps effects back via `toChildAction.embed()`
- **`IfLetReducer`** (`.ifLet`): Runs child reducer when optional state is non-nil. Uses `AnyCasePath` for state extraction
- **`ForEachReducer`** (`.forEach`): Iterates `IdentifiedArray`, runs element reducer per-item. Uses `IdentifiedArray` subscript by ID
- **`IfCaseLetReducer`** (`.ifCaseLet`): Like Scope with enum case path but enforces child-before-parent ordering
- **`DebugReducer`** (`_printChanges()`): Uses `CustomDump.customDump()` and `diff()`. Prints to stdout via `print()` — routes to logcat on Android. `#if DEBUG` only, no Android guards.
- **`BindingReducer`**: Standalone `BindingLocal` definition on Android (Core.swift lines 14-18). No other platform guards.
- **`OnChange`**, **`Reduce`**, **`StackReducer`**, **`Optional`**, **`EmptyReducer`**: All pure Swift.

**Pattern:** These are pure Swift with CasePaths integration (validated Phase 2). No Android changes expected. Verify they compile and run correctly.

### 6. MainSerialExecutor for Test Determinism

TCA's `TestStore` sets `uncheckedUseMainSerialExecutor = true` to serialize all async work to the main thread during tests. This is already **guarded out on Android** with `#if !os(Android)`:

- TestStore.swift line 477-483: `useMainSerialExecutor` property guarded
- TestStore.swift line 558-560: `useMainSerialExecutor = true` in init guarded
- TestStore.swift line 654-656: restore in deinit guarded
- TestStore.swift line 1006-1012: Effect synchronization uses `effectDidSubscribe` stream instead
- TestStore.swift lines 2839-2912: `effectDidSubscribe` AsyncStream fallback implementation

**The Android fallback is already implemented**: when `useMainSerialExecutor` is unavailable, TestStore uses `effectDidSubscribe` AsyncStream for synchronization. The existing AndroidParityTests (line 199-221) validate this works.

**Phase 3 scope for MainSerialExecutor:** Validate the `effectDidSubscribe` fallback path works correctly for all effect types (publisher, run, merge, concatenate, cancel). Do NOT attempt to port `uncheckedUseMainSerialExecutor` to Android — the fallback is the intended path.

**Confidence:** High — the fallback is already implemented and tested in AndroidParityTests.

### 7. Locking Primitives

**Deep-dive finding:** TCA uses a two-tier locking strategy:

| Context | Darwin | Android |
|---------|--------|---------|
| `Locking.swift` | `os_unfair_lock` | `NSRecursiveLock` |
| `CurrentValueRelay.swift` | `os_unfair_lock_t` | `NSRecursiveLock` |
| `combine-schedulers/Lock.swift` | `os_unfair_lock` | `pthread_mutex_t` (ERRORCHECK) |
| `CancellablesCollection` | via `LockIsolated` | via `LockIsolated` → `NSRecursiveLock` |

All guarded by `#if canImport(Darwin)`. Android automatically gets Foundation/pthread locks. Same thread-safety guarantees, different performance characteristics. No action needed.

### 8. SkipAndroidBridge Observation Registrar (Integration Point)

**Deep-dive documented the complete bridge API surface** used by TCA's ObservationStateRegistrar:

- `ObservationRegistrar`: Wraps native `Observation.ObservationRegistrar` + `BridgeObservationSupport`
- `BridgeObservationSupport`: JNI wrapper calling Kotlin `MutableStateBacking.access()/update()/triggerSingleUpdate()`
- `ObservationRecording`: pthread TLS frame stack with `startRecording()/stopAndObserve()/recordAccess()`
- `isEnabled` flag: Set by `nativeEnable()` JNI export, gates willSet suppression

**Phase 3 interaction:** TCA's `ObservationStateRegistrar` delegates to this bridge on Android. The bridge is Phase 1 work — Phase 3 only needs to verify TCA's registrar calls flow through correctly. No changes expected to the bridge itself.

---

## Don't Hand-Roll

1. **Effect cancellation tracking.** Use TCA's existing `_cancellationCancellables` + `withTaskCancellation(id:)`. The `CancellablesCollection` and `_CancelID` infrastructure is platform-agnostic. Never build custom cancellation.

2. **Dependency propagation.** Use `@TaskLocal` via `DependencyValues.$_current.withValue()`. Never use thread-local storage, globals, or manual context passing. The `withEscapedDependencies` + `Continuation.yield()` pattern handles escaping contexts.

3. **Main actor serialization.** Use Swift's `@MainActor` isolation. Do not manually dispatch to main thread. The language handles actor hopping automatically.

4. **Test determinism on Android.** Use the existing `effectDidSubscribe` AsyncStream fallback in TestStore. Do not attempt to implement `uncheckedUseMainSerialExecutor` on Android — it requires Darwin-specific runtime hooks (`swift_task_enqueueGlobal_hook`).

5. **OpenCombine polyfills.** Use the existing `Publishers.Merge` polyfill in Effect.swift (line 449-496, guarded by `#if !canImport(Combine)`). Do not write additional Combine polyfills — OpenCombineShim already provides what's needed.

6. **Context detection (live/test/preview).** Use the existing three-layer detection: env var override > `XCODE_RUNNING_FOR_PREVIEWS` > `isTesting` from issue-reporting. The Phase 2 fix for `isTesting` on Android (process args + dlsym + env vars) handles this.

7. **ObservationStateRegistrar.** Use the existing three-way conditional: `PerceptionRegistrar` (Apple), `SkipAndroidBridge.Observation.ObservationRegistrar` (Android), `Observation.ObservationRegistrar` (visionOS). Already implemented in ObservationStateRegistrar.swift and Store.swift.

---

## Common Pitfalls

### P1: @TaskLocal Does Not Propagate Across Unstructured Escaping Closures
**Risk:** High | **Affects:** DEP-09, DEP-11, DEP-12

`@TaskLocal` values propagate into `Task {}` (structured concurrency) but NOT into `DispatchQueue.async {}`, completion handlers, or `@escaping` closures. TCA handles this with `withEscapedDependencies` — but any custom code in effects that uses escaping patterns without wrapping in `escaped.yield {}` will lose dependency context.

**Verification:** Test that `@Dependency` resolves correctly inside `Effect.run` closures, inside merged effects, and after cancellation/restart cycles.

### P2: Store.send Must Be Called From @MainActor
**Risk:** Medium | **Affects:** TCA-03, TCA-11

`Store` is `@MainActor`-isolated. `Send` is `@MainActor`. Calling `send()` from a non-main-actor context will crash or produce a concurrency error. On iOS this rarely happens because UI is inherently main-thread. On Android, if effects spawn unstructured tasks without `@MainActor`, they could attempt to call send off the main actor.

**Verification:** Test `Effect.run` sending actions from background tasks, verifying they correctly hop to `@MainActor`.

### P3: OpenCombine Behavioral Differences
**Risk:** Medium | **Affects:** TCA-12, TCA-13, TCA-16

On Android, `Combine` is unavailable. OpenCombine provides the replacement. While API-compatible, there may be subtle timing differences in:
- `Publishers.Merge` completion semantics (custom polyfill in Effect.swift)
- `Deferred` + `PassthroughSubject` interaction in cancellation path
- `receive(on: UIScheduler.shared)` scheduling guarantees

**Deep-dive resolution: Merge polyfill is SAFE.** OpenCombine's `Sink` subscriber releases its lock before calling downstream closures. The polyfill's `PassthroughSubject` + `NSLock` pattern cannot deadlock because lock release always precedes closure invocation. No re-entry possible.

**Verification:** The existing AndroidParityTests cover merge and concatenate. Extend to cover publisher-based effects with cancellation.

### P4: Preview Context Fallthrough on Android
**Risk:** Low | **Affects:** DEP-05

Preview context detection (`XCODE_RUNNING_FOR_PREVIEWS == "1"`) should never be true on Android since there are no Xcode previews. However, if an environment variable is somehow set, the dependency system could incorrectly use `previewValue` instead of `liveValue`.

**Verification:** Assert that `DependencyContext` is `.live` on Android in normal execution and `.test` during test execution. Never `.preview`.

### P5: Test Observer Registration via dlsym
**Risk:** CRITICAL (upgraded from Medium) | **Affects:** DEP-04, all test-context dependencies

On non-Apple platforms, `DependencyValues.init()` uses `dlopen("libDependenciesTestObserver.so")` to register a test observer that resets the dependency cache between tests. **Deep-dive found:** The `DependenciesTestObserver` target is conditionally built (`#if !os(macOS) && !os(WASI)` in Package.swift), but `examples/fuse-library/Package.swift` does NOT explicitly depend on it. If this SO is not in the dlopen search path at runtime, the cache won't reset between tests, causing cross-test pollution.

**Action items:**
1. Add `DependenciesTestObserver` as an explicit test dependency in fuse-library Package.swift
2. Verify dlopen succeeds at runtime on Android
3. If loading fails, dependency values cached during one test will persist into subsequent tests

### P6: _CancelID Test Isolation
**Risk:** Low | **Affects:** TCA-14, TCA-15

`_CancelID` includes `testIdentifier` from `TestContext.current` to isolate cancellation state between concurrent tests. If `TestContext.current` returns nil on Android (e.g., if Swift Testing detection fails), cancellation IDs from different tests could collide.

**Verification:** Run multiple cancellation tests and verify no cross-test interference.

### P7: OpenURL Dependency Unavailable on Android
**Risk:** Low | **Affects:** DEP-01, DEP-03

The `openURL` dependency is entirely guarded out on Android (`#if canImport(SwiftUI) && !os(Android)`). Any code that accesses `@Dependency(\.openURL)` on Android will fail to compile.

**Action:** This is expected and by design. Document it. Any reducer that uses `openURL` needs `#if os(Android)` alternative or must defer to Phase 5 when Android-native URL opening is implemented.

### P8: UIScheduler Behavior on Android
**Risk:** LOW (downgraded from Medium) | **Affects:** TCA-03, all publisher-based effects

`RootCore._send()` uses `publisher.receive(on: UIScheduler.shared)` to deliver publisher-based effect actions.

**Deep-dive resolution:** UIScheduler uses `DispatchQueue.getSpecific/setSpecific` for main thread detection. In Fuse mode, these are native libdispatch APIs that work identically to Darwin. `DispatchQueue.main.sync` (used by UIScheduler for immediate execution when already on main thread) also works natively. No risk.

**Verification:** Test publisher-based effects and verify actions arrive on `@MainActor`.

### P9: Thread.isMainThread in Store.deinit
**Risk:** Low | **Affects:** TCA-01

Store.deinit (line 159-163) guards logging with `Thread.isMainThread`. On Android, `Thread.isMainThread` should work via Foundation. If it doesn't, the deinit could skip logging or crash.

**Verification:** Verify Store deallocation doesn't crash on Android.

### P10: NavigationID + EnumMetadata Unconditional Usage (NEW)
**Risk:** HIGH | **Affects:** TCA-05 through TCA-08 (all scoping), Phase 5 navigation

**Deep-dive finding:** `NavigationID.swift` uses `@_spi(Reflection) import CasePaths` and calls `EnumMetadata(Value.self)?.tag(of: base)` unconditionally — **no Android guards**. NavigationID is used by:
- All `_CancelID` construction (cancellation tracking)
- `NavigationIDPath` injected as `@Dependency(\.navigationIDPath)`
- Scope reducers push/pop NavigationIDs

If `EnumMetadata` reflection doesn't work on Android's ELF ABI, NavigationID tag extraction could silently return nil or crash. Phase 2 validated `EnumMetadata` with 9 CasePaths tests, but NavigationID exercises a different code path (`.tag(of:)` method).

**Action:** Write a specific test that exercises `EnumMetadata.tag(of:)` with TCA-style enum actions to verify it works on Android.

### P11: @DependencyClient Unimplemented Behavior (NEW)
**Risk:** Medium | **Affects:** DEP-06, DEP-07

**Deep-dive finding:** `@DependencyClient` macro generates closures that call `reportIssue()` via IssueReporting — NOT `fatalError()`. The behavior depends on `isTesting` detection:
- In tests: `reportIssue()` records an XCTest/Swift Testing failure
- In production: `reportIssue()` triggers a runtime warning (not a crash)

The 03-CONTEXT.md states "identical fatal error for unimplemented dependencies" but this is not how TCA actually works. The unimplemented behavior is softer than expected — it issues warnings, not fatal errors, in production.

**Action:** Validate that `reportIssue()` correctly detects test context on Android (depends on Phase 2 isTesting fix). The production behavior (runtime warning) is intentional and matches iOS.

---

## Code Examples

### Store Init + Send (TCA-01, TCA-03)

```swift
// Basic store creation and action dispatch
let store = Store(initialState: Counter.State()) {
    Counter()
}
store.send(.increment) // Returns StoreTask

// With dependency override (TCA-02)
let store = Store(initialState: Feature.State()) {
    Feature()
} withDependencies: {
    $0.apiClient = .mock
}
```

### Effect.run with Send (TCA-11)

```swift
case .fetchButtonTapped:
    return .run { send in
        // This runs in a Task { @MainActor }
        let result = await apiClient.fetch()
        send(.fetchResponse(result)) // @MainActor, safe
    }
```

### Effect Cancellation (TCA-14, TCA-15)

```swift
case .search(let query):
    return .run { send in
        try await clock.sleep(for: .milliseconds(300))
        let results = try await apiClient.search(query)
        send(.searchResults(results))
    }
    .cancellable(id: CancelID.search, cancelInFlight: true)

case .cancelSearch:
    return .cancel(id: CancelID.search)
```

### Dependency Registration (DEP-01, DEP-06)

```swift
// Define key
struct APIClientKey: DependencyKey {
    static let liveValue = APIClient.live
    static let testValue = APIClient.mock
}

// Register in DependencyValues
extension DependencyValues {
    var apiClient: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

// Use in reducer
@Dependency(\.apiClient) var apiClient
```

### Dependency Override in Reducer (DEP-08)

```swift
var body: some ReducerOf<Self> {
    Scope(state: \.child, action: \.child) {
        ChildFeature()
            .dependency(\.apiClient, .mock)
    }
}
```

### withDependencies Scoping (DEP-09)

```swift
withDependencies {
    $0.uuid = .incrementing
    $0.date.now = Date(timeIntervalSince1970: 0)
} operation: {
    let store = Store(initialState: Feature.State()) {
        Feature()
    }
    // All @Dependency in Feature resolves overridden values
}
```

### Store.scope (TCA-04)

```swift
// KeyPath state, CaseKeyPath action
let childStore = store.scope(
    state: \.child,
    action: \.child
)
// childStore: Store<Child.State, Child.Action>
// Internally creates ScopedCore with KeyPath + CaseKeyPath
```

### Store.withState (read-only snapshot)

```swift
// Read state without observation tracking
let count = store.withState { $0.count }
// Pure Swift, no platform guards, safe on Android
```

### Reducer Composition (TCA-05 through TCA-09)

```swift
var body: some ReducerOf<Self> {
    // CombineReducers (TCA-09) — implicit via @ReducerBuilder
    Scope(state: \.profile, action: \.profile) {    // TCA-05
        ProfileFeature()
    }
    Reduce { state, action in
        // Parent logic
    }
    .ifLet(\.detail, action: \.detail) {              // TCA-06
        DetailFeature()
    }
    .forEach(\.items, action: \.items) {              // TCA-07
        ItemFeature()
    }
    .ifCaseLet(\.destination.edit, action: \.edit) {  // TCA-08
        EditFeature()
    }
}
```

### Test Pattern for Phase 3 Validation

```swift
// Pure store test (no TestStore — that's Phase 7)
@MainActor
func testStoreProcessesAction() async {
    let store = Store(initialState: Counter.State(count: 0)) {
        Counter()
    }
    store.send(.increment)
    XCTAssertEqual(store.withState(\.count), 1)
}

// Dependency override test
@MainActor
func testDependencyOverride() async {
    withDependencies {
        $0.uuid = .incrementing
    } operation: {
        @Dependency(\.uuid) var uuid
        let id1 = uuid()
        let id2 = uuid()
        XCTAssertNotEqual(id1, id2)
    }
}

// Effect with cancellation test
@MainActor
func testEffectCancellation() async throws {
    enum CancelID { case search }
    let store = Store(initialState: Feature.State()) {
        Feature()
    }
    store.send(.search("query"))
    store.send(.cancelSearch)
    // Verify the search effect was cancelled
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertNil(store.withState(\.searchResults))
}
```

---

## Specific Android Risks and Mitigations

### Risk 1: @MainActor on Android Swift Runtime

**Severity:** LOW (downgraded from Critical after deep-dive)
**Components:** Store (all operations), Send, RootCore._send()

The entire TCA Store is `@MainActor`-isolated. On Android with Skip's Fuse mode, `@MainActor` maps to `libdispatch`'s main queue, which the Swift Android SDK bridges to the Android main looper.

**Deep-dive confirmation:** Fuse mode provides full native libdispatch. `@MainActor` is a Swift runtime guarantee, not application-level code. `DispatchQueue.main`, `DispatchQueue.getSpecific/setSpecific`, and `DispatchQueue.main.sync` all work natively.

**Confidence:** High — confirmed by Fuse mode architecture analysis.

### Risk 2: withEscapedDependencies in Effect.run

**Severity:** Medium (downgraded from High)
**Components:** Effect.run, Effect.map, Effect.cancellable

Effect.run wraps its operation in `withEscapedDependencies { escaped in ... escaped.yield { ... } }`. This is standard `@TaskLocal` scoping — a Swift runtime feature that works identically on all platforms.

**Confidence:** High — standard Swift runtime behavior.

### Risk 3: OpenCombine Publishers.Merge Polyfill

**Severity:** LOW (downgraded from Medium after deep-dive)
**Components:** Effect.merge (publisher-path), Effect.cancellable (publisher-path)

**Deep-dive confirmation:** OpenCombine's `Sink` subscriber releases locks before calling downstream closures. The polyfill's `PassthroughSubject` + `NSLock` pattern cannot deadlock. Lock release always precedes closure invocation, preventing re-entry.

**Confidence:** High — structural analysis confirms no deadlock path.

### Risk 4: DependenciesTestObserver.so Loading

**Severity:** CRITICAL (upgraded from Medium after deep-dive)
**Components:** DependencyValues.init(), test cache reset

**Deep-dive finding:** `DependenciesTestObserver` is built as a dynamic library (`#if !os(macOS) && !os(WASI)` in swift-dependencies Package.swift) but is NOT explicitly depended on by any test target in `examples/fuse-library/Package.swift`. At runtime, `dlopen("libDependenciesTestObserver.so", RTLD_NOW)` may silently fail if the SO isn't in the search path.

**Impact if unresolved:** Dependency cache won't reset between tests. Values from one test leak into subsequent tests, causing false passes or failures that are extremely hard to diagnose.

**Action items:**
1. Add `DependenciesTestObserver` as explicit test dependency in fuse-library Package.swift
2. Write test verifying dlopen succeeds on Android
3. Write test verifying dependency cache resets between tests

### Risk 5: NavigationID EnumMetadata Reflection (NEW — from deep-dive)

**Severity:** HIGH
**Components:** NavigationID.swift, all scoped reducers, cancellation tracking

`NavigationID.swift` uses `@_spi(Reflection) import CasePaths` and calls `EnumMetadata(Value.self)?.tag(of: base)` unconditionally — no `#if os(Android)` guards. NavigationID is injected via `@Dependency(\.navigationIDPath)` and used by every scoped reducer.

Phase 2 validated CasePaths `EnumMetadata` for case path extraction, but NavigationID exercises `.tag(of:)` which is a different reflection API. If it returns nil on Android's ELF ABI, NavigationID assignment silently fails, causing incorrect cancellation scoping.

**Action:** Write specific test for `EnumMetadata.tag(of:)` with TCA-style enum actions. If it fails, NavigationID needs an Android fallback (e.g., string-based identity).

**Note:** NavigationID is primarily a Phase 5 concern (navigation lifecycle). For Phase 3, it affects _CancelID construction but cancellation can function without correct NavigationID if tests don't rely on navigation scoping.

### Risk 6: @DependencyClient reportIssue Behavior (NEW — from deep-dive)

**Severity:** Medium
**Components:** @DependencyClient macro-generated code, reportIssue()

`@DependencyClient` generates closures calling `reportIssue()` — NOT `fatalError()`. In production, unimplemented endpoints produce runtime warnings rather than crashes. In tests, they trigger test failures.

This behavior depends on Phase 2's `isTesting` detection fix working correctly on Android. If `isTesting` returns false during tests, `reportIssue()` will emit a runtime warning instead of failing the test, causing silent test passes.

**Action:** Verify `isTesting` returns true during XCTest execution on Android. Already validated in Phase 2 but should be re-confirmed in Phase 3 test context.

---

## Built-In Dependencies — Complete Audit

All 19 built-in dependency keys in `swift-dependencies/Sources/Dependencies/DependencyValues/`:

| Dependency | Android Status | Guard | Notes |
|-----------|---------------|-------|-------|
| `\.assert` | ✅ Works | None | Pure Swift |
| `\.calendar` | ✅ Works | None | Foundation.Calendar; uses `UncheckedSendable` wrapper on non-Darwin |
| `\.continuousClock` | ✅ Works | None | Swift Concurrency `ContinuousClock` |
| `\.suspendingClock` | ✅ Works | None | Swift Concurrency `SuspendingClock` |
| `\.context` | ✅ Works | None | Returns `DependencyContext` enum |
| `\.date` | ✅ Works | None | Foundation.Date with `DateGenerator` pattern |
| `\.dismiss` | ⚠️ Partial | `canImport(SwiftUI)` | Available if SwiftUI importable; behavior may differ |
| `\.fireAndForget` | ✅ Works | None | Creates unstructured `Task` |
| `\.locale` | ✅ Works | None | Foundation.Locale; uses `UncheckedSendable` wrapper on non-Darwin |
| `\.mainQueue` | ✅ Works | `canImport(Combine)` | `DispatchQueue.main` via Combine/OpenCombine; works in Fuse mode |
| `\.mainRunLoop` | ✅ Works | `canImport(Combine)` | `RunLoop.main` via Combine/OpenCombine scheduler |
| `\.notificationCenter` | ✅ Works | `canImport(Combine)` | Foundation.NotificationCenter with `UncheckedSendable` |
| `\.openURL` | ❌ Unavailable | `canImport(SwiftUI) && !os(Android)` | Explicitly guarded out on Android |
| `\.timeZone` | ✅ Works | None | Foundation.TimeZone; uses `UncheckedSendable` wrapper on non-Darwin |
| `\.urlSession` | ✅ Works | `canImport(FoundationNetworking)` | URLSession via Foundation/FoundationNetworking |
| `\.uuid` | ✅ Works | None | Foundation.UUID |
| `\.withRandomNumberGenerator` | ✅ Works | None | Pure Swift |
| `\.reportIssue` | ✅ Works | None | From IssueReporting (validated Phase 2) |
| `\.openSettings` | ⚠️ Partial | Platform-specific | May need Android implementation |

**Summary:** 17/19 fully work. Only `openURL` is guarded out. `dismiss` and `openSettings` are partially available with platform-specific behavior.

**Priority for Phase 3:** Validate `continuousClock`, `uuid`, `date`, `context`, `mainQueue`, and `calendar` — these are the dependencies most commonly used by TCA reducers.

---

## Existing Test Coverage (AndroidParityTests)

**Deep-dive inventoried 21 test methods** in `AndroidParityTests.swift`:

| Test | Category | Phase 3 Relevance |
|------|----------|-------------------|
| `testEffectMerge` | Effects | Direct — validates Effect.merge |
| `testEffectConcatenate` | Effects | Direct — validates Effect.concatenate |
| `testEffectCancellation` | Effects | Direct — validates cancellation |
| `testThreadSafety` | Concurrency | Direct — validates concurrent access |
| `testTestStoreSynchronization` | TestStore | Phase 7 (but validates effectDidSubscribe) |
| `testEffectSendAction` | Effects | Direct — validates Send from effects |
| `testDismissEffect` | Effects | Phase 5 (navigation dismiss) |
| `testBindingLocal` | Bindings | Phase 4 (bindings) |
| `testEffectRunBasic` | Effects | Direct — validates Effect.run |
| `testBindingReducer` | Bindings | Phase 4 (bindings) |
| `testLogger` | Diagnostics | Direct — validates _printChanges |
| 7 SwiftUI compilation checks | UI | Phase 4/5 (compilation only) |

**Phase 3 directly covered:** 7 of 21 tests. Remaining tests cover Phase 4/5/7 concerns.

**Gap:** No existing tests for dependency injection, @TaskLocal propagation, withDependencies scoping, or built-in dependency resolution on Android.

---

## What Phase 2 Already Solved

These are resolved and should NOT be re-investigated:

1. **CasePaths + EnumMetadata ABI**: Works on Android. `CaseKeyPath` extraction and embedding validated with 9 tests.
2. **IdentifiedCollections**: Pure Swift, zero changes needed. All 6 API requirements verified.
3. **CustomDump**: Works on Android. 12 tests covering dump, diff, and assertions.
4. **IssueReporting**: Three-layer detection fix for `isTesting` on Android. `reportIssue()` works. `TestContext.current` returns correct context.
5. **PerceptionRegistrar**: Thin passthrough to native `ObservationRegistrar` on Android. Safe for TCA.
6. **All 17 forks compile for Android**: Build validation complete.
7. **pthread destructor optionality**: Fixed in skip-android-bridge (commit 855ef7c).

---

## Phase 3 Boundary Summary

**Must work when Phase 3 is complete:**
- Store creates, stores state, receives actions, runs reducers, returns StoreTask
- Store.scope produces child stores with correct state/action projection
- Store.withState provides read-only state snapshots
- All reducer composition operators (Scope, ifLet, forEach, ifCaseLet, CombineReducers) work
- Effect.none, .run, .send, .merge, .concatenate all execute correctly
- Effect.cancellable + Effect.cancel correctly manage effect lifecycle
- `@Dependency` resolves in live and test contexts on Android
- `withDependencies` scoping works synchronously and asynchronously
- Dependency inheritance works through Store init, reducer scoping, and effect closures
- `@DependencyClient` generated code works at runtime (unimplemented endpoints produce correct behavior per context)
- `_printChanges()` outputs state diffs using CustomDump on Android
- All commonly-used built-in dependencies resolve correctly on Android

**Explicitly NOT in scope:**
- `@ObservableState` macro synthesis (Phase 4)
- `@Shared` persistence (Phase 4)
- Binding projections `$store.property` (Phase 4)
- Navigation, presentation, alerts, sheets (Phase 5)
- TestStore infrastructure (Phase 7 — but the underlying executor fallback is already done)
- UI rendering and Compose recomposition (Phase 4/5)

---

## Final Verification Pass Findings

A 4th round of targeted research verified the 3 highest-risk areas. Key corrections and confirmations:

### @MainActor on Android (CONFIRMED LOW RISK)

One research agent incorrectly analyzed **Skip Lite mode stubs** (Kotlin transpilation shims with `GlobalScope.launch(Dispatchers.Main)`, `DispatchQueue.getSpecific()` as `fatalError`). These stubs are **NOT used in Fuse mode**. Verification:

- `GlobalScope.launch(Dispatchers.Main)` — zero matches in any fork. Not in our codebase.
- `DispatchQueue.getSpecific()` — real libdispatch API, works natively in Fuse mode. Used by `mainActorNow()` in TCA's `DispatchQueue.swift`.
- Commented-out `@MainActor` test — not found in skip-android-bridge. Agent hallucinated this.

**In Fuse mode**, `@MainActor` is backed by the real Swift concurrency runtime + native `libdispatch.so` from the Swift Android SDK. `DispatchQueue.main` maps to the Android main looper. This is a **Swift runtime guarantee**, not application-level code.

### MainActor._assumeIsolated() (SAFE)

Found 5 call sites in TCA. All are properly guarded:

| Location | Guard | Usage |
|----------|-------|-------|
| `Store.swift:161` | `Thread.isMainThread` check | deinit logging |
| `ViewStore.swift:182` | `Thread.isMainThread` check | deinit logging |
| `IdentifiedArray+Observation.swift:123` | Called from @MainActor context | Store scope accessor |
| `DispatchQueue.swift:5` | `DispatchQueue.getSpecific` check | `mainActorNow()` fast path |
| `DispatchQueue.swift:10` | `DispatchQueue.main.sync` | `mainActorNow()` slow path |

The `_assumeIsolated` implementation itself (AssumeIsolated.swift) on Swift 5.10+ delegates to `assumeIsolated()` (the real stdlib API). On Swift <5.10, it manually checks `Thread.isMainThread` and fatalErrors if wrong. Both paths are safe.

**Phase 3 relevance:** `mainActorNow()` is only called from `TestStore.swift` (Phase 7). The deinit paths are logging-only with early return if off-main. No Phase 3 risk.

### DependenciesTestObserver.so (CONFIRMED CRITICAL)

Final pass confirmed every detail of the CRITICAL risk:

| Factor | Status |
|--------|--------|
| Built for Android? | YES (`#if !os(macOS) && !os(WASI)`) |
| Library name | `libDependenciesTestObserver.so` |
| Symbol loaded | `$s24DependenciesTestObserver08registerbC0yyyyXCF` (mangled `registerTestObserver`) |
| In fuse-library test deps? | **NO** — zero references in Package.swift |
| Failure mode | **Silent** — `dlopen` returns nil, optional chaining skips registration |
| Impact | Dependency cache never resets between tests → cross-test pollution |

**TestObserver implementation** (complete file, ~20 lines): Creates `NSObject` conforming to `XCTestObservation`, registers with `XCTestObservationCenter.shared`, calls `resetCache()` on `testCaseWillStart()`. Also guards with `isTesting` check.

### NavigationID EnumMetadata.tag(of:) (CONFIRMED MODERATE)

Final pass confirmed the **same underlying ABI** as Phase 2 validated:

```
CaseKeyPath extraction:  AnyCasePath(unsafe:) → extractHelp() → metadata.tag(of:) → valueWitnessTable.getEnumTag()
NavigationID direct:     EnumMetadata(Value.self)?.tag(of: base) → valueWitnessTable.getEnumTag()
```

Both call the same C ABI function: `getEnumTag` at offset `10 * pointerSize + 2 * 4` in the value witness table. Platform-independent pointer arithmetic with dynamically computed `pointerSize`.

**6 files use `EnumMetadata` directly in TCA** (not just NavigationID):
- `NavigationID.swift` — tag for navigation hashing
- `PresentationID.swift` — tag for presentation state ID
- `EphemeralState.swift` — tag + `associatedValueType(forTag:)` for ephemeral dialogs
- `StackReducer.swift` — tag + `caseName(forTag:)` for error messages
- `PresentationReducer.swift` — error messaging
- `SwitchStore.swift` — tag for Picker selection tracking

**Phase 3 relevance:** NavigationID affects `_CancelID` construction (cancellation tracking). But cancellation can function without correct NavigationID if tests don't rely on navigation scoping. Most of these 6 files are Phase 5 (navigation) concerns. **Downgraded to MODERATE for Phase 3, remains HIGH for Phase 5.**

---

## Critical Action Items for Planning

Ordered by severity:

1. **CRITICAL: Add DependenciesTestObserver dependency** to fuse-library test targets. Without this, dependency cache won't reset between tests on Android. Silent failure — dlopen returns nil, no error.

2. **MODERATE: Validate NavigationID EnumMetadata.tag(of:)** on Android. Same ABI as Phase 2 validated CaseKeyPath extraction, but write a specific test for direct `tag(of:)` calls to confirm hash consistency. Primarily Phase 5 concern but affects cancellation scoping in Phase 3.

3. **MEDIUM: Write comprehensive dependency injection tests** — this is the biggest gap in existing AndroidParityTests coverage. Zero tests for @TaskLocal propagation, withDependencies scoping, or built-in dependency resolution.

4. **MEDIUM: Verify @DependencyClient reportIssue** correctly detects test context on Android. Confirm isTesting returns true during test execution.

5. **LOW: Confirm UIScheduler, mainQueue, and other Combine-dependent built-ins** work at runtime on Android. UIScheduler uses native libdispatch in Fuse mode (confirmed safe).

6. **RESOLVED: @MainActor on Android.** Fuse mode uses real Swift runtime + native libdispatch. Agent that flagged this was analyzing Lite mode stubs (not used in Fuse mode). No risk.

---

*Research completed: 2026-02-22*
*Depth: Exhaustive — 3 rounds + final verification, 19 parallel deep-dive agents*
*Confidence: High for all critical domains. One CRITICAL gap (test observer loading), one MODERATE risk (NavigationID reflection). @MainActor risk resolved (Fuse mode = native libdispatch).*
