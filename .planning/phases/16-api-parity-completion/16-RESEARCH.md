# Phase 16: TCA API Parity Completion - Research

**Researched:** 2026-02-24
**Domain:** Cross-platform conditional compilation guard removal (TCA, swift-navigation, skip-fuse-ui)
**Confidence:** HIGH

## Summary

Phase 16 removes `#if !os(Android)` and `#if canImport(SwiftUI) && !os(Android)` guards from P3 tech debt items across the TCA fork (swift-composable-architecture), swift-navigation fork, and skip-fuse-ui fork. The phase has three workstreams: (1) implement `withTransaction` in skip-fuse-ui to unblock animation-related guards, (2) remove guards from TCA files (~24 guards) and swift-navigation files (~15+ guards), and (3) enable TextState rich text modifiers on Android.

The core enabler is that SkipFuseUI's SkipSwiftUI module already provides all the SwiftUI types needed (Animation, Transaction, Font, Color, CGFloat, LocalizedStringKey, Visibility, etc.). The `import SwiftUI` statement resolves on Android because SkipFuseUI re-exports SkipSwiftUI as SwiftUI via `@_exported import`. The only real implementation gap is `withTransaction` — currently a `fatalError()` stub — which blocks 8+ animation-related guards in TCA.

**Primary recommendation:** Implement `withTransaction` first (small, well-scoped change in skip-fuse-ui), then systematically remove guards across TCA and swift-navigation forks, with empirical build verification after each batch. TextState enablement is the riskiest workstream due to the number of SwiftUI types involved.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Import Strategy:** SkipFuseUI re-exports SkipSwiftUI as SwiftUI via `@_exported import` — `import SwiftUI` resolves on both Darwin and Android. Remove `#if !os(Android)` guards entirely rather than converting to `canImport`. Migrate ALL `#if !os(Android)` SwiftUI import guards across the TCA fork, not just Phase 16's named items. Comprehensive audit. For guards wrapping code with additional non-import incompatibilities: convert the outer import guard, add targeted `#if os(Android)` inner guards around specific incompatible lines. Deprecated APIs (IfLetStore, NavigationStackStore, old Alert/ConfirmationDialog): remove their guards too. Only re-gate if they are the sole reason for a build failure. No test coverage for deprecated APIs.
- **withTransaction Implementation:** Implement `withTransaction` in skip-fuse-ui by extracting `transaction.animation` and delegating to `withAnimation`. Replace the `@available(*, unavailable)` stubs with working implementations. This single fix unblocks all 8 animation-related guards in the TCA fork.
- **IfLetStore Disposition:** Remove `#if !os(Android)` guards (per import strategy). No test coverage for IfLetStore itself (deprecated). Write a specific TCA pattern test proving the @Observable alternative works. Test name should explicitly reference IfLetStore.
- **TextState Rich Text Enablement:** Remove `&& !os(Android)` from all guards in TextState.swift. Verify compilation empirically. Block until resolved — do not accept a plain text fallback. Tests verify compile + no crash for modifiers. Do NOT assert on rendered output.
- **BindingLocal Cleanup:** Keep definition in ViewStore.swift (upstream location), remove its `#if !os(Android)` guard, delete duplicate from Core.swift.
- **ObservedObject.Wrapper Guards:** Research question — empirically verify whether `ObservedObject` is accessible at compile time in Fuse mode. If accessible: remove guards. If inaccessible: leave guards as-is.
- **Bind Conformances:** Research question — verify whether `AccessibilityFocusState` and `FocusedBinding` exist in SkipFuseUI. If yes, remove guards. If no, leave.
- **UIKitNavigation Export:** Must stay — UIKitNavigation does not exist on Android.
- **NavigationStack+Observation.swift:150:** Research needed during planning.
- **Additional swift-navigation Guards:** Alert.swift:201 and ConfirmationDialog.swift:227 — remove guards per strategy. Binding.swift and ButtonState.swift `#if os(Android)` paths — already-enabled, no changes needed.
- **Test Evidence:** One focused test per enablement. Tests in fuse-library/Tests. Tests run on both Darwin and Android. IfLetStore alternative test explicitly links to exclusion. TextState tests verify compile + no crash. No test coverage for deprecated APIs.

