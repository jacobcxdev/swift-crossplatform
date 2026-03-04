# Synthesis: Canonical View Identity Approach for SkipUI

> **Author:** OpenAI Codex (synthesised from 8 independent position papers)
> **Date:** 2026-03-01
> **Status:** Canonical recommendation
> **Input papers:** 01-swiftui-parity-purist, 02-compose-native-advocate, 03-protocol-designer, 04-transpiler-maximalist, 05-pragmatic-minimalist, 06-upstream-reviewer, 07-devils-advocate, 08-cross-framework-comparator

---

## 1. Points of Universal Agreement

Every paper — regardless of position — agrees on the following:

- **The current `.id()` path is wrong.** Raw bridged values must not flow into Compose identity unchanged. Keys must be normalized to simple Compose-safe values before comparison or persistence (Papers 1, 2, 3, 5, 6, 7, 8).

- **Data-driven sibling identity is the load-bearing case.** `ForEach` items must survive insert, delete, and reorder by data ID rather than position. No paper argues that pure positional identity is sufficient for dynamic collections (Papers 1, 2, 5, 6, 7, 8).

- **The real risk surface is runtime container consumption, not evaluation-time tricks.** Even papers that want more parity still rely on container-level `key()` at the point siblings are rendered (Papers 1, 3, 4, context docs).

- **`AnimatedContent` is the only risky mechanical change.** Every paper that treats this seriously either calls it out as the first path to test or the first path that can regress silently (Papers 5, 6, 7, context docs).

---

## 2. Key Tensions and Their Resolution

### Tension A: SwiftUI parity vs Compose-native minimalism

Paper 1 wants full semantic parity. Papers 2, 5, and 7 argue for bridging only the real mismatches.

**Resolution:** Match SwiftUI where developers explicitly depend on identity contracts, and stop there. That means `ForEach`, `.id()`, selection tags, and keyed sibling groups. It does not mean transpiler-emitted structural IDs for every branch or `AnyView` parity now.

### Tension B: Architectural cleanliness vs upstream maintainability

Papers 3 and 8 are right that identity, explicit reset, and selection are different semantics. Paper 6 is right that a public `Renderable` protocol break is the wrong way to encode that.

**Resolution:** Internal separation of channels, not public API expansion. `Renderable`'s public surface stays unchanged.

### Tension C: One key channel vs three channels

The single-channel design is smaller, but it loses an essential case: a child inside `ForEach` can have both stable item identity and its own `.id()` reset semantics. The semantics must be three-channel. What loses is making those three channels public protocol requirements.

**Resolution:** Three internal channels (`siblingKey`, `explicitResetKey`, `selectionTag`) carried by an internal wrapper. Not protocol requirements.

### Tension D: Surgical patching vs universal runtime rule

Paper 5's triage is useful for rollout order. Paper 1 is right that the runtime needs one canonical rule.

**Resolution:** One shared container helper for all sibling iteration sites, rolled out in risk order (safe sites first, AnimatedContent only after tests pass).

---

## 3. The Canonical Recommended Approach

### 3.1 Keep `Renderable` public surface unchanged

```swift
public protocol Renderable {
    @Composable func Render(context: ComposeContext)
}
```

Do not add `identityKey`, `selectionTag`, or `explicitID` as public protocol requirements. Paper 6 is correct that this is an unnecessary upstream-breaking change.

### 3.2 Internal identity side channel

Add an internal wrapper type and metadata struct:

```swift
internal enum ComposeIdentityKey: Hashable {
    case int(Int)
    case long(Int64)
    case string(String)
}

internal struct IdentityMetadata {
    var siblingKey: ComposeIdentityKey?
    var explicitResetKey: ComposeIdentityKey?
    var selectionTag: Any?
}

internal struct IdentityWrappedRenderable: Renderable {
    let content: Renderable
    let identity: IdentityMetadata
}
```

### 3.3 One producer-side normalizer

```swift
internal func normalizeIdentityKey(_ raw: Any?) -> ComposeIdentityKey?
```

**Rules for `normalizeIdentityKey`:**
- Accept `String`, `Int`, `Int64` directly.
- Normalize `UUID`, enums with raw values, `Identifiable.id`, and optionals to one of those simple forms.
- Never rely on raw `SwiftHashable` equality across JNI.
- Normalize once, at the producer. Consumers receive already-safe values.

