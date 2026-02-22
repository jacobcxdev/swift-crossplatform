# @Shared Recomposition Research: Android vs Apple

## Summary

`@Shared` uses **two parallel notification channels**: an `ObservationRegistrar` (via `PerceptionRegistrar`) for SwiftUI/Compose observation, and a `PassthroughRelay` (Combine publisher) for subscriber-based reactivity. On Apple, SwiftUI views additionally use a `@State` generation counter bumped by the publisher. On Android, the generation counter is disabled, and recomposition depends entirely on the observation registrar path -- but this path has a **critical gap**: the `PerceptionRegistrar` inside `_BoxReference`/`_PersistentReference` routes to the **stdlib** `ObservationRegistrar`, bypassing the bridge's JNI-backed `Observation.ObservationRegistrar` wrapper. This means `@Shared` mutations may not trigger Compose recomposition unless the bridge's record-replay system captures the access during body evaluation.

---

## 1. Shared.update() Guard

**File:** `forks/swift-sharing/Sources/Sharing/Shared.swift:496-503`

```swift
#if canImport(SwiftUI)
  extension Shared: DynamicProperty {
    #if !os(Android)
      public func update() {
        box.subscribe(state: _generation)
      }
    #endif
  }
#endif
```

**What Apple does:** `update()` is called by SwiftUI's property-wrapper lifecycle. It calls `box.subscribe(state:)`, which sets up a Combine sink on the `PassthroughRelay` that increments a `@State private var generation: Int`. Every time the underlying reference's value changes, the publisher fires, the generation counter bumps, and SwiftUI sees the `@State` mutation, triggering a view re-render.

**What Android skips:** The entire `update()` method and `_generation` state property are compiled out via `#if !os(Android)`. Android has no `@State`-based generation counter. The `Box.subscribe(state:)` method (lines 406-413) and `swiftUICancellable` (lines 367, 402-404) are also compiled out.

**Why:** Skip's Compose integration does not use SwiftUI's `DynamicProperty.update()` lifecycle. Compose recomposition is driven by `MutableState` reads/writes through the JNI bridge, not by SwiftUI's `@State` change detection.

---

## 2. Shared as DynamicProperty

**File:** `forks/swift-sharing/Sources/Sharing/Shared.swift:20-24, 496-503`

```swift
public struct Shared<Value> {
  let box: Box
  #if canImport(SwiftUI) && !os(Android)
    @State private var generation = 0
  #endif
  // ...
}
```

**Apple path:** `Shared` conforms to `DynamicProperty`. SwiftUI calls `update()` during the view update phase. `update()` subscribes to the `Box`'s `PassthroughRelay` via a Combine sink that increments `_generation`. Because `_generation` is `@State`, SwiftUI detects the change and schedules a re-render.

This is a **pre-iOS 17 fallback**. Note `Box.subscribe(state:)` line 408:
```swift
guard #unavailable(iOS 17, macOS 14, tvOS 17, watchOS 10) else { return }
```
On iOS 17+, this subscribe is a no-op because SwiftUI natively tracks `Observable` conformances. The generation counter is only active on iOS 16 and below.

**Android path:** `_generation` is not compiled. `update()` is not compiled. `Shared` still conforms to `DynamicProperty` (the conformance itself is not guarded), but the protocol has no required methods, so an empty conformance is valid.

---

## 3. Observation Bridge Pathway for @Shared Mutation

### Mutation flow: `$shared.withLock { $0 = newValue }`

Tracing from caller through the code:

1. **`Shared.withLock`** (Shared.swift:140-172) calls `reference.withLock { ... }`
2. **`_BoxReference.withLock`** (Reference.swift:119-123):
   ```swift
   func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
     try withMutation(keyPath: \.value) {
       try lock.withLock { try body(&value) }
     }
   }
   ```
3. **`_BoxReference.withMutation`** (Reference.swift:148-164) calls `_$perceptionRegistrar.withMutation(of: self, keyPath: keyPath, mutation)`
4. **`PerceptionRegistrar.withMutation`** (PerceptionRegistrar.swift:146-167):
   - Checks `#if canImport(Observation)` -- **true on Android**
   - Checks `#available(iOS 17, ...)` -- **true on Android** (no platform match = available)
   - Checks `!isObservationBeta` -- **true** (only checks iOS/tvOS/watchOS)
   - Casts subject to `any Observable` -- **succeeds** (`_BoxReference` conforms to `Observable`)
   - Routes to: `observationRegistrar.withMutation(of: subject, keyPath: keyPath, mutation)`
