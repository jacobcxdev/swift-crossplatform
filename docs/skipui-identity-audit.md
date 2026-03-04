# SkipUI View Identity: Comprehensive Audit Report

> **Date:** 2026-03-01
> **Status:** Complete — gaps catalogued, remediation plan proposed
> **Auditors:** Claude Opus (architect), OpenAI Codex (high reasoning), Google Gemini Pro
> **Related:** `docs/compose-identity-review.md`, `docs/observation-architecture-decision.md`

## Executive Summary

A triple-model audit of **every SkipUI container** that iterates renderables reveals **systematic
identity gaps** beyond the ForEach/VStack fix already in place. The current 3-layer identity system
works for non-animated VStack/HStack paths but fails in 6 other container contexts. All three
auditors independently conclude the 3-layer architecture **does not scale** and recommend a
first-class identity property on `Renderable`.

**By the numbers:**
- 24 container files audited
- 14 renderable iteration paths found without `key()` wrapping
- 3 High severity, 5 Medium severity, 6 Low severity gaps
- 3 distinct key normalisation paths (`composeKeyValue`, `composeBundleString`, raw `Any`)

## Gap Inventory

### Legend
- **Covered**: Has per-item `key()` wrapping — identity preserved on insert/delete/reorder
- **Missing**: No `key()` — positional identity only, state migrates to wrong items on mutation
- **Partial**: Has whole-list keying but not per-item keying

### High Severity (state loss on common operations)

| Container | Path | File:Line | key()? | Impact |
|-----------|------|-----------|--------|--------|
| VStack | AnimatedContent v0 | VStack.swift:224 | Missing | ForEach items lose identity when animated insert/delete occurs |
| VStack | AnimatedContent v1+ | VStack.swift:250 | Missing | Same — all three auditors rate High |
| HStack | AnimatedContent v0 | HStack.swift:188 | Missing | Horizontal equivalent of VStack AnimatedContent gap |
| HStack | AnimatedContent v1+ | HStack.swift:213 | Missing | Same |
| ZStack | Non-animated Box loop | ZStack.swift:58 | Missing | ForEach items in overlays lose identity on mutation |
| ZStack | AnimatedContent Box loop | ZStack.swift:93 | Missing | Same, compounded by animation misattribution |

### Medium Severity (correctness risk with bridged types or dynamic content)

| Container | Path | File:Line | key()? | Impact |
|-----------|------|-----------|--------|--------|
| TagModifier | `.id` role Render | AdditionalViewModifiers.swift:1426 | Raw value | `.id()` uses raw SwiftHashable, not `composeKeyValue()` — JNI equality fails silently |
| TagModifier | `.id` role stateSaver | AdditionalViewModifiers.swift:1413 | Raw value | Same path for state saver key |
| TabView | Tab identity | TabView.swift:438,478 | Index-based | Content state keyed by tab index, not tag identity; dynamic tab insertion/reorder breaks |
| Navigation | Toolbar leading items | Navigation.swift:385 | Missing | Dynamic toolbar items can migrate state between positions |
| Navigation | Toolbar trailing items | Navigation.swift:393 | Missing | Same |
| ViewThatFits | Candidate rendering | ViewThatFits.swift:40 | Missing | All candidates exist in composition simultaneously; non-chosen retain stale state |

### Low Severity (rarely hit in practice)

| Container | Path | File:Line | key()? | Impact |
|-----------|------|-----------|--------|--------|
| LazyVStack | Section headers | LazyVStack.swift:134 | Missing | Headers rarely dynamic; positional if sections inserted |
| LazyVStack | Section footers | LazyVStack.swift:141 | Missing | Same |
| LazyHStack | Section headers/footers | LazyHStack.swift:117-126 | Missing | Same |
| LazyVGrid/LazyHGrid | Section headers/footers | LazyVGrid.swift:149, LazyHGrid.swift:131 | Missing | Same |
| List | Section headers (`stickyHeader`) | List.swift:302 | Missing | Headers positional if sections change |
| List | Section footers | List.swift:316 | Missing | Same |
| NavigationLink | Label renderables | Navigation.swift:1352 | Missing | Multi-child labels uncommon |

### Correctly Covered (no gaps)

