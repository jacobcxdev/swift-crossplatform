# Phase 5 Context: Navigation & Presentation

**Created:** 2026-02-22
**Phase goal:** TCA navigation patterns (stack, sheet, alert, confirmation dialog) and SwiftUI presentation lifecycle work on Android
**Requirements:** NAV-01..NAV-16, TCA-26..TCA-28, TCA-32..TCA-35, UI-01..UI-08 (32 total)

## Decisions

### D1: NavigationStack — Enable and Validate

**Decision:** Remove ALL `#if !os(Android)` guards from TCA's `NavigationStack+Observation.swift`. Enable the modern `NavigationStack.init(path:root:destination:)` extension on Android and validate against Skip's bridge.

**Rationale:** Skip's `Navigation.swift` has a full Compose implementation of NavigationStack with push/pop animations and back handling. The guards were likely added conservatively when Skip support was unknown. Skip's underlying NavigationStack exists — the TCA integration layer was blocked, not the primitive.

**Scope of guard removal:**
- Enable ALL sections including Perception.Bindable and UIBindable scope extensions
- Perception WILL exist on Android (porting is part of this effort)
- UIBindable availability is a research question
- Goal is full Darwin/Android parity — identify what doesn't work, don't preemptively guard it out

**Key research question:** Does Skip's NavigationStack support `navigationDestination(for:destination:)` with type-based routing? TCA's extension uses `.navigationDestination(for: StackState<State>.Component.self)`. If Skip doesn't support this, a shim approach becomes the fallback.

### D2: Popover — Fall Back to Sheet on Android

**Decision:** On Android, `.popover` renders as `.sheet` (Material3 bottom sheet). Write an Android-specific version of TCA's `Popover.swift` that delegates to sheet presentation.

**Rationale:** Skip marks `.popover(isPresented:)` as `@available(*, unavailable)` and the `item:` overload is a no-op. Android has no native popover concept. Material3 bottom sheet is the standard Android UX equivalent.

**Implementation:** Replace `#if canImport(SwiftUI) && !os(Android)` in `Popover.swift` with a platform split: Darwin uses popover, Android uses sheet with the same store-driven presentation pattern.

### D3: Dismiss Dependency — Full Lifecycle Validation

**Decision:** Validate BOTH the reducer mechanics AND view-level dismiss behavior in Phase 5.

**What to validate:**
1. `PresentationReducer` correctly nils optional child state on `.dismiss`
2. Effect cancellation via `PresentationDismissID` works on Android
3. `@Dependency(\.dismiss)` resolves and executes correctly
4. Skip's `.sheet`/`.fullScreenCover` actually closes when the TCA binding flips to nil
5. `onDismiss` closure fires on sheet dismissal

**Architecture note:** TCA's dismiss is fully state-driven (nils optional state, view reacts). It never calls SwiftUI's `@Environment(\.dismiss)` directly. Skip's `DismissAction` is `{ isPresented.set(false) }` injected into the environment by `SheetPresentation`.

### D4: openSettings Dependency — Validate No-Crash

**Decision:** Validate both `dismiss` and `openSettings` dependencies on Android. Even if `openSettings` is a no-op on Android, confirm it doesn't crash.

**Source:** Pending TODO from STATE.md — "dismiss/openSettings dependency validation (Phase 5)".

### D5: _EphemeralState — Research Before Enabling

**Decision:** Research why `_EphemeralState` conformance is guarded out on Android (`#if canImport(SwiftUI) && !os(Android)` in `EphemeralState.swift`) before removing the guard.

**Why this is critical:** Without `_EphemeralState` conformance, `AlertState` and `ConfirmationDialogState` won't auto-dismiss after button taps in `PresentationReducer`. The `ephemeralType(of:)` function returns nil, so the auto-nil-on-action logic is skipped. This breaks NAV-09 through NAV-13.

**Research questions:**
- Do `AlertState` and `ConfirmationDialogState` compile on Android? They're in swift-navigation which has many `#if !os(Android)` guards on `ButtonState` and `TextState`.
- What SwiftUI types do they depend on? (`ButtonRole`, `Text`, etc.)
- Can we make them conform to `_EphemeralState` on Android without pulling in unavailable types?

### D6: UI Pattern Testing — Compile + Store Tests

**Decision:** Write tests that BOTH compile SwiftUI patterns on Android (proving the APIs exist in Skip) AND validate data flow through Store.

**Examples:**
- `.task {}` modifier compiles → proves Skip supports it
- `Form { Button {} }` compiles → proves Skip supports Form
- `Binding` extensions resolve through Store → validates data flow
- `@State` initialization compiles → proves Skip pattern support

