# Synthesis: The Canonical Approach to SkipUI Compose View Identity

> **Date:** 2026-03-01
> **Status:** Synthesis of 8 position papers + audit findings
> **Input:** Papers 01–08, `compose-identity-review.md`, `skipui-identity-audit.md`

---

## 1. Points of Universal Agreement

These findings are shared by all or nearly all papers. They are non-negotiable.

### 1.1 Layer 1 (Transpiler Peer Remembering) Is Sound

All 8 papers agree that `SwiftPeerHandle` with `remember`/`remember(key)` for Swift peer lifecycle is correctly designed and should not change. It solves ARC-vs-GC lifecycle bridging — an orthogonal problem to view identity. (Papers 01–08 unanimous.)

### 1.2 ForEach Items in Dynamic Containers Require Explicit `key()`

Every paper — including Paper 02 (Compose-Native Advocate) — agrees that ForEach items in eager containers (VStack, HStack, ZStack) must be wrapped in `key()` with data-derived identifiers. Compose's positional identity is insufficient when list membership changes. This is universal across all UI frameworks (Paper 08 confirms React, Flutter, Vue, Svelte, Angular all converge on the same requirement).

### 1.3 `.tag()` Conflates Selection and Identity

All 8 papers identify the dual use of `.tag()` (ForEach structural identity + Picker/TabView selection binding) as architecturally wrong. Paper 03 provides the most rigorous analysis; Paper 08 confirms that no other UI framework conflates these concerns. Papers 05 and 06 acknowledge the problem but differ on urgency.

### 1.4 `.id()` Must Normalise Through `composeKeyValue()`

All papers that address it (01, 02, 03, 05, 06, 07) agree this is a clear bug. The `.tag` role normalises; the `.id` role does not. The fix is mechanical and uncontroversial.

### 1.5 Key Normalisation to Compose-Native Types Is Mandatory

SwiftHashable JNI equality is fundamentally incompatible with Compose's internal key comparison. All papers agree keys must be converted to String/Int/Long before entering Compose's `key()`. The disagreement is over *how many* normalisation paths to maintain, not *whether* normalisation is needed.

### 1.6 The 14 Unkeyed Paths Are Real, but Not Equal

All papers accept the audit's catalogue of 14 missing `key()` sites. They diverge sharply on how many are worth fixing (Paper 02 says 4; Paper 01 says all 14; Paper 05 says 3 immediately). The triage in Section 2.2 below resolves this.

---

## 2. Key Tensions and Their Resolution

### 2.1 Tension: Protocol Change vs Wrapper vs Status Quo

**The camps:**
- Papers 01, 03, 08: Add `identityKey` (and optionally `selectionTag`, `explicitID`) as properties on `Renderable`.
- Paper 02: Add `identityKey` via an `IdentifiedRenderable` wrapper type, accessed through a protocol extension.
- Paper 06 (Upstream): Reject protocol changes; prefer wrapper if needed.
- Papers 05, 07: Defer all architectural changes; use existing `composeKey`.

**Resolution: Protocol extension with modifier-based storage.**

Paper 03's design is the most carefully considered. The three identity fields (`identityKey`, `selectionTag`, `explicitID`) are provided as *extension-computed properties* on `Renderable`, not protocol requirements. They have default implementations returning `nil` (or walking `forEachModifier`). This means:

- No protocol requirement change — existing `Renderable` conformers are unaffected.
- No wrapper nesting problem (Paper 03 Section 2.4 correctly identifies `IdentifiedRenderable` wrapper issues).
- Identity is stored in an `IdentityKeyModifier` (new modifier type), which travels through `ModifiedContent` chains via the existing `forEachModifier` traversal — no new propagation machinery needed.
- Paper 06's concern about "breaking protocol change" is addressed: extension-provided computed properties with defaults are additive, not breaking.

