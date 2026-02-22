# Phase 4: TCA State & Bindings — Research

**Completed:** 2026-02-22
**Mode:** Ecosystem research — implementation approach for @ObservableState, bindings, and @Shared persistence on Android
**Depth:** Source-level audit of all fork code relevant to Phase 4 requirements

---

## Standard Stack

Phase 4 uses these libraries (all already forked, all compiled for Android in Phase 2):

| Library | Fork | Role | Phase 3 Status |
|---------|------|------|----------------|
| swift-composable-architecture | `forks/swift-composable-architecture` | @ObservableState, bindings, Store scoping, onChange, _printChanges, @ViewAction | Phase 3 complete — Store/Reducer/Effect validated |
| swift-sharing | `forks/swift-sharing` | @Shared, SharedKey, appStorage, fileStorage, inMemory, Observations, publisher | Compiles for Android; Android-specific patches already present |
| swift-perception | `forks/swift-perception` | PerceptionRegistrar (thin passthrough on Android), Bindable backport | Already patched for Android |
| OpenCombine / OpenCombineShim | `forks/OpenCombine` | Publisher support for $shared.publisher, debounce in fileStorage | Validated Phase 3 |
| combine-schedulers | `forks/combine-schedulers` | AnySchedulerOf<DispatchQueue> used by FileStorage.inMemory | Validated Phase 3 |
| skip-android-bridge | `forks/skip-android-bridge` | ObservationRegistrar bridge, BridgeObservationSupport JNI | Phase 1 work; used by ObservationStateRegistrar |

**No new libraries needed.** Phase 4 is about making existing fork code work correctly at runtime on Android for state observation, binding projection, and persistence.

**Confidence:** High — all libraries are already in the fork set and compile for Android.

---

## Architecture Patterns

### 1. @ObservableState Macro and ObservationStateRegistrar (TCA-17, TCA-18)

The `@ObservableState` macro synthesizes three members on state structs:
- `var _$id: ObservableStateID` — stable identity for change detection
- `var _$observationRegistrar: ObservationStateRegistrar` — delegates observation tracking
- `mutating func _$willModify()` — called before mutations to invalidate identity

**ObservationStateRegistrar** (already patched in Phase 1) uses a three-way conditional:

```swift
#if !os(visionOS) && !os(Android)
  let registrar = PerceptionRegistrar()           // Apple (pre-iOS 17)
#elseif os(Android)
  let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()  // Android
#else
  let registrar = Observation.ObservationRegistrar()  // visionOS
#endif
```

The registrar's `access()`, `mutate()`, `willModify()`, and `didModify()` methods have two overload sets:
1. `Subject: Observable` — for iOS 17+/visionOS (uses `Observation.ObservationRegistrar`)
2. `Subject: Perceptible` — for pre-iOS 17 (uses `PerceptionRegistrar`), guarded with `#if !os(visionOS) && !os(Android)`

