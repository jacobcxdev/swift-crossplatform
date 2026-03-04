# Position Paper: Renderable Protocol Identity Design

> **Author:** Protocol / Type System Designer
> **Date:** 2026-03-01
> **Status:** Proposal
> **Scope:** `Renderable` protocol surface, identity propagation through modifier chains, key normalisation

---

## 1. Audit of the Current Renderable Protocol

### 1.1 Existing Protocol Surface

The `Renderable` protocol (defined in `Renderable.swift`) has a minimal core:

```swift
public protocol Renderable {
    @Composable func Render(context: ComposeContext)
}
```

Extensions on `Renderable` (under `#if SKIP`) add:

| Member | Kind | Purpose |
|--------|------|---------|
| `shouldRenderListItem(context:)` | Method | Lazy list specialisation check |
| `RenderListItem(context:modifiers:)` | Method | Lazy list item rendering |
| `isSwiftUIEmptyView` | Computed property | Checks if stripped content is `EmptyView` |
| `strip()` | Method | Unwraps `ModifiedContent` wrappers |
| `forEachModifier(perform:)` | Method | Walks modifier chain, returns first non-nil result |
| `composeKey` | Computed property | Reads `.tag` modifier value, normalises via `composeKeyValue()` |
| `asView()` | Method | Wraps as `ComposeView` if not already a `View` |

The identity-relevant surface is exactly one property: `composeKey`. It is computed by walking the modifier chain looking for a `TagModifier` with role `.tag`, then normalising its value through `composeKeyValue()`.

### 1.2 What Is Missing

**No separation of concerns.** The single `composeKey` property conflates three semantically distinct concepts:

1. **Selection tags** (`.tag()` for `Picker`/`TabView` binding) -- a value that identifies which option the user selected.
2. **Explicit identity** (`.id()` for state destruction) -- a value that, when changed, destroys and recreates view state.
3. **Structural identity** (ForEach item keys) -- a value that Compose uses to match items across list mutations.

All three currently flow through `TagModifier`, but only structural identity should produce a Compose `key()`. Selection tags should be read by selection containers without affecting composition structure. Explicit identity (`.id()`) should trigger state saver reset without necessarily being used as a sibling key.

**No identity propagation contract.** `ModifiedContent`, `LazyLevelRenderable`, `ComposeView`, `LazySectionHeader`, and `LazySectionFooter` all wrap renderables, but only `ModifiedContent` and `LazyLevelRenderable` forward `forEachModifier`. `ComposeView` does not -- it captures a closure, so the modifier chain is severed. This means `composeKey` (which relies on `forEachModifier` to find `TagModifier`) returns `nil` for any renderable wrapped in a `ComposeView`.

### 1.3 How Modifiers Propagate Through ModifiedContent

`ModifiedContent` is the universal wrapper. Its identity-relevant behaviour:

```
ModifiedContent(content: renderable, modifier: tagModifier)
    .composeKey          -- walks: tagModifier -> renderable's modifiers
    .strip()             -- delegates to renderable.strip()
    .forEachModifier(f)  -- tries f(modifier), then renderable.forEachModifier(f)
```

This means `composeKey` on a `ModifiedContent` finds the *outermost* matching `TagModifier` with role `.tag`. The traversal is depth-first through the modifier chain. This is correct for single-tag scenarios but provides no mechanism for an identity property that should take precedence over tags.

### 1.4 Key Normalisation Inconsistency

Three separate normalisation paths exist today:

| Function | Location | Input | Output | Used by |
|----------|----------|-------|--------|---------|
| `composeKeyValue(_:)` | Renderable.swift | `Any` | `String\|Int\|Long` | `composeKey`, `TagModifier.Render` (`.tag` role) |
| `composeBundleString(for:)` | ComposeStateSaver.swift | `Any?` | `String` | Lazy item keys in `List`, `LazyVStack`, etc. |
| Raw `Any` passthrough | AdditionalViewModifiers.swift:1413,1426 | `Any?` | `Any?` | `TagModifier` `.id` role |

`composeKeyValue` strips `Optional(...)` wrappers via string manipulation. `composeBundleString` uses `Identifiable.id` or `RawRepresentable.rawValue` unwrapping. The `.id` role uses raw values with no normalisation at all. These three paths can produce different keys for the same logical value.

---

## 2. Proposed Identity Model

### 2.1 Design Principles

