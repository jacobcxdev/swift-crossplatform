# Phase 5: Navigation & Presentation - Research

**Researched:** 2026-02-22
**Domain:** TCA navigation patterns on Android via Skip's Fuse mode
**Confidence:** HIGH

## Summary

Phase 5 enables TCA's navigation layer on Android. The work falls into four domains: (1) stack-based navigation via `NavigationStack` with TCA's `StackState`/`StackAction`, (2) tree-based presentation via `.sheet`, `.fullScreenCover`, and `.popover` with TCA's `PresentationState`/`PresentationAction`, (3) alert/dialog state types (`AlertState`, `ConfirmationDialogState`) with `_EphemeralState` auto-dismissal, and (4) SwiftUI pattern validation (`.task`, `@State`, `Binding` extensions, `Form`).

The critical finding is that most data-layer code (reducers, state types, macros) already works on Android with zero guards. The work is primarily removing conservative `#if !os(Android)` guards from TCA's SwiftUI integration layer and validating that Skip's Compose bridge handles the resulting calls. Skip provides full implementations of `NavigationStack` (with type-based routing), sheets (Material3 `ModalBottomSheet`), alerts (`BasicAlertDialog`), and confirmation dialogs (action sheet style). The main risk is Skip's `NavigationStack.init(path: Any)` type erasure with TCA's `Binding<Store<StackState<...>>>`.

**Primary recommendation:** Remove guards incrementally by presentation type. Validate each with compile + store-driven tests. Do NOT attempt to implement animated send on Android (`withTransaction` is a `fatalError()` stub).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D1: NavigationStack — Enable and Validate.** Remove ALL `#if !os(Android)` guards from TCA's `NavigationStack+Observation.swift`. Enable the modern `NavigationStack.init(path:root:destination:)` extension on Android and validate against Skip's bridge. Enable ALL sections including Perception.Bindable and UIBindable scope extensions. Goal is full Darwin/Android parity — identify what doesn't work, don't preemptively guard it out.

**D2: Popover — Fall Back to Sheet on Android.** On Android, `.popover` renders as `.sheet` (Material3 bottom sheet). Write an Android-specific version of TCA's `Popover.swift` that delegates to sheet presentation. Darwin uses popover, Android uses sheet.

**D3: Dismiss Dependency — Full Lifecycle Validation.** Validate BOTH the reducer mechanics AND view-level dismiss behavior. Includes `PresentationReducer` nilling state, `PresentationDismissID` effect cancellation, `@Dependency(\.dismiss)` resolution, and Skip's sheet/fullScreenCover closing when binding flips to nil.

**D4: openSettings Dependency — Validate No-Crash.** Validate both `dismiss` and `openSettings` dependencies on Android. Even if `openSettings` is a no-op, confirm it doesn't crash.

**D5: _EphemeralState — Research Before Enabling.** Research why `_EphemeralState` conformance is guarded on Android before removing the guard. Without it, AlertState/ConfirmationDialogState won't auto-dismiss after button taps.

**D6: UI Pattern Testing — Compile + Store Tests.** Write tests that BOTH compile SwiftUI patterns on Android AND validate data flow through Store. Not testing view-level semantics (deferred to Phase 7).

**D7: iOS 26+ Compatibility — No Deprecated APIs.** Use modern patterns: `@Bindable`, `NavigationStack(path:)`, `.sheet(item:)`.

### Deferred Ideas (OUT OF SCOPE)

