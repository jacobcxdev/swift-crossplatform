# Unified Identity Fix Design: Sections 3, 6, 7

> Date: 2026-03-02
> Phase: 18.1 (Canonical View Identity System)
> Status: Designed — validated via independent Codex diagnosis + pair programming
> Prerequisite: [identity-diagnosis-sections-3-6-7.md](identity-diagnosis-sections-3-6-7.md)
>
> Implementation plans (Codex-validated):
> - [identity-implementation-plan-peerstore.md](identity-implementation-plan-peerstore.md) — Sections 6 & 7
> - [identity-implementation-plan-animation.md](identity-implementation-plan-animation.md) — Section 3

## Overview

Three independent issues share overlapping infrastructure. This document describes the
unified fix architecture validated by parallel Codex pair-programming sessions.

| Section | Problem | Fix Component |
|---------|---------|---------------|
| 3 | ForEach animation never fires | RetainedAnimatedItems (per-item AnimatedVisibility) |
| 6 | Identity lost on LazyColumn scroll | PeerStore + rememberViewPeer |
| 7 | Identity lost on tab switch | PeerStore + rememberViewPeer |

---

## Component 1: RetainedAnimatedItems (Section 3)

### Root Cause (confirmed by Codex)

Container `idMap` checks `TagModifier(.id)` but ForEach wraps items with `TagModifier(.tag)`.
Result: `ids=0` always → NON-ANIMATED path → no `AnimatedContent` → no transitions.

`AnimatedContent` is the **wrong Compose primitive** for list-item transitions. It is designed
for "swap entire content" (crossfading between screens), not "animate individual items in a
list." Per-item `AnimatedVisibility` is the correct approach.

### Design

#### New shared helper (new file in skip-ui)

**`RetainedAnimatedItems.swift`** — shared across VStack/HStack/ZStack:

```kotlin
/// Per-item animation state tracked across recompositions.
class RetainedAnimatedItem {
    val key: Any
    val renderable: Renderable
    val visibility: MutableTransitionState<Boolean>
    val enterTransition: EnterTransition?
    val exitTransition: ExitTransition?
    val animationSpec: AnimationSpec<Float>?
    var previousOrder: Int  // for exit positioning
}

/// Registry tracking current + exiting items with their animation state.
class RetainedAnimatedItemsState {
    val items: MutableMap<Any, RetainedAnimatedItem>
    val previousOrderedKeys: MutableList<Any>

    /// Sync current renderables into the registry.
    /// - Present items: targetState = true
    /// - Removed items: targetState = false (retained for exit animation)
    /// - Completed exits (isIdle && !currentState): pruned
    fun sync(
        renderables: List<Renderable>,
        animation: Animation?,
        keyExtractor: (Renderable, Int) -> Any
    )

    /// Ordered list of items to render (present + exiting, in position order).
    fun orderedItems(): List<RetainedAnimatedItem>
}

@Composable
fun rememberRetainedAnimatedItemsState(): RetainedAnimatedItemsState
```

#### Effective key extraction

```kotlin
fun effectiveAnimatedKey(renderable: Renderable, index: Int): Any {
    // Explicit .id() takes priority
    TagModifier.on(content: renderable, role: .id)?.value?.let { return normalizeKey(it) }
    // Then ForEach-provided identity key
    renderable.identityKey?.let { return it }
    // Fallback: positional index (no animation for unkeyed items)
    return index
}
```

#### Exit item positioning

Exiting items are anchored **before the next surviving right neighbour** from
`previousOrderedKeys`. Example: deleting B from [A, B, C] → render order [A, B(exiting), C].

#### Animation spec capture

`Animation.current(isAnimating:)` is read **once at container scope** and snapshotted onto
items whose `targetState` changes in that recomposition pass. This prevents the `withAnimation`
thread-local from being cleared before the animation spec is consumed.

#### Container integration

Each container (VStack/HStack/ZStack) replaces its current dual-path logic:

```kotlin
// Before: dual ANIMATED / NON-ANIMATED paths
if ids.size < renderables.size {
    // NON-ANIMATED path (Column/Row/Box with key())
} else {
    // ANIMATED path (AnimatedContent)
}

// After: single unified path
let retainedState = rememberRetainedAnimatedItemsState()
let animation = Animation.current(isAnimating: /* active transitions exist */)
retainedState.sync(renderables: renderables, animation: animation, keyExtractor: ::effectiveAnimatedKey)

Column/Row/Box {
    for item in retainedState.orderedItems() {
        key(item.key) {
            AnimatedVisibility(
                visibleState: item.visibility,
                enter: item.enterTransition ?? EnterTransition.None,
                exit: item.exitTransition ?? ExitTransition.None
            ) {
                item.renderable.Render(context: contentContext)
            }
        }
    }
}
```

For items with no transition modifier, `AnimatedVisibility` with `EnterTransition.None` /
`ExitTransition.None` is effectively a no-op wrapper — zero visual change from current behaviour.

#### Container size animation

When active transitions exist, apply `animateContentSize()` to the container modifier,
replacing `AnimatedContent`'s `SizeTransform` behaviour.

#### AnimatedContent path removal

The existing `AnimatedContent`-based ANIMATED path is **removed entirely** for child-list
diffs. Explicit `.id()` still works for state-reset semantics (handled by `TagModifier.Render`),
but its value feeds into `effectiveAnimatedKey` alongside `identityKey`.

### Files Changed

| File | Change |
|------|--------|
| **NEW** `RetainedAnimatedItems.swift` | Shared helper (RetainedAnimatedItemsState, effectiveAnimatedKey) |
| `VStack.swift` | Replace dual-path with unified RetainedAnimatedItems path |
| `HStack.swift` | Same |
| `ZStack.swift` | Same |

### Risk

Medium. Replaces the entire container animation path, but:
- Items without transitions get `EnterTransition.None` / `ExitTransition.None` → no-op
- Items without keys fall back to positional index → same as current NON-ANIMATED path
- Explicit `.id()` still contributes to key extraction → existing Section 8 behaviour preserved

---

## Component 2: PeerStore (Sections 6 & 7)

### Root Cause (confirmed by Codex)

`remember { SwiftPeerHandle(...) }` doesn't survive Compose composition disposal:
- **LazyColumn** (Section 6): disposes off-screen items
- **TabView NavHost** (Section 7): `popUpTo(saveState: true)` disposes tab compositions

`SwiftPeerHandle.onForgotten()` releases the peer → Store/instanceID destroyed.
`@State` survives via `rememberSaveable`, but `let`-with-default properties are lost.

### Design

#### PeerStore (skip-ui runtime)

```kotlin
/// Composite cache key — handles multiple peer-backed views per ForEach row.
data class PeerCacheKey(
    val namespace: Any?,       // ForEach identity domain (or route key)
    val itemKey: Any?,         // ForEach item identity (or structural path segment)
    val viewSlotKey: String    // Source-location key per rememberViewPeer call site
)

/// Single cached peer entry.
data class PeerEntry(
    val peer: Long,
    val inputsHash: Long?,
    val retainFn: (Long) -> Unit,
    val releaseFn: (Long) -> Unit
)

/// Parent-scoped peer cache. Lives at LazyColumn parent / TabView route level.
class PeerStore : RememberObserver {
    private val cache: MutableMap<PeerCacheKey, PeerEntry> = mutableMapOf()

    fun lookup(key: PeerCacheKey): PeerEntry? = cache[key]

    fun insert(key: PeerCacheKey, entry: PeerEntry) {
        entry.retainFn(entry.peer)  // Extra retain for cache ownership
        cache[key] = entry
    }

    fun replace(key: PeerCacheKey, newEntry: PeerEntry) {
        cache.remove(key)?.let { old -> old.releaseFn(old.peer) }
        insert(key, newEntry)
    }

    fun evict(key: PeerCacheKey) {
        cache.remove(key)?.let { it.releaseFn(it.peer) }
    }

    /// Evict entries whose itemKey is not in the active set (for a given namespace).
    fun cleanup(namespace: Any?, activeKeys: Set<Any?>) {
        val toRemove = cache.keys.filter { it.namespace == namespace && it.itemKey !in activeKeys }
        toRemove.forEach { evict(it) }
    }

    // RememberObserver — release all on parent disposal
    override fun onForgotten() { cache.values.forEach { it.releaseFn(it.peer) }; cache.clear() }
    override fun onAbandoned() { onForgotten() }
    override fun onRemembered() {}
}
```

#### CompositionLocals

