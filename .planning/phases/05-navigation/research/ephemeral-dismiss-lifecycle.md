# _EphemeralState Protocol & Dismiss Lifecycle on Android

## 1. _EphemeralState Protocol Definition

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Internal/EphemeralState.swift`

### Protocol definition (lines 8-11)

```swift
public protocol _EphemeralState<Action> {
  associatedtype Action
  static var actionType: Any.Type { get }
}
```

Default implementation (lines 13-15):
```swift
extension _EphemeralState {
  public static var actionType: Any.Type { Action.self }
}
```

### Conformances — blocked on Android (lines 17-24)

```swift
#if canImport(SwiftUI) && !os(Android)       // <-- THE GUARD
@_documentation(visibility: private)
extension AlertState: _EphemeralState {}

@_documentation(visibility: private)
@available(iOS 13, macOS 12, tvOS 13, watchOS 6, *)
extension ConfirmationDialogState: _EphemeralState {}
#endif
```

`AlertState` is defined in `forks/swift-navigation/Sources/SwiftNavigation/AlertState.swift:134`.
`ConfirmationDialogState` is defined in `forks/swift-navigation/Sources/SwiftNavigation/ConfirmationDialogState.swift:119`.

Both are plain Swift structs with no platform-specific code. The `#if !os(Android)` guard is purely on the _conformance_, not on the types themselves.

### Helper functions (lines 27-48)

```swift
func ephemeralType<State>(of state: State) -> (any _EphemeralState.Type)? {
  (State.self as? any _EphemeralState.Type)
    ?? EnumMetadata(type(of: state)).flatMap { metadata in
      metadata.associatedValueType(forTag: metadata.tag(of: state))
        as? any _EphemeralState.Type
    }
}

func isEphemeral<State>(_ state: State) -> Bool {
  ephemeralType(of: state) != nil
}
```

The `ephemeralType` function first checks direct conformance, then uses `EnumMetadata` reflection to check if the _associated value_ of an enum case conforms. This is how `Destination.State` enums (e.g., `.alert(AlertState)`) are detected as ephemeral even when the top-level type is not `_EphemeralState`.

`canSend` (lines 42-47) checks whether an action type matches the ephemeral state's expected action type, also using enum metadata reflection for nested action enums.

---

## 2. PresentationReducer Dismiss Flow

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Reducer/Reducers/PresentationReducer.swift`

### The `reduce` method (line 586) — three critical branches:

#### Branch 1: Explicit `.dismiss` action (lines 594-601)

```swift
case let (.some(destinationState), .some(.dismiss)):
  destinationEffects = .none
  baseEffects = self.base.reduce(into: &state, action: action)
  if self.navigationIDPath(for: destinationState)
    == state[keyPath: self.toPresentationState].wrappedValue.map(self.navigationIDPath(for:))
  {
    state[keyPath: self.toPresentationState].wrappedValue = nil   // <-- STATE NILLED
  }
```

When `.dismiss` is sent explicitly, the parent reducer runs first, then state is set to `nil`. **_EphemeralState is NOT involved here** — this path always works.

#### Branch 2: `.presented(action)` — THE EPHEMERAL AUTO-DISMISS (lines 603-625)

```swift
case let (.some(destinationState), .some(.presented(destinationAction))):
  // ... destination reducer runs ...
  baseEffects = self.base.reduce(into: &state, action: action)

  if let ephemeralType = ephemeralType(of: destinationState),        // LINE 619
    destinationNavigationIDPath
      == state[keyPath: self.toPresentationState].wrappedValue.map(self.navigationIDPath(for:)),
    ephemeralType.canSend(destinationAction)                         // LINE 622
  {
    state[keyPath: self.toPresentationState].wrappedValue = nil      // LINE 624 — AUTO-NIL
  }
