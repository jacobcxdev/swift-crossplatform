# Phase 13: API Parity Gaps - Research

**Researched:** 2026-02-24
**Domain:** TCA API parity on Android via Skip Fuse mode
**Confidence:** HIGH

## Summary

Phase 13 addresses the PARITY-GAPS-IN-CURRENT-APIS audit gap from v1.0-MILESTONE-AUDIT.md. The audit identified 8 parity risk items where non-deprecated TCA APIs are gated with `#if !os(Android)` or `#if canImport(SwiftUI) && !os(Android)` without Android equivalents.

After thorough investigation, the situation is significantly better than the audit initially suggested. Several items already have Android implementations or modern replacements that work on Android:

- **SwitchStore/CaseLet**: Deprecated since TCA 1.7. The modern `store.case` property (`CaseReducer.swift:60`) has zero platform guards and works on Android. The deprecated views depend on `WithViewStore`/`ViewStore` (Combine-based) which are architecturally incompatible with Android.
- **IfLetStore(then:else:)**: Deprecated since TCA 1.7. Modern replacement `if let childStore = store.scope(...)` works on Android already.
- **Popover**: Already has Android fallback in Popover.swift (falls back to `.sheet`).
- **NavigationStack programmatic push**: Already has Android adapter from Phase 10 (free function `NavigationStack(path:root:destination:)` in `NavigationStack+Observation.swift:269`).
- **TextState/ButtonState**: Already have Android implementations in swift-navigation fork (plain text for TextState, ButtonRole init for ButtonState).

The real work items are:
1. `ViewActionSending.send(_:animation:)` -- needs a no-op animation overload on Android
2. `fullScreenCover` TCA integration -- the deprecated `.fullScreenCover(store:)` needs Android equivalent using skip-fuse-ui's `fullScreenCover(item:)`
3. Alert/ConfirmationDialog `.animatedSend` cases -- guarded out on Android, need no-op handling
4. TextState rich text rendering -- currently drops all formatting (bold, italic, color) to plain text

**Primary recommendation:** Implement the 3-4 genuine gaps, document the deprecated APIs as out-of-scope per REQUIREMENTS.md (which already lists "Deprecated TCA APIs" as out of scope), and verify `store.case` enum switching works end-to-end on Android.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| swift-composable-architecture | fork/dev/swift-crossplatform | TCA framework | Project's core dependency |
| swift-navigation | fork/dev/swift-crossplatform | Navigation helpers, TextState, ButtonState | TCA's navigation layer |
| skip-fuse-ui | fork/dev/swift-crossplatform | Android SwiftUI equivalent | Provides sheet, fullScreenCover, alert, confirmationDialog |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| skip-fuse | upstream | Swift-to-Kotlin bridge layer | Already integrated |
| swift-perception | fork/dev/swift-crossplatform | Perceptible protocol on Android | Phase 12 delivered this |

### Alternatives Considered
None -- all work is within existing forks.

## Architecture Patterns

### Pattern 1: No-Op Animation Parameter on Android
**What:** When an API accepts an `Animation?` or `Transaction` parameter that cannot function on Android (because `withTransaction` is `fatalError()` in skip-fuse-ui), provide the same API surface but ignore the animation parameter.
**When to use:** Any API that takes `Animation?` or `Transaction` and is needed on Android.
**Example:**
```swift
// In ViewAction.swift, inside ViewActionSending extension:
#if os(Android)
/// Send a view action to the store with animation (no-op on Android).
@discardableResult
public func send(_ action: StoreAction.ViewAction, animation: Animation?) -> StoreTask {
    self.store.send(.view(action))  // Ignore animation parameter
}
#endif
```

### Pattern 2: Deprecated API Exclusion
**What:** Deprecated TCA APIs (SwitchStore, CaseLet, IfLetStore, ForEachStore, WithViewStore) depend on Combine-based `ViewStore` and `ObservableObject` conformance. These are fundamentally incompatible with Android's observation model. The modern `@Observable`-based APIs (`store.case`, `if let store.scope(...)`, `ForEach` with store) already work on Android.
**When to use:** When the success criteria reference deprecated views.
**Decision:** Do NOT implement deprecated API equivalents on Android. Document that modern equivalents work instead.

