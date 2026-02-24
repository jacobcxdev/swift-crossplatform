# R2 — Observation Chain: @FetchAll / @FetchOne / @Fetch on Android

**Research date:** 2026-02-22
**Scope:** Full end-to-end trace of the database observation chain from property wrapper
declaration through GRDB ValueObservation, swift-sharing SharedReader, swift-perception, and
the Phase 1 Fuse-mode bridge into Compose recomposition.

---

## 1. Overview

`@FetchAll`, `@FetchOne`, and `@Fetch` are thin property wrappers that each hold a
`SharedReader<Value>` backed by a `FetchKey<Value>` shared-reader key. The key establishes a
live GRDB `ValueObservation` subscription. Every database change relevant to the query fires a
callback that updates the `_PersistentReference` value, which in turn fires the Perception
observation registrar. That registrar notifies `withObservationTracking`, which the Phase 1
bridge uses via the record-replay mechanism to schedule a Compose recomposition.

The chain has **six distinct layers**. Each is examined in full below.

---

## 2. Layer 1 — Property Wrappers (FetchAll / FetchOne / Fetch)

### Files
- `/forks/sqlite-data/Sources/SQLiteData/FetchAll.swift`
- `/forks/sqlite-data/Sources/SQLiteData/FetchOne.swift`
- `/forks/sqlite-data/Sources/SQLiteData/Fetch.swift`

### Structure

All three wrappers share the same design: they hold a `SharedReader<Value>` and delegate
every operation to it.

```swift
// FetchAll.swift (lines 21–31)
@dynamicMemberLookup
@propertyWrapper
public struct FetchAll<Element: Sendable>: Sendable {
  public var sharedReader: SharedReader<[Element]> = SharedReader(value: [])

  public var wrappedValue: [Element] {
    sharedReader.wrappedValue
  }
}
```

The key initialiser path for `FetchAll` (and identically for `FetchOne`/`Fetch`) constructs
a `SharedReader` with a `.fetch(...)` key:

```swift
// FetchAll.swift (lines 138–146)
sharedReader = SharedReader(
  wrappedValue: wrappedValue,
  .fetch(
    FetchAllStatementValueRequest(statement: statement),
    database: database
  )
)
```

`FetchAllStatementValueRequest` is a private `StatementKeyRequest` that calls
`statement.fetchAll(db)` inside the GRDB transaction. `FetchOneStatementValueRequest` calls
`statement.fetchOne(db)`. The `Fetch` wrapper accepts any `FetchKeyRequest` directly.

### Android conditional: `update()` is guarded

A critical Android-specific guard is present in all three wrappers and in `SharedReader`
itself:

```swift
// FetchAll.swift (lines 401–403)
#if canImport(SwiftUI)
  extension FetchAll: DynamicProperty {
    #if !os(Android)
    public func update() {
      sharedReader.update()
    }
    // ... animation initialisers ...
    #endif
  }
#endif
```

On Android the `DynamicProperty.update()` hook is not compiled. This is correct — Android
does not use the SwiftUI `DynamicProperty` invalidation pump. Observation must come
exclusively through the Perception/Phase 1 bridge path.

---

## 3. Layer 2 — FetchKey (SharedReaderKey)

### File
- `/forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift`

`FetchKey<Value>` conforms to `SharedReaderKey` and is the hub where GRDB observation is
established. It has two entry points called by swift-sharing: `load()` and `subscribe()`.

### 3.1 `load()` — one-shot read

```swift
// FetchKey.swift (lines 78–109)
public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
  guard case .userInitiated = context else {
    continuation.resumeReturningInitialValue()
    return
  }
  let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
  withEscapedDependencies { dependencies in
    database.asyncRead { dbResult in
      let result = dbResult.flatMap { db in
        Result { try dependencies.yield { try request.fetch(db) } }
      }
      scheduler.schedule {
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
      }
    }
  }
}
```

`load()` only fires for `.userInitiated` contexts (explicit `.load()` calls). For
`.initialValue` it immediately returns the default value. This is correct on Android — no
initial one-shot fetch is needed because `subscribe()` delivers the first value itself.

### 3.2 `subscribe()` — live observation (THE CRITICAL PATH)

