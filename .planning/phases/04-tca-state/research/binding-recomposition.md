# Binding Recomposition Loop Risk Analysis

## Overview

This document traces the full binding write-read cycle on Android (Skip Fuse mode) to assess the risk of infinite recomposition loops when TCA bindings mutate state. The cycle under investigation is:

```
Binding write -> Store.send(.set(...)) -> BindingReducer -> State mutation
  -> Observation notification -> Compose recomposition -> View body re-eval
  -> Binding read -> (potential re-trigger?)
```

**Conclusion: The loop risk is LOW for standard bindings, but there are edge cases requiring attention.** Multiple layered protections exist, though they operate on different mechanisms (task-local, reentrancy guard, identity check) that interact in non-obvious ways across the JNI bridge.

---

## 1. Binding Write Path (Full Trace)

### Step 1: `$store.text` subscript access

When a SwiftUI view writes `$store.text = "hello"`, it goes through `_StoreBindable_SwiftUI`:

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/Binding+Observation.swift` (lines 36-45)

```swift
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SwiftUI.Bindable {
  @_disfavoredOverload
  public subscript<State: ObservableState, Action, Member>(
    dynamicMember keyPath: KeyPath<State, Member>
  ) -> _StoreBindable_SwiftUI<State, Action, Member>
  where Value == Store<State, Action> {
    _StoreBindable_SwiftUI(bindable: self, keyPath: keyPath)
  }
}
```

The `.sending()` method on `_StoreBindable_SwiftUI` creates a `Binding<Value>` that calls `store[state:action:]` subscript (line 368-370).

### Step 2: Store `dynamicMember` subscript setter

For `@BindableAction` conforming actions, the store's subscript setter fires:

**File:** `Binding+Observation.swift` (lines 175-191)

```swift
extension Store where State: ObservableState, Action: BindableAction, Action.State == State {
  public subscript<Value: Equatable & Sendable>(
    dynamicMember keyPath: WritableKeyPath<State, Value>
  ) -> Value {
    get { self.state[keyPath: keyPath] }
    set {
      BindingLocal.$isActive.withValue(true) {        // <-- PROTECTION #1
        self.send(
          .set(
            keyPath.unsafeSendable(),
            newValue,
            isInvalidated: { [weak self] in self?.core.isInvalid ?? true }
          )
        )
      }
    }
  }
}
```

**Key observation:** `BindingLocal.$isActive.withValue(true)` wraps the entire send call, setting a task-local flag.

### Step 3: `Store.send()` dispatches to `RootCore._send()`

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` (lines 335-337)

```swift
public func send(_ action: Action) -> Task<Void, Never>? {
    core.send(action)
}
```

### Step 4: `RootCore._send()` processes with reentrancy guard

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Core.swift` (lines 88-100)

```swift
private func _send(_ action: Root.Action) -> Task<Void, Never>? {
    self.bufferedActions.append(action)
    guard !self.isSending else { return nil }     // <-- PROTECTION #2

    self.isSending = true
    var currentState = self.state
    // ... process actions in loop ...
    defer {
      self.state = currentState                   // state written ONCE at end
      self.isSending = false
    }
    // ...
    let effect = reducer.reduce(into: &currentState, action: action)
    // ...
}
```

**Key observation:** `isSending` is a reentrancy guard. If a second `send()` arrives while the first is still processing, it buffers the action and returns `nil`. State is only committed to `self.state` in the `defer` block after all buffered actions are processed.

### Step 5: `BindingReducer.reduce(into:action:)` applies the mutation

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Reducer/Reducers/BindingReducer.swift` (lines 73-82)

```swift
public func reduce(into state: inout State, action: Action) -> Effect<Action> {
    guard let bindingAction = self.toViewAction(action).flatMap({ $0.binding })
    else { return .none }

    bindingAction.set(&state)       // <-- Direct mutation of local copy
    return .none
}
```

**Key observation:** `bindingAction.set(&state)` mutates the `currentState` local variable inside `RootCore._send()`, NOT the stored `self.state` property. The stored state is only updated in the `defer` block. This means the `@ObservableState` macro's `willSet`/`didSet` on individual properties fires against the local copy, but the Store-level observation registrar notification happens later.

### Step 6: State mutation via `bindingAction.set`

**File:** `Binding+Observation.swift` (lines 79-82)

```swift
// For @ObservableState (modern path):
.init(
  keyPath: keyPath,
  set: { $0[keyPath: keyPath] = value },    // <-- triggers @ObservableState willSet/didSet
  ...
)
```

