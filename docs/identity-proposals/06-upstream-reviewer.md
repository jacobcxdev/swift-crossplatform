# Position Paper: Upstream Review of Compose View Identity Proposals

> **Perspective:** Skip upstream maintainer (Skip Tools)
> **Date:** 2026-03-01
> **Re:** 14 identity gaps identified in skip-ui fork, proposed remediation across 3 phases

---

## 1. Overall Assessment

The audit is thorough and the gaps are real. Compose's positional identity model does diverge from SwiftUI's structural identity in the ways described. However, not all divergences are bugs — some are acceptable trade-offs that have served Skip apps well for years. Our guiding principle is pragmatic fidelity: we match SwiftUI behaviour where it matters for real apps, not where it matters for specification compliance.

We would welcome targeted fixes for the high-severity gaps. We would push back on architectural refactors that change protocol surfaces or transpiler codegen without strong evidence of user-facing breakage in shipping apps.

---

## 2. Per-Change Evaluation

### Phase 1: Mechanical `key()` Additions — Mostly Acceptable

**ZStack render loops (1a) — Accept.**
ZStack iterates renderables in a Box without per-item keying. Adding `key(composeKey ?? i)` follows the exact pattern already established in VStack/HStack non-animated paths. The diff is small, the risk is low, and overlapping ForEach items in ZStack are a real (if uncommon) use case. We would review and merge this.

**AnimatedContent paths in VStack/HStack (1b, 1c) — Accept with caveats.**
These are the highest-severity gaps and the fix is clearly needed. However, AnimatedContent iterates `for renderable in state` without a natural index variable, and inserting `key()` inside `AnimatedContent`'s content lambda may interact with `animateEnterExit` modifier application. We would require:
- Empirical verification that `key()` does not interfere with enter/exit transitions (the `animateEnterExit` modifier is applied per-renderable and its scope relative to `key()` matters).
- An indexed iteration approach (`state.forEachIndexed` or `for i in 0..<state.size`) rather than relying on a counter variable, to match the existing non-animated pattern.
- A test case demonstrating the fix (animated ForEach, delete middle item, remaining items retain state).

**`.id` normalisation through `composeKeyValue()` (1d) — Accept.**
This is a clear oversight. The `.tag` role normalises through `composeKeyValue()` but `.id` uses raw values. Given that SwiftHashable JNI equality is known to be unreliable for Compose's internal comparisons, applying the same normalisation is the right call. Small, safe, obviously correct.

**Lazy section headers/footers (1e) — Accept, low priority.**
Headers and footers in LazyVStack/LazyHStack/LazyVGrid/LazyHGrid are rarely dynamic. We would merge this but would not prioritise it. No rush.

**Navigation toolbar loops (1f) — Accept, low priority.**
Same reasoning. Dynamic toolbar items are uncommon in practice. The fix is mechanical and safe.

**Summary for Phase 1:** We would accept all six items as separate, focused PRs. Items 1b/1c need the most review attention due to AnimatedContent interaction.

### Phase 2: Key Normalisation Unification — Partially Acceptable

**Unifying `composeKeyValue` and `composeBundleString` (2a) — Needs discussion.**
We acknowledge three normalisation paths is not ideal. But `composeBundleString` exists in the lazy item API for a reason: it produces stable string keys for Compose's `LazyListScope.items(key:)` parameter, which requires `Any?` but practically needs stable `equals()`/`hashCode()`. Unification is desirable in principle, but we need to see the concrete proposal. If it means `composeKeyValue()` gains the `composeBundleString` behaviour (or vice versa) without breaking lazy list keying, we would consider it. If it requires changing how lazy APIs consume keys, the blast radius is too large.

**TabView tag normalisation (2b) — Accept.**
TabView reading raw `.tag` values without normalisation is a bug. The fix is small and targeted. Happy to merge.

**Duplicate key graceful handling (2c) — Accept in principle, design matters.**
Compose throws on duplicate keys in the same scope. SwiftUI allows duplicate `.tag()` outside selection contexts. A fallback to `tag + index` (or similar deduplication) is reasonable, but the implementation needs care: we do not want to silently swallow duplicate keys in Picker/TabView where they indicate a real programming error. The PR should only apply deduplication in non-selection container contexts (VStack, HStack, ZStack).

### Phase 3: Architectural Refactor — Mostly Reject for Upstream

**Adding `identityKey` to `Renderable` protocol (3a) — Reject.**
This is a breaking change. `Renderable` is a public protocol. Every custom `Renderable` implementation — including those in user code and in other Skip libraries — would need updating. Even with a default `nil` implementation, adding a stored property expectation to a protocol changes the contract. The migration cost across the Skip ecosystem is not justified by the identity gaps identified, most of which are fixable with Phase 1 mechanical patches.

