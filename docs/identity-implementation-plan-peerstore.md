# PeerStore Implementation Plan (Sections 6 & 7)

> Date: 2026-03-02
> Status: Finalised via Codex pair programming (3 iteration rounds)
> Prerequisite: [identity-unified-fix-design.md](identity-unified-fix-design.md)

## Summary of Design Decisions

| Decision | Rationale |
|----------|-----------|
| `PeerStore.insert` retains the peer | Store is a real owner. Without its own retain, GC finaliser could free peer while store holds it. |
| Store hit path retains cached peer for new Kotlin object | Each Kotlin object needs its own retain paired with `finalize()`. Store retain is separate, paired with eviction/`onForgotten`. |
| Fallback path keeps `SwiftPeerHandle.swapFrom` | Without PeerStore, old lifecycle model applies: `remember` returns cached handle, `swapFrom` transfers ownership. |
| Gate: `store != nil && itemKey != nil` | Namespace-only (no itemKey) would cause aliasing for same-type siblings. Safety over convenience. |
| Single TabView-level PeerStore (not per-route) | Simpler. Route becomes part of namespace. PeerStore lives outside NavHost so it survives tab switches. |
| `PeerStoreNamespaceModifier` on lazy renderables | Avoids changing LazyItemCollector API. ForEach wraps produced renderables with modifier. |
| `Swift_refreshPeer` uses `pointee()!` API | Matches existing bridge cdecl patterns. |

---

## Prerequisites / Disk State

**IMPORTANT: The working tree has uncommitted changes that do NOT appear in git HEAD. A new session must be aware of these before reading or editing any file.**

| File | Uncommitted Working-Tree State |
|------|-------------------------------|
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/VStack.swift` | idMap revert applied + ungated verbose `ComposeIdentity` logging added (Plan 08 rollback) |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/HStack.swift` | idMap revert applied + ungated verbose `ComposeIdentity` logging added (Plan 08 rollback) |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ZStack.swift` | idMap revert applied + ungated verbose `ComposeIdentity` logging added |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Compose/Renderable.swift` | Ungated verbose `ComposeIdentity` logging in `identityKey`, `normalizeKey`, `IdentityKeyModifier.init`, `IdentityKeyModifier.Render` |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift` | `identityLog` helper function added at top of file; verbose logging throughout `Evaluate`, `produceLazyItems`, `identifiedRenderable`, `identifiedIteration`, `taggedRenderable` |

These are working-tree changes only — `git HEAD` does not have them. The source excerpts in this plan reflect the **current working-tree state**, not HEAD.

After all PeerStore fixes are complete, all `ComposeIdentity` logging should be re-gated behind `#if FUSE_IDENTITY_DEBUG` or removed.

---

## Retain Count Lifecycle Trace

### Store-backed path (LazyColumn / TabView keyed content)

**First composition:**
- Bridge creates K1 with P1: `P1 refcount = 1` (K1 owns via finalize)
- `rememberViewPeer` → store miss → `store.insert` retains P1: `P1 refcount = 2` (K1 + Store)

**Recomposition (K2 created with fresh P2):**
- `P2 refcount = 1` (K2 owns via finalize)
- `rememberViewPeer` → store hit → `retainFn(cached P1)`: `P1 refcount = 3` (K1 + Store + K2)
- `releaseFn(P2)`: `P2 refcount = 0` (freed)
- `K2.Swift_peer = P1`
- Later K1.finalize(): `P1 refcount = 2` (K2 + Store)

**Composition disposal (scroll off / tab switch):**
- No composition-scoped cleanup fires (no SwiftPeerHandle in this path)
- K2 becomes unreachable → K2.finalize(): `P1 refcount = 1` (Store only)

**Store eviction / onForgotten:**
- Store releases P1: `P1 refcount = 0` (freed)

### Fallback path (no PeerStore in scope)

**First composition:**
- Bridge creates K1 with P1: `P1 refcount = 1`
- `remember { SwiftPeerHandle(...) }` → SwiftPeerHandle.init retains: `P1 refcount = 2` (K1 + Handle)

**Recomposition (K2 with fresh P2):**
- `P2 refcount = 1`
- `remember` returns existing Handle (P1)
- `handle.peer != peer` → `swapFrom(stale: P2)` → retains P1 (`refcount = 3`), releases P2 (`refcount = 0`)
- `K2.Swift_peer = P1`
- K1.finalize(): `P1 refcount = 2` (K2 + Handle)

**Composition disposal:**
- Handle.onForgotten(): `P1 refcount = 1` (K2 only)
- K2.finalize(): `P1 refcount = 0` (freed)

---

## Implementation Steps

### Step 1: Create `PeerStore.swift`

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Compose/PeerStore.swift` (new file — does not exist yet)

Contents:
- `PeerCacheKey` (Hashable struct: `namespace: AnyHashable?`, `itemKey: AnyHashable`, `viewSlotKey: String`)
- `PeerEntry` (class: `peer: Long`, `inputsHash: Long?` (mutable), `retainFn`, `releaseFn`)
- `PeerStore` (RememberObserver): `lookup`, `insert` (retains), `evict` (releases), `cleanup(namespace:activeKeys:)`, `onForgotten` (releases all)
- `LocalPeerStore` (`staticCompositionLocalOf<PeerStore?> { nil }`)
- `LocalPeerStoreItemKey` (`staticCompositionLocalOf<AnyHashable?> { nil }`)
- `LocalPeerStoreNamespace` (`staticCompositionLocalOf<AnyHashable?> { nil }`)
- `PeerNamespacePath` (private Hashable struct: `parent: AnyHashable?`, `current: AnyHashable`)
- `PeerStoreNamespaceModifier` (RenderModifier: reads current namespace, provides combined path)
- `SwiftPeerHandle` (shared: `peer`, `retainFn`, `releaseFn`, `swapFrom(stale:)`, RememberObserver lifecycle)
- `rememberViewPeer()` (@Composable public func)

Key `rememberViewPeer` logic:

```swift
@Composable
public func rememberViewPeer(
    slotKey: String,
    peer: Long,
    retainFn: @escaping (Long) -> Void,
    releaseFn: @escaping (Long) -> Void,
    inputsHash: Long? = nil,
    refreshPeerFn: ((Long, Long) -> Void)? = nil
) -> Long {
    let store = LocalPeerStore.current
    let itemKey = LocalPeerStoreItemKey.current
    let namespace = LocalPeerStoreNamespace.current

    if let store, let itemKey {
        let cacheKey = PeerCacheKey(namespace: namespace, itemKey: itemKey, viewSlotKey: slotKey)
        if let cached = store.lookup(cacheKey) {
            retainFn(cached.peer)       // ownership for current Kotlin object
            if let inputsHash, cached.inputsHash != inputsHash, let refreshPeerFn {
                refreshPeerFn(cached.peer, peer)
                cached.inputsHash = inputsHash
            }
            releaseFn(peer)             // drop fresh bridge peer
            return cached.peer
        } else {
            store.insert(cacheKey, PeerEntry(peer: peer, inputsHash: inputsHash,
                                             retainFn: retainFn, releaseFn: releaseFn))
            return peer
        }
    }

    // Fallback: existing remember-based behaviour
    let handle: SwiftPeerHandle
    if let inputsHash {
        handle = remember(inputsHash) { SwiftPeerHandle(peer: peer, retainFn: retainFn, releaseFn: releaseFn) }
    } else {
        handle = remember { SwiftPeerHandle(peer: peer, retainFn: retainFn, releaseFn: releaseFn) }
    }
    if handle.peer != peer {
        handle.swapFrom(stale: peer)
    }
    return handle.peer
}
```

---

### Step 2: IdentityKeyModifier provides `LocalPeerStoreItemKey`

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Compose/Renderable.swift`

