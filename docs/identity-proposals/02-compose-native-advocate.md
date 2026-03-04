# Position Paper: Lean Into Compose's Identity Model

> **Author:** Compose-Native Advocate
> **Date:** 2026-03-01
> **Status:** Proposal for discussion
> **Related:** `docs/skipui-identity-audit.md`, `docs/compose-identity-review.md`

## Thesis

SkipUI's current identity system fights Compose rather than working with it. The audit identified 14 render paths missing `key()` wrapping -- but the right response is not to add `key()` to all 14. Instead, we should ask: *how many of these "gaps" are actually Compose working correctly, just differently from SwiftUI?* The answer, I will argue, is more than half.

The thinnest possible bridge between SwiftUI's identity model and Compose's identity model is not a 3-layer system with manual `key()` in every container. It is a system that speaks Compose's language natively and translates only at the genuine impedance mismatches.

---

## 1. How Compose Identity Actually Works

### The Slot Table: Positional Identity by Default

Compose's runtime maintains a **slot table** -- a linear array of composition records indexed by call site position. Every `@Composable` function call gets a **group** in the slot table identified by its source location (a compiler-generated `$key` integer). When Compose recomposes, it walks the slot table and matches groups by position within their parent.

This is not a limitation. It is a deliberate design choice. The Compose team's position (articulated in the `androidx.compose.runtime` docs and Leland Richardson's talks) is that **positional identity is correct for the overwhelmingly common case**. A `Text("Hello")` at line 42 of `MyScreen.kt` is the same `Text` every recomposition. No explicit identity needed.

```kotlin
// Compose assigns stable positional identity automatically.
// The slot table entry for each Text is keyed by source position.
@Composable
fun Profile(user: User) {
    Column {
        Text(user.name)      // group key: hash of source location A
        Text(user.email)     // group key: hash of source location B
        Avatar(user.avatar)  // group key: hash of source location C
    }
}
```

State stored via `remember` is attached to the slot table entry at that position. When `user` changes and `Profile` recomposes, each `Text` finds its existing slot table entry and preserves any `remember`-ed state.

### `key()`: Overriding Positional Identity

The `key()` composable creates a **movable group** in the slot table. Instead of matching by position, Compose matches by the key value. This is specifically designed for **dynamic lists** where items can be inserted, removed, or reordered:

```kotlin
@Composable
fun ItemList(items: List<Item>) {
    Column {
        for (item in items) {
            key(item.id) {  // movable group: matched by item.id
                ItemRow(item)
            }
        }
    }
}
```

Critically, `key()` is only useful when **the set of items changes between compositions**. For static structures (fixed number of children, always the same types in the same order), `key()` adds overhead for zero benefit -- Compose's positional matching already does the right thing.

### `LazyColumn`/`LazyRow`: Compose-Native Keyed Lists

Lazy layouts have their own key mechanism that is **separate from `key()`**:

```kotlin
LazyColumn {
    items(
        count = data.size,
        key = { index -> data[index].id }  // Lazy-native key
    ) { index ->
        ItemRow(data[index])
    }
}
```

This key parameter feeds directly into the lazy layout's internal item management. It controls:
- Which items are reused vs recreated on scroll
- Animation of insertions/deletions (`animateItem()`)
- State preservation when items move

This is **not** the same as wrapping each item in `key()`. The lazy `key` parameter is consumed by the `LazyListScope` infrastructure and stored in the `LazyListIntervalContent`. Wrapping lazy items in `key()` composable additionally would be redundant and potentially confusing to the runtime.

### `remember` and Key Interaction

`remember` stores a value in the slot table at the current position. When paired with `key()`:

```kotlin
key(item.id) {
    val counter = remember { mutableStateOf(0) }  // lives in this key's group
    Text("Count: ${counter.value}")
}
```

The `remember` block is inside the `key()` movable group. When `item.id` moves from position 2 to position 0, the entire movable group (including the `remember`-ed counter) moves with it.

When `remember` takes explicit keys, it provides **value-based invalidation**:

```kotlin
val derived = remember(input1, input2) { expensiveCompute(input1, input2) }
```

This is invalidation, not identity. The slot table entry stays in the same position; only the cached value is recomputed when inputs change. This is exactly what SkipUI's transpiler uses for `Swift_inputsHash` -- and it is the correct Compose pattern.

### How Compose Handles Conditionals

```kotlin
@Composable
fun ConditionalContent(showExtra: Boolean) {
    Column {
        if (showExtra) {
            Text("Extra")  // group A (conditional)
        }
        Text("Always")     // group B
    }
}
```

When `showExtra` toggles from `false` to `true`, Compose inserts a new group for `Text("Extra")`. The `Text("Always")` group shifts position, but Compose **does not** confuse it with the inserted group because each group carries its source-location key. The slot table diff algorithm handles insertions by matching source keys, not raw positions.

This is where Compose's model diverges from a naive "position = identity" reading. Compose uses **source-location keys within a parent group** as its primary matching strategy, falling back to position only when source keys are ambiguous (as in loops).

---

## 2. Where Compose Already Handles Things the Current Implementation Manages Manually

### Conditional Content (Audit Gap: "ViewBuilder conditionals")

The audit flags that SkipUI does not track conditional view identity like SwiftUI's `_ConditionalContent`. But **Compose already handles this correctly** for the transpiled output. The Skip transpiler emits Kotlin `if/else` blocks, and Compose's slot table assigns distinct source-location groups to each branch.

The audit's example -- `if flag { TextField() }; TextField()` causing state migration -- would only occur if both `TextField()` calls compiled to the **same source key**. In practice, the Kotlin compiler plugin assigns different keys because they are at different source locations. This "gap" is Compose working correctly.

**Verdict: Not a real gap.** No translation layer needed. The only scenario where this breaks is if the transpiler generates code that collapses distinct SwiftUI view sites into the same Kotlin source position -- which would be a transpiler bug, not an identity model bug.

### AnyView Type Erasure (Audit Severity: noted)

The audit notes that `AnyView` does not erase structural identity in SkipUI. In Compose terms, `AnyView` wraps content in a `ComposeView` lambda. When the wrapped type changes, the lambda body changes, and Compose's recomposition handles the diff naturally.

If old and new types produce the same composition structure, Compose reuses state. If they produce different structures, Compose destroys and recreates. This is **not identical** to SwiftUI's behaviour (which always destroys on type change), but it is arguably **better** -- why destroy state if the new content is structurally compatible?

**Verdict: Compose's behaviour is acceptable.** The semantic difference is observable but rarely matters in practice. Adding explicit identity erasure would fight Compose for minimal user benefit.

### Static Container Children (Audit Low Severity: toolbar items, NavigationLink labels, section headers/footers)

Six of the fourteen "gaps" are in contexts where children are **static or near-static**: toolbar leading/trailing items, lazy section headers/footers, NavigationLink labels. These are not dynamic lists. Items are not inserted, deleted, or reordered at runtime.

For static children, Compose's positional identity is **exactly correct**. Adding `key()` wrapping to these paths would be pure ceremony -- it costs runtime overhead (movable group allocation) and provides no behavioural benefit.

**Verdict: Not real gaps.** These are Compose working as designed. The audit classified them as Low severity, and even that overstates the risk.

### ViewThatFits (Audit Severity: Medium by one auditor)

The audit notes that `ViewThatFits` renders all candidates simultaneously for measurement, meaning non-chosen candidates retain state. In Compose, this is actually the **correct** behaviour for a measurement-based layout. The candidates exist in the composition because they need to be measured. Their state should be retained because the "winning" candidate can change on recomposition (e.g., screen rotation), and destroying/recreating state on every layout pass would be expensive and janky.

**Verdict: Compose's behaviour is correct for this use case.** If SwiftUI truly destroys non-fitting candidates, that is a SwiftUI-specific optimisation that we should not replicate -- it would require removing candidates from composition, which prevents measurement.

---