```

**This is the critical auto-dismiss logic.** After processing any `.presented(action)` on ephemeral state:
1. Check if the current state IS ephemeral (via `ephemeralType`)
2. Verify the navigation identity hasn't changed
3. Verify the action type matches what the ephemeral state expects
4. If all true: **automatically nil out the state**

This means: when a user taps an alert button, the button action is sent as `.presented(buttonAction)`, and the PresentationReducer automatically nils the state — the developer never needs to manually dismiss.

#### Branch 3: Effect cancellation — ephemeral exemption (lines 660-675)

```swift
if presentationIdentityChanged,
  let presentedPath = initialPresentationState.presentedID,
  initialPresentationState.wrappedValue.map({
    self.navigationIDPath(for: $0) == presentedPath && !isEphemeral($0)   // LINE 668
  })
    ?? true
{
  dismissEffects = ._cancel(navigationID: presentedPath)
}
```

Ephemeral states skip the effect cancellation dance — they have no long-running effects to cancel.

#### Branch 4: Present effect setup — ephemeral exemption (lines 681-697)

```swift
if presentationIdentityChanged || state[keyPath: self.toPresentationState].presentedID == nil,
  let presentationState = state[keyPath: self.toPresentationState].wrappedValue,
  !isEphemeral(presentationState)                                          // LINE 684
{
  // ... sets up a long-lived effect that emits .dismiss when cancelled ...
}
```

Ephemeral states do NOT get the `presentedID` tracking or the long-lived effect. This is by design — alerts/dialogs are fire-and-forget.

### Also: IfLetReducer (line 262)

```swift
// forks/.../Reducer/Reducers/IfLetReducer.swift:259-264
if childIDAfter == childIDBefore,
  self.toChildAction.extract(from: action) != nil,
  let childState = state[keyPath: self.toChildState],
  isEphemeral(childState)
{
  state[keyPath: toChildState] = nil
}
```

Same auto-dismiss pattern for `ifLet` (non-presentation variant).

---

## 3. @Presents Macro

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/Macros.swift:140-147`

```swift
/// Wraps a property with ``PresentationState`` and observes it.
///
/// Use this macro instead of ``PresentationState`` when you adopt the ``ObservableState()``
/// macro, which is incompatible with property wrappers like ``PresentationState``.
@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(`$`), prefixed(_))
public macro Presents() =
  #externalMacro(module: "ComposableArchitectureMacros", type: "PresentsMacro")
```

`@Presents` is syntactic sugar that generates a `PresentationState<T>` wrapper with observation tracking. Given:

```swift
@Presents var destination: Destination.State?
```

The macro generates:
- A backing `_destination: PresentationState<Destination.State>` property
- A `$destination` projected value for use with `.ifLet(\.$destination, ...)`
- Observation accessors that notify the `ObservationStateRegistrar`

The connection to PresentationReducer: `.ifLet(\.$destination, action: \.destination)` creates a `_PresentationReducer` that watches the `PresentationState<Destination.State>` and processes `PresentationAction<Destination.Action>`.

---

## 4. SwiftUI Sheet/Alert Dismiss Binding (TCA side)

### PresentationModifier.swift — the binding bridge

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/PresentationModifier.swift`

`PresentationStore.body` (lines 306-327) creates a `Binding<AnyIdentifiable?>`:

```swift
self.viewStore.binding(
  get: {
    $0.wrappedValue.flatMap(toDestinationState) != nil
      ? toID($0).map { AnyIdentifiable(Identified($0) { $0 }) }
      : nil
  },
  compactSend: { [weak viewStore = self.viewStore] in
    guard
      let viewStore = viewStore,
      $0 == nil,                    // When SwiftUI sets to nil (user dismisses)
      viewStore.wrappedValue != nil,
      id == nil || self.toID(viewStore.state) == id
    else { return nil }
    return .dismiss                 // Send .dismiss action to store
  }
)
```

This binding converts between:
- **Store state -> SwiftUI**: `wrappedValue != nil` means `isPresented = true`
- **SwiftUI -> Store**: Setting binding to `nil`/`false` sends `.dismiss` to the store

### Alert.swift — how TCA alert connects

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/Alert.swift:70-108`