---

## 2. Observation Notification Path (Android)

### Step 1: `ObservationStateRegistrar.mutate()` fires on state diff

When `RootCore._send()` completes and commits `self.state = currentState` in the defer block, the `didSet` on `RootCore.state` fires `didSet.send(())`.

For scoped stores, the `Store.init` subscribes to `core.didSet` and calls:

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` (line 360)

```swift
self._$observationRegistrar.withMutation(of: self, keyPath: \.currentState) {}
```

### Step 2: Android bridge `ObservationRegistrar.withMutation()`

On Android, `_$observationRegistrar` is `SkipAndroidBridge.Observation.ObservationRegistrar`.

**File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` (lines 47-52)

```swift
public func withMutation<Subject, Member, T>(
    of subject: Subject, keyPath: KeyPath<Subject, Member>,
    _ mutation: () throws -> T
) rethrows -> T where Subject : Observable {
    if !ObservationRecording.isEnabled {            // <-- PROTECTION #3
        bridgeSupport.willSet(subject, keyPath: keyPath)
    }
    return try registrar.withMutation(of: subject, keyPath: keyPath, mutation)
}
```

### Step 3: Two notification channels

When `ObservationRecording.isEnabled == true` (always true in Fuse mode after app startup):

1. **`bridgeSupport.willSet()` is SUPPRESSED** -- the `!ObservationRecording.isEnabled` check prevents direct `MutableStateBacking.update()` calls during withMutation.

2. **`registrar.withMutation()` fires** -- this goes through Swift's native `ObservationRegistrar`, which notifies any `withObservationTracking` closures that were previously registered.

### Step 4: `withObservationTracking` onChange triggers recomposition

When observation tracking was set up (via `ObservationRecording.stopAndObserve()`), the onChange handler fires:

**File:** `Observation.swift` (lines 156-164)

```swift
ObservationModule.withObservationTrackingFunc({
    for closure in closures {
        closure()                                   // replay access() calls
    }
}, onChange: {
    DispatchQueue.main.async {                      // <-- PROTECTION #4: async dispatch
        trigger()                                   // calls bridgeSupport.triggerSingleUpdate()
    }
})
```

**Key observation:** The onChange handler dispatches the trigger ASYNCHRONOUSLY via `DispatchQueue.main.async`. This breaks the synchronous call chain.

### Step 5: `triggerSingleUpdate()` increments Compose state

**File:** `Observation.swift` (lines 204-209)

```swift
func triggerSingleUpdate() {
    lock.wait()
    defer { lock.signal() }
    guard Java_hasInitialized, Java_peer != nil else { return }
    Java_update(0)                                  // MutableStateBacking.update(0)
}
```

This calls `MutableStateBacking.update(0)` via JNI, which increments a Compose `MutableState<Int>` counter, triggering Compose recomposition of the enclosing composable scope.

---

## 3. BindingLocal.isActive Protection (Deep Dive)

### Definition

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Core.swift` (lines 14-17, Android path)

```swift
#if !canImport(SwiftUI) || os(Android)
enum BindingLocal {
  @TaskLocal static var isActive = false
}
#endif
```

Also defined for non-Android at:
**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/ViewStore.swift` (lines 632-635)

```swift
#if !os(Android)  // BindingLocal already defined in Core.swift for Android
enum BindingLocal {
  @TaskLocal static var isActive = false
}
#endif
```

### Mechanism

`BindingLocal.isActive` is a **Swift `@TaskLocal`** value. It uses structured concurrency's task-local storage, meaning:

- The value `true` is only visible within the dynamic scope of `BindingLocal.$isActive.withValue(true) { ... }`
- It propagates through synchronous calls within that scope
- It resets to `false` once the closure returns

### Usage in `IfLetCore.send()`

**File:** `Core.swift` (lines 301-305)

```swift
func send(_ action: Action) -> Task<Void, Never>? {
    if BindingLocal.isActive && isInvalid {
      return nil                                    // silently drops binding action
    }
    return base.send(actionKeyPath(action))
}
```

This prevents binding writes to dismissed optional child state from crashing.

### Cross-bridge behavior

**CRITICAL FINDING:** `@TaskLocal` is a Swift concurrency primitive. It works correctly within the same synchronous call chain on any platform (including Android). The binding write path is entirely synchronous:

```
subscript setter -> BindingLocal.$isActive.withValue(true) {
  -> store.send() -> core._send() -> reducer.reduce() -> state mutation
}
```