#### Current code (working-tree, lines 114–118)

```swift
// File: forks/skip-ui/Sources/SkipUI/SkipUI/Compose/Renderable.swift, lines 104–118
final class IdentityKeyModifier: RenderModifier {
    let normalizedKey: Any  // String | Int | Long — guaranteed by normalizeKey()

    init(key: Any) {
        android.util.Log.d("ComposeIdentity", "IdentityKeyModifier.init: rawKey=\(key) type=\(type(of: key))")
        self.normalizedKey = normalizeKey(key)
        android.util.Log.d("ComposeIdentity", "IdentityKeyModifier.init: normalizedKey=\(normalizedKey) type=\(type(of: normalizedKey))")
        super.init(role: .unspecified)
    }

    @Composable override func Render(content: Renderable, context: ComposeContext) {
        android.util.Log.d("ComposeIdentity", "IdentityKeyModifier.Render: key=\(normalizedKey) content=\(type(of: content))")
        content.Render(context: context)  // transparent — container consumes identity
    }
}
```

#### What to replace

Replace the `Render` method body (lines 114–117). The logging line and the single `content.Render` call are replaced with a `CompositionLocalProvider` wrapper.

```swift
// BEFORE (lines 114–117):
    @Composable override func Render(content: Renderable, context: ComposeContext) {
        android.util.Log.d("ComposeIdentity", "IdentityKeyModifier.Render: key=\(normalizedKey) content=\(type(of: content))")
        content.Render(context: context)  // transparent — container consumes identity
    }

// AFTER:
    @Composable override func Render(content: Renderable, context: ComposeContext) {
        CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(normalizedKey)) {
            content.Render(context: context)
        }
    }
```

#### Expected result

```swift
    @Composable override func Render(content: Renderable, context: ComposeContext) {
        CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(normalizedKey)) {
            content.Render(context: context)
        }
    }
```

`LocalPeerStoreItemKey` is defined in `PeerStore.swift` (Step 1). No additional imports are needed — `CompositionLocalProvider` is already imported via the `#if SKIP` block at the top of the file.

---

### Step 3: ForEach namespace and eviction

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift`

The file is 375 lines (working-tree). The key sections that need changes are:

#### 3a. Add `peerStoreNamespace` stored property

The `ForEach` class declaration (lines 16–37) currently has these stored properties:

```swift
// File: forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift, lines 16–37
// SKIP @bridge
public final class ForEach : View, Renderable, LazyItemFactory {
    let identifier: ((Any) -> AnyHashable?)?
    let indexRange: (() -> Range<Int>)?
    let indexedContent: ((Int) -> any View)?
    let objects: (any RandomAccessCollection<Any>)?
    let objectContent: ((Any) -> any View)?
    let objectsBinding: Binding<any RandomAccessCollection<Any>>?
    let objectsBindingContent: ((Binding<any RandomAccessCollection<Any>>, Int) -> any View)?
    let editActions: EditActions
    var onDeleteAction: ((IndexSet) -> Void)?
    var onMoveAction: ((IndexSet, Int) -> Void)?
```

**Add** a `var peerStoreNamespace: AnyHashable?` stored property after `onMoveAction`:

```swift
    var onDeleteAction: ((IndexSet) -> Void)?
    var onMoveAction: ((IndexSet, Int) -> Void)?
    var peerStoreNamespace: AnyHashable?   // ← ADD THIS LINE
```

#### 3b. Namespace initialisation in `Evaluate`

The `Evaluate` method begins at line 86. The current opening (lines 86–92):

```swift
// File: forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift, lines 86–92
    #if SKIP
    @Composable override func Evaluate(context: ComposeContext, options: Int) -> kotlin.collections.List<Renderable> {
        guard !EvaluateOptions(options).isKeepForEach else {
            return listOf(self)
        }
        let isLazy = EvaluateOptions(options).lazyItemLevel != nil
        identityLog("Evaluate: isLazy=\(isLazy), hasIdentifier=\(identifier != nil), hasObjects=\(objects != nil), objectCount=\(objects?.count ?? -1)")
```

**Insert** the namespace creation immediately after the `identityLog` call (after line 91, before the `var isFirst` declaration at line 98):

```swift
        identityLog("Evaluate: isLazy=\(isLazy), hasIdentifier=\(identifier != nil), hasObjects=\(objects != nil), objectCount=\(objects?.count ?? -1)")

        // ← INSERT BLOCK BELOW
        // Create or recall stable namespace UUID for this ForEach instance.
        // Used by PeerStore to scope peer cache entries so siblings don't alias.
        if let store = LocalPeerStore.current {
            if peerStoreNamespace == nil {
                peerStoreNamespace = AnyHashable(rememberSaveable { java.util.UUID.randomUUID().toString() })
            }
            // Schedule eviction of peers for items that are no longer present.
            // SideEffect runs after every recomposition with the current data snapshot.
            let activeKeys = currentPeerStoreKeys()
            let ns = peerStoreNamespace
            SideEffect { store.cleanup(namespace: ns, activeKeys: activeKeys) }
        }
        // ← END INSERT BLOCK
```

#### 3c. Add `currentPeerStoreKeys()` helper

Add this private helper method after `isUnrollRequired` (after line 207, before `produceLazyItems`):

```swift
    // Returns the set of AnyHashable item keys currently in the data source.
    // Used by the PeerStore eviction SideEffect.
    private func currentPeerStoreKeys() -> Set<AnyHashable> {
        var keys = Set<AnyHashable>()
        if let indexRange, let identifier {
            for index in indexRange() {
                if let k = identifier(index) { keys.insert(k) }
            }
        } else if let indexRange {
            for index in indexRange() { keys.insert(AnyHashable(index)) }
        } else if let objects, let identifier {
            for object in objects {
                if let k = identifier(object) { keys.insert(k) }
            }
        } else if let objectsBinding, let identifier {
            let objs = objectsBinding.wrappedValue
            for i in 0..<objs.count {
                if let k = identifier(objs[i]) { keys.insert(k) }
            }
        }
        return keys
    }
```

#### 3d. Wrap lazy-produced renderables with `PeerStoreNamespaceModifier`

In `produceLazyItems` (lines 209–248), wrap each call to `taggedRenderable(for:defaultTag:)` with `PeerStoreNamespaceModifier` if a namespace is present. The three factory closures currently end with:

```swift
// Lines 222–223 (indexedItems factory):
                return taggedRenderable(for: renderable, defaultTag: tag)
            }

// Lines 233–234 (objectItems factory):
                return taggedRenderable(for: renderable, defaultTag: tag)
            }