1. **Separate concerns into distinct properties.** Selection, explicit identity, and structural identity are different things and must not share a single field.
2. **Identity is a protocol requirement with defaults, not a separate wrapper type.** Adding an `IdentifiedRenderable` wrapper creates yet another layer in the wrapping chain. Protocol defaults (`nil`) keep the common case zero-cost.
3. **One normalisation function, called at the producer.** Normalise once when setting the value, not at every consumer. Consumers receive Compose-safe values and use them directly.
4. **Propagation through wrappers is explicit.** Every type that wraps a `Renderable` must forward identity properties. The compiler cannot enforce this, but the protocol documentation and a small number of wrapper types make it tractable.
5. **Containers consume `identityKey`; selection containers consume `selectionTag`; `.id()` stands alone.** No container needs to inspect all three.

### 2.2 The Three Fields

```swift
extension Renderable {
    /// Structural identity key for sibling disambiguation in Compose.
    /// Set by ForEach during Evaluate. Consumed by VStack, HStack, ZStack,
    /// and all other containers that iterate renderables in a loop.
    /// Value MUST be Compose-safe (String, Int, Long) -- normalised at the producer.
    /// Default: nil (container falls back to positional index).
    public var identityKey: Any? { nil }

    /// Selection tag for Picker/TabView binding.
    /// Set by .tag() modifier. Read by selection containers to match
    /// against the bound selection value. Never used as a Compose key().
    /// Retains the original Swift value (no normalisation needed --
    /// comparison is done in Swift, not by Compose).
    /// Default: nil.
    public var selectionTag: Any? { nil }

    /// Explicit identity for state destruction semantics.
    /// Set by .id() modifier. When this value changes between
    /// recompositions, the view's state saver is reset and all
    /// remembered values are discarded.
    /// Retains the original Swift value.
    /// Default: nil.
    public var explicitID: Any? { nil }
}
```

### 2.3 Why Not a Single `structuralID`?

A single `structuralID: Any?` field (as proposed in the audit report) would still conflate selection tags with identity. Picker reads `.tag` to match the bound selection value. If we merge tag into structuralID, Picker must distinguish "this is a ForEach identity key" from "this is a user-supplied selection tag." The three-field model eliminates this ambiguity at the type level.

### 2.4 Why Not an `IdentifiedRenderable` Wrapper?

An `IdentifiedRenderable(content: renderable, identityKey: key)` wrapper is tempting but problematic:

- It adds another layer to `strip()` / `forEachModifier` traversal.
- It interacts poorly with `ModifiedContent` ordering: should modifiers wrap `IdentifiedRenderable` or vice versa?
- `LazyLevelRenderable` already wraps renderables -- nesting wrappers creates `LazyLevelRenderable(IdentifiedRenderable(ModifiedContent(...)))`.

Instead, storing identity directly on the renderable (via `ModifiedContent` with a new `IdentityModifier`) keeps the wrapper chain flat.

---

## 3. Concrete Protocol Definition

### 3.1 Updated Renderable Protocol

```swift
/// Renders content via Compose.
public protocol Renderable {
    #if SKIP
    @Composable func Render(context: ComposeContext)
    #endif
}

#if SKIP
extension Renderable {
    // --- Existing members (unchanged) ---
    @Composable public func shouldRenderListItem(context: ComposeContext) -> (Bool, (() -> Void)?) { (false, nil) }
    @Composable public func RenderListItem(context: ComposeContext, modifiers: kotlin.collections.List<ModifierProtocol>) { }
    public final var isSwiftUIEmptyView: Bool { strip() is EmptyView }
    public func strip() -> Renderable { self }
    public func forEachModifier<R>(perform action: (ModifierProtocol) -> R?) -> R? { nil }
    public func asView() -> View { self as? View ?? ComposeView(content: { self.Render($0) }) }

    // --- New: Identity Properties ---

    /// Structural identity key for container sibling loops.
    /// Compose-safe (String | Int | Long). Normalised at the producer.
    public var identityKey: Any? {
        forEachModifier { modifier in
            (modifier as? IdentityKeyModifier)?.normalizedKey
        }
    }

    /// Selection tag for Picker/TabView.
    /// Raw Swift value -- compared in Swift, not by Compose.
    public var selectionTag: Any? {
        TagModifier.on(content: self, role: .tag)?.value
    }

    /// Explicit ID for state destruction (.id() modifier).
    /// Raw Swift value.
    public var explicitID: Any? {
        TagModifier.on(content: self, role: .id)?.value
    }

    // --- Deprecated ---

    /// Replaced by `identityKey`. Retained temporarily for migration.
    @available(*, deprecated, renamed: "identityKey")
    public var composeKey: Any? { identityKey }
}
#endif
```