### Pattern 3: TCA Presentation Modifier Bridge
**What:** TCA's deprecated `.fullScreenCover(store:)` and `.sheet(store:)` use the internal `PresentationModifier` infrastructure which depends on Combine-based `ViewStore` and `ObservableObject`. The modern pattern uses `$store.scope(state:action:)` to produce a `Binding<Store?>` that feeds into standard SwiftUI `.fullScreenCover(item:)` / `.sheet(item:)`.
**When to use:** For presentation modifiers on Android.
**Example:**
```swift
// Modern TCA pattern (already works on Android via skip-fuse-ui):
.sheet(item: $store.scope(state: \.child, action: \.child)) { store in
    ChildView(store: store)
}
// This works because:
// 1. Binding.scope (Store+Observation.swift) has no Android guard
// 2. SwiftUI.Bindable.scope (Store+Observation.swift) has no Android guard
// 3. skip-fuse-ui provides sheet(item:) and fullScreenCover(item:)
```

### Pattern 4: Alert/ConfirmationDialog AnimatedSend Handling
**What:** `ButtonState.ButtonAction` has a `.animatedSend` case that wraps an action with animation. On Android, this case is currently gated out with `#if !os(Android)`. The fix is to handle `.animatedSend` by falling through to plain `.send` on Android (ignore animation).
**When to use:** Alert+Observation.swift and ConfirmationDialog observation extensions.

### Anti-Patterns to Avoid
- **Do not implement Combine-dependent deprecated views on Android.** SwitchStore, CaseLet, IfLetStore, ForEachStore, WithViewStore all depend on `ObservableObject`/`@ObservedObject`/Combine publishers which are unavailable on Android. Use modern equivalents.
- **Do not try to make `withTransaction` work on Android.** It is intentionally `fatalError()` in skip-fuse-ui. Always use the no-op pattern for animation parameters.
- **Do not gate `store.case` on Android.** It is already unguarded and should work. Verify, don't restrict.
- **Do not add `ObservedObject.Wrapper` extensions on Android.** These reference `ObservableObject` conformance which uses Combine. The `SwiftUI.Bindable` and `Binding` extensions are the correct paths on Android.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Enum case switching in views | Custom Android SwitchStore | `switch store.case {}` (built-in) | Already works unguarded on Android |
| Optional child store rendering | Android IfLetStore | `if let childStore = store.scope(...)` | Already works unguarded on Android |
| Popover on Android | Custom popover UI | Sheet fallback (already implemented) | Android has no native popover concept |
| Rich text on Android | Custom attributed string renderer | Document limitations, use plain text | SkipSwiftUI Text has limited formatting support |

**Key insight:** Most "gaps" are actually deprecated APIs whose modern replacements already work on Android. The effort is verification and minor bridging, not reimplementation.

## Common Pitfalls

### Pitfall 1: Confusing Deprecated with Current APIs
**What goes wrong:** Implementing deprecated SwitchStore/CaseLet/IfLetStore on Android when modern equivalents already work.
**Why it happens:** The REQUIREMENTS.md originally listed these (TCA-25 mentions `switch store.case`), and the audit flagged SwitchStore/CaseLet. But TCA-25 says "switch store.case {} enum store switching" -- this is the MODERN API, not the deprecated SwitchStore view.
**How to avoid:** Check REQUIREMENTS.md wording carefully. TCA-25 says `store.case` not `SwitchStore`. Verify the modern API works, don't build the deprecated one.
**Warning signs:** If you find yourself importing Combine or referencing ObservableObject, you're implementing the deprecated path.