Paper 07 raises valid propagation concerns (Section 2: "Who sets it? Nested ForEach? ModifiedContent chains?"). Paper 03 answers all of these concretely: `IdentityKeyModifier` is set by ForEach, propagated through `ModifiedContent.forEachModifier`, and `ComposeView` is always wrapped in `ModifiedContent` when identity is needed (an existing invariant).

**The three-field model is correct but should be deployed incrementally.** `identityKey` first (immediate need). `selectionTag` second (when TabView/Picker bugs surface). `explicitID` can wait — `.id()` already works via `TagModifier` with role `.id`, and the only fix needed now is normalisation.

### 2.2 Tension: Fix All 14 Gaps vs Fix Only What Breaks

**The camps:**
- Paper 01: Fix all 14 — identity correctness is not probabilistic.
- Paper 02: Fix 4 (eager container dynamic paths only); 10 are not real gaps.
- Paper 05: Fix 3 now (ZStack + `.id()` normalisation + AnimatedContent with tests); defer rest.
- Paper 06: Accept all Phase 1 PRs but prioritise differently.
- Paper 07: Fix ZStack and `.id()` immediately; AnimatedContent only after empirical testing.

**Resolution: A three-tier priority with Paper 07's empirical-test-first principle for AnimatedContent.**

Paper 02 is right that static-child contexts (toolbar items, NavigationLink labels, lazy section headers/footers) are not meaningfully dynamic and Compose's positional identity handles them correctly. Paper 05 is right that AnimatedContent requires empirical validation before shipping. Paper 01 is right that ZStack is a genuine gap hitting real patterns (card decks, overlays).

**Tier 1 — Fix immediately (< 1 day):**
- ZStack both render loops: `key(identityKey ?? i)`. Mechanical, identical to proven VStack/HStack pattern.
- `.id()` normalisation: `composeKeyValue()` at `AdditionalViewModifiers.swift:1413, 1426`. One-line fixes.
- TabView tag normalisation through `composeKeyValue()`. Bug fix.

**Tier 2 — Fix with empirical testing (1–3 days):**
- AnimatedContent in VStack (2 paths) and HStack (2 paths). Paper 07 is correct: write a failing test first that exercises `key()` inside `AnimatedContent`'s content lambda alongside `animateEnterExit`. If `key()` breaks enter/exit animations, the fix must be redesigned (possibly keying at the `AnimatedContent` level via `contentKey` enrichment rather than per-item inside the lambda). Do not ship without this test.

**Tier 3 — Defer (fix when hit):**
- Lazy section headers/footers (6 sites). Rarely dynamic. Paper 02 and 05 agree.
- Navigation toolbar loops (2 sites). Toolbar items are near-static. Paper 02 correct.
- ViewThatFits. Paper 02 convincingly argues Compose's behaviour is correct for measurement.
- NavigationLink labels. Exotic use case.

### 2.3 Tension: Transpiler Structural ID Injection

**The camps:**
- Paper 04: Transpiler should own structural identity, ViewBuilder branch keying, and the `stateVariables.isEmpty` fix.
- Paper 01: Transpiler branch `key()` for `if/else` is needed for `_ConditionalContent` parity.
- Paper 02: Compose's compiler plugin already handles conditional identity via source-location keys; transpiler injection is unnecessary.
- Paper 06: Reject — too complex, too costly to maintain in skipstone fork.
- Paper 07: Fragile by design — refactoring changes identity, developers cannot diagnose.

**Resolution: Reject transpiler structural ID for now. Fix `stateVariables.isEmpty` guard only.**

Paper 02's argument is underappreciated: Compose's own compiler plugin assigns distinct source-location group keys to each `if/else` branch in the generated Kotlin. The Skip transpiler emits standard Kotlin `if/else`, which the Compose compiler plugin then instruments. The conditional identity "gap" exists only if the transpiler collapses distinct SwiftUI view sites into the same Kotlin source position — which would be a transpiler bug, not a missing feature.