### 3.2 IdentityKeyModifier

A new, lightweight modifier type that carries only the normalised identity key:

```swift
#if SKIP
/// Carries a normalised structural identity key through the modifier chain.
/// Produced by ForEach during Evaluate. Consumed by container render loops.
final class IdentityKeyModifier: ModifierProtocol {
    let role: ModifierRole = .unspecified
    let normalizedKey: Any  // Always String | Int | Long

    init(key: Any) {
        self.normalizedKey = normalizeKey(key)
    }

    @Composable func Evaluate(content: View, context: ComposeContext, options: Int)
        -> kotlin.collections.List<Renderable>? { nil }

    @Composable func Render(content: Renderable, context: ComposeContext) {
        // Identity is consumed by the CONTAINER, not by this modifier.
        // This modifier is transparent during rendering.
        content.Render(context: context)
    }
}
#endif
```

### 3.3 Unified Key Normalisation

One function replaces both `composeKeyValue` and `composeBundleString`:

```swift
#if SKIP
/// Normalise a Swift value into a Compose-safe key.
///
/// Compose's `key()` uses Kotlin structural equality for matching.
/// SwiftHashable wrappers use JNI-based equality that is incompatible
/// with Compose's internal comparison. This function converts to
/// Kotlin-native types that Compose can compare reliably.
///
/// Called ONCE at the producer (ForEach, lazy item factory).
/// Consumers use the normalised value directly.
public func normalizeKey(_ raw: Any) -> Any {
    // Fast path: already Compose-safe
    if raw is String || raw is Int || raw is Long {
        return raw
    }
    // Structural unwrap for Optional
    if let optional = raw as? AnyOptionalProtocol {
        guard let unwrapped = optional.unwrappedValue else {
            return "__nil__"
        }
        return normalizeKey(unwrapped)
    }
    // Identifiable: use .id for stable identity
    if let identifiable = raw as? Identifiable<AnyHashable> {
        return normalizeKey(identifiable.id)
    }
    // RawRepresentable: use .rawValue (enums)
    if let rawRepr = raw as? RawRepresentable<AnyHashable> {
        return normalizeKey(rawRepr.rawValue)
    }
    // Fallback: string representation
    return "\(raw)"
}

/// Protocol for structural Optional unwrapping.
/// Avoids string-based "Optional(...)" stripping.
fileprivate protocol AnyOptionalProtocol {
    var unwrappedValue: Any? { get }
}
extension Optional: AnyOptionalProtocol {
    var unwrappedValue: Any? {
        switch self {
        case .some(let wrapped):
            // Recursively unwrap nested Optionals
            if let nested = wrapped as? AnyOptionalProtocol {
                return nested.unwrappedValue
            }
            return wrapped
        case .none:
            return nil
        }
    }
}
#endif
```

**Note on Kotlin compatibility:** On Android, Swift `Optional<T>` is erased to Kotlin nullable `T?`. The `AnyOptionalProtocol` conformance may not survive transpilation. If not, the fallback `"\(raw)"` path handles it, and the string-based `Optional(...)` stripping can be retained as a secondary guard within the `"\(raw)"` branch. The key improvement is that this is a *single* function called at *one* site, not three separate normalisers scattered across the codebase.

---

## 4. Producer and Consumer Interactions

### 4.1 ForEach (Producer)

ForEach sets `identityKey` during Evaluate via `IdentityKeyModifier` instead of `TagModifier`:

```swift
// In ForEach.swift — replaces taggedRenderable(for:defaultTag:)
private func identifiedRenderable(for renderable: Renderable, key: Any?) -> Renderable {
    guard let key else { return renderable }
    // Only add identity if one isn't already present
    if renderable.identityKey != nil { return renderable }
    return ModifiedContent(
        content: renderable,
        modifier: IdentityKeyModifier(key: key)  // normalises internally
    )
}
```

`taggedIteration` becomes `identifiedIteration`, grouping multi-renderable iterations under a single `IdentityKeyModifier` (unchanged logic, different modifier type).

