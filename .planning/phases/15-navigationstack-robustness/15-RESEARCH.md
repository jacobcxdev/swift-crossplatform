# Phase 15: NavigationStack Android Robustness - Research

**Researched:** 2026-02-24
**Domain:** NavigationStack binding-driven push, JVM type erasure, dismiss JNI timing on Android
**Confidence:** HIGH

## Summary

Phase 15 fixes three P2 NavigationStack bugs on Android that were documented during Phase 10's gap audit. Each bug has a well-defined root cause traceable through the codebase:

1. **Binding-driven push** — `NavigationLink(state:)` wraps the user's state in `StackState.Component` and passes it as a `NavigationLink(value:)`. On Android, the `_TCANavigationStack` adapter creates a `Binding<NavigationPath>` whose `set:` closure handles pop but has a no-op comment for push ("push is handled by navigationDestination(for:) callback"). The `NavigationLink(value:)` in skip-fuse-ui passes a `SwiftHashable`-wrapped value to skip-ui's `Navigator.navigate(to:)`, which appends to the path binding. The issue is that the `_TCANavigationStack` binding's `set:` closure receives updated `NavigationPath` but doesn't dispatch `store.send(.push(...))` — it only handles the `newPath.count < currentCount` (pop) case.

2. **JVM type erasure** — `navigationDestination(for: StackState<State>.Component.self)` registers with key `String(describing: StackState<State>.Component.self)`. On JVM, generic type parameters are erased at runtime, so `StackState<A>.Component` and `StackState<B>.Component` produce identical keys. Single-destination is safe; multi-destination needs a type-discriminating key.

3. **Dismiss JNI timing** — `PresentationReducer` wires dismiss via `Empty(completeImmediately: false)` cancellable + `Just(.dismiss)` concatenation. `DismissEffect` calls `Task._cancel(id: PresentationDismissID())`, which cancels the `Empty` publisher, allowing `Just(.dismiss)` to fire. On Android, this chain crosses the JNI boundary, and the cancel-then-emit sequence appears to have timing issues under the full effect pipeline, causing `store.receive(\.destination.dismiss)` to never arrive in integration tests.

**Primary recommendation:** Fix each bug at its root cause (skip-fuse-ui/TCA adapter layers), with one plan per bug, comprehensive tests replacing `withKnownIssue` wrappers, validated on both Darwin and Android.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Claude determines optimal fix order based on code dependency analysis
- One plan per bug — each fix gets its own plan with isolated fix + test, verified independently
- All three bugs must be fixed in this phase — no deferral even if one proves significantly harder
- Fixes should target the root cause, going as deep as needed (skip-fuse-ui, skip-android-bridge, etc.) rather than patching at the TCA layer
- Remove `withKnownIssue` wrappers immediately when each fix lands, in the same plan
- Also clean up related workarounds (e.g., `#if os(Android)` guards, Effect.send workaround) that become redundant after a fix
- Revert the Effect.send workaround (Just publisher to run effect switch) back to the upstream Just publisher pattern if the dismiss timing root cause fix makes it unnecessary — minimise fork divergence
- Fork divergence policy: balance case-by-case — small divergence is acceptable, large divergence prefers upstream alignment
- Comprehensive tests for each fix: happy path + edge cases + regression guards
- Tests live in existing `examples/fuse-library/Tests/` target alongside other cross-platform tests
- Tests must pass on both Darwin (`swift test`) and Android (`skip android test`) — no platform-only test gates
- Use TCA `TestStore` where possible for action/state exhaustivity; fall back to direct `Store` only if TestStore has Android issues
- skip-fuse-ui API surface changes are acceptable if needed (SwiftUI-facing API should stay the same)
- No limit on how many forks a single fix can touch — fix it right across whatever forks the root cause requires
- Update the fuse-app example if fixes change navigation behaviour — demonstrate end-to-end functionality
- New files/modules in forks are fine — clean architecture over minimising file count

