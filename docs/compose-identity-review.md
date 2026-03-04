# Compose View Identity: Architecture Review & Findings

> **Date:** 2026-03-01
> **Status:** Active — gaps identified, not all resolved
> **Related:** `docs/skip/compose-view-identity-gap.md`, `docs/observation-architecture-decision.md`

## Background

SwiftUI has view identity baked in from the ground up. Compose uses positional identity in
its slot table, supplemented by `key()`. The Skip bridge must translate between these models.

We implemented a 3-layer identity system to solve state loss in ForEach lists (deleting item N
caused items N+1.. to lose counters and instance UUIDs). The fix is verified working for the
ForEach/VStack case, but a triple-model review (Claude Opus, Codex, Gemini) identified
architectural concerns and gaps that extend beyond ForEach.

## Current Implementation: 3 Layers

### Layer 1: Transpiler Peer Remembering

**Files:** `forks/skipstone/Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift`

For bridged View structs with `let`-with-default properties (`let store = Store(...)`,
`let instanceID = UUID()`), the transpiler generates `remember`-based code in a
`_ComposeContent` override:

- **No constructor params (Phase 1):**
  `remember { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }`
- **Has constructor params (Phase 2):**
  `remember(Swift_inputsHash(Swift_peer)) { SwiftPeerHandle(...) }`

`SwiftPeerHandle` implements `RememberObserver` for retain/release lifecycle, pairing
Swift ARC with Compose slot table lifetime.

**Purpose:** Preserves the Swift peer pointer (native memory) across Compose recompositions.
Without this, every recomposition allocates a new Swift peer, losing `let`-with-default state.

### Layer 2: Container key() Wrapping

**Files:** `forks/skip-ui/.../Containers/VStack.swift`, `HStack.swift`

In Column/Row render loops, each renderable is wrapped with `key(composeKey)`:

```swift
let composeKey: Any = renderable.composeKey ?? i  // fallback to index
androidx.compose.runtime.key(composeKey) {
    renderable.Render(context: contentContext)
}
```

Adaptive spacing is emitted OUTSIDE the key() scope to avoid destabilising composition
structure (a subtle but critical detail — spacing inside key() changes the group's structure
between iterations, preventing Compose from matching groups).

**Purpose:** Tells Compose to match items by key rather than position in the parent
Column/Row, surviving insertions and deletions.

### Layer 3: TagModifier.Render key() Wrapping

**Files:** `forks/skip-ui/.../View/AdditionalViewModifiers.swift`

TagModifier wraps content in `key(composeKeyValue(value))` during the Render phase for
items with `.tag` role:

```swift
} else if role == .tag, let value {
    let convertedKey = composeKeyValue(value)
    androidx.compose.runtime.key(convertedKey) {
        super.Render(content: content, context: context)
    }
}
```