**Not testing:** View-level semantics like "exactly one recomposition" or "fires on appearance" — these require a running view hierarchy and are deferred to Phase 7 integration testing.

### D7: iOS 26+ Compatibility — No Deprecated APIs

**Decision:** Validate we don't use any APIs deprecated before iOS 17. Confirm we use modern patterns:
- `@Bindable` (not `@ObservedObject` with `ViewStore`)
- `NavigationStack(path:)` (not `NavigationStackStore`)
- `.sheet(item:)` (not `sheet(store:)`)

No need to test against iOS 26 SDK. This is a code audit concern.

## Discovered Issues

### I1: `#if !os(Android)` Guards Across Navigation Files

Files with Android guards that need evaluation during research/planning:

**TCA (swift-composable-architecture):**
- `NavigationStack+Observation.swift` — 4 guard blocks (NavigationStack init, modifier, NavigationLink, Perception/UIBindable)
- `NavigationStackStore.swift` — 1 guard (SwitchStore-based init, deprecated)
- `Popover.swift` — entire file guarded out
- `EphemeralState.swift` — AlertState/ConfirmationDialogState conformance guarded out
- `Alert.swift` / `ConfirmationDialog.swift` — `.animatedSend` case guarded out (minor)
- `SwitchStore.swift` — entire file guarded out (deprecated, likely OK to leave)
- `Binding.swift` — legacy BindingState guarded out (deprecated, likely OK to leave)
- `FullScreenCover.swift` — guarded with `#if !os(macOS)`, no Android guard (should work)

**swift-navigation:**
- `ButtonState.swift` — core struct compiles on Android (no guard on struct); extensive `#if !os(Android)` on SwiftUI rendering (ButtonRole conversion, etc.)
- `TextState.swift` — extensive Android guards on SwiftUI Text rendering extensions
- `NavigationLink.swift` — entire file guarded out
- `AlertState.swift` — pure Swift, NO Android guards, depends on ButtonState + TextState core types
- `ConfirmationDialogState.swift` — same as AlertState

### I2: StackReducer Has No Android Guards

Good news: `StackReducer.swift` (which implements `StackState`, `StackAction`, `.forEach` for stacks) has zero `#if !os(Android)` guards. The data-layer stack navigation works on Android already.

### I3: PresentationReducer Has No Android Guards

Good news: `PresentationReducer.swift` (`_PresentationReducer`, `PresentationState`, `PresentationAction`, `.ifLet` for presentations) has zero Android guards. The data-layer presentation lifecycle works on Android already.

### I4: Skip's Sheet/Alert/ConfirmationDialog Are Fully Implemented

Skip provides complete Compose implementations:
- `SheetPresentation` — Material3 `ModalBottomSheet` with detent support
- `AlertPresentation` — Material3 `AlertDialog` with destructive role (red), cancel role (bold)
- `ConfirmationDialogPresentation` — Material3 bottom sheet action sheet with role support
- `DismissAction` — `{ isPresented.set(false) }` injected into environment

### I5: Skip HAS `navigationDestination(for:destination:)`

Confirmed at `Navigation.swift:1004`: `func navigationDestination<D>(for data: D.Type, destination: (D) -> any View)`. TCA's type-based routing with `StackState<State>.Component.self` should work. Research should verify the generic type registration works with custom Hashable types.

### I6: Skip HAS `.task` Modifier

Confirmed at `AdditionalViewModifiers.swift:1223`: both `task(priority:action:)` and `task(id:priority:action:)` exist. UI-06 is covered at the API level.

### I7: AlertState/ButtonState/TextState Core Types Compile on Android

`AlertState` (AlertState.swift) — pure Swift: `UUID`, `[ButtonState]`, `TextState?`, `TextState`. No SwiftUI imports.
`ButtonState` (ButtonState.swift:9) — core struct NOT guarded. Only `import SwiftUI` and rendering extensions are `#if !os(Android)`.
`TextState` — core type likely similar pattern (research should confirm).

This means `_EphemeralState` conformance guard in `EphemeralState.swift` is likely overly conservative and can be removed. Research should confirm no transitive SwiftUI dependency.

### I8: `store.send(_:animation:)` and `withTransaction` Guarded Out — Correctly

`Store.swift:205` has `#if canImport(SwiftUI) && !os(Android)` blocking both `send(_:animation:)` and `send(_:transaction:)`. These use `withTransaction(transaction) { ... }`.