Paper 07's criticism is decisive: AST-position-based IDs make refactoring change identity, creating a class of bugs that cannot be diagnosed because the structural ID is invisible. Paper 06 adds that skipstone evolves rapidly and transpiler divergence is the most expensive fork maintenance cost.

However, Paper 04's `stateVariables.isEmpty` fix (Section 5) is correct, important, and self-contained. Views with both `@State` and `let`-with-default must get both state syncing and peer remembering. The simpler variant (keep state init in `Evaluate`, add peer remembering in `_ComposeContent`) is low-risk and addresses a confirmed gap. This is a transpiler change worth making.

### 2.4 Tension: One Normalisation Function vs Current Three

**The camps:**
- Papers 01, 03, 08: Unify to a single `normalizeKey()` called at the producer.
- Paper 06: Needs discussion — `composeBundleString` exists for a reason in lazy APIs.
- Paper 05: Do not unify until a bug forces it.

**Resolution: Unify, but carefully.**

Paper 03's `normalizeKey()` design (Section 3.3) is the right target. One function, called at the producer (ForEach/`IdentityKeyModifier.init`), producing Compose-safe values. Consumers never normalise.

Paper 06's concern about `composeBundleString` in lazy APIs is valid but addressable: if `normalizeKey()` produces the same output for the same inputs as `composeBundleString` does today, lazy list scroll positions and state are preserved. The migration must include equivalence testing for lazy item keys. Do this as part of the `identityKey` rollout, not as a separate phase.

### 2.5 Tension: Duplicate Key Handling

**The camps:**
- Paper 01: Append index suffix for duplicates (`"\(key)_\(i)"`).
- Paper 06: Accept in principle, but only in non-selection containers.
- Paper 07: Must ship *with or before* Phase 1, not after.
- Paper 03: Decoupling `.tag()` from identity eliminates the primary duplicate-key source.

**Resolution: Paper 03 is correct — decoupling eliminates the root cause.**

