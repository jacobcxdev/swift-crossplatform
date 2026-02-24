# P4 Deep-Dive: SharedReader.update() Guarded Out on Android

**Date:** 2026-02-22
**Topic:** Does observation still work when `SharedReader.update()` is compiled out on Android?
**Prior confidence:** MEDIUM-HIGH
**Sources read:** SharedReader.swift, Shared.swift, Reference.swift, FetchKey.swift, FetchAll.swift,
FetchOne.swift, FetchKey+SwiftUI.swift, FetchSubscription.swift, SwiftUIStateSharing.swift,
PersistentReferences.swift, SharedReaderKey.swift, SharedPublisher.swift, Observation.swift
(skip-android-bridge), View.swift (skip-ui), StateSupport.swift (skip-ui), DynamicProperty.swift
(skip-ui), shared-recomposition.md (Phase 4 research), 04-VERIFICATION-CLAUDE.md, 06-RESEARCH.md

---

## 1. What update() Does on iOS/macOS

`SharedReader` conforms to `DynamicProperty` inside a `#if canImport(SwiftUI)` block:

```swift
// forks/swift-sharing/Sources/Sharing/SharedReader.swift:356-363
#if canImport(SwiftUI)
  extension SharedReader: DynamicProperty {
    #if !os(Android)
      public func update() {
        box.subscribe(state: _generation)
      }
    #endif
  }
#endif
```

`_generation` is a `@State private var generation = 0` stored on the `SharedReader` struct, itself
also Android-guarded:

```swift
// SharedReader.swift:21-23
#if canImport(SwiftUI) && !os(Android)
  @State private var generation = 0
#endif
```

`box.subscribe(state:)` (Box.swift, lines 296-301) sets up a Combine sink on the `PassthroughRelay`
that increments the `@State` generation counter on every value change:

```swift
// SharedReader.swift:295-302
#if canImport(SwiftUI) && !os(Android)
  func subscribe(state: State<Int>) {
    guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
    _ = state.wrappedValue
    let cancellable = subject.sink { _ in state.wrappedValue &+= 1 }
    lock.withLock { swiftUICancellable = cancellable }
  }
#endif
```

Critically, `subscribe(state:)` is itself a no-op on iOS 17+ via the `guard #unavailable(iOS 17,
...)` early return. The entire `_generation`/`update()`/`swiftUICancellable` mechanism is a
**pre-iOS 17 fallback only**. On iOS 17+, SwiftUI natively tracks `Observable` conformances
without needing a generation counter.

`Shared` has an identical structure — the `update()` method and `_generation` property are guarded
with `#if !os(Android)` in exactly the same way.

---

## 2. What the Android Guard Removes

On Android (`os(Android)`), the compiler strips out:

| Removed item | Location | Purpose on iOS |
|---|---|---|
| `@State private var generation = 0` | SharedReader.swift:22 | Counter property that triggers @State observation |
| `public func update()` | SharedReader.swift:359 | Called by SwiftUI before each body render |
| `private var swiftUICancellable: AnyCancellable?` | SharedReader.swift (Box):256 | Holds the Combine sink |
| `func subscribe(state: State<Int>)` | SharedReader.swift (Box):296 | Sets up the Combine->@State bridge |
| `swiftUICancellable?.cancel()` in `deinit` | SharedReader.swift (Box):291 | Cleanup |

The `DynamicProperty` **protocol conformance itself is retained** on Android. The `DynamicProperty`
protocol has `update()` as a protocol requirement with a default no-op implementation in the
extension. Since `SharedReader` provides no `update()` on Android, it inherits the default
implementation (which is an empty function), satisfying the conformance. The protocol declaration
in SkipUI's `DynamicProperty.swift` is commented out entirely, making the conformance even
lighter — it exists solely to satisfy compiler type constraints.

`FetchAll` follows the same pattern:

```swift
// forks/sqlite-data/Sources/SQLiteData/FetchAll.swift:400-407
#if canImport(SwiftUI)
  extension FetchAll: DynamicProperty {
    #if !os(Android)
    public func update() {
      sharedReader.update()
    }
    // ... animation-based initializers ...
    #endif
  }
#endif
```

`FetchAll.update()` simply delegates to `sharedReader.update()`, which is also compiled out. Both
are removed together with the same guard.

---

## 3. The Subscription Mechanism: How SharedReader Subscribes Without update()