- Popover with anchor positioning on Android (DropdownMenu/Popup)
- Animation parity for navigation transitions
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NAV-01 | `NavigationStack` with `$store.scope(state: \.path, action: \.path)` renders on Android | Guard removal in NavigationStack+Observation.swift + Skip's `init(path: Any)` type erasure bridge |
| NAV-02 | Path append pushes new destination onto stack on Android | Skip's `Navigator.navigate(to:)` + `navigateToPath()` sync from bound array |
| NAV-03 | Path removeLast pops top destination on Android | Skip's `Navigator.navigateBack()` + popBackStack sync |
| NAV-04 | `navigationDestination(item:)` with binding pushes destination on Android | Skip has `navigationDestination(item:)` at Navigation.swift:1053, uses `NavigationDestinationItemWrapper` |
| NAV-05 | `.sheet(item: $store.scope(...))` presents modal on Android | Skip's `SheetPresentation` (Material3 ModalBottomSheet) + TCA's `PresentationModifier` |
| NAV-06 | `.sheet` `onDismiss` closure fires when dismissed on Android | Skip invokes `onDismissState.value?()` in LaunchedEffect when isPresentedValue flips false |
| NAV-07 | `.popover(item: $store.scope(...))` displays popover on Android | D2: Android popover falls back to sheet presentation |
| NAV-08 | `.fullScreenCover(item: $store.scope(...))` presents full-screen on Android | Skip's `SheetPresentation(isFullScreen: true)` + `#if !os(macOS)` guard (no Android guard) |
| NAV-09 | `.alert` with `AlertState` renders on Android | `AlertPresentation` + _EphemeralState conformance enablement (D5) |
| NAV-10 | Alert buttons with roles render correctly on Android | Skip's alert handles `.destructive` (red) and `.cancel` (bold) via ButtonRole bridge |
| NAV-11 | `.confirmationDialog` with `ConfirmationDialogState` renders on Android | `ConfirmationDialogPresentation` + _EphemeralState conformance enablement |
| NAV-12 | `AlertState.map(_:)` transforms action type on Android | Pure Swift, no guards, already works |
| NAV-13 | `ConfirmationDialogState.map(_:)` transforms action type on Android | Pure Swift, no guards, already works |
| NAV-14 | Dismissing via binding (nil optional) closes presentation on Android | Skip's `DismissAction { isPresented.set(false) }` + TCA's PresentationReducer nil-out logic |
| NAV-15 | `Binding` subscript with `CaseKeyPath` extracts enum value on Android | Pure Swift via CasePaths, no SwiftUI dependency |
| NAV-16 | Navigation patterns compatible with iOS 26+ APIs | D7: code audit for deprecated patterns |
| TCA-26 | `@Dependency(\.dismiss)` dismiss on Android | `Dismiss.swift` already has `#else` branch for non-animated dismiss on Android |
| TCA-27 | `@Presents` macro on Android | `PresentsMacro.swift` is pure SwiftSyntax, zero guards (confirmed I10) |
| TCA-28 | `PresentationAction.dismiss` nils child state on Android | `PresentationReducer.swift` has zero Android guards (confirmed I3) |
| TCA-32 | `StackState<Element>` on Android | `StackReducer.swift` has zero Android guards (confirmed I2) |
| TCA-33 | `StackAction` routes through `forEach` on Android | Same as TCA-32, zero guards |
| TCA-34 | `@ReducerCaseEphemeral` on Android | Depends on _EphemeralState conformance (D5) |
| TCA-35 | `@ReducerCaseIgnored` on Android | Pure SwiftSyntax macro, zero guards, works already |
| UI-01 | `Task { await method() }` in closures on Android | Standard Swift concurrency, works on Android |
| UI-02 | Custom `Binding` extensions via dynamic member lookup on Android | Store subscript extensions, pure Swift |
| UI-03 | `@State` variables correctly tracked on Android | Skip implements `@State` via Compose `mutableStateOf` |
| UI-04 | State mutations trigger body re-evaluation once on Android | Observation bridge from Phase 1 ensures single recomposition |
| UI-05 | `.sheet(isPresented:)` opens/dismisses on Android | Skip's `SheetPresentation` binding-driven |
| UI-06 | `.task {}` modifier on Android | Confirmed: Skip has `task(priority:action:)` and `task(id:priority:action:)` |
| UI-07 | Nested `@Observable` object graphs on Android | Observation bridge handles nested access tracking |
| UI-08 | Multiple buttons in Form trigger independent actions on Android | Skip has Form support with Compose list rendering |
</phase_requirements>

## Standard Stack