ForEach also sets `selectionTag` when items need to participate in Picker/TabView selection. This is a separate `TagModifier` with role `.tag`, applied only when the caller is a selection context. In the common case (VStack/HStack containing ForEach), no `.tag` modifier is applied -- only `IdentityKeyModifier`.

```swift
// taggedIteration becomes:
private func identifiedIteration(
    renderables: kotlin.collections.List<Renderable>,
    defaultKey: Any?
) -> kotlin.collections.List<Renderable> {
    guard let defaultKey else { return renderables }
    if renderables.size <= 1 {
        return renderables.map { identifiedRenderable(for: $0, key: defaultKey) }
    }
    // Multiple renderables: wrap in a single group
    let grouped = ComposeView(content: { context in
        for renderable in renderables {
            renderable.Render(context: context)
        }
    })
    return listOf(identifiedRenderable(for: grouped, key: defaultKey))
}
```

**Selection context detection:** When ForEach is evaluated inside a Picker or TabView (detectable via `ComposeContext` or `EvaluateOptions`), it *also* applies a `TagModifier` with role `.tag` carrying the raw (un-normalised) value. This preserves the current Picker/TabView selection matching while decoupling it from structural identity.

### 4.2 VStack / HStack / ZStack (Consumers)

All container render loops consume `identityKey`:

```swift
// VStack.swift — non-animated path (representative example)
for i in 0..<renderables.size {
    let renderable = renderables[i]
    let composeKey: Any = renderable.identityKey ?? i  // normalised or index fallback
    let spacingResult = EmitAdaptiveSpacing(...)
    androidx.compose.runtime.key(composeKey) {
        renderable.Render(context: contentContext)
    }
    // spacing bookkeeping...
}
```

The pattern is identical for:
- VStack non-animated (2 layout version paths)
- VStack animated (2 paths -- **currently missing key(), this fixes that**)
- HStack non-animated (2 paths)
- HStack animated (2 paths -- **currently missing key(), this fixes that**)
- ZStack (2 paths -- **currently missing key(), this fixes that**)

A single line change per loop. No normalisation at the consumer -- `identityKey` is already Compose-safe.

### 4.3 TagModifier (Decoupled)

With identity decoupled, `TagModifier` simplifies:

```swift
final class TagModifier: RenderModifier {
    static let defaultIdValue = "<TagModifier.defaultIdValue>"

    let value: Any?
    var stateSaver: ComposeStateSaver?

    init(value: Any?, role: ModifierRole) {
        self.value = value
        super.init(role: role)
    }

    @Composable override func Render(content: Renderable, context: ComposeContext) -> Void {
        if let stateSaver {
            // .id() role: reset state saver, key for state destruction
            var context = context
            context.stateSaver = stateSaver
            let idKey = normalizeKey(value ?? Self.defaultIdValue)
            androidx.compose.runtime.key(idKey) {
                super.Render(content: content, context: context)
            }
        } else {
            // .tag() role: NO key() wrapping.
            // Selection tags are data, not composition structure.
            // The container reads selectionTag when it needs the value.
            super.Render(content: content, context: context)
        }
    }

    // Evaluate unchanged for .id() path (state saver reset logic)
    // ...
}
```

Key change: **TagModifier no longer calls `key()` for the `.tag` role.** This eliminates Layer 3 entirely. The `.tag` role becomes purely a data carrier for selection contexts. The `.id` role retains its `key()` wrapping (for state destruction semantics) but now normalises through `normalizeKey` instead of using raw values.

### 4.4 Lazy Containers (List, LazyVStack, LazyHStack, LazyVGrid, LazyHGrid)

Lazy containers use Compose's native `items(count, key)` API. The `key` lambda reads `identityKey`:

```swift
// In lazy item collector setup:
items(count: range.count, key: { index in
    let renderable = factory(range.start + index, context)
    renderable.identityKey ?? (range.start + index)
}) { index in
    factory(range.start + index, context).Render(context: context)
}
```

This replaces `composeBundleString` with `identityKey` (already normalised). The `composeBundleString` function can be deprecated.

### 4.5 Picker / TabView (Selection Consumers)

These containers read `selectionTag` (not `identityKey`) for matching against the bound selection value:

```swift
// TabView.swift — representative
let tag = renderable.selectionTag
if tag == selection {
    // This tab is selected
}
```

No normalisation needed -- both `selectionTag` and the bound `selection` value are Swift objects compared via Swift equality.

---

## 5. Wrapper Propagation

