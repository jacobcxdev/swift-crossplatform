# Identity Issues — UAT Round 5 (2026-03-03)

Two persistent issues have blocked Phase 18.1 since Round 1 (five rounds of UAT). This document provides all evidence for a fresh session to investigate each independently.

## Table of Contents

1. [Issue 1: ForEach Namespace UUID Instability](#issue-1-foreach-namespace-uuid-instability)
2. [Issue 2: Section 7 LocalPeerStoreItemKey Never Propagated](#issue-2-section-7-localpeerestoreitemkey-never-propagated)
3. [Related Fix: asciiValue Crash](#related-fix-asciivalue-crash)
4. [What Has Been Fixed (Working)](#what-has-been-fixed-working)
5. [Log Files](#log-files)
6. [Key Architectural Context](#key-architectural-context)

---

## Issue 1: ForEach Namespace UUID Instability

### Symptoms

Section 6 CounterCard counters reset to 0 after:
- Switching tabs (Identity tab → other tab → back)
- Adding a card via "Add Card" button (always on first add after initial population)
- Deleting a card (intermittent)

Section 6 CounterCard counters are correctly retained during scrolling within the same composition lifecycle.

### Log Evidence

**Tab switch** (`/tmp/r5-tab-switch-logs.txt`):
```
Before switch: ns=1/2a464f1d-7444-425b-b4a3-863de431d0e9 → all HITs
releaseAll: count=3                     ← List's PeerStore destroyed on tab switch
After return:  ns=1/5045b3f4-f7d5-442e-9ba2-14587986c5cc → all MISSes → new inserts
```

**Add card** (`/tmp/r5-add-card-logs.txt`):
```
Before add:  ns=1/0a968fe9-fabe-4c56-80f4-812eb649bd4a → HITs
After add:   ns=1/abc4930f-62e4-43b5-8193-ba043023ebf4 → all MISSes → new inserts
```

**Delete card** (`/tmp/r5-delete-card-logs.txt`):
```
Three different namespace UUIDs over the session:
  1/6bf76215-b96e-4149-8605-529a3508af7e
  1/c7d4f3ac-0112-49e1-8953-737fab959051
  1/dd270250-3dcd-425f-a7cc-cdc52d21f5ed
```

In all cases, item keys (card UUIDs like `15A179AA-...`) are stable across the namespace change. Only the namespace portion of the `PeerCacheKey` changes.

### Observation

The namespace is the ForEach's `peerStoreNamespace` property, set via `rememberSaveable { UUID.randomUUID().toString() }`. Despite using `rememberSaveable`, the UUID changes across data mutations and tab switches.

### Relevant Code

**Swift source** (`forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift`):
```swift
// Line 30:
var peerStoreNamespace: AnyHashable?

// Lines 97-108 (inside @Composable Evaluate):
if let store = LocalPeerStore.current {
    if peerStoreNamespace == nil {
        peerStoreNamespace = rememberSaveable { java.util.UUID.randomUUID().toString() }
    }
    let activeKeys = currentPeerStoreKeys()
    let ns = peerStoreNamespace
    SideEffect { store.cleanup(namespace: ns, activeKeys: activeKeys) }
}
```

**Transpiled Kotlin** (`ForEach.kt`):
```kotlin
// Line 32:
internal var peerStoreNamespace: AnyHashable? = null
    get() = field.sref({ this.peerStoreNamespace = it })
    set(newValue) { field = newValue.sref() }

// Lines 104-112 (inside @Composable Evaluate):
LocalPeerStore.current.sref()?.let { store ->
    if (peerStoreNamespace == null) {
        peerStoreNamespace = rememberSaveable { -> java.util.UUID.randomUUID().toString() }
    }
    val activeKeys = currentPeerStoreKeys()
    val ns = peerStoreNamespace.sref()
    SideEffect { -> store.cleanup(namespace = ns, activeKeys = activeKeys) }
}
```

### What Has Been Tried

| Plan | Approach | Result |
|------|----------|--------|
| Plan 10 | `rememberSaveable { UUID }` for namespace | UUID changes across data mutations and tab switches |
| Plan 15 | Normalise cleanup keys via `composeBundleNormalizedKey()` | Fixed cleanup evictions (0 spurious evicts), but namespace instability unchanged |
| Plan 16 | Replace `PeerNamespacePath` struct with String-based namespace composition | Fixed structural equality within a single lifecycle (HITs during scroll), but namespace UUID still regenerates across mutations/tab switches |

---

## Issue 2: Section 7 LocalPeerStoreItemKey Never Propagated

### Symptoms

- Section 7 `PeerRememberTestView` and `CounterCard` always show `itemKey=null` in `rememberViewPeer` logs
- These views always take the fallback `remember` path (not PeerStore path)
- Counter values do not survive tab switches

### Log Evidence

```
[rememberViewPeer] store=true itemKey=null itemKeyType=nil namespace=1 slotKey=IdentitySection7View
[rememberViewPeer] store=true itemKey=null itemKeyType=nil namespace=1 slotKey=PeerRememberTestView
[rememberViewPeer] store=true itemKey=null itemKeyType=nil namespace=1 slotKey=CounterCard
```

`store=true` (PeerStore exists from TabView) but `itemKey=null` → falls through the `if let store, let itemKey` gate in `rememberViewPeer()`.

### Relevant Code

**Swift source** (`examples/fuse-app/Sources/FuseApp/IdentityFeature.swift:653-662`):
```swift
// Inside IdentitySection7View.body:
#if SKIP
let peerRememberItemKey: String = "peer-remember-test-view"
// SKIP INSERT: val providedPeerItemKey = LocalPeerStoreItemKey provides peerRememberItemKey
CompositionLocalProvider(providedPeerItemKey) {
    PeerRememberTestView()
}
#else
PeerRememberTestView()
#endif
```

**Transpiled Kotlin** (`IdentityFeature.kt:446-461`) — `IdentitySection7View._ComposeContent`:
```kotlin
override fun _ComposeContent(context: skip.ui.ComposeContext) {
    val currentHash = Swift_inputsHash(Swift_peer)
    Swift_peer = skip.ui.rememberViewPeer(slotKey = "IdentitySection7View", ...)
    skip.ui.ViewObservation.startRecording?.invoke()
    skip.model.StateTracking.pushBody()
    val renderables = body().Evaluate(context = context, options = 0)
    // ...
}
```

Where `body()` calls through JNI:
```kotlin
override fun body(): skip.ui.View {
    return skip.ui.ComposeBuilder { composectx ->
        Swift_composableBody(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok
    }
}
```

### Key Observation

Grepping the transpiled `IdentityFeature.kt` for `LocalPeerStoreItemKey`, `providedPeerItemKey`, `peerRememberItemKey`, and `CompositionLocalProvider` returns **zero matches**. The `#if SKIP` block and its `SKIP INSERT` content are not present in the transpiled Kotlin.

`IdentitySection7View` is a bridged view (`SwiftPeerBridged`). Its `body()` is evaluated on the Swift side via JNI (`Swift_composableBody(Swift_peer)`). On the Swift side, `#if SKIP` evaluates to false.

### What Has Been Tried

| Plan | Approach | Result |
|------|----------|--------|
| Plan 14 | Raw Kotlin string literals in `SKIP INSERT` inside `#if SKIP` body block | `itemKey=null` |
| Plan 17 | Swift-typed `let` variables before `SKIP INSERT` inside `#if SKIP` body block | `itemKey=null` — same result |

Both approaches modified code inside the same `#if SKIP` block within `IdentitySection7View.body`.

---

## Related Fix: asciiValue Crash

**Status: Fixed locally, not yet committed.**

`IdentityFeature.swift:250` had a force-unwrap `state.nextLazyCardLetter.asciiValue! + 1` that crashes when rapidly adding cards past ASCII 126. Fixed with a wrapping guard that resets to 'A'.

Crash log:
```
Abort message: 'FuseApp/IdentityFeature.swift:250: Fatal error: Unexpectedly found nil while unwrapping an Optional value'
```

---

## What Has Been Fixed (Working)

These fixes from earlier plans ARE working correctly:

| Fix | Plan | Evidence |
|-----|------|----------|
| PeerStore cleanup key normalisation | Plan 15 | 0 spurious evictions in all R5 logs |
| PeerNamespacePath → String namespace | Plan 16 | Within a single ForEach lifecycle, all lookups are HITs (structural equality works) |
| `composeBundleNormalizedKey()` for item keys | Plan 15 | `itemKeyType=class kotlin.String` confirmed in logs |
| Diagnostic logging in PeerStore | Plans 15/17 | All logs include store, itemKey, itemKeyType, namespace, slotKey |

---

## Log Files

All saved to `/tmp/` on the development machine:

| File | Reproduction |
|------|-------------|
| `/tmp/r5-tab-switch-logs.txt` | Tab switch loses Section 6 state |
| `/tmp/r5-add-card-logs.txt` | Add card loses Section 6 state |
| `/tmp/r5-delete-card-logs.txt` | Delete card loses Section 6 state |
| `/tmp/r5-crash-logs.txt` | Rapid add crash (asciiValue force-unwrap) |

---

## Key Architectural Context

- **Skip Fuse mode**: Views are bridged — their body is evaluated on the Swift side via JNI (`Swift_composableBody`)
- **`#if SKIP`**: Compile-time flag that's true only in transpiled Kotlin code
- **`SKIP INSERT`**: Emits raw Kotlin code at the transpilation point. Only present in transpiled code.
- **`rememberViewPeer()`**: Central peer caching function in `PeerStore.swift`. Gate: `if let store, let itemKey` → PeerStore path; else → `remember`/`rememberSaveable` fallback
- **PeerCacheKey**: `(namespace: AnyHashable?, itemKey: AnyHashable, viewSlotKey: String)` — all three must match for a cache HIT
- **PeerStore**: Parent-scoped cache (`RememberObserver`) created by lazy containers and TabView. Outlives individual item compositions.
- **ForEach namespace**: UUID assigned via `rememberSaveable` to scope sibling ForEach instances within a shared PeerStore
- **`sref()`**: Skip's Kotlin bridging for Swift reference semantics — wraps property access with retain/release semantics