```swift
private func _alert<State, Action, ButtonAction>(...) -> some View {
  self.presentation(
    store: store, state: toDestinationState, action: fromDestinationAction
  ) { `self`, $isPresented, destination in
    let alertState = store.withState { $0.wrappedValue.flatMap(toDestinationState) }
    self.alert(
      ...,
      isPresented: $isPresented,    // <-- Binding from PresentationStore
      presenting: alertState,
      actions: { alertState in
        ForEach(alertState.buttons) { button in
          Button(role: ...) {
            // When button tapped:
            store.send(.presented(fromDestinationAction(action)))  // LINE 89
          }
        }
      }
    )
  }
}
```

**The key flow on iOS:**
1. User taps alert button
2. SwiftUI calls the Button action closure
3. `store.send(.presented(buttonAction))` is dispatched
4. PresentationReducer receives `.presented(buttonAction)` in Branch 2
5. `ephemeralType(of: destinationState)` returns `AlertState` as ephemeral type (because `AlertState: _EphemeralState`)
6. `ephemeralType.canSend(destinationAction)` confirms the action type matches
7. State is auto-nilled: `state[keyPath: ...].wrappedValue = nil`
8. The `PresentationStore` binding re-evaluates: `wrappedValue == nil` -> `isPresented = false`
9. SwiftUI dismisses the alert

---

## 5. Skip's Dismiss Mechanism

### AlertPresentation (Skip/Android side)

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Layout/Presentation.swift`

#### AlertPresentation (lines 464-577)

```swift
@Composable func AlertPresentation(
  title: Text? = nil, ...,
  isPresented: Binding<Bool>,
  ...
) {
  guard isPresented.get() else { return }          // LINE 465 — reactive guard
  // ... build dialog ...
  SkipAlertDialog(
    onDismissRequest: { isPresented.set(false) },  // LINE 530 — background tap
    confirmButton: {
      TextButton(onClick: {
        isPresented.set(false)                      // LINE 534 — button tap
        confirmAction?()                            // then run action
      })
    },
    dismissButton: ... {
      TextButton(onClick: {
        isPresented.set(false)                      // LINE 550 — cancel button
        dismissAction?()
      })
    }
  )
}
```

**Critical observation:** Skip's `AlertPresentation` sets `isPresented.set(false)` **BEFORE** calling the action closure. This is the opposite order from SwiftUI's native alert, where the button action fires first and the alert dismisses after.

#### AlertButton helper (lines 655-669)

```swift
@Composable func AlertButton(...) {
  Box(modifier: modifier.clickable(onClick: {
    isPresented.set(false)     // Dismiss first
    action?()                  // Then run action
  }))
}
```

Same pattern — dismiss before action.

#### SheetPresentation (lines 94-226)

```swift
let onDismissRequest = { isPresented.set(false) }
ModalBottomSheet(onDismissRequest: onDismissRequest, ...)
```

Sheets use `isPresented` binding reactively. When `isPresented.get()` becomes `false` (from state nilling), the `LaunchedEffect` at lines 216-225 hides the sheet:

```swift
if !isPresentedValue {
  LaunchedEffect(true) {
    if sheetState.targetValue != SheetValue.Hidden {
      sheetState.hide()
    }
    // ...
  }
}
```

**Skip DOES observe binding changes reactively** via Compose's `mutableStateOf` / `rememberSaveable` and the `Binding.get()` calls inside `@Composable` functions. When TCA nils the state, the binding flips, and Compose recomposes to remove the dialog/sheet.

---

## 6. End-to-End Lifecycle Trace

### Sequence Diagram — Alert dismiss on iOS (working)

```
User               SwiftUI Alert      TCA Alert.swift    PresentationReducer    PresentationStore
 |                     |                    |                    |                      |
 |--tap button-------->|                    |                    |                      |
 |                     |--action closure--->|                    |                      |
 |                     |                    |--store.send------->|                      |
 |                     |                    | .presented(action) |                      |
 |                     |                    |                    |--ephemeralType()----->|
 |                     |                    |                    |  returns AlertState   |
 |                     |                    |                    |--canSend() = true---->|
 |                     |                    |                    |--state = nil--------->|
 |                     |                    |                    |                      |
 |                     |                    |                    |            binding re-evaluates
 |                     |                    |                    |            isPresented = false
 |                     |<---dismiss---------|--------------------|-----------binding----|
 |                     |                    |                    |                      |