Every type that wraps a `Renderable` must forward the three identity properties. The key insight is that all three properties are derived from `forEachModifier`, so any wrapper that correctly forwards `forEachModifier` automatically gets correct identity propagation.

### 5.1 ModifiedContent (already correct)

```swift
override func forEachModifier<R>(perform action: (ModifierProtocol) -> R?) -> R? {
    if let ret = action(modifier) { return ret }
    return renderable?.forEachModifier(perform: action)
}
```

`identityKey` calls `forEachModifier` looking for `IdentityKeyModifier`. `selectionTag` calls `TagModifier.on(content:role:)` which uses `forEachModifier`. Both work through `ModifiedContent` without changes.

### 5.2 LazyLevelRenderable (already correct)

```swift
override func forEachModifier<R>(perform action: (ModifierProtocol) -> R?) -> R? {
    content.forEachModifier(perform: action)
}
```

Delegates to wrapped content. Identity flows through.

### 5.3 ComposeView (broken -- needs fix)

`ComposeView` captures a `@Composable` closure. It has no modifier chain and no `forEachModifier` override. This means:

```swift
let grouped = ComposeView(content: { context in ... })
grouped.identityKey  // Always nil!
```

This is the reason `taggedIteration` (now `identifiedIteration`) wraps the `ComposeView` in a `ModifiedContent` with the identity modifier. The identity lives on the `ModifiedContent` layer, not on `ComposeView` itself. This is correct and intentional -- `ComposeView` should remain a simple composable-closure wrapper.

**Invariant:** `ComposeView` must never be the outermost renderable in a keyed context. It must always be wrapped in `ModifiedContent(content: composeView, modifier: IdentityKeyModifier(...))` when identity is needed.

### 5.4 LazySectionHeader / LazySectionFooter (no identity needed)

These types represent structural elements (section boundaries), not user content. They should not carry identity keys. Their current lack of `forEachModifier` forwarding is acceptable, though adding it would be more consistent:

```swift
// Optional improvement for consistency:
override func forEachModifier<R>(perform action: (ModifierProtocol) -> R?) -> R? {
    for renderable in content {
        if let result = renderable.forEachModifier(perform: action) {
            return result
        }
    }
    return nil
}
```

### 5.5 Propagation Summary

| Wrapper | `forEachModifier` | Identity flows? | Action needed |
|---------|-------------------|-----------------|---------------|
| `ModifiedContent` | Forwards through chain | Yes | None |
| `LazyLevelRenderable` | Delegates to content | Yes | None |
| `ComposeView` | Not implemented | No (by design) | Always wrap with `ModifiedContent` when identity needed |
| `LazySectionHeader` | Not implemented | No (acceptable) | Optional: add forwarding |
| `LazySectionFooter` | Not implemented | No (acceptable) | Optional: add forwarding |

---

## 6. The `.tag()` Decoupling in Detail

### 6.1 Current State

Today, `.tag(value)` creates `TagModifier(value: value, role: .tag)`. This single modifier serves two masters:

1. **ForEach identity** -- `composeKey` reads it to produce Compose keys.
2. **Picker/TabView selection** -- the container reads it to match against the bound value.

ForEach's `taggedRenderable` adds a `.tag` modifier as a *default* tag, checking first whether the user already applied one (ForEach.swift:298). This means user-applied `.tag()` for Picker selection collides with ForEach-injected `.tag()` for identity.

### 6.2 Proposed State

After decoupling:

- **ForEach identity** uses `IdentityKeyModifier` (new type). Never collides with `.tag()`.
- **`.tag()` modifier** creates `TagModifier(value: value, role: .tag)` as before, but `TagModifier.Render` no longer calls `key()`. It is purely a data annotation.
- **`.id()` modifier** creates `TagModifier(value: value, role: .id)` as before. `TagModifier.Render` still calls `key()` for `.id` role (state destruction semantics).

### 6.3 Migration Path

The transition can be done in two steps:

**Step 1: Additive.** Add `IdentityKeyModifier`, `identityKey`, `selectionTag`, `explicitID`, and `normalizeKey`. Have ForEach produce *both* `IdentityKeyModifier` and `TagModifier` during transition. Containers read `identityKey` (with fallback to deprecated `composeKey`).

**Step 2: Removal.** Remove `composeKey`. Remove `TagModifier.Render` key() for `.tag` role. ForEach stops producing `TagModifier` for identity (only for selection contexts). Remove `composeKeyValue` and `composeBundleString`.