Skip HAS `Animation`, `Transaction`, and `withTransaction` types in its bridge, BUT `withTransaction` is a **`fatalError()` stub** (`Transaction.swift:219`). The guard is currently correct — enabling it would crash at runtime.

**Impact:** The `.animatedSend` case in `Alert.swift:92` and `ConfirmationDialog.swift:96` is also correctly guarded. Alert/dialog button taps use `.send` (non-animated) as fallback on Android, which is functionally correct — animations are cosmetic.

**Decision:** Keep the `!os(Android)` guard on `store.send(_:animation:)` for now. The non-animated `send(_:)` path works on Android. If Skip implements `withTransaction` in the future, the guard can be removed.

### I9: Skip's NavigationStack `path:` Initializer Uses Type Erasure

Skip's `NavigationStack.init(path: Any, root:)` (`Navigation.swift:112`) takes `Any` and force-casts to `Binding<[Any]>?`. TCA passes a `Binding<StackState<Path.State>>` scoped via `$store.scope(state: \.path, action: \.path)`.

**Risk:** The type erasure bridge may not correctly handle TCA's `StackState` type. Research must verify:
1. Does the `Binding<StackState<...>>` pass through the `Any` cast?
2. Does Skip's navigation engine correctly observe mutations on the bound array?
3. Does `StackState.Component` (the element type) survive type erasure for `navigationDestination(for:)` matching?

### I10: `@Presents` Macro Has No Android Guards

`PresentsMacro.swift` is pure SwiftSyntax — no `#if os(Android)` guards. The macro generates accessor wrappers for optional child state. Since it operates at compile-time via SwiftSyntax (not SwiftUI), it works identically on Android. TCA-27 is covered.

### I11: `@ReducerCaseEphemeral`/`@ReducerCaseIgnored` Have No Android Guards

Both macros in `ReducerMacro.swift` are pure SwiftSyntax with no platform guards. `@ReducerCaseEphemeral` marks enum cases whose state type conforms to `_EphemeralState` — this interacts with D5 (the `_EphemeralState` conformance guard). If D5 research enables the conformance on Android, TCA-34 automatically works. TCA-35 (`@ReducerCaseIgnored`) is independent and works already.

### I12: NAV-04 `navigationDestination(item:)` Exists in Skip

Skip has `navigationDestination(item:)` at `Navigation.swift:1101`, delegating to a `Binding`-based variant. The API exists but needs validation that TCA's store-scoped bindings pass through correctly.

## Deferred Ideas

- **Popover with anchor positioning on Android:** Could implement using Compose `DropdownMenu` or `Popup` for a more popover-like experience. Not in Phase 5 scope.
- **Animation parity for navigation transitions:** Skip has slide animations for push/pop but they may differ from iOS. Out of scope per REQUIREMENTS.md.

## Research Priorities

1. **NavigationStack `path:` type erasure with TCA's StackState** — Skip's `init(path: Any, root:)` force-casts to `Binding<[Any]>?`. Verify TCA's `Binding<StackState<Path.State>>` survives the cast and Skip's navigation engine observes mutations correctly. Critical for NAV-01..NAV-03.
2. **`_EphemeralState` guard removal** — Confirm AlertState/ConfirmationDialogState + ButtonState/TextState core types all compile on Android. If so, remove `#if !os(Android)` guard. Critical for NAV-09..NAV-13 and TCA-34.
3. **UIBindable on Android** — Does swift-navigation's UIBindable exist or compile on Android? Affects NavigationStack scope extensions in `NavigationStack+Observation.swift`.
4. **ButtonState SwiftUI rendering on Android** — The `#if !os(Android)` guards block `ButtonRole` conversion. TCA's alert rendering uses these. Determine if Skip's alert bridge handles roles directly (it does — see I4) or needs ButtonState→SwiftUI.ButtonRole conversion.
5. **`navigationDestination(for:)` with custom Hashable types** — Verify `StackState<State>.Component` (which conforms to `Hashable`) works as destination type via Skip's type-erased navigation engine. Critical for NAV-01.
6. **`navigationDestination(item:)` binding passthrough** — Verify TCA's store-scoped bindings work with Skip's `navigationDestination(item:)` at Navigation.swift:1101. Critical for NAV-04.
7. ~~**`.animatedSend` on Android**~~ — **RESOLVED (I8):** `withTransaction` is a `fatalError()` stub in Skip. Guard is correct. Keep non-animated `send(_:)` path on Android.

## Next Steps

→ `/gsd:research-phase 5` then `/gsd:plan-phase 5`