If identity propagation is truly needed beyond `composeKey`, we would prefer a wrapper-based approach (an `IdentifiedRenderable` struct that wraps any `Renderable` with an identity value) over protocol modification. This is additive, not breaking.

**Separate `selectionTag` from identity (3b) — Reject for now.**
The tag/identity conflation is architecturally inelegant, but it works. ForEach's `taggedRenderable()` already handles the overlap correctly by checking for existing tags before adding defaults. Splitting into two separate modifier roles is a large refactor touching ForEach, TabView, Picker, TagModifier, and every container. The benefit is conceptual cleanliness; the cost is real code churn with regression risk. We would reconsider if a concrete bug report demonstrates that conflation causes user-visible breakage that cannot be fixed locally.

**ForEach sets `identityKey` during Evaluate (3c, 3d, 3e, 3f) — Reject.**
These all depend on 3a/3b and form a chain of refactors that collectively rewrite how identity flows through the system. This is too much architectural change for the problem being solved. The existing `composeKey` property (reading `.tag` modifier) works. The gaps are in containers that do not read it, not in the identity propagation mechanism itself.

**Transpiler structural ID injection (3g) — Reject.**
Injecting `__structuralID` from AST location into every view struct is a significant transpiler change with wide-ranging implications. It changes the generated Kotlin for every bridged view. It requires the transpiler to track ViewBuilder structural position, which is complex and fragile (the transpiler does not currently model SwiftUI's `_ConditionalContent` lowering). The maintenance burden on our small team would be substantial, and the benefit — fixing `if/else` branch identity and `AnyView` erasure — addresses edge cases that most Skip apps do not hit.

If conditional identity is important for TCA-style apps with complex conditional view hierarchies, this belongs in the fork. We would not accept this upstream.

---

## 3. Backward Compatibility Concerns

The changes most likely to break existing Skip apps:

1. **Protocol changes to `Renderable`** (3a, 3b) — Any app or library implementing `Renderable` directly (rare but possible) would break. Custom `Renderable` types in skip-ui itself (e.g., `LazyLevelRenderable`, `ComposeView`, `ModifiedContent`) all need updating. High risk.

2. **Duplicate key handling changes** (2c) — If deduplication changes the effective key for items that previously had duplicate tags, their Compose state will be invalidated on the first recomposition after the update. This is a one-time state reset, not a crash, but it could be surprising.

3. **`composeKeyValue()` unification** (2a) — If the unified normalisation produces different string representations than the current `composeBundleString` for lazy items, lazy list scroll positions and remembered state could reset. Needs careful equivalence testing.

4. **AnimatedContent `key()` addition** (1b, 1c) — Low risk but non-zero. Adding `key()` inside AnimatedContent changes the composition structure. Existing apps with animated VStack/HStack ForEach content will see a one-time state reset as Compose rebuilds the slot table. This is acceptable (and correct), but worth noting in release notes.

Phase 1 items (1a-1f) have minimal backward compatibility risk. They add `key()` where none existed, which can only improve identity tracking. The only risk is the one-time slot table rebuild mentioned above.

---

## 4. Recommended Upstream PR Strategy

We would accept PRs structured as follows, in this order:

### PR 1: ZStack per-item keying
- Files: `ZStack.swift`
- Pattern: `key(composeKey ?? i)` in both Box loop paths
- Standalone, no dependencies
- Estimated review: quick

### PR 2: `.id` normalisation
- Files: `AdditionalViewModifiers.swift`
- Change: `key(value ?? Self.defaultIdValue)` to `key(composeKeyValue(value ?? Self.defaultIdValue))`
- Both Evaluate and Render paths
- Standalone, no dependencies
- Estimated review: quick

### PR 3: AnimatedContent keying (VStack + HStack)
- Files: `VStack.swift`, `HStack.swift`
- Must include: test case or test app demonstrating the fix
- Must verify: no interaction with `animateEnterExit`
- Estimated review: medium (needs testing)

### PR 4: TabView tag normalisation
- Files: `TabView.swift`
- Normalise raw tag reads through `composeKeyValue()`
- Standalone
- Estimated review: quick

### PR 5: Duplicate key graceful handling
- Files: `VStack.swift`, `HStack.swift`, `ZStack.swift`
- Only in non-selection containers
- Needs design discussion before implementation
- Estimated review: medium

### PR 6: Lazy section header/footer keying + toolbar keying
- Files: `LazyVStack.swift`, `LazyHStack.swift`, `LazyVGrid.swift`, `LazyHGrid.swift`, `List.swift`, `Navigation.swift`
- Bundle the low-severity items together
- Estimated review: quick

### PRs we would NOT accept:
- Protocol changes to `Renderable`
- Tag/identity decoupling refactor
- Transpiler structural ID injection
- Any change to `composeBundleString` without extensive lazy list testing

---

## 5. Skip's Design Philosophy and Its Implications

Skip's mission is "write Swift, run on Android." This is not "replicate SwiftUI's internal implementation on Android." We make pragmatic choices:

**"It works" beats "it's identical."** SwiftUI's structural identity model is deeply tied to its implementation (the attribute graph, `_ConditionalContent`, `_VariadicView`). Compose has its own identity model (slot table, positional memoisation). We bridge between them at the observable-behaviour level, not the implementation level. If a VStack of ForEach items preserves state correctly on insert/delete, that is sufficient — we do not need to replicate SwiftUI's exact identity tokens.

**Common patterns over edge cases.** The gaps identified fall into two categories:
- *Common patterns* (ForEach in animated stacks, `.id()` for state reset): These affect real apps. Fix them.
- *Edge cases* (`if/else` branch identity, `AnyView` erasure, `ViewThatFits` state leakage, dynamic tab reordering): These affect unusual view hierarchies that most Skip apps avoid. Not worth architectural refactors.

**Simplicity is a feature.** The current `composeKey` property on `Renderable` is simple: it reads the `.tag` modifier and normalises the value. Containers that iterate renderables can use it. This is easy to understand, easy to maintain, and easy to debug. A three-field identity model (`selectionTag`, `explicitID`, `identityKey`) is more correct but substantially more complex. For a small team maintaining a large framework, complexity is the enemy.

**The 80/20 rule applies.** Phase 1 fixes close the most impactful gaps (animated paths, ZStack, `.id` normalisation) with minimal code change. Phase 3 fixes the remaining 20% at 5x the cost. We would rather ship Phase 1 and move on to other user-facing improvements.

---

## 6. Fork Maintenance Costs

For changes we would not accept upstream, the fork maintainer should consider:

**Acceptable to maintain in a fork:**
- AnimatedContent `key()` additions (if upstream is slow to merge — these are self-contained)
- `composeKeyValue()` hardening (Optional stripping improvements)
- Debug logging (`FUSE_IDENTITY_DEBUG` guards) — upstream has no reason to carry these

**Costly to maintain in a fork:**
- `Renderable` protocol changes — every upstream update to `Renderable`, `ModifiedContent`, `LazyLevelRenderable`, `ComposeView`, or any other `Renderable` conformance will conflict. Expect merge conflicts on every upstream sync.
- Transpiler structural ID injection — skipstone transpiler changes are particularly expensive to maintain. The transpiler evolves rapidly, and structural changes to code generation will conflict with virtually every upstream transpiler update. The fork would need a dedicated person tracking skipstone changes.
- Tag/identity decoupling — touches too many files. Every upstream container change risks a conflict.

**Recommendation for the fork:** Implement Phase 1 (all items) and Phase 2 (2b, 2c). Upstream PRs 1-4 immediately. Keep Phase 3 in the fork only if TCA-specific patterns demonstrably require it, and accept the ongoing merge cost as a conscious trade-off. Do not implement transpiler structural ID injection unless you are prepared to maintain a permanent skipstone fork divergence.

**Quantifying the cost:** Based on skip-ui's commit frequency (roughly weekly), a fork carrying Phase 1 changes (6 files, ~30 lines changed) will see conflicts perhaps once every 2-3 months. A fork carrying Phase 3 changes (~15 files, ~200 lines, protocol changes) will conflict on nearly every sync. The transpiler fork is worse: skipstone's code generation evolves rapidly, and a structural ID injection will conflict on most transpiler updates.

---

## Summary Table

| Change | Upstream Verdict | Rationale |
|--------|-----------------|-----------|
| 1a: ZStack `key()` | **Accept** | Mechanical, safe, follows existing pattern |
| 1b/1c: AnimatedContent `key()` | **Accept** (with tests) | High-severity gap, needs animation interaction verification |
| 1d: `.id` normalisation | **Accept** | Obvious bug fix |
| 1e: Lazy headers/footers `key()` | **Accept** (low priority) | Correct but rarely hit |
| 1f: Toolbar `key()` | **Accept** (low priority) | Correct but rarely hit |
| 2a: Unify normalisation | **Discuss** | Desirable but needs concrete proposal |
| 2b: TabView normalisation | **Accept** | Bug fix |
| 2c: Duplicate key handling | **Accept** (design first) | Non-selection contexts only |
| 3a: `identityKey` on `Renderable` | **Reject** | Breaking protocol change, not justified |
| 3b: `selectionTag` split | **Reject** | Architecturally clean but too much churn |
| 3c-3f: Identity propagation refactor | **Reject** | Depends on 3a/3b |
| 3g: Transpiler structural ID | **Reject** | Too complex, too risky, too costly to maintain |