### Core

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| TCA NavigationStack+Observation | `forks/swift-composable-architecture/.../Observation/NavigationStack+Observation.swift` | Binding scope for `StackState`/`StackAction`, `NavigationStack.init(path:root:destination:)`, `_NavigationDestinationViewModifier` | The ONLY stack navigation integration layer between TCA and SwiftUI |
| TCA PresentationReducer | `forks/swift-composable-architecture/.../Reducer/Reducers/PresentationReducer.swift` | `.ifLet` for optional child state, dismiss lifecycle, effect cancellation | Zero Android guards, handles all presentation state lifecycle |
| TCA StackReducer | `forks/swift-composable-architecture/.../Reducer/Reducers/StackReducer.swift` | `.forEach` for stack navigation, `StackState`/`StackAction` | Zero Android guards, data layer for stack navigation |
| Skip NavigationStack | `forks/skip-ui/.../Containers/Navigation.swift` | Compose NavHost with path binding, type-based routing, push/pop animations | Skip's complete NavigationStack implementation |
| Skip Presentation | `forks/skip-ui/.../Layout/Presentation.swift` | `SheetPresentation`, `AlertPresentation`, `ConfirmationDialogPresentation` | Material3 implementations of all presentation types |
| swift-navigation AlertState/ButtonState/TextState | `forks/swift-navigation/Sources/SwiftNavigation/` | Pure data types for alert/dialog content | No Android guards on core structs |
| EphemeralState | `forks/swift-composable-architecture/.../Internal/EphemeralState.swift` | `_EphemeralState` protocol + conformances for auto-dismiss | Guard removal needed for Android |

### Supporting

| Component | Location | Purpose | When to Use |
|-----------|----------|---------|-------------|
| TCA Dismiss dependency | `forks/swift-composable-architecture/.../Dependencies/Dismiss.swift` | `@Dependency(\.dismiss)` for child self-dismissal | When testing dismiss lifecycle |
| PresentationModifier | `forks/swift-composable-architecture/.../SwiftUI/PresentationModifier.swift` | `PresentationStore` view + binding bridge | All presentation view modifiers use this |
| TCA Alert+Observation | `forks/swift-composable-architecture/.../Observation/Alert+Observation.swift` | Modern `.alert(item:)` / `.confirmationDialog(item:)` bindings | Modern TCA alert/dialog pattern |
| ButtonState SwiftUI bridge | `forks/swift-navigation/.../ButtonState.swift` (lines 391-431) | Android-specific `ButtonRole` init + `Button` init from ButtonState | Already ported for Android |

## Architecture Patterns

### Pattern 1: Guard Removal — NavigationStack

**What:** Remove `#if !os(Android)` from three blocks in `NavigationStack+Observation.swift`:
1. Lines 150-219: `NavigationStack.init(path:root:destination:)` + `_NavigationDestinationViewModifier`
2. Lines 264-421: `NavigationLink` extension with state parameter
3. Lines 111-148: `Perception.Bindable` + `UIBindable` scope extensions

**Critical detail on block 3:** `Perception.Bindable` is fully guarded out on Android (`#if canImport(SwiftUI) && !os(Android)` in `forks/swift-perception/.../Bindable.swift`). The `Perception.Bindable` scope extension CANNOT be enabled on Android because the type itself does not exist there. The guard on lines 111-128 is correct for `Perception.Bindable`. However, `UIBindable` (lines 130-147) IS available on Android (defined in `swift-navigation/Sources/SwiftNavigation/UIBindable.swift` with no Android guards). These two must be split.

**Action:** Remove the outer `#if !os(Android)` guard and add a targeted `#if !os(Android)` around ONLY the `Perception.Bindable` extension (lines 116-128). Leave `UIBindable` extension unguarded.

**Example (after):**
```swift
#if !os(Android)
@available(iOS, introduced: 13, obsoleted: 17)
// ...
extension Perception.Bindable {
  public func scope<...>(...) -> Binding<...> { ... }
}
#endif

extension UIBindable {
  public func scope<...>(...) -> UIBinding<...> { ... }
}
```

### Pattern 2: Guard Removal — Presentation Modifiers (Sheet, Alert, ConfirmationDialog)

**What:** The `Sheet.swift`, `Alert.swift`, `ConfirmationDialog.swift`, and `Alert+Observation.swift` files use `#if canImport(SwiftUI)` (no Android exclusion). They already compile on Android. The only Android guards within are on `.animatedSend` cases, which are correctly guarded (see I8).

**Key insight:** These files need NO guard changes. They already work on Android. The `#if !os(Android)` on the `.animatedSend` case is correct and must stay.

### Pattern 3: Guard Removal — EphemeralState

