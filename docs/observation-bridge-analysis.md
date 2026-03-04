# Observation Bridge Analysis (2026-02-19)

## Root Cause: Infinite Recomposition Loop

### The Generated Bridge Code (Smoking Gun)

Skip's build plugin generates `Swift_composableBody` for each view:

```swift
@_cdecl("Java_service_app_ContentView_Swift_1composableBody")
public func ContentView_Swift_composableBody(...) -> JavaObjectPointer? {
    let peer_swift: SwiftValueTypeBox<ContentView> = Swift_peer.pointee()!
    return SkipBridge.assumeMainActorUnchecked {
        let body = peer_swift.value.body  // ← NO observation wrapping
        return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
    }
}
```

This JNI function is called from a Kotlin `@Composable` context. The body is evaluated **raw** — no `withObservationTracking`, no `withPerceptionTracking`.

Generated bridge files location:
`.build/plugins/outputs/service-app/ServiceApp/destination/skipstone/SkipBridgeGenerated/`

### How iOS Works (Reference)

```
SwiftUI internally:
  withObservationTracking {
    body()                    ← tracks keypath accesses
  } onChange: {
    scheduleRerender()        ← fires ONCE, then auto-cancels
  }
```

- SwiftUI wraps body eval with `withObservationTracking`
- When any tracked property changes, onChange fires ONCE
- SwiftUI schedules a single re-render
- On next body eval, tracking re-enters

### How Android Works (Current — Broken)

```
skip-android-bridge ObservationRegistrar:
  access() → bridgeSupport.access() → JNI → MutableStateBacking.access(index)
           → reads MutableState<Int>.value → registers Compose snapshot dependency
           → ALSO registrar.access() → Swift Observation (but nobody listens)

  withMutation() → bridgeSupport.willSet() → JNI → MutableStateBacking.update(index)
                 → MutableState<Int>.value += 1 → triggers Compose recomposition
                 → ALSO registrar.withMutation() → Swift Observation (but nobody listens)
```

- MutableStateBacking uses integer COUNTERS, not actual values
- Every withMutation() increments, ALWAYS triggers recomposition
- Swift Observation is completely passive (no withObservationTracking wrapping)
- TCA's `_$id` UUID changes on every `_$willModify()`, so `removeDuplicates()` never filters
- Result: every state assignment → withMutation → counter++ → recomposition → repeat

### The Loop Chain

1. Body evaluates → reads store.state → access() → MutableState[0] read → Compose tracks
2. .onAppear → action → reducer → state change
3. TCA's subscribeToDidSet → compactMap(_$id) → removeDuplicates (never filters) → withMutation
4. withMutation → MutableState[0] += 1 → Compose recomposes
5. Body re-evaluates → reads store.state → MutableState[0] read
6. (Any further state changes continue the cascade)

Note: .onAppear uses `remember { mutableStateOf(false) }` — only fires ONCE.
But TCA's subscribeToDidSet generates continuous withMutation calls for each state change.

## skip-model vs swift-perception Comparison

### skip-model (Current Observation Layer)

- Counter-based: `MutableState<Int>` per keypath index
- "Skip does not support calls to the generated `access(keyPath:)` and `withMutation(keyPath:_:)` functions"
- Deferred tracking via StateTracking can lose initial mutations
- Every update() triggers recomposition regardless of actual value change
- No `withObservationTracking` equivalent on Android

### swift-perception (Proposed Foundation)

- Complete backport of Swift Observation (iOS 13+)
- Per-keypath tracking with proper identity
- `withPerceptionTracking` provides onChange callbacks (fires ONCE, auto-cancels)
- Works on Android already (pthread-based locking, no iOS deps for core)
- Already used by TCA, swift-navigation, swift-sharing on iOS
- NO Compose integration (pure Swift observation)
- Core files have NO Android guards — fully available

### Key Insight

swift-perception provides BETTER observation semantics but NO Compose integration.
skip-model provides Compose integration but BROKEN observation semantics.

The fix: use Perception for observation, bridge it to Compose via a thin MutableState counter layer.

## Proposed Architecture

```
                     Android (proposed)
                     ──────────────────
View body eval:   withPerceptionTracking {
                    body()                    ← Perception tracks keypath accesses
                  } onChange: {
                    composeMutableState += 1  ← ONE Compose recomposition trigger
                  }

State change:     PerceptionRegistrar.withMutation
                    → Perception onChange fires (ONCE, then auto-cancels)
                    → composeMutableState += 1
                    → Compose recomposes
                    → withPerceptionTracking re-enters on next body eval
```

This matches iOS semantics exactly:
- One onChange per tracking scope
- Natural deduplication
- TCA stays untouched (already uses PerceptionRegistrar on iOS)

## Implementation Paths

### Path A: Fork skip-android-bridge
Rewrite ObservationRegistrar to use withPerceptionTracking internally.
- access() still reads MutableState (for Compose dependency registration)
- withMutation() becomes a no-op for Compose — Perception handles notification
- When Perception onChange fires, increment MutableState counter ONCE

### Path B: Fork skip-fuse-ui
Modify Kotlin-side @Composable view rendering to wrap JNI body call.
- Closer to how iOS works (wrapping at view rendering level)
- But requires modifying precompiled Kotlin code

### Path C: Modify generated bridge code
Have skipstone emit withPerceptionTracking in Swift_composableBody.
- Cleanest solution
- Requires forking Skip's build plugin (highest complexity)

### Constraint
The generated `Swift_composableBody` is emitted by Skip's build plugin (skipstone).
Cannot modify without forking the code generator.

## Why Swift Observation Needs Bridging

Swift Observation (and Perception) work NATIVELY on Android via Skip. The functions
`access()`, `withMutation()`, `withObservationTracking()` all execute correctly.

The gap: **Compose doesn't know about Swift Observation.** On iOS, SwiftUI internally
uses `withObservationTracking` to know when to re-render. On Android, Compose uses
its own MutableState/snapshot system. The "bridge" connects Swift Observation's
change notifications to Compose's recomposition system.

Perception already runs on Android. We just need a thin layer that translates
"Perception detected a change" → "increment a Compose MutableState counter."

## Key Files

- Bridge registrar: `.build/checkouts/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`
- MutableStateBacking: `.build/checkouts/skip-model/Sources/SkipModel/MutableStateBacking.swift`
- StateTracking: `.build/checkouts/skip-model/Sources/SkipModel/StateTracking.swift`
- Generated bridges: `.build/plugins/outputs/service-app/ServiceApp/destination/skipstone/SkipBridgeGenerated/`
- TCA Store registrar: `swift-composable-architecture/.../Store.swift` (lines 119-125)
- TCA ObservationStateRegistrar: `swift-composable-architecture/.../ObservationStateRegistrar.swift`
- swift-perception core: `swift-perception/Sources/Perception/`
- Observing wrapper (backup): `Sources/ServiceApp/Observing.swift.bak`

## Current State of TCA Fork

Store.swift and ObservationStateRegistrar.swift use bridge registrar on Android:
```swift
#if !os(visionOS) && !os(Android)
    let registrar = PerceptionRegistrar(...)
#elseif os(Android)
    let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
#else
    let registrar = Observation.ObservationRegistrar()
#endif
```

This is the ORIGINAL state — reverted from the PerceptionRegistrar experiment.