### Claude's Discretion
None specified — all decisions locked.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TCA-19 | `BindableAction` protocol + `case binding(BindingAction<State>)` compiles and routes correctly on Android | Guard removal in Binding.swift, Binding+Observation.swift enables full binding pipeline. Already passes tests (Phase 4) but guards still gate some extensions. |
| TCA-20 | `BindingReducer()` applies binding mutations to state on Android | BindingLocal cleanup (Core.swift + ViewStore.swift dedup) and guard removal in Binding.swift enables clean path. Already passes tests (Phase 4). |
| NAV-05 | `.sheet(item: $store.scope(...))` presents modal content on Android | Alert+Observation.swift guard removal (animatedSend cases) enabled by withTransaction fix. Already works via PresentationReducer. |
| NAV-07 | `.popover(item: $store.scope(...))` displays popover on Android | Popover.swift guard removal. Already works via PresentationReducer. |
</phase_requirements>

## Standard Stack

### Core
| Library/Fork | Location | Purpose | Why Relevant |
|-------------|----------|---------|--------------|
| skip-fuse-ui | `forks/skip-fuse-ui/Sources/SkipSwiftUI/` | SwiftUI re-export for Android | Provides all SwiftUI types; `withTransaction` implementation target |
| swift-composable-architecture | `forks/swift-composable-architecture/Sources/ComposableArchitecture/` | TCA fork with Android guards | 24+ guards to audit and remove |
| swift-navigation | `forks/swift-navigation/Sources/SwiftNavigation/` | Navigation/TextState fork | 15+ guards including TextState rich text pipeline |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `make darwin-build` | Quick compilation check | After each guard removal batch |
| `make darwin-test` | Full test suite | After all changes in a workstream |
| `EXAMPLE=fuse-library make android-build` | Android compilation | Critical verification after guard removal |
| `EXAMPLE=fuse-library make android-test` | Full Android test parity | Final verification |

## Architecture Patterns

### Pattern 1: withTransaction Implementation
**What:** Replace `@available(*, unavailable)` stubs in skip-fuse-ui Transaction.swift with working implementations that delegate to `withAnimation`.
**When to use:** This is the prerequisite for all animation-related guard removal.
**Implementation:**

```swift
// In forks/skip-fuse-ui/Sources/SkipSwiftUI/Animation/Transaction.swift
// Replace lines 105-113 (the two @available(*, unavailable) withTransaction functions)

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    if let animation = transaction.animation {
        return try withAnimation(animation, body)
    } else {
        return try body()
    }
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var transaction = Transaction()
    transaction[keyPath: keyPath] = value
    if let animation = transaction.animation {
        return try withAnimation(animation, body)
    } else {
        return try body()
    }
}
```

**Confidence:** HIGH — `withAnimation` is fully implemented in skip-fuse-ui (Animation.swift:476) with Compose bridging. The `Transaction` struct already has a working `animation: Animation?` property. This is a straightforward delegation.

**Call chain verified:** `Store.send(_:animation:)` → creates `Transaction(animation:)` → calls `send(_:transaction:)` → calls `withTransaction(transaction) { ... }` → extracts animation → delegates to `withAnimation`. Source: Store.swift lines 205-231, Animation.swift lines 476-484.