```swift
// FetchKey.swift (lines 111–169)
public func subscribe(
  context: LoadContext<Value>, subscriber: SharedSubscriber<Value>
) -> SharedSubscription {
  let observation = withEscapedDependencies { dependencies in
    ValueObservation.tracking { db in
      dependencies.yield {
        Result { try request.fetch(db) }
      }
    }
  }

  let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
  #if canImport(Combine)
    let dropFirst = switch context {
      case .initialValue: false
      case .userInitiated: true
    }
    let cancellable = observation.publisher(in: database, scheduling: scheduler)
      .dropFirst(dropFirst ? 1 : 0)
      .sink { completion in ... } receiveValue: { newValue in
        switch newValue {
        case .success(let value): subscriber.yield(value)
        case .failure(let error): subscriber.yield(throwing: error)
        }
      }
    return SharedSubscription { cancellable.cancel() }
  #else
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

**On Android, `canImport(Combine)` is false.** The `#else` branch is taken, using GRDB's
direct callback API `ValueObservation.start(in:scheduling:onError:onChange:)`. This is a
clean, Combine-free path. The `subscriber.yield(value)` call is the bridge into swift-sharing.

### 3.3 Default scheduler: `ImmediateScheduler`

When no scheduler is supplied (the common case from `@FetchAll` / `@FetchOne`), the default
used is:

```swift
// FetchKey.swift (lines 194–199)
private struct ImmediateScheduler: ValueObservationScheduler, Hashable {
  func immediateInitialValue() -> Bool { true }
  func schedule(_ action: @escaping @Sendable () -> Void) {
    action()
  }
}
```

`immediateInitialValue() -> true` means GRDB delivers the first value synchronously on the
observation's start thread. Subsequent values are dispatched through the same `schedule`
function — which calls the action directly (inline, on whatever thread GRDB is running).

**Implication:** On Android, the `onChange` callback fires on GRDB's internal write-dispatch
queue, not the main thread. The subscriber update therefore happens off the main thread. This
is handled correctly by `_PersistentReference.withMutation` (see Layer 4).

---

## 4. Layer 3 — SharedReader / _PersistentReference (swift-sharing)

### Files
- `/forks/swift-sharing/Sources/Sharing/SharedReader.swift`
- `/forks/swift-sharing/Sources/Sharing/SharedReaderKey.swift`
- `/forks/swift-sharing/Sources/Sharing/Internal/Reference.swift`
- `/forks/swift-sharing/Sources/Sharing/Internal/PersistentReferences.swift`

### 4.1 SharedReader initialisation