Once ForEach uses `IdentityKeyModifier` (not `.tag()`) for identity, user-applied `.tag()` no longer produces Compose `key()` calls in containers. Duplicate `.tag()` values become inert data. The remaining duplicate-key risk is ForEach items with genuinely duplicate data IDs, which is a developer error in any framework. A defensive fallback (Paper 01's `"\(key)_\(i)"` for duplicates within a scope) is still worth adding as a guard, but it is no longer a crash-regression concern gating Phase 1.

---

## 3. The Canonical Recommended Approach

### 3.1 Identity Model: Two Properties on `Renderable` (via Extension)

```swift
#if SKIP
extension Renderable {
    /// Structural identity key for container sibling loops.
    /// Set by ForEach via IdentityKeyModifier during Evaluate.
    /// Always Compose-safe (String | Int | Long) — normalised at the producer.
    /// nil = use positional index fallback.
    public var identityKey: Any? {
        forEachModifier { ($0 as? IdentityKeyModifier)?.normalizedKey }
    }

    /// Selection tag for Picker/TabView binding.
    /// Set by .tag() modifier. Raw Swift value — compared in Swift, not Compose.
    public var selectionTag: Any? {
        TagModifier.on(content: self, role: .tag)?.value
    }

    // Deprecated — replaced by identityKey
    @available(*, deprecated, renamed: "identityKey")
    public var composeKey: Any? { identityKey }
}
#endif
```

**Rationale:** Extension-computed properties with defaults are non-breaking (addresses Paper 06). Two fields, not three — `explicitID` is deferred because `.id()` already works through `TagModifier` with role `.id` and only needs normalisation, not a new field. Two fields cover the two concerns that are actually conflated today (identity vs selection).

### 3.2 New Modifier: `IdentityKeyModifier`

```swift
#if SKIP
final class IdentityKeyModifier: ModifierProtocol {
    let role: ModifierRole = .unspecified
    let normalizedKey: Any  // String | Int | Long

    init(key: Any) {
        self.normalizedKey = normalizeKey(key)
    }

    @Composable func Render(content: Renderable, context: ComposeContext) {
        // Transparent — identity is consumed by the CONTAINER, not this modifier.
        content.Render(context: context)
    }
}
#endif
```

### 3.3 Unified Key Normalisation

```swift
#if SKIP
public func normalizeKey(_ raw: Any) -> Any {
    if raw is String || raw is Int || raw is Long { return raw }
    // Structural optional unwrapping (replaces fragile string-based stripping)
    if let optional = raw as? AnyOptionalProtocol,
       let unwrapped = optional.unwrappedValue {
        return normalizeKey(unwrapped)
    }
    if let identifiable = raw as? any Identifiable {
        return normalizeKey(identifiable.id)
    }
    return "\(raw)"
}

fileprivate protocol AnyOptionalProtocol {
    var unwrappedValue: Any? { get }
}
extension Optional: AnyOptionalProtocol {
    var unwrappedValue: Any? {
        switch self {
        case .some(let w): return (w as? AnyOptionalProtocol)?.unwrappedValue ?? w
        case .none: return nil
        }
    }
}
#endif
```

**Note on Kotlin compatibility:** Paper 03 correctly flags that `Optional` may be erased to Kotlin nullable on Android. If `AnyOptionalProtocol` conformance does not survive transpilation, retain the string-based `Optional(...)` stripping as a fallback inside the `"\(raw)"` branch. The key improvement is one function, one call site.

### 3.4 ForEach: Producer of Identity

Replace `taggedRenderable()`/`taggedIteration()` with `identifiedRenderable()`/`identifiedIteration()`:

```swift
// ForEach.swift
private func identifiedRenderable(for renderable: Renderable, key: Any?) -> Renderable {
    guard let key else { return renderable }
    if renderable.identityKey != nil { return renderable }  // don't override existing
    return ModifiedContent(content: renderable, modifier: IdentityKeyModifier(key: key))
}
```

ForEach stops producing `TagModifier` with role `.tag` for identity purposes. It only produces `TagModifier` with role `.tag` when evaluated inside a selection context (Picker/TabView), carrying the raw un-normalised value for `selectionTag`.

### 3.5 Container Consumption: Universal Pattern

Every container render loop that iterates potentially-dynamic renderables uses:

```swift
for i in 0..<renderables.size {
    let renderable = renderables[i]
    let composeKey: Any = renderable.identityKey ?? i
    androidx.compose.runtime.key(composeKey) {
        renderable.Render(context: contentContext)
    }
}
```

Applied to:
- VStack non-animated (2 paths) — rename `composeKey` to `identityKey`
- VStack AnimatedContent (2 paths) — add `key()` wrapping (Tier 2, after empirical test)
- HStack non-animated (2 paths) — rename
- HStack AnimatedContent (2 paths) — add `key()` wrapping (Tier 2)
- ZStack (2 paths) — add `key()` wrapping (Tier 1)

Not applied to static-child contexts (toolbar items, NavigationLink labels, lazy section headers/footers). Paper 02 is correct: these are static, and Compose's positional identity is appropriate.

### 3.6 TagModifier Simplification

After decoupling:
- **`.tag` role:** No `key()` wrapping in `Render`. Purely a data annotation. Layer 3 is eliminated.
- **`.id` role:** Retains `key()` wrapping for state destruction semantics. Now normalises through `normalizeKey()` instead of using raw values.

```swift
@Composable override func Render(content: Renderable, context: ComposeContext) {
    if role == .id {
        let idKey = normalizeKey(value ?? Self.defaultIdValue)
        var ctx = context
        ctx.stateSaver = stateSaver
        androidx.compose.runtime.key(idKey) {
            super.Render(content: content, context: ctx)
        }
    } else {
        // .tag role: no key(), just data
        super.Render(content: content, context: context)
    }
}
```

### 3.7 Picker/TabView: Selection Consumers

TabView and Picker read `selectionTag` instead of raw `.tag` modifier values:

```swift
let tag = renderable.selectionTag  // Raw Swift value, compared in Swift
```

This eliminates the need for normalisation on the selection path (comparison is Swift-side, not Compose-side).

### 3.8 Duplicate Key Guard

In container render loops, add a lightweight deduplication guard:

```swift
var seenKeys = mutableSetOf<Any>()
for i in 0..<renderables.size {
    let renderable = renderables[i]
    var composeKey: Any = renderable.identityKey ?? i
    if !seenKeys.add(composeKey) {
        composeKey = "\(composeKey)_dup\(i)"
    }
    androidx.compose.runtime.key(composeKey) { ... }
}
```

This prevents Compose duplicate-key exceptions without silently hiding developer errors. The `_dup` suffix makes the deduplication visible in debugging.

---

## 4. Phasing

### Phase 0: Immediate Fixes (< 1 day, no architectural change)

These use the existing `composeKey` and existing patterns. Ship as standalone PRs.

1. **ZStack `key()` wrapping** — both Box loop paths. Mechanical copy of VStack/HStack pattern.
2. **`.id()` normalisation** — `composeKeyValue()` at `AdditionalViewModifiers.swift:1413, 1426`.
3. **TabView tag normalisation** — `composeKeyValue()` for raw tag reads.

### Phase 1: `identityKey` Introduction (3–5 days)

The core architectural change. One atomic PR.

1. Add `normalizeKey()` to `Renderable.swift`.
2. Add `IdentityKeyModifier` class.
3. Add `identityKey` and `selectionTag` extension properties on `Renderable`.
4. Deprecate `composeKey` and `composeKeyValue()`.
5. Refactor ForEach: `taggedRenderable` → `identifiedRenderable`, `taggedIteration` → `identifiedIteration`.
6. Update VStack/HStack non-animated loops: `composeKey` → `identityKey`.
7. Update ZStack loops (if not already done in Phase 0).
8. Simplify `TagModifier.Render`: remove `key()` for `.tag` role; normalise `.id` role.
9. Update TabView/Picker to read `selectionTag`.
10. Add duplicate-key guard to container loops.
11. Deprecate `composeBundleString` — lazy containers use `identityKey` from `IdentityKeyModifier` set during ForEach Evaluate. Equivalence test against `composeBundleString` output for key stability.

### Phase 2: AnimatedContent Fix (1–3 days, empirical)

Gated on a test that verifies `key()` inside `AnimatedContent` does not break `animateEnterExit`.

1. Write a test: animated ForEach in VStack, delete middle item, verify remaining items retain state AND deleted item gets exit animation.
2. If test infrastructure confirms compatibility: add `key(identityKey ?? i)` to VStack AnimatedContent (2 paths) and HStack AnimatedContent (2 paths).
3. If `key()` breaks `animateEnterExit`: investigate alternative (enriching `AnimatedContent`'s `contentKey` with per-item identity, or restructuring the animated rendering path). Document findings.

### Phase 3: Transpiler `stateVariables.isEmpty` Fix (1–2 days)

Independent of Phases 1–2. Can be done in parallel.

1. Remove the `stateVariables.isEmpty` guard at `KotlinBridgeToKotlinVisitor.swift:1734`.
2. Generate `_ComposeContent` with peer remembering for views that have both `@State` and `let`-with-default.
3. Keep state init in `Evaluate` (simpler variant from Paper 04 Section 5.2).
4. Add transpiler test in `BridgeToKotlinTests.swift`: view with `@State var count` + `let instanceID = UUID()` produces both `rememberSaveable` and `SwiftPeerHandle` in generated output.

### Deferred Indefinitely

- Transpiler structural ID injection (Section 5.1 explains why).
- Conditional branch identity (`if/else` `_ConditionalContent` parity).
- `AnyView` identity erasure.
- `explicitID` as a third field on `Renderable` (`.id()` works adequately via `TagModifier`).
- `key()` wrapping for static-child contexts (toolbar, NavigationLink labels, lazy section headers/footers).

---

## 5. What We Explicitly Reject and Why

### 5.1 Transpiler-Injected `__structuralID` (Paper 04, partially Paper 01)

**Rejected.** Three reasons:

1. **Compose already handles it.** Paper 02 correctly identifies that the Compose compiler plugin assigns source-location group keys to each `if/else` branch in the emitted Kotlin. The transpiler emits standard Kotlin control flow; Compose instruments it. The conditional identity gap exists only if the transpiler collapses distinct view sites into one Kotlin source position.

2. **Refactoring changes identity.** Paper 07 Section 4 is decisive: extracting a view into a helper function, moving between files, or reordering declarations changes the AST-derived ID, causing silent state loss on Android that cannot be reproduced on iOS and is invisible in code review.

3. **Maintenance cost.** Paper 06 quantifies: skipstone's code generation evolves rapidly, and structural changes conflict with nearly every upstream transpiler update. The fork maintenance burden is disproportionate to the benefit.

### 5.2 Full SwiftUI Identity Parity as a Near-Term Goal (Paper 01)

**Rejected as a near-term target, accepted as a long-term north star.** Paper 01's grading of SkipUI against 13 SwiftUI identity semantics is valuable as documentation but counterproductive as a work plan. Fixing S1 (`_ConditionalContent`), S3 (`AnyView` erasure), and S4 (stable container slots) requires either transpiler changes we reject (5.1) or fundamental changes to how `ComposeBuilder.Evaluate()` works. Paper 05 is right: ship the app, fix bugs when they appear.

### 5.3 `IdentifiedRenderable` Wrapper Type Instead of Modifier (Paper 02)

**Rejected.** Paper 03 Section 2.4 provides the definitive argument: a wrapper type adds another layer to `strip()`/`forEachModifier` traversal, creates nesting ambiguity with `ModifiedContent`, and interacts poorly with `LazyLevelRenderable`. Using a modifier (`IdentityKeyModifier`) that travels through the *existing* `ModifiedContent` chain is strictly simpler and leverages infrastructure that already works.

### 5.4 "Do Nothing More" / Pure Fix-Forward (Paper 05)

**Partially rejected.** Paper 05's surgical fixes (ZStack, `.id()` normalisation) are correct and form our Phase 0. But the "do nothing more architecturally" stance is rejected. Paper 07 Section 6 makes the compelling counter-argument: 14 gaps means 14 future fire drills, incremental fixes accumulate inconsistency, and the architectural fix gets harder over time. The `identityKey` introduction (Phase 1) is a bounded, well-defined change that prevents the "fix as you go" entropy Paper 07 warns about.

### 5.5 Three-Field Model as Immediate Requirement (Paper 01, 03)

**Partially rejected — deploy two fields now, defer the third.** The `explicitID` field (Paper 01's E1, Paper 03 Section 2.2) adds a third property that is not needed yet. `.id()` already works via `TagModifier` with role `.id`. The only immediate fix needed is normalisation (Phase 0). Adding `explicitID` as a `Renderable` property is warranted only if a bug surfaces where `.id()` state destruction fails in a way that cannot be fixed locally in `TagModifier`. Until then, two fields (`identityKey`, `selectionTag`) cover the two conflated concerns.

### 5.6 `key()` Wrapping for Static-Child Contexts (Paper 01)

**Rejected.** Paper 02 is correct: toolbar items, NavigationLink labels, lazy section headers/footers, and `ViewThatFits` candidates are static or near-static. Compose's positional identity is appropriate and correct for these. Adding `key()` to these paths is pure ceremony — runtime overhead for zero behavioural benefit. Paper 01's argument that "identity correctness is not probabilistic" is philosophically sound but practically wasteful when applied to children that do not change.

### 5.7 Development-Mode Warnings for Missing Keys (Paper 08)

**Rejected for now.** Paper 08 draws from React's convention of warning when list items lack keys. This is useful only when the framework provides a reliable mechanism to supply them. We should first ship `identityKey`, then consider warnings. Warnings before infrastructure create noise without actionable guidance.

---

## 6. Upstream Strategy

Following Paper 06's guidance, the changes partition into upstream-acceptable and fork-only:

**Upstream PRs (in order):**
1. ZStack per-item `key()` — standalone, mechanical
2. `.id()` normalisation — one-line bug fix
3. TabView tag normalisation — bug fix
4. AnimatedContent `key()` (with test) — after empirical validation
5. Duplicate key graceful handling — after identity decoupling

**Fork-only (not upstreamable per Paper 06):**
- `identityKey`/`selectionTag` on `Renderable` (extension properties, but touches too many files)
- `IdentityKeyModifier` and ForEach refactor
- `TagModifier.Render` simplification
- `normalizeKey()` unification
- `stateVariables.isEmpty` transpiler fix

The fork-only changes touch ~11 files with ~200 lines of net change. Per Paper 06's estimate, this will conflict roughly once every 2–3 months on upstream sync — manageable for the architectural benefit.

---

## 7. Files Modified (Complete List)

| File | Change | Phase |
|------|--------|-------|
| `Renderable.swift` | Add `identityKey`, `selectionTag`, `normalizeKey()`, `AnyOptionalProtocol`. Deprecate `composeKey`, `composeKeyValue()`. | 1 |
| `IdentityKeyModifier.swift` (new, or in Renderable.swift) | New modifier class | 1 |
| `ForEach.swift` | `taggedRenderable` → `identifiedRenderable`, `taggedIteration` → `identifiedIteration` | 1 |
| `AdditionalViewModifiers.swift` | Normalise `.id()` via `normalizeKey()`. Remove `.tag` role `key()` in `Render`. | 0+1 |
| `VStack.swift` | `composeKey` → `identityKey` (non-animated). Add `key()` to AnimatedContent. | 0+2 |
| `HStack.swift` | Same as VStack | 0+2 |
| `ZStack.swift` | Add `key(identityKey ?? i)` to both Box loops | 0 |
| `TabView.swift` | Read `selectionTag`. Normalise tag reads. | 0+1 |
| `Picker.swift` | Read `selectionTag` | 1 |
| `LazyVStack.swift`, `LazyHStack.swift`, `LazyVGrid.swift`, `LazyHGrid.swift`, `List.swift` | Replace `composeBundleString` with `identityKey` in key lambdas | 1 |
| `ComposeStateSaver.swift` | Deprecate `composeBundleString` | 1 |
| `KotlinBridgeToKotlinVisitor.swift` | Remove `stateVariables.isEmpty` guard | 3 |
| `BridgeToKotlinTests.swift` | Test for `@State` + `let`-with-default combined codegen | 3 |

---

## 8. Summary

The canonical approach is: **two-field identity model (`identityKey` + `selectionTag`) on `Renderable` via non-breaking extension properties, with a single `normalizeKey()` function called at the producer, consumed uniformly by eager containers.** This decouples selection from identity (the root architectural problem), eliminates Layer 3 redundancy, unifies three normalisation paths into one, and closes the high-severity gaps — all without protocol-breaking changes or transpiler structural ID injection.

The approach is deliberately less ambitious than Paper 01's full SwiftUI parity and Paper 04's transpiler-first vision. It is deliberately more structured than Paper 05's fix-forward pragmatism. It threads the needle identified by Paper 07: address verified bugs and prevent architectural entropy, without introducing new abstractions whose failure modes are not yet understood.