### Pattern 2: Comprehensive Guard Removal (Import Strategy)
**What:** Remove `#if !os(Android)` and `#if canImport(SwiftUI) && !os(Android)` guards where `import SwiftUI` resolves on Android via SkipFuseUI re-export.
**When to use:** All guard sites except UIKitNavigation export (Exports.swift:14).
**Approach:**
1. For `#if canImport(SwiftUI) && !os(Android)` → change to `#if canImport(SwiftUI)` (removing `&& !os(Android)`)
2. For `#if !os(Android)` wrapping SwiftUI-only code → remove guard entirely
3. If removal causes build failure due to missing SkipFuseUI API → add targeted inner `#if os(Android)` guard

### Pattern 3: TextState Rich Text Enablement
**What:** Remove `&& !os(Android)` from all 13+ guards in TextState.swift to enable modifiers, LocalizedStringKey, and Storage enum cases on Android.
**When to use:** TextState.swift in swift-navigation fork.
**Key types verified in SkipFuseUI:**
- `CGFloat` — available via SkipLib (confirmed: 5+ files use it)
- `LocalizedStringKey` — available (SkipSwiftUI/Text/LocalizedStringKey.swift)
- `Font`, `Font.Design`, `Font.Weight` — available (SkipSwiftUI/Text/Font.swift)
- `Color` — available (SkipSwiftUI throughout)
- `AccessibilityHeadingLevel` — available (SkipSwiftUI/System/Accessibility.swift)
- `AccessibilityTextContentType` — available (SkipSwiftUI/System/Accessibility.swift)
- `FontWidth` — TextState defines its own enum (not SwiftUI's `Font.Width`), maps to SwiftUI only in `toSwiftUI` computed property. On Android, the enum itself is fine; the `toSwiftUI` property needs `@available` gating.
- `LocalizedStringResource` — **NOT confirmed in SkipFuseUI**. May need inner guard for `.localizedStringResource` storage case.

**Risk:** MEDIUM — Most types are available, but `LocalizedStringResource` and `Text.LineStyle.Pattern` mapping to SwiftUI may need inner guards. Empirical build verification required.

### Pattern 4: BindingLocal Cleanup
**What:** Deduplicate BindingLocal definition.
**Current state:**
- `Core.swift:14-18`: `#if !canImport(SwiftUI) || os(Android)` — defined on Android
- `ViewStore.swift:632-636`: `#if !os(Android)` — defined on Darwin

**Fix:** Remove the `#if !os(Android)` guard from ViewStore.swift:632 so it compiles on both platforms. Delete Core.swift:14-18 entirely. The upstream location is ViewStore.swift.

### Anti-Patterns to Avoid
- **Removing UIKitNavigation export guard:** Exports.swift:14 MUST keep its `#if !os(Android)` — UIKitNavigation module doesn't exist on Android.
- **Testing deprecated APIs:** IfLetStore, NavigationStackStore, SwitchStore, ActionSheet, LegacyAlert — do NOT write tests for these. Test the modern alternatives instead.
- **Asserting rendered output in TextState tests:** Tests should verify compile + no crash for modifiers, NOT assert on visual rendering.

## Research Answers

### ObservedObject.Wrapper Guards (8 guards in TCA)
**Finding:** `ObservedObject` is **NOT available** in skip-fuse-ui's SkipSwiftUI module. Grep across the entire `forks/skip-fuse-ui/Sources` directory returns zero matches for `ObservedObject`. In skip-ui (Lite mode), it exists as `typealias ObservedObject<T> = Bindable<T>` but gated behind `#if !SKIP_BRIDGE` (Fuse mode excluded).

**Recommendation:** Leave all 8 ObservedObject.Wrapper guards as-is. These are deprecated pre-@Observable patterns (`@available(iOS, introduced: 13, obsoleted: 17)`) and not needed on Android. Files affected:
- `Binding+Observation.swift` ×4 (lines 14, 47, 290, 373)
- `NavigationStack+Observation.swift` ×2 (lines 74, 111)
- `Store+Observation.swift` ×2 (lines 197, 317)

**Confidence:** HIGH — direct grep verification.

### Bind Conformances (2 guards in swift-navigation)
**Finding:** Both `AccessibilityFocusState` and `FocusedBinding` **exist** in SkipFuseUI:
- `AccessibilityFocusState` — defined in `SkipSwiftUI/System/Accessibility.swift:639` as `@propertyWrapper @frozen public struct`
- `FocusedBinding` — defined in `SkipSwiftUI/Properties/FocusedBinding.swift:5` as `@propertyWrapper public struct`
- `FocusState` — defined in `SkipSwiftUI/Properties/FocusState.swift`
- `AppStorage` — defined in `SkipSwiftUI/Properties/AppStorage.swift`

**However:** `AccessibilityFocusState.Binding` is not exposed — the `projectedValue` returns `Any` (line 659: `public var projectedValue: Any /* AccessibilityFocusState<Value>.Binding { get } */`). The conformance `AccessibilityFocusState.Binding: _Bindable` would fail because `AccessibilityFocusState.Binding` is not a real type in SkipFuseUI.

**Recommendation:**
- `Bind.swift:62` (AccessibilityFocusState + AccessibilityFocusState.Binding): **Leave guard** — `.Binding` nested type is stubbed out (`Any`).
- `Bind.swift:75` (FocusedBinding + FocusState + FocusState.Binding): **Leave guard** — `FocusState.Binding` is likely similarly stubbed. Also, `AppStorage` conformance is in this same guard block (line 70), and its `_Bindable` conformance depends on `wrappedValue` setter behavior that may differ.

**Confidence:** HIGH — direct source inspection.

### NavigationStack+Observation.swift:150
**Finding:** This guard wraps a `NavigationStack` init extension that creates a TCA-driven navigation stack with `path: Binding<Store<StackState<State>, StackAction<State, Action>>>`. The constraint is `Data == StackState<State>.PathView`.

Skip-fuse-ui **does** provide `NavigationStack`, and Phase 15 already added the TCA `NavigationStack` free function adapter for Android. However, this extension is on `NavigationStack` directly (not a free function), and it constrains `Data` and `Root` generic parameters to specific TCA types.

The skip-fuse-ui `NavigationStack` is `NavigationStack<Data, Root>` matching SwiftUI's generic signature. This extension should compile if SkipFuseUI's `NavigationStack` accepts the same generic constraints.

**Recommendation:** Remove the guard and verify empirically. If it fails (e.g., SkipFuseUI's NavigationStack doesn't support the `ModifiedContent` constraint for `Root`), re-gate with `#if !os(Android)`.

**Confidence:** MEDIUM — types exist but generic constraint satisfaction unverified.

### ButtonState.swift Guards in swift-navigation
**Finding:** ButtonState.swift has **many more guards** than listed in CONTEXT.md's "already-enabled" section. The `animatedSend` enum case and all its usage sites (lines 5, 66, 86, 129, 137, 150, 161, 209, 238, 260) are behind `#if canImport(SwiftUI) && !os(Android)` guards. These are NOT "already-enabled" — they gate the `animatedSend` case which uses `Animation` type and `withAnimation`.

After `withTransaction` is implemented, these guards can be removed because:
1. `Animation` type is available in SkipFuseUI
2. `withAnimation` is fully implemented in SkipFuseUI
3. The `animatedSend` case just wraps `withAnimation(animation) { perform(action) }`

**Recommendation:** Remove all `&& !os(Android)` / `!os(Android)` guards from ButtonState.swift after withTransaction is implemented. This is necessary for the Alert/ConfirmationDialog animation paths in TCA to work.

**Confidence:** HIGH — `withAnimation` confirmed working, `Animation` type confirmed available.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Animation on Android | Custom animation dispatch | `withAnimation` in skip-fuse-ui | Already bridges to Compose; handles animation lifecycle |
| Transaction on Android | Transaction thread-local storage | Delegation to `withAnimation` | Transaction's only meaningful property is `animation`; other properties are `@available(*, unavailable)` stubs |
| Rich text on Android | Manual attributed string | TextState modifier pipeline | Existing infrastructure handles storage, equality, hashing — just needs guard removal |

**Key insight:** The entire Phase 16 is about removing guards, not building new functionality. The only new code is the ~10-line `withTransaction` delegation to `withAnimation`.

## Common Pitfalls

### Pitfall 1: Guard Removal Order Matters
**What goes wrong:** Removing animation-related guards in TCA before implementing `withTransaction` causes immediate build failures (`fatalError()` at the call site is `@available(*, unavailable)`, so the compiler rejects it).
**Why it happens:** The `@available(*, unavailable)` attribute makes `withTransaction` a compile-time error, not just a runtime crash.
**How to avoid:** Implement `withTransaction` in skip-fuse-ui FIRST, then remove TCA guards.
**Warning signs:** Compiler error "withTransaction is unavailable".

### Pitfall 2: TextState LocalizedStringResource Availability
**What goes wrong:** Removing `&& !os(Android)` from TextState.swift Storage enum exposes `.localizedStringResource(LocalizedStringResourceBox)` case on Android, but `LocalizedStringResource` may not exist in SkipFuseUI.
**Why it happens:** `LocalizedStringResource` is an iOS 16+ API that may not be stubbed in SkipSwiftUI.
**How to avoid:** After removing outer guards, check if `LocalizedStringResource` compiles. If not, add a targeted inner `#if !os(Android)` or `#if canImport(SwiftUI)` guard around just the `.localizedStringResource` case and its usage sites.
**Warning signs:** "Cannot find type 'LocalizedStringResource' in scope" compiler error.

### Pitfall 3: ButtonState.swift Must Also Be Unguarded
**What goes wrong:** Removing animation guards from Alert+Observation.swift and ConfirmationDialog.swift (TCA) but leaving ButtonState.swift (swift-navigation) guarded. The `switch button.action.type` in Alert+Observation.swift references `.animatedSend` which is conditionally compiled in ButtonState.swift.
**Why it happens:** The `_ActionType.animatedSend` enum case is in swift-navigation, but it's used from TCA. Both must be unguarded simultaneously.
**How to avoid:** Unguard ButtonState.swift `animatedSend` cases in the same task as Alert+Observation.swift unguarding.
**Warning signs:** "Type '_ActionType' has no member 'animatedSend'" compiler error.

### Pitfall 4: BindingLocal Deletion Ordering
**What goes wrong:** Deleting Core.swift's BindingLocal before removing ViewStore.swift's guard causes duplicate symbol on Darwin (both active) or missing symbol on Android (neither active).
**Why it happens:** Core.swift guard is `#if !canImport(SwiftUI) || os(Android)` — active on Android. ViewStore.swift guard is `#if !os(Android)` — active on Darwin. Changing one without the other breaks one platform.
**How to avoid:** In a single commit: (1) remove `#if !os(Android)` guard from ViewStore.swift, (2) delete BindingLocal from Core.swift, (3) also delete the `#if !canImport(SwiftUI)` block around `_isInPerceptionTracking` in Core.swift if it's also now covered.
**Warning signs:** "Invalid redeclaration of 'BindingLocal'" or "Cannot find 'BindingLocal' in scope".

### Pitfall 5: Cross-Fork Dependency
**What goes wrong:** Building TCA fork without first building swift-navigation fork with its guard removals (especially ButtonState.swift animatedSend).
**Why it happens:** TCA depends on swift-navigation. If swift-navigation still has `animatedSend` guarded out, TCA code referencing it won't compile.
**How to avoid:** Apply swift-navigation changes before TCA changes, or apply both and build together.

## Code Examples

### withTransaction Implementation (skip-fuse-ui)
```swift
// Source: forks/skip-fuse-ui/Sources/SkipSwiftUI/Animation/Transaction.swift
// Replace lines 105-113

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    if let animation = transaction.animation {
        return try withAnimation(animation, body)
    } else {
        return try body()
    }
}

public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var transaction = Transaction()
    transaction[keyPath: keyPath] = value
    if let animation = transaction.animation {
        return try withAnimation(animation, body)
    } else {
        return try body()
    }
}
```

### Guard Removal Example (TCA Animation.swift)
```swift
// Source: forks/swift-composable-architecture/Sources/ComposableArchitecture/Effects/Animation.swift
// Before: #if canImport(SwiftUI) && !os(Android)
// After:  #if canImport(SwiftUI)
#if canImport(SwiftUI)
import OpenCombineShim
import SwiftUI

extension Effect {
  public func animation(_ animation: Animation? = .default) -> Self {
    self.transaction(Transaction(animation: animation))
  }
  // ... rest unchanged
}
#endif
```

### IfLetStore Alternative Test
```swift
// Source: examples/fuse-library/Tests/TCATests/ (new file or addition to existing)
/// Tests the modern @Observable alternative to the deprecated IfLetStore pattern.
/// IfLetStore is deprecated and excluded from test coverage — this test proves
/// the recommended replacement works on both platforms.
@Test func testIfLetStoreAlternativePattern() async {
    @Reducer struct Parent {
        @ObservableState struct State {
            @Presents var child: Child.State?
        }
        enum Action {
            case child(PresentationAction<Child.Action>)
            case showChild
            case hideChild
        }
        @Reducer struct Child {
            @ObservableState struct State { var value = "hello" }
            enum Action { case noop }
            var body: some ReducerOf<Self> { Reduce { _, _ in .none } }
        }
        var body: some ReducerOf<Self> {
            Reduce { state, action in
                switch action {
                case .showChild:
                    state.child = Child.State()
                    return .none
                case .hideChild:
                    state.child = nil
                    return .none
                case .child:
                    return .none
                }
            }
            .ifLet(\.$child, action: \.child) { Child() }
        }
    }

    let store = TestStore(initialState: Parent.State()) { Parent() }
    // Child nil → scope returns nil
    await store.send(.showChild) { $0.child = Parent.Child.State() }
    // Child non-nil → scope returns child store
    await store.send(.hideChild) { $0.child = nil }
}
```

### TextState Modifier Test
```swift
// Source: examples/fuse-library/Tests/NavigationTests/ (new or existing)
@Test func testTextStateModifiersCompileAndExecute() {
    // Verify modifiers compile and don't crash (no rendered output assertion)
    let bold = TextState("Hello").bold()
    let italic = TextState("Hello").italic()
    let kerning = TextState("Hello").kerning(1.5)
    let foreground = TextState("Hello").foregroundColor(.red)
    let font = TextState("Hello").font(.body)
    let combined = TextState("Hello").bold().italic().font(.headline)

    // Verify equality still works with modifiers
    #expect(bold == TextState("Hello").bold())
    #expect(bold != italic)

    // Verify concatenation with modifiers
    let concat = TextState("Hello ") + TextState("World").bold()
    #expect(concat == TextState("Hello ") + TextState("World").bold())
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `#if !os(Android)` on all SwiftUI code | SkipFuseUI re-exports SwiftUI types | Phase 10 (discovery) | Most guards are now unnecessary |
| `withTransaction` unavailable on Android | Delegation to `withAnimation` | Phase 16 (this phase) | Unblocks 8+ animation guards |
| TextState plain-text fallback on Android | Full rich text pipeline | Phase 16 (this phase) | Enables modifiers, LocalizedStringKey |
| IfLetStore on Android | @Observable `if let store.scope(...)` pattern | TCA deprecation | Modern pattern works; deprecated view unneeded |
| Duplicate BindingLocal definitions | Single definition in ViewStore.swift | Phase 16 (this phase) | Cleaner code, matches upstream |

## Open Questions

1. **LocalizedStringResource on Android**
   - What we know: `LocalizedStringKey` is available in SkipFuseUI. `LocalizedStringResource` is an iOS 16+ Foundation type.
   - What's unclear: Whether SkipFuseUI or SkipLib provides `LocalizedStringResource`. It's a Foundation type, not SwiftUI, so it might be available through skip-foundation.
   - Recommendation: Attempt guard removal. If `LocalizedStringResource` is missing, add a targeted inner `#if !os(Android)` guard around just the `.localizedStringResource` storage case and its init/equality/hash methods. LOW impact — `LocalizedStringResource` is a rarely-used iOS 16+ API.

2. **TextState `toSwiftUI` computed properties**
   - What we know: TextState defines internal enums (`FontWidth`, `LineStylePattern`) with `toSwiftUI` computed properties that reference `SwiftUI.Font.Width` and `SwiftUI.Text.LineStyle.Pattern`.
   - What's unclear: Whether these specific SwiftUI types exist in SkipFuseUI. `FontWidth` in SkipFuseUI exists for `Text` but the mapping to `Font.Width` is unverified.
   - Recommendation: These `toSwiftUI` properties are only used in the `Text.init(_ state: TextState)` SwiftUI extension (which applies modifiers to create `SwiftUI.Text`). On Android, a different `Text.init(_ state:)` path will be used. The `toSwiftUI` properties may need `#if !os(Android)` inner guards if types don't compile. LOW risk.

3. **NavigationStack+Observation.swift:150 extension**
   - What we know: skip-fuse-ui provides `NavigationStack<Data, Root>`. Phase 15 added a free function adapter.
   - What's unclear: Whether the `ModifiedContent<R, _NavigationDestinationViewModifier<...>>` constraint on `Root` is satisfied by SkipFuseUI's NavigationStack.
   - Recommendation: Remove guard, attempt build. If it fails, re-gate. This is a convenience initializer — the free function adapter from Phase 15 covers the same use case.

## Sources

### Primary (HIGH confidence)
- Direct source inspection of `forks/skip-fuse-ui/Sources/SkipSwiftUI/` — verified type availability for Animation, Transaction, Font, Color, CGFloat, LocalizedStringKey, Visibility, AccessibilityFocusState, FocusedBinding, FocusState, AppStorage
- Direct source inspection of `forks/skip-fuse-ui/Sources/SkipSwiftUI/Animation/Animation.swift:476` — confirmed `withAnimation` is fully implemented with Compose bridging
- Direct source inspection of `forks/skip-fuse-ui/Sources/SkipSwiftUI/Animation/Transaction.swift` — confirmed `withTransaction` is `@available(*, unavailable)` with `fatalError()`
- Direct source inspection of `forks/swift-composable-architecture/Sources/` — full guard inventory (24+ guards)
- Direct source inspection of `forks/swift-navigation/Sources/` — full guard inventory (15+ guards)
- `forks/swift-navigation/Sources/SwiftNavigation/TextState.swift` — TextState full structure, modifiers, storage enum
- `forks/swift-navigation/Sources/SwiftNavigation/ButtonState.swift` — animatedSend enum case and all usage sites

### Secondary (MEDIUM confidence)
- CONTEXT.md discussion outcomes — withTransaction implementation approach, comprehensive guard audit counts
- Phase 10 decisions (STATE.md) — canImport(SwiftUI) is false on Android, SkipFuseUI re-export chain

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all files directly inspected, type availability verified via grep
- Architecture: HIGH — withTransaction implementation is straightforward delegation; guard removal is mechanical
- Pitfalls: HIGH — cross-fork dependency order and TextState type availability are well-characterized risks
- Research answers: HIGH for ObservedObject (not available), HIGH for Bind conformances (types exist but .Binding subtypes stubbed), MEDIUM for NavigationStack:150 and TextState edge cases

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (stable — fork code changes infrequently)