| Container | Path | File:Line | Notes |
|-----------|------|-----------|-------|
| VStack | Non-animated v0 | VStack.swift:131 | `key(composeKey ?? i)` |
| VStack | Non-animated v1+ | VStack.swift:165 | `key(composeKey ?? i)` |
| HStack | Non-animated v0 | HStack.swift:114 | `key(composeKey ?? i)` |
| HStack | Non-animated v1+ | HStack.swift:135 | `key(composeKey ?? i)` |
| LazyVStack | `items(count:key:)` data | LazyVStack.swift:114 | Compose-native lazy key API |
| LazyHStack | `items(count:key:)` data | LazyHStack.swift:100 | Same |
| LazyVGrid | `items(count:key:)` data | LazyVGrid.swift:123 | Same |
| LazyHGrid | `items(count:key:)` data | LazyHGrid.swift:106 | Same |
| List | `items(count:key:)` data | List.swift:270-290 | `composeBundleString` keying |
| Group | Transparent Evaluate | Group.swift:33 | No rendering, no iteration |
| Section | Transparent Evaluate | Section.swift:85 | No rendering, no iteration |
| ScrollView | Delegates to content | ScrollView.swift:129 | No direct iteration |

## SwiftUI Semantics Gaps

### 1. `.id()` does not normalise bridged values (all three agree)

**SwiftUI:** `.id(value)` destroys and recreates view state when value changes.
**SkipUI:** `TagModifier` uses `key(value ?? Self.defaultIdValue)` with **raw** SwiftHashable values
(line 1413, 1426 of AdditionalViewModifiers.swift). The `.tag` role correctly uses
`composeKeyValue(value)` for normalisation, but `.id` does not.

**Consequence:** Bridged Swift types (UUID, enums, custom Hashable) used with `.id()` may fail
Compose's internal key comparison via JNI `equals()`, causing either:
- Constant state destruction (if Compose sees different keys each recomposition), or
- No state destruction when it should occur (if equality is unreliable)

### 2. Conditional view identity not tracked (Codex + Gemini agree)

**SwiftUI:** `if/else` branches in `@ViewBuilder` get distinct structural identity via
`_ConditionalContent`. Toggling a branch destroys one view's state and creates the other's.

**SkipUI:** `ViewBuilder` support is built into the Skip transpiler (ViewBuilder.swift:3 is a stub).
`ComposeBuilder` runs a composable lambda directly. Branch identity relies entirely on Compose's
positional slot table for the emitted control flow.

**Consequence:** If an `if` branch adds a view above existing views, the flat renderable list shifts.
Views below the insertion point inherit state from views that previously occupied their position.
Example: `if flag { TextField() }; TextField()` — toggling `flag` causes the second TextField to
inherit the first's text state.

### 3. Duplicate `.tag()` values crash Compose (Gemini unique finding)

**SwiftUI:** Duplicate `.tag()` values are legal outside selection contexts (Picker/TabView).
**SkipUI:** VStack/HStack apply `key(composeKey)` using tag values. Compose throws a
"Multiple identical keys" exception for duplicate keys in the same scope.

**Consequence:** Legal SwiftUI code like `VStack { Text("A").tag(1); Text("B").tag(1) }` crashes
on Android.

### 4. AnyView does not erase structural identity (Claude + Gemini agree)

**SwiftUI:** `AnyView` breaks structural identity — SwiftUI must use type-based heuristics.
**SkipUI:** `AnyView` transparently delegates `Evaluate` to the wrapped view. No identity erasure.

**Consequence:** Changing the wrapped type inside AnyView may not reset state if old and new types
produce the same number of renderables. Approximately correct in practice due to Compose's own
type-based recomposition, but not semantically identical to SwiftUI.

### 5. Tag/Identity conflation (all three agree)

`.tag()` serves dual purpose: selection (Picker/TabView) and structural identity (ForEach keying
via `composeKey`). ForEach's `taggedRenderable()` checks for existing tags before adding defaults
(ForEach.swift:298), which is correct. But the architectural conflation means:
- Three distinct key normalisation paths exist: `composeKeyValue` (tag→String), `composeBundleString`
  (lazy items→String), and raw `Any` (`.id`, TabView tags)
- TabView reads raw `.tag` for selection (TabView.swift:478) without normalisation
- User-applied `.tag()` for Picker selection collides with ForEach identity in edge cases

### 6. ViewThatFits retains state for non-displayed candidates (Claude unique finding)

**SwiftUI:** Only the fitting view exists in the view hierarchy.
**SkipUI:** All candidates are rendered in a Layout composable for measurement, meaning non-chosen
candidates exist in the composition and retain state.

## Architecture Assessment

**Consensus: The 3-layer approach does not scale.**

All three auditors independently reached this conclusion:

1. **Manual, path-sensitive**: Each container must independently implement `key()` wrapping. The
   AnimatedContent gap proves that even within a single file, it's easy to miss paths.

2. **Inconsistent normalisation**: Three different key conversion paths (`composeKeyValue`,
   `composeBundleString`, raw `Any`) guarantee drift and subtle equality bugs.

3. **Dual-keying ambiguity**: Non-animated VStack/HStack have double `key()` (container + TagModifier),
   while AnimatedContent/ZStack have only TagModifier's inner `key()`. No clear contract about which
   layer owns identity.

4. **Non-inline function boundary trap** (Gemini): TagModifier.Render is a protocol method (non-inline).
   When it calls `key()`, Compose creates the movable group *nested inside* a non-movable positional
   group. Compose cannot move the group across loop iterations. This means Layer 3 (TagModifier key)
   is **structurally ineffective** for positional matching — it only provides subtree-level key scoping.

### Codex's Three-Field Model

Codex proposes the identity model needs at least three fields:
- `selectionTag: Any?` — for Picker/TabView selection binding (what `.tag()` should be)
- `explicitID: Any?` — for `.id()` state destruction semantics
- `identityKey: Any?` — consumed by sibling containers and lazy APIs (what `composeKey` should be)

`identityKey` should be Compose-safe exactly once, propagated through wrappers (`ModifiedContent`,
`LazyLevelRenderable`, `ComposeView`), and consumed everywhere a sibling loop or lazy item is emitted.

### Gemini's Transpiler Structural ID

Gemini proposes the transpiler should inject a hidden static `__structuralID: String` based on AST
location into every view struct. This mimics SwiftUI's structural identity and fixes ViewBuilder
flattening state leaks. It also prevents duplicate-tag crashes — containers would use `structuralID`
as primary key, with `identityKey` as override for ForEach items.

## Remediation Plan

### Phase 1: Fix Concrete Holes (Short-term, low risk)

These are mechanical fixes that don't change architecture. They close the highest-severity gaps
using the pattern already proven in VStack/HStack non-animated paths.

| # | Fix | Files | Effort | Severity Addressed |
|---|-----|-------|--------|-------------------|
| 1a | Add per-item `key(composeKey ?? i)` to ZStack both paths | ZStack.swift | Low | High |
| 1b | Add per-item `key(composeKey ?? i)` to VStack AnimatedContent (2 paths) | VStack.swift | Medium | High |
| 1c | Add per-item `key(composeKey ?? i)` to HStack AnimatedContent (2 paths) | HStack.swift | Medium | High |
| 1d | Normalise `.id` through `composeKeyValue()` | AdditionalViewModifiers.swift | Low | Medium |
| 1e | Add `key` to lazy section headers/footers | LazyVStack/HStack/VGrid/HGrid.swift, List.swift | Low | Low |
| 1f | Add `key` to Navigation toolbar loops | Navigation.swift | Low | Low |

**AnimatedContent complexity note**: The animated paths iterate `for renderable in state` without a
natural index variable. The fix requires either `state.forEachIndexed` or manual index tracking.
Additionally, `key()` inside `AnimatedContent`'s content lambda may interact with `animateEnterExit`
— needs testing.

### Phase 2: Unify Key Normalisation (Medium-term)

| # | Fix | Files | Effort |
|---|-----|-------|--------|
| 2a | Unify `composeKeyValue` and `composeBundleString` into single normalisation | Renderable.swift, List.swift, LazyVStack.swift, etc. | Medium |
| 2b | Normalise TabView tag reading through `composeKeyValue` | TabView.swift | Low |
| 2c | Handle duplicate keys gracefully (fallback to `tag + index`) | VStack.swift, HStack.swift, ZStack.swift | Medium |

### Phase 3: Architectural Refactor (Long-term, high impact)

| # | Fix | Files | Effort |
|---|-----|-------|--------|
| 3a | Add `identityKey: Any?` to `Renderable` protocol | Renderable.swift | Medium |
| 3b | Add `selectionTag: Any?` separate from identity | Renderable.swift, TagModifier | Medium |
| 3c | ForEach sets `identityKey` during Evaluate, not `.tag` | ForEach.swift | Medium |
| 3d | All containers read `renderable.identityKey ?? i` | Every container file | High |
| 3e | Remove `.tag`-based identity from `composeKey` | Renderable.swift | Low |
| 3f | Remove TagModifier.Render `key()` for `.tag` role | AdditionalViewModifiers.swift | Low |
| 3g | Investigate transpiler structural ID injection | KotlinBridgeToKotlinVisitor.swift | High |