**Purpose:** Provides identity for ForEach items in non-container contexts (ZStack, Group,
custom containers that don't iterate renderables themselves).

### Key Conversion

**File:** `forks/skip-ui/.../Compose/Renderable.swift`

`composeKeyValue()` converts bridged values to Compose-safe types:
- String/Int/Long pass through directly
- Others are stringified via `"\(raw)"`
- `Optional(...)` wrapper from SwiftHashable JNI `toString()` is stripped

## Triple-Model Review Findings

### Consensus (all three models agree)

#### 1. Layer 1 is essential and orthogonal
Transpiler peer remembering solves Swift ARC lifecycle ↔ Compose slot table, a fundamentally
different problem from list identity. Well-designed, no changes needed.

#### 2. Layer 3 is redundant for ForEach items in containers
VStack/HStack already apply `key(composeKey)` using the same tag value. TagModifier's inner
`key()` creates unnecessary nested slot table entries. Compose handles nested `key()` gracefully
(compound keys), so it works but is wasteful and blurs ownership of identity.

**Recommendation:** Consider removing TagModifier.Render `key()` for `.tag` role when the
container already handles it. However, Layer 3 is still needed for non-container contexts.

#### 3. Eval-phase key() removal is correct
The ForEach Evaluate phase had `key()` calls that were removed because `evaluateKeyed()`
creates non-inline function boundaries. Compose can only move `key()` movable groups within
the same parent group — a non-inline function boundary prevents groups from being moved
across loop iterations. The Evaluate phase produces a flat `List<Renderable>`, and the actual
Compose composition tree is built later during Render.

#### 4. `composeKeyValue()` Optional stripping is fragile
String-based `Optional(...)` stripping depends on Swift's `String(describing:)` format.
Risks: nested optionals, values containing parentheses, format instability.

**Alternative:** Protocol-based structural unwrapping (proposed by Gemini):
```swift
fileprivate protocol AnyOptional {
    var flattenedValue: Any? { get }
}
extension Optional: AnyOptional {
    var flattenedValue: Any? {
        switch self {
        case .some(let wrapped): return (wrapped as? AnyOptional)?.flattenedValue ?? wrapped
        case .none: return nil
        }
    }
}
```
Note: May not work on Kotlin side where Optional is native nullability, not a type.

#### 5. Dedicated identity side-channel is the most elegant long-term solution
All three models independently proposed: add a first-class identity property to `Renderable`
rather than piggybacking on `.tag()` modifiers:
- Add `structuralID: Any?` to `Renderable` protocol (defaults to `nil`)
- ForEach sets it during Evaluate via lightweight `IdentifiedRenderable` wrapper
- VStack/HStack read `renderable.structuralID ?? i` for keys
- Remove `.tag`-based identity; `.tag()` returns to its SwiftUI purpose (Picker/TabView selection)

### Confirmed Gaps

#### Gap 1: Stateful views with let-with-default don't get peer remembering
**Severity: Medium** | **Source: Codex** | **Confirmed by code analysis**

The transpiler has two mutually exclusive paths:
- State syncing: generates `Evaluate` with `rememberSaveable` for `@State`/`@Environment`
- Peer remembering: generates `_ComposeContent` with `remember { SwiftPeerHandle }`

Guard at line 1734: `(canRememberPeer || canRememberPeerWithInputCheck) && stateVariables.isEmpty`

A view with BOTH `@State` and `let instanceID = UUID()` gets ONLY state syncing — the peer
is NOT remembered. `instanceID` would be recreated every recomposition.

**Impact:** Does not affect our current test case (CounterCard has no `@State`). Affects views
combining `@State`/`@Environment` with identity-bearing `let`-with-default properties.

**Fix:** Generate `_ComposeContent` that handles BOTH state syncing and peer remembering.
Move `rememberSaveable` calls from the Evaluate override into `_ComposeContent` so both run
in the Render phase inside stable key() scopes. Medium complexity — changes generated Kotlin
for all stateful views.

#### Gap 2: `.id` path not normalised through composeKeyValue()
**Severity: Medium** | **Source: Codex**

`composeKeyValue()` (SwiftHashable → Compose-safe key conversion) is only applied to `.tag`
paths. The `.id` role in TagModifier uses raw values:
- `AdditionalViewModifiers.swift:1426`: `key(value ?? Self.defaultIdValue)` — raw, not converted
- `VStack.swift:82`, `HStack.swift:79`: animation logic reads raw `.id` values

If SwiftHashable equality problems exist for `.id` values (same JNI bridge), identity would
break in `.id`-driven paths too.

#### Gap 3: AnimatedContent path missing per-item key()
**Severity: Medium** | **Source: Claude**

`RenderAnimatedContent` in VStack (lines 224-235) and HStack iterates
`for renderable in state` WITHOUT per-item `key()` wrapping. If ForEach items with individual
tags flow through this animated path, they lose positional identity within the Column/Row.

The `AnimatedContent` uses `contentKey` to diff at the list level, but individual items within
the layout are not keyed.

#### Gap 4: Class-typed constructor params skipped in inputsHash
**Severity: Low** | **Source: Codex**

The generated `Swift_inputsHash` intentionally skips `AnyClass` values to avoid false churn
from unstable reference wrappers. But this means some real logical input changes won't reset
the remembered peer.

### Disagreement: Eval-phase key restoration

Gemini suggested restoring eval-phase keys inline within ForEach's loop. Claude and Codex
correctly identify this as wrong: the Evaluate phase produces a flat list before any Compose
composition scope exists. The transpiler's `remember` runs in `_ComposeContent` (Render phase),
not during Evaluate.

## Recommended Work Items

### Short-term (low risk, immediate value)
1. Apply `composeKeyValue()` to `.id` paths for consistency (Gap 2)
2. Harden Optional stripping (nested optionals, or protocol-based unwrapping)
3. Audit AnimatedContent path for missing key() (Gap 3)

### Medium-term (the stateful views fix)
4. Merge state syncing into `_ComposeContent` for views with both `@State` and let-with-default (Gap 1)

### Long-term (architectural elegance)
5. Add `structuralID` to `Renderable` protocol, eliminating Tag↔Identity conflation
6. Remove TagModifier.Render key() for `.tag` role (Layer 3 redundancy)
7. Comprehensive identity audit across all SkipUI containers and modifiers

## Open Questions

1. **How many other SkipUI containers iterate renderables without key()?** VStack and HStack
   are fixed, but ZStack, Group, Section, NavigationStack, TabView, and custom containers may
   have the same positional-identity problem.

2. **Does the `.id()` modifier work correctly for state reset semantics?** SwiftUI's `.id()`
   modifier is supposed to destroy and recreate a view's state when the ID changes. Does
   SkipUI's TagModifier achieve this?

3. **How does conditional view identity work?** SwiftUI assigns different structural identity
   to `if/else` branches. Does SkipUI handle this through Compose's slot table, or are there
   gaps?

4. **What about `AnyView` type erasure?** SwiftUI warns that `AnyView` breaks structural
   identity. Does SkipUI's `ComposeView` wrapper have similar implications?

## Test Coverage

Tests that should exist but may not:
1. Bridged view with `@State` + `let instanceID = UUID()` in ForEach — delete middle item
2. `.id()` values via SwiftHashable bridge — verify state reset on ID change
3. Multi-renderable ForEach iteration (item + Divider) — preserving identity on delete
4. AnimatedContent path with ForEach items — verify identity preservation
5. Collision cases for Optional and non-string key types
6. Views in ZStack/Group/Section with identity — verify key() coverage