### Pitfall 2: canImport(SwiftUI) vs os(Android) Guard Confusion
**What goes wrong:** Removing `#if canImport(SwiftUI)` guards thinking they block Android code, when actually `canImport(SwiftUI)` IS true on Android (SkipFuseUI re-exports as SwiftUI module on Android -- actually NO, `canImport(SwiftUI)` is FALSE on Android per CLAUDE.md).
**Why it happens:** The project CLAUDE.md explicitly states: "canImport(SwiftUI) is false on Android -- SkipFuseUI re-exports SkipSwiftUI, not Apple's SwiftUI module."
**How to avoid:** Files gated with `#if canImport(SwiftUI)` are the ENTIRE file being excluded on Android. To provide Android equivalents, code must go in `#if os(Android)` blocks or be placed outside the `canImport(SwiftUI)` guard.
**Warning signs:** Code inside `#if canImport(SwiftUI)` blocks that you expect to run on Android.

### Pitfall 3: PresentationModifier Dependency Chain
**What goes wrong:** Trying to enable TCA's deprecated `.fullScreenCover(store:)` / `.sheet(store:)` on Android.
**Why it happens:** These use `PresentationStore` which uses `@ObservedObject var viewStore: ViewStore<...>` -- Combine-dependent.
**How to avoid:** Use the modern `$store.scope(state:action:)` + `.fullScreenCover(item:)` pattern. This goes through `Binding.scope` and `SwiftUI.Bindable.scope` which are unguarded.
**Warning signs:** If PresentationModifier.swift needs modifications, you're on the wrong path.

### Pitfall 4: ButtonState.ButtonAction.animatedSend on Android
**What goes wrong:** Alert and ConfirmationDialog buttons crash or compile-fail because `.animatedSend` case is gated out.
**Why it happens:** `ButtonStateAction` has two cases: `.send(Action?)` and `.animatedSend(Action?, animation: Animation?)`. The `.animatedSend` case is `#if !os(Android)` because it references `SwiftUI.Animation`.
**How to avoid:** On Android, either: (a) add `.animatedSend` case that ignores animation, or (b) ensure the `#if !os(Android)` guards in Alert+Observation.swift properly handle the missing case. Current guards in Alert+Observation.swift lines 27-32 and 70-75 already gate the `.animatedSend` switch cases, which is correct IF `.animatedSend` is never created on Android.
**Warning signs:** Runtime crash in alert button handlers on Android.

## Code Examples

### Example 1: Modern Enum Case Switching (Already Works on Android)
```swift
// Source: CaseReducer.swift (no platform guards)
// In view:
switch store.case {
case .loggedIn(let store):
    LoggedInView(store: store)
case .loggedOut(let store):
    LoggedOutView(store: store)
}
```

### Example 2: ViewActionSending.send(_:animation:) No-Op
```swift
// In ViewAction.swift, replace the existing #if !os(Android) block:
#if !os(Android)
@discardableResult
public func send(_ action: StoreAction.ViewAction, animation: Animation?) -> StoreTask {
    self.store.send(.view(action), animation: animation)
}

@discardableResult
public func send(_ action: StoreAction.ViewAction, transaction: Transaction) -> StoreTask {
    self.store.send(.view(action), transaction: transaction)
}
#else
// Android: animation/transaction parameters are no-ops
@discardableResult
public func send(_ action: StoreAction.ViewAction, animation: Animation?) -> StoreTask {
    self.store.send(.view(action))
}
#endif
```

### Example 3: Modern Presentation (Already Works on Android)
```swift
// Source: Store+Observation.swift Binding.scope + skip-fuse-ui
struct FeatureView: View {
    @Bindable var store: StoreOf<Feature>

    var body: some View {
        Button("Show Sheet") { store.send(.showSheetTapped) }
        .sheet(item: $store.scope(state: \.child, action: \.child)) { store in
            ChildView(store: store)
        }
    }
}
```