```

### Sequence Diagram — Alert dismiss on Android (CURRENT — broken)

```
User               Compose Alert      TCA Alert.swift    PresentationReducer    PresentationStore
 |                     |                    |                    |                      |
 |--tap button-------->|                    |                    |                      |
 |                     |--isPresented=false--|                    |                      |
 |                     |--action()--------->|                    |                      |
 |                     |                    |--store.send------->|                      |
 |                     |                    | .presented(action) |                      |
 |                     |                    |                    |--ephemeralType()----->|
 |                     |                    |                    |  returns nil (!)      |
 |                     |                    |                    |  AlertState is NOT    |
 |                     |                    |                    |  _EphemeralState      |
 |                     |                    |                    |                      |
 |                     |                    |                    |  STATE NOT NILLED     |
 |                     |                    |                    |  (no auto-dismiss)    |
 |                     |                    |                    |                      |
 |   Dialog already gone (Compose side)     |    State still non-nil (TCA side)        |
 |   STATE DESYNC: TCA thinks alert is      |    still presented                       |
 |   showing but Compose already removed it |                                          |
```

**The state desync:** On Android, Skip dismisses the dialog via `isPresented.set(false)` from the Compose button handler. But the `PresentationStore` binding's `compactSend` fires `.dismiss` to the store. Meanwhile, the action closure also fires `store.send(.presented(buttonAction))`. The problem is:

1. Without `_EphemeralState` conformance, `ephemeralType()` returns `nil`
2. The auto-dismiss in Branch 2 (line 619-624) does NOT fire
3. However, the `.dismiss` from the binding set(false) DOES fire (via `compactSend`)
4. These two actions race, and depending on ordering, the state may or may not clean up correctly

Actually, let me re-examine more carefully. Skip's alert directly calls `isPresented.set(false)`, which flows through the `PresentationStore` binding's setter. The `compactSend` closure sends `.dismiss`. So the dismiss DOES happen from the binding side. But the `.presented(action)` is also sent. The question is whether both get processed correctly.

### Sequence Diagram — Alert dismiss on Android (WITH _EphemeralState enabled)

```
User               Compose Alert      TCA Alert.swift    PresentationReducer    PresentationStore
 |                     |                    |                    |                      |
 |--tap button-------->|                    |                    |                      |
 |                     |--isPresented=false--|                    |           compactSend|
 |                     |                    |                    |<--.dismiss------------|
 |                     |--action()--------->|                    |                      |
 |                     |                    |--store.send------->|                      |
 |                     |                    | .presented(action) |                      |
 |                     |                    |                    |--ephemeralType()----->|
 |                     |                    |                    |  returns AlertState   |
 |                     |                    |                    |--canSend() = true     |
 |                     |                    |                    |--state = nil (again)  |
 |                     |                    |                    |                      |
 |                     |                    |                    |  Clean: state is nil  |
 |                     |                    |                    |  Both paths agree     |