// Lines 243–244 (objectBindingItems factory):
                return taggedRenderable(for: renderable, defaultTag: tag)
            }
```

Replace each `return taggedRenderable(...)` with:

```swift
                let r = taggedRenderable(for: renderable, defaultTag: tag)
                if let ns = peerStoreNamespace {
                    return ModifiedContent(content: r, modifier: PeerStoreNamespaceModifier(namespace: ns))
                }
                return r
```

---

### Step 4: LazyVStack PeerStore provider

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/LazyVStack.swift`

#### Current code

The `Render` method `#if SKIP` block runs from line 47 to line 173. The `LazyColumn` starts at line 103 and closes at line 168. The three `items(count:key:)` blocks (inside `itemCollector.value.initialize(...)`) are at lines 113–117 (indexed), 119–124 (object), and 126–131 (objectBinding).

```swift
// File: forks/skip-ui/Sources/SkipUI/SkipUI/Containers/LazyVStack.swift, lines 98–133
                    let contentPadding = EnvironmentValues.shared._contentPadding.asPaddingValues()
                    EnvironmentValues.shared.setValues {
                        $0.set_contentPadding(EdgeInsets())
                        return ComposeResult.ok
                    } in: {
                    LazyColumn(state: listState, modifier: Modifier.fillMaxWidth(), verticalArrangement: columnArrangement, horizontalAlignment: columnAlignment, contentPadding: contentPadding, userScrollEnabled: isScrollEnabled, flingBehavior: flingBehavior) {
                        itemCollector.value.initialize(
                            startItemIndex: isSearchable ? 1 : 0,
                            item: { renderable, _ in
                                item {
                                    renderable.Render(context: context.content(scope: self))
                                }
                            },
                            indexedItems: { range, identifier, _, _, _, _, factory in
                                let count = range.endExclusive - range.start
                                let key: ((Int) -> String)? = identifier == nil ? nil : { composeBundleNormalizedKey(for: identifier!($0 + range.start)) }
                                items(count: count, key: key) { index in
                                    let scopedContext = context.content(scope: self)
                                    factory(index + range.start, scopedContext).Render(context: scopedContext)
                                }
                            },
                            objectItems: { objects, identifier, _, _, _, _, factory in
                                let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objects[$0])) }
                                items(count: objects.count, key: key) { index in
                                    let scopedContext = context.content(scope: self)
                                    factory(objects[index], scopedContext).Render(context: scopedContext)
                                }
                            },
                            objectBindingItems: { objectsBinding, identifier, _, _, _, _, _, factory in
                                let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objectsBinding.wrappedValue[$0])) }
                                items(count: objectsBinding.wrappedValue.count, key: key) { index in
                                    let scopedContext = context.content(scope: self)
                                    factory(objectsBinding, index, scopedContext).Render(context: scopedContext)
                                }
                            },
```

#### What to change

**Before `LazyColumn`** (insert after the `EnvironmentValues.shared.setValues { $0.set_contentPadding(...) } in: {` line, before `LazyColumn(`):

```swift
                    } in: {
                    // ← INSERT: create PeerStore scoped to this LazyVStack instance
                    let peerStore = androidx.compose.runtime.remember { PeerStore() }
                    CompositionLocalProvider(LocalPeerStore provides peerStore) {
                    LazyColumn(...) {
```

**Inside each `items(count:key:)` block**, wrap the render call with `LocalPeerStoreItemKey` provision. The item key is the string produced by `composeBundleNormalizedKey` — use the same value:

```swift
                            indexedItems: { range, identifier, _, _, _, _, factory in
                                let count = range.endExclusive - range.start
                                let key: ((Int) -> String)? = identifier == nil ? nil : { composeBundleNormalizedKey(for: identifier!($0 + range.start)) }
                                items(count: count, key: key) { index in
                                    let scopedContext = context.content(scope: self)
                                    let itemKey = key?(index) ?? String(index + range.start)  // ← ADD
                                    CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(itemKey)) {  // ← ADD
                                        factory(index + range.start, scopedContext).Render(context: scopedContext)
                                    }  // ← ADD
                                }
                            },
                            objectItems: { objects, identifier, _, _, _, _, factory in
                                let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objects[$0])) }
                                items(count: objects.count, key: key) { index in
                                    let scopedContext = context.content(scope: self)
                                    let itemKey = key(index)  // ← ADD
                                    CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(itemKey)) {  // ← ADD
                                        factory(objects[index], scopedContext).Render(context: scopedContext)
                                    }  // ← ADD
                                }
                            },
                            objectBindingItems: { objectsBinding, identifier, _, _, _, _, _, factory in
                                let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objectsBinding.wrappedValue[$0])) }
                                items(count: objectsBinding.wrappedValue.count, key: key) { index in
                                    let scopedContext = context.content(scope: self)
                                    let itemKey = key(index)  // ← ADD
                                    CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(itemKey)) {  // ← ADD
                                        factory(objectsBinding, index, scopedContext).Render(context: scopedContext)
                                    }  // ← ADD
                                }
                            },
```

