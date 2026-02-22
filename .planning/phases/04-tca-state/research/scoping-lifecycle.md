# Store Scoping Lifecycle — ForEach, Optional, and Enum Case Switching on Android

**Completed:** 2026-02-22
**Scope:** Deep dive into Store scoping lifecycle for Phase 4 Android validation
**Source files audited:** 15 files across swift-composable-architecture and swift-case-paths forks

---

## Table of Contents

1. [ForEach Scoping (_StoreCollection)](#1-foreach-scoping-_storecollection)
2. [Optional Scoping](#2-optional-scoping)
3. [Enum Case Switching (store.case)](#3-enum-case-switching-storecase)
4. [IfLetCore Reducer](#4-ifletcore-reducer)
5. [Store.children Dictionary](#5-storechildren-dictionary)
6. [MainActor._assumeIsolated on Android](#6-mainactor_assumeisolated-on-android)
7. [IdentifiedArray Identity Stability](#7-identifiedarray-identity-stability)
8. [Teardown Side Effects](#8-teardown-side-effects)
9. [Android Risk Summary](#9-android-risk-summary)

---

## 1. ForEach Scoping (_StoreCollection)

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/IdentifiedArray+Observation.swift`

### How _StoreCollection Is Implemented

`_StoreCollection` is a `RandomAccessCollection` that wraps a store scoped to `IdentifiedArray<ID, State>`:

```
Store<ParentState, ParentAction>
  |
  scope(state: \.rows, action: \.rows)
  |
  Store<IdentifiedArray<ID, State>, IdentifiedAction<ID, Action>>
  |
  _StoreCollection (wraps this store)
  |
  subscript(position:) -> Store<State, Action>   (per-element child stores)
```

On initialization, `_StoreCollection`:
1. Calls `store._$observationRegistrar.access(store, keyPath: \.currentState)` to register observation tracking
2. Snapshots the current state: `self.data = store.withState { $0 }`
3. Records whether it was initialized inside perception tracking (`_isInPerceptionTracking`)

The subscript at each position creates or retrieves a child store by element ID.

### How Child Stores Are Cached in store.children

The subscript operates as follows:

```
subscript(position: Int) -> Store<State, Action> {
    precondition(Thread.isMainThread)        // [1] Guard
    MainActor._assumeIsolated {              // [2] Isolation bridge
        let elementID = data.ids[position]   // [3] Stable ID lookup
        let scopeID = store.id(              // [4] ScopeID derivation
            state: \.[id: elementID],
            action: \.[id: elementID]
        )
        if let child = store.children[scopeID] as? Store<State, Action> {
            return child                     // [5] Cache hit
        }
        // [6] Cache miss — create IfLetCore + child store
        return store.scope(id: scopeID, childCore: IfLetCore(...))
    }
}
```

### ScopeID Derivation

`ScopeID<State, Action>` is a `Hashable` struct containing:
- `state: PartialKeyPath<State>` — the key path `\IdentifiedArray.[id: elementID]`
- `action: PartialCaseKeyPath<Action>` — the case path `\IdentifiedAction.[id: elementID]`

Since `elementID` is baked into the key path subscript, two elements with the same ID always produce the same `ScopeID`, regardless of array position. Two elements with different IDs always produce different `ScopeID`s.

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` (lines 402-405)

```swift
@_spi(Internals) public struct ScopeID<State, Action>: Hashable {
    let state: PartialKeyPath<State>
    let action: PartialCaseKeyPath<Action>
}
```

### Thread.isMainThread on Android

The `precondition(Thread.isMainThread)` call is the first line of the subscript. On Android in Fuse mode, `Foundation.Thread` uses the real Swift runtime with pthreads. `Thread.isMainThread` checks whether the current thread is the main thread via `pthread_self() == pthread_main_thread_np()` (or equivalent). This works correctly because:

1. Swift's Foundation on Android provides `Thread.isMainThread`
2. Fuse mode uses native Swift threads (not JVM threads)
3. The main actor executor runs on the main thread

**Validated in Phase 3 research.**

### Android Lifecycle Diagram — ForEach

```
ForEach body evaluation (Compose recomposition)
  |
  store.scope(state: \.rows, action: \.rows)
  |
  _StoreCollection.init(scopedStore)
  |  registers observation via _$observationRegistrar.access()
  |  snapshots data = IdentifiedArray
  |
  For each position i:
    |
    _StoreCollection[i]
    |  precondition(Thread.isMainThread)   -- SAFE on Android
    |  MainActor._assumeIsolated { ... }   -- SAFE on Android (see section 6)
    |
    Lookup: elementID = data.ids[i]
    scopeID = ScopeID(state: \.[id: elementID], action: \.[id: elementID])
    |
    +-- Cache HIT:  store.children[scopeID] exists -> return it
    |
    +-- Cache MISS: create IfLetCore(base, cachedState, \.[id: elementID], \.[id: elementID])
                    store.scope(id: scopeID, childCore: ifLetCore)
                    -> creates child Store, stores in children[scopeID], returns it
```

---

## 2. Optional Scoping

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/Store+Observation.swift` (lines 84-116)

### Nil -> Non-Nil: Child Store Creation

```swift
public func scope<ChildState, ChildAction>(
    state stateKeyPath: KeyPath<State, ChildState?>,
    action actionKeyPath: CaseKeyPath<Action, ChildAction>,
    ...
) -> Store<ChildState, ChildAction>? {
    let id = id(state: stateKeyPath, action: actionKeyPath)
    guard let childState = state[keyPath: stateKeyPath]
    else {
        children[id] = nil  // Eagerly clean up
        return nil
    }
    // Create IfLetCore wrapping the optional state
    func open(_ core: some Core<State, Action>) -> any Core<ChildState, ChildAction> {
        IfLetCore(base: core, cachedState: childState, stateKeyPath: stateKeyPath, actionKeyPath: actionKeyPath)
    }
    return scope(id: id, childCore: open(core))
}
```

When state transitions from `nil` to non-nil:
1. `state[keyPath: stateKeyPath]` returns a value
2. An `IfLetCore` is created with the current child state as `cachedState`
3. `store.scope(id:childCore:)` checks `children[id]` — cache miss on first appearance
4. A new `Store<ChildState, ChildAction>` is created, stored in `children[id]`, and returned

### Non-Nil -> Nil: Child Store Destruction

When state transitions from non-nil to `nil`:
1. `state[keyPath: stateKeyPath]` returns nil
2. `children[id] = nil` explicitly removes the cached child store
3. Returns `nil`

The cleanup is **eager** — the TODO comment `// TODO: Eager?` in the source suggests this was a deliberate design choice. The child store is removed from the cache immediately when the optional scope returns nil.

### Memory Leak Risk

**Low risk.** The child store removal path is straightforward:

```
Optional state goes nil
  -> scope() called during next view evaluation
  -> guard fails (state is nil)
  -> children[id] = nil (removes strong reference)
  -> child Store has no other strong references
  -> child Store deallocated (deinit runs)
```

The potential leak scenario is if `scope()` is never called again after state goes nil (e.g., the parent view stops rendering). In that case, `children[id]` retains the child store. However:

- The child store's `IfLetCore.isInvalid` returns `true` when `base.state[keyPath: stateKeyPath] == nil`
- The `parentCancellable` in `Store.init` subscribes to `core.didSet` and calls `parent?.removeChild(scopeID:)` after a 300ms delay when the observable state's `_$id` changes
- On `Store.deinit`, the parent-child reference chain breaks naturally

**No `#if os(Android)` guards** in the optional scoping code path.

### Optional Scoping Lifecycle Diagram

```
[State: .child = nil]
  |
  store.scope(state: \.child, action: \.child)
  -> returns nil
  -> children[id] = nil (cleanup)

[State: .child = ChildState()]     // nil -> non-nil
  |
  store.scope(state: \.child, action: \.child)
  -> creates IfLetCore(base: parentCore, cachedState: childState, ...)
  -> children[id] = Store(core: ifLetCore)
  -> returns Store<ChildState, ChildAction>

[State: .child = updatedState]     // non-nil -> non-nil (same identity)
  |
  store.scope(state: \.child, action: \.child)
  -> children[id] already exists (cache hit)
  -> IfLetCore.state reads base.state[keyPath: \\.child?] ?? cachedState
  -> returns existing cached Store (same object identity)

[State: .child = nil]              // non-nil -> nil
  |
  store.scope(state: \.child, action: \.child)
  -> guard fails
  -> children[id] = nil (child store released)
  -> returns nil
  -> _IfLetReducer cancels child effects (see section 8)
```

---

## 3. Enum Case Switching (store.case)

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/CaseReducer.swift`

### The `case` Property

```swift
extension Store where State: CaseReducerState, State.StateReducer.Action == Action {
    public var `case`: State.StateReducer.CaseScope {
        State.StateReducer.scope(self)
    }
}
```

This delegates to `StateReducer.scope(_:)`, which is a **macro-generated** static method.

### Macro-Generated CaseScope and scope()

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitectureMacros/ReducerMacro.swift` (lines 386-413)

For a `@Reducer enum Destination { case featureA(FeatureA); case featureB(FeatureB) }`, the macro generates:

```swift
// CaseScope enum — one case per reducer case, wrapping a scoped Store
public enum CaseScope {
    case featureA(StoreOf<FeatureA>)
    case featureB(StoreOf<FeatureB>)
}

// scope() — switches on current state, creates optional-scoped child stores
@preconcurrency @MainActor
public static func scope(_ store: Store<State, Action>) -> CaseScope {
    switch store.state {
    case .featureA:
        return .featureA(store.scope(state: \.featureA, action: \.featureA)!)
    case .featureB:
        return .featureB(store.scope(state: \.featureB, action: \.featureB)!)
    }
}
```

**Key insight:** `store.scope(state: \.featureA, action: \.featureA)` calls the **optional scoping** method (section 2), since `@CasePathable` enum case key paths produce optional key paths (`KeyPath<State, FeatureA.State?>`). The force-unwrap `!` is safe because we already matched the case in the `switch`.

### How EnumMetadata.tag(of:) Is Used

`EnumMetadata.tag(of:)` is NOT directly called by `store.case` or the macro-generated `scope()`. Instead, it is used **indirectly** through:

1. **CaseKeyPath extraction** — when `@CasePathable` enums use case key paths like `\.featureA`, the underlying `AnyCasePath.extract` calls `EnumMetadata.tag(of:)` to compare enum tags
2. **NavigationID** — when creating navigation IDs for cancellation, `NavigationID(base:keyPath:)` calls `EnumMetadata(Value.self)?.tag(of: base)` to capture the enum tag
3. **PresentationID** — `PresentationID(base:)` calls `EnumMetadata(Base.self)?.tag(of: base)` for identity tracking

**Source:** `forks/swift-case-paths/Sources/CasePaths/EnumReflection.swift` (lines 195-222)

```swift
@_spi(Reflection) public struct EnumMetadata {
    func tag<Enum>(of value: Enum) -> UInt32 {
        withUnsafePointer(to: value) {
            self.valueWitnessTable.getEnumTag($0, self.ptr)
        }
    }
}
```

This uses the Swift runtime's value witness table — a C function pointer stored in the type metadata. It reads a tag integer from the enum's memory representation. **This is ABI-level, works on any platform with the Swift runtime, including Android.** Validated in Phase 2 with 9 CasePaths tests.

### Lifecycle When Switching from Case A to Case B

```
[State: .featureA(FeatureA.State())]
  |
  store.case
  -> scope(store)
  -> switch store.state { case .featureA: ... }
  -> store.scope(state: \.featureA, action: \.featureA)
  -> cache miss for scopeID(.featureA)
  -> creates IfLetCore, child Store
  -> children[scopeID(.featureA)] = childStoreA
  -> returns CaseScope.featureA(childStoreA)

[State mutates: .featureA -> .featureB]
  |
  Reducer runs:
    _PresentationReducer detects presentationIdentityChanged
    -> cancels all effects scoped to featureA's navigationIDPath
    -> presentEffects for featureB
  |
  View re-evaluates (observation fires):
  store.case
  -> scope(store)
  -> switch store.state { case .featureB: ... }
  -> store.scope(state: \.featureB, action: \.featureB)
     -> cache miss for scopeID(.featureB)
     -> creates IfLetCore for featureB, child Store
     -> children[scopeID(.featureB)] = childStoreB
  -> store.scope(state: \.featureA, action: \.featureA)
     -> NOT called (switch only enters .featureB branch)
     -> childStoreA remains in children cache until...
     -> IfLetCore.isInvalid returns true (state is nil)
     -> parentCancellable fires after 300ms delay
     -> parent.removeChild(scopeID: .featureA)

  -> returns CaseScope.featureB(childStoreB)
```

**Note on stale cache entries:** When switching from case A to B, the `children[scopeID(.featureA)]` entry is NOT immediately cleaned up by the `scope()` call. It persists until either:
1. `scope(state: \.featureA, action: \.featureA)` is called and returns nil (eagerly cleaning up)
2. The `parentCancellable`'s 300ms deferred cleanup fires (detecting `_$id` change via `IfLetCore.isInvalid`)
3. The parent store itself is deallocated

This is a benign leak bounded by the number of enum cases (typically small: 2-5).

---

## 4. IfLetCore (Store-Level Core)

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Core.swift` (lines 275-327)

### Purpose

`IfLetCore` is the `Core` implementation used for **optional and collection element scoping**. It wraps a base core and reads child state through an optional key path.

```swift
final class IfLetCore<Base: Core, State, Action>: Core {
    let base: Base
    var cachedState: State                           // Last known non-nil state
    let stateKeyPath: KeyPath<Base.State, State?>    // Optional path into parent
    let actionKeyPath: CaseKeyPath<Base.Action, Action>
}
```

### State Access Pattern

```swift
var state: State {
    let state = base.state[keyPath: stateKeyPath] ?? cachedState
    cachedState = state
    return state
}
```

This is a **read-through cache** pattern:
- If parent state still has a value at the optional key path, use it and update the cache
- If parent state is nil, return the last cached (stale) value
- This prevents crashes when the view reads state after the parent has nil'd it but before the view has been removed

### Invalidity

```swift
var isInvalid: Bool {
    base.state[keyPath: stateKeyPath] == nil || base.isInvalid
}
```

An `IfLetCore` becomes invalid when:
1. The parent state's optional property is nil
2. The base core itself is invalid (recursive — e.g., grandparent also nil'd)

### Action Sending Guard

```swift
func send(_ action: Action) -> Task<Void, Never>? {
    if BindingLocal.isActive && isInvalid {
        return nil  // Suppress binding actions to invalid stores
    }
    return base.send(actionKeyPath(action))
}
```

When a binding tries to send an action to an invalid store (state already nil), the action is silently dropped. This prevents crashes from stale bindings.

### No Platform Guards

`IfLetCore` has **zero** `#if os(Android)` or platform-conditional code. It is pure Swift generics. Safe on Android.

---

## 5. Store.children Dictionary

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` (line 108)

### Definition

```swift
public final class Store<State, Action> {
    var children: [ScopeID<State, Action>: AnyObject] = [:]
}
```

- **Key:** `ScopeID<State, Action>` — a pair of `(PartialKeyPath<State>, PartialCaseKeyPath<Action>)`
- **Value:** `AnyObject` — always a `Store<ChildState, ChildAction>` (type-erased)

### How Entries Are Added

In `Store.scope(id:childCore:)` (lines 283-299):

```swift
func scope<ChildState, ChildAction>(
    id: ScopeID<State, Action>?,
    childCore: @autoclosure () -> any Core<ChildState, ChildAction>
) -> Store<ChildState, ChildAction> {
    guard core.canStoreCacheChildren, let id,
          let child = children[id] as? Store<ChildState, ChildAction>
    else {
        let child = Store<ChildState, ChildAction>(core: childCore(), scopeID: id, parent: self)
        if core.canStoreCacheChildren, let id {
            children[id] = child    // <-- ADDED HERE
        }
        return child
    }
    return child  // Cache hit
}
```

### How Entries Are Removed

Three removal paths:

1. **Eager removal in optional scope** (Store+Observation.swift line 104):
   ```swift
   children[id] = nil  // When state goes nil
   ```

2. **Deferred removal via parentCancellable** (Store.swift lines 346-364):
   ```swift
   // In Store.init — subscribes to core.didSet
   // When _$id changes (state identity shift):
   DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
       parent?.removeChild(scopeID: scopeID)
   }
   ```

3. **Protocol-based removal** (Store.swift lines 112-114):
   ```swift
   func removeChild(scopeID: AnyHashable) {
       children[scopeID as! ScopeID<State, Action>] = nil
   }
   ```

### Thread Safety

The `children` dictionary is **not explicitly thread-safe**. It relies on:
- `Store` being `@MainActor`-isolated (all access must be on the main actor)
- `precondition(Thread.isMainThread)` in `_StoreCollection.subscript`
- `MainActor._assumeIsolated` wrapping all children access

This is safe on Android because Fuse mode's main actor executor runs on the main thread, same as iOS.

### #if os(Android) Guards

**None** in the children dictionary code. The only Android-related code in Store.swift is:
- Line 7-9: `#if os(Android) import SkipAndroidBridge`
- Lines 119-127: Three-way `_$observationRegistrar` conditional (PerceptionRegistrar / SkipAndroidBridge / Observation)
- Line 205: `#if canImport(SwiftUI) && !os(Android)` for animation-parameterized `send`

---

## 6. MainActor._assumeIsolated on Android

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Internal/AssumeIsolated.swift`

### Implementation

```swift
extension MainActor {
    static func _assumeIsolated<T: Sendable>(
        _ operation: @MainActor () throws -> T,
        file: StaticString = #fileID,
        line: UInt = #line
    ) rethrows -> T {
        #if swift(<5.10)
            // Manual check: Thread.isMainThread + unsafeBitCast
            guard Thread.isMainThread else {
                fatalError("Incorrect actor executor assumption")
            }
            return try withoutActuallyEscaping(operation) { fn in
                try unsafeBitCast(fn, to: (() throws -> T).self)()
            }
        #else
            return try assumeIsolated(operation, file: file, line: line)
        #endif
    }
}
```

On Swift 5.10+ (which this project targets), it delegates to `MainActor.assumeIsolated()` — the stdlib implementation. This calls `swift_task_isCurrentExecutor()` at runtime to verify the current executor matches the main actor executor.

### Android Safety

**Confirmed safe in Fuse mode:**
- Swift 6.2+ runtime on Android has full actor executor support
- `MainActor.assumeIsolated()` works because the main actor uses libdispatch's main queue, which runs on the main thread
- `Thread.isMainThread` (the fallback path) also works via Foundation on Android
- Phase 3 research explicitly validated this: "The `_assumeIsolated` implementation itself (AssumeIsolated.swift) on Swift 5.10+ delegates to `assumeIsolated()` (the real stdlib API). Both paths are safe."

### Usage in _StoreCollection.subscript

```swift
public subscript(position: Int) -> Store<State, Action> {
    precondition(Thread.isMainThread, ...)    // Belt
    return MainActor._assumeIsolated { ... }  // Suspenders
}
```

Both the precondition and the `_assumeIsolated` call serve as redundant safety checks. The precondition fires first (with a descriptive error message about lazy views), then `_assumeIsolated` grants main-actor-isolated access to the closure body.

---

## 7. IdentifiedArray Identity Stability

### Reorder Scenario

When an `IdentifiedArray` is reordered (same elements, different positions), the Store scoping **correctly reuses child stores by ID, not by position**.

Proof from `_StoreCollection.subscript`:

```swift
let elementID = self.data.ids[position]
let scopeID = self.store.id(state: \.[id: elementID], action: \.[id: elementID])
guard let child = self.store.children[scopeID] ...
```

The `position` is used only to look up the `elementID`. The `scopeID` is derived from `elementID`, not `position`. Therefore:

```
Before reorder:  [A, B, C]  positions [0, 1, 2]
                  scopeID(A) -> children[A]
                  scopeID(B) -> children[B]
                  scopeID(C) -> children[C]

After reorder:   [C, A, B]  positions [0, 1, 2]
                  position 0 -> elementID = C -> scopeID(C) -> children[C] (cache HIT)
                  position 1 -> elementID = A -> scopeID(A) -> children[A] (cache HIT)
                  position 2 -> elementID = B -> scopeID(B) -> children[B] (cache HIT)
```

All three child stores are reused. No stores are created or destroyed. **Identity is stable across reorders.**

### Add/Remove Scenario

```
Before: [A, B, C]
After:  [A, D, C]   (B removed, D added)

  scopeID(A) -> cache HIT  (reused)
  scopeID(D) -> cache MISS (new child store created)
  scopeID(C) -> cache HIT  (reused)

  children[scopeID(B)] -> still in cache (stale)
  -> _ForEachReducer.reduce() detects idsBefore.subtracting(idsAfter) = {B}
  -> cancels effects for B via ._cancel(id: NavigationID(id: B, ...), ...)
  -> child store for B eventually removed via parentCancellable (300ms) or next nil scope call
```

### Android Implications

No Android-specific concerns. `IdentifiedArray` is pure Swift (validated Phase 2). The identity-based caching depends only on `Hashable` conformance of element IDs, which is ABI-stable across platforms.

---

## 8. Teardown Side Effects

### When a Child Store Is Destroyed

There are **two layers** of cleanup when child state goes away:

#### Layer 1: Reducer-Level Effect Cancellation

**_IfLetReducer** (`Reducer/Reducers/IfLetReducer.swift` lines 246-279):

```swift
public func reduce(into state: inout Parent.State, action: Parent.Action) -> Effect<Parent.Action> {
    let childEffects = self.reduceChild(into: &state, action: action)

    let childIDBefore = state[keyPath: toChildState].map {
        NavigationID(base: $0, keyPath: toChildState)
    }
    let parentEffects = self.parent.reduce(into: &state, action: action)
    let childIDAfter = state[keyPath: toChildState].map {
        NavigationID(base: $0, keyPath: toChildState)
    }

    // If child identity changed (including nil'd out), cancel child effects
    let childCancelEffects: Effect<Parent.Action>
    if let childID = childIDBefore, childID != childIDAfter {
        childCancelEffects = ._cancel(id: childID, navigationID: self.navigationIDPath)
    } else {
        childCancelEffects = .none
    }

    return .merge(childEffects, parentEffects, childCancelEffects)
}
```

**Key behaviors:**
- Child reducer runs FIRST (before parent), so child can handle its actions while state exists
- Parent reducer runs SECOND, may nil out child state
- After both run, compare `childIDBefore` vs `childIDAfter`
- If identity changed or state went nil, emit `._cancel(id:navigationID:)` effect
- This cancels ALL in-flight effects scoped to that child's `NavigationID`

#### Layer 1b: _ForEachReducer Effect Cancellation

**_ForEachReducer** (`Reducer/Reducers/ForEachReducer.swift` lines 249-275):

```swift
let idsBefore = state[keyPath: toElementsState].ids
let parentEffects = self.parent.reduce(into: &state, action: action)
let idsAfter = state[keyPath: toElementsState].ids

let elementCancelEffects =
    areOrderedSetsDuplicates(idsBefore, idsAfter)
    ? .none
    : .merge(
        idsBefore.subtracting(idsAfter).map {
            ._cancel(id: NavigationID(id: $0, keyPath: toElementsState), navigationID: navigationIDPath)
        }
    )
```

For each element ID that was removed from the `IdentifiedArray`, a cancel effect is emitted.

#### Layer 1c: _PresentationReducer Effect Cancellation (Enum/Navigation)

**_PresentationReducer** (`Reducer/Reducers/PresentationReducer.swift` lines 660-675):

```swift
let presentationIdentityChanged =
    initialPresentationState.presentedID
    != state[keyPath: toPresentationState].wrappedValue.map(navigationIDPath(for:))

let dismissEffects: Effect<Base.Action>
if presentationIdentityChanged,
   let presentedPath = initialPresentationState.presentedID,
   initialPresentationState.wrappedValue.map({
       navigationIDPath(for: $0) == presentedPath && !isEphemeral($0)
   }) ?? true
{
    dismissEffects = ._cancel(navigationID: presentedPath)
} else {
    dismissEffects = .none
}
```

When presentation identity changes (case A -> case B, or non-nil -> nil), ALL effects scoped to the old presentation's `NavigationIDPath` are cancelled. This covers:
- `.dismiss` action handling
- Case switching in `@Reducer enum` destinations
- Identity change within the same case (e.g., presenting a different detail)

#### Layer 2: Store-Level Cleanup

The child `Store` object is removed from `parent.children[]`:
- **Eagerly** when optional scope returns nil (`children[id] = nil`)
- **Deferred** (300ms) when the `parentCancellable` fires on `_$id` change

#### Cancellation Mechanism

**Source:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Effects/Cancellation.swift`

Effects are registered in `_cancellationCancellables` (a `LockIsolated<CancellablesCollection>`):

```swift
class CancellablesCollection {
    var storage: [_CancelID: Set<AnyCancellable>] = [:]

    func cancel(id: some Hashable, path: NavigationIDPath) {
        let cancelID = _CancelID(id: id, navigationIDPath: path)
        storage[cancelID]?.forEach { $0.cancel() }
        storage[cancelID] = nil
    }
}
```

`_CancelID` combines:
- The cancellation identifier (e.g., `NavigationID` or `_PresentedID`)
- The `NavigationIDPath` (hierarchical scope path)
- A `testIdentifier` for test isolation

When `._cancel(id:navigationID:)` fires, it looks up all cancellables at that `(id, path)` combination and cancels them. This cancels:
- In-flight publisher effects (via `PassthroughSubject` completion)
- In-flight `Task`s (via `Task.cancel()`)

### Teardown Lifecycle Diagram

```
[Action dispatched that nils child state]
  |
  _IfLetReducer.reduce():
    1. reduceChild() -- child handles action (state still exists)
    2. parent.reduce() -- parent nils child state
    3. childIDBefore != childIDAfter? YES
    4. emit ._cancel(id: childNavigationID, navigationID: parentPath)
  |
  RootCore processes effects:
    ._cancel effect runs synchronously:
      _cancellationCancellables.cancel(id: childNavID, path: parentPath)
      -> all in-flight effects for child are cancelled
      -> publisher effects: PassthroughSubject sends completion
      -> run effects: Task.cancel() called
  |
  Store-level:
    observation fires (state changed)
    view re-evaluates
    scope(state: \.child, action: \.child) -> nil
    children[scopeID] = nil  (child store released)
  |
  Child Store.deinit:
    "StoreOf<Child>.deinit" logged
```

### Android-Specific Concerns

**None identified.** The entire cancellation mechanism is:
- `LockIsolated` for thread safety (validated Phase 3)
- `AnyCancellable` from OpenCombine/Combine (validated Phase 3)
- `Task.cancel()` using Swift concurrency (works in Fuse mode)
- `NavigationID` using `EnumMetadata.tag(of:)` (validated Phase 2)

No `#if os(Android)` guards in any of the cancellation code.

---

## 9. Android Risk Summary

| Component | Risk | Reason |
|-----------|------|--------|
| `_StoreCollection` subscript | **LOW** | `Thread.isMainThread` + `_assumeIsolated` both validated on Android |
| `IfLetCore` state caching | **NONE** | Pure Swift generics, no platform code |
| Optional scope create/destroy | **NONE** | No platform guards, standard dictionary operations |
| Enum case switching | **LOW** | Depends on `EnumMetadata.tag(of:)` (validated Phase 2) and macro-generated code (compile-time) |
| `store.children` dictionary | **NONE** | `@MainActor`-isolated, no platform guards |
| Effect cancellation on teardown | **NONE** | `LockIsolated` + `AnyCancellable` + `Task.cancel()` all validated |
| `NavigationID` identity | **LOW** | Uses `EnumMetadata.tag(of:)` for enum tag — ABI-stable, validated |
| `_ForEachReducer` element cleanup | **NONE** | Pure Swift, `OrderedSet.subtracting()` for ID diffing |
| `_PresentationReducer` dismiss | **NONE** | `NavigationIDPath`-based cancellation, no platform guards |
| IdentifiedArray reorder stability | **NONE** | ID-based caching, not position-based |

### Items Requiring Phase 4 Validation Tests

1. **ForEach scoping round-trip:** Add elements, remove elements, reorder — verify child stores cached/reused/destroyed correctly
2. **Optional scope lifecycle:** nil -> non-nil -> nil cycle — verify no memory leaks, effects cancelled
3. **Enum case switching:** case A -> case B — verify old case effects cancelled, new case store created
4. **Concurrent ForEach access:** Verify `precondition(Thread.isMainThread)` fires correctly on background thread (negative test)
5. **IfLetCore staleness:** After state goes nil, verify `isInvalid == true` and actions are dropped

### No Code Changes Needed

All scoping lifecycle code is platform-agnostic. The only Android-specific code in the Store layer is the `_$observationRegistrar` conditional (already patched in Phase 1). No new `#if os(Android)` guards are required for scoping to work on Android.

---

*Research completed: 2026-02-22*
*Source files audited: IdentifiedArray+Observation.swift, Store+Observation.swift, Store.swift, Core.swift, CaseReducer.swift, ReducerMacro.swift, IfLetReducer.swift, ForEachReducer.swift, PresentationReducer.swift, Cancellation.swift, AssumeIsolated.swift, EnumReflection.swift, NavigationID.swift, PresentationID.swift*
*Confidence: HIGH — all scoping lifecycle code is pure Swift with no platform conditionals*
