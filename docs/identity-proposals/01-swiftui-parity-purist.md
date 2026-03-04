# Position Paper: SwiftUI Identity Parity is Non-Negotiable

> **Position:** Full semantic fidelity with SwiftUI's view identity model
> **Author:** SwiftUI Parity Purist
> **Date:** 2026-03-01
> **Status:** Proposal

## Thesis

SwiftUI's view identity model is not a convenience feature -- it is a correctness contract. Every SwiftUI developer writes code that depends on identity semantics implicitly: `@State` lifetime, animation targeting, transition scoping, conditional branching, and list diffing all route through the identity system. If SkipUI diverges from these semantics even slightly, the result is not "degraded UX" -- it is **silent data corruption**. State attaches to the wrong view. Animations target phantom nodes. Transitions fire on views that should be stable. These bugs are impossible to diagnose because the developer's mental model (SwiftUI's identity contract) does not match the runtime behaviour (Compose's positional slot table).

SkipUI must replicate SwiftUI's identity semantics exactly, or it cannot claim to be a SwiftUI bridge.

---

## 1. Complete Enumeration of SwiftUI Identity Semantics

SwiftUI defines view identity through two orthogonal axes: **structural identity** (implicit, derived from position in the view hierarchy) and **explicit identity** (developer-assigned via `.id()` or data-driven via `ForEach`). Every semantic below is load-bearing -- removing any one creates a class of bugs.

### 1.1 Structural Identity

**S1. Type-based branching via `_ConditionalContent`:** When `@ViewBuilder` encounters `if/else`, it produces `_ConditionalContent<TrueContent, FalseContent>`. Each branch gets a distinct structural identity. Toggling the condition destroys one branch's state and creates the other's. This is not positional -- it is type-discriminated.

**S2. Positional identity within a container:** Two `Text` views in a `VStack` are distinguished by their position in the static view tree. Reordering them in source code changes their identity. This is compile-time, not runtime.

**S3. `AnyView` type erasure:** `AnyView` deliberately breaks structural identity. SwiftUI falls back to type-based heuristics and may destroy/recreate state when the wrapped type changes. Developers use `AnyView` knowing this cost.

**S4. Stable container slots:** A `VStack` with three children always has three identity slots. Adding a fourth child does not shift the identity of children 1-3 -- they remain in their original slots. Only dynamic content (ForEach, if/else) can change slot count.

### 1.2 Explicit Identity

**E1. `.id()` modifier -- state destruction:** `.id(value)` assigns an explicit identity. When `value` changes, SwiftUI destroys the view's state completely and creates a fresh instance. This is the primary mechanism for forcing state reset.

**E2. ForEach data-driven identity:** `ForEach(items, id: \.id)` assigns each item's identity from the data model. Insert, delete, and reorder operations are diffed by identity, not position. State follows the item, not the index.

**E3. `.tag()` for selection binding:** `.tag(value)` in `Picker` and `TabView` binds a view to a selection value. This is semantically distinct from structural identity -- it is a selection key, not a lifecycle key.

**E4. ForEach range identity:** `ForEach(0..<5)` uses the index as identity. This is a special case where positional and explicit identity coincide.

### 1.3 Identity-Dependent Behaviours

**B1. `@State` lifetime:** `@State` is scoped to identity. Same identity across renders = same state. Different identity = fresh state. This is the single most important invariant.

**B2. Animation targeting:** `withAnimation` targets identity-stable views. Compose's `AnimatedContent` must key on identity to animate the correct transitions.

**B3. Transition scoping:** `.transition()` fires when a view's identity appears or disappears. If identity is positional, transitions fire on the wrong views during list mutations.

**B4. `onAppear`/`onDisappear`:** These fire based on identity lifecycle. Positional identity causes spurious `onAppear` calls when items shift position.

**B5. Focus and scroll state:** `ScrollViewReader.scrollTo(id:)` targets explicit identity. Focus state is identity-scoped.

---

## 2. Current Implementation Grade

### Grading Scale
- **Pass:** Semantically equivalent to SwiftUI
- **Partial:** Works in common cases, fails in edge cases
- **Fail:** Fundamentally divergent from SwiftUI semantics