### Claude's Discretion
- Exact fix ordering across the three bugs
- Technical approach per bug (type tokens vs generics workaround, JNI timing strategy, etc.)
- Test naming and organisation within the existing test target
- Whether to inline small helpers or extract to new files

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NAV-02 | Path append pushes a new destination onto the navigation stack on Android | Bug 1 (binding-driven push): currently only reducer-driven push works; binding-driven push via `NavigationLink(state:)` needs the `_TCANavigationStack` adapter's set closure to dispatch `.push(...)` when `newPath.count > currentCount` |
| TCA-32 | `StackState<Element>` initializes, appends, and indexes by `StackElementID` on Android | Bug 1 & 2: StackState data operations work, but the UI-binding path (push via NavigationLink) and multi-destination type resolution (JVM erasure) need fixes for full correctness |
</phase_requirements>

## Standard Stack

### Core
| Library/Module | Location | Purpose | Role in Phase 15 |
|----------------|----------|---------|-------------------|
| skip-fuse-ui | `forks/skip-fuse-ui/Sources/SkipSwiftUI/Containers/Navigation.swift` | Swift-side NavigationStack/NavigationLink bridge to skip-ui | Binding-driven push fix location |
| swift-composable-architecture | `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/NavigationStack+Observation.swift` | TCA NavigationStack adapter for Android (`_TCANavigationStack`, `NavigationLink(state:)`) | Binding-driven push, type erasure fix location |
| swift-composable-architecture | `forks/swift-composable-architecture/Sources/ComposableArchitecture/Reducer/Reducers/PresentationReducer.swift` | Dismiss pipeline (`Empty` + `Just(.dismiss)` concatenation) | Dismiss timing fix location |
| skip-ui | `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/Navigation.swift` | Kotlin-side Navigator with destination key matching | Type erasure fix location (destination key resolution) |

### Supporting
| Library/Module | Location | Purpose | When Touched |
|----------------|----------|---------|--------------|
| swift-composable-architecture | `Sources/ComposableArchitecture/Dependencies/Dismiss.swift` | `DismissEffect` Android fallback path | If dismiss timing fix requires changes to the callAsFunction path |
| swift-composable-architecture | `Sources/ComposableArchitecture/Effect.swift` | `Effect.send` implementation (Just publisher) | Potential revert of Effect.send workaround if dismiss timing fix resolves underlying issue |
| fuse-app | `examples/fuse-app/Sources/FuseApp/ContactsFeature.swift` | End-to-end NavigationStack usage | Update if fixes change navigation behaviour |

## Architecture Patterns

### Pattern 1: Binding-Driven Push on Android (Bug 1)
**What:** When a user taps `NavigationLink(state:)`, TCA wraps the state in `StackState.Component` and passes it as `NavigationLink(value:)`. On iOS, the `NavigationStack.init(path:root:destination:)` extension handles this via the PathView binding setter. On Android, the `_TCANavigationStack` adapter bridges to skip-fuse-ui's `NavigationStack(path: Binding<NavigationPath>)`.

**Current flow on Android:**
```
1. NavigationLink(state: someState)
   → wraps in StackState.Component(id: stackElementID(), element: someState)
   → passes as NavigationLink(value: component)

2. skip-fuse-ui NavigationLink.Java_view
   → bridgedValue = Java_swiftHashable(for: component)
   → SkipUI.NavigationLink(bridgedDestination: nil, value: bridgedValue, bridgedLabel: ...)

3. skip-ui Navigator.navigate(to: targetValue)
   → path exists, so path.wrappedValue.append(targetValue)
   (path is the Binding<NavigationPath> from _TCANavigationStack)

4. _TCANavigationStack Binding<NavigationPath> set: closure fires
   → newPath.count > currentCount → COMMENT: "push is handled by callback, not path set"
   → NO store.send(.push(...)) dispatched ← BUG
```

**Fix approach:** The `_TCANavigationStack` binding's `set:` closure must extract the `StackState.Component` from the new path entry and dispatch `store.send(.push(id: component.id, state: component.element))` when `newPath.count > currentCount`.

**Key challenge:** The `NavigationPath` from skip-fuse-ui stores `AnyHashable` elements. The pushed value arrives as a `SwiftHashable`-wrapped `StackState.Component`. The `set:` closure needs to unwrap `SwiftHashable` → `AnyHashable` → `StackState.Component` to extract the `id` and `element`.

**Code location:** `NavigationStack+Observation.swift` lines 236-249 (`_TCANavigationStack.body` → `androidPath` binding).