## 3. A Solution That Works WITH Compose

### Principle: Use Compose's Own Mechanisms, Not Reimplementations

The current 3-layer system reimplements identity tracking at the SkipUI level. I propose collapsing this to a **1.5-layer** system:

**Layer 1 (keep as-is): Transpiler peer remembering.** `SwiftPeerHandle` with `remember`/`remember(key)` is pure Compose idiom. It correctly maps Swift ARC lifetime to Compose slot table lifetime. No changes needed.

**Layer 1.5 (new): ForEach identity via Compose-native keying.** Instead of the current Tag-based pipeline (`ForEach -> taggedRenderable -> .tag modifier -> composeKey property -> container key() wrapping`), ForEach should communicate identity through the mechanism each container already understands:

- **Lazy containers (LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, List):** Already use `items(count:key:)` with `composeBundleString`. This is correct and Compose-native. No changes needed.
- **Eager containers (VStack, HStack, ZStack):** Use `key()` in the render loop. This is also correct -- it is the standard Compose pattern for dynamic `for` loops.

The change is **how the key gets from ForEach to the container**. Currently it travels through `.tag()` modifiers, which conflates selection tags with identity keys and requires every container to independently extract and normalise the key. Instead:

### Proposed: `identityKey` on Renderable

Add a single property to the `Renderable` protocol:

```swift
extension Renderable {
    /// Identity key for sibling disambiguation. Set by ForEach during Evaluate.
    /// Containers use this directly: `key(renderable.identityKey ?? index)`.
    /// Nil means "use positional identity" -- the Compose default.
    public var identityKey: String? {
        // Default: check for a wrapper that carries the key
        return (self as? IdentifiedRenderable)?.key
    }
}
```

ForEach sets this during Evaluate by wrapping renderables in a lightweight `IdentifiedRenderable`:

```swift
struct IdentifiedRenderable: Renderable {
    let wrapped: Renderable
    let key: String  // Already normalised to String -- Compose-safe

    @Composable func Render(context: ComposeContext) {
        wrapped.Render(context: context)
    }
}
```

Containers then use one universal pattern:

```swift
for i in 0..<renderables.size {
    let renderable = renderables[i]
    let composeKey: Any = renderable.identityKey ?? i
    key(composeKey) {
        renderable.Render(context: contentContext)
    }
}
```

**This is what the audit's Phase 3 recommends, and I agree with it -- but only for eager containers with ForEach children.** The critical difference in my proposal is that we do NOT add `key()` to the six static-child contexts identified as Low severity. Those paths should remain positional.

### ForEach in Lazy Containers: Already Correct

The lazy path (`items(count:key:)`) already works with Compose's native lazy identity. ForEach communicates with lazy containers through the `LazyItemFactory` protocol, which provides `identifier` closures. This is **already the right architecture**. The `composeBundleString` normalisation converts identifiers to Strings, which is the correct type for lazy keys.

No changes needed here. This path is Compose-native by design.

### AnimatedContent: Let Compose Own the Animation Identity

The animated VStack/HStack paths use `AnimatedContent` with a `contentKey` that maps the entire renderable list through `idMap`. This is a Compose-level diff mechanism -- `AnimatedContent` compares `contentKey` outputs to decide whether to animate.

The audit flags that individual items within the `AnimatedContent` `content` lambda are not wrapped in `key()`. But consider: `AnimatedContent` is already doing list-level identity comparison via `contentKey`. Adding per-item `key()` inside the `content` lambda is asking Compose to track identity at two levels simultaneously -- the `AnimatedContent` level (which list state are we showing?) and the per-item level (which item is which within the current state?).

This double-tracking can work, but it creates a tension: `AnimatedContent` expects to control the transition between states, while per-item `key()` expects items to persist across states. If an item exists in both old and new states, should it animate (because the state changed) or persist (because the key matched)?

My proposal: **add per-item `key()` inside AnimatedContent ONLY for the eager container paths** (VStack, HStack, ZStack), because these genuinely iterate ForEach items that can be inserted/deleted. But recognise that the interaction with `animateEnterExit` needs empirical testing -- the audit correctly flags this as an open question.