### Dependency Graph

```
Phase 1 (independent fixes):
  1a ──┐
  1b ──┤
  1c ──┼── can be done in parallel
  1d ──┤
  1e ──┤
  1f ──┘

Phase 2 (after Phase 1):
  2a ── 2b ── 2c

Phase 3 (after Phase 2):
  3a ── 3b ── 3c ── 3d ── 3e ── 3f
                                  │
  3g (independent) ───────────────┘
```

## Test Matrix

### Identity Preservation Tests

| # | Scenario | Container | Expected Behaviour |
|---|----------|-----------|-------------------|
| T1 | ForEach in animated VStack: delete middle item | VStack (animated) | Remaining items retain counter + instanceID |
| T2 | ForEach in animated HStack: insert at beginning | HStack (animated) | Existing items don't reset; new item gets fresh state |
| T3 | ForEach in ZStack: delete/reorder overlay cards | ZStack | Cards retain state through reorder |
| T4 | `.id(UUID())` on bridged view: change UUID | Any container | View state fully resets |
| T5 | `.id(UUID())` unchanged across recomposition | Any container | View state preserved (no spurious reset) |
| T6 | ForEach in lazy list: delete middle item | LazyVStack/List | Remaining items retain state; smooth animation |
| T7 | Dynamic section with stateful header | LazyVStack/List | Header identity stable across content changes |
| T8 | Dynamic tab insertion/reorder | TabView | Tab-local state follows tag, not page index |
| T9 | `if/else` toggling stateful branches | VStack | Each branch gets independent state |
| T10 | ViewThatFits with stateful candidates | ViewThatFits | Non-displayed candidate doesn't retain stale state |

### Crash/Edge Case Tests

| # | Scenario | Expected |
|---|----------|----------|
| T11 | Duplicate `.tag()` values in VStack | No crash (graceful fallback, not Compose exception) |
| T12 | Selection binding with bridged enum tag | TabView/Picker selection round-trips correctly |
| T13 | `.id()` with nested Optional value | State resets correctly, no Optional wrapping artefacts |
| T14 | Conditional toolbar items in NavigationStack | Button state attached to correct item |

## Auditor Agreement Matrix

| Finding | Claude | Codex | Gemini |
|---------|--------|-------|--------|
| ZStack missing key() | Medium | High | High |
| AnimatedContent missing key() | High | High | High |
| .id() raw values | Medium | Medium | High |
| 3-layer doesn't scale | Yes | Yes | Yes |
| structuralID recommended | Yes | Yes (3-field) | Yes (transpiler) |
| Lazy data rows correct | Yes | Yes | Yes |
| Lazy headers/footers gap | Low | Medium | Low |
| Tag/Identity conflation | Yes | Yes | Yes |
| ViewBuilder conditionals gap | Noted | Yes | Yes |
| Duplicate tags crash risk | No | No | Yes (unique) |
| ViewThatFits state leak | Medium | Low | Not flagged |
| TabView index-based identity | Not flagged | High | Medium |
| Non-inline boundary trap | Referenced | Not flagged | Yes (unique) |

## Open Questions

1. **AnimatedContent + key() interaction**: Does per-item `key()` inside `AnimatedContent`'s content
   lambda interact with `animateEnterExit`? Needs empirical testing before implementing fix 1b/1c.

2. **Transpiler structural ID feasibility**: Gemini's proposal to inject `__structuralID` from AST
   location requires understanding the transpiler's ViewBuilder lowering. How much of SwiftUI's
   `_ConditionalContent` model can be recovered from the transpiler's output?

3. **Compose duplicate key tolerance**: Gemini identifies that duplicate `.tag()` values crash
   Compose. Is this an actual crash path, or does Compose handle it gracefully? Needs empirical test.

4. **TabView dynamic tab support**: Codex rates TabView's index-based identity as High severity.
   How common is dynamic tab insertion/reorder in practice? Is this a blocking concern?

5. **stateVariables.isEmpty guard**: From the prior review — views with both `@State` and
   `let`-with-default don't get peer remembering. Is this a blocking fix for Phase 1, or can it wait?

## References

- Prior review: `docs/compose-identity-review.md`
- Observation architecture: `docs/observation-architecture-decision.md`
- Identity gap original docs: `docs/skip/compose-view-identity-gap.md`
- Phase 18 plan: `.planning/phases/18-complete-view-identity-layer-implementation/`