5. **`observationRegistrar`** is the **stdlib** `ObservationRegistrar` (stored as `rawValue` during init)

### Does it go through the bridge's ObservationRegistrar?

**NO.** The `PerceptionRegistrar` stores a **stdlib** `ObservationRegistrar` directly. The bridge's `Observation.ObservationRegistrar` (in `skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`) is a separate type that wraps the stdlib one and adds JNI `BridgeObservationSupport` calls. It is only used when:
- The `@Observable` macro expansion explicitly references `Observation.ObservationRegistrar` (the bridge's shadowing type)
- Or code explicitly uses the bridge's `Observation.ObservationRegistrar` type

### Does it go through the PassthroughRelay publisher?

**YES, simultaneously.** The `value` property has a `willSet` observer (Reference.swift:50-56):
```swift
private var value: Value {
  willSet {
    @Dependency(\.snapshots) var snapshots
    if !snapshots.isAsserting {
      subject.send(newValue)
    }
  }
}
```
When `body(&value)` mutates the value inside `withLock`, the `willSet` fires and sends through the `PassthroughRelay`. The `Box` subscribes to this relay and forwards to its own `subject` (Shared.swift:379-381, 394-396).

### Both paths fire:
- **ObservationRegistrar path:** `withMutation` -> stdlib `ObservationRegistrar.willSet`/`didSet` -> notifies any `withObservationTracking` observers
- **Publisher path:** `value.willSet` -> `subject.send(newValue)` -> Combine subscribers

For `_PersistentReference`, the flow is identical: `withLock` wraps in `withMutation`, and the `value` property has the same `willSet` publisher pattern.

---

## 4. How SwiftUI/Compose Views Get Notified

### Apple (iOS 17+):
1. View reads `@Shared` value -> `Shared.wrappedValue.get` -> `reference.wrappedValue` -> `_BoxReference.wrappedValue`
2. `_BoxReference.wrappedValue` calls `access(keyPath: \.value)` -> `_$perceptionRegistrar.access(self, keyPath:)`
3. `PerceptionRegistrar.access` routes to stdlib `ObservationRegistrar.access(subject, keyPath:)`
4. SwiftUI's observation tracking records this access
5. On mutation, `ObservationRegistrar.willSet/didSet` fires, SwiftUI schedules re-render

### Apple (pre-iOS 17):
1. Same access path, but `PerceptionRegistrar` falls through to `_PerceptionRegistrar` (custom backport)
2. Additionally, `Shared.update()` subscribes `_generation` to the publisher
3. Mutation fires `willSet` on value -> publisher -> `_generation` bumps -> SwiftUI re-renders

### Android (with observation bridge):
1. View body evaluates inside Compose's `Evaluate()` function
2. The bridge calls `ObservationRecording.startRecording()` via JNI before body eval
3. View reads `@Shared` value -> `_BoxReference.wrappedValue` -> `access(keyPath: \.value)`
4. `PerceptionRegistrar.access` routes to **stdlib** `ObservationRegistrar.access(subject, keyPath:)`
5. **CRITICAL:** `ObservationRecording.isRecording` is checked inside the **bridge's** `Observation.ObservationRegistrar.access()`, NOT the stdlib one. Since `_BoxReference` uses a `PerceptionRegistrar` that stores the **stdlib** `ObservationRegistrar`, the bridge's recording hooks are **never invoked** for `@Shared` property reads.

### The gap on Android:

```
@Shared wrappedValue.get
  -> _BoxReference.access(keyPath: \.value)
    -> PerceptionRegistrar.access(self, keyPath:)
      -> stdlib ObservationRegistrar.access(self, keyPath:)  // NOT bridge's wrapper
        // No ObservationRecording.recordAccess() call
        // No BridgeObservationSupport.access() call
        // No JNI MutableStateBacking.access() call
```

The bridge's record-replay pattern (`ObservationRecording.startRecording` / `stopAndObserve`) only intercepts `access()` calls that go through the **bridge's** `Observation.ObservationRegistrar`. Since `@Shared`'s references use `PerceptionRegistrar` which stores the **stdlib** `ObservationRegistrar`, the bridge never sees these accesses.

**This means `@Shared` value reads during Compose body evaluation are invisible to the bridge, and mutations will NOT trigger Compose recomposition through the observation path.**

### Potential saving grace: `withObservationTracking`

If Skip's view evaluation wraps body execution in `withObservationTracking` (the stdlib version), then the stdlib `ObservationRegistrar.access()` calls WOULD be captured, and the stdlib `withObservationTracking`'s `onChange` handler would fire on mutation. However, this only works if Skip connects the `onChange` callback to Compose recomposition (e.g., via `MutableState` increment).

The bridge's `ObservationRecording.stopAndObserve()` does exactly this -- it replays recorded accesses inside `withObservationTracking` and connects `onChange` to `triggerSingleUpdate()`. But the recording step misses `@Shared` accesses because they bypass the bridge's registrar.

---

## 5. SharedBinding on Android

**File:** `forks/swift-sharing/Sources/Sharing/SharedBinding.swift:17-48`

```swift
public init(_ base: Shared<Value>) {
  guard
    #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *),
    let reference = base.reference as? any MutableReference & Observable
  else {
    #if os(Android)
      func open(_ reference: some MutableReference<Value>) -> Binding<Value> {
        @SwiftUI.Bindable var reference = reference
        return $reference._wrappedValue as! Binding<Value>
      }
      self = open(base.reference)
      return
    #else
      // PerceptionCore.Bindable path for pre-iOS 17
    #endif
  }
  // iOS 17+ path: SwiftUI.Bindable
}
```

**Android path:** The `#available(iOS 17, ...)` check succeeds on Android (no platform match), so the guard's `let reference = base.reference as? any MutableReference & Observable` is attempted. Since `_BoxReference` conforms to both `MutableReference` and `Observable`, this cast **succeeds**, and the code falls through to the iOS 17+ path:

```swift
func open<V>(_ reference: some MutableReference<V> & Observable) -> Binding<Value> {
  @SwiftUI.Bindable var reference = reference
  return $reference._wrappedValue as! Binding<Value>
}
self = open(reference)
```

This uses `@SwiftUI.Bindable`, which on Android (via Skip) creates a Binding that reads/writes through the `Observable` reference. When the binding writes, it calls `_wrappedValue.set` -> `reference.withLock { $0 = newValue }`, triggering the same mutation path described in section 3.

**Connection to Compose:** `@SwiftUI.Bindable` in Skip produces a Binding backed by Compose's state management. The write triggers `withMutation` on the stdlib `ObservationRegistrar`, which notifies any active `withObservationTracking` observers. If the Compose composable is observing via Skip's `withObservationTracking` integration, it recomposes.

---

## 6. ValueReference and Observation

**Note:** There is no `ValueReference.swift` in the current codebase. The relevant types are:

### _BoxReference (in-memory references)
**File:** `forks/swift-sharing/Sources/Sharing/Internal/Reference.swift:45-169`

- Conforms to: `MutableReference`, `Observable`, `Perceptible`, `@unchecked Sendable`
- Has: `private let _$perceptionRegistrar = PerceptionRegistrar(isPerceptionCheckingEnabled: false)`
- `access()`: Routes through `_$perceptionRegistrar.access(self, keyPath:)` -> on Android, this goes to stdlib `ObservationRegistrar.access()`
- `withMutation()`: Routes through `_$perceptionRegistrar.withMutation(of: self, keyPath:)` -> on Android, stdlib `ObservationRegistrar.withMutation()`
- Thread safety: if not on main thread, dispatches a no-op `withMutation` to main thread asynchronously (ensures UI update on main thread)

### _PersistentReference (key-backed references)
**File:** `forks/swift-sharing/Sources/Sharing/Internal/Reference.swift:171-353`

- Conforms to: `Reference`, `Observable`, `Perceptible`, `@unchecked Sendable`
- Same `PerceptionRegistrar` pattern as `_BoxReference`
- Same `access()`/`withMutation()` routing
- Additionally: subscribes to external key changes via `SharedSubscription`, which update `wrappedValue` through `withMutation`

### Does the registrar's access()/withMutation() flow through the Android bridge?

**No.** As detailed in section 4, the `PerceptionRegistrar` stores the **stdlib** `ObservationRegistrar`, not the bridge's `Observation.ObservationRegistrar`. The bridge's JNI hooks (`BridgeObservationSupport.access()`, `BridgeObservationSupport.willSet()`, `ObservationRecording.recordAccess()`) are never called for `@Shared` property accesses.

---

## 7. PersistentReference Caching

**File:** `forks/swift-sharing/Sources/Sharing/Internal/PersistentReferences.swift`

```swift
final class PersistentReferences: @unchecked Sendable, DependencyKey {
  private var storage: [AnyHashable: Any] = [:]
  private let lock = NSRecursiveLock()

  func value<Key: SharedReaderKey>(
    forKey key: Key,
    default value: @autoclosure () throws -> Key.Value,
    skipInitialLoad: Bool
  ) rethrows -> _PersistentReference<Key> {
    // Double-check locking pattern
    if let reference = lock.withLock({ (storage[key.id] as? Weak<Key>)?.reference }) {
      return reference  // Return existing reference
    } else {
      // Create new, but check again inside lock
      let reference = _PersistentReference(key: key, value: value, skipInitialLoad: skipInitialLoad)
      return lock.withLock {
        if let reference = (storage[key.id] as? Weak<Key>)?.reference {
          return reference  // Another thread created it first
        } else {
          storage[key.id] = Weak(reference: reference)
          // ...
          return reference
        }
      }
    }
  }
}
```

**Yes, they share the same `_PersistentReference`.** Two `@Shared(.appStorage("key"))` declarations will resolve to the same `_PersistentReference` instance (keyed by `key.id`). The cache uses `Weak` references, so the `_PersistentReference` is kept alive as long as at least one `@Shared` holds a strong reference to it via its `Box`.

**Cross-notification:** When one `@Shared` mutates the value via `withLock`, the `_PersistentReference.withLock` calls `withMutation(keyPath: \.value)`, which:
1. Notifies the stdlib `ObservationRegistrar` (willSet/didSet) -- all `withObservationTracking` observers see the change
2. Fires the `willSet` on the `value` property, which sends through the `PassthroughRelay` -- all Combine subscribers see the change
3. Both `@Shared` instances hold the same `_PersistentReference`, so any view reading either gets the updated value

Additionally, `_PersistentReference` subscribes to the `SharedKey` for external changes (e.g., UserDefaults changes from another process), which also go through `wrappedValue.set` -> `withMutation`.

---

## 8. Double-Notification Prevention (SHR-11)

**Scenario:** `@Observable` model contains `@ObservationIgnored @Shared var prop`

```swift
@Observable
class FeatureModel {
  @ObservationIgnored @Shared(.appStorage("count")) var count = 0
}
```

### On mutation via `$model.count.withLock { $0 += 1 }`:

1. **Observable registrar fires?** **NO.** `@ObservationIgnored` prevents the `@Observable` macro from generating `access()`/`withMutation()` calls for this property. The model's `ObservationRegistrar` is not notified.

2. **Shared registrar fires?** **YES.** The mutation goes through `Shared.withLock` -> `_PersistentReference.withLock` -> `_PersistentReference.withMutation(keyPath: \.value)` -> `_$perceptionRegistrar.withMutation(of: self, keyPath:)`. This notifies the reference's own registrar.

3. **Is there any path where both could fire?** **Only if `@ObservationIgnored` is omitted.** Without the annotation:
   - Reading `model.count` would trigger both the model's registrar (`access` on the computed property) AND the reference's registrar (inside `wrappedValue.get`)
   - Writing would trigger both the model's `withMutation` AND the reference's `withMutation`
   - This would cause **double notification**: SwiftUI would see two separate observation changes and potentially render twice

   With `@ObservationIgnored`, only the reference's registrar fires, which is the correct behavior.

### Android-specific concern:
On Android, the same logic applies but through the stdlib `ObservationRegistrar`. The bridge's `Observation.ObservationRegistrar` would only be involved if the `@Observable` macro expansion uses the bridge's type (which it does for bridge-compiled models). But since the property is `@ObservationIgnored`, the bridge registrar on the model is not involved for this property.

---

## Notification Path Diagram

```
                        APPLE (iOS 17+)                          ANDROID (with bridge)
                        ===============                          ====================

  @Shared.wrappedValue.get
       |                                                              |
       v                                                              v
  _BoxReference.wrappedValue                                    _BoxReference.wrappedValue
       |                                                              |
       v                                                              v
  access(keyPath: \.value)                                      access(keyPath: \.value)
       |                                                              |
       v                                                              v
  PerceptionRegistrar.access()                                  PerceptionRegistrar.access()
       |                                                              |
       v                                                              v
  stdlib ObservationRegistrar.access()                          stdlib ObservationRegistrar.access()
       |                                                              |
       v                                                              v
  SwiftUI observation tracking records access                   stdlib observation tracking records access
                                                                (bridge's ObservationRecording does NOT see this)


  $shared.withLock { $0 = newValue }
       |                                                              |
       v                                                              v
  _BoxReference.withLock                                        _BoxReference.withLock
       |                                                              |
       +---> withMutation(keyPath: \.value)                           +---> withMutation(keyPath: \.value)
       |         |                                                    |         |
       |         v                                                    |         v
       |    PerceptionRegistrar.withMutation()                        |    PerceptionRegistrar.withMutation()
       |         |                                                    |         |
       |         v                                                    |         v
       |    stdlib ObservationRegistrar                               |    stdlib ObservationRegistrar
       |      .willSet() / .didSet()                                  |      .willSet() / .didSet()
       |         |                                                    |         |
       |         v                                                    |         v
       |    SwiftUI schedules re-render                               |    stdlib onChange fires
       |                                                              |    (but who is listening?)
       |                                                              |
       +---> value.willSet { subject.send(newValue) }                 +---> value.willSet { subject.send(newValue) }
                 |                                                               |
                 v                                                               v
            PassthroughRelay -> Box.subject                                 PassthroughRelay -> Box.subject
                 |                                                               |
                 v                                                               v
            (pre-iOS 17: generation++ -> @State)                            (no subscriber on Android,
            (iOS 17+: no-op, already handled above)                          generation counter compiled out)


  APPLE RESULT: View re-renders via                              ANDROID RESULT: stdlib ObservationRegistrar
  observation tracking (iOS 17+) or                              fires willSet/didSet, but unless Skip's
  @State generation counter (iOS 16-)                            Compose integration uses stdlib
                                                                 withObservationTracking to observe the
                                                                 _BoxReference, the change is INVISIBLE
                                                                 to Compose recomposition.

                                                                 The bridge's record-replay system
                                                                 (ObservationRecording) does NOT capture
                                                                 @Shared accesses because they go through
                                                                 the stdlib registrar, not the bridge's
                                                                 Observation.ObservationRegistrar wrapper.
```

---

## Critical Finding: The @Shared Android Recomposition Gap

### The Problem

`@Shared`'s underlying references (`_BoxReference`, `_PersistentReference`) use `PerceptionRegistrar`, which on Android stores the **stdlib** `ObservationRegistrar`. The observation bridge's `Observation.ObservationRegistrar` (in `skip-android-bridge`) is a separate type that wraps the stdlib one AND adds:
- `BridgeObservationSupport.access()` -> JNI `MutableStateBacking.access()`
- `BridgeObservationSupport.willSet()` -> JNI `MutableStateBacking.update()`
- `ObservationRecording.recordAccess()` -> record-replay for `withObservationTracking`

Since `@Shared` bypasses the bridge's wrapper, none of these JNI calls happen for `@Shared` property reads/writes.

### Why @Observable Models Work but @Shared Might Not

When you write:
```swift
@Observable class Model {
  var count = 0
}
```

The `@Observable` macro expansion (on Android with `SKIP_BRIDGE`) generates code that uses the bridge's `Observation.ObservationRegistrar`, which includes `BridgeObservationSupport`. So `model.count` accesses go through the bridge and trigger JNI calls.

But `@Shared` creates its own `PerceptionRegistrar` internally, which stores the stdlib `ObservationRegistrar` directly, with no bridge wrapper.

### Possible Mitigations

1. **Skip's Compose integration may use stdlib `withObservationTracking` directly.** If Skip wraps view body evaluation in `Observation.withObservationTracking` (the stdlib one), then the stdlib registrar's access tracking would work, and `onChange` would fire on mutation. The bridge's record-replay is then redundant for this case.

2. **The publisher path could be leveraged.** The `PassthroughRelay` always fires on mutation. If Skip's `Binding` implementation subscribes to publishers, changes could propagate that way.

3. **Force @Shared references through the bridge registrar.** This would require modifying `PerceptionRegistrar` or `_BoxReference` to use the bridge's `Observation.ObservationRegistrar` on Android instead of the stdlib one. This is architecturally complex because `PerceptionRegistrar` is in `swift-perception` which doesn't depend on `skip-android-bridge`.

4. **Wrap @Shared access in a bridged @Observable.** If TCA's `Store` (which is `@Observable` via the bridge) reads `@Shared` values in its observed properties, the Store's bridge registrar fires on access, and the `@Shared` value is included in the render. However, this only works if the Store property read triggers the bridge, and the `@Shared` mutation also triggers the Store's willSet (which it won't if the property is `@ObservationIgnored`).

### Recommendation for Phase 4

The safest approach is to verify empirically whether Skip's Compose integration already handles stdlib `ObservationRegistrar` changes (mitigation 1). If it does, `@Shared` works out of the box. If not, the fix likely needs to be at the `PerceptionRegistrar` level or via a TCA-level adapter that bridges `@Shared` changes into the observation bridge's notification system.
