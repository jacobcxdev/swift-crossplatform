# Position Paper 08: Cross-Framework View Identity Comparison

> **Date:** 2026-03-01
> **Role:** Cross-Framework Comparator
> **Status:** Complete
> **References:** `docs/skipui-identity-audit.md`, `docs/compose-identity-review.md`

## Introduction

SkipUI's view identity problem -- bridging SwiftUI's identity model to Compose's slot table -- is not unique. Every cross-platform UI framework must reconcile "which component is this?" across rendering boundaries. This paper examines how React Native, Flutter, Compose Multiplatform, and web frameworks solve analogous problems, then extracts patterns that can inform SkipUI's architecture.

---

## 1. React Native's Reconciliation Model

### How React's `key` Prop Works

React's reconciler (Fiber) uses a two-pass identity system:

1. **Structural identity by position and type.** Two elements at the same position in the same parent with the same component type are considered the same instance. React preserves their state across renders.
2. **Explicit identity via `key`.** When rendering lists or when the developer wants to force identity association, a `key` prop overrides positional matching. Keys must be unique among siblings, stable across renders, and derived from the data (not from the render index).

React's reconciler walks the old and new fiber trees in parallel. For each position, it checks: same type? If yes, reuse the fiber (update props). If no, unmount the old fiber and mount a new one. When `key` is present, React builds a map of `key -> fiber` from the old children and looks up matches regardless of position.

**Crucially, React treats missing keys as positional identity.** There is no intermediate state -- either you have an explicit key or you have positional identity. This binary model is simple and well-understood.

### The Bridge Problem in React Native

React Native faces a version of the "two identity systems" problem, but it is structurally different from SkipUI's:

- **React Native's bridge is imperative, not declarative.** The JavaScript thread runs React's reconciler and produces a stream of `createView`, `updateView`, `removeView`, and `moveView` commands sent over the bridge (or, in the New Architecture, via JSI). The native side never runs its own reconciliation -- it simply executes mutations.
- **Identity is assigned once, on the JS side.** Each native view gets a numeric `reactTag` when created. This tag is the view's identity for its entire lifetime. The native side never needs to figure out which view is which -- the JS reconciler already did that work.
- **There is no "two reconcilers" problem.** UIKit/Android Views don't have their own identity-based diffing. They are stateful objects that persist until explicitly removed.

**Lesson for SkipUI:** React Native sidesteps the dual-identity problem entirely by making one side (JS) the single source of identity truth, with the other side (native) as a dumb executor. SkipUI cannot do this because Compose has its own slot table that actively manages composition state. SkipUI's renderables enter Compose's composition tree, at which point Compose's identity rules take over. This is fundamentally harder than React Native's model.

### What SkipUI Can Learn

- **Keys should be data-derived, never index-derived.** React's documentation is emphatic about this. SkipUI's `composeKey ?? i` fallback to index is a pragmatic compromise, but it means unkeyed items silently degrade to positional identity. React would warn in development mode.
- **Key scope is per-sibling-group.** Keys only need to be unique among siblings, not globally. SkipUI's current model respects this (keys are per-container loop), which is correct.
- **Key stability matters more than key uniqueness.** A key that changes every render is worse than no key at all. SkipUI's `composeKeyValue()` stringification must be deterministic -- the Optional-stripping fragility flagged in the audit is exactly the kind of instability React's model warns against.

---

## 2. Flutter's Element Tree

### Widget, Element, RenderObject

Flutter's rendering pipeline has three layers:

1. **Widget** -- an immutable configuration object (like SwiftUI's `View` struct). Widgets are cheap to create and are rebuilt every frame.
2. **Element** -- a mutable object that sits in the element tree and holds state. Elements are the identity holders. An element is created when a widget is first mounted and persists across rebuilds as long as the framework considers the widget "the same."
3. **RenderObject** -- the actual layout/paint node. Managed by the element.

Flutter's identity algorithm for elements:

1. Walk old and new widget lists in parallel (like React).
2. Two widgets match if they have the **same `runtimeType` AND the same `key`** (if a key is present).
3. If matched, the element is updated with the new widget's configuration.
4. If not matched, the old element is unmounted and a new one is created.

### Flutter's Key Hierarchy

Flutter provides a rich key taxonomy:

| Key Type | Identity Semantics |
|----------|-------------------|
| `ValueKey<T>` | Identity by value equality of the wrapped `T` |
| `ObjectKey` | Identity by object reference (`identical()`) |
| `UniqueKey` | Every instance is unique -- forces fresh state |
| `GlobalKey` | Unique across the entire widget tree, not just siblings |
| `PageStorageKey` | Persists scroll position across navigation |

**`GlobalKey` is particularly interesting.** It allows a widget to maintain its element (and state) even when it moves to a completely different location in the tree. This is used for hero animations, form field preservation across navigation, and overlay management.

**Does SkipUI need GlobalKey?** Probably not in the short term. SwiftUI does not have an equivalent -- `@State` is always scoped to structural identity, and moving a view to a different position in the hierarchy resets its state. However, if SkipUI ever needs to implement matched geometry effects or navigation transition animations, a global identity mechanism would be necessary on the Compose side.

### Flutter's Advantage: No Bridge

Flutter compiles to native rendering via Skia/Impeller. There is no "bridge between two UI frameworks." The Widget/Element/RenderObject pipeline is a single, unified system. This means:

- There is exactly one identity system (the Element tree).
- Keys are consumed by exactly one reconciler.
- There is no translation step where key semantics could be lost.

**Lesson for SkipUI:** Flutter's clean separation of configuration (Widget) from identity (Element) from rendering (RenderObject) is instructive. SkipUI's `Renderable` conflates all three -- it is the configuration, the identity carrier (via `composeKey`), and the render entry point (via `Render()`). The audit's recommendation to add a first-class `identityKey` to `Renderable` is a step toward Flutter's separation, but it does not go as far as creating a distinct identity layer.

### What SkipUI Can Learn

- **Type + key is the universal matching rule.** Flutter, React, and Compose all use some form of "same type at same position, optionally overridden by key." SkipUI should ensure its identity model respects this -- currently, `composeKey` overrides position but does not encode type information.
- **Multiple key types serve different purposes.** Flutter's `ValueKey` vs `ObjectKey` vs `UniqueKey` distinction maps to real use cases. SkipUI's single `composeKeyValue()` path that stringifies everything loses this distinction. A UUID-based identity and a string-based identity should not go through the same normalization path.
- **Explicit "reset state" is a key type, not a side effect.** Flutter's `UniqueKey()` says "always treat this as new." SwiftUI's `.id()` modifier serves the same purpose. SkipUI's `.id` path using raw SwiftHashable values (flagged in the audit) should be modeled as a distinct identity operation, not as a variant of `.tag()`.

---

## 3. Compose Multiplatform

### Identity Across Backends

Compose Multiplatform (by JetBrains) extends Jetpack Compose to Desktop (JVM), Web (Canvas/WASM), and iOS (via Skiko). The key question: does Compose Multiplatform face a dual-identity problem when targeting different backends?

**No, it does not.** Compose Multiplatform uses the same Compose runtime and slot table on every platform. The backend differences are in the rendering layer (Skia on Desktop/iOS, Canvas on Web), not in the composition layer. The slot table, `key()`, `remember()`, and positional memoization work identically everywhere.

This means there is **no precedent within Compose Multiplatform for wrapping or translating Compose's identity model.** SkipUI's challenge -- injecting identity information from an external framework (SwiftUI) into Compose's slot table -- is genuinely novel.

### How Compose's `key()` Works Internally

Compose's slot table is a linear array of groups. Each group records:
- A **key** (either positional hash or explicit via `key()`)
- A **node** (the emitted UI element, if any)
- **Slots** (stored `remember` values, state, etc.)

During recomposition, Compose walks the slot table linearly. When it encounters a `key()` call, it looks ahead in the table for a group with a matching key. If found, it jumps to that group (preserving its slots). If not found, it creates a new group. Groups with keys that are no longer present are garbage-collected.

**Critical detail:** `key()` uses `equals()` and `hashCode()` for matching. This is why SkipUI's `SwiftHashable` problem is so pernicious -- `SwiftHashable.equals()` calls through JNI to Swift, but Compose's internal comparison happens on the Kotlin/JVM side. If `equals()` is unreliable or slow, Compose's key matching degrades silently.

### What SkipUI Can Learn

- **Compose's `key()` is the only extension point for explicit identity.** There is no way to register a custom identity resolver or override the slot table's matching algorithm. SkipUI must work within this constraint -- keys must be Kotlin-native types with reliable `equals()`/`hashCode()`.
- **Compose has no equivalent of Flutter's GlobalKey.** Identity is always scoped to the parent group. Cross-subtree identity preservation is not supported. This constrains what SkipUI can achieve for features like matched geometry effects.
- **`remember(key)` is the mechanism for input-dependent caching.** SkipUI's transpiler already uses this correctly for `Swift_inputsHash`. This pattern is idiomatic Compose.

---

## 4. Web Frameworks

### The Universal `key` Attribute

Every major web framework uses a `key` attribute for list rendering identity:

| Framework | Syntax | Scope | Default |
|-----------|--------|-------|---------|
| React | `key={id}` prop | Per sibling group | Index (with warning) |
| Vue | `:key="id"` directive | Per `v-for` loop | Index |
| Svelte | `{#each items as item (item.id)}` | Per `{#each}` block | Index |
| Angular | `trackBy: trackById` | Per `*ngFor` directive | Object reference |
| SolidJS | `<For each={items}>` with `key` | Per `<For>` component | Inferred from data |

**Conventions that have emerged:**

1. **Keys should be stable, unique identifiers from the data model.** Database IDs, UUIDs, or natural keys. Never array indices (unless the list is truly static).
2. **Keys are strings or numbers.** No framework uses complex objects as keys. This is partly a performance optimization (fast equality) and partly a simplicity constraint.
3. **Missing keys trigger development warnings** (React, Vue). This is a strong convention -- frameworks consider unkeyed dynamic lists a bug.
4. **Keys are local to the iteration scope.** No framework requires globally unique keys for list items.

### Conditional Rendering Identity

Web frameworks handle conditional rendering differently:

- **React:** `{condition ? <A /> : <B />}` at the same position. If `A` and `B` are different component types, React unmounts one and mounts the other (state reset). If same type, React reuses the instance (state preserved). Developers use `key` to force reset: `{condition ? <Input key="a" /> : <Input key="b" />}`.
- **Vue:** `v-if`/`v-else` with same component type preserves state by default. Developers add `:key` to force reset. Vue 3 added automatic key injection for `v-if`/`v-else` chains.
- **Svelte:** `{#if}`/`{:else}` always destroys and recreates. No state preservation across branches (simpler model).

**Lesson for SkipUI:** SwiftUI's `_ConditionalContent` approach (distinct structural identity per branch) most closely resembles Svelte's model -- each branch is a fresh view. The audit identifies that SkipUI does not implement this, relying instead on Compose's positional matching. This means SkipUI's conditional rendering is closer to React's default behavior (type-based matching) than to SwiftUI's (branch-based destruction). This is a semantic gap.

---

## 5. Synthesised Patterns

### What Is Universal

| Pattern | React | Flutter | Compose | Web | SwiftUI |
|---------|-------|---------|---------|-----|---------|
| Explicit keys for lists | Yes (`key`) | Yes (`Key`) | Yes (`key()`) | Yes (`:key`) | Yes (via `ForEach(id:)`) |
| Positional identity as default | Yes | Yes | Yes | Yes | Yes (structural) |
| Keys are simple types (string/int) | Yes | No (typed `Key`) | Yes (any with `equals`) | Yes | No (`Hashable`) |
| Key scope is per-sibling-group | Yes | Yes | Yes | Yes | Yes |
| Type + position = structural identity | Yes | Yes | Yes | Yes | Yes (type + position in ViewBuilder) |
| Conditional branches get distinct identity | Partial | Yes (different types) | No (positional) | Varies | Yes (`_ConditionalContent`) |

**Explicit keying is always needed for dynamic lists.** This is not a SwiftUI-specific pattern -- it is universal across all frameworks. Every framework that has tried index-based list identity has eventually added explicit keying.

**Structural identity (type + position) is universal, not SwiftUI-specific.** Every framework uses it as the default. SwiftUI's contribution is making it more explicit through `@ViewBuilder` and `_ConditionalContent`, but the underlying principle exists everywhere.

**All frameworks separate "list item identity" from "component selection/binding."** React's `key` is not the same as a `value` prop. Flutter's `Key` is not the same as a widget's configuration. SwiftUI conflates `.tag()` for both selection and identity -- and the audit correctly identifies this as a design problem.

### What Is Unique to SkipUI

1. **Two independent identity systems running simultaneously.** No other framework faces this. React Native avoids it by making the native side stateless. Flutter avoids it by owning the entire pipeline. Compose Multiplatform avoids it by using the same runtime everywhere. SkipUI is the only framework that must inject identity from Framework A (SwiftUI) into Framework B (Compose) where Framework B has its own opinions about identity.

2. **Cross-language key comparison.** The SwiftHashable/JNI equality problem is unique to SkipUI. No other framework bridges key equality across a language boundary at runtime. React Native's `reactTag` is a plain integer. Flutter's keys never cross a language boundary.

3. **Transpiler-generated identity.** SkipUI's transpiler generates Kotlin code from Swift source. This is an opportunity no other framework has -- the transpiler can inject identity information at compile time that would be impossible to add at runtime.

---

## 6. Proposed Approach for SkipUI

### The Proven Industry Pattern

Every successful framework converges on the same model:

1. **A single, authoritative identity for each component instance**, derived from either position (structural) or an explicit key (data-driven).
2. **Keys are simple, comparable values** (strings, integers) that work natively in the target runtime.
3. **Identity is assigned at the data layer**, not at the rendering layer. React's `key` comes from the data. Flutter's `Key` comes from the data. ForEach's `id` keypath comes from the data.
4. **Identity and selection/binding are separate concerns.** No framework uses the same mechanism for "which item is this in the list" and "which item is selected."

### Where SkipUI's Problem Is Common vs Unique

| Aspect | Common Pattern | SkipUI's Unique Challenge |
|--------|---------------|--------------------------|
| List identity via keys | Universal | Keys must cross Swift -> Kotlin boundary |
| Structural identity via position | Universal | Two slot tables (SwiftUI conceptual + Compose actual) |
| Key normalization to simple types | Universal | SwiftHashable JNI equality is unreliable |
| Identity != selection | Universal | `.tag()` conflation must be unwound |
| Conditional branch identity | Common but varied | SwiftUI's `_ConditionalContent` has no Compose equivalent |
| Compile-time identity injection | Unique opportunity | Transpiler can generate structural IDs |

### A Framework-Agnostic Identity Bridge

Drawing from cross-framework patterns, here is what SkipUI's identity layer should look like:

**Principle 1: Single point of identity assignment.**
Identity should be set exactly once, during the Evaluate phase (when SwiftUI's identity is known), and consumed exactly once, during the Render phase (when Compose needs it). This mirrors React's model where `key` is set in JSX and consumed by the reconciler.

**Principle 2: Three distinct identity channels** (aligning with Codex's three-field model from the audit):

| Channel | Purpose | Analogue |
|---------|---------|----------|
| `identityKey: String?` | Sibling disambiguation in container loops | React `key`, Flutter `ValueKey`, Compose `key()` |
| `explicitID: String?` | State destruction on value change (`.id()`) | React `key` for reset, Flutter `UniqueKey` |
| `selectionTag: Any?` | Picker/TabView binding value | React `value` prop, HTML `value` attribute |

Note that `identityKey` and `explicitID` are `String`, not `Any`. This is deliberate -- following the web convention that keys are simple comparable types. The `composeKeyValue()` normalization happens at assignment time, not at consumption time. This eliminates the three-normalization-path problem.

**Principle 3: Transpiler-injected structural identity.**
Gemini's proposal for `__structuralID` from AST location is supported by cross-framework analysis. SwiftUI's `_ConditionalContent` is essentially compile-time branch tagging. The transpiler can generate equivalent branch identifiers, giving Compose the information it needs to distinguish `if/else` branches without relying on positional matching. This is unique to SkipUI's architecture and should be exploited.

**Principle 4: Fail-safe defaults with development warnings.**
Following React's convention, when a container iterates renderables without explicit keys, SkipUI should:
- Fall back to index-based identity (current behavior, pragmatically correct).
- Emit a development-mode warning (like React's "Each child in a list should have a unique key prop").
- Never fall back to SwiftHashable-based comparison.

### Concrete Recommendation

The audit's Phase 3 (architectural refactor) is well-aligned with cross-framework patterns. The specific ordering I would recommend, informed by industry precedent:

1. **Separate `.tag()` from identity immediately.** Every framework treats selection and identity as orthogonal. This is the highest-leverage architectural change because it unblocks clean reasoning about all other identity concerns.

2. **Normalize keys to String at assignment time.** Do not pass `Any` through the system. React, Vue, Svelte, and Angular all use string/number keys. SkipUI should normalize to `String` (or `Int` for integer-keyed collections) at the point where `ForEach` sets identity, not at the point where `VStack` consumes it.

3. **Add `identityKey` to `Renderable` as a protocol property.** This is the Flutter Element analogy -- a dedicated identity channel that every container can read uniformly. The audit's Phase 3a.

4. **Fix all container iteration loops to read `identityKey`.** With a single, pre-normalized key on every renderable, this becomes mechanical. The audit's Phase 3d, but dramatically simpler because normalization is already done.

5. **Investigate transpiler structural IDs last.** This is the most ambitious change and the one with the least cross-framework precedent (since no other framework has a transpiler in the loop). It addresses the conditional rendering gap, which is real but lower priority than list identity.

### What Not to Do

- **Do not introduce GlobalKey.** SwiftUI does not have cross-subtree identity, and adding it would create semantics that diverge from SwiftUI's model. Compose does not support it either.
- **Do not try to make SwiftHashable work with Compose's key comparison.** The JNI boundary makes this fundamentally unreliable. The industry pattern is clear: keys are simple types. Normalize early, compare natively.
- **Do not add development warnings before fixing the architecture.** Warnings about missing keys are useful only when the framework provides a reliable mechanism to supply them. Fix the `identityKey` channel first, then warn about its absence.

---

## Summary

| Framework | Identity Model | Bridge Challenge | Key Insight for SkipUI |
|-----------|---------------|-----------------|----------------------|
| React Native | JS reconciler is sole authority; native side is stateless | Avoided entirely | One side must be authoritative |
| Flutter | Widget type + Key -> Element identity | No bridge (single pipeline) | Separate identity from configuration |
| Compose Multiplatform | Same slot table everywhere | No bridge (same runtime) | No precedent for wrapping Compose identity |
| React (Web) | Type + position + `key` prop | N/A | Keys are simple types; normalize early |
| Vue/Svelte/Angular | Similar to React with minor variations | N/A | Selection and identity are always separate |

SkipUI's problem is genuinely harder than any of these because it must inject external identity into Compose's slot table. But the solution patterns are well-established: simple keys, single normalization point, identity separate from selection, and one authoritative source of identity truth. The transpiler is SkipUI's unique advantage -- it can generate the identity information that other frameworks require developers to provide manually.