**What:** Remove `#if canImport(SwiftUI) && !os(Android)` from `EphemeralState.swift` lines 17-24.

**Why safe:** `AlertState` is pure Swift (UUID, [ButtonState], TextState?, TextState). `ConfirmationDialogState` is pure Swift (same pattern + `Visibility` enum). `ButtonState` core struct has no guards. `TextState` core struct has no guards (only the `modifiers` array and SwiftUI rendering extensions are guarded). The conformance `extension AlertState: _EphemeralState {}` adds zero new dependencies.

**Replace with:** Unconditional conformance (no `#if` at all), since `AlertState` and `ConfirmationDialogState` are always available.

```swift
@_documentation(visibility: private)
extension AlertState: _EphemeralState {}

@_documentation(visibility: private)
@available(iOS 13, macOS 12, tvOS 13, watchOS 6, *)
extension ConfirmationDialogState: _EphemeralState {}
```

### Pattern 4: Popover Fallback to Sheet

**What:** Replace entire-file `#if canImport(SwiftUI) && !os(Android)` guard in `Popover.swift` with platform split. On Android, delegate `.popover(store:)` to `.sheet(store:)`.

**Why:** Skip marks both `.popover(isPresented:)` and `.popover(item:)` as `@available(*, unavailable)`. Android has no native popover. Material3 bottom sheet is the platform-standard alternative.

**Example:**
```swift
#if canImport(SwiftUI)
import SwiftUI

#if !os(Android)
// Existing Darwin popover implementation
extension View {
  public func popover<State, Action, Content: View>(
    store: Store<PresentationState<State>, PresentationAction<Action>>,
    // ... existing code ...
  ) -> some View { ... }
}
#else
// Android: fall back to sheet
extension View {
  public func popover<State, Action, Content: View>(
    store: Store<PresentationState<State>, PresentationAction<Action>>,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge = .top,
    @ViewBuilder content: @escaping (_ store: Store<State, Action>) -> Content
  ) -> some View {
    self.sheet(store: store, content: content)
  }
}
#endif
#endif
```

### Pattern 5: NavigationStack Type Erasure Bridge (CONFIRMED INCOMPATIBLE — needs adapter)

**What:** Skip's `NavigationStack.init(path: Any)` force-casts to `Binding<[Any]>?`. TCA passes `Binding<StackState<State>.PathView>` where `PathView` is a custom struct conforming to `RandomAccessCollection` with `Element == Component`. **This cast crashes unconditionally** — Swift does not allow covariant casts of generic types (`Binding<PathView>` is not `Binding<[Any]>`).

**The modern TCA API** (`NavigationStack.init(path:root:destination:)` at NavigationStack+Observation.swift:150) also cannot work because it extends `NavigationStack<Data, Root>` — but Skip's `NavigationStack` is non-generic.

**Fix (Option A — recommended):** Add `#if os(Android)` branch inside `NavigationStackStore.body` that bridges `PathView` into `Binding<[Any]>`:

```swift
#if os(Android)
let pathBinding = Binding<[Any]>(
    get: { self.viewStore.state.path.map { $0 as Any } },
    set: { newPath in
        let currentPath = self.viewStore.state.path
        if newPath.count > currentPath.count,
           let last = newPath.last as? StackState<State>.Component {
            self.viewStore.send(.push(id: last.id, state: last.element))
        } else if newPath.count < currentPath.count {
            self.viewStore.send(.popFrom(id: currentPath[newPath.count].id))
        }
    }
)
NavigationStack(path: pathBinding) { ... }
#else
// existing iOS implementation
#endif
```

**Remaining risk:** Destination type routing — `navigationDestination(for: StackState<State>.Component.self)` must match Skip's `type(of: targetValue)` lookup through JVM generic erasure. Needs runtime verification.

See `research/nav-stack-type-erasure.md` for full type chain analysis and alternative fix options.

### Anti-Patterns to Avoid