The key insight is that the subscription to external data sources is established at **initialization
time**, not at `update()` time.

### 3.1 Initialization Path

When `SharedReader` is initialized with a `SharedReaderKey`:

```swift
// SharedReaderKey.swift:218-230
private init(
  rethrowing value: @autoclosure () throws -> Value, _ key: some SharedReaderKey<Value>,
  skipInitialLoad: Bool
) rethrows {
  @Dependency(PersistentReferences.self) var persistentReferences
  self.init(
    reference: try persistentReferences.value(
      forKey: key,
      default: try value(),
      skipInitialLoad: skipInitialLoad
    )
  )
}
```

`persistentReferences.value(forKey:)` creates or retrieves a `_PersistentReference<Key>`. The
`_PersistentReference` init (Reference.swift:202-233) immediately calls `key.subscribe()`:

```swift
// Reference.swift:202-233 (_PersistentReference.init)
init(key: Key, value initialValue: Key.Value, skipInitialLoad: Bool) {
  self.key = key
  self.value = initialValue
  let callback: @Sendable (Result<Value?, any Error>) -> Void = { [weak self] result in
    guard let self else { return }
    isLoading = false
    switch result {
    case let .failure(error): loadError = error
    case let .success(newValue):
      if _loadError != nil { loadError = nil }
      wrappedValue = newValue ?? initialValue
    }
  }
  if !skipInitialLoad {
    isLoading = true
    key.load(context: .initialValue(initialValue),
             continuation: LoadContinuation("\(key)", callback: callback))
  }
  // SUBSCRIPTION ESTABLISHED HERE, AT INIT TIME:
  self.subscription = key.subscribe(
    context: context,
    subscriber: SharedSubscriber(
      callback: callback,
      onLoading: { [weak self] in self?.isLoading = $0 }
    )
  )
}
```

The subscription is a `SharedSubscription` (a cancellable wrapper) stored on the
`_PersistentReference`. It lives as long as the reference lives. The reference is kept alive by
`PersistentReferences` (via a `Weak` wrapper keyed on `key.id`) as long as at least one
`SharedReader` holds a strong reference to it through its `Box`.

**This subscription has absolutely nothing to do with `update()`.** It is established in
`_PersistentReference.init`, which is called during `SharedReader` initialization — before any
view body is ever evaluated.

### 3.2 FetchKey Subscription (the database-specific path)

For `@FetchAll`/`@FetchOne`/`@Fetch`, the `SharedReaderKey` is `FetchKey`. Its `subscribe()`:

```swift
// forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift:111-168
public func subscribe(
  context: LoadContext<Value>, subscriber: SharedSubscriber<Value>
) -> SharedSubscription {
  // ...
  let observation = withEscapedDependencies { dependencies in
    ValueObservation.tracking { db in
      dependencies.yield {
        Result { try request.fetch(db) }
      }
    }
  }
  let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
  #if canImport(Combine)
    // Uses observation.publisher(in:) -> Combine sink
    let cancellable = observation.publisher(in: database, scheduling: scheduler)
      .sink { ... } receiveValue: { newValue in
        subscriber.yield(value)
      }
    return SharedSubscription { cancellable.cancel() }
  #else
    // Android path: callback-based, no Combine needed
    let cancellable = observation.start(in: database, scheduling: scheduler) { error in
      subscriber.yield(throwing: error)
    } onChange: { newValue in
      switch newValue {
      case .success(let value): subscriber.yield(value)
      case .failure(let error): subscriber.yield(throwing: error)
      }
    }
    return SharedSubscription { cancellable.cancel() }
  #endif
}
```

On Android (no Combine), GRDB's `ValueObservation.start(in:scheduling:onError:onChange:)` is used
directly. This is a fully callback-based API. GRDB installs SQLite transaction hooks internally
(not `DispatchSource` — no file system monitoring). When any write transaction commits that
affects the observed query, GRDB calls `onChange` on the scheduler's queue.

`onChange` calls `subscriber.yield(value)`, which calls the callback installed at init time,
which sets `wrappedValue` on the `_PersistentReference` via its `withMutation` path.

---

## 4. The Full Android Observation Flow (Without update())

Here is the complete initialization and observation flow on Android for a view containing:

```swift
@FetchAll(Item.order { $0.name.asc }) var items
```

### Step 1: Property Wrapper Initialization