All of this happens synchronously within the `withValue(true)` scope, so `BindingLocal.isActive` is correctly `true` during the entire binding write. However, `BindingLocal.isActive` does NOT persist across the async boundary in the observation onChange handler (`DispatchQueue.main.async { trigger() }`). By the time recomposition triggers, the task-local has already been restored to `false`.

**This is actually the correct behavior** -- `BindingLocal.isActive` only needs to protect the write path, not the subsequent recomposition.

---

## 4. ObservationRecording.isEnabled Flag

### Definition

**File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` (lines 88-91)

```swift
/// True once hooks are registered -- gates bridgeSupport.willSet() suppression.
/// When false (no hooks), bridgeSupport.willSet() fires normally (original behavior).
/// When true, withObservationTracking handles recomposition instead.
public static var isEnabled = false
```

### How it's set

Set once at app startup via JNI from Kotlin:

**File:** `Observation.swift` (lines 291-294)

```swift
@_cdecl("Java_skip_ui_ViewObservation_nativeEnable")
func _jni_nativeEnable(_ env: OpaquePointer?, _ thiz: OpaquePointer?) {
    ObservationRecording.isEnabled = true
}
```

Called from `ViewObservation.init` in Kotlin (View.swift line 31).

### Interaction with binding path

When `isEnabled == true`:

1. **`willSet()` in `ObservationRegistrar`** (line 37-39): `bridgeSupport.willSet()` is suppressed. This prevents direct `MutableStateBacking.update()` calls during property mutation, which would cause SYNCHRONOUS Compose state changes.

2. **`withMutation()` in `ObservationRegistrar`** (line 48-51): Same suppression of `bridgeSupport.willSet()`.

3. **Instead, recomposition goes through the record-replay path**: `access()` calls are recorded during body eval, replayed inside `withObservationTracking`, and the onChange handler fires asynchronously.

**This is a critical protection:** Without `isEnabled`, every `willSet` during binding mutation would synchronously call `MutableStateBacking.update()`, potentially triggering recomposition before the mutation completes.

---

## 5. Store.withState vs Direct Property Access

### `store.state` (observable access)

**File:** `Store+Observation.swift` (lines 12-16)

```swift
extension Store where State: ObservableState {
  var observableState: State {
    self._$observationRegistrar.access(self, keyPath: \.currentState)  // registers tracking
    return self.currentState
  }
}
```

When a view body reads `store.text`, it calls `store.state[keyPath: \.text]`, which calls `observableState`, which calls `_$observationRegistrar.access()`. On Android, this goes through:

**File:** `Observation.swift` (lines 25-34)

```swift
public func access<Subject, Member>(_ subject: Subject, keyPath: ...) {
    if ObservationRecording.isRecording {
        ObservationRecording.recordAccess(
            replay: { [registrar] in registrar.access(subject, keyPath: keyPath) },
            trigger: { [bridgeSupport] in bridgeSupport.triggerSingleUpdate() }
        )
    }
    bridgeSupport.access(subject, keyPath: keyPath)     // JNI MutableStateBacking.access()
    registrar.access(subject, keyPath: keyPath)          // Swift observation tracking
}
```

### Can a read trigger mutation?

**No.** The `access()` path only:
1. Records the access for replay (if recording)
2. Calls `MutableStateBacking.access()` via JNI (which reads the Compose state, establishing a Compose dependency)
3. Calls the native registrar's `access()` (which registers the keypath for observation tracking)

None of these mutate state or send actions. **Reads are side-effect-free.**

### `store.withState()`

**File:** `Store.swift` (lines 177-185)

```swift
public func withState<R>(_ body: (_ state: State) -> R) -> R {
    body(self.currentState)     // bypasses observation registrar
}
```

`withState` accesses `currentState` directly without going through `_$observationRegistrar.access()`, so it does NOT establish observation tracking. This is intentionally non-observable.

---

## 6. Compose Recomposition Model in Skip Fuse Mode

### How Compose decides to recompose

In Skip's Fuse mode, recomposition is triggered by `MutableStateBacking.update(index)`, which increments a `MutableState<Int>` counter. Any composable that has called `MutableStateBacking.access(index)` during its previous composition will be invalidated and scheduled for recomposition.

### Evaluate() cycle

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` (lines 86-99)

```swift
@Composable public func Evaluate(context: ComposeContext, options: Int) -> ... {
    if let renderable = self as? Renderable {
        return listOf(self)
    } else {
        ViewObservation.startRecording?()           // push recording frame

        StateTracking.pushBody()
        let renderables = body.Evaluate(...)        // evaluate view body
        StateTracking.popBody()

        ViewObservation.stopAndObserve?()           // pop frame, setup withObservationTracking
        return renderables
    }
}
```