```

---

## 7. What Breaks WITHOUT _EphemeralState (Current Android Behavior)

### Problem 1: No auto-dismiss after button action

When a button action is sent via `.presented(buttonAction)`, the PresentationReducer's ephemeral auto-dismiss at line 619-624 does NOT fire. The state remains non-nil after the action is processed.

**Impact:** If the developer relies on the auto-dismiss behavior (which is the standard TCA pattern for alerts), the state stays stale. Subsequent attempts to show a new alert may fail or show stale data because `destination` is still non-nil with the old alert.

### Problem 2: Double-action race

Skip's `AlertButton` calls `isPresented.set(false)` then `action()`. This means:
1. The binding setter fires `.dismiss` to the store
2. The action closure fires `store.send(.presented(buttonAction))`

Without ephemeral detection, `.dismiss` nils the state first. Then `.presented(buttonAction)` arrives and hits the `.none, .some` branch (lines 631-657), triggering a `reportIssue` warning:

> An "ifLet" received a presentation action when destination state was absent.

This is a runtime warning/test failure but not a crash.

### Problem 3: Missing convenience `ifLet` overload

The `ifLet` overload at line 437 requires `DestinationState: _EphemeralState`:

```swift
public func ifLet<DestinationState: _EphemeralState, DestinationAction>(
  _ toPresentationState: ...,
  action toPresentationAction: ...,
  // NO `destination:` parameter — no child reducer needed
) -> some Reducer<State, Action>
```

Without the conformance, developers must provide an empty `destination: {}` closure for alerts. This is ergonomic friction, not a functional blocker.

### Problem 4: Effect lifecycle mismatch

The `presentedID` tracking and long-lived dismiss effect (lines 681-697) are gated on `!isEphemeral(presentationState)`. Without ephemeral detection:
- A `presentedID` is set for alert states
- A long-lived effect is created that emits `.dismiss` when cancelled
- This effect is unnecessary for alerts and adds overhead

---

## 8. What Enables Correctly WITH _EphemeralState

### Auto-dismiss works

`ephemeralType(of: alertState)` returns `AlertState.self`, so Branch 2 auto-nils the state after any button action. This is the canonical TCA behavior.

### No stale state

State is guaranteed to be nilled after button interaction, preventing stale alert state from accumulating.

### Convenience overload available

The `ifLet` overload without `destination:` parameter becomes usable for alerts and confirmation dialogs on Android.

### Correct effect lifecycle

Ephemeral states are exempt from `presentedID` tracking and long-lived effects, matching iOS behavior.

---

## 9. Risk Analysis

### Risk 1: Double-dismiss (LOW)

**Scenario:** Skip calls `isPresented.set(false)` (sends `.dismiss`) AND the ephemeral auto-dismiss nils the state.

**Analysis:** This is safe. The `.dismiss` action arrives first (from binding setter), which nils the state via Branch 1 (line 600). When `.presented(buttonAction)` arrives, the state is already nil, hitting the `.none, .some` branch (line 631). This fires `reportIssue` — BUT this is exactly the same race that happens on iOS when SwiftUI dismisses an alert. TCA handles this gracefully; the `reportIssue` is a diagnostic, not a crash.

**Wait — re-examining the order.** In Skip, the onClick handler runs synchronously:
```swift
onClick: { isPresented.set(false); confirmAction?() }
```

Both calls happen in the same synchronous scope. The binding's `compactSend` sends `.dismiss`. Then `confirmAction()` calls `store.send(.presented(action))`. These are sequential store sends. The store processes them in order:

1. `.dismiss` -> Branch 1 -> state nilled
2. `.presented(action)` -> `.none, .some` -> `reportIssue` warning

This is a minor issue but it is the **existing behavior** even without `_EphemeralState`. Enabling ephemeral doesn't make this worse.

Actually, looking more carefully at TCA's `Alert.swift` (line 86-96), the button actions send `.presented(fromDestinationAction(action))` directly to the store. But this is the TCA-specific alert modifier that uses `PresentationStore`. Skip's native alert buttons (from `Presentation.swift`) call `isPresented.set(false)` then `action()`. The TCA alert modifier's buttons call `store.send(.presented(...))` without setting isPresented.

**The two codepaths are separate:**
- **TCA `.alert(store:)`** (Alert.swift) — uses `PresentationStore` binding; button sends `.presented(action)` to store; SwiftUI/Skip handles dismiss via binding
- **SwiftUI `.alert(isPresented:)`** (Presentation.swift) — pure SwiftUI alert with `isPresented` binding; button calls `isPresented.set(false)` then `action()`

When using TCA's `.alert(store:)`, the flow is:
1. Button tapped in SwiftUI/Compose
2. TCA's Button closure runs: `store.send(.presented(fromDestinationAction(action)))`
3. PresentationReducer processes it, auto-dismiss fires (with ephemeral), state nilled
4. `PresentationStore` binding re-evaluates -> `isPresented` becomes `false`
5. SwiftUI/Compose dismisses dialog

**This is clean.** No double-dismiss because the TCA Alert.swift buttons do NOT call `isPresented.set(false)` — they only send to the store.

### Risk 2: EnumMetadata reflection on Android (MEDIUM-LOW)

`ephemeralType` relies on `@_spi(Reflection) import CasePaths` and `EnumMetadata` for detecting ephemeral associated values in destination enums. This uses Swift runtime metadata.

**Analysis:** This same reflection is already used elsewhere in TCA on Android (case paths, enum extraction, etc.). If it works for action routing, it works for ephemeral detection. The `CasePaths` package is already a dependency.

### Risk 3: ReducerMacro `isEphemeral` check (LOW)

The `@Reducer` macro has compile-time `isEphemeral` checks in `ReducerMacro.swift` (lines 159, 186, 526, 763, 775, 782). These check for `AlertState` and `ConfirmationDialogState` by name to generate appropriate reducer code.

**Analysis:** The macro runs at compile time and generates code that uses `_EphemeralState` at runtime. The macro's name-based check is platform-independent. The only platform gate is the _conformance_ in EphemeralState.swift line 17. Removing the `!os(Android)` guard makes the conformance available, and the macro-generated code will work correctly.

### Risk 4: animatedSend unavailable on Android (ALREADY HANDLED)

In both `Alert.swift:91-96` and `ConfirmationDialog.swift:96-101`:
```swift
#if !os(Android)
case let .animatedSend(action, animation):
  if let action {
    store.send(.presented(fromDestinationAction(action)), animation: animation)
  }