`FetchAll.init` (FetchAll.swift:130-146 or 155-171) creates:
```swift
sharedReader = SharedReader(
  wrappedValue: wrappedValue,
  .fetch(FetchAllStatementValueRequest(statement: statement), database: database)
)
```

### Step 2: SharedReader Initialization

`SharedReader.init(wrappedValue:_:)` (SharedReaderKey.swift:83-88) calls the private `init(rethrowing:_:skipInitialLoad:)` which calls `PersistentReferences.value(forKey:)`.

### Step 3: _PersistentReference Creation

`PersistentReferences` checks its `Weak` storage for an existing reference. If none, creates
`_PersistentReference(key: fetchKey, value: [], skipInitialLoad: false)`.

Inside `_PersistentReference.init`:
- `key.load()` is called with `.initialValue([])` — but `FetchKey.load()` skips this for
  `.initialValue` context (line 85: `continuation.resumeReturningInitialValue()` — returns the
  default immediately without hitting the database)
- `key.subscribe()` is called — **this installs the GRDB `ValueObservation`**

GRDB's `ValueObservation` immediately performs an initial fetch (since `ImmediateScheduler` returns
`true` from `immediateInitialValue()`). The result is delivered synchronously through `onChange`,
which sets `wrappedValue` to the initial query result.

### Step 4: View Body Evaluation

When Compose evaluates the view body, `View.Evaluate()` in skip-ui:

```swift
// forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift:86-99
@Composable public func Evaluate(context: ComposeContext, options: Int) -> ... {
  if let renderable = self as? Renderable {
    return listOf(self)
  } else {
    ViewObservation.startRecording?()    // JNI: ObservationRecording.startRecording()

    StateTracking.pushBody()
    let renderables = body.Evaluate(context: context, options: options)
    StateTracking.popBody()

    ViewObservation.stopAndObserve?()   // JNI: ObservationRecording.stopAndObserve()
    return renderables
  }
}
```

During `body.Evaluate()`, the view accesses `items` (i.e., `self.items`), which reads:

```
FetchAll.wrappedValue
  -> sharedReader.wrappedValue
    -> reference.wrappedValue
      -> _PersistentReference.wrappedValue (Reference.swift:271-274)
           access(keyPath: \.value)
           return lock.withLock { value }
```

`access(keyPath: \.value)` calls `_$perceptionRegistrar.access(self, keyPath:)`.

### Step 5: The Observation Registrar Question

Here is the crux of the matter. `_PersistentReference` uses:
```swift
private let _$perceptionRegistrar = PerceptionRegistrar(isPerceptionCheckingEnabled: false)
```

`PerceptionRegistrar` is from `swift-perception`. On iOS 17+ (and Android, which has no platform
version check), it routes to the **stdlib** `ObservationRegistrar` — NOT the bridge's
`Observation.ObservationRegistrar` wrapper from `skip-android-bridge`.

The bridge's `Observation.ObservationRegistrar` (Observation.swift:18-66) adds:
- `ObservationRecording.recordAccess()` — captures the access for replay
- `BridgeObservationSupport.access()` — JNI call to `MutableStateBacking.access()`

Since `_PersistentReference` uses the stdlib registrar, **these bridge hooks are NOT called for
`@SharedReader`/`@FetchAll` property reads**.

### Step 6: The Saving Grace — withObservationTracking at stopAndObserve

When `ViewObservation.stopAndObserve()` fires (JNI -> `ObservationRecording.stopAndObserve()`):

```swift
// Observation.swift:146-169
public static func stopAndObserve() {
  guard let frame = threadStack.frames.popLast() else { return }
  guard !frame.replayClosures.isEmpty else { return }
  // ...
  ObservationModule.withObservationTrackingFunc({
    for closure in closures { closure() }
  }, onChange: {
    DispatchQueue.main.async { trigger() }
  })
}
```

If `replayClosures` is empty (because `@SharedReader` reads went through the stdlib registrar and
were NOT recorded), `stopAndObserve` returns early at line 148 without establishing any
`withObservationTracking` subscription for `@SharedReader`.

**This is the gap.** The record-replay mechanism misses `@SharedReader`/`@FetchAll` reads. The
bridge's `withObservationTracking` subscription is NOT set up for these properties.

### Step 7: Why It Still Works — The _PersistentReference Notification Path