| # | Semantic | Grade | Evidence |
|---|----------|-------|----------|
| S1 | Conditional branching | **Fail** | No `_ConditionalContent` equivalent. `if/else` in `@ViewBuilder` produces a flat renderable list. Branch toggling shifts positions of subsequent views. (`skipui-identity-audit.md`, Semantics Gap 2) |
| S2 | Positional identity | **Partial** | Works in non-animated VStack/HStack paths (lines 131, 165 of `VStack.swift`). Fails in AnimatedContent paths (lines 224, 250), ZStack (line 58, 93), and 8 other containers. |
| S3 | AnyView erasure | **Fail** | `AnyView` transparently delegates `Evaluate`. No type-change detection, no state reset. (`skipui-identity-audit.md`, Semantics Gap 4) |
| S4 | Stable container slots | **Partial** | `key(composeKey ?? i)` in non-animated paths provides index-based stability. But index fallback means insertions at position 0 shift all subsequent identities -- unlike SwiftUI's static slot model. |
| E1 | `.id()` state destruction | **Partial** | `TagModifier` wraps in `key(value)` and resets `ComposeStateSaver`. But uses raw `SwiftHashable` values without `composeKeyValue()` normalisation (`AdditionalViewModifiers.swift:1413, 1426`). JNI equality failures cause either constant destruction or no destruction. |
| E2 | ForEach data identity | **Partial** | Works in non-animated VStack/HStack via `.tag()` + `composeKey`. Fails in ZStack, AnimatedContent, TabView, and any container that iterates renderables without `key()`. 14 unkeyed iteration paths identified. |
| E3 | `.tag()` selection | **Partial** | Works for Picker. TabView uses raw tag values without normalisation (`TabView.swift:478-482`). Tag/identity conflation means ForEach identity and selection semantics share one modifier. |
| E4 | ForEach range identity | **Pass** | Index used as default tag when no identifier provided (`ForEach.swift:125`). |
| B1 | `@State` lifetime | **Partial** | Correct when identity is correct. Incorrect whenever identity gaps cause state to attach to wrong view. Transpiler `stateVariables.isEmpty` guard (`KotlinBridgeToKotlinVisitor.swift:1734`) means views with both `@State` and `let`-with-default lose peer remembering. |
| B2 | Animation targeting | **Fail** | All 6 AnimatedContent paths (VStack x2, HStack x2, ZStack x2) iterate without per-item `key()`. Animations target positional slots, not identity-stable views. |
| B3 | Transition scoping | **Fail** | Transitions in AnimatedContent use `animateEnterExit` on positionally-matched views. Deleting item N causes item N+1's view to receive item N's exit transition. |
| B4 | onAppear/onDisappear | **Partial** | Fires correctly in keyed paths. Fires spuriously in the 14 unkeyed paths. |
| B5 | Focus/scroll identity | **Partial** | `ScrollViewReader` exists but identity depends on `.id()` normalisation, which is broken (E1). |

**Summary:** 3 Pass/near-Pass, 8 Partial, 4 Fail. The system works for the happy path (non-animated VStack/HStack with ForEach) and breaks everywhere else.

---

## 3. The Ideal Solution: Unified Identity Layer

The correct fix is a **single, first-class identity property on `Renderable`** that every container consumes uniformly, plus a **branch discriminator** that recovers `_ConditionalContent` semantics.

### 3.1 `Renderable` Protocol Extension

```swift
// Renderable.swift — additions to the Renderable protocol
public protocol Renderable {
    #if SKIP
    @Composable func Render(context: ComposeContext)

    /// The identity key for this renderable within its sibling scope.
    /// Set by ForEach (data identity), `.id()` (explicit identity), or
    /// the transpiler (structural identity). Consumed by ALL containers.
    /// nil means "use positional identity" (index fallback).
    var identityKey: Any? { get }

    /// Selection tag for Picker/TabView binding. Semantically distinct
    /// from identity — does not affect lifecycle or state scoping.
    var selectionTag: Any? { get }

    /// Explicit ID from `.id()` modifier. When this changes, the view's
    /// entire state subtree must be destroyed and recreated.
    var explicitID: Any? { get }
    #endif
}
```

Default implementations return `nil`. This separates three concerns currently conflated in `TagModifier`:

1. **`identityKey`** -- consumed by container `key()` calls. Set by ForEach during `Evaluate` (from `identifier` closure), or by `.id()` modifier. Always normalised through `composeKeyValue()` at assignment time, never at consumption time.

2. **`selectionTag`** -- consumed by Picker and TabView for selection binding. Raw value, no normalisation needed (compared within Swift, not Compose).

3. **`explicitID`** -- consumed by state management. When non-nil and changed, triggers `ComposeStateSaver` reset and `remember` cache invalidation. Also normalised through `composeKeyValue()`.

### 3.2 Structural Identity via Transpiler Injection

For `_ConditionalContent` parity, the transpiler should inject a branch discriminator:

```kotlin
// Generated by KotlinBridgeToKotlinVisitor for if/else in @ViewBuilder
if (condition) {
    key("branch_0") {  // structural identity for true branch
        TrueContent()
    }
} else {
    key("branch_1") {  // structural identity for false branch
        FalseContent()
    }
}
```