This replaces the three existing normalisation paths (`composeKeyValue`, `composeBundleString`, raw `Any`). One function, called once.

### 3.4 How identity is produced

- **`ForEach`** assigns `siblingKey` from its item ID and wraps each emitted root renderable in `IdentityWrappedRenderable`.
- **`.id(value)`** assigns `explicitResetKey = normalizeIdentityKey(value)` and still wraps its subtree in `key(explicitResetKey)` for state destruction semantics.
- **`.tag(value)`** assigns `selectionTag = value` only. It does **not** call `key()`. `.tag()` is a data annotation, not a composition structure change.
- If a renderable already carries metadata, wrappers merge rather than overwrite.

### 3.5 How containers consume identity

Every runtime site that iterates sibling renderables uses the same rule:

```swift
// Canonical container loop — one rule, applied everywhere
for i in 0..<renderables.size {
    let renderable = renderables[i]
    let meta = (renderable as? IdentityWrappedRenderable)?.identity
    let baseKey: ComposeIdentityKey = meta?.siblingKey
        ?? meta?.explicitResetKey
        ?? .int(i)
    let safeKey = duplicateSafe(baseKey, index: i, seen: &seenKeys)
    androidx.compose.runtime.key(safeKey.value) {
        renderable.Render(context: contentContext)
    }
}
```

This rule applies to: `VStack`, `HStack`, `ZStack` (animated and non-animated paths), and any other true sibling-rendering container loop.

**Lazy containers** that already use native key APIs (`items(count:key:)`) keep using them, but their key source becomes the same normalized `siblingKey`.

### 3.6 How `ForEach` and `.id()` coexist

- `ForEach` owns sibling matching (via `siblingKey`).
- `.id()` owns subtree reset (via `explicitResetKey`).
- If both are present, parent containers use `siblingKey` first. The `.id()` modifier still creates an inner reset scope inside the `key(siblingKey)` group.

This is the important case that single-channel designs get wrong: a ForEach item with an explicit `.id()` for forced state reset should not confuse the container's sibling matching key with the reset key.

### 3.7 How `.tag()` interacts

- `.tag()` never affects lifecycle identity.
- `Picker` and `TabView` read `selectionTag` only.
- `TabView` selection and child identity stop sharing plumbing. If tabs need lifecycle identity, they get it from `ForEach` or `.id()`, not from selection tags.
- Duplicate selection tags are a control-level issue, not a Compose keying concern.

### 3.8 Duplicate key handling

- Detect duplicates per sibling group using a local `seenKeys` set per container loop.
- In debug builds: warn loudly.
- In release: disambiguate deterministically (e.g. `"\(key)_\(index)"`) so the app does not crash.
- Do **not** apply this disambiguation to `selectionTag`.

---

## 4. Phasing

### Phase 0: Write tests before touching `AnimatedContent`

Tests that must exist before any animated path is modified:
1. `ForEach` deletion/reorder in `VStack` — remaining items retain state
2. `ForEach` deletion/reorder in `HStack` — remaining items retain state
3. `ForEach` deletion/reorder in `ZStack` — remaining items retain state
4. `.id()` reset with non-primitive IDs (UUID, enum, custom Hashable) — state resets correctly
5. `AnimatedContent` in `VStack`: delete middle item — remaining items retain state AND enter/exit animations still fire

### Phase 1: Safe mechanical fixes (ship immediately)

These can be done before the architectural change and carry minimal risk:

| Fix | Location | Risk |
|-----|----------|------|
| Normalise `.id()` through `composeKeyValue()` | AdditionalViewModifiers.swift:1413, 1426 | Very low — one-line change |
| Add `key(composeKey ?? i)` to ZStack Box loops | ZStack.swift:58, 93 | Very low — follows existing VStack pattern |
| Add duplicate-key detection and disambiguation | VStack, HStack, ZStack container loops | Low — additive safety check |

### Phase 2: Introduce internal identity side channel (the canonical design change)

This is the core architectural change. It is upstream-friendly because `Renderable`'s public surface does not change.