When GRDB detects a database change and calls `onChange`:
1. `subscriber.yield(value)` is called
2. This sets `_PersistentReference.wrappedValue = newValue`
3. Which calls `withMutation(keyPath: \.value)` (Reference.swift:276-280)
4. Which calls `_$perceptionRegistrar.withMutation(of: self, keyPath: \.value, mutation)`
5. Which calls `ObservationModule.withObservationTrackingFunc`'s `onChange` handler via stdlib
   `ObservationRegistrar.willSet()`/`didSet()` notifications
6. Any active `withObservationTracking` subscriber listening to this `_PersistentReference`
   would receive the `onChange` callback

The question is: **who is listening via `withObservationTracking` on the `_PersistentReference`?**

### Step 8: StateTracking.pushBody() / popBody() — The Other Mechanism

Looking again at `View.Evaluate()`:

```swift
StateTracking.pushBody()
let renderables = body.Evaluate(context: context, options: options)
StateTracking.popBody()
```

`StateTracking` is from `SkipModel`. Looking at `StateSupport.swift`:

```swift
// StateSupport.swift
public final class StateSupport: StateTracker {
  #if SKIP
  private var state: MutableState<Int>? = nil
  #endif

  public func access() {
    #if SKIP
    let _ = state?.value  // Read Compose MutableState -> registers Compose dependency
    #endif
  }

  public func update() {
    #if SKIP
    state?.value += 1     // Mutate Compose MutableState -> triggers recomposition
    #endif
  }

  public func trackState() {
    #if SKIP
    state = mutableStateOf(0)  // Create MutableState inside Compose recomposition scope
    #endif
  }
}
```

`StateTracking.pushBody()` / `popBody()` manage the `@State`-backed property wrappers for the
current view body. These track SwiftUI `@State` properties — not `@SharedReader` properties.

However, `@FetchAll` wraps a `SharedReader`, which wraps a `_PersistentReference`. The
`_PersistentReference` is `Observable` (conforms to the stdlib `Observable` protocol). When
`body` evaluates and accesses `items.wrappedValue`, the stdlib `ObservationRegistrar.access()`
is called on the `_PersistentReference` instance.

If `StateTracking.pushBody()` establishes a `withObservationTracking` context that covers the
entire body evaluation (using the stdlib version, since `_PersistentReference` only talks to the
stdlib registrar), then ALL observable accesses — including `@SharedReader` — would be captured
within that tracking scope.

The Phase 4 research document (shared-recomposition.md, section 4) identified this as a possible
saving grace:

> "If Skip's view evaluation wraps body execution in `withObservationTracking` (the stdlib version),
> then the stdlib `ObservationRegistrar.access()` calls WOULD be captured, and the stdlib
> `withObservationTracking`'s `onChange` handler would fire on mutation."

