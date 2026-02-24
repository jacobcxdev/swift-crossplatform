# Phase 16: TCA API Parity Completion - Context

**Gathered:** 2026-02-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove `#if !os(Android)` and `#if canImport(SwiftUI) && !os(Android)` guards from P3 tech debt items across the TCA fork (swift-composable-architecture), swift-navigation fork, and skip-fuse-ui fork — enabling Binding+Observation extensions, Alert/ConfirmationDialog observation, animation paths, TextState rich text, and other gated APIs on Android. Each enablement validated by a dedicated test. IfLetStore (deprecated) is unguarded but not tested; the @Observable alternative is tested instead.

</domain>

<decisions>
## Implementation Decisions

### Import Strategy (applies globally across all guard removals)
- SkipFuseUI re-exports SkipSwiftUI as SwiftUI via `@_exported import` — `import SwiftUI` resolves on both Darwin and Android. Files never need both imports.
- Remove `#if !os(Android)` guards entirely rather than converting to `canImport`. The import is already satisfied.
- Migrate ALL `#if !os(Android)` SwiftUI import guards across the TCA fork, not just Phase 16's named items. Comprehensive audit.
- For guards that wrap code with additional non-import incompatibilities (e.g. missing SkipFuseUI APIs): convert the outer import guard, add targeted `#if os(Android)` inner guards around specific incompatible lines. Layered approach.
- Deprecated APIs (IfLetStore, NavigationStackStore, old Alert/ConfirmationDialog): remove their guards too. Only re-gate if they are the sole reason for a build failure. No test coverage for deprecated APIs.

### withTransaction Implementation (skip-fuse-ui fork)
- `withTransaction` is currently `@available(*, unavailable)` with `fatalError()` in skip-fuse-ui (Transaction.swift lines 105-113). Also a `fatalError()` stub in skip-ui (Transaction.swift line 219).
- `withAnimation` IS fully implemented in skip-fuse-ui with Compose bridging (Animation.swift line 476). `Transaction` struct exists with a working `animation: Animation?` property.
- TCA's animation chain: `Store.send(_:animation:)` → creates `Transaction(animation:)` → calls `send(_:transaction:)` → calls `withTransaction(transaction) { ... }` → fatalError on Android.
- **Fix:** Implement `withTransaction` in skip-fuse-ui by extracting `transaction.animation` and delegating to `withAnimation`. Replace the `@available(*, unavailable)` stubs with working implementations.
- This single fix unblocks all 8 animation-related guards in the TCA fork (`.animatedSend` cases in Alert/ConfirmationDialog, `send(_:animation:)`, `send(_:while:animation:)`, ViewAction send with animation).

### IfLetStore Disposition
- IfLetStore is deprecated in upstream TCA. The modern pattern is `if let store = store.scope(...)` with @Observable.
- Remove the `#if !os(Android)` guards (per import strategy above) — let it compile if it can. Only re-gate if it's the sole cause of a build failure.
- No test coverage for IfLetStore itself (deprecated API).
- Write a specific TCA pattern test proving the @Observable alternative works: parent with optional child state, scope into child, verify child view appears when state is non-nil and disappears when nil.
- Test name and/or comment should explicitly reference IfLetStore (e.g. `testIfLetStoreAlternativePattern`) to link the exclusion to its proof.
- Document the exclusion with a code comment only at the guard site. No CLAUDE.md or REQUIREMENTS.md updates needed.

### TextState Rich Text Enablement (swift-navigation fork)
- The TextState issue is NOT just CGFloat ambiguity — the entire rich text pipeline (modifiers, LocalizedStringKey, Font, accessibility types) is behind `#if canImport(SwiftUI) && !os(Android)` guards (10+ guards in TextState.swift).
- On Android, TextState currently falls back to plain text only (lines 849-874: `Text(verbatim: state._plainText)`).
- CGFloat is available via SkipLib. LocalizedStringKey, Font, and other SwiftUI types are already supported in SkipFuseUI.
- **Fix:** Remove `&& !os(Android)` from all guards in TextState.swift. Verify compilation empirically.
- Block until resolved — do not accept a plain text fallback. This is a success criterion.
- Cross-fork fixes acceptable if needed (e.g. if SkipFuseUI needs additions).
- Tests verify compile + no crash for modifiers (e.g. `.bold()`, `.kerning()`, `.foregroundColor()`). Do NOT assert on rendered output — that's UI-level testing beyond TCA's scope.

### BindingLocal Cleanup (TCA fork)
- Currently defined twice with complementary guards:
  - `Core.swift:14-18`: `#if !canImport(SwiftUI) || os(Android)` — defined on Android
  - `ViewStore.swift:632-636`: `#if !os(Android)` — defined on Darwin
- This is duplicating code unnecessarily. Upstream TCA defines BindingLocal in ViewStore.swift.
- **Fix:** Keep the definition in ViewStore.swift (upstream location), remove its `#if !os(Android)` guard so it compiles on both platforms, and delete the duplicate from Core.swift entirely.