- **DO NOT enable `store.send(_:animation:)`** — `withTransaction` is a `fatalError()` stub in Skip. The `#if !os(Android)` guard in `Store.swift:205` is correct.
- **DO NOT enable `.animatedSend` cases in Alert/ConfirmationDialog** — Same root cause. The non-animated `send(_:)` fallback is functionally correct.
- **DO NOT attempt to make `Perception.Bindable` work on Android** — The entire type is guarded out in swift-perception. Use `SwiftUI.Bindable` (available on Android via Skip) or `UIBindable` instead.
- **DO NOT enable deprecated TCA APIs** — `NavigationStackStore`, `SwitchStore`, legacy `BindingState` are deprecated and correctly guarded out.
- **DO NOT hand-roll NavigationStack** — Skip's implementation is complete. The work is making TCA's integration layer compile against it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stack navigation on Android | Custom Compose NavHost integration | Skip's NavigationStack + TCA's guard removal | Skip's Navigator handles route management, animations, back handling |
| Alert rendering on Android | Custom AlertDialog composable | Skip's AlertPresentation via SwiftUI `.alert()` API | Material3 dialog with role support already complete |
| Confirmation dialog on Android | Custom BottomSheet dialog | Skip's ConfirmationDialogPresentation | Action sheet style with cancel/destructive roles |
| Sheet presentation on Android | Custom ModalBottomSheet | Skip's SheetPresentation | Detent support, dismiss handling, safe area management |
| Popover on Android | Custom Compose Popup/DropdownMenu | Sheet fallback (D2) | Standard Android UX pattern, no anchor positioning needed |
| Type-based routing | Custom destination registry | Skip's `navigationDestination(for:destination:)` preference system | Skip aggregates destinations via PreferenceKey, handles type matching |
| Dismiss lifecycle | Custom dismiss mechanism | TCA's `PresentationReducer` + `DismissEffect` + Skip's `DismissAction` | Proven state-driven dismiss: nil state -> view reacts -> closes |

**Key insight:** Every presentation primitive needed already exists in either TCA's data layer (no guards) or Skip's Compose bridge (full implementations). The work is purely removing guards on the SwiftUI integration layer that connects them.

## Common Pitfalls

### Pitfall 1: NavigationStack Path Type Erasure Failure

**What goes wrong:** Skip's `NavigationStack.init(path: Any)` does `path as! Binding<[Any]>?`. TCA passes `Binding<StackState<Path.State>.PathView>`. If `PathView` doesn't survive the `as! Binding<[Any]>?` cast, it's nil and navigation breaks silently (no crash, just no path binding).
**Why it happens:** Swift's type system and Binding's covariance don't guarantee arbitrary collection types cast to `[Any]`.
**How to avoid:** Write a compile+runtime test that creates a `NavigationStack(path:root:destination:)` with a TCA store-scoped binding and verifies the path binding is non-nil inside the NavigationStack. If it fails, implement a `Binding` adapter shim that bridges `StackState.PathView` to `[Any]`.
**Warning signs:** Navigation destinations don't render. Push/pop has no effect. Path count stays at 0.

### Pitfall 2: _EphemeralState Not Enabled — Alerts Don't Auto-Dismiss

**What goes wrong:** Alert/dialog button taps send the action but the alert stays visible. User has to dismiss manually.
**Why it happens:** Without `_EphemeralState` conformance, `ephemeralType(of:)` returns nil, and `PresentationReducer` skips the `state[keyPath:].wrappedValue = nil` line (PresentationReducer.swift:624).
**How to avoid:** Enable `_EphemeralState` conformance unconditionally in EphemeralState.swift. Verify with a test that sends an alert button action and checks state becomes nil.
**Warning signs:** TestStore shows alert state is non-nil after button action was sent.

### Pitfall 3: Perception.Bindable vs SwiftUI.Bindable Confusion

**What goes wrong:** Code uses `Perception.Bindable` on Android, which doesn't exist, causing compilation failure.
**Why it happens:** On Darwin pre-iOS 17, TCA uses `Perception.Bindable` as a backport. On Android, neither `Perception.Bindable` nor `ObservedObject.Wrapper` exist. Only `SwiftUI.Bindable` (from Skip) is available.
**How to avoid:** Keep `Perception.Bindable` scope extension guarded on Android. The `SwiftUI.Bindable` extension (line 91-109) is NOT guarded with `!os(Android)` and already works. `UIBindable` also works unguarded. Test with `@Bindable var store: StoreOf<Feature>` (which uses `SwiftUI.Bindable` on Android).
**Warning signs:** Compilation error mentioning `Perception.Bindable` not found.