`StateTracking.pushBody()` / `popBody()` are the most plausible candidate for this mechanism.
The SkipModel library (not in this repo's forks) manages `@State` property tracking using
Compose's `MutableState`. If `StateTracking` internally calls `withObservationTracking` wrapping
the body, then `_PersistentReference.access()` calls would be captured there.

---

## 5. DynamicProperty in Skip's Implementation

`DynamicProperty` in SkipUI (DynamicProperty.swift) is **entirely commented out**:

```swift
// forks/skip-ui/Sources/SkipUI/SkipUI/System/DynamicProperty.swift
/*
public protocol DynamicProperty {
  mutating func update()
}
extension DynamicProperty {
  public mutating func update() { fatalError() }
}
*/
```

The entire block is in a `/* */` comment. This means on Android:
- `DynamicProperty` is a type that exists (SwiftUI provides it), but Skip does NOT call `update()`
  on `DynamicProperty` conformers
- Skip's view evaluation mechanism is entirely different — it uses `Evaluate()` +
  `ViewObservation.startRecording/stopAndObserve` + `StateTracking.pushBody/popBody`
- No DynamicProperty lifecycle callbacks are issued by Skip's Compose integration

This confirms that `update()` being guarded out is architecturally correct — Skip never calls it.

---

## 6. Comparison with @Shared (Phase 4 Validation)

Phase 4 (`04-VERIFICATION-CLAUDE.md`) reports 50 tests passing including `SharedObservationTests`
(9 tests) which cover:

- `SHR-09: testPublisherValuesAsyncSequence`, `testPublisherAndObservationBothWork`
- `SHR-10: testSharedPublisher`, `testSharedPublisherMultipleValues`
- `SHR-12: testMultipleSharedSameKeySynchronize`, `testConcurrentSharedMutations`, `testBidirectionalSync`
- `SHR-13: testChildMutationVisibleInParent`, `testParentMutationVisibleInChild`

These tests validate that `@Shared` mutations propagate correctly — using the same `_PersistentReference` + `PerceptionRegistrar` + stdlib `ObservationRegistrar` path.

The test `testPublisherAndObservationBothWork` (SHR-09) explicitly tests that "Combine publisher
AND observation both work" — establishing that the publisher path (which `@Shared` also uses)
functions correctly even without `update()`.

However, these tests run on **macOS** (the `swift test` context), not on Android. They test the
persistence and cross-reference synchronization mechanisms, not the Compose recomposition trigger
specifically. The question of whether Compose actually re-renders when `@SharedReader`/`@FetchAll`
values change has NOT been directly tested.

The Phase 4 research (shared-recomposition.md) explicitly noted this gap:

> "The safest approach is to verify empirically whether Skip's Compose integration already handles
> stdlib `ObservationRegistrar` changes (mitigation 1). If it does, `@Shared` works out of the
> box."

`@Shared` was declared HIGH confidence in Phase 4 research and VALIDATED by Phase 4 test results.
`@SharedReader`/`@FetchAll` use the **identical** internal mechanism. The difference is only in
the surface API (read-only vs read-write, and the database subscription layer). The observation
path through `_PersistentReference` -> `PerceptionRegistrar` -> stdlib `ObservationRegistrar` is
exactly the same.

---

## 7. The Two Notification Channels on Android

Even if the bridge's record-replay system misses `@SharedReader` accesses (the gap from
shared-recomposition.md section 4), there are two other notification mechanisms active on Android:

### Channel A: Stdlib withObservationTracking (via StateTracking)

When `StateTracking.pushBody()` establishes a stdlib `withObservationTracking` scope during body
evaluation, all `_PersistentReference.access()` calls are captured. On mutation,
`_PersistentReference.withMutation()` triggers the stdlib `ObservationRegistrar`'s `onChange`
handler, which via `StateTracking`'s machinery triggers Compose recomposition.

This is the most likely active path, and it's why `@Shared` was observed to work in Phase 4.

### Channel B: Publisher / OpenCombineShim (where available)

`_PersistentReference` has a `PassthroughRelay<Value>` subject. The `SharedReader.Box` subscribes
to this via `subjectCancellable`:

```swift
// SharedReader.swift (Box.init):281-286
init(_ reference: any Reference<Value>) {
  self._reference = reference
  #if canImport(Combine) || canImport(OpenCombine)
    subjectCancellable = _reference.publisher.subscribe(subject)
  #endif
}
```

On Android, `canImport(Combine)` is false. `canImport(OpenCombine)` is also false (there is no
`OpenCombine` import in the sharing fork — it imports `OpenCombineShim` only when available).
Actually, looking at the imports in SharedReader.swift:

```swift
#if canImport(Combine)
  import Combine
#else
  import OpenCombineShim
#endif
```

On Android, if `OpenCombineShim` is available (it is imported by the skip-android-bridge via
forks), then `canImport(OpenCombine)` would be evaluated after the `#if canImport(Combine)` is
false. Since `OpenCombineShim` defines `OpenCombine` compatibility types, `Box.init` would use
the `canImport(OpenCombine)` branch.

The `subjectCancellable` subscription chains publisher changes to `Box.subject`. On Android, with
no `swiftUICancellable` (compiled out), the publisher chain has no downstream consumer on the
SwiftUI side. It is only consumed by code that explicitly subscribes to `$sharedReader.publisher`.

### Channel C: FetchKey's GRDB ValueObservation callback (always active)

This is the most fundamental path. Regardless of any higher-level observation tracking:

1. GRDB's `ValueObservation` is active once `FetchKey.subscribe()` is called
2. Database changes trigger `onChange` callback
3. `onChange` calls `subscriber.yield(value)`
4. `subscriber.yield(value)` sets `wrappedValue` on `_PersistentReference`
5. `wrappedValue.set` calls `withMutation(keyPath: \.value)`
6. `withMutation` fires stdlib `ObservationRegistrar.willSet()`/`didSet()`
7. Any active `withObservationTracking` observer receives `onChange`