### ObservedObject.Wrapper Guards (TCA fork — research needed)
- 8 guards in TCA wrap `ObservedObject.Wrapper` extensions (Binding+Observation.swift ×4, NavigationStack+Observation.swift ×2, Store+Observation.swift ×2).
- These are all pre-@Observable deprecated patterns (`@available(iOS, introduced: 13, obsoleted: 17)`).
- `ObservedObject` is absent from skip-fuse-ui's SkipSwiftUI module. It exists in skip-ui as `typealias ObservedObject<T> = Bindable<T>`, but gated behind `#if !SKIP_BRIDGE` (Lite mode only).
- **Research question:** Empirically verify whether `ObservedObject` is accessible at compile time in Fuse mode via SkipFuseUI's module re-export chain. Test: add `let _: ObservedObject<AnyObject>? = nil` in an Android-compiled file.
- If accessible: remove guards (per import strategy).
- If inaccessible: leave guards as-is (deprecated code paths, not needed on Android).

### Bind Conformances (swift-navigation fork — research needed)
- `Bind.swift:62,75`: `AccessibilityFocusState: _Bindable` and `FocusedBinding: _Bindable` behind `#if !os(Android)`.
- **Research question:** Verify whether `AccessibilityFocusState` and `FocusedBinding` exist in SkipFuseUI. If yes, remove guards. If no, leave.

### UIKitNavigation Export (must stay)
- `Exports.swift:14`: `@_exported import UIKitNavigation` behind `#if !os(Android)`. UIKitNavigation does not exist on Android. This guard must remain.

### NavigationStack+Observation.swift:150 (research needed)
- `NavigationStack` init extension behind `#if !os(Android)`. Needs investigation during planning to determine if this is removable (skip-fuse-ui provides NavigationStack) or must stay.

### Additional swift-navigation Guards
- `Alert.swift:201`: Deprecated alert API — remove guard per strategy (deprecated, only re-gate if build fails).
- `ConfirmationDialog.swift:227`: Deprecated confirmation dialog API — remove guard per strategy.
- `Binding.swift:81,120` and `Binding+Internal.swift:6`: `#if os(Android)` — these are already-enabled Android code paths, no changes needed.
- `ButtonState.swift:391`: `#if os(Android)` — already-enabled Android ButtonRole extension, no changes needed.

### Test Evidence
- One focused test per enablement (not thorough coverage suites).
- Tests added to existing test suites in fuse-library/Tests — co-located with related tests (e.g. NavigationTests for Alert, TCATests for Binding).
- Tests run on both Darwin and Android (not Android-only) — confirms parity and catches regressions.
- IfLetStore alternative test explicitly links to exclusion (naming/comment).
- TextState tests verify compile + no crash for modifiers.
- No test coverage for deprecated APIs.

</decisions>

<specifics>
## Specific Ideas

- The withTransaction implementation is a small, well-scoped change in skip-fuse-ui: extract `transaction.animation` and call `withAnimation`. The `Transaction` struct already has the `animation` property. Skip docs confirm `withAnimation` has medium support with Compose equivalents.
- Animation support in Skip converts SwiftUI animation types to Compose equivalents. Animatable properties include background/border colors, font size, foreground styles, frame dimensions, offset, opacity, rotation, scale. Springs use Compose's `EaseInOutBack` easing unless `Spring(mass:stiffness:damping:)` is used.
- The comprehensive guard audit found 24 guards in TCA fork, ~15 in swift-navigation fork. Full file-level inventory:
  - **TCA removable (13):** IfLetStore.swift ×3, NavigationStackStore.swift ×1, Binding.swift ×2, Popover.swift ×1, Alert.swift ×1, ConfirmationDialog.swift ×1, Alert+Observation.swift ×2, ViewStore.swift:251+365 ×2
  - **TCA ObservedObject research (8):** Binding+Observation.swift ×4, NavigationStack+Observation.swift ×2, Store+Observation.swift ×2
  - **TCA must stay (2):** Exports.swift ×1 (UIKitNavigation), NavigationStack+Observation.swift:150 ×1 (research)
  - **TCA cleanup (1):** ViewStore.swift:632 BindingLocal → delete, keep upstream definition
  - **swift-navigation TextState (10+):** Lines 4, 54, 121, 143, 192, 209, 259, 288, 409, 674, 693, 742, 758
  - **swift-navigation removable (2):** Alert.swift:201, ConfirmationDialog.swift:227
  - **swift-navigation research (2):** Bind.swift:62, Bind.swift:75
  - **swift-navigation already-enabled (4):** Binding.swift ×2, Binding+Internal.swift ×1, ButtonState.swift ×1
- ViewAction.swift:31 (`send(_:animation:)`) is also removable after withTransaction fix.
- Other forks (combine-schedulers, swift-sharing, swift-case-paths) have functional Android adaptations that should NOT be changed in Phase 16.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 16-api-parity-completion*
*Context gathered: 2026-02-24*