### Synchronous vs. batched

Compose recomposition is **batched and asynchronous**:

1. `MutableStateBacking.update()` marks composables as dirty
2. Compose schedules a recomposition frame (similar to Android's `invalidate()`)
3. Recomposition happens on the next frame, not immediately

This is fundamentally different from SwiftUI, where state changes can trigger synchronous view body re-evaluation in certain cases.

### Impact on loop protection

The batched nature of Compose recomposition provides an **additional layer of protection**:

- Even if the onChange handler fires synchronously (it doesn't -- it uses `DispatchQueue.main.async`), Compose would still batch the recomposition
- The double-async gap (Swift `DispatchQueue.main.async` + Compose frame scheduling) means there is always a temporal separation between the binding write and the subsequent view body re-evaluation
- By the time the view body re-evaluates, `BindingLocal.isActive` has long been reset to `false`, and `RootCore.isSending` has been reset to `false`

---

## 7. Full Cycle Diagram

```
USER INPUT (e.g., TextField onChange)
  |
  v
$store.text = "hello"
  |
  v
_StoreBindable_SwiftUI.sending() -> Binding<Value> setter
  |
  v
Store[dynamicMember:] setter  (Binding+Observation.swift:181)
  |  Sets BindingLocal.$isActive = true (task-local)
  |
  v
Store.send(.binding(.set(\.text, "hello")))  (Binding+Observation.swift:182-188)
  |
  v
RootCore._send()  (Core.swift:88)
  |  isSending = true  (reentrancy guard)
  |  currentState = self.state  (snapshot)
  |
  v
BindingReducer.reduce(into: &currentState, action:)  (BindingReducer.swift:73)
  |
  v
bindingAction.set(&currentState)  (BindingReducer.swift:79)
  |  currentState.text = "hello"
  |  (fires @ObservableState macro willSet/didSet on LOCAL copy)
  |  ObservationStateRegistrar.mutate() called
  |    -> isEnabled=true, so bridgeSupport.willSet() SUPPRESSED
  |    -> registrar.withMutation() fires Swift observation
  |    -> BUT: withObservationTracking onChange queues ASYNC trigger
  |
  v
defer { self.state = currentState }  (Core.swift:99)
  |  isSending = false  (Core.swift:100)
  |  RootCore.state.didSet fires didSet.send(())
  |
  v
Store.init subscriber receives didSet  (Store.swift:358-361)
  |  _$observationRegistrar.withMutation(of: self, keyPath: \.currentState) {}
  |  -> Again, isEnabled=true, bridgeSupport.willSet() SUPPRESSED
  |  -> registrar.withMutation() fires Swift observation onChange
  |
  v
onChange handler: DispatchQueue.main.async { trigger() }  (Observation.swift:161)
  |  (ASYNC BOUNDARY -- BindingLocal.isActive is now false)
  |  (ASYNC BOUNDARY -- RootCore.isSending is now false)
  |
  v
trigger() -> bridgeSupport.triggerSingleUpdate()  (Observation.swift:204)
  |  Java_update(0)  (MutableStateBacking counter++)
  |
  v
[Compose frame boundary -- ASYNC]
  |
  v
Compose recomposition of enclosing composable
  |
  v
View.Evaluate()  (View.swift:86)
  |  ViewObservation.startRecording()
  |  body evaluation:
  |    store.text -> observableState -> access() -> records access
  |    (pure read, no mutation, no action sent)
  |  ViewObservation.stopAndObserve()
  |    -> replays access() inside withObservationTracking
  |    -> sets up NEW onChange handler for next change
  |
  v
CYCLE COMPLETE -- no re-trigger unless state actually changes again
```

---

## 8. Known Protections Summary

| # | Protection | Type | File | Lines | Scope |
|---|-----------|------|------|-------|-------|
| 1 | `BindingLocal.$isActive.withValue(true)` | Task-local flag | `Binding+Observation.swift` | 181, 204, 225, 251, 438 | Wraps `store.send()` during binding write; used by `IfLetCore.send()` to drop actions to dismissed state |
| 2 | `RootCore.isSending` reentrancy guard | Instance variable | `Core.swift` | 71, 90-100 | Buffers actions if `send()` is called while already processing; prevents recursive reducer execution |
| 3 | `ObservationRecording.isEnabled` flag | Global static flag | `Observation.swift` | 91, 37-39, 48-50 | Suppresses `bridgeSupport.willSet()` during mutations; prevents synchronous `MutableStateBacking.update()` during state write |
| 4 | `DispatchQueue.main.async` in onChange | Async dispatch | `Observation.swift` | 161 | Breaks synchronous call chain between observation notification and Compose recomposition trigger |
| 5 | Compose frame batching | Framework behavior | (Compose runtime) | N/A | Compose batches recomposition to next frame; never re-enters during same synchronous call |
| 6 | `isIdentityEqual` check in `ObservationStateRegistrar.mutate()` | Value comparison | `ObservationStateRegistrar.swift` | 64 | Skips `withMutation()` entirely if the old and new values have the same identity (same `_$id`), preventing notification for no-op mutations |
| 7 | `ObservationRecording` thread-local stack | Thread-local (pthread) | `Observation.swift` | 107-131 | Recording state is per-thread; nested `Evaluate()` calls push/pop frames correctly; concurrent recomposition on different threads is isolated |
| 8 | Read-only access path | By design | `Store+Observation.swift` | 13-16 | `store.state` access only calls `registrar.access()` -- pure read, no mutations, no actions sent |

---

## 9. Edge Cases and Risks

### 9.1 Same-value binding writes (LOW RISK)

If a binding writes the same value that's already in state:
- `BindingReducer.reduce()` still calls `bindingAction.set(&state)` unconditionally
- But `ObservationStateRegistrar.mutate()` checks `isIdentityEqual` and skips notification if identity matches
- For primitive types (String, Int, Bool), identity is always "not equal" (returns `false` from `_$isIdentityEqual<T>` for non-ObservableState types), BUT `shouldNotifyObservers` defaults to `{ _, _ in true }`
- **However**, even if observation fires, the async gap + Compose batching prevents loops
- **Mitigation:** The `Equatable` check in `BindingAction` itself prevents sending duplicate actions at the SwiftUI binding level

### 9.2 Binding write during body evaluation (MEDIUM RISK)

If a view modifier or `onAppear` synchronously writes a binding during body evaluation:
- `ObservationRecording.isRecording` would be `true`
- The write path would call `registrar.willSet()` which could interfere with recording
- **However**, `isEnabled = true` suppresses `bridgeSupport.willSet()`, and the actual state change goes through `send()` which is buffered by `isSending`
- **Mitigation:** This pattern is discouraged in SwiftUI generally and would behave the same on iOS

### 9.3 Task-local across JNI boundary (NO RISK)

`@TaskLocal` values are Swift-side only and don't cross JNI. But this is fine because:
- `BindingLocal.isActive` is only read in `IfLetCore.send()` on the Swift side
- The JNI calls (`MutableStateBacking.access/update`) don't read task-locals
- The async onChange handler runs in a new task context where `isActive == false`, which is correct

### 9.4 Multiple rapid binding writes (LOW RISK)

If a user types quickly in a TextField, generating rapid binding writes:
- Each write calls `store.send()` synchronously
- `RootCore.isSending` buffers concurrent sends
- Multiple onChange handlers queue via `DispatchQueue.main.async`
- Compose batches all updates into a single recomposition frame
- **No loop risk**, but potential for UI lag if reducer processing is slow

### 9.5 Effect-driven state changes during binding (LOW RISK)

If a binding write triggers an effect that synchronously sends another action:
- The effect action is processed via `receiveValue` on `UIScheduler.shared`
- This goes through `send()` which buffers via `isSending`
- No loop risk, but the observation notification from the effect's state change compounds with the binding's notification

---

## 10. Recommendations for Phase 4 Implementation

1. **No custom loop protection needed** for standard `@BindableAction` bindings. The existing layered protections (task-local, reentrancy guard, isEnabled suppression, async dispatch, Compose batching) are sufficient.

2. **Test same-value writes** to ensure `ObservationStateRegistrar.mutate()` correctly suppresses notification for equal values on Android.

3. **Test rapid-fire bindings** (e.g., TextField with debounce) to verify Compose batching works correctly under load.

4. **Avoid synchronous binding writes during body evaluation** in any Phase 4 example code.

5. **Monitor for `willSet` suppression correctness** -- the `isEnabled` flag is global and one-way. If it somehow doesn't get set (bridge load failure), `bridgeSupport.willSet()` would fire during mutations, causing synchronous `MutableStateBacking.update()` calls that could create loops. The `ViewObservation.init` block already logs this as a fatal error.