#endif
```

This is already guarded. Enabling `_EphemeralState` doesn't affect this.

---

## 10. Verdict: SAFE_TO_ENABLE

### Change required

In `forks/swift-composable-architecture/Sources/ComposableArchitecture/Internal/EphemeralState.swift`, line 17:

```swift
// BEFORE:
#if canImport(SwiftUI) && !os(Android)

// AFTER:
#if canImport(SwiftUI)
```

### Why it's safe

1. **No double-dismiss risk with TCA alerts:** The TCA `Alert.swift` button closures send `.presented(action)` to the store, NOT `isPresented.set(false)`. The auto-dismiss nils state, the binding reflects it, and Compose removes the dialog. Single clean path.

2. **Skip's reactive binding works:** `AlertPresentation` guards on `isPresented.get()` — when TCA nils the state and the binding flips to `false`, Compose recomposes and the dialog vanishes.

3. **No new runtime dependencies:** `EnumMetadata` reflection and `CasePaths` already work on Android.

4. **Matches iOS behavior exactly:** The auto-dismiss, effect lifecycle exemptions, and convenience overloads all become consistent cross-platform.

5. **Fixes existing state desync:** Without ephemeral, the `.presented(action)` path does NOT auto-nil, which can leave stale alert state in the TCA store. Enabling ephemeral eliminates this class of bugs.

### One caveat

If anyone uses Skip's vanilla `.alert(isPresented:)` (NOT the TCA store-based version) with a TCA-managed binding, the `isPresented.set(false)` + `action()` pattern in Skip's `AlertButton` will still produce the existing double-send. But this is not a regression — it's the current behavior, and enabling `_EphemeralState` doesn't make it worse. The canonical TCA pattern uses `.alert(store:)`.