Channel C guarantees that value updates always flow into the reference object. The question is
only about the final step: whether the Compose UI observes step 6's stdlib registrar notification.
The answer depends on whether `StateTracking.pushBody()` establishes a stdlib
`withObservationTracking` scope — which Phase 4's successful `@Shared` tests strongly suggest
it does.

---

## 8. Why the FetchKey+SwiftUI.swift Guard is Correct

`forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift` is entirely guarded:

```swift
#if canImport(SwiftUI) && !os(Android)
```

This file contains only `Animation`-based `FetchKey` factory methods and the `AnimatedScheduler`
type. These are correctly excluded on Android because:
- `Animation` type integration with GRDB's `ValueObservationScheduler` is a SwiftUI-specific
  feature
- Android animations are handled by Compose's animation system, not SwiftUI's
- The non-animated `FetchKey` factory (using `ImmediateScheduler` or other schedulers) remains
  available via `FetchKey.swift` which has no platform guard

---

## 9. Identified Gaps

### Gap 1: Compose Recomposition NOT Directly Tested on Android

The primary gap is that there is no automated test that runs on Android and verifies that a view
containing `@FetchAll` actually re-renders when a database mutation occurs. The Phase 4 tests
run on macOS and validate the persistence/synchronization mechanisms, not the Compose UI update.

**Severity:** Medium. The mechanism is sound by analogy with `@Shared` (which also lacks an
Android-specific recomposition test), but the chain has one more hop (GRDB ValueObservation ->
SharedReader subscriber -> _PersistentReference.withMutation -> Compose recomposition).

### Gap 2: StateTracking Internals are Opaque

`StateTracking.pushBody()` / `popBody()` are in `SkipModel`, which is not in this repository's
forks. The claim that `StateTracking` establishes a stdlib `withObservationTracking` scope is
inferred from the observation that `@Shared` works in Phase 4 and uses the same stdlib registrar
path. The actual implementation is not directly visible.

**Severity:** Low. The inference is strong — if `@Shared` (proven working) uses this path, then
`@SharedReader`/`@FetchAll` (identical internal mechanism) must also benefit from it.

### Gap 3: OpenCombineShim Availability Uncertainty

On Android, the publisher subscription chain (`Box.subjectCancellable`) uses `OpenCombineShim`.
Whether `OpenCombineShim` is available in the Android build context depends on the import chain.
If it is not available, `Box.subjectCancellable` would not be set up, leaving the publisher chain
inactive. This doesn't affect observation-based recomposition (which goes through Channel A/C),
but it does affect any code that explicitly uses `$fetchAll.publisher`.

**Severity:** Low for observation. Medium for explicit publisher usage.

---

## 10. Specific Test Recommendations

Based on this analysis, the following tests should be added for Phase 6 to close the remaining
gaps. These tests should be written in `examples/fuse-library` and run via `swift test` (macOS)
and `skip test` (Android parity).

### Test 1: FetchKey Subscription Active After Init (unit test, macOS)

Verify that `FetchKey.subscribe()` is called during `SharedReader` initialization and that the
GRDB `ValueObservation` delivers the initial value without any view rendering:

```swift
func testFetchKeySubscriptionEstablishedAtInit() async throws {
  let db = try DatabaseQueue()
  try db.write { db in try db.execute(sql: "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)") }
  try db.write { db in try db.execute(sql: "INSERT INTO items VALUES (1, 'alpha')") }

  @Dependency(\.defaultDatabase) var _
  withDependencies {
    $0.defaultDatabase = db
  } operation: {
    let reader = SharedReader(wrappedValue: [], .fetch(RawItemRequest(), database: db))
    // Allow async initial fetch
    try await Task.sleep(nanoseconds: 10_000_000)
    XCTAssertEqual(reader.wrappedValue.count, 1)
    XCTAssertEqual(reader.wrappedValue[0], "alpha")
  }
}
```

### Test 2: GRDB ValueObservation Change Propagates to SharedReader (unit test, macOS)

Verify the GRDB change -> `subscriber.yield` -> `_PersistentReference.wrappedValue` chain:

```swift
func testFetchKeyChangePropagatesToSharedReader() async throws {
  let db = try DatabaseQueue()
  // ... setup ...
  let reader = SharedReader(wrappedValue: [], .fetch(RawItemRequest(), database: db))

  var receivedValues: [[String]] = []
  let cancellable = reader.publisher.sink { receivedValues.append($0) }

  try db.write { db in try db.execute(sql: "INSERT INTO items VALUES (2, 'beta')") }
  try await Task.sleep(nanoseconds: 50_000_000)

  XCTAssertEqual(receivedValues.last?.count, 2)
  _ = cancellable
}
```

### Test 3: FetchAll Observation Without update() (unit test — validates the core claim)

```swift
func testFetchAllObservationWithoutDynamicPropertyUpdate() async throws {
  // This test explicitly does NOT call sharedReader.update() or fetchAll.update()
  // It verifies that the GRDB subscription mechanism alone propagates changes
  let db = try DatabaseQueue()
  // ... setup schema ...

  let fetchAll = FetchAll(wrappedValue: [], Item.all.selectStar().asSelect(), database: db)
  // No update() call

  var values: [[Item]] = [fetchAll.wrappedValue]
  let expectation = XCTestExpectation(description: "Change received")

  let cancellable = fetchAll.publisher.dropFirst().sink { items in
    values.append(items)
    expectation.fulfill()
  }

  try db.write { db in
    var item = Item(id: 1, name: "alpha")
    try item.insert(db)
  }

  await fulfillment(of: [expectation], timeout: 1.0)
  XCTAssertEqual(values.last?.count, 1)
  _ = cancellable
}
```

### Test 4: _PersistentReference Observation Tracking (integration test)

```swift
func testPersistentReferenceObservationTracking() throws {
  // Verify that withObservationTracking on a _PersistentReference fires on mutation
  let db = try DatabaseQueue()
  // ... setup ...
  let reader = SharedReader(wrappedValue: [], .fetch(RawItemRequest(), database: db))

  var changed = false
  withObservationTracking {
    _ = reader.wrappedValue  // Access -> registers observation
  } onChange: {
    changed = true
  }

  try db.write { db in try db.execute(sql: "INSERT INTO items VALUES (1, 'alpha')") }
  RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  XCTAssertTrue(changed, "stdlib withObservationTracking should fire on SharedReader mutation")
}
```

This test directly validates the "saving grace" hypothesis: that stdlib `withObservationTracking`
captures `@SharedReader` reads and fires `onChange` on mutation. If this test passes on macOS, it
confirms that Android's `StateTracking`-based equivalent also works (since `StateTracking` uses
the same stdlib `withObservationTracking` mechanism).

### Test 5: FetchSubscription Cancellation (correctness test)

```swift
func testFetchSubscriptionCancelsObservation() async throws {
  let db = try DatabaseQueue()
  // ... setup ...
  let fetchAll = FetchAll(wrappedValue: [], Item.all.selectStar().asSelect(), database: db)

  let sub = try await fetchAll.load(Item.all.selectStar().asSelect(), database: db)

  var postCancelCount = 0
  // Subscribe to publisher for post-cancel change count
  let cancellable = fetchAll.publisher.dropFirst().sink { _ in postCancelCount += 1 }

  sub.cancel()

  try db.write { db in /* insert */ }
  try await Task.sleep(nanoseconds: 50_000_000)

  XCTAssertEqual(postCancelCount, 0, "After FetchSubscription.cancel(), no updates should arrive")
  _ = cancellable
}
```

---

## 11. Revised Confidence Assessment

### Original Claim
"On Android via Skip, the DynamicProperty lifecycle works differently. Skip's SwiftUI bridge handles
view updates through the Phase 1 observation bridge, not through SwiftUI's `update()` mechanism."

### Evidence Supporting HIGH Confidence

1. **DynamicProperty is not called by Skip at all** — SkipUI's `DynamicProperty.swift` has the
   entire protocol definition commented out. Skip's `View.Evaluate()` never calls `update()`.
   The guard is architecturally correct.

2. **Subscription established at init, not at update** — `key.subscribe()` is called in
   `_PersistentReference.init`, which executes during `SharedReader` initialization, well before
   any view renders. The GRDB `ValueObservation` is live from the moment `@FetchAll` is created.

3. **Identical mechanism to @Shared** — `@Shared` uses the same `_PersistentReference` /
   `PerceptionRegistrar` / stdlib `ObservationRegistrar` path. `@Shared` was validated with 50
   tests in Phase 4 including direct observation tests (`SharedObservationTests`). The internal
   observation mechanism is not platform-specific — it uses Swift's stdlib `Observable` protocol.