### Pattern 2: Type-Discriminating Destination Key (Bug 2)
**What:** `navigationDestination(for:)` on skip-fuse-ui uses `String(describing: data)` as the destination key. On the lookup side, skip-ui's `Navigator` uses `destinationKeyTransformer(targetValue)` which calls `String(describing: type(of: value))` on the pushed value.

**Registration side (skip-fuse-ui):**
```swift
.navigationDestination(destinationKey: String(describing: data), bridgedDestination: ...)
// For TCA: data = StackState<State>.Component.self
// Key: "Component" (JVM erases generic parameter)
```

**Lookup side (skip-fuse-ui NavigationStack.Java_view):**
```swift
let destinationKeyTransformer: (Any) -> String = {
    let value = ($0 as! SwiftHashable).base
    return String(describing: type(of: value))
}
// For TCA: value = StackState<State>.Component instance
// Key: "Component" (JVM erases generic parameter)
```

**Why single-destination works:** With only one `navigationDestination(for:)` registration, the erased key always matches the only registered handler.

**Why multi-destination breaks:** Multiple `StackState<A>.Component` and `StackState<B>.Component` registrations produce identical `"Component"` keys → last registration wins.

**Fix approach:** Include the `Element` type name in the destination key. Options:
1. Override `destinationKeyTransformer` in `_TCANavigationStack` to produce keys like `"Component<ContactsFeature.Path.State>"` using a stored type token
2. Add a `destinationKey` property to `StackState.Component` that includes the element type name
3. Override `String(describing:)` on `StackState.Component` to include the generic parameter name (compile-time, not JVM-erased)

**Recommended:** Option 2 or 3 — embed type information at the Swift level before JVM erasure occurs. Use `String(describing: Element.self)` at `Component` creation time (in Swift, not at JVM runtime).

**Code locations:**
- `NavigationStack+Observation.swift` line 211: `.navigationDestination(for: StackState<State>.Component.self)`
- `NavigationStack+Observation.swift` lines 56-59: `destinationKeyTransformer` in `_TCANavigationStack`
- `forks/skip-fuse-ui/.../Navigation.swift` line 229: `navigationDestination(destinationKey:)`

### Pattern 3: Dismiss Effect Pipeline (Bug 3)
**What:** PresentationReducer sets up dismiss via:
```swift
presentEffects = .concatenate(
    .publisher { Empty(completeImmediately: false) }   // ← stays alive until cancelled
        ._cancellable(id: PresentationDismissID(), ...),
    .publisher { Just(self.toPresentationAction.embed(.dismiss)) }  // ← fires after cancel
)
```

When `await dismiss()` is called, `DismissEffect` executes `Task._cancel(id: PresentationDismissID())`. This cancels the `Empty` publisher, allowing `Just(.dismiss)` to fire and deliver `.destination(.dismiss)`.

**Android-specific issue:** The `Task._cancel → cancel publisher → Just fires → action delivered` chain crosses multiple async boundaries through the JNI bridge. The fuse-app integration tests show `store.receive(\.destination.dismiss)` never arrives even with 10-second timeouts.

**Hypothesis:** The publisher cancellation notification may not propagate synchronously through OpenCombine on Android, or the `Task.cancel(id:)` call may not complete its effect within the JNI effect pipeline timing. The `Empty(completeImmediately: false)` publisher uses OpenCombine's `Empty` type which depends on correct cancellation propagation.

**Investigation vectors:**
1. Check if `Task._cancel` on Android correctly resolves the `navigationIDPath` dependency before cancellation
2. Check if OpenCombine's `Empty` correctly signals cancellation to the concatenation operator
3. Check if the JNI boundary introduces an async hop that breaks the synchronous cancel→emit chain
4. Test with `Effect.run` instead of `Effect.publisher` to see if the async effect path works better on Android

**Potential fixes:**
- Replace `Empty + Just` concatenation with an `Effect.run`-based approach that uses `AsyncStream` continuation cancellation instead of publisher cancellation
- Add explicit `Task.yield()` or `MainActor.run` bridging to ensure the cancel propagates before checking for the next effect
- Use `withTaskCancellationHandler` in the dismiss effect to ensure cancellation is observed across the JNI boundary