**Android code path:** On Android, the `Observable` overload set is active (because Android doesn't match `!os(visionOS) && !os(Android)`). The `access()` call flows through `SkipAndroidBridge.Observation.ObservationRegistrar.access()` which records property access via `BridgeObservationSupport` JNI, and `mutate()` calls `withMutation()` which triggers Compose recomposition via the bridge.

**ObservableState protocol** itself already has the Android conditional:

```swift
#if !os(visionOS) && !os(Android)
  public protocol ObservableState: Perceptible { ... }
#else
  public protocol ObservableState: Observable { ... }
#endif
```

On Android, `ObservableState` conforms to `Observable` (not `Perceptible`), which is correct — native `libswiftObservation.so` provides the `Observable` protocol.

**Pattern for Phase 4:** Test via behavior — create `@ObservableState` structs, mutate properties, verify observation tracking fires correctly through the bridge registrar. Test `@ObservationStateIgnored` suppresses tracking. Test `_$id` stability across mutations.

### 2. Binding Projection Chain (TCA-19 through TCA-22)

The binding chain on Android follows this path:

```
@Bindable var store → $store.property → SwiftUI.Bindable<Store>.subscript(dynamicMember:)
  → _StoreBindable_SwiftUI → .sending(\.action) → Binding<Value>
  → Compose recomposition via observation bridge
```

**Key code paths already Android-aware:**

1. **`Binding+Observation.swift`**: `_StoreBinding`, `_StoreBindable_SwiftUI` are NOT guarded — available on all platforms. Only `_StoreObservedObject`, `_StoreBindable_Perception`, `_StoreUIBinding`, and `_StoreUIBindable` are guarded with `#if !os(Android)` (these are Apple-backport types).

2. **`Store` subscript for BindableAction** (Binding+Observation.swift line 175-192): The `Store[dynamicMember:]` setter calls `BindingLocal.$isActive.withValue(true) { self.send(.set(...)) }`. This is pure Swift — no platform guards. Available on Android.

3. **`BindingReducer`** (BindingReducer.swift): Entirely platform-agnostic. Extracts `BindingAction` from action, calls `bindingAction.set(&state)`. Pure Swift.

4. **`BindableAction` protocol** and `BindingAction` struct (Binding.swift): Fully available on all platforms. The `#if canImport(SwiftUI)` guard at the top of Binding.swift includes Android (Skip provides SwiftUI on Android).

**The `.sending()` API** (TCA-22): `_StoreBinding.sending()` and `_StoreBindable_SwiftUI.sending()` both call `self.binding[state: keyPath, action: action]` which invokes the Store subscript `store[state:action:]`. This writes the new value by sending `action(newValue)` through `BindingLocal.$isActive.withValue(true)`. Pure Swift, works on Android.

**Critical risk: Infinite recomposition.** The binding write path is: user mutates binding → `Store.send(.set(...))` → reducer mutates state → observation bridge fires → Compose recomposition → view body re-evaluates → reads binding (should NOT trigger another write). The Phase 1 observation bridge's `isEnabled` flag and `willSet` suppression during recording are the protection mechanism. If the binding read during body evaluation is correctly wrapped in `withObservationTracking`, no loop occurs. But if the binding's `get` accessor triggers a state mutation (e.g., due to lazy initialization), it could loop.

**Pattern:** End-to-end test: store → @Bindable → $store.property → mutate → verify exactly one state update, no loop. Explicit regression test for infinite recomposition.

### 3. ForEach Scoping with IdentifiedArray (TCA-23)

`Store.scope(state:action:)` for `IdentifiedArray` returns a `_StoreCollection` (IdentifiedArray+Observation.swift). This collection:

1. Calls `store._$observationRegistrar.access(store, keyPath: \.currentState)` to register observation
2. Copies `store.withState { $0 }` into a local `data` snapshot
3. Subscript access creates `IfLetCore` scoped to `\.[id: elementID]` with stable `scopeID`

**Identity stability:** Child stores are cached in `store.children[scopeID]` using a scope ID derived from the element's `IdentifiedArray` ID. As long as the element ID is stable, the child store is reused. Adding/removing/reordering elements creates/destroys child stores based on ID presence, not position.

**Android concern:** `_StoreCollection.subscript` calls `precondition(Thread.isMainThread)` and then `MainActor._assumeIsolated()`. Both should work on Android (Thread.isMainThread works via Foundation; `_assumeIsolated` validated in Phase 3 research).

**Pattern:** Test add, remove, reorder operations on IdentifiedArray state. Verify child store identity is preserved across reorders. Verify child state is NOT lost when collection is reordered.

### 4. Optional and Enum Scoping (TCA-24, TCA-25)

**Optional scoping** (`store.scope(state: \.child, action: \.child)` returning `Store?`):
- Implemented in Store+Observation.swift lines 84-116
- Returns `nil` when state is `nil`, creates `IfLetCore` when non-nil
- Caches child store in `children[id]`, cleans up on nil transition (`children[id] = nil`)

**Enum case switching** (`switch store.case { }`):
- Requires `@Reducer enum` macro synthesis + `@CasePathable` metadata (validated Phase 2)
- `EnumMetadata.tag(of:)` is used for runtime case discrimination
- Phase 3 research confirmed `EnumMetadata.tag(of:)` uses the same ABI as CaseKeyPath extraction (both call `valueWitnessTable.getEnumTag()`)

**Pattern:** Test nil → non-nil → nil lifecycle for optional scoping. Test case A → case B transition for enum scoping. Verify old child store is torn down on transition.

### 5. @Shared Persistence — AppStorage (SHR-01)

**AppStorageKey** is already Android-aware. The file guard is:
```swift
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit) || os(Android)
```

Key Android-specific patches already present:
1. **No KVO subscription** (line 457-461): Returns no-op `SharedSubscription {}` on Android because `UserDefaults` (backed by `SharedPreferences` via Skip) doesn't support KVO
2. **No NSObject Observer** (line 547-563): `Observer` class guarded with `#if !os(Android)`
3. **No Selector introspection** (line 315): Suite deduplication debug check guarded with `#if DEBUG && !os(Android)`
4. **InMemory UserDefaults** (line 631-632): Uses UUID-based suite name on Android (no `NSTemporaryDirectory()`)

**Implication of no-op subscription:** External changes to `UserDefaults` (from another process or thread not going through `@Shared`) will NOT be observed on Android. However, TCA's `@Shared` observation wrapper handles Compose recomposition for mutations going through the `@Shared` write path. This is sufficient for SHR-01 through SHR-06.

**Value types to validate:** Bool, Int, Double, String, Data, URL, Date, [String], optionals of each, RawRepresentable enums, Codable types. The `CastableLookup` uses `store.object(forKey:) as? Value` — must verify each type round-trips correctly through Skip's `SharedPreferences` bridge.

**Pattern:** Test every value type round-trip. Test nil optionals. Test concurrent read/write from different actors.

### 6. @Shared Persistence — FileStorage (SHR-02)

**CRITICAL FINDING: FileStorageKey is NOT available on Android.**

The file guard is:
```swift
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)
```

This does NOT include `os(Android)`. The entire `FileStorageKey` type, `FileStorage` struct, and all related infrastructure is compiled out on Android.

**Why:** FileStorageKey depends on:
- `DispatchSource.makeFileSystemObjectSource()` — file system event monitoring (Linux inotify / Darwin kqueue). Android support for `DispatchSource` file system monitoring via libdispatch is uncertain.
- `CombineSchedulers.AnySchedulerOf<DispatchQueue>` — for debounced writes
- `FileManager.default` — available on Android via Foundation, but the DispatchSource dependency is the blocker

**Required action for Phase 4:** Either:
1. **Add `|| os(Android)` to the guard** and provide an Android-specific `subscribe()` implementation (e.g., polling or no-op, similar to appStorage's approach)
2. **Create an Android-specific FileStorageKey** that uses Foundation `FileManager` for read/write but skips `DispatchSource`-based file watching

**Recommended approach:** Option 1 — add `os(Android)` to the guard, keep the `FileStorage.fileSystem` static property mostly intact (FileManager, Data.write, Data.contentsOf all work on Android), but provide a no-op or polling-based `fileSystemSource` on Android. The `FileStorage.inMemory` variant works as-is (no DispatchSource dependency).

**URL resolution:** On Android, `URL.documentsDirectory` (and similar Foundation URLs) should resolve to the app's internal storage directory. Skip bridges `FileManager` operations to Android's `Context.getFilesDir()` equivalent. Verify with a test that writes a file and reads it back.

**Confidence:** Medium — FileManager basics should work, but DispatchSource file monitoring needs an Android fallback.

### 7. @Shared Persistence — InMemory (SHR-03)

**Trivially portable.** `InMemoryKey` has no platform guards, no imports beyond `Dependencies` and `Foundation`. Uses `Mutex<[String: any Sendable]>` for thread-safe storage. `subscribe()` returns no-op `SharedSubscription {}`.

**Pattern:** Validate basic read/write/cross-feature sharing. No deep investigation needed.

### 8. Combine/OpenCombine in swift-sharing (SHR-10, $shared.publisher)

**Already patched.** The swift-sharing library uses `#if canImport(Combine) || canImport(OpenCombine)` throughout:

| File | Combine Usage | Android Path |
|------|--------------|--------------|
| `Shared.swift` | `PassthroughRelay<Value>` subject, `AnyCancellable` | OpenCombine via `OpenCombineShim` |
| `SharedReader.swift` | Same pattern | OpenCombine via `OpenCombineShim` |
| `SharedPublisher.swift` | `$shared.publisher` API | OpenCombine `Publisher` protocol |
| `PassthroughRelay.swift` | Custom relay (not Combine's PassthroughSubject) | Dual implementation with `#if canImport(Combine)` / `#else` branches |
| `Reference.swift` | Publisher for value changes | OpenCombine |

**The `$shared.publisher` API** (SharedPublisher.swift) returns `Just<Void>(()).flatMap { _ in box.subject.prepend(wrappedValue) }`. This uses `Just`, `flatMap`, and `prepend` — all available in OpenCombine.

**The PassthroughRelay** is a custom implementation (NOT Combine's `PassthroughSubject`). It has explicit `#if canImport(Combine)` and `#else` (OpenCombine) branches for the `Subscription` inner class because `Combine.Subscription` and `OpenCombine.Subscription` are different protocols. Both branches are functionally identical.

**DebugReducer** (`_printChanges`) imports `OpenCombineShim` unconditionally and uses `Deferred<Empty<Action, Never>>` + `.publisher { }` for async print scheduling. This works with OpenCombine on Android.

**Pattern:** Test `$shared.publisher` emits values on mutation. Test `Observations { }` async sequence (SHR-09) emits on `@Shared` mutation. Both APIs must work on Android.

### 9. Shared Binding Projection (SHR-05, SHR-06, SHR-07, SHR-08)

**`Binding($shared)`** (SharedBinding.swift) already has an Android code path:

```swift
#elseif os(Android)
  func open(_ reference: some MutableReference<Value>) -> Binding<Value> {
    @SwiftUI.Bindable var reference = reference
    return $reference._wrappedValue as! Binding<Value>
  }
  self = open(base.reference)
  return
```

On Android, it uses `SwiftUI.Bindable` (available via Skip's SwiftUI bridge) to create a `Binding` from the mutable reference. On pre-iOS 17 Apple platforms, it uses `PerceptionCore.Bindable` instead.

**`$shared.child` keypath projection** (Shared.swift line 261-270): Uses `_AppendKeyPathReference(base:keyPath:)` to create a derived `Shared<Member>` from a writable key path. Pure Swift, no platform guards.

**`Shared($optional)` unwrapping** (Shared.swift line 61-67): Uses `_OptionalReference(base:initialValue:)`. Pure Swift, no platform guards.

**`Shared: DynamicProperty`** (Shared.swift line 496-503): The `update()` method is guarded with `#if !os(Android)` — on Android, `Shared` does NOT call `box.subscribe(state: _generation)`. This means the SwiftUI `@State`-based generation counter for triggering view updates is disabled on Android. Instead, the observation bridge handles recomposition.

**Pattern:** Test `Binding($shared)` creates a working two-way binding. Test keypath projection derives child Shared. Test optional unwrapping.

### 10. Cross-Cutting: Double-Notification Prevention (SHR-11)

When an `@Observable` model contains `@ObservationIgnored @Shared var prop`, mutations to `prop` should fire exactly one notification (from the `@Shared` change tracking), not two (one from Observable, one from Shared). The `@ObservationIgnored` annotation prevents the Observable registrar from tracking the property, while `@Shared`'s own change tracking still fires.

**Pattern:** Dedicated regression test — `@Observable` model with `@ObservationIgnored @Shared` property. Mutate. Assert exactly one recomposition.

### 11. Cross-Cutting: Thread Safety (SHR-12, SHR-13)

The `InMemoryKey` uses `Mutex<[String: any Sendable]>` (swift-sharing's Mutex wrapper). `AppStorageKey` uses `UserDefaults` which is thread-safe. `PersistentReferences` (the global reference cache) uses locking.

**Pattern:** Concurrent mutations from multiple actors to same `@Shared` key. Verify synchronization — all readers see consistent state.

### 12. onChange Reducer (TCA-29)

`_OnChangeReducer` (OnChange.swift) is pure Swift generics — captures `toValue: (State) -> Value`, compares old/new with `isDuplicate`, runs nested reducer on change. No platform guards, no imports beyond the TCA module.

**Pattern:** Standard behavioral test. Low risk.

### 13. _printChanges (TCA-30)

`_PrintChangesReducer` (DebugReducer.swift) uses `CustomDump.customDump()` and `diff()` (validated Phase 2). Output goes to `print()` which routes to logcat on Android. Uses `DispatchQueue` for async print scheduling — works in Fuse mode.

The `#if DEBUG` guard means `_printChanges()` is a no-op in release builds. The `SharedChangeTracker` integration (for `@Shared` state changes) requires `@_spi(SharedChangeTracking) import Sharing`.

**Pattern:** Verify output format is readable in Android logcat. Validate diff rendering with customDump.

### 14. @ViewAction (TCA-31)

`ViewAction` protocol and `ViewActionSending` protocol (ViewAction.swift) are pure Swift with `#if canImport(SwiftUI)`. The `send(_:animation:)` and `send(_:transaction:)` overloads are guarded with `#if !os(Android)` (no SwiftUI animation/transaction API on Android), but the base `send(_:)` method is available.

**Pattern:** Verify `send()` dispatches the correct view action. Low risk.

---

## Don't Hand-Roll

1. **ObservationStateRegistrar.** Use the existing three-way conditional in `ObservationStateRegistrar.swift`. The bridge registrar on Android delegates to `SkipAndroidBridge.Observation.ObservationRegistrar`. Do not create a custom registrar.

2. **Binding projection types.** Use `_StoreBinding`, `_StoreBindable_SwiftUI`, and the Store subscript setters. These are already available on Android. Do not create custom binding wrappers.

3. **SharedKey persistence infrastructure.** Use the existing `SharedKey` / `SharedReaderKey` protocol and `LoadContinuation` / `SaveContinuation` / `SharedSubscriber` / `SharedSubscription` types. They are fully platform-agnostic.

4. **OpenCombine publisher support.** Use the existing `#if canImport(Combine) || canImport(OpenCombine)` pattern with `OpenCombineShim` import. The `PassthroughRelay` already has dual implementations. Do not create custom publisher types.

5. **File system monitoring on Android.** Do NOT attempt to implement `DispatchSource.makeFileSystemObjectSource()` on Android. Use a no-op subscription (like appStorage does) or a simple polling fallback. The `FileStorage.inMemory` variant already works without DispatchSource.

6. **UserDefaults KVO on Android.** The no-op subscription is already implemented in AppStorageKey. Do not attempt to bridge KVO to SharedPreferences change listeners. TCA's observation bridge handles recomposition for mutations going through `@Shared`.

7. **Mutex / locking primitives.** Use the existing `Mutex` (swift-sharing's backport of Swift 6 Mutex), `LockIsolated` (from ConcurrencyExtras), and `NSRecursiveLock`. These are validated on Android.

---

## Common Pitfalls

### P1: FileStorageKey Compiled Out on Android
**Risk:** CRITICAL | **Affects:** SHR-02
**Root cause:** `#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)` guard does NOT include `os(Android)`.
**Impact:** `@Shared(.fileStorage(url))` will fail to compile on Android. Any TCA app using file-backed shared state will not build.
**Fix:** Add `|| os(Android)` to the guard. Provide Android-compatible `FileStorage.fileSystem` implementation using Foundation `FileManager` (which works on Android) with a no-op or simplified `fileSystemSource` (no DispatchSource on Android).
**Verification:** Compile test with `@Shared(.fileStorage(...))` on Android. Write + read back a Codable value. Test debounced writes (may need to replace `CombineSchedulers` dependency with direct `DispatchQueue.asyncAfter`).

### P2: Infinite Recomposition via Binding Loop
**Risk:** HIGH | **Affects:** TCA-21, SHR-06
**Root cause:** Binding write → state mutation → observation fires → Compose recomposition → view body reads binding → if read triggers another write → infinite loop.
**Protection:** Phase 1's `ObservationRecording.isEnabled` flag suppresses `willSet` during observation recording. `BindingLocal.$isActive` prevents recursive binding dispatch. But the interaction between these two mechanisms and Compose's recomposition scheduler has not been validated end-to-end on Android.
**Verification:** Write a binding mutation test that counts recomposition cycles. Must be exactly 1 per binding write. Test with both `$store.property` (TCA binding) and `Binding($shared)` (Shared binding).

### P3: AppStorage No-Op Subscription Means No External Change Detection
**Risk:** MEDIUM | **Affects:** SHR-01, SHR-12
**Root cause:** On Android, `AppStorageKey.subscribe()` returns a no-op subscription. If another component writes directly to `UserDefaults` (not through `@Shared`), the `@Shared` reference will not update until next `load()`.
**Impact:** Multiple `@Shared(.appStorage("key"))` declarations with the same key will synchronize writes (because they share the same `PersistentReference` via the reference cache), but writes that bypass `@Shared` entirely (e.g., direct `UserDefaults.standard.set()`) will NOT be reflected.
**Verification:** Test that two `@Shared(.appStorage("key"))` references see each other's mutations. Document the limitation that direct UserDefaults writes are not observed.

### P4: Shared DynamicProperty update() Disabled on Android
**Risk:** MEDIUM | **Affects:** SHR-05, SHR-06
**Root cause:** `Shared.update()` is guarded with `#if !os(Android)` — the SwiftUI `@State`-based generation counter is not used on Android. Instead, the observation bridge is responsible for triggering Compose recomposition.
**Impact:** If the observation bridge does not correctly observe `@Shared` mutations (e.g., because `@Shared` uses its own `PassthroughRelay` publisher rather than going through the bridge registrar), views may not update.
**Verification:** Verify that `@Shared` mutations in a view body cause Compose recomposition. The test must run in a view hierarchy (or simulate one via observation bridge hooks).

### P5: FileStorage DispatchSource Dependency
**Risk:** MEDIUM | **Affects:** SHR-02
**Root cause:** `FileStorage.fileSystem` uses `DispatchSource.makeFileSystemObjectSource()` for monitoring file changes. This requires `open()` file descriptors and GCD dispatch sources. While libdispatch is available in Fuse mode, DispatchSource file system monitoring may not be fully functional on Android.
**Impact:** If `DispatchSource` file monitoring fails, external file changes (from another process) will not be observed. For TCA usage (where `@Shared` is the sole writer), this is acceptable — same as appStorage's no-op approach.
**Fix:** Use a no-op file system source on Android, similar to `FileStorage.inMemory`'s approach. Write + read via Foundation `FileManager` (which works). Skip the DispatchSource monitoring.

### P6: CombineSchedulers Dependency in FileStorage
**Risk:** LOW | **Affects:** SHR-02 (only FileStorage.inMemory variant)
**Root cause:** `FileStorage.inMemory` uses `AnySchedulerOf<DispatchQueue>` from `combine-schedulers` for debounced writes. This is already validated (Phase 3 stack).
**Verification:** Test `FileStorage.inMemory` with debounced writes on Android.

### P7: Store.case Enum Switching Relies on EnumMetadata
**Risk:** LOW (downgraded from Phase 3 research) | **Affects:** TCA-25
**Root cause:** `switch store.case { }` relies on `@Reducer enum` macro synthesis + `@CasePathable` enum metadata + `EnumMetadata.tag(of:)`. Phase 3 research confirmed `EnumMetadata.tag(of:)` uses the same ABI as CaseKeyPath extraction (validated Phase 2 with 9 tests).
**Verification:** Test enum case switching with a simple two-case `@Reducer enum`. Verify correct case renders.

### P8: ViewActionSending send(_:animation:) Unavailable on Android
**Risk:** LOW | **Affects:** TCA-31
**Root cause:** `send(_:animation:)` and `send(_:transaction:)` are guarded with `#if !os(Android)`. Only the base `send(_:)` is available.
**Impact:** Views using animation-parameterized `send` calls need `#if !os(Android)` guards. This is expected and documented.
**Verification:** Verify base `send(_:)` dispatches correctly. Document animation API unavailability.

---

## Code Examples

### @ObservableState with BindableAction (TCA-17, TCA-19, TCA-20, TCA-21)

```swift
@Reducer
struct BindingFeature {
  @ObservableState
  struct State: Equatable {
    var text: String = ""
    var isOn: Bool = false
    @ObservationStateIgnored var ignored: Int = 0  // TCA-18
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
  }

  var body: some ReducerOf<Self> {
    BindingReducer()
  }
}

// View usage:
struct BindingView: View {
  @Bindable var store: StoreOf<BindingFeature>

  var body: some View {
    TextField("Text", text: $store.text)     // TCA-21
    Toggle("Toggle", isOn: $store.isOn)      // TCA-21
  }
}
```

### .sending() Binding Projection (TCA-22)

```swift
@Reducer
struct SendingFeature {
  @ObservableState
  struct State: Equatable {
    var count: Int = 0
  }

  enum Action {
    case setCount(Int)
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .setCount(let value):
        state.count = value
        return .none
      }
    }
  }
}

// View usage:
struct SendingView: View {
  @Bindable var store: StoreOf<SendingFeature>

  var body: some View {
    Stepper("\(store.count)", value: $store.count.sending(\.setCount))
  }
}
```

### ForEach Scoping (TCA-23)

```swift
// In view:
ForEach(store.scope(state: \.rows, action: \.rows)) { childStore in
  ChildView(store: childStore)
}
```

### Optional Scoping (TCA-24)

```swift
if let childStore = store.scope(state: \.child, action: \.child) {
  ChildView(store: childStore)
}
```

### Enum Case Switching (TCA-25)

```swift
switch store.case {
case .featureA(let store):
  FeatureAView(store: store)
case .featureB(let store):
  FeatureBView(store: store)
}
```

### @Shared AppStorage (SHR-01)

```swift
@Shared(.appStorage("username")) var username: String = "default"

// Mutate:
$username.withLock { $0 = "newValue" }

// Binding:
TextField("Name", text: Binding($username))
```

### @Shared FileStorage (SHR-02)

```swift
@Shared(.fileStorage(.documentsDirectory.appending(component: "settings.json")))
var settings = Settings()
```

### @Shared InMemory (SHR-03)

```swift
@Shared(.inMemory("sessionToken")) var token: String = ""
```

### Observations Async Sequence (SHR-09)

```swift
@Shared(.appStorage("count")) var count: Int = 0

for await count in $count {
  print("Count changed to \(count)")
}
```

### $shared.publisher (SHR-10)

```swift
@Shared(.appStorage("count")) var count: Int = 0

$count.publisher
  .sink { print("Count: \($0)") }
```

### Custom SharedKey (SHR-14)

```swift
struct MyCustomKey<Value: Codable & Sendable>: SharedKey {
  let key: String
  var id: String { key }

  func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
    // Custom load logic
    continuation.resumeReturningInitialValue()
  }

  func subscribe(context: LoadContext<Value>, subscriber: SharedSubscriber<Value>) -> SharedSubscription {
    SharedSubscription {}
  }

  func save(_ value: Value, context: SaveContext, continuation: SaveContinuation) {
    // Custom save logic
    continuation.resume()
  }
}
```

### onChange Reducer (TCA-29)

```swift
BindingReducer()
  .onChange(of: \.isHapticFeedbackEnabled) { oldValue, newValue in
    Reduce { state, action in
      .run { _ in await hapticEngine.update(enabled: newValue) }
    }
  }
```

### _printChanges (TCA-30)

```swift
var body: some ReducerOf<Self> {
  Reduce { state, action in /* ... */ }
    ._printChanges()  // Outputs state diffs to console (logcat on Android)
}
```

### @ViewAction (TCA-31)

```swift
@ViewAction(for: Feature.self)
struct FeatureView: View {
  let store: StoreOf<Feature>

  var body: some View {
    Button("Tap") { send(.buttonTapped) }  // Synthesized send()
  }
}
```

### Test Pattern for Phase 4

```swift
// Binding test (non-UI, using Store directly)
@MainActor
func testBindingMutation() async {
  let store = Store(initialState: BindingFeature.State()) {
    BindingFeature()
  }
  store.text = "hello"  // Uses dynamic member subscript setter → sends BindingAction
  XCTAssertEqual(store.withState(\.text), "hello")
}

// @Shared appStorage test
@MainActor
func testAppStorageRoundTrip() async {
  @Shared(.appStorage("testKey")) var value: String = "default"
  $value.withLock { $0 = "updated" }
  XCTAssertEqual(value, "updated")
}

// Cross-feature @Shared synchronization test
@MainActor
func testSharedSynchronization() async {
  @Shared(.inMemory("counter")) var counter1: Int = 0
  @Shared(.inMemory("counter")) var counter2: Int = 0
  $counter1.withLock { $0 = 42 }
  XCTAssertEqual(counter2, 42)  // Must see counter1's mutation
}
```

---

## FileStorage Android Implementation Strategy

### Recommended Approach

Modify `FileStorageKey.swift` to include Android:

```swift
// Change guard from:
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)
// To:
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit) || os(Android)
```

Provide Android-specific `FileStorage.fileSystem`:

```swift
#if os(Android)
public static let fileSystem = Self(
  id: AnyHashableSendable(DispatchQueue.main),
  async: { DispatchQueue.main.async(execute: $0) },
  asyncAfter: { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) },
  attributesOfItemAtPath: { try FileManager.default.attributesOfItem(atPath: $0) },
  createDirectory: {
    try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: $1)
  },
  fileExists: { FileManager.default.fileExists(atPath: $0.path) },
  fileSystemSource: { _, _, _ in
    // No DispatchSource file monitoring on Android — return no-op
    SharedSubscription {}
  },
  load: { url in try Data(contentsOf: url) },
  save: { data, url in try data.write(to: url, options: .atomic) }
)
#else
// Existing Darwin implementation
#endif
```

This preserves all read/write functionality. Only file system change monitoring is a no-op — acceptable because TCA's `@Shared` is the sole writer, so external change notification is not needed.

**CombineSchedulers dependency:** The `FileStorage.inMemory` variant uses `AnySchedulerOf<DispatchQueue>` which is available on Android (validated Phase 3). The `import CombineSchedulers` at the top of the file needs to be available on Android — verify it's not guarded out.

---

## Phase 2/3 Solved — Do NOT Re-Investigate

1. **CasePaths + EnumMetadata ABI on Android**: Works. 9 tests validated. `tag(of:)` uses same ABI (Phase 3 confirmed).
2. **IdentifiedCollections**: Pure Swift, zero changes. All 6 API requirements verified.
3. **CustomDump + diff**: Works on Android. 12 tests.
4. **IssueReporting + isTesting**: Three-layer detection fix validated.
5. **PerceptionRegistrar**: Thin passthrough on Android. Safe.
6. **OpenCombine compatibility**: Validated in Phase 3 (merge, concatenate, cancellation).
7. **@MainActor on Android**: Fuse mode uses real Swift runtime + native libdispatch. Confirmed safe.
8. **Locking primitives**: NSRecursiveLock, Mutex, LockIsolated all work on Android.
9. **Store, Reducer, Effect, Dependencies**: All validated Phase 3 — 39 tests passing.

---

## Phase 4 Boundary Summary

**Must work when Phase 4 is complete:**
- `@ObservableState` struct property mutations propagate to views via observation bridge on Android
- `@ObservationStateIgnored` suppresses tracking on Android
- `$store.property` binding projection reads/writes state through the store on Android
- `$store.property.sending(\.action)` derives a binding that sends a specific action on Android
- `BindingReducer()` applies binding mutations to state on Android
- `ForEach` with `store.scope(state:action:)` renders list of child stores with stable identity on Android
- Optional scoping creates/destroys child stores on nil transitions on Android
- `switch store.case { }` enum switching renders correct case on Android
- `Reducer.onChange(of:)` runs nested reducer when derived value changes on Android
- `_printChanges()` logs state diffs to Android logcat
- `@ViewAction` macro `send()` dispatches correctly on Android
- `@Shared(.appStorage("key"))` persists and restores all supported value types on Android
- `@Shared(.fileStorage(url))` persists and restores Codable state on Android
- `@Shared(.inMemory("key"))` shares state in-memory across features on Android
- `$shared` binding creates two-way binding driving Compose recomposition on Android
- `$parent.child` keypath projection derives child Shared on Android
- `Shared($optional)` unwrapping returns `Shared<T>` when non-nil on Android
- `Observations { }` async sequence emits on every `@Shared` mutation on Android
- `$shared.publisher` exposes working Combine/OpenCombine publisher on Android
- `@ObservationIgnored @Shared` prevents double-notification on Android
- Multiple `@Shared` declarations with same backing store synchronize updates on Android
- Child component mutation of `@Shared` parent state is visible in parent on Android
- Custom `SharedKey` implementation compiles and runs on Android

**Explicitly NOT in scope:**
- Navigation, presentation, alerts, sheets (Phase 5)
- TestStore infrastructure (Phase 7)
- Database/StructuredQueries (Phase 6)
- Animation/transaction parameters on bindings (not available on Android)

---

## Critical Action Items for Planning

Ordered by severity:

1. **CRITICAL: Enable FileStorageKey on Android** (SHR-02). Add `|| os(Android)` to the compilation guard. Implement Android-specific `FileStorage.fileSystem` with no-op file system monitoring. Without this, `@Shared(.fileStorage(...))` does not exist on Android.

2. **HIGH: Infinite recomposition regression test** (TCA-21, SHR-06). End-to-end binding mutation test counting recomposition cycles. Must be exactly 1 per mutation. Critical because this was the Phase 1 bug that Phase 4 bindings could reintroduce at a different layer.

3. **HIGH: AppStorage value type exhaustive validation** (SHR-01). Test every type that `AppStorageKey` supports (Bool, Int, Double, String, Data, URL, Date, [String], optionals, RawRepresentable, Codable) through Skip's UserDefaults→SharedPreferences bridge.

4. **MEDIUM: Combine audit in FileStorageKey** (SHR-02). FileStorageKey imports `CombineSchedulers` unconditionally. Verify this import resolves on Android. The debounce-based write coalescing in `save()` uses `DispatchWorkItem` (not Combine directly), so it should work, but the import must not break compilation.

5. **MEDIUM: Verify @Shared triggers Compose recomposition** (SHR-06). Since `Shared.update()` is disabled on Android, verify that `@Shared` mutations still trigger view updates through the observation bridge pathway.

6. **LOW: Custom SharedKey validation** (SHR-14). Write a minimal custom `SharedKey` implementation and verify it compiles and runs on Android.

---

## Deep Dive Findings (Round 2)

Six parallel deep-dive agents examined 80+ source files. Full reports in `research/` subdirectory. Key findings that update or override the initial research:

### DD-1: FileStorage Android Enablement (research/filestorage-android.md)

**Guard locations:** Single outer guard on line 1 of `FileStorageKey.swift` gates the entire 432-line file. Same guard on `FileStorageTests.swift`.

**DispatchSource blocker is worse than expected:** The `FileStorage` struct's field type signature references `DispatchSource.FileSystemEvent` directly (line 323-325), meaning the struct definition itself won't compile on Android — not just the file monitoring implementation. **Fix requires abstracting the type** with a cross-platform `FileSystemEvent` type alias (real type on Darwin, polyfill `OptionSet` on Android).

**URL.documentsDirectory missing on Android:** Skip-android-bridge polyfills `URL.applicationSupportDirectory` and `URL.cachesDirectory` but is **missing** `URL.documentsDirectory`. A polyfill needs to be added.

**Debounced writes use DispatchWorkItem, not Combine** — no Combine blockers for write coalescing.

**6 prescriptive changes identified** — see full report for exact file/line references.

### DD-2: Binding Recomposition Loop Risk — DOWNGRADED to LOW (research/binding-recomposition.md)

**8 layered protections identified** preventing infinite loops:
1. `BindingLocal.isActive` task-local flag
2. `RootCore.isSending` reentrancy guard (buffers recursive sends)
3. `ObservationRecording.isEnabled` suppresses synchronous willSet during recording
4. `DispatchQueue.main.async` breaks the synchronous chain in onChange handler
5. Compose frame batching (async recomposition scheduling)
6. `isIdentityEqual` value comparison in ObservationStateRegistrar
7. Thread-local recording stack isolation
8. Read-only access path (store property reads don't trigger mutations)

**Key insight: Double async gap.** The cycle is broken by two asynchronous boundaries (Swift's `DispatchQueue.main.async` + Compose's frame-based scheduling). By the time view body re-evaluates, all synchronous guards have reset.

**Still needs regression test** but risk is architectural, not practical.

### DD-3: AppStorage Type Bridging — BROKEN for [String] (research/appstorage-bridging.md)

**Critical finding: `[String]` array storage is broken on Android.** Skip Foundation's `set(_ value: Any?, forKey:)` has no branch for arrays — values are silently discarded. Both `array(forKey:)` and `stringArray(forKey:)` are `@available(*, unavailable)`.

**3-layer bridge chain:** `AppStorageKey` → `AndroidUserDefaults` (Swift) → `UserDefaultsAccess` (Kotlin bridge) → `skip.foundation.UserDefaults` (SharedPreferences wrapper).

**Skip uses unrepresentable type tagging** — companion keys (`__unrepresentable__:<key>`) for types SharedPreferences doesn't natively support (Double stored as Long raw bits, Date as ISO 8601 string, Data as base64).

**Type compatibility matrix (22 types):**
- **Working:** Bool, Int, Double, String, Data, URL, Date, optionals of each, RawRepresentable enums, Codable types
- **Broken:** `[String]`, `[String]?` — silently discarded
- **Risk:** Date loses sub-second precision (ISO 8601 round-trip), Double relies on type tag integrity

**6 existing `#if os(Android)` guards** already present — all correctly placed.

### DD-4: @Shared Recomposition — CRITICAL GAP FOUND (research/shared-recomposition.md)

**Most important finding of all deep dives:** `@Shared` uses the **stdlib `ObservationRegistrar`**, NOT the bridge's `SkipAndroidBridge.Observation.ObservationRegistrar` wrapper.

**Root cause chain:**
- `_BoxReference` and `_PersistentReference` use `PerceptionRegistrar`
- `PerceptionRegistrar` checks `canImport(Observation)` (true on Android) → uses stdlib `ObservationRegistrar`
- `#available(iOS 17, ...)` resolves to true on Android (no platform match)
- `isObservationBeta` is false (only checks iOS/tvOS/watchOS)
- Result: stdlib `ObservationRegistrar()` is used, **bypassing bridge JNI hooks entirely**

**Impact:** The bridge's `BridgeObservationSupport.access()` and `ObservationRecording.recordAccess()` are never called for `@Shared` property accesses. The bridge's record-replay system is blind to `@Shared`.

**However:** This may still work if Skip's Compose integration handles stdlib `withObservationTracking` directly (which it likely does in Fuse mode, since the bridge IS the observation tracking mechanism). **Empirical verification required as first Phase 4 action.**

**Both notification channels fire on mutation:** ObservationRegistrar path (willSet/didSet) AND PassthroughRelay publisher path. Cross-reference caching confirmed — two `@Shared(.appStorage("key"))` share the same `_PersistentReference`.

**Double-notification prevention (SHR-11) works correctly:** `@ObservationIgnored` prevents the model's registrar from tracking; only `@Shared`'s own registrar fires.

### DD-5: OpenCombine Audit — PASS (research/opencombine-audit.md)

**All Combine usage in swift-sharing is fully Android-compatible.** Every file uses the standard dual-path pattern (`#if canImport(Combine)` / `#else import OpenCombineShim`).

**PassthroughRelay dual branches are byte-for-byte identical** except for module-qualified type names.

**SharedPublisher uses `Just`, `flatMap`, `prepend`** — all in OpenCombine.

**`Observations` async sequence** goes through `.publisher.values` which works in OpenCombine 0.14+ (already the minimum version).

**CombineSchedulers supports Android** via OpenCombineShim with explicit `.android` platform condition.

**No blockers found.**

### DD-6: Scoping Lifecycle — ALL PLATFORM-AGNOSTIC (research/scoping-lifecycle.md)

**All Store scoping lifecycle code has zero platform guards.** No new `#if os(Android)` needed.

**ForEach:** Child stores cached by element ID (not position) via `ScopeID` derived from `\.[id: elementID]`. Reordering preserves all child stores. `Thread.isMainThread` + `MainActor._assumeIsolated` both safe on Android.

**Optional:** nil → non-nil creates `IfLetCore` + child store cached in `children[id]`. non-nil → nil eagerly removes child + 300ms deferred cleanup fallback. Low memory leak risk.

**Enum case:** Delegates to macro-generated `StateReducer.scope()` which reuses optional scoping. `EnumMetadata.tag(of:)` works via ABI (validated Phase 2). `_PresentationReducer` cancels effects on case change.

**Teardown:** Three reducers handle effect cancellation — `_IfLetReducer` (optional), `_ForEachReducer` (collection), `_PresentationReducer` (enum/presentation). All use `_cancellationCancellables` with `LockIsolated`. Zero platform guards.

---

## Revised Critical Action Items (Post-Deep-Dive)

Ordered by severity, incorporating deep dive findings:

1. **CRITICAL: Verify @Shared observation path on Android** (NEW from DD-4). `@Shared` bypasses the bridge registrar and uses stdlib `ObservationRegistrar`. Must empirically verify that Skip's Compose integration handles stdlib `withObservationTracking` for recomposition. If not, `PerceptionRegistrar` needs an Android-specific path to use the bridge registrar. **This is the Phase 4 gating question.**

2. **CRITICAL: Enable FileStorageKey on Android** (SHR-02, refined by DD-1). Six changes needed:
   - Add `|| os(Android)` to outer guard (FileStorageKey.swift line 1)
   - Abstract `DispatchSource.FileSystemEvent` type (struct field blocker)
   - Provide Android `FileStorage.fileSystem` with no-op `fileSystemSource`
   - Add `URL.documentsDirectory` polyfill to skip-android-bridge
   - Update FileStorageTests.swift guard
   - Guard DispatchSource-dependent live tests with `#if !os(Android)`

3. **HIGH: Fix [String] array storage on Android** (NEW from DD-3). Skip Foundation silently discards arrays in `UserDefaults.set(_:forKey:)`. Either:
   - Fix in Skip Foundation (preferred but external dependency)
   - Work around by encoding arrays as JSON Data in AppStorageKey on Android
   - Document as known limitation and exclude `[String]` from Android support

4. **HIGH: Infinite recomposition regression test** (TCA-21, SHR-06, downgraded from DD-2). 8 protection layers make loops architecturally unlikely, but still needs end-to-end validation test counting recomposition cycles.

5. **MEDIUM: AppStorage exhaustive type validation** (SHR-01, refined by DD-3). Test round-trips for all 22 types in the compatibility matrix. Pay special attention to Date sub-second precision loss and Double type tag integrity.

6. **MEDIUM: Combine audit resolved** (DD-5). No action needed — all Combine usage is Android-compatible via OpenCombine. Remove from action items.

7. **LOW: Scoping lifecycle validation** (TCA-23, TCA-24, TCA-25, from DD-6). All code is platform-agnostic. Standard behavioral tests sufficient — no code changes expected.

8. **LOW: Custom SharedKey validation** (SHR-14). Pure Swift protocol, no platform concerns.

---

*Research completed: 2026-02-22 (initial) + deep dives (6 parallel agents, 80+ files)*
*Depth: Source-level audit of all Phase 4 fork code (80+ files examined across 6 deep dives)*
*Confidence: High for bindings/scoping/OpenCombine, Medium for fileStorage/appStorage (need code changes), Unknown for @Shared recomposition (needs empirical verification)*
*Deep dive reports: `.planning/phases/04-tca-state/research/`*