1. Add `ComposeIdentityKey`, `IdentityMetadata`, `IdentityWrappedRenderable` internally.
2. Add `normalizeIdentityKey(_:)` replacing `composeKeyValue` and `composeBundleString`.
3. Migrate `ForEach` from `taggedRenderable` (producing `TagModifier(.tag)`) to `IdentityWrappedRenderable` (producing `siblingKey`).
4. Migrate `.id()` to set `explicitResetKey` and remove its current `key()` call from `TagModifier.Render` for the `.id` role (the inner reset `key()` moves to a dedicated `IDModifier.Render`).
5. Migrate `.tag()` to set `selectionTag` only — remove `key()` from `TagModifier.Render` for `.tag` role entirely.
6. Update `Picker` and `TabView` to read `selectionTag` instead of raw `.tag` modifier value.

### Phase 3: Apply the shared container helper to `AnimatedContent` paths

Only after Phase 0 tests pass for animated paths. Apply the canonical loop rule to:
- VStack AnimatedContent v0 (VStack.swift:224)
- VStack AnimatedContent v1+ (VStack.swift:250)
- HStack AnimatedContent v0 (HStack.swift:188)
- HStack AnimatedContent v1+ (HStack.swift:213)

### Phase 4: Lower-priority sibling loops

After Phase 3 is stable:
- Lazy section headers/footers (LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, List)
- Navigation toolbar item groups
- TabView tab identity (dynamic tab insertion/reorder)
- NavigationLink multi-child labels

### Phase 5: Transpiler peer-remembering guard (adjacent, independent)

Fix the `stateVariables.isEmpty` guard at `KotlinBridgeToKotlinVisitor.swift:1734` so views with both `@State` and `let`-with-default properties get both state syncing and peer remembering. This is a real gap (Paper 4, context doc gap 1) but is orthogonal to the identity model changes above. Ship as a separate, focused transpiler PR.

---

## 5. What We Explicitly Reject and Why

| Rejected Approach | Why |
|-------------------|-----|
| **Public `Renderable` protocol requirements for identity fields** | Paper 6 is correct: unnecessary upstream breakage for any code that implements `Renderable` directly. Internal separation achieves the same semantic clarity without the protocol-surface cost. |
| **Transpiler-injected structural IDs for `if/else` branches** | Papers 6 and 7 win on maintainability: fragile under refactors (moving a view changes its AST position, causing silent state loss on Android that cannot be reproduced on iOS), adds permanent transpiler complexity, and is not yet justified by verified user failures. Paper 7's observation that this creates unreproducible refactoring bugs is the decisive argument. |
| **Continuing to use `.tag()` as the identity carrier for `ForEach`** | Semantically wrong. Blocks a clean `.tag()`/`.id()` split. Creates the duplicate-key crash risk. Paper 3's decoupling analysis is correct. |
| **Raw `Any` or `SwiftHashable` values as Compose keys** | The foundational JNI equality problem that all sides agree must go away. Non-negotiable. |
| **"Patch only currently broken files and keep the model conflated forever"** | Patches symptoms but preserves the design ambiguity that created the gaps. Paper 7's warning about accumulating inconsistency across ad-hoc patches is correct. |
| **Shipping `AnimatedContent` key changes without tests** | Papers 5, 6, and 7 are correct to treat the `animateEnterExit` interaction as a silent-regression trap. The `key()` + `AnimatedContent` scope chain interaction is empirically unverified and must be tested before shipping. |
| **AnyView identity erasure parity** | Not justified by verified user failures. Compose's own structural recomposition provides acceptable coverage for the overwhelming majority of real `AnyView` usage. |
| **`ViewThatFits` state isolation** | Requires removing candidates from composition to prevent measurement, which defeats the purpose of `ViewThatFits`. Compose's behaviour (all candidates measured, only fitting one displayed) is correct for this use case. |

---

## Summary

The canonical answer is: **internal three-channel identity semantics, one normalized key type, `ForEach` produces sibling identity, `.id()` produces reset identity, `.tag()` is selection only, and every sibling-rendering container consumes identity through one shared helper.**

That is the smallest design that covers the verified use cases, does not break upstream `Renderable` consumers, and does not introduce fragile transpiler machinery that is invisible under refactoring. It provides a permanent fix rather than an accumulation of surgical patches, while respecting the rollout discipline (AnimatedContent last, behind tests) that the risk analysis demands.