### Example 4: TextState Plain Text on Android
```swift
// Source: swift-navigation/TextState.swift lines 849-874 (already implemented)
#if os(Android)
extension Text {
    public init(_ state: TextState) {
        self = Text(verbatim: state._plainText)  // Drops bold/italic/color
    }
}
#endif
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SwitchStore` + `CaseLet` | `switch store.case {}` | TCA 1.7 | Old views deprecated, modern works on Android |
| `IfLetStore(then:else:)` | `if let store.scope(...)` | TCA 1.7 | Old view deprecated, modern works on Android |
| `.sheet(store:)` / `.fullScreenCover(store:)` | `.sheet(item: $store.scope(...))` | TCA 1.7 | Old modifiers use Combine, modern uses Binding |
| `WithViewStore` | Direct `store.state` access | TCA 1.7 | WithViewStore deprecated, direct access works |
| `ForEachStore` | `ForEach` with store scoping | TCA 1.7 | Old view deprecated |

**Deprecated/outdated:**
- SwitchStore, CaseLet, IfLetStore, ForEachStore, WithViewStore: All deprecated in TCA 1.7 migration. REQUIREMENTS.md "Out of Scope" section explicitly lists "Deprecated TCA APIs: ViewStore, WithViewStore, @PresentationState, TaskResult, ForEachStore, IfLetStore, SwitchStore -- use modern equivalents."

## Open Questions

1. **Does `store.case` work end-to-end on Android?**
   - What we know: `CaseReducer.swift` has no platform guards. The `case` property calls `State.StateReducer.scope(self)` which is pure reducer logic.
   - What's unclear: Whether the view-layer switch on the returned `CaseScope` renders correctly on Android via skip-fuse-ui's `ViewBuilder`.
   - Recommendation: Write a test that creates a `@Reducer enum` with multiple cases and verifies `switch store.case {}` renders the correct case on Android. HIGH confidence this works since it's pure Swift.

2. **Do the modern `.sheet(item:)` / `.fullScreenCover(item:)` patterns work with TCA's `$store.scope` binding on Android?**
   - What we know: `Binding.scope` and `SwiftUI.Bindable.scope` in Store+Observation.swift are unguarded. skip-fuse-ui provides `sheet(item:)` and `fullScreenCover(item:)`.
   - What's unclear: Whether the `Binding<Store?>` produced by `$store.scope` is correctly bridged through skip-fuse-ui's `sheet(item:)` which expects `Binding<Item?>` where `Item: Identifiable`.
   - Recommendation: Verify `Store` conforms to `Identifiable` (it does -- Store+Observation.swift line 40), then test the full chain.

3. **Should `.animatedSend` case be added to ButtonStateAction on Android, or should it stay gated?**
   - What we know: `ButtonStateAction` in ButtonState.swift has `.send` and `.animatedSend` cases. The `.animatedSend` case references `SwiftUI.Animation`. On Android, alert/dialog buttons only ever create `.send` actions (the `.animatedSend` creation path is in gated code).
   - What's unclear: Whether any code path could create an `.animatedSend` on Android.
   - Recommendation: Keep `.animatedSend` gated out on Android. The creation paths (in Alert+Observation.swift and ConfirmationDialog observation) are also gated. The existing pattern is self-consistent. Just verify no runtime crash occurs.

<phase_requirements>
## Phase Requirements

The phase description says "Derived from PARITY-GAPS-IN-CURRENT-APIS audit gap (affects NAV-05, NAV-07, NAV-08, TCA-25 and others)."