```kotlin
val LocalPeerStore = staticCompositionLocalOf<PeerStore?> { null }
val LocalPeerStoreItemKey = staticCompositionLocalOf<Any?> { null }
val LocalPeerStoreNamespace = staticCompositionLocalOf<Any?> { null }
```

#### `rememberViewPeer()` runtime helper

```kotlin
@Composable
fun rememberViewPeer(
    slotKey: String,           // Source-location key (transpiler-generated)
    peer: Long,
    retainFn: (Long) -> Unit,
    releaseFn: (Long) -> Unit,
    inputsHash: Long? = null,
    refreshPeerFn: ((Long, Long) -> Unit)? = null  // For mixed views: refresh(cached, fresh)
): Long {
    val store = LocalPeerStore.current
    val itemKey = LocalPeerStoreItemKey.current
    val namespace = LocalPeerStoreNamespace.current

    if (store != null && itemKey != null) {
        val cacheKey = PeerCacheKey(namespace, itemKey, slotKey)
        val cached = store.lookup(cacheKey)

        if (cached != null) {
            if (inputsHash != null && cached.inputsHash != inputsHash && refreshPeerFn != null) {
                // Mixed view: inputs changed — refresh cached peer with new constructor params
                refreshPeerFn(cached.peer, peer)
                store.replace(cacheKey, PeerEntry(cached.peer, inputsHash, retainFn, releaseFn))
                releaseFn(peer)  // Release the fresh peer
            } else {
                releaseFn(peer)  // Release the fresh peer, use cached
            }
            return cached.peer
        } else {
            store.insert(cacheKey, PeerEntry(peer, inputsHash, retainFn, releaseFn))
            return peer
        }
    }

    // Fallback: existing behaviour (no PeerStore in scope)
    val handle: SwiftPeerHandle
    if (inputsHash != null) {
        handle = remember(inputsHash) { SwiftPeerHandle(peer, retainFn, releaseFn) }
    } else {
        handle = remember { SwiftPeerHandle(peer, retainFn, releaseFn) }
    }
    return handle.peer
}
```

#### `Swift_refreshPeer` (transpiler-generated, mixed views only)

Whole-value struct reconstruction — respects `let` immutability:

```swift
// Generated for CounterCard (constructor params: title; let-with-default: store, instanceID)
@_cdecl("Java_...CounterCard_Swift_refreshPeer")
func Swift_refreshPeer(_ existingPeer: SwiftObjectPointer, _ freshPeer: SwiftObjectPointer) {
    let existing = existingPeer.takeUnretainedValue() as! SwiftValueTypeBox<CounterCard>
    let fresh = freshPeer.takeUnretainedValue() as! SwiftValueTypeBox<CounterCard>
    existing.value = CounterCard(
        title: fresh.value.title,             // constructor param from fresh
        store: existing.value.store,          // let-with-default preserved
        instanceID: existing.value.instanceID // let-with-default preserved
    )
}
```

Generated only for views where `canRememberPeerWithInputCheck == true`.

#### Container providers

**LazyVStack.swift** — provide PeerStore at lazy container scope:
```kotlin
val peerStore = remember { PeerStore() }
CompositionLocalProvider(LocalPeerStore provides peerStore) {
    LazyColumn(...) {
        items(count: count, key: keyFn) { index ->
            CompositionLocalProvider(
                LocalPeerStoreItemKey provides keyFn(index),
                LocalPeerStoreNamespace provides forEachId
            ) {
                content(index)
            }
        }
    }
}
```

**TabView.swift** — provide per-route PeerStore:
```kotlin
val routeStores = remember { mutableMapOf<String, PeerStore>() }
// In each composable(route) block:
val routeStore = routeStores.getOrPut(route) { PeerStore() }
CompositionLocalProvider(
    LocalPeerStore provides routeStore,
    LocalPeerStoreItemKey provides route,
    LocalPeerStoreNamespace provides "tab"
) {
    tabContent()
}
```

**IdentityKeyModifier.Render** — propagate item key:
```kotlin
@Composable override func Render(content: Renderable, context: ComposeContext) {
    CompositionLocalProvider(LocalPeerStoreItemKey provides normalizedKey) {
        content.Render(context: context)
    }
}
```

### Transpiler Changes (KotlinBridgeToKotlinVisitor.swift)

Mechanical replacement in `_ComposeContent` generation:

```kotlin
// Phase 1 (no constructor params):
// Old:
val peerHandle = remember { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }
// New:
Swift_peer = skip.ui.rememberViewPeer(
    slotKey = "com.example.PeerRememberTestView",
    peer = Swift_peer,
    retainFn = ::Swift_retain,
    releaseFn = ::Swift_release
)

// Phase 2 (mixed views):
// Old:
val currentHash = Swift_inputsHash(Swift_peer)
val peerHandle = remember(currentHash) { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }
// New:
val currentHash = Swift_inputsHash(Swift_peer)
Swift_peer = skip.ui.rememberViewPeer(
    slotKey = "com.example.CounterCard",
    peer = Swift_peer,
    retainFn = ::Swift_retain,
    releaseFn = ::Swift_release,
    inputsHash = currentHash,
    refreshPeerFn = ::Swift_refreshPeer
)
```

### Eviction Policy

| Context | Strategy |
|---------|----------|
| ForEach in LazyColumn | `peerStore.cleanup(namespace, activeKeys)` on each ForEach data change |
| TabView routes | Accept route-scoped over-retention (bounded tab count). Release all on TabView removal |
| Conditional static subtrees | Future: sweep strategy for conditionally-shown views |

### Files Changed

| File | Change |
|------|--------|
| **NEW** `PeerStore.swift` | PeerStore, PeerCacheKey, PeerEntry, CompositionLocals, rememberViewPeer() |
| `Renderable.swift` | IdentityKeyModifier provides LocalPeerStoreItemKey |
| `LazyVStack.swift` | Provide PeerStore + namespace + item key |
| `TabView.swift` | Provide per-route PeerStore |
| `ForEach.swift` | Cleanup eviction on data change |
| `KotlinBridgeToKotlinVisitor.swift` | Replace `remember { SwiftPeerHandle }` with `rememberViewPeer()` |
| `KotlinBridgeToKotlinVisitor.swift` | Generate `Swift_refreshPeer` for mixed views |

### Risk Assessment

| Component | Risk | Mitigation |
|-----------|------|------------|
| PeerStore runtime | Medium | Null-check fallback: `LocalPeerStore.current == null` → existing `remember` behaviour |
| Transpiler changes | Low | Mechanical replacement; `rememberViewPeer` delegates to `remember` when no store |
| `Swift_refreshPeer` | Medium | Generated only for mixed views; struct reconstruction is safe |
| Eviction bugs | Medium | Over-retention (memory leak) is safer than under-retention (identity loss) |

---

## Implementation Order

### Wave 1: PeerStore infrastructure (no container changes)

1. **PeerStore.swift** — new file with PeerStore, PeerCacheKey, PeerEntry, CompositionLocals, `rememberViewPeer()`
2. **Transpiler** — replace `remember { SwiftPeerHandle }` with `rememberViewPeer()`, generate `Swift_refreshPeer`
3. **IdentityKeyModifier** — provide `LocalPeerStoreItemKey`

At this point: all existing views work identically (fallback path). No PeerStore providers yet.

### Wave 2: PeerStore providers (fixes Sections 6 & 7)

4. **LazyVStack.swift** — provide PeerStore + item key + namespace
5. **TabView.swift** — provide per-route PeerStore
6. **ForEach.swift** — eviction on data change

At this point: Sections 6 & 7 should be fixed. Section 3 animation still broken.

### Wave 3: RetainedAnimatedItems (fixes Section 3)

7. **RetainedAnimatedItems.swift** — new shared helper
8. **VStack.swift** — replace dual-path with unified RetainedAnimatedItems
9. **HStack.swift** — same
10. **ZStack.swift** — same

At this point: all three sections fixed.

### Wave 4: Cleanup

11. Re-gate verbose `ComposeIdentity` logging behind `FUSE_IDENTITY_DEBUG`
12. Commit idMap revert (currently uncommitted on disk)
13. Update test UI if needed

---

## What This Does NOT Fix

- **Process death restoration**: PeerStore is in-memory only
- **Surviving-sibling placement animation**: Compose has `animateItem()` for lazy containers but no equivalent for eager Column/Row; this is a separate concern
- **Arbitrary reorder animation**: Exit positioning is optimised for deletions; complex reorder scenarios may need a more sophisticated ordering algorithm