### Pitfall 4: withTransaction / Animated Send on Android

**What goes wrong:** Runtime crash (`fatalError`) when `withTransaction` is called.
**Why it happens:** Skip's `Transaction.swift:219` has `withTransaction` as a `fatalError()` stub. The `store.send(_:animation:)` and `.animatedSend` paths call it.
**How to avoid:** Keep ALL `#if !os(Android)` guards around animation-dependent send paths. Never enable `store.send(_:animation:)` or `store.send(_:transaction:)` on Android.
**Warning signs:** `fatalError` crash in `Transaction.swift` during alert button tap.

### Pitfall 5: FullScreenCover macOS Guard

**What goes wrong:** `FullScreenCover.swift` is guarded with `#if !os(macOS)`, NOT `#if !os(Android)`. On Android, macOS is not the target, so this guard passes — fullScreenCover is already available on Android.
**Why it happens:** The guard is platform-correct (fullScreenCover doesn't exist on macOS). No change needed.
**How to avoid:** Don't add an Android guard to FullScreenCover.swift. It already compiles correctly.
**Warning signs:** None — this is a non-issue noted for completeness.

### Pitfall 6: NavigationLink State Parameter on Android

**What goes wrong:** `NavigationLink.init(state:label:)` uses `@Dependency(\.stackElementID)` to create `StackState.Component` values. If Skip's NavigationLink doesn't support `value:` parameter, the link won't navigate.
**Why it happens:** Skip's `NavigationLink` stores a `value: Any?` and calls `navigator?.navigate(to: value)`. It should work, but the `StackState.Component` type must be Hashable (it is) and must be registered via `navigationDestination(for:)`.
**How to avoid:** The `_NavigationDestinationViewModifier` registers `StackState<State>.Component.self` as the destination type. Skip's `navigationDestination(for:)` uses `data.Type` as the key. Verify that `StackState<State>.Component.self` correctly registers as a type key in Skip's destination dictionary.
**Warning signs:** NavigationLink tap has no effect. Destination not found in Navigator's destination map.

## Code Examples

### NavigationStack with TCA Store (Modern Pattern)
```swift
// After guard removal, this compiles on Android
@Reducer
struct AppFeature {
  @ObservableState
  struct State {
    var path = StackState<Path.State>()
  }
  enum Action {
    case path(StackActionOf<Path>)
  }
  var body: some ReducerOf<Self> {
    Reduce { state, action in .none }
      .forEach(\.path, action: \.path) { Path() }
  }
  @Reducer
  enum Path {
    case detail(DetailFeature)
  }
}

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>

  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      RootView()
    } destination: { store in
      switch store.case {
      case .detail(let store):
        DetailView(store: store)
      }
    }
  }
}
```

### Alert with _EphemeralState Auto-Dismiss
```swift
@Reducer
struct Feature {
  @ObservableState
  struct State {
    @Presents var alert: AlertState<Action.Alert>?
  }
  enum Action {
    case alert(PresentationAction<Alert>)
    case deleteButtonTapped
    enum Alert {
      case confirmDeletion
    }
  }
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .deleteButtonTapped:
        state.alert = AlertState {
          TextState("Delete?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmDeletion) {
            TextState("Delete")
          }
        }
        return .none
      case .alert(.presented(.confirmDeletion)):
        // Handle deletion
        return .none
      case .alert:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)  // No destination reducer needed for _EphemeralState
  }
}
```

### Sheet with Store Binding (Modern Pattern)
```swift
struct ParentView: View {
  @Bindable var store: StoreOf<ParentFeature>

  var body: some View {
    Form {
      Button("Show Child") { store.send(.showChildTapped) }
    }
    .sheet(item: $store.scope(state: \.child, action: \.child)) { childStore in
      ChildView(store: childStore)
    }
  }
}
```

### Popover Fallback (Android)
```swift
// On Android, this renders as a sheet
ParentView()
  .popover(item: $store.scope(state: \.detail, action: \.detail)) { detailStore in
    DetailView(store: detailStore)
  }
```

### Dismiss Dependency
```swift
@Reducer
struct ChildFeature {
  @Dependency(\.dismiss) var dismiss

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .doneButtonTapped:
        return .run { _ in await self.dismiss() }  // Non-animated on Android
      }
    }
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NavigationStackStore` | `NavigationStack(path: $store.scope(...))` | TCA 1.7+ | Stack store is deprecated, modern uses Binding scope |
| `.sheet(store:)` | `.sheet(item: $store.scope(...))` | TCA 1.7+ | Store-based modifiers deprecated, modern uses item binding |
| `.alert(store:)` | `.alert($store.scope(...))` | TCA 1.7+ | Same migration as sheet |
| `@PresentationState` | `@Presents` | TCA 1.7+ | Macro replaces property wrapper |
| `Perception.Bindable` | `SwiftUI.Bindable` (iOS 17+) | Swift 5.9 / iOS 17 | Perception is backport; on Android, use native SwiftUI.Bindable from Skip |
| `ViewStore` / `WithViewStore` | Direct `store` access | TCA 1.7+ | Deprecated, do not use |

**Deprecated/outdated:**
- `NavigationStackStore`: Replaced by `NavigationStack(path:root:destination:)` with Binding scope
- `SwitchStore`: Replaced by `store.case` switching — correctly guarded out on Android
- Store-based `.sheet(store:)`, `.alert(store:)`, `.popover(store:)`: All deprecated in favor of item/binding variants
- `BindingState` / `BindingAction` legacy patterns: Replaced by `@BindableAction` + `BindingReducer()`

## Deep Dive Findings

Three deep dive investigations were completed on 2026-02-22. Full reports in `research/` subdirectory.

### NavigationStack Type Erasure — REQUIRES_ADAPTATION

**Report:** `research/nav-stack-type-erasure.md`

**Verdict:** Two blocking incompatibilities and one unknown:

| Layer | Problem | Severity |
|-------|---------|----------|
| Modern TCA API | `NavigationStack.init(path:)` extension is `#if !os(Android)` — does not compile because Skip's `NavigationStack` is non-generic | Blocking |
| Legacy `NavigationStackStore` | `Binding<PathView>` force-cast to `Binding<[Any]>?` crashes — `PathView` is a custom struct, not `Array<Any>` | Blocking |
| Destination routing | `StackState<State>.Component` type registration vs Skip's `type(of:)` lookup through JVM generics | Unknown — needs runtime verification |

**Recommended fix:** Add `#if os(Android)` branch in `NavigationStackStore.body` that bridges `PathView` into `Binding<[Any]>` with explicit push/pop semantics. This isolates the adaptation to a single file without touching Skip.

### ButtonState/TextState Guards — NO CHANGES NEEDED

**Report:** `research/button-text-state-guards.md`

**Verdict:** The fork is already correctly structured for Android:
- `AlertState`, `ConfirmationDialogState` — zero guards, fully cross-platform
- `ButtonState` struct — unguarded; only `.animatedSend` enum case guarded (correct)
- `TextState` struct — available with `.verbatim` and `.concatenated` storage
- Android bridges already provided: `Text.init(TextState)`, `Button.init(ButtonState)`, `ButtonRole.init(ButtonStateRole)`
- Modern view modifiers (`View.alert`, `View.confirmationDialog`) use `#if canImport(SwiftUI)` not `!os(Android)` — available on Android

**Remaining risks** (SkipUI integration, not guard-related):
1. Whether Skip implements `View.alert(_:isPresented:presenting:actions:message:)` — the `presenting:` overload
2. Whether `ForEach` works with `[ButtonState]` (Identifiable) inside alert action builders
3. Whether `Button(role:action:label:)` works in Skip's alert context

### _EphemeralState Dismiss Lifecycle — SAFE_TO_ENABLE

**Report:** `research/ephemeral-dismiss-lifecycle.md`

**Verdict:** Single-line change, no double-dismiss risk.

**Change:** `EphemeralState.swift:17` — remove `&& !os(Android)` from `#if canImport(SwiftUI) && !os(Android)`

**Why safe:** TCA's `Alert.swift` button closures send `.presented(action)` to the store (NOT `isPresented.set(false)`). The auto-dismiss nils state, the binding reflects it, Compose removes the dialog. No race condition because the TCA alert modifier controls the dismiss flow, not Skip's native button handler.

**Full dismiss lifecycle (with fix):**
1. User taps alert button in Compose
2. TCA's button closure sends `.presented(buttonAction)` to store
3. `PresentationReducer` processes it; `ephemeralType()` returns `AlertState.self`
4. Auto-dismiss fires: `state[keyPath: ...].wrappedValue = nil`
5. `PresentationStore` binding re-evaluates → `isPresented = false`
6. Compose recomposes, `AlertPresentation`'s `guard isPresented.get()` fails, dialog removed

### Updated Risk Map

| Area | Verdict | Effort | Confidence |
|------|---------|--------|------------|
| NavigationStack path binding | REQUIRES_ADAPTATION | Medium — bridge in `NavigationStackStore` | HIGH (source-verified crash) |
| ButtonState/TextState guards | ALREADY_DONE | None | HIGH (guards mapped line-by-line) |
| _EphemeralState enable | SAFE_TO_ENABLE | Trivial — 1 line change | HIGH (lifecycle traced end-to-end) |
| SkipUI alert `presenting:` overload | UNKNOWN | Needs runtime validation | LOW (not yet tested) |
| navigationDestination type routing | UNKNOWN | Needs Android emulator test | LOW (JVM type erasure unknown) |

## Open Questions (Updated)

### Resolved

1. **~~NavigationStack path type erasure~~** → **CONFIRMED INCOMPATIBLE.** `Binding<PathView>` cannot cast to `Binding<[Any]>?`. Fix: Android-specific adapter in `NavigationStackStore.body`.

2. **~~ButtonState/TextState guards blocking AlertState~~** → **NOT BLOCKING.** Fork already has correct Android bridges. No guard changes needed.

3. **~~_EphemeralState safety~~** → **SAFE TO ENABLE.** Single-line change with no double-dismiss risk.

### Still Open

1. **navigationDestination(for:) type registration with StackState.Component**
   - Skip stores destinations keyed by `data.Type` (metatype). TCA registers `StackState<State>.Component.self`.
   - JVM generic erasure may strip the generic parameter, making `type(of: component)` return an erased type that doesn't match the registration key.
   - Recommendation: Validate with runtime test on Android emulator. If matching fails, use `destinationKeyTransformer` or a string-based key.

2. **SkipUI `presenting:` alert overload**
   - SwiftUINavigation's `View.alert(_:isPresented:presenting:actions:message:)` uses the `presenting:` parameter form.
   - Skip may only implement `View.alert(_:isPresented:actions:)` without `presenting:`.
   - If missing, TCA's alert modifier will fail at runtime. Needs Skip source verification or runtime test.

3. **openSettings on Android**
   - Not in TCA's dependency system. Likely purely a SwiftUI `@Environment(\.openSettings)` concern.
   - Low priority — document as N/A for this phase if not found in TCA deps.

## Sources

### Primary (HIGH confidence)
- Direct source code analysis of all fork files listed in Standard Stack table
- Skip NavigationStack implementation: `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/Navigation.swift`
- Skip Presentation implementation: `forks/skip-ui/Sources/SkipUI/SkipUI/Layout/Presentation.swift`
- TCA NavigationStack+Observation: `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/NavigationStack+Observation.swift`
- TCA PresentationReducer: `forks/swift-composable-architecture/Sources/ComposableArchitecture/Reducer/Reducers/PresentationReducer.swift`
- TCA EphemeralState: `forks/swift-composable-architecture/Sources/ComposableArchitecture/Internal/EphemeralState.swift`
- swift-navigation AlertState/ButtonState/TextState: `forks/swift-navigation/Sources/SwiftNavigation/`
- Perception Bindable: `forks/swift-perception/Sources/PerceptionCore/SwiftUI/Bindable.swift`

### Secondary (MEDIUM confidence)
- Phase 5 Context document (05-CONTEXT.md) — user decisions and discovered issues from discuss-phase session
- Prior project state (STATE.md) — accumulated decisions from Phases 1-4

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components verified via direct source code reading
- Architecture patterns: HIGH — guard locations and contents confirmed line-by-line
- Pitfalls: HIGH for pitfalls 2-5 (verified in source); MEDIUM for pitfall 1 (type erasure is runtime behavior that can't be verified statically)
- Code examples: HIGH — patterns match TCA documentation and current API

**Research date:** 2026-02-22
**Valid until:** 2026-03-22 (stable — fork code is under project control)
