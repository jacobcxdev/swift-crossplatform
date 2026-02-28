# Phase 18: Complete View Identity Layer Implementation - Research

**Researched:** 2026-02-28
**Domain:** Compose view identity, ForEach/List lazy item keying, Compose stability/skippability, Skip transpiler codegen
**Confidence:** HIGH (all findings based on direct source code inspection + official Compose docs)

## Summary

Phase 18 completes the view identity layer by implementing the final two phases from the compose-view-identity-gap.md roadmap: **Phase 4 (ForEach identity)** and **Phase 5 (input diffing/skippability)**. Research reveals that ForEach identity (Phase 4) is largely already handled by skip-ui's existing `key` parameter plumbing in `LazyColumn`/`LazyListScope.items()`, but there is a critical gap in the **non-lazy (Evaluate) path** where ForEach items in non-lazy contexts (e.g. VStack containing ForEach) do NOT get `key()` wrapping — only `.tag()` modifiers. Phase 5 (input diffing) is lower priority but has a clear path via Compose's `@Stable` annotation on bridged view classes combined with strong skipping mode.

Additionally, research identified that the TabView workaround has been fully reverted (no `initialBindingRoute` code remains in TabView.swift), confirming Phase 1 fixed the root cause. The current Phase 1+2 `SwiftPeerHandle` implementation is sound for ForEach scenarios — Compose's `key` parameter in `LazyListScope.items()` provides positional scoping equivalent to `key()` for `remember` blocks, meaning remembered peers follow the correct items during reorder/insert/delete.

**Primary recommendation:** Phase 4 requires adding `key()` wrapping in ForEach's non-lazy Evaluate path (small skip-ui change). Phase 5 requires adding `@Stable` annotation to transpiler-generated bridged View classes (small skipstone change). Both are incremental, low-risk changes.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| skipstone transpiler | local fork | Generates bridged Kotlin View classes with `Evaluate` overrides | Where `@Stable` annotation would be added |
| skip-ui | local fork | SwiftUI equivalent on Compose — ForEach, List, LazyColumn wrappers | Where ForEach `key()` wrapping changes go |
| Compose Runtime | Bundled with Skip | `remember`, `key()`, `@Stable`, `@Immutable` annotations | Underlying primitives we lean on |
| Compose Foundation | Bundled with Skip | `LazyColumn`, `LazyListScope.items(key:)` | Lazy list identity mechanism |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Compose Compiler | Bundled with Skip | Strong skipping mode, stability inference | Phase 5 optimisation |

## Architecture Patterns

### Pattern 1: ForEach Identity via Compose `key` Parameter (Lazy Path — ALREADY WORKING)

**What:** When ForEach items are rendered inside a `LazyColumn` (via List, LazyVStack, etc.), skip-ui's `LazyItemCollector.initialize()` passes the identifier function as the `key` parameter to Compose's `LazyListScope.items(count:key:)`. This is the Compose-native mechanism for stable item identity in lazy lists.

**Current implementation (List.swift, line 269-270):**
```swift
let key: ((Int) -> String)? = identifier == nil ? nil : { composeBundleString(for: identifier!(range.start + itemCollector.value.remapIndex($0, from: offset))) }
items(count: count, key: key) { index in
    // ...render item...
}
```

**How it works:**
1. SwiftUI `ForEach(data, id: \.id)` → skip-ui ForEach stores `identifier` closure
2. When inside LazyColumn, `produceLazyItems()` passes identifier to collector
3. Collector's `indexedItems`/`objectItems` closures convert identifier to `key` function
4. `LazyListScope.items(count:key:)` uses key for Compose positional memoization
5. `remember` blocks inside each item scope (including `SwiftPeerHandle` from Phase 1/2) follow the key

**Confidence:** HIGH — verified by reading List.swift, LazyVStack.swift, LazyVGrid.swift, LazyHGrid.swift, LazyHStack.swift — all follow the same pattern.