```swift
// SharedReaderKey.swift (lines 218–230)
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

`PersistentReferences` is a dependency-injected singleton that deduplicates references by
`key.id` (a `FetchKeyID` based on database object identity + request hash + scheduler hash).
Multiple views observing the same query share a single `_PersistentReference`.

### 4.2 _PersistentReference — where the subscription lives

```swift
// Reference.swift (lines 202–234)
init(key: Key, value initialValue: Key.Value, skipInitialLoad: Bool) {
  self.key = key
  self.value = initialValue
  let callback: @Sendable (Result<Value?, any Error>) -> Void = { [weak self] result in
    guard let self else { return }
    isLoading = false
    switch result {
    case let .failure(error):
      loadError = error
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
  let context: LoadContext<Key.Value> =
    skipInitialLoad ? .userInitiated : .initialValue(initialValue)
  self.subscription = key.subscribe(
    context: context,
    subscriber: SharedSubscriber(
      callback: callback,
      onLoading: { [weak self] in self?.isLoading = $0 }
    )
  )
}
```

The `subscription` is the live GRDB `AnyDatabaseCancellable` wrapped in `SharedSubscription`.
When GRDB fires `onChange`, it calls `callback`, which sets `wrappedValue`.

### 4.3 wrappedValue setter — the Perception notification

```swift
// Reference.swift (lines 271–281)
var wrappedValue: Key.Value {
  get {
    access(keyPath: \.value)
    return lock.withLock { value }
  }
  set {
    withMutation(keyPath: \.value) {
      lock.withLock { value = newValue }
    }
  }
}
```

```swift
// Reference.swift (lines 332–348)
func withMutation<Member, MutationResult>(
  keyPath: _SendableKeyPath<_PersistentReference, Member>,
  _ mutation: () throws -> MutationResult
) rethrows -> MutationResult {
  #if os(WASI)
    return try _$perceptionRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
  #else
    if Thread.isMainThread {
      return try _$perceptionRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
    } else {
      DispatchQueue.main.async {
        self._$perceptionRegistrar.withMutation(of: self, keyPath: keyPath) {}
      }
      return try mutation()
    }
  #endif
}
```

This is a key design choice: when `wrappedValue` is set from a background thread (as happens
with `ImmediateScheduler` on GRDB's dispatch queue), the `_$perceptionRegistrar.withMutation`
call is hop-dispatched to `DispatchQueue.main.async`. The mutation itself (`lock.withLock { value = newValue }`) executes immediately on the background thread, making the value available,
but the Perception notification fires asynchronously on the main thread.

**On Android:** This means the GRDB callback path is:
1. GRDB write-dispatch queue → `FetchKey.onChange` → `subscriber.yield(value)`
2. `_PersistentReference.wrappedValue = newValue` (background thread — value stored immediately)
3. `DispatchQueue.main.async { _$perceptionRegistrar.withMutation(...) {} }` — queued
4. Main thread — `withMutation` fires, which calls `willSet`/`didSet` on the Perception registrar

### 4.4 OpenCombineShim on Android

On Android, `SharedReader.swift` imports `OpenCombineShim` instead of Combine:

```swift
// SharedReader.swift (lines 7–11)
#if canImport(Combine)
  import Combine
#else
  import OpenCombineShim
#endif
```

The `Box` class inside `SharedReader` uses `PassthroughRelay<Value>` backed by OpenCombine.
This relay is used for SwiftUI's `@State`-based generation counter (the `subject.sink { _ in state.wrappedValue &+= 1 }` pattern). On Android this subscriber path is also guarded:

```swift
// SharedReader.swift (lines 255–258)
#if canImport(SwiftUI) && !os(Android)
  private var swiftUICancellable: AnyCancellable?
#endif
```

```swift
// SharedReader.swift (lines 357–364)
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

The SwiftUI `@State`-based generation counter mechanism is completely absent on Android.
Recomposition relies entirely on Perception observation (Layer 5).

---

## 5. Layer 4 — swift-perception (_PersistentReference as Perceptible)

### File
- `/forks/swift-perception/Sources/PerceptionCore/Perception/PerceptionRegistrar.swift`

`_PersistentReference` holds a `PerceptionRegistrar`:

```swift
// Reference.swift (line 174)
private let _$perceptionRegistrar = PerceptionRegistrar(isPerceptionCheckingEnabled: false)
```

On Android (which has `canImport(Observation)` available via the bridge), `PerceptionRegistrar`
delegates directly to the native Swift `ObservationRegistrar`:

```swift
// PerceptionRegistrar.swift (lines 42–48)
init(isPerceptionCheckingEnabled: Bool = true) {
  #if canImport(Observation)
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *), !isObservationBeta {
      rawValue = ObservationRegistrar()
      return
    }
  #endif
  rawValue = _PerceptionRegistrar()
}
```

Android's Swift SDK ships with iOS 17+ availability, so `ObservationRegistrar` is used. When
`withMutation` fires on the main thread, it calls:

```swift
// PerceptionRegistrar.swift (lines 152–167)
public func withMutation<Subject: Perceptible, Member, T>(
  of subject: Subject,
  keyPath: KeyPath<Subject, Member>,
  _ mutation: () throws -> T
) rethrows -> T {
  #if canImport(Observation)
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *), !isObservationBeta,
       let subject = subject as? any Observable {
      func open<S: Observable>(_ subject: S) throws -> T {
        try observationRegistrar.withMutation(of: subject, keyPath: keyPath, mutation)
      }
      return try open(subject)
    }
  #endif
  return try perceptionRegistrar.withMutation(of: subject, keyPath: keyPath, mutation)
}
```

This fires the native Swift `ObservationRegistrar.withMutation`, which notifies any active
`withObservationTracking` callbacks.

---

## 6. Layer 5 — Phase 1 Bridge (ObservationRecording + BridgeObservationSupport)

### File
- `/forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`

This is the Phase 1 bridge built in the preceding phases of this project. It connects Swift
Observation to Compose recomposition via a record-replay mechanism.

### 6.1 The critical question: does SharedReader.wrappedValue access get recorded?

When a SwiftUI view body reads `items` (i.e., `fetchAll.wrappedValue`), the call chain is:

```
items               (FetchAll.wrappedValue)
  → sharedReader.wrappedValue
    → reference.wrappedValue    (_PersistentReference.wrappedValue getter)
      → access(keyPath: \.value)
        → _$perceptionRegistrar.access(self, keyPath: \.value)
          → ObservationRegistrar.access(subject, keyPath: \.value)
```

On Android, `ObservationRegistrar.access` is the native Swift `Observation` framework's
registrar. This access fires `BridgeObservationSupport.access(subject, keyPath:)` indirectly
through the bridge's `ObservationRegistrar` wrapper:

```swift
// Observation.swift (lines 25–34)
public func access<Subject, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) where Subject : Observable {
  if ObservationRecording.isRecording {
    ObservationRecording.recordAccess(
      replay: { [registrar] in registrar.access(subject, keyPath: keyPath) },
      trigger: { [bridgeSupport] in bridgeSupport.triggerSingleUpdate() }
    )
  }
  bridgeSupport.access(subject, keyPath: keyPath)
  registrar.access(subject, keyPath: keyPath)
}
```

**Wait — this `access` override is on `Observation.ObservationRegistrar`**, which is the
bridge's *own* registrar wrapping the native one. But `_PersistentReference` uses the native
`ObservationRegistrar` directly (from `PerceptionRegistrar.init`). The bridge's
`ObservationRegistrar` type is `ObservationModule.ObservationRegistrarType`, only instantiated
in `Observation.ObservationRegistrar.init()`.

This is the critical gap to investigate further (see Section 8). The `_PersistentReference`'s
`access()` call goes to the native `ObservationRegistrar`, not through the bridge's
`ObservationRegistrar`. Whether `ObservationRecording.recordAccess` fires depends on whether
native `withObservationTracking` is in scope.

### 6.2 The ViewObservation hook (skip-ui)

```
// skip-ui/Sources/SkipUI/SkipUI/View/View.swift (lines 86–98)
@Composable public func Evaluate(context: ComposeContext, options: Int) -> kotlin.collections.List<Renderable> {
    if let renderable = self as? Renderable {
        return listOf(self)
    } else {
        ViewObservation.startRecording?()    // → ObservationRecording.startRecording()

        StateTracking.pushBody()
        let renderables = body.Evaluate(context: context, options: options)
        StateTracking.popBody()

        ViewObservation.stopAndObserve?()   // → ObservationRecording.stopAndObserve()
        return renderables
    }
}
```

`ViewObservation.startRecording` and `ViewObservation.stopAndObserve` are closures wired up
by JNI at app start (via `nativeStartRecording` / `nativeStopAndObserve`).

`startRecording()` pushes a new `Frame` onto the thread-local stack.
`stopAndObserve()` pops the frame and calls:

```swift
// Observation.swift (lines 146–169)
public static func stopAndObserve() {
  guard let frame = threadStack.frames.popLast() else { return }
  guard !frame.replayClosures.isEmpty else { return }
  guard let trigger = frame.triggerClosure else { ... }

  let closures = frame.replayClosures
  ObservationModule.withObservationTrackingFunc({
    for closure in closures { closure() }
  }, onChange: {
    DispatchQueue.main.async { trigger() }
  })
}
```

`withObservationTrackingFunc` calls native `withObservationTracking`. The replay closures
re-execute the `registrar.access(subject, keyPath:)` calls, which registers subscriptions
on the native `ObservationRegistrar`. When `withMutation` fires later (from a database update),
the `onChange` closure fires, calling `trigger()` which calls
`bridgeSupport.triggerSingleUpdate()` → `Java_update(0)` on the Kotlin `MutableStateBacking`.

### 6.3 The `recordAccess` path

```swift
// Observation.swift (lines 171–185)
static func recordAccess(
  replay: @escaping () -> Void,
  trigger: @escaping () -> Void
) {
  let stack = threadStack
  guard !stack.frames.isEmpty else { return }
  stack.frames[stack.frames.count - 1].replayClosures.append(replay)
  if stack.frames[stack.frames.count - 1].triggerClosure == nil {
    stack.frames[stack.frames.count - 1].triggerClosure = trigger
  }
}
```

This records `replay` closures only if `isRecording` is true (i.e., during `Evaluate()`).
The bridge's custom `ObservationRegistrar.access` is what calls `recordAccess`. The question
remains whether `_PersistentReference.access(keyPath:)` flows through the bridge's registrar.

---

## 7. Complete Data Flow Diagram

```
DATABASE WRITE
     │
     ▼
GRDB write-dispatch queue
  SQLite journal flush
     │
     ▼
ValueObservation.tracking { db in
  Result { try request.fetch(db) }   ← FetchKeyRequest.fetch(_:)
}
     │  (GRDB internal change detection)
     ▼
FetchKey.subscribe() → #else branch (no Combine)
  observation.start(in: database, scheduling: ImmediateScheduler()) { error in
    subscriber.yield(throwing: error)
  } onChange: { newValue in              ← fires on GRDB write-dispatch queue
    subscriber.yield(value)
  }
     │
     ▼ subscriber.yield(value)  [SharedSubscriber callback]
     │
     ▼
_PersistentReference callback (background thread)
  wrappedValue = newValue
     │  → lock.withLock { value = newValue }   (value stored immediately)
     │  → since !Thread.isMainThread:
     ▼
DispatchQueue.main.async {
  _$perceptionRegistrar.withMutation(of: self, keyPath: \.value) {}
}
     │
     ▼ (main thread)
ObservationRegistrar.withMutation(of: _PersistentReference, keyPath: \.value)
  [native Swift Observation framework]
     │  fires all registered withObservationTracking onChange closures
     ▼
ObservationRecording.stopAndObserve() previously registered onChange:
  DispatchQueue.main.async {
    bridgeSupport.triggerSingleUpdate()
  }
     │
     ▼ (already on main thread, async dispatched again)
BridgeObservationSupport.Java_update(0)
  peer.call(method: Java_state_update_methodID, args: [Int32(0)])
     │  JNI call into Kotlin
     ▼
MutableStateBacking.update(0)   [Kotlin/Compose side]
  Compose MutableState counter incremented
     │
     ▼
Compose recomposition scheduled
  Evaluate() called on view
     │
     ├─ ViewObservation.startRecording?()
     │    ObservationRecording.startRecording()
     │    [pushes new Frame onto thread-local stack]
     │
     ├─ body evaluated
     │    items  →  FetchAll.wrappedValue
     │           →  SharedReader.wrappedValue
     │           →  _PersistentReference.wrappedValue (getter)
     │                → access(keyPath: \.value)
     │                  → ObservationRegistrar.access(...)
     │                    → BridgeObservationSupport.access(...)  [IF bridge registrar]
     │                      → ObservationRecording.recordAccess(replay:trigger:)
     │                        [records replay closure + trigger in current frame]
     │
     └─ ViewObservation.stopAndObserve?()
          ObservationRecording.stopAndObserve()
          withObservationTracking({
            for closure in replayClosures { closure() }  // re-accesses \.value
          }, onChange: {
            DispatchQueue.main.async { trigger() }       // for next change
          })
          [native Observation registers subscription for next mutation]
```

---

## 8. Gap Analysis — Android-Specific Issues

### Gap 1 (CRITICAL): Does `_PersistentReference` flow through the bridge's `ObservationRegistrar`?

**The gap:** `_PersistentReference` uses `PerceptionRegistrar(isPerceptionCheckingEnabled: false)`.
On Android that resolves to the native `ObservationRegistrar` from the Swift stdlib. The Phase
1 bridge's `Observation.ObservationRegistrar` type is a *different* type that wraps the native
one and intercepts `access()` calls to call `ObservationRecording.recordAccess`.

`_PersistentReference` does **not** use the bridge's `ObservationRegistrar`. It uses the
native one directly. Therefore, when `access(keyPath: \.value)` is called during body
evaluation, it goes to the native `ObservationRegistrar.access`, which does *not* call
`ObservationRecording.recordAccess`.

**What this means:** The record-replay mechanism does not capture `_PersistentReference`
accesses. The replay closures for `@FetchAll` values are **not** recorded in the
`ObservationRecording` frame.

**However — withObservationTracking still works:**
The `_PersistentReference`'s `access(keyPath:)` call does reach the native
`ObservationRegistrar`, which *is* tracked by `withObservationTracking`. When
`stopAndObserve()` calls `withObservationTracking`, the replay closures it executes re-call
`access(keyPath: \.value)` on the native registrar. So the native observation subscription
*is* correctly established — just through the replay path, not the record path.

But if `stopAndObserve()` has no replay closures recorded (because none went through the
bridge's `ObservationRegistrar.access`), `stopAndObserve()` bails early:

```swift
guard !frame.replayClosures.isEmpty else { return }
```

**This means `withObservationTracking` is never called for the native-only registrar path.**
The subscription for future database updates is not established. The view will not recompose
on subsequent database writes after the first render.

**Confidence: HIGH that this is a real gap.** The bridge's recording mechanism only captures
accesses through its own `ObservationRegistrar` type. `_PersistentReference` bypasses this.

### Gap 2 (MEDIUM): Thread safety of `DispatchQueue.main.async` on Android

The `withMutation` dispatch to main uses `DispatchQueue.main.async`. On Android, Skip
provides a `DispatchQueue.main` shim that delegates to the Android main looper. This is
expected to work but adds a potential async hop that could delay recomposition by one run-loop
cycle. This is not a correctness issue but a latency consideration.

### Gap 3 (LOW): `ImmediateScheduler` fires synchronously on the GRDB thread

The first value from `ValueObservation` with `ImmediateScheduler` is delivered synchronously
during `subscribe()`. This means `_PersistentReference` callback fires during init, before
any view has observed the value. This is safe but means the first render always sees the
initial default value, not the database value, for a brief period (until the async main-thread
dispatch fires). On iOS this is also true; on Android there is no additional issue.

### Gap 4 (LOW): `FetchSubscription.cancel()` replaces SharedReader with a static value

```swift
// FetchSubscription.swift (lines 20–21)
init<Value>(sharedReader: SharedReader<Value>) {
  onCancel = { sharedReader.projectedValue = SharedReader(value: sharedReader.wrappedValue) }
}
```

When a `.task` view modifier is cancelled (e.g., on navigation pop), the subscription is
replaced with a static `SharedReader(value:)`. If the view is reused (navigation return), a
new `load(statement:)` must be called to re-establish observation. This is by design but
requires explicit view lifecycle management not present in simple `@FetchAll` declarations.

### Gap 5 (LOW): Animation scheduler not compiled on Android

```swift
// FetchKey+SwiftUI.swift (line 1)
#if canImport(SwiftUI) && !os(Android)
```

The `AnimatedScheduler` and `.animation(_:)` initialisers for `@FetchAll`/`@FetchOne` are
excluded on Android. This is intentional — Compose handles animation differently. No gap.

---

## 9. Confidence Assessment

| Aspect | Confidence | Notes |
|--------|------------|-------|
| FetchKey `#else` branch used on Android | HIGH | `canImport(Combine)` is false on Android |
| GRDB ValueObservation fires correctly | HIGH | GRDB's Android port is established |
| `subscriber.yield` → `_PersistentReference.wrappedValue` setter | HIGH | Code is clear |
| DispatchQueue.main.async for Perception notification | HIGH | Present in `withMutation` |
| Native `ObservationRegistrar.withMutation` fires on main | HIGH | Via `DispatchQueue.main.async` |
| `withObservationTracking` subscription established | MEDIUM-LOW | Depends on Gap 1 |
| Record-replay captures `_PersistentReference.access` | LOW | Bridge's custom registrar not used |
| Compose recomposition fires after database write | UNCERTAIN | Blocked by Gap 1 |

---

## 10. Summary of Gaps Requiring Investigation/Fixing

### Primary Gap (must fix before Phase 6 can claim working observation)

**Gap 1:** The `_PersistentReference` Perception registrar (`ObservationRegistrar`, native
Swift Observation) does not flow through the Phase 1 bridge's custom `ObservationRegistrar`
type. As a result, `ObservationRecording.recordAccess` is never called for database-backed
shared reader values. `stopAndObserve()` bails early (no replay closures), so
`withObservationTracking` is never established for future database updates. Views using
`@FetchAll`/`@FetchOne`/`@Fetch` will receive the initial value (synchronously from
`ImmediateScheduler`) but will not recompose on subsequent database writes.

**Possible fixes:**
1. Make `_PersistentReference` use the bridge's `ObservationRegistrar` (requires fork of
   swift-sharing's `Reference.swift` to use `Observation.ObservationRegistrar` on Android).
2. Teach `ObservationRecording` to intercept native `ObservationRegistrar.access` calls (via
   a Kotlin-side hook in the Compose `Evaluate()` scope that wraps the entire body in native
   `withObservationTracking` rather than using the replay mechanism).
3. Add a `SharedReader`-specific Android hook that manually calls
   `ObservationRecording.recordAccess` when `wrappedValue` is accessed (requires fork of
   swift-sharing's `SharedReader.wrappedValue`).

The cleanest fix is option 1: fork `_PersistentReference.withMutation` to use the bridge's
`ObservationRegistrar` on Android, similar to how `Observation.ObservationRegistrar` wraps
the native one.

---

## 11. File Reference Summary

| File | Role in chain |
|------|--------------|
| `forks/sqlite-data/Sources/SQLiteData/FetchAll.swift` | Property wrapper; holds `SharedReader<[Element]>`; `update()` excluded on Android |
| `forks/sqlite-data/Sources/SQLiteData/FetchOne.swift` | Property wrapper; holds `SharedReader<Value>`; identical Android guard |
| `forks/sqlite-data/Sources/SQLiteData/Fetch.swift` | Property wrapper; accepts `FetchKeyRequest`; identical Android guard |
| `forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift` | `SharedReaderKey`; establishes GRDB `ValueObservation`; `#else` branch on Android |
| `forks/sqlite-data/Sources/SQLiteData/FetchSubscription.swift` | Subscription lifetime token; cancels by swapping to static `SharedReader` |
| `forks/sqlite-data/Sources/SQLiteData/FetchKeyRequest.swift` | Protocol defining `fetch(_:)` on a GRDB `Database` |
| `forks/sqlite-data/Sources/SQLiteData/Internal/StatementKey.swift` | `StatementKeyRequest` bridging SQL query to `FetchKeyRequest` |
| `forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift` | `AnimatedScheduler`; excluded on Android (`!os(Android)`) |
| `forks/swift-sharing/Sources/Sharing/SharedReader.swift` | `SharedReader` struct; `Box` with OpenCombineShim; `update()` excluded on Android |
| `forks/swift-sharing/Sources/Sharing/SharedReaderKey.swift` | `SharedReaderKey` protocol; `_PersistentReference` initialisation path |
| `forks/swift-sharing/Sources/Sharing/Internal/Reference.swift` | `_PersistentReference`; Perception `withMutation`; main-thread dispatch pattern |
| `forks/swift-sharing/Sources/Sharing/Internal/PersistentReferences.swift` | Deduplication store for `_PersistentReference` instances |
| `forks/swift-sharing/Sources/Sharing/Internal/PassthroughRelay.swift` | OpenCombine `PassthroughRelay`; used by `Box` for publisher |
| `forks/swift-perception/Sources/PerceptionCore/Perception/PerceptionRegistrar.swift` | `PerceptionRegistrar` → native `ObservationRegistrar` on Android |
| `forks/swift-perception/Sources/PerceptionCore/PerceptionTracking.swift` | `withPerceptionTracking`; back-port of `withObservationTracking` |
| `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` | Phase 1 bridge; `ObservationRecording` record-replay; JNI exports |
| `forks/skip-android-bridge/Sources/SkipAndroidBridge/ObservationModule.swift` | Thin wrapper exposing native `withObservationTracking` |
| `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` | `Evaluate()` + `ViewObservation` hooks; calls `startRecording`/`stopAndObserve` |