This is a transpiler-level change in `KotlinBridgeToKotlinVisitor.swift`. The key values are derived from AST position (source file + line + column), guaranteeing uniqueness without runtime cost. This recovers `_ConditionalContent` semantics: toggling the branch destroys one key scope and creates another, resetting all `remember`/`rememberSaveable` state within.

### 3.3 Universal Container Consumption

Every container rendering loop becomes:

```swift
for i in 0..<renderables.size {
    let renderable = renderables[i]
    let composeKey: Any = renderable.identityKey ?? i
    androidx.compose.runtime.key(composeKey) {
        renderable.Render(context: contentContext)
    }
}
```

This pattern must appear in **every** container that iterates renderables. The audit identified 24 container files; all must use this pattern. There is no exception for "rarely dynamic" containers -- identity correctness is not probabilistic.

### 3.4 `.id()` State Destruction

The `.id()` modifier must:
1. Set `explicitID` on the renderable (normalised via `composeKeyValue()`)
2. Set `identityKey` to the same value (so containers key on it)
3. Wrap content in `key(normalised)` to scope `remember`/`rememberSaveable`

Current implementation at `AdditionalViewModifiers.swift:1413,1426` uses raw values. The fix is mechanical: replace `key(value ?? Self.defaultIdValue)` with `key(composeKeyValue(value) ?? Self.defaultIdValue)`.

### 3.5 Duplicate Key Safety

SwiftUI allows duplicate `.tag()` values outside selection contexts. Compose crashes on duplicate `key()` values in the same scope. The solution:

```swift
let composeKey: Any = renderable.identityKey ?? i
// Append index suffix if key is duplicate within this scope
let safeKey: Any = if seenKeys.contains(composeKey) {
    "\(composeKey)_\(i)"
} else {
    composeKey
}
seenKeys.add(composeKey)
```

This preserves identity stability for the first occurrence and degrades gracefully for duplicates, matching SwiftUI's "first match wins" behaviour for selection.

---

## 4. Evaluation of Existing Proposals

### 4.1 Proposal (a): `structuralID` on Renderable

**Closest to ideal: 60%.** Correctly identifies the need for a first-class identity property. Missing:
- No separation of selection tag from identity key (tag/identity conflation persists)
- No `.id()` normalisation fix
- No conditional branching solution
- No duplicate key safety

### 4.2 Proposal (b): Codex Three-Field Model (`selectionTag`, `explicitID`, `identityKey`)

**Closest to ideal: 85%.** This is architecturally correct. It separates all three concerns and proposes normalisation at assignment time. Missing:
- No transpiler-level conditional branching fix (the hardest problem)
- No concrete plan for universal container adoption (just "all containers read `identityKey`")
- No duplicate key safety mechanism

### 4.3 Proposal (c): Gemini Transpiler `__structuralID`

**Closest to ideal: 50%.** Correctly identifies the conditional branching gap and proposes a transpiler fix. But:
- Conflates structural identity with explicit identity (one field for two concerns)
- Doesn't address tag/selection separation
- Transpiler-only solution cannot fix runtime containers that iterate without `key()`
- Over-indexes on the transpiler when the majority of gaps are in SkipUI container code

### Verdict

**Codex's three-field model (b) is the right foundation**, augmented with Gemini's transpiler branch discrimination. Neither alone is sufficient. The ideal solution is (b) + the branch-keying aspect of (c) + universal container adoption + duplicate key safety.

---

## 5. Costs of Full Parity

**Complexity:** The three-field model adds three optional properties to `Renderable`, a protocol implemented by every view in SkipUI. Default `nil` implementations mean zero cost for views that don't use identity features, but every container must be audited and updated.

**Maintenance burden:** 24 container files must be updated to read `identityKey`. Every new container added to SkipUI must follow the pattern. This is a tax on all future container development. A lint rule or protocol requirement can enforce it.

**Transpiler changes:** Branch discrimination requires changes to `KotlinBridgeToKotlinVisitor.swift`'s ViewBuilder lowering. This is the riskiest change -- incorrect AST position tracking could produce non-unique keys or change key values across recompilations, causing mass state destruction. Extensive transpiler test coverage is mandatory.

**Upstream friction:** The three-field model changes `Renderable`, a public protocol in skip-ui. This is a breaking change for any downstream code that implements `Renderable` directly (uncommon but possible). Skip upstream may resist the complexity.

**Performance:** Per-item `key()` in every container adds Compose slot table entries. For large lists (1000+ items), this increases memory pressure. Lazy containers (`LazyVStack`, `List`) already use Compose-native keying and are unaffected. The cost is proportional to the number of simultaneously-composed items, which Compose already bounds.

**Testing:** The test matrix in the audit identifies 14 scenarios. Full parity requires all 14 to pass on both platforms. This is approximately 2-3 days of test authoring and debugging.

---