### Pattern 2: ForEach Identity in Non-Lazy Path (Evaluate) — GAP IDENTIFIED

**What:** When ForEach is NOT inside a lazy container (e.g. `VStack { ForEach(...) }`), ForEach's `Evaluate` method iterates items and applies `taggedRenderable()` with the identifier value as a `.tag` role `TagModifier`. However, `.tag` role does NOT trigger `key()` wrapping — only `.id` role does (AdditionalViewModifiers.swift line 1435: `guard role == .id`).

**Current implementation (ForEach.swift, Evaluate, lines 93-109):**
```swift
for index in indexRange() {
    var renderables = indexedContent!(index).Evaluate(context: context, options: options)
    // ...
    let defaultTag: Any?
    if let identifier {
        defaultTag = identifier(index)
    } else {
        defaultTag = index
    }
    renderables = renderables.map { taggedRenderable(for: $0, defaultTag: defaultTag) }
    collected.addAll(renderables)
}
```

**The gap:** `taggedRenderable` applies `TagModifier(value:, role: .tag)`, not `.id`. This means:
- In the non-lazy path, ForEach items get `.tag` modifiers (used by Picker, TabView for selection matching)
- But `.tag` does NOT invoke `key()` wrapping
- So `remember` blocks (including `SwiftPeerHandle`) use **positional** identity only
- Insert/delete/reorder in a non-lazy ForEach could cause remembered peers to follow wrong items

**Impact assessment:** MEDIUM. Most ForEach usage in practice is inside List (lazy path, already keyed). Non-lazy ForEach inside VStack/HStack is less common but still a valid pattern. The fuse-app examples all use ForEach inside List, so this gap doesn't affect the primary use case.

**Confidence:** HIGH — verified by reading ForEach.swift Evaluate path and TagModifier.Evaluate in AdditionalViewModifiers.swift.

### Pattern 3: `@Stable` on Transpiler-Generated Classes