| ID | Description | Research Support |
|----|-------------|-----------------|
| TCA-25 | `switch store.case { }` enum store switching renders correctly on Android | `store.case` property (CaseReducer.swift:60) has NO platform guards. Modern API, not deprecated SwitchStore. Needs verification test only. |
| NAV-05 | `.sheet(item: $store.scope(...))` presents modal content on Android | Modern Binding.scope (Store+Observation.swift) is unguarded. skip-fuse-ui provides sheet(item:). Needs integration verification. |
| NAV-07 | `.popover(item: $store.scope(...))` displays popover on Android | Already implemented -- Popover.swift has Android fallback to sheet. Already-correct per 10-GAP-REPORT.md D31. |
| NAV-08 | `.fullScreenCover(item: $store.scope(...))` presents full-screen content on Android | Modern Binding.scope is unguarded. skip-fuse-ui provides fullScreenCover(item:). Needs integration verification. |
| SC-1 (new) | `ViewActionSending.send(_:animation:)` compiles on Android | Currently gated `#if !os(Android)`. Needs no-op Android overload. |
| SC-2 (new) | `IfLetStore(then:else:)` else branch renders on Android | DEPRECATED API. Modern `if let store.scope(...)` + `else` block works on Android. Out of scope per REQUIREMENTS.md. |
| SC-3 (new) | `SwitchStore` / `CaseLet` renders on Android | DEPRECATED API. Modern `switch store.case {}` works on Android. Out of scope per REQUIREMENTS.md. |
| SC-4 (new) | `TextState`/`ButtonState` rendering on Android | Already implemented (plain text fallback + ButtonRole init). Document known limitation: bold/italic/color silently dropped. |
| SC-5 (new) | `NavigationStack` programmatic push via path binding bidirectional | Phase 10 adapter handles push via NavigationLink. Pop works via `store.send(.popFrom(...))`. Verify bidirectionality. |
</phase_requirements>

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing + XCTest (mixed) |
| Config file | examples/fuse-library/Package.swift |
| Quick run command | `cd examples/fuse-library && swift test --filter TCATests` |
| Full suite command | `cd examples/fuse-library && swift test` |
| Estimated runtime | ~30 seconds |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TCA-25 | `store.case` enum switching | unit | `swift test --filter TCATests` | Needs new test |
| NAV-05 | Sheet with $store.scope binding | unit (data layer) | `swift test --filter NavigationTests` | Partially exists (SheetToggleFeature) |
| NAV-07 | Popover fallback to sheet | unit (data layer) | `swift test --filter NavigationTests` | Already tested |
| NAV-08 | fullScreenCover with $store.scope | unit (data layer) | `swift test --filter NavigationTests` | Needs new test |
| SC-1 | ViewActionSending animation no-op | unit | `swift test --filter TCATests` | Needs new test |
| SC-4 | TextState/ButtonState rendering | unit | `swift test --filter NavigationTests` | Partially exists |
| SC-5 | NavigationStack bidirectional push | unit | `swift test --filter NavigationTests` | Exists (ContactsFeature navigation tests) |

### Wave 0 Gaps (must be created before implementation)
- [ ] Test for `store.case` enum switching on Android -- `TCATests/EnumCaseSwitchingTests.swift`
- [ ] Test for `ViewActionSending.send(_:animation:)` on Android -- extend existing ViewAction tests
- [ ] Test for `fullScreenCover` with `$store.scope` binding -- `NavigationTests/FullScreenCoverTests.swift`

## Sources

### Primary (HIGH confidence)
- Direct code inspection of all guarded files in swift-composable-architecture fork
- Direct code inspection of swift-navigation fork (TextState.swift, ButtonState.swift, Popover.swift, Bind.swift)
- Direct code inspection of skip-fuse-ui Presentation.swift (sheet, fullScreenCover, alert, confirmationDialog implementations)
- `.planning/phases/10-navigationstack-path-android/10-GAP-REPORT.md` -- systematic guard audit
- `.planning/v1.0-MILESTONE-AUDIT.md` -- gap identification
- REQUIREMENTS.md Out of Scope section -- "Deprecated TCA APIs" explicitly excluded

### Secondary (MEDIUM confidence)
- TCA 1.7 migration guide (referenced in deprecated annotations) -- confirms modern API replacements

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all forks already in project, no new dependencies
- Architecture: HIGH - patterns verified by direct code inspection of guard boundaries
- Pitfalls: HIGH - all pitfalls documented from actual Phase 10 gap analysis
- Gap scope: HIGH - comprehensive guard audit from 10-GAP-REPORT.md covers all 38 locations

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (30 days -- stable domain, no expected upstream changes)