## 6. Minimum Viable Subset

If full parity is too expensive for the current phase, these are the **non-negotiable** semantics vs. deferrable ones:

### Non-Negotiable (breaks real apps if missing)

| Priority | Semantic | Why |
|----------|----------|-----|
| P0 | **E2: ForEach identity in ALL containers** | Every app with a dynamic list. The 14 unkeyed paths are ticking bombs. VStack AnimatedContent (lines 224, 250), HStack AnimatedContent (lines 188, 213), ZStack (lines 58, 93) are highest priority. |
| P0 | **E1: `.id()` normalisation** | `.id()` is the primary state-reset mechanism. Broken normalisation at `AdditionalViewModifiers.swift:1413,1426` means `.id()` is unreliable on Android. Mechanical fix. |
| P0 | **Tag/identity separation** | The conflation of `.tag()` (selection) and identity (lifecycle) causes the duplicate-key crash and makes reasoning about identity impossible. At minimum, `identityKey` must be a separate property from selection tag. |
| P1 | **B2/B3: Animation identity** | Any app using `withAnimation` on list mutations. Animated paths are the most visible failure mode. |

### Deferrable (nice-to-have, low real-world impact today)

| Priority | Semantic | Why deferrable |
|----------|----------|----------------|
| P2 | S1: Conditional branching | Compose's positional slot table handles simple `if/else` correctly when branch bodies have different types. Only fails when same-typed views shift positions. Transpiler fix is high-effort. |
| P2 | S3: AnyView erasure | `AnyView` is rare in well-structured SwiftUI code. TCA apps almost never use it. |
| P2 | B5: Focus/scroll identity | Depends on `.id()` fix (P0). Once `.id()` works, scroll identity follows. |
| P3 | S4: Stable container slots | Only matters for non-ForEach dynamic content. Low real-world frequency. |
| P3 | Lazy section headers/footers | Rarely dynamic. Six Low-severity gaps. |

### Recommended Minimum Implementation

1. **Add `identityKey: Any?` to `Renderable`** (Codex field 3). ForEach sets it during `Evaluate`. All containers read it. This closes all 14 gaps with one architectural change.

2. **Normalise `.id()` through `composeKeyValue()`** at `AdditionalViewModifiers.swift:1413,1426`. One-line fix each.

3. **Add `selectionTag: Any?` to `Renderable`** (Codex field 1). TabView and Picker read this instead of `.tag()`. ForEach stops setting `.tag()` for identity.

4. **Add duplicate key fallback** in container loops. Prevents crashes from legal SwiftUI code.

These four changes address every P0 item, require no transpiler modifications, and can be implemented incrementally. Conditional branching (P2) and AnyView (P2) can follow in a subsequent phase when the foundation is solid.

---

## Conclusion

The current 3-layer identity system is a prototype that proved the concept works for one container. Extending it to all containers by manually adding `key()` calls is the wrong abstraction level -- it treats the symptom (missing keys) rather than the disease (no first-class identity model). Codex's three-field model, implemented as properties on `Renderable` and consumed uniformly by every container, is the architecturally correct solution. It is more work upfront but eliminates an entire class of bugs permanently.

SwiftUI developers will write code that depends on identity semantics. They will not annotate which semantics they depend on. They will not test on Android first. When their app breaks, they will not suspect the identity layer -- they will suspect their own logic, waste hours debugging, and conclude that SkipUI is unreliable. The only way to prevent this is to make the identity layer invisible by making it correct.

---

## Appendix: Key File References

| File | Relevant Lines | Role |
|------|---------------|------|
| `forks/skip-ui/Sources/SkipUI/SkipUI/Compose/Renderable.swift` | 10-14 (protocol), 52-57 (`composeKey`), 70-89 (`composeKeyValue`) | Identity property home; key normalisation |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/VStack.swift` | 131, 165 (keyed), 224, 250 (unkeyed AnimatedContent) | Container key() coverage gap |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/HStack.swift` | 114, 135 (keyed), 188, 213 (unkeyed AnimatedContent) | Same pattern as VStack |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ZStack.swift` | 58 (unkeyed Box), 93 (unkeyed AnimatedContent Box) | Both paths missing key() |
| `forks/skip-ui/Sources/SkipUI/SkipUI/View/AdditionalViewModifiers.swift` | 1413, 1426 (raw `.id()` values) | `.id()` normalisation gap |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift` | 125 (default tag), 279-295 (`taggedIteration`), 297-303 (`taggedRenderable`) | Identity assignment during Evaluate |
| `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/TabView.swift` | 438 (index-based rendering), 478-482 (raw tag reading) | Tab identity gaps |
| `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift` | ~1734 (`stateVariables.isEmpty` guard) | Transpiler peer remembering exclusion |