**Code location:** `PresentationReducer.swift` lines 688-694 (dismiss pipeline), `StackReducer.swift` lines 647-656 (similar pattern for stack dismiss).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NavigationPath type bridging | Custom path wrapper | skip-fuse-ui's existing `NavigationPath` + `SwiftHashable` bridge | Bridge already handles AnyHashable wrapping/unwrapping |
| Destination key generation | Runtime reflection on JVM | Compile-time type name embedding in `Component` | JVM erases generics at runtime; only Swift-side type info is reliable |
| Effect cancellation mechanism | Custom cancellation tokens | TCA's existing `_cancellable`/`Task._cancel` machinery | The infrastructure is correct; the issue is timing, not mechanism |
| Publisher cancellation propagation | Custom publisher types | OpenCombine's existing operators | If OpenCombine has a bug, fix it there rather than working around in TCA |

**Key insight:** All three bugs are integration-level issues at the seam between Swift, JVM, and JNI. The individual components (TCA reducers, skip-ui navigation, OpenCombine publishers) work correctly in isolation — the bugs appear at the crossing points.

## Common Pitfalls

### Pitfall 1: SwiftHashable Unwrapping on Android
**What goes wrong:** Values crossing the JNI bridge are wrapped in `SwiftHashable`. Code that expects raw Swift types (e.g., `StackState.Component`) receives `SwiftHashable`-wrapped versions.
**Why it happens:** skip-fuse-ui's `Java_swiftHashable(for:)` wraps all values for JVM interop.
**How to avoid:** Always unwrap via `(value as! SwiftHashable).base as! ExpectedType` when reading values from skip-ui callbacks. The existing `destinationKeyTransformer` closure in `NavigationStack.Java_view` shows the correct pattern.
**Warning signs:** `as?` casts returning nil, `type(of:)` showing `SwiftHashable` instead of expected type.

### Pitfall 2: JVM Type Erasure of Swift Generics
**What goes wrong:** `String(describing: SomeGeneric<T>.self)` produces the same string for all `T` on JVM.
**Why it happens:** JVM erases generic type parameters at runtime. `StackState<A>.Component` and `StackState<B>.Component` are the same JVM class.
**How to avoid:** Capture type information at Swift compile time (e.g., store `String(describing: Element.self)` as a stored property on `Component` or pass it as a parameter). Never rely on `type(of:)` or `String(describing:)` for generic types at JVM runtime.
**Warning signs:** Multiple `navigationDestination(for:)` registrations resolving to the same handler.

### Pitfall 3: Publisher Cancellation Timing Across JNI
**What goes wrong:** Synchronous cancel→emit chains that work on Darwin may not propagate correctly through the JNI effect pipeline.
**Why it happens:** JNI boundary may introduce async hops or thread transitions that break the assumption that cancellation propagates synchronously.
**How to avoid:** Prefer `Effect.run` with `AsyncStream` patterns over `Effect.publisher` with `Empty + Just` for cross-boundary effect chains. Use explicit `await` points to ensure async boundaries are crossed.
**Warning signs:** `TestStore.receive` timing out, effects that work in unit tests but fail in integration tests.

### Pitfall 4: Testing Push Without SwiftUI Runtime
**What goes wrong:** Tests that validate push via `store.send(.push(...))` pass, but binding-driven push via `NavigationLink(state:)` fails because it requires the SwiftUI/skip-fuse-ui view hierarchy.
**Why it happens:** The binding-driven push path goes through view-level code (`NavigationLink` → `Navigator` → path binding → store). Reducer-level tests bypass this entirely.
**How to avoid:** Test the binding adapter's `set:` closure directly by constructing the `Binding<NavigationPath>` and exercising it with Component values. This tests the push dispatch path without requiring a running view hierarchy.
**Warning signs:** All reducer tests passing but binding-driven push not working in the app.

### Pitfall 5: Effect.send Workaround Reversion
**What goes wrong:** Reverting the Effect.send workaround (Just → run effect switch) before confirming dismiss timing is fixed causes dismiss to break again.
**Why it happens:** The workaround may mask the dismiss timing issue rather than being a separate concern.
**How to avoid:** Fix dismiss timing first, verify with the workaround still in place, then revert the workaround and verify again. If reversion breaks dismiss, the workaround addresses a different issue than the timing fix.
**Warning signs:** Dismiss tests passing with workaround, failing after reversion.