---

## 4. Genuine Impedance Mismatches

Not everything maps cleanly. These are the real differences that require a translation layer:

### Mismatch 1: SwiftUI's `.id()` State Destruction

SwiftUI's `.id(value)` modifier is a **state destruction primitive**: when `value` changes, the view's entire state tree is destroyed and recreated. Compose has no direct equivalent. The closest is `key(value)`, but `key()` provides identity -- it does not guarantee destruction. If the old key is simply removed (not replaced), Compose disposes the group. If the key changes, Compose treats it as a remove + insert.

This is close enough for most cases, but the semantics differ at the edges:
- SwiftUI `.id()` always destroys, even if the view structure is identical
- Compose `key()` change = remove old group + insert new group, which looks like destruction but goes through a different lifecycle path

**Translation needed:** Keep the `key()` wrapping for `.id()`, but normalise values through `composeKeyValue()` (currently missing -- audit Gap 2). The `.id` role in `TagModifier` should use the same normalisation as `.tag`.

### Mismatch 2: ForEach Identity for Bridged Types

SwiftUI identifies ForEach items by their `id` property (via `Identifiable` or explicit `id:` parameter). These identifiers flow naturally through SwiftUI's internal identity system. In SkipUI, these identifiers must cross the JNI bridge as `SwiftHashable` values, and Compose's internal key comparison uses Kotlin `equals()`.

The `composeKeyValue()` function exists to solve this by converting to Kotlin-native types (String/Int/Long). This is a genuine translation layer and is correctly designed. The only issue is consistency -- it must be applied everywhere an identity value is used as a Compose key, including `.id()` paths.

**Translation needed:** Unify all key normalisation through a single `composeKeyValue()` path. The current three paths (`composeKeyValue`, `composeBundleString`, raw `Any`) should collapse to one.

### Mismatch 3: Tag/Selection Conflation

SwiftUI's `.tag()` serves selection binding (Picker, TabView). SkipUI overloads `.tag()` to also carry ForEach identity. This conflation causes:
- User-applied `.tag()` for Picker selection colliding with ForEach-generated identity tags
- TabView reading raw `.tag` values without normalisation
- Duplicate `.tag()` values (legal in SwiftUI for non-selection contexts) crashing Compose via duplicate `key()` values

**Translation needed:** Separate selection tags from identity keys. The `identityKey` property on `Renderable` (proposed above) handles identity. `.tag()` returns to its SwiftUI purpose: selection binding only.

### Mismatch 4: Peer Lifecycle (ARC vs GC)

Swift uses ARC; Kotlin uses GC. `SwiftPeerHandle` with `RememberObserver` is the correct Compose-native bridge between these lifecycles. The `remember { SwiftPeerHandle(...) }` pattern pairs retain/release with Compose's `onForgotten`/`onAbandoned` callbacks.

**Translation needed:** This is already correctly implemented. The transpiler's Layer 1 is sound. The one gap (views with both `@State` and `let`-with-default) should be fixed by merging state syncing into `_ComposeContent`, as the audit recommends.

---

## 5. Against Over-Engineering: Which "Gaps" Are Not Gaps

Of the 14 identified render paths without `key()`, I argue the following are **not gaps**:

| "Gap" | Why It Is Not a Gap |
|-------|---------------------|
| LazyVStack section headers (Low) | Static content. Positional identity correct. |
| LazyVStack section footers (Low) | Same. |
| LazyHStack section headers/footers (Low) | Same. |
| LazyVGrid/LazyHGrid section headers/footers (Low) | Same. |
| List section headers (Low) | Same. |
| List section footers (Low) | Same. |
| NavigationLink labels (Low) | Labels are static or single-child. |
| Navigation toolbar leading items (Medium) | Toolbar items are typically static. Dynamic toolbar items are rare and can use `.id()`. |
| Navigation toolbar trailing items (Medium) | Same. |
| ViewThatFits candidates (Medium) | All candidates must exist for measurement. Retaining state is correct. |