**Close the `CompositionLocalProvider` wrapper** after the closing brace of `LazyColumn(...)` (before the `}` that closes the `EnvironmentValues.shared.setValues in:` block):

```swift
                    }  // closes LazyColumn
                    }  // closes CompositionLocalProvider(LocalPeerStore provides peerStore)
                    }  // closes EnvironmentValues.shared.setValues in:
```

#### Expected result (abbreviated diff)

```swift
                    } in: {
                    let peerStore = androidx.compose.runtime.remember { PeerStore() }
                    CompositionLocalProvider(LocalPeerStore provides peerStore) {
                    LazyColumn(state: listState, ...) {
                        itemCollector.value.initialize(
                            ...
                            indexedItems: { range, identifier, _, _, _, _, factory in
                                let count = range.endExclusive - range.start
                                let key: ((Int) -> String)? = ...
                                items(count: count, key: key) { index in
                                    let scopedContext = context.content(scope: self)
                                    let itemKey = key?(index) ?? String(index + range.start)
                                    CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(itemKey)) {
                                        factory(index + range.start, scopedContext).Render(context: scopedContext)
                                    }
                                }
                            },
                            // ... objectItems and objectBindingItems same pattern ...
                        )
                        ...
                    }
                    }  // closes CompositionLocalProvider(LocalPeerStore provides peerStore)
                    }  // closes EnvironmentValues.shared.setValues in:
```

---

### Step 5: Mirror to LazyHStack

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/LazyHStack.swift`

Apply the identical pattern as Step 4. The relevant section is the `LazyRow` block at line 89.

#### Current code (lines 83–115)

```swift
// File: forks/skip-ui/Sources/SkipUI/SkipUI/Containers/LazyHStack.swift, lines 83–115
            EnvironmentValues.shared.setValues {
                $0.set_scrollTargetBehavior(nil)
                return ComposeResult.ok
            } in: {
                let contentPadding = EnvironmentValues.shared._contentPadding
                EnvironmentValues.shared.setValues {
                    $0.set_contentPadding(EdgeInsets())
                    return ComposeResult.ok
                } in: {
                LazyRow(state: listState, modifier: modifier, horizontalArrangement: rowArrangement, verticalAlignment: rowAlignment, contentPadding: contentPadding.asPaddingValues(), userScrollEnabled: isScrollEnabled, flingBehavior: flingBehavior) {
                    itemCollector.value.initialize(
                        startItemIndex: 0,
                        item: { renderable, _ in
                            item {
                                renderable.Render(context: context.content(scope: self))
                            }
                        },
                        indexedItems: { range, identifier, _, _, _, _, factory in
                            let count = range.endExclusive - range.start
                            let key: ((Int) -> String)? = identifier == nil ? nil : { composeBundleNormalizedKey(for: identifier!($0 + range.start)) }
                            items(count: count, key: key) { index in
                                factory(index + range.start, context.content(scope: self)).Render(context: context.content(scope: self))
                            }
                        },
                        objectItems: { objects, identifier, _, _, _, _, factory in
                            let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objects[$0])) }
                            items(count: objects.count, key: key) { index in
                                factory(objects[index], context.content(scope: self)).Render(context: context.content(scope: self))
                            }
                        },
                        objectBindingItems: { objectsBinding, identifier, _, _, _, _, _, factory in
                            let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objectsBinding.wrappedValue[$0])) }
                            items(count: objectsBinding.wrappedValue.count, key: key) { index in
                                factory(objectsBinding, index, context.content(scope: self)).Render(context: context.content(scope: self))
                            }
                        },
```

#### What to change

Same structure as LazyVStack. Insert `PeerStore` creation and `CompositionLocalProvider` wrapper around `LazyRow`. Note that LazyHStack uses `context.content(scope: self)` inline (no `scopedContext` variable), so the item key provision wraps the render call directly:

```swift
                } in: {
                let peerStore = androidx.compose.runtime.remember { PeerStore() }  // ← ADD
                CompositionLocalProvider(LocalPeerStore provides peerStore) {       // ← ADD
                LazyRow(...) {
                    itemCollector.value.initialize(
                        ...
                        indexedItems: { range, identifier, _, _, _, _, factory in
                            let count = range.endExclusive - range.start
                            let key: ((Int) -> String)? = identifier == nil ? nil : { composeBundleNormalizedKey(for: identifier!($0 + range.start)) }
                            items(count: count, key: key) { index in
                                let itemKey = key?(index) ?? String(index + range.start)  // ← ADD
                                CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(itemKey)) {  // ← ADD
                                    factory(index + range.start, context.content(scope: self)).Render(context: context.content(scope: self))
                                }  // ← ADD
                            }
                        },
                        objectItems: { objects, identifier, _, _, _, _, factory in
                            let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objects[$0])) }
                            items(count: objects.count, key: key) { index in
                                let itemKey = key(index)  // ← ADD
                                CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(itemKey)) {  // ← ADD
                                    factory(objects[index], context.content(scope: self)).Render(context: context.content(scope: self))
                                }  // ← ADD
                            }
                        },
                        objectBindingItems: { objectsBinding, identifier, _, _, _, _, _, factory in
                            let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objectsBinding.wrappedValue[$0])) }
                            items(count: objectsBinding.wrappedValue.count, key: key) { index in
                                let itemKey = key(index)  // ← ADD
                                CompositionLocalProvider(LocalPeerStoreItemKey provides AnyHashable(itemKey)) {  // ← ADD
                                    factory(objectsBinding, index, context.content(scope: self)).Render(context: context.content(scope: self))
                                }  // ← ADD
                            }
                        },
                        ...
                    )
                    ...
                }
                }  // closes CompositionLocalProvider(LocalPeerStore provides peerStore)  ← ADD
                }  // closes EnvironmentValues.shared.setValues in:
```

---

### Step 6: TabView PeerStore provider

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/TabView.swift`

The `RenderTabViewContent` method contains the `NavHost` that manages tab navigation. Peers must survive tab switches — the `PeerStore` must be created **outside** `NavHost` (so it isn't discarded when the host resets), and each tab route must provide a namespace so peers from different tabs don't alias.

#### Current code (lines 381–424)

```swift
// File: forks/skip-ui/Sources/SkipUI/SkipUI/Containers/TabView.swift, lines 381–424
        IgnoresSafeAreaLayout(expandInto: ignoresSafeAreaEdges) { _, _ in
            ComposeContainer(modifier: context.modifier, fillWidth: true, fillHeight: true) { modifier in
                // Don't use a Scaffold: it clips content beyond its bounds and prevents .ignoresSafeArea modifiers from working
                Column(modifier: modifier.background(Color.background.colorImpl())) {
                    NavHost(navController,
                            modifier: Modifier.fillMaxWidth().weight(Float(1.0)),
                            startDestination: "0",
                            enterTransition: { fadeIn() },
                            exitTransition: { fadeOut() }) {
                        // Use a constant number of routes. Changing routes causes a NavHost to reset its state
                        let entryContext = context.content()
                        for tabIndex in 0..<100 {
                            composable(String(describing: tabIndex)) { _ in
                                // Inset manually where our container ignored the safe area, but we aren't showing a bar
                                let topPadding = ignoresSafeAreaEdges.contains(.top) ? WindowInsets.safeDrawing.asPaddingValues().calculateTopPadding() : 0.dp
                                var bottomPadding = 0.dp
                                if bottomBarTopPx.value <= Float(0.0) && ignoresSafeAreaEdges.contains(.bottom) {
                                    bottomPadding = max(0.dp, WindowInsets.safeDrawing.asPaddingValues().calculateBottomPadding() - WindowInsets.ime.asPaddingValues().calculateBottomPadding())
                                }
                                let contentModifier = Modifier.fillMaxSize().padding(top: topPadding, bottom: bottomPadding)
                                let contentSafeArea = safeArea?.insetting(.bottom, to: bottomBarTopPx.value)

                                // Special-case the first composition to avoid seeing the layout adjust. This is a common
                                // issue with nav stacks in particular, and they're common enough that we need to cater to them.
                                // Use an extra container to avoid causing the content itself to recompose
                                let hasComposed = remember { mutableStateOf(false) }
                                SideEffect { hasComposed.value = true }
                                let alpha = hasComposed.value ? Float(1.0) : Float(0.0)
                                Box(modifier: Modifier.alpha(alpha), contentAlignment: androidx.compose.ui.Alignment.Center) {
                                    // This block is called multiple times on tab switch. Use stable arguments that will prevent our entry from
                                    // recomposing when called with the same values
                                    let arguments = TabEntryArguments(tabIndex: tabIndex, modifier: contentModifier, safeArea: contentSafeArea)
                                    PreferenceValues.shared.collectPreferences([tabBarPreferencesCollector]) {
                                        RenderEntry(with: arguments, context: entryContext)
                                    }
                                }
                            }
                        }
                    }
                    bottomBar()
                }
            }
        }
```

#### `RenderEntry` method (lines 426–442)

```swift
// File: forks/skip-ui/Sources/SkipUI/SkipUI/Containers/TabView.swift, lines 426–442
    @Composable private func RenderEntry(with arguments: TabEntryArguments, context: ComposeContext) {
        // WARNING: This function is a potential recomposition hotspot. It should not need to be called
        // multiple times for the same tab on tab change. Test after modifications
        Box(modifier: arguments.modifier, contentAlignment: androidx.compose.ui.Alignment.Center) {
            EnvironmentValues.shared.setValues {
                if let safeArea = arguments.safeArea {
                    $0.set_safeArea(safeArea)
                }
                return ComposeResult.ok
            } in: {
                let renderables = EvaluateContent(context: context)
                if renderables.size > arguments.tabIndex {
                    renderables[arguments.tabIndex].Render(context: context)
                }
            }
        }
    }
```

#### What to change

**In `RenderTabViewContent`**: Create a single `PeerStore` before `NavHost` and wrap `NavHost` with `CompositionLocalProvider`. Inside each `composable(route)` block, wrap `RenderEntry` with a namespace provider.

Insert `PeerStore` creation before `NavHost` (inside `Column`, after its `{`):

```swift
                Column(modifier: modifier.background(Color.background.colorImpl())) {
                    // ← INSERT: single PeerStore for all tabs — must live outside NavHost
                    let tabPeerStore = remember { PeerStore() }
                    CompositionLocalProvider(LocalPeerStore provides tabPeerStore) {  // ← INSERT
                    NavHost(navController,
                            modifier: Modifier.fillMaxWidth().weight(Float(1.0)),
                            startDestination: "0",
                            enterTransition: { fadeIn() },
                            exitTransition: { fadeOut() }) {
                        let entryContext = context.content()
                        for tabIndex in 0..<100 {
                            composable(String(describing: tabIndex)) { _ in
                                // ... padding/safeArea setup unchanged ...
                                Box(modifier: Modifier.alpha(alpha), ...) {
                                    let arguments = TabEntryArguments(tabIndex: tabIndex, modifier: contentModifier, safeArea: contentSafeArea)
                                    // ← WRAP: provide route as namespace for this tab's peers
                                    CompositionLocalProvider(LocalPeerStoreNamespace provides AnyHashable(String(describing: tabIndex))) {  // ← INSERT
                                        PreferenceValues.shared.collectPreferences([tabBarPreferencesCollector]) {
                                            RenderEntry(with: arguments, context: entryContext)
                                        }
                                    }  // ← INSERT: closes CompositionLocalProvider(LocalPeerStoreNamespace)
                                }
                            }
                        }
                    }
                    }  // ← INSERT: closes CompositionLocalProvider(LocalPeerStore provides tabPeerStore)
                    bottomBar()
                }
```

The `RenderEntry` method itself does **not** need changes — item-level `LocalPeerStoreItemKey` is provided by `IdentityKeyModifier.Render` (Step 2) on each tab's content renderable.

#### Expected result (abbreviated)

```swift
                Column(modifier: modifier.background(Color.background.colorImpl())) {
                    let tabPeerStore = remember { PeerStore() }
                    CompositionLocalProvider(LocalPeerStore provides tabPeerStore) {
                    NavHost(...) {
                        let entryContext = context.content()
                        for tabIndex in 0..<100 {
                            composable(String(describing: tabIndex)) { _ in
                                // ... unchanged padding/alpha setup ...
                                Box(...) {
                                    let arguments = TabEntryArguments(...)
                                    CompositionLocalProvider(LocalPeerStoreNamespace provides AnyHashable(String(describing: tabIndex))) {
                                        PreferenceValues.shared.collectPreferences([tabBarPreferencesCollector]) {
                                            RenderEntry(with: arguments, context: entryContext)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }
                    bottomBar()
                }
```

---

### Step 7: Transpiler changes

**File:** `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift`

The transpiler currently generates per-view `SwiftPeerHandle` class definitions and uses `remember { SwiftPeerHandle(...) }` / `remember(hash) { SwiftPeerHandle(...) }` for peer survival. This step replaces that with `skip.ui.rememberViewPeer(...)` calls so the PeerStore path is used when a store is in scope.

There are **four** sites to change: the two class/external generation sites (lines 1632–1698) and the two usage sites (`_ComposeContent` at lines 1777–1785 and `swiftUIEvaluate` at lines 1835–1841).

#### 7a. Phase 1 helper generation (lines 1632–1651): remove `SwiftPeerHandle` class, keep `Swift_retain`

**Current code (lines 1632–1651):**

```swift
// File: forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift, lines 1632–1651
        if canRememberPeer || canRememberPeerWithInputCheck {
            if canRememberPeer {
                // Generate SwiftPeerHandle helper class and Swift_retain external function for peer remembering
                let peerHandleClass = KotlinRawStatement(sourceCode: "private class SwiftPeerHandle(val peer: Long, private val retainFn: (Long) -> Unit, private val releaseFn: (Long) -> Unit) : androidx.compose.runtime.RememberObserver { init { retainFn(peer) }; fun swapFrom(stale: Long) { retainFn(peer); releaseFn(stale) }; override fun onRemembered() {}; override fun onAbandoned() { releaseFn(peer) }; override fun onForgotten() { releaseFn(peer) } }")
                statements.append(peerHandleClass)
                let retainExternal = KotlinRawStatement(sourceCode: "private external fun Swift_retain(Swift_peer: skip.bridge.SwiftObjectPointer)")
                statements.append(retainExternal)

                let classType = ClassType(classDeclaration)
                let retainCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_retain", translator: translator)
                var retainBody: [String] = []
                switch classType {
                case .generic:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature.typeErasedClass).self)")
                case .reference:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature).self)")
                default:
                    retainBody.append("_ = Swift_peer.retained(as: SwiftValueTypeBox<\(classDeclaration.signature)>.self)")
                }
                cdeclFunctions.append(CDeclFunction(name: retainCdecl.cdeclFunctionName, cdecl: retainCdecl.cdecl, signature: .function([classType.peerSwiftParameter], .void, APIFlags(), nil), body: retainBody))
```

**What to replace** — remove the `peerHandleClass` generation; keep `Swift_retain` external and cdecl:

```swift
        if canRememberPeer || canRememberPeerWithInputCheck {
            if canRememberPeer {
                // Generate Swift_retain external function for rememberViewPeer
                // (SwiftPeerHandle class is no longer generated here — it lives in PeerStore.swift)
                let retainExternal = KotlinRawStatement(sourceCode: "private external fun Swift_retain(Swift_peer: skip.bridge.SwiftObjectPointer)")
                statements.append(retainExternal)

                let classType = ClassType(classDeclaration)
                let retainCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_retain", translator: translator)
                var retainBody: [String] = []
                switch classType {
                case .generic:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature.typeErasedClass).self)")
                case .reference:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature).self)")
                default:
                    retainBody.append("_ = Swift_peer.retained(as: SwiftValueTypeBox<\(classDeclaration.signature)>.self)")
                }
                cdeclFunctions.append(CDeclFunction(name: retainCdecl.cdeclFunctionName, cdecl: retainCdecl.cdecl, signature: .function([classType.peerSwiftParameter], .void, APIFlags(), nil), body: retainBody))
```

#### 7b. Phase 2 helper generation (lines 1652–1698): remove `SwiftPeerHandle` class, add `Swift_refreshPeer`, keep others

**Current code (lines 1652–1698):**

```swift
// File: forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift, lines 1652–1698
            } else if canRememberPeerWithInputCheck {
                // Phase 2: Generate SwiftPeerHandle (same shape as Phase 1), Swift_inputsHash, and Swift_retain
                // Uses remember(key) with inputsHash as key — Compose handles invalidation automatically
                let peerHandleClass = KotlinRawStatement(sourceCode: "private class SwiftPeerHandle(val peer: Long, private val retainFn: (Long) -> Unit, private val releaseFn: (Long) -> Unit) : androidx.compose.runtime.RememberObserver { init { retainFn(peer) }; fun swapFrom(stale: Long) { retainFn(peer); releaseFn(stale) }; override fun onRemembered() {}; override fun onAbandoned() { releaseFn(peer) }; override fun onForgotten() { releaseFn(peer) } }")
                statements.append(peerHandleClass)
                let inputsHashExternal = KotlinRawStatement(sourceCode: "private external fun Swift_inputsHash(Swift_peer: skip.bridge.SwiftObjectPointer): Long")
                statements.append(inputsHashExternal)
                let retainExternal = KotlinRawStatement(sourceCode: "private external fun Swift_retain(Swift_peer: skip.bridge.SwiftObjectPointer)")
                statements.append(retainExternal)

                let classType = ClassType(classDeclaration)

                // Generate Swift_inputsHash cdecl
                let inputsHashCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_inputsHash", translator: translator)
                var inputsHashBody: [String] = []
                switch classType {
                case .generic:
                    inputsHashBody.append("let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!")
                case .reference:
                    inputsHashBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                default:
                    inputsHashBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                }
                inputsHashBody.append("var hasher = Hasher()")
                for paramName in allConstructorParamNames {
                    let access = classType == .value ? "peer_swift.value.\(paramName)" : "peer_swift.\(paramName)"
                    // Only hash value-semantic types. Reference types (classes) are skipped because
                    // their identity/hash is allocation-based and unstable across recompositions
                    // (e.g. TCA Store scopes are recreated when sibling array elements change).
                    inputsHashBody.append("if !(type(of: \(access)) is AnyClass), let h = \(access) as? AnyHashable { hasher.combine(h) }")
                }
                inputsHashBody.append("return Int64(hasher.finalize())")
                cdeclFunctions.append(CDeclFunction(name: inputsHashCdecl.cdeclFunctionName, cdecl: inputsHashCdecl.cdecl, signature: .function([classType.peerSwiftParameter], .int64, APIFlags(), nil), body: inputsHashBody))

                // Generate Swift_retain cdecl (same as Phase 1)
                let retainCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_retain", translator: translator)
                var retainBody: [String] = []
                switch classType {
                case .generic:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature.typeErasedClass).self)")
                case .reference:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature).self)")
                default:
                    retainBody.append("_ = Swift_peer.retained(as: SwiftValueTypeBox<\(classDeclaration.signature)>.self)")
                }
                cdeclFunctions.append(CDeclFunction(name: retainCdecl.cdeclFunctionName, cdecl: retainCdecl.cdecl, signature: .function([classType.peerSwiftParameter], .void, APIFlags(), nil), body: retainBody))
            }
        }
```

**What to replace** — remove `peerHandleClass`, keep `Swift_inputsHash` and `Swift_retain`, and **add** `Swift_refreshPeer` generation:

```swift
            } else if canRememberPeerWithInputCheck {
                // Phase 2: Generate Swift_inputsHash, Swift_retain, and Swift_refreshPeer externals
                // (SwiftPeerHandle class is no longer generated here — it lives in PeerStore.swift)
                let inputsHashExternal = KotlinRawStatement(sourceCode: "private external fun Swift_inputsHash(Swift_peer: skip.bridge.SwiftObjectPointer): Long")
                statements.append(inputsHashExternal)
                let retainExternal = KotlinRawStatement(sourceCode: "private external fun Swift_retain(Swift_peer: skip.bridge.SwiftObjectPointer)")
                statements.append(retainExternal)
                let refreshPeerExternal = KotlinRawStatement(sourceCode: "private external fun Swift_refreshPeer(Swift_peer: skip.bridge.SwiftObjectPointer, fresh_peer: skip.bridge.SwiftObjectPointer)")
                statements.append(refreshPeerExternal)

                let classType = ClassType(classDeclaration)

                // Generate Swift_inputsHash cdecl (unchanged)
                let inputsHashCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_inputsHash", translator: translator)
                var inputsHashBody: [String] = []
                switch classType {
                case .generic:
                    inputsHashBody.append("let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!")
                case .reference:
                    inputsHashBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                default:
                    inputsHashBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                }
                inputsHashBody.append("var hasher = Hasher()")
                for paramName in allConstructorParamNames {
                    let access = classType == .value ? "peer_swift.value.\(paramName)" : "peer_swift.\(paramName)"
                    inputsHashBody.append("if !(type(of: \(access)) is AnyClass), let h = \(access) as? AnyHashable { hasher.combine(h) }")
                }
                inputsHashBody.append("return Int64(hasher.finalize())")
                cdeclFunctions.append(CDeclFunction(name: inputsHashCdecl.cdeclFunctionName, cdecl: inputsHashCdecl.cdecl, signature: .function([classType.peerSwiftParameter], .int64, APIFlags(), nil), body: inputsHashBody))

                // Generate Swift_retain cdecl (unchanged)
                let retainCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_retain", translator: translator)
                var retainBody: [String] = []
                switch classType {
                case .generic:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature.typeErasedClass).self)")
                case .reference:
                    retainBody.append("_ = Swift_peer.retained(as: \(classDeclaration.signature).self)")
                default:
                    retainBody.append("_ = Swift_peer.retained(as: SwiftValueTypeBox<\(classDeclaration.signature)>.self)")
                }
                cdeclFunctions.append(CDeclFunction(name: retainCdecl.cdeclFunctionName, cdecl: retainCdecl.cdecl, signature: .function([classType.peerSwiftParameter], .void, APIFlags(), nil), body: retainBody))

                // Generate Swift_refreshPeer cdecl — copies constructor params from fresh peer into cached peer.
                // The cached peer keeps its let-with-default state; only constructor params are updated.
                let refreshPeerCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_refreshPeer", translator: translator)
                var refreshPeerBody: [String] = []
                switch classType {
                case .generic:
                    refreshPeerBody.append("var cached_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!")
                    refreshPeerBody.append("let fresh_swift: \(classDeclaration.signature.typeErasedClass) = fresh_peer.pointee()!")
                case .reference:
                    refreshPeerBody.append("var cached_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                    refreshPeerBody.append("let fresh_swift: \(classDeclaration.signature) = fresh_peer.pointee()!")
                default:
                    refreshPeerBody.append("var cached_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                    refreshPeerBody.append("let fresh_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = fresh_peer.pointee()!")
                }
                for paramName in allConstructorParamNames {
                    let cachedAccess = classType == .value ? "cached_swift.value.\(paramName)" : "cached_swift.\(paramName)"
                    let freshAccess = classType == .value ? "fresh_swift.value.\(paramName)" : "fresh_swift.\(paramName)"
                    refreshPeerBody.append("\(cachedAccess) = \(freshAccess)")
                }
                // refreshPeer takes two peer parameters: cached + fresh
                let refreshPeerParams = [classType.peerSwiftParameter,
                                         Parameter<SwiftExpression>(externalLabel: "fresh_peer", declaredType: .named("skip.bridge.SwiftObjectPointer", []), apiFlags: APIFlags())]
                cdeclFunctions.append(CDeclFunction(name: refreshPeerCdecl.cdeclFunctionName, cdecl: refreshPeerCdecl.cdecl, signature: .function(refreshPeerParams, .void, APIFlags(), nil), body: refreshPeerBody))
            }
        }
```

#### 7c. `_ComposeContent` override usage (lines 1777–1785)

**Current code:**

```swift
// File: forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift, lines 1777–1785
            var composeContentKotlin: [String] = []
            if canRememberPeer {
                composeContentKotlin.append("val peerHandle = androidx.compose.runtime.remember { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }")
                composeContentKotlin.append("val swapped = peerHandle.peer != Swift_peer")
                composeContentKotlin.append("if (swapped) { peerHandle.swapFrom(Swift_peer); Swift_peer = peerHandle.peer }")
            } else {
                composeContentKotlin.append("val currentHash = Swift_inputsHash(Swift_peer)")
                composeContentKotlin.append("val peerHandle = androidx.compose.runtime.remember(currentHash) { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }")
                composeContentKotlin.append("val swapped = peerHandle.peer != Swift_peer")
                composeContentKotlin.append("if (swapped) { peerHandle.swapFrom(Swift_peer); Swift_peer = peerHandle.peer }")
            }
```

**What to replace:**

```swift
            var composeContentKotlin: [String] = []
            if canRememberPeer {
                composeContentKotlin.append("Swift_peer = skip.ui.rememberViewPeer(slotKey = \"\(classDeclaration.signature)\", peer = Swift_peer, retainFn = ::Swift_retain, releaseFn = ::Swift_release)")
            } else {
                composeContentKotlin.append("val currentHash = Swift_inputsHash(Swift_peer)")
                composeContentKotlin.append("Swift_peer = skip.ui.rememberViewPeer(slotKey = \"\(classDeclaration.signature)\", peer = Swift_peer, retainFn = ::Swift_retain, releaseFn = ::Swift_release, inputsHash = currentHash, refreshPeerFn = ::Swift_refreshPeer)")
            }
```

`slotKey` is a fully-qualified Kotlin type name used to distinguish same-structural-position siblings of different types. `classDeclaration.signature` produces this string (e.g. `"com.example.app.CounterCard"`).

#### 7d. `swiftUIEvaluate` function usage (lines 1835–1841)

**Current code:**

```swift
// File: forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift, lines 1835–1841
        let classType = ClassType(classDeclaration)
        var bodyKotlin: [String] = []
        if canRememberPeer {
            bodyKotlin.append("val peerHandle = androidx.compose.runtime.remember { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }")
            bodyKotlin.append("if (peerHandle.peer != Swift_peer) { peerHandle.swapFrom(Swift_peer); Swift_peer = peerHandle.peer }")
        } else if canRememberPeerWithInputCheck {
            bodyKotlin.append("val currentHash = Swift_inputsHash(Swift_peer)")
            bodyKotlin.append("val peerHandle = androidx.compose.runtime.remember(currentHash) { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }")
            bodyKotlin.append("if (peerHandle.peer != Swift_peer) { peerHandle.swapFrom(Swift_peer); Swift_peer = peerHandle.peer }")
        }
```

**What to replace:**

```swift
        let classType = ClassType(classDeclaration)
        var bodyKotlin: [String] = []
        if canRememberPeer {
            bodyKotlin.append("Swift_peer = skip.ui.rememberViewPeer(slotKey = \"\(classDeclaration.signature)\", peer = Swift_peer, retainFn = ::Swift_retain, releaseFn = ::Swift_release)")
        } else if canRememberPeerWithInputCheck {
            bodyKotlin.append("val currentHash = Swift_inputsHash(Swift_peer)")
            bodyKotlin.append("Swift_peer = skip.ui.rememberViewPeer(slotKey = \"\(classDeclaration.signature)\", peer = Swift_peer, retainFn = ::Swift_retain, releaseFn = ::Swift_release, inputsHash = currentHash, refreshPeerFn = ::Swift_refreshPeer)")
        }
```

---

### Step 8: Transpiler tests

**File:** `forks/skipstone/Tests/SkipSyntaxTests/BridgeToKotlinTests.swift`

- Update `testInternalViewPeerRemember`: assert `skip.ui.rememberViewPeer(` present, `SwiftPeerHandle` absent in generated output
- Update `testMixedStateAndLetWithDefaultPeerRemember`: assert `Swift_refreshPeer`, `inputsHash`, `refreshPeerFn` present; `SwiftPeerHandle` absent
- Add new test: verify `Swift_refreshPeer` cdecl is generated and reconstructs struct with constructor params from fresh peer

---

## E2E Test Plan

| Test | Section | Verification |
|------|---------|-------------|
| Lazy scroll survival | 6 | Scroll item off-screen and back. instanceID and counter preserved. |
| Lazy add/delete | 6 | Add cards, delete middle card. Remaining cards keep counter + instanceID. |
| Tab switch survival | 5/7 | Switch tabs, switch back. Counter and instanceID preserved for keyed content. |
| Input refresh | 1/6 | Change CounterCard's title. Title updates, instanceID stays same. |
| Eviction on removal | 6 | Remove item from ForEach, verify peer freed (no memory leak). |
| Non-keyed fallback | 7 | PeerRememberTestView (no item key) in static tab content. Falls back to `remember`. |

---

## Edge Cases

| Edge Case | Resolution |
|-----------|-----------|
| Fresh peer leaked on store insert | `insert` retains; bridge's original retain pairs with K1.finalize() |
| Fresh peer leaked on store hit | `retainFn(cached.peer)` for K2 pairs with K2.finalize(); `releaseFn(peer)` drops fresh P2 |
| GC thread racing with retain | Store holds its own retain, peer never reaches 0 while store owns it |
| Thread safety | PeerStore is composition-thread-only, consistent with skip-ui model |
| Eviction during exit animation | Safe for LazyVStack (no `animateItem()`). Defer List.swift to follow-up |
| Store present but itemKey null | Falls back to `remember`-based path. No aliasing |
| Multiple same-type siblings (no item key) | Documented limitation: falls back to `remember` |
| Namespace composition (nested ForEach) | `PeerNamespacePath` composes parent + current into hashable path |

---

## Open Questions

1. **List.swift**: Should we add PeerStore? Uses `animateItem()` so SideEffect eviction may be too aggressive. Recommendation: defer.
2. **Structural path for unkeyed tab siblings**: If limitation becomes real issue, add path counter to cache key. Not needed now.
3. **`Swift_refreshPeer` for reference-type views**: Scoped to value types only. Not needed for current scope.