**What:** Compose's `@Stable` annotation tells the compiler that a type's public properties are stable (won't change without Compose being notified). This enables the compiler to skip recomposition of composable functions that receive only stable parameters.

**Current usage in skipstone:**
- `KotlinObservationTransformer.swift` already adds `@Stable` to `@Observable` classes (line 36) and `ObservableObject` classes (line 163)
- skip-ui manually adds `@Stable` via `// SKIP INSERT: @Stable` on `List`, `Table`, `ComposeContext`, `Navigator`, `ListArguments`, `TabEntryArguments`, etc.

**Gap:** Transpiler-generated bridged View classes do NOT get `@Stable`. This means Compose treats them as unstable, preventing function skipping even when inputs haven't changed. Since bridged views have a `Swift_peer` (Long) property that changes on every recomposition (before the `SwiftPeerHandle` swap in Evaluate), the class instance is inherently unstable from Compose's perspective.

**Confidence:** HIGH — verified by searching for `@Stable` in skipstone Sources and finding it only in `KotlinObservationTransformer.swift` (for `@Observable`/`ObservableObject`), not in `KotlinBridgeToKotlinVisitor.swift`.

### Pattern 4: Compose Strong Skipping Mode

**What:** [Strong skipping mode](https://developer.android.com/develop/ui/compose/performance/stability/strongskipping) (Compose Compiler 1.5.4+) relaxes stability requirements — all restartable composable functions become skippable regardless of parameter stability. Unstable parameters use instance equality (`===`) instead of `Object.equals()`.

**Relevance:** With strong skipping enabled, even without `@Stable` on bridged view classes, Compose will skip recomposition when the same instance is passed. However, bridged views are recreated on each parent recomposition (new Kotlin instance via `toJavaObject`), so instance equality will fail. `@Stable` with proper `equals()` would be needed for skipping to work.

**Skip's status:** Research did not find evidence of strong skipping mode configuration in the skip-ui or skipstone codebases. This may be controlled by Skip's Gradle configuration. Whether Skip enables strong skipping mode is an open question.

**Confidence:** MEDIUM — based on official Android docs + codebase search (no `strongSkipping` or `strong_skipping` found in forks/).

### Anti-Patterns to Avoid

- **Adding `key()` inside ForEach's Evaluate for ALL items:** This would break `.tag` semantics used by Picker and TabView selection. The `key()` must be added ONLY when the role is identity-related, not for selection matching.
- **Making bridged views `@Stable` without proper `equals()`:** `@Stable` is a contract — the compiler trusts it. If `equals()` doesn't correctly reflect state changes, views will fail to update. Bridged views with `Swift_peer` need careful `equals()` implementation or should not be marked `@Stable`.
- **Trying to make `SwiftPeerHandle` itself `@Stable`:** The handle is a private internal class, not a composable parameter. Stability annotations only affect composable function skipping decisions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Lazy list item identity | Custom `key()` wrapping in ForEach | Compose's `LazyListScope.items(key:)` | Already implemented in skip-ui; Compose handles all memoization scoping |
| Non-lazy item identity | Manual `remember(key)` per item | `key()` composable wrapper around each item's Evaluate | Compose's `key()` automatically scopes all `remember` blocks |
| Recomposition skipping | Manual diffing in Evaluate | `@Stable` + Compose compiler | Compose's compiler plugin handles all skipping logic |

## Common Pitfalls

### Pitfall 1: `.tag` vs `.id` Role Confusion
**What goes wrong:** ForEach applies `.tag` role modifiers for selection matching (Picker, TabView). Adding `key()` wrapping to `.tag` would break selection semantics.
**Why it happens:** `.tag` and `.id` serve different purposes — `.tag` is for value matching, `.id` is for view identity/lifecycle.
**How to avoid:** Only add `key()` wrapping for identity purposes via a SEPARATE mechanism (not by changing TagModifier's role). The ForEach Evaluate path should wrap each item in `key(identifier)` BEFORE applying the tag modifier.
**Warning signs:** Picker or TabView selection breaks after changes.

### Pitfall 2: Hash Collisions in `Swift_inputsHash`
**What goes wrong:** Phase 2's `remember(currentHash)` uses `Hasher.finalize()` which returns `Int`. Two different inputs could produce the same hash, causing a stale peer to be reused with wrong inputs.
**Why it happens:** Swift's `Hasher` is randomised per process but not collision-free.
**How to avoid:** This is a theoretical concern — `Int64` hash space makes collisions astronomically unlikely in practice. Document as known limitation. If ever observed, could add per-property equality checks as fallback.
**Warning signs:** View shows stale data after parent input changes (extremely rare).

### Pitfall 3: `@Stable` on Bridged Views Without Proper Equals
**What goes wrong:** Marking a bridged view `@Stable` tells Compose it can skip recomposition when `equals()` returns true. But bridged views have a `Swift_peer` Long field that changes on recomposition (before SwiftPeerHandle swap).
**Why it happens:** Kotlin's default `equals()` for classes uses identity, and new instances are created each recomposition.
**How to avoid:** Either (a) don't add `@Stable` to bridged views (safest), or (b) add `@Stable` only to views that have peer remembering active AND override `equals()` to compare by peer handle identity. Option (a) is recommended initially.
**Warning signs:** Views stop updating when they should.

### Pitfall 4: Non-Lazy ForEach Reorder Without Key Causes Peer Misalignment
**What goes wrong:** In a non-lazy `VStack { ForEach(items) { ... } }`, if items are reordered, Compose's positional `remember` follows the position (index 0, 1, 2...) not the item identity. A remembered `SwiftPeerHandle` at position 0 stays at position 0 even if the item at position 0 changed.
**Why it happens:** Without `key()` wrapping, `remember` uses call-site position as its key.
**How to avoid:** Add `key(identifier)` wrapping in ForEach's non-lazy Evaluate path.
**Warning signs:** After reordering a non-lazy ForEach, items display stale state from their previous position.

## Code Examples

### Example 1: Adding `key()` to ForEach Non-Lazy Evaluate Path

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift`

The change wraps each item's Evaluate call in `key()` when an identifier is available:

```swift
// In ForEach.Evaluate(), for the indexRange path:
for index in indexRange() {
    let itemIdentifier: Any? = identifier?(index) ?? index
    // Wrap in key() for identity-based remember scoping
    var renderables: kotlin.collections.List<Renderable>
    if let itemIdentifier {
        renderables = androidx.compose.runtime.key(itemIdentifier) {
            indexedContent!(index).Evaluate(context: context, options: options)
        }
    } else {
        renderables = indexedContent!(index).Evaluate(context: context, options: options)
    }
    // ... rest of existing logic (taggedRenderable, etc.)
}
```

**Why:** This ensures `remember` blocks (including `SwiftPeerHandle`) inside each ForEach item follow the item's identity, not its position. The existing `taggedRenderable` call remains unchanged for `.tag` selection semantics.

### Example 2: Adding `@Stable` to Bridged View Classes (Phase 5)

**File:** `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift`

```swift
// In addSwiftUIImplementation() or the class declaration generation:
if classDeclaration.swiftUIType == .view {
    classDeclaration.annotations.append("@Stable")
}
```

**Caveat:** This is only safe if Compose's strong skipping mode is NOT relying on `equals()` for these classes. With strong skipping, unstable params use `===` (instance equality), which would fail since new instances are created each recomposition. The `@Stable` annotation would tell Compose to use `equals()` instead, which defaults to identity — also failing. This needs careful evaluation of whether it actually helps or hinders.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No peer remembering | Phase 1+2 SwiftPeerHandle | 2026-02-27 | Root cause fix for view identity gap |
| TabView workaround (initialBindingRoute guard) | Reverted — Phase 1 fix eliminates need | 2026-02-27 | Workaround fully removed from TabView.swift |
| Default Compose stability (no annotations) | `@Stable` on `@Observable` classes only | Existing | Only observation classes get stability; bridged views don't |
| Normal skipping mode | Strong skipping mode available | Compose Compiler 1.5.4+ | May be enabled by Skip; status unknown |

## Open Questions

1. **Does Skip enable Compose strong skipping mode?**
   - What we know: Strong skipping is available in Compose Compiler 1.5.4+. Skip bundles a Compose compiler.
   - What's unclear: Whether Skip's Gradle config enables `strongSkipping`. This affects whether `@Stable` on bridged views provides any benefit.
   - Recommendation: Check Skip's Gradle build files or `skip.yml` for `strongSkipping` configuration. If already enabled, `@Stable` + proper `equals()` could help. If not, the benefit is limited.

2. **Is `@Stable` on bridged View classes actually beneficial?**
   - What we know: Bridged views are recreated each recomposition (new Kotlin instance). Even with `@Stable`, Compose would need `equals()` to return true for skipping. Default class `equals()` is identity-based.
   - What's unclear: Whether overriding `equals()` on bridged views to compare by `Swift_peer` after SwiftPeerHandle swap would be correct and safe.
   - Recommendation: Defer `@Stable` on bridged views until profiling shows recomposition is a bottleneck. The Phase 1+2 SwiftPeerHandle already prevents the most expensive cost (Swift peer recreation). Compose-level skipping is a secondary optimisation. LOW priority.

3. **Non-lazy ForEach with identifier — how common is this pattern?**
   - What we know: All fuse-app ForEach usages are inside List (lazy). Non-lazy ForEach in VStack/HStack is valid SwiftUI but less common.
   - What's unclear: Whether real-world apps hit the non-lazy ForEach identity gap.
   - Recommendation: Implement the fix anyway — it's small (wrap in `key()`) and prevents a class of subtle bugs.

4. **ForEach with `Range<Int>` (no explicit `id:`) — does positional identity suffice?**
   - What we know: `ForEach(0..<5) { i in ... }` uses integer index as default identity. If the range doesn't change, positional identity = correct identity.
   - What's unclear: If the range changes (e.g. count grows), items at existing positions keep their remembered state, which is correct. Items at new positions get new state, also correct.
   - Recommendation: Positional identity is correct for `Range<Int>` ForEach. The `key()` fix should use the index as key, which matches positional identity — no behavioral change, just explicit.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing + XCTest (transpiler tests use XCTest `check()` pattern) |
| Config file | Standard SPM test targets |
| Quick run command | `cd forks/skipstone && swift test --filter BridgeToKotlinTests` |
| Full suite command | `just ios-test` |

### Phase Requirements -> Test Map

No formal requirement IDs assigned. Testing approach:

| Area | Behavior | Test Type | Automated Command |
|------|----------|-----------|-------------------|
| ForEach non-lazy key() | ForEach Evaluate wraps items in key() when identifier present | Unit (skip-ui) | Manual verification or skip-ui test if exists |
| ForEach lazy key | Lazy path already uses items(key:) | N/A (already verified) | Existing tests |
| @Stable on bridged views | Annotation present on generated Kotlin | Unit (transpiler) | `swift test --filter BridgeToKotlinTests` |
| SwiftPeerHandle + key() | Peer follows item identity on reorder | Integration (emulator) | Manual emulator test |

### Wave 0 Gaps
- ForEach non-lazy path test may need to be manual or integration-level (ForEach.swift is skip-ui runtime, not transpiler output)
- `@Stable` transpiler test can be added to existing BridgeToKotlinTests

## Detailed Phase Breakdown

### Phase 4: ForEach Identity (MEDIUM priority, small scope)

**Goal:** Ensure ForEach items with stable identity get proper Compose `key()` wrapping so remembered Swift peers follow the correct items during insert/delete/reorder.

**Finding: Lazy path already works.** List, LazyVStack, LazyVGrid, LazyHGrid, LazyHStack all pass the ForEach identifier as the `key` parameter to `LazyListScope.items()`. Compose's lazy list infrastructure handles identity-based memoization automatically. No changes needed for the lazy path.

**Finding: Non-lazy path needs `key()` wrapping.** ForEach's `Evaluate` method (lines 93-141) iterates items and collects renderables, but does NOT wrap each item's Evaluate call in `key(identifier)`. Items get `.tag` modifiers for selection, but `.tag` does not trigger `key()`. This means `remember` blocks inside items (including `SwiftPeerHandle`) use positional identity only.

**Implementation plan:**
1. In `ForEach.Evaluate()`, wrap each item's content evaluation in `androidx.compose.runtime.key(identifier)` when an identifier is available
2. Apply to all three paths: `indexRange`, `objects`, `objectsBinding`
3. Keep existing `taggedRenderable` logic unchanged (`.tag` for selection)
4. For `indexRange` without explicit identifier, use the index as key (matches current positional behavior, but explicit)

**Files to modify:**
- `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift` — Evaluate method

**Risk:** LOW — additive change, no existing behavior modified. The `key()` wrapper only affects `remember` scoping inside each item.

### Phase 5: Input Diffing / Skippable Composables (LOW priority, deferred unless profiling shows need)

**Goal:** Leverage Compose's stability system to skip recomposition for bridged views when inputs haven't changed.

**Finding: `@Stable` is already used in the codebase.** The observation transformer adds `@Stable` to `@Observable` and `ObservableObject` classes. skip-ui manually annotates List, Table, ComposeContext, Navigator, etc.

**Finding: Bridged view classes do NOT get `@Stable`.** Generated Kotlin classes from the bridge visitor have no stability annotations. This means Compose treats them as unstable, preventing function skipping.

**Finding: `@Stable` on bridged views is problematic.** Bridged views are recreated each recomposition (new Kotlin instance via `toJavaObject`). Even with `@Stable`, Compose needs `equals()` to return true for skipping. Default class equality is identity-based, which fails for new instances. Overriding `equals()` to compare by `Swift_peer` is possible but complex — the `Swift_peer` value itself changes before SwiftPeerHandle swap.

**Recommendation: DEFER.** The Phase 1+2 SwiftPeerHandle already prevents the most expensive cost (Swift struct recreation with `let`-with-default reinitialisation). Compose-level recomposition skipping is a secondary optimisation that:
- Requires understanding Skip's Compose compiler configuration (strong skipping mode status)
- Requires careful `equals()` implementation on bridged views
- May provide marginal benefit given SwiftPeerHandle already preserves expensive state

**If pursued later:**
1. Add `@Stable` to bridged View classes in `KotlinBridgeToKotlinVisitor.swift`
2. Override `equals()` and `hashCode()` on bridged views to compare by current `Swift_peer` value
3. Verify strong skipping mode configuration in Skip's Gradle setup
4. Profile before/after to measure actual recomposition reduction

### Additional Gap: TabView Workaround Status (VERIFIED CLEAN)

The TabView workaround (`initialBindingRoute` guard) has been fully reverted. Grep for `initialBindingRoute` and `workaround` in TabView.swift returned no matches. The compose-view-identity-gap.md status correctly reflects "REVERTED" for Section 4. No action needed.

### Additional Gap: Configuration Change Peer Loss (DOCUMENTED)

The compose-view-identity-gap.md documents that `remember {}` (not `rememberSaveable`) is used for peer handles, meaning peers are lost on Android configuration changes (Activity recreation on rotation, locale). This is a known scope limitation documented in Section 6 and considered acceptable. No action needed in Phase 18.

## Sources

### Primary (HIGH confidence)
- `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ForEach.swift` — ForEach Evaluate and produceLazyItems implementation
- `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/List.swift` — LazyColumn items(key:) plumbing (lines 267-295)
- `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/LazySupport.swift` — LazyItemCollector, LazyItemFactory
- `forks/skip-ui/Sources/SkipUI/SkipUI/View/AdditionalViewModifiers.swift` — TagModifier, `.id()` -> `key()` mapping (lines 1395-1458)
- `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift` — Phase 1+2 SwiftPeerHandle generation (lines 1580-1770)
- `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinObservationTransformer.swift` — `@Stable` annotation on Observable classes (lines 36, 163)
- `docs/skip/compose-view-identity-gap.md` — Full design document with Phase 1-5 roadmap
- [Compose strong skipping mode](https://developer.android.com/develop/ui/compose/performance/stability/strongskipping) — Official Android docs
- [Compose LazyColumn best practices](https://developer.android.com/develop/ui/compose/performance/bestpractices) — Key parameter guidance
- [Compose Lists and grids](https://developer.android.com/develop/ui/compose/lists) — LazyColumn items(key:) API

### Secondary (MEDIUM confidence)
- [Compose stability annotations explained](https://medium.com/androiddevelopers/jetpack-compose-strong-skipping-mode-explained-cbdb2aa4b900) — Strong skipping mode details
- [LazyList key deep dive](https://dev.to/theplebdev/what-the-key-parameter-in-lazycolumn-is-actually-doing-a-deep-dive-4ac6) — How keys affect recomposition

## Metadata

**Confidence breakdown:**
- ForEach lazy path (already working): HIGH — direct source code verification across 5 lazy container files
- ForEach non-lazy path (gap): HIGH — direct source code verification of Evaluate path + TagModifier role logic
- `@Stable` feasibility: MEDIUM — clear mechanism exists but interaction with bridged view lifecycle needs runtime verification
- Strong skipping mode status: LOW — could not determine Skip's Compose compiler configuration

**Research date:** 2026-02-28
**Valid until:** 2026-03-28 (stable — Compose APIs and Skip transpiler don't change rapidly)