## Code Examples

### Binding-Driven Push Fix (Bug 1)
```swift
// In _TCANavigationStack.body — androidPath Binding<NavigationPath> set: closure
// BEFORE (broken):
set: { newPath in
    let currentCount = store.currentState.count
    if newPath.count > currentCount {
        // Push: Note: NavigationPath doesn't expose elements, so push is handled
        // by navigationDestination(for:) callback, not by path set
    } else if newPath.count < currentCount {
        store.send(.popFrom(id: store.currentState.ids[newPath.count]))
    }
}

// AFTER (fixed):
set: { newPath in
    let currentCount = store.currentState.count
    if newPath.count > currentCount {
        // Extract the pushed Component from the last path element
        // NavigationPath stores AnyHashable elements; the Component arrives
        // as SwiftHashable-wrapped StackState<State>.Component
        let lastElement = newPath[newPath.count - 1]
        // Unwrap SwiftHashable → Component
        if let component = lastElement as? StackState<State>.Component {
            store.send(.push(id: component.id, state: component.element))
        }
    } else if newPath.count < currentCount {
        store.send(.popFrom(id: store.currentState.ids[newPath.count]))
    }
}
```

**Note:** The exact unwrapping depends on how `SwiftHashable` wraps the value. The Component may arrive as `(SwiftHashable).base` → `AnyHashable` → `StackState<State>.Component`. Testing will reveal the exact unwrapping chain needed.

### Type-Discriminating Key Fix (Bug 2)
```swift
// Option A: Add destinationTypeKey to Component
extension StackState {
    public struct Component: Hashable {
        public let id: StackElementID
        public var element: Element
        // New: compile-time type name, not JVM-erased
        public let elementTypeName: String

        public init(id: StackElementID, element: Element) {
            self.id = id
            self.element = element
            self.elementTypeName = String(describing: Element.self)
        }
    }
}

// Override destinationKeyTransformer in _TCANavigationStack
let destinationKeyTransformer: (Any) -> String = {
    let value = ($0 as! SwiftHashable).base
    if let component = value as? StackState<State>.Component {
        return "Component<\(component.elementTypeName)>"
    }
    return String(describing: type(of: value))
}

// And on registration side in _NavigationDestinationViewModifier:
.navigationDestination(
    for: StackState<State>.Component.self,
    // Pass key that includes State type name
    destinationKey: "Component<\(String(describing: State.self))>"
)
```

**Note:** The registration side also needs to produce a matching key. This may require a new `navigationDestination(for:destinationKey:destination:)` overload in skip-fuse-ui, or the key can be baked into a custom `destinationKey` property.

### Dismiss Timing Fix (Bug 3 — investigative)
```swift
// Potential fix: Replace publisher-based dismiss with Effect.run
// In PresentationReducer, replace:
presentEffects = .concatenate(
    .publisher { Empty(completeImmediately: false) }
        ._cancellable(id: PresentationDismissID(), ...),
    .publisher { Just(self.toPresentationAction.embed(.dismiss)) }
)

// With Effect.run-based approach:
presentEffects = Effect.run { send in
    try await withTaskCancellationHandler {
        // Wait indefinitely until cancelled
        try await Task.sleep(for: .seconds(86400 * 365))
    } onCancel: {
        // Cancellation triggers dismiss action delivery
    }
    // After cancellation, send dismiss
    await send(self.toPresentationAction.embed(.dismiss))
}
._cancellable(id: PresentationDismissID(), ...)
```

**Warning:** This is speculative. The actual fix requires diagnosing whether the issue is in OpenCombine's `Empty` cancellation, the concatenation operator, or the JNI async boundary. The fix should be validated empirically.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NavigationStackStore` (deprecated) | `NavigationStack(path:root:destination:)` with binding scope | TCA 1.7+ | Modern pattern is what Phase 15 fixes target |
| Type-based destination keys | String-based destination keys (skip-fuse-ui bridge) | Skip Fuse mode | JVM erasure makes type-based keys unreliable |
| `Effect.publisher { Just(...) }` for sync dispatch | `Effect.send(...)` uses same Just internally | Current | Upstream pattern uses Just; any workaround should be reverted if possible |