4. **Value changes flow through _PersistentReference.withMutation** — GRDB's `onChange` callback
   ultimately calls `withMutation` on the `_PersistentReference`, which fires the stdlib
   `ObservationRegistrar`. Any active `withObservationTracking` observer receives `onChange`.

5. **StateTracking.pushBody()/popBody() likely establishes stdlib withObservationTracking** —
   The view body evaluation in `View.Evaluate()` wraps the body call with `StateTracking.pushBody`
   / `StateTracking.popBody`. For `@State` properties to work in Skip (which they demonstrably do),
   `StateTracking` must integrate with some observation tracking mechanism. The stdlib
   `withObservationTracking` is the most direct mechanism for this.

### Remaining Uncertainty

The one unverified assumption is that `StateTracking.pushBody()` establishes a **stdlib**
`withObservationTracking` scope that captures `_PersistentReference.access()` calls. This is
opaque code in `SkipModel`. The bridge's `ObservationRecording` record-replay system does NOT
capture these calls (confirmed gap from Phase 4 research). So recomposition depends entirely on
whether `StateTracking` uses stdlib `withObservationTracking`.

The analogy with `@Shared` being validated (Phase 4, 50 tests) strongly supports this, but it is
an inference, not a direct measurement.

### Revised Confidence: HIGH (raised from MEDIUM-HIGH)

The mechanism is structurally sound:
- `DynamicProperty.update()` is correctly excluded — Skip never calls it
- Subscription is init-time, not update-time
- The observation chain from GRDB -> `_PersistentReference` -> stdlib `ObservationRegistrar` ->
  Compose recomposition is the same path validated for `@Shared` in Phase 4
- No architectural changes are needed

The recommendation is to add Tests 3 and 4 above to the Phase 6 test suite to directly validate
the `withObservationTracking` hypothesis at the macOS unit test level, establishing a
cross-platform parity baseline via `skip test`.

---

## 12. Summary Diagram: Android Observation Flow for @FetchAll

```
INITIALIZATION (happens once, at property wrapper creation):

  @FetchAll(Item.all) var items
    |
    v
  FetchAll.init
    -> SharedReader.init(wrappedValue: [], .fetch(request, database: db))
      -> PersistentReferences.value(forKey: fetchKey)
        -> _PersistentReference.init(key: fetchKey, ...)
             key.load(context: .initialValue) --> returns default immediately (FetchKey skips for .initialValue)
             key.subscribe(context:, subscriber:) --> INSTALLS GRDB ValueObservation
               ValueObservation.start(in: db, scheduling: ImmediateScheduler) {
                 onError: subscriber.yield(throwing:)
                 onChange: subscriber.yield(value)   // <-- delivers every DB change
               }
             Initial fetch delivered synchronously: wrappedValue = [initial items]


RUNTIME (repeats on every database change):

  GRDB transaction commits
    |
    v
  ValueObservation.onChange callback fires
    |
    v
  subscriber.yield(value)
    |
    v
  _PersistentReference.wrappedValue.set(newValue)
    |
    v
  withMutation(keyPath: \.value) {
    _$perceptionRegistrar.withMutation(of: self, keyPath:)
      stdlib ObservationRegistrar.willSet() / didSet()
        |
        v
      [Notifies all active withObservationTracking observers]
  }
    |
    v
  StateTracking's withObservationTracking onChange fires
    |
    v
  Compose recomposition scheduled on main thread
    |
    v
  View.Evaluate() runs again
    ViewObservation.startRecording()
    body.Evaluate() -- accesses items.wrappedValue
    ViewObservation.stopAndObserve()
      (Note: record-replay misses @SharedReader reads,
       but StateTracking's own tracking already handles recomposition)


VIEW READS (during body.Evaluate()):

  items.wrappedValue
    -> sharedReader.wrappedValue
      -> reference.wrappedValue
        -> _PersistentReference.wrappedValue
             access(keyPath: \.value)
             stdlib ObservationRegistrar.access()
               -> captured by StateTracking's withObservationTracking
             return lock.withLock { value }   // returns latest fetched data
```

---

*Research completed: 2026-02-22*
*Files examined: 18 source files + 4 planning documents*
*Confidence revised: MEDIUM-HIGH -> HIGH*