That is **10 of 14** paths where the current behaviour is acceptable or correct.

The remaining 4 are genuine and should be fixed:

| Gap | Fix |
|-----|-----|
| ZStack non-animated loop | Add `key(renderable.identityKey ?? i)` |
| ZStack AnimatedContent loop | Add `key(renderable.identityKey ?? i)` |
| VStack AnimatedContent loops (x2) | Add `key(renderable.identityKey ?? i)` |
| HStack AnimatedContent loops (x2) | Add `key(renderable.identityKey ?? i)` |

Plus the normalisation fixes:
- `.id()` should use `composeKeyValue()`
- Unify `composeKeyValue` and `composeBundleString`
- Separate `.tag()` selection from identity keying

The Gemini proposal to inject `__structuralID` from AST location is interesting but **unnecessary**. Compose already assigns structural identity via source-location keys from its compiler plugin. Injecting a second structural identity system from the Swift AST would be reimplementing what Compose already does, at the cost of transpiler complexity and potential conflicts with Compose's own tracking.

---

## 6. The Minimal Translation Layer

Here is the complete bridge, in order of implementation priority:

### Step 1: Add `identityKey` to Renderable (the only architectural change)

```swift
// Renderable.swift
public protocol Renderable {
    @Composable func Render(context: ComposeContext)
}

extension Renderable {
    public var identityKey: String? {
        return (self as? IdentifiedRenderable)?.key
    }
}

struct IdentifiedRenderable: Renderable {
    let wrapped: Renderable
    let key: String
    // Delegates Render, strip, forEachModifier, etc. to wrapped
}
```

### Step 2: ForEach sets `identityKey` during Evaluate

Replace `taggedRenderable()` with `identifiedRenderable()`. ForEach no longer touches `.tag()` for identity purposes.

### Step 3: Eager containers read `identityKey`

VStack, HStack, ZStack -- all render loops (including AnimatedContent paths) use:

```swift
let composeKey: Any = renderable.identityKey ?? i
key(composeKey) { renderable.Render(context: contentContext) }
```

This is 4 lines of change per container, applied only where items are genuinely dynamic (ForEach-sourced).

### Step 4: Normalise `.id()` through `composeKeyValue()`

One-line fix in `AdditionalViewModifiers.swift`.

### Step 5: Stop. Do not add `key()` to static paths.

No changes to lazy section headers/footers, toolbar items, NavigationLink labels, or ViewThatFits. These are static contexts where positional identity is correct.

### What We Do NOT Build

- No transpiler-injected `__structuralID`. Compose's compiler plugin handles structural identity.
- No `key()` in static child loops. Compose's positional matching is correct there.
- No separate tracking of conditional branch identity. Compose's source-key-based slot table handles `if/else`.
- No explicit `AnyView` identity erasure. Compose's structural recomposition is acceptable.
- No dual-keying (container `key()` + TagModifier `key()`). One key, set once, consumed once.

---

## Summary

The current 3-layer system has 14 "gaps" because it chose to fight Compose's identity model rather than work with it. Every container must independently implement key extraction, normalisation, and wrapping -- and inevitably some paths get missed.

The Compose-native approach accepts that Compose handles identity differently from SwiftUI, and asks only: **where do they genuinely diverge?** The answer is four places: dynamic eager lists need `key()`, bridged values need normalisation, `.id()` needs state destruction semantics, and selection tags must be separated from identity keys.

Everything else -- static children, conditional branches, type erasure, lazy list items, measurement layouts -- is Compose working correctly. We should let it.

The result is a translation layer measured in dozens of lines, not hundreds. It is auditable because there is one identity mechanism (`identityKey`) instead of three overlapping ones. And it is maintainable because new containers do not need to independently discover and implement key wrapping -- they either iterate dynamic content (use `identityKey`) or they do not (use positional identity).

Compose's identity model is not broken. It is different. The thinnest bridge is the best bridge.