### 6.4 Duplicate Tag Safety

With identity decoupled from `.tag()`, duplicate `.tag()` values no longer crash Compose. The user can write:

```swift
VStack {
    Text("A").tag(1)
    Text("B").tag(1)
}
```

Both views get `identityKey == nil` (no ForEach), so VStack falls back to positional index `0` and `1`. The duplicate `.tag(1)` values are inert data -- no `key()` call uses them. This matches SwiftUI semantics where duplicate tags are legal outside selection contexts.

---

## 7. Summary of Changes

| Component | Current | Proposed | Risk |
|-----------|---------|----------|------|
| `Renderable` protocol | `composeKey` (1 field) | `identityKey`, `selectionTag`, `explicitID` (3 fields) | Low -- additive, defaults to nil |
| Key normalisation | 3 functions | 1 function (`normalizeKey`) | Medium -- behavioural change for edge cases |
| `IdentityKeyModifier` | Does not exist | New modifier type | Low -- transparent render pass-through |
| ForEach | Produces `TagModifier(.tag)` | Produces `IdentityKeyModifier` | Medium -- changes Evaluate output |
| TagModifier.Render | `key()` for both `.tag` and `.id` | `key()` for `.id` only | Medium -- removes Layer 3 |
| Container loops | `renderable.composeKey ?? i` | `renderable.identityKey ?? i` | Low -- rename |
| Lazy items | `composeBundleString` | `identityKey` | Low -- already normalised |
| Picker/TabView | Reads `.tag` modifier | Reads `selectionTag` | Low -- same underlying value |

### Files Modified

1. **Renderable.swift** -- new properties, `normalizeKey`, deprecate `composeKey`/`composeKeyValue`
2. **ModifiedContent.swift** -- add `IdentityKeyModifier` class (or new file)
3. **ForEach.swift** -- `taggedRenderable` -> `identifiedRenderable`, `taggedIteration` -> `identifiedIteration`
4. **AdditionalViewModifiers.swift** -- simplify `TagModifier.Render`, normalise `.id` values
5. **VStack.swift** -- `composeKey` -> `identityKey` (4 loop sites, including animated paths)
6. **HStack.swift** -- same (4 loop sites)
7. **ZStack.swift** -- add `identityKey` keying (2 loop sites, currently missing)
8. **LazyVStack.swift, LazyHStack.swift, LazyVGrid.swift, LazyHGrid.swift, List.swift** -- replace `composeBundleString` with `identityKey`
9. **TabView.swift** -- read `selectionTag` instead of raw `.tag` value
10. **Picker.swift** -- read `selectionTag`
11. **ComposeStateSaver.swift** -- deprecate `composeBundleString`

---

## 8. Design Decisions and Tradeoffs

### Why properties on the extension, not protocol requirements?

Making `identityKey`, `selectionTag`, and `explicitID` protocol requirements would force every `Renderable` conformer (44+ types) to implement them. Since the default behaviour (returning `nil` or walking `forEachModifier`) is correct for all types, extension-provided defaults are the right choice. Only `ModifiedContent` needs custom behaviour, and it already gets it through `forEachModifier`.

### Why normalise at the producer, not the consumer?

Normalising at every consumer (the current approach with `composeKeyValue` in VStack, `composeBundleString` in List, raw in `.id`) is the root cause of the inconsistency bugs. Normalising once when the key is created (`IdentityKeyModifier.init` or `normalizeKey`) guarantees consistency. The cost is that `normalizeKey` runs even if no container ever reads the key, but this cost is negligible compared to the Compose recomposition overhead.

### Why not inject identity from the transpiler?

Gemini's proposal to inject `__structuralID` from AST location addresses a different problem: ViewBuilder conditional identity (`if/else` branch disambiguation). That problem is real but orthogonal to the ForEach/container identity problem addressed here. The two solutions are complementary: `__structuralID` provides *static* structural identity from source location, while `identityKey` provides *dynamic* structural identity from data identity. Both can coexist -- `__structuralID` would become a fourth property on `Renderable` if implemented, independent of the three proposed here.

### Why keep `TagModifier` at all?

`TagModifier` still serves two legitimate purposes: (1) carrying `.id` role values for state destruction, and (2) carrying `.tag` role values for Picker/TabView selection. Only its `key()` wrapping for `.tag` role is removed. The class itself remains, simplified.