## Open Questions

1. **NavigationPath element access on Android**
   - What we know: skip-fuse-ui's `NavigationPath` stores `[AnyHashable]` internally with a subscript accessor
   - What's unclear: Whether the pushed `StackState.Component` survives the `Java_swiftHashable` → `NavigationPath.append` → `NavigationPath[index]` round-trip with its type intact
   - Recommendation: Write a focused unit test that round-trips a `StackState.Component` through `NavigationPath` on Android to verify type preservation before implementing the push fix

2. **OpenCombine Empty cancellation on Android**
   - What we know: The dismiss pipeline relies on `Empty(completeImmediately: false)` being cancelled, triggering the concatenated `Just(.dismiss)` to fire
   - What's unclear: Whether OpenCombine's `Empty` correctly signals completion-on-cancel through the `Concatenate` subscriber on Android
   - Recommendation: Write a focused test of `Empty + Just` concatenation with cancellation on Android. If this test fails, the fix is in OpenCombine, not in TCA

3. **Effect.send workaround scope**
   - What we know: The CONTEXT.md mentions reverting "Effect.send workaround (Just publisher → run effect switch)" if dismiss timing is root-cause fixed
   - What's unclear: The current `Effect.send` in Effect.swift line 150 uses `Just(action).eraseToAnyPublisher()` (upstream pattern). If there WAS a workaround, it may have already been reverted, or it may be in a different location
   - Recommendation: Search for any non-upstream `Effect.send` or run-based effect dispatch changes before planning the reversion task. The current code appears to be the upstream Just pattern already

4. **Multi-destination real-world scenario**
   - What we know: Current apps use single-destination `NavigationStack`. Multi-destination requires multiple `navigationDestination(for:)` calls with different `StackState<X>.Component` types
   - What's unclear: Whether TCA's NavigationStack extension actually supports multiple `navigationDestination(for:)` calls with different State types, or if it always uses a single enum path
   - Recommendation: The canonical TCA pattern uses a single `@Reducer enum Path` with one `navigationDestination(for: StackState<Path.State>.Component.self)`. Multi-destination may only be relevant for non-TCA usage. Validate with the `/pfw-composable-architecture` skill patterns

## Sources

### Primary (HIGH confidence)
- `NavigationStack+Observation.swift` — full source read, `_TCANavigationStack` adapter analysis
- `forks/skip-fuse-ui/.../Navigation.swift` — full source read, binding and key bridging analysis
- `forks/skip-ui/.../Navigation.swift` — full source read (1100+ lines), Navigator keyed navigation, destinationIndexes, key resolution
- `PresentationReducer.swift` — full source read, dismiss pipeline (`Empty + Just` concatenation, `PresentationDismissID`)
- `Dismiss.swift` — full source read, `DismissEffect` Android fallback path
- `Effect.swift` — `Effect.send` implementation verified as upstream Just pattern
- `10-GAP-REPORT.md` — Phase 10 systematic audit documenting all three bugs with root cause analysis
- `15-CONTEXT.md` — User decisions constraining fix approach

### Secondary (MEDIUM confidence)
- `fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` — dismiss test evidence (10-second timeouts, `store.receive(\.destination.dismiss)`)
- `fuse-library/Tests/NavigationTests/` — existing test patterns for push/pop/dismiss
- `STATE.md` — project history, Phase 10 decisions on dismiss timing and JVM type erasure

### Tertiary (LOW confidence)
- OpenCombine `Empty` cancellation behaviour on Android — inferred from dismiss failure pattern, not directly tested
- `SwiftHashable` round-trip preservation through `NavigationPath` — inferred from architecture, needs empirical validation

## Metadata

**Confidence breakdown:**
- Binding-driven push: HIGH — root cause clearly identified in `_TCANavigationStack` set closure (no-op push branch)
- JVM type erasure: HIGH — mechanism well-understood from skip-ui source; fix pattern clear (embed type name at compile time)
- Dismiss timing: MEDIUM — root cause narrowed to publisher cancellation propagation across JNI, but exact failure point needs empirical diagnosis
- Architecture: HIGH — all relevant source files read and analysed; cross-fork dependency chain fully traced

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (stable domain — skip-fuse-ui and TCA fork APIs unlikely to change)
