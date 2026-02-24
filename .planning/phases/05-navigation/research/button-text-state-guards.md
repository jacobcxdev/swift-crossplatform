# ButtonState & TextState Android Guards -- Impact on AlertState Rendering

**Date:** 2026-02-22
**Scope:** `forks/swift-navigation/` and `forks/swift-composable-architecture/`

---

## 1. Complete Guard Inventory

### 1.1 ButtonState.swift (`SwiftNavigation/ButtonState.swift`)

| Line(s) | Guard | What's Guarded | Category |
|---------|-------|---------------|----------|
| 5-7 | `#if canImport(SwiftUI) && !os(Android)` | `import SwiftUI` | Import |
| 66-71 | `#if canImport(SwiftUI) && !os(Android)` | `withAction()` sync: `.animatedSend` case branch | Core logic (animation path) |
| 86-102 | `#if canImport(SwiftUI) && !os(Android)` | `withAction()` async: `.animatedSend` case branch + warning | Core logic (animation path) |
| 129-133 | `#if canImport(SwiftUI) && !os(Android)` | `ButtonStateAction.send(_:animation:)` static factory | Core API (animation factory) |
| 137-140 | `#if canImport(SwiftUI) && !os(Android)` | `ButtonStateAction.action` getter: `.animatedSend` case | Core logic |
| 150-153 | `#if canImport(SwiftUI) && !os(Android)` | `ButtonStateAction.map()`: `.animatedSend` case | Core logic |
| 161-163 | `#if canImport(SwiftUI) && !os(Android)` | `_ActionType.animatedSend` enum case definition | **Core data type** |
| 209-218 | `#if canImport(SwiftUI) && !os(Android)` | `CustomDumpReflectable`: `.animatedSend` case | Debug support |
| 238-241 | `#if canImport(SwiftUI) && !os(Android)` | `Hashable`: `.animatedSend` case in `hash(into:)` | Protocol conformance |
| 260-357 | `#if canImport(SwiftUI) && !os(Android)` | SwiftUI bridging: `Alert.Button.init`, `ButtonRole.init`, `Button.init` extensions | **SwiftUI view code** |
| 391-431 | `#if os(Android)` | Android-specific SwiftUI bridging: `ButtonRole.init`, `Button.init` | **Android replacement** |

**Key insight:** The `ButtonState` struct itself (lines 9-119) is **NOT guarded** -- it compiles on all platforms. The `#if` guards inside it only affect the `.animatedSend` enum case and its handling. On Android, `_ActionType` only has `.send`, which is sufficient for AlertState rendering. The Android block at lines 391-431 already provides `ButtonRole.init` and `Button.init` extensions for Skip/SwiftUI on Android.

### 1.2 ButtonStateBuilder.swift (`SwiftNavigation/ButtonStateBuilder.swift`)

**No guards at all.** Fully available on all platforms.

### 1.3 TextState.swift (`SwiftNavigation/TextState.swift`)

| Line(s) | Guard | What's Guarded | Category |
|---------|-------|---------------|----------|
| 4-6 | `#if canImport(SwiftUI) && !os(Android)` | `import SwiftUI` | Import |
| 54-115 | `#if canImport(SwiftUI) && !os(Android)` | `modifiers` property, `Modifier` enum, `FontWidth` enum, `LineStylePattern` enum | **Rich text styling** |
| 121-129 | `#if canImport(SwiftUI) && !os(Android)` | `Storage.localizedStringKey` and `.localizedStringResource` cases | **Core data type** (localization storage) |
| 143-183 | `#if canImport(SwiftUI) && !os(Android)` | `Storage.==` cases for localized comparisons | Equality logic |
| 192-198 | `#if canImport(SwiftUI) && !os(Android)` | `Storage.hash(into:)` for localized cases | Hashing logic |
| 209-245 | `#if canImport(SwiftUI) && !os(Android)` | `LocalizedStringResourceBox` private struct | Localization support |
| 259-282 | `#if canImport(SwiftUI) && !os(Android)` | `TextState.init(_:LocalizedStringKey)` and `TextState.init(_:LocalizedStringResource)` | **API constructors** (localization) |
| 288-404 | `#if canImport(SwiftUI) && !os(Android)` | All rich text modifier methods (`.bold()`, `.font()`, `.italic()`, etc.) | Rich text API |
| 409-665 | `#if canImport(SwiftUI) && !os(Android)` | Accessibility enums, `Text.init(_ state: TextState)` SwiftUI bridge, all modifier application | **SwiftUI view code** |
| 674-685 | `#if canImport(SwiftUI) && !os(Android)` | `String.init(state:)` localized cases | String conversion |
| 693-731 | `#if canImport(SwiftUI) && !os(Android)` | `LocalizedStringKey.formatted()` helper | Localization utility |
| 742-747 | `#if canImport(SwiftUI) && !os(Android)` | `customDumpValue` localized cases | Debug support |
| 758-841 | `#if canImport(SwiftUI) && !os(Android)` | `customDumpValue` modifier rendering | Debug support |
| 849-874 | `#if os(Android)` | Android-specific `Text.init(_ state:)` and `_plainText` helper | **Android replacement** |

**Key insight:** `TextState` struct itself is available on Android with two storage cases: `.concatenated` and `.verbatim`. The `init(verbatim:)` and `init<S: StringProtocol>(_:)` constructors work on Android. The Android block (849-874) provides a `Text.init(_ state: TextState)` bridge that flattens to plain text. AlertState only needs `TextState` for titles and messages, which works fine with verbatim strings.

### 1.4 AlertState.swift (`SwiftNavigation/AlertState.swift`)

**No `#if` guards at all.** The entire `AlertState` struct, including its initializers, `map`, `Equatable`, `Hashable`, `Sendable`, and `CustomDumpReflectable` conformances, compiles unconditionally on all platforms.

### 1.5 ConfirmationDialogState.swift (`SwiftNavigation/ConfirmationDialogState.swift`)

**No `#if` guards at all.** Same as AlertState -- fully cross-platform. `ConfirmationDialogStateTitleVisibility` enum is also unguarded.

### 1.6 Alert.swift (`SwiftUINavigation/Alert.swift`)

| Line(s) | Guard | What's Guarded | Category |
|---------|-------|---------------|----------|
| 1 | `#if canImport(SwiftUI)` | Entire file | SwiftUI dependency |
| 152-168 | (inside `#if canImport(SwiftUI)`) | `View.alert(_:AlertState, action:)` sync -- the main AlertState view modifier | **SwiftUI view modifier** |
| 185-198 | (inside `#if canImport(SwiftUI)`) | `View.alert(_:AlertState, action:)` async variant | **SwiftUI view modifier** |
| 201-278 | `#if !os(Android)` | Legacy `Alert.init(_ state: AlertState)` (deprecated iOS 13-era API) | **Legacy SwiftUI code** |

**Key insight:** The modern `View.alert(_:AlertState)` modifiers (lines 152-198) are inside `#if canImport(SwiftUI)` but **NOT** inside `#if !os(Android)`. They are available on Android. Only the deprecated `Alert.init` legacy API is excluded from Android, which is correct since SkipUI doesn't have the old `Alert` type.

### 1.7 ConfirmationDialog.swift (`SwiftUINavigation/ConfirmationDialog.swift`)

| Line(s) | Guard | What's Guarded | Category |
|---------|-------|---------------|----------|
| 1 | `#if canImport(SwiftUI)` | Entire file | SwiftUI dependency |
| 175-224 | (inside `#if canImport(SwiftUI)`) | `View.confirmationDialog(_:ConfirmationDialogState, action:)` modifiers | **SwiftUI view modifier** |
| 227-266 | `#if !os(Android)` | Legacy `ActionSheet.init` (deprecated) | **Legacy SwiftUI code** |

**Same pattern as Alert.swift.** Modern API is available on Android; only legacy `ActionSheet` is excluded.

### 1.8 TCA Alert.swift (`ComposableArchitecture/SwiftUI/Alert.swift`)

| Line(s) | Guard | What's Guarded | Category |
|---------|-------|---------------|----------|
| 1 | `#if canImport(SwiftUI)` | Entire file | SwiftUI dependency |
| 91-96 | `#if !os(Android)` | `.animatedSend` case in button action switch | Animation path |

**Key insight:** The TCA alert modifier is gated only by `#if canImport(SwiftUI)`, NOT by `!os(Android)`. It IS available on Android. The only Android exclusion is the `.animatedSend` case, which is correct since that enum case doesn't exist on Android.

### 1.9 TCA ConfirmationDialog.swift (`ComposableArchitecture/SwiftUI/ConfirmationDialog.swift`)

| Line(s) | Guard | What's Guarded | Category |
|---------|-------|---------------|----------|
| 1 | `#if canImport(SwiftUI)` | Entire file | SwiftUI dependency |
| 96-100 | `#if !os(Android)` | `.animatedSend` case in button action switch | Animation path |

**Identical pattern to TCA Alert.swift.** Available on Android, animation case correctly excluded.

---

## 2. Dependency Chain Diagram

```
AlertState<Action>
  |
  +-- title: TextState                    [UNGUARDED - available on Android]
  |     |
  |     +-- Storage.verbatim(String)      [UNGUARDED]
  |     +-- Storage.concatenated           [UNGUARDED]
  |     +-- Storage.localizedStringKey     [GUARDED OUT on Android]
  |     +-- Storage.localizedStringResource [GUARDED OUT on Android]
  |     +-- modifiers: [Modifier]          [GUARDED OUT on Android - no rich text]
  |
  +-- message: TextState?                 [UNGUARDED - same as title]
  |
  +-- buttons: [ButtonState<Action>]      [UNGUARDED - available on Android]
        |
        +-- id: UUID                      [UNGUARDED]
        +-- label: TextState              [UNGUARDED - same as above]
        +-- role: ButtonStateRole?        [UNGUARDED - cancel/destructive]
        +-- action: ButtonStateAction     [UNGUARDED]
              |
              +-- _ActionType.send        [UNGUARDED]
              +-- _ActionType.animatedSend [GUARDED OUT on Android]


View.alert(_: Binding<AlertState?>, action:)     -- SwiftUINavigation/Alert.swift
  |
  +-- Text.init(_ state: TextState)               [PROVIDED on Android at TextState.swift:849-874]
  +-- ForEach($0.buttons)                         [ButtonState is Identifiable, works]
  +-- Button($0, action: handler)                 [PROVIDED on Android at ButtonState.swift:406-430]
  +-- ButtonRole.init(_ role: ButtonStateRole)     [PROVIDED on Android at ButtonState.swift:394-404]


ConfirmationDialogState<Action>
  |
  +-- title: TextState                    [UNGUARDED]
  +-- message: TextState?                 [UNGUARDED]
  +-- buttons: [ButtonState<Action>]      [UNGUARDED]
  +-- titleVisibility: ...TitleVisibility [UNGUARDED]


View.confirmationDialog(_: Binding<ConfirmationDialogState?>, action:)
  |
  +-- Visibility.init(_ visibility:)      [PROVIDED in ConfirmationDialog.swift, inside #if canImport(SwiftUI)]
  +-- Text.init(_ state: TextState)       [PROVIDED on Android]
  +-- Button($0, action: handler)         [PROVIDED on Android]
```

---

## 3. Guards That MUST Be Removed for Android AlertState Rendering

**None.** The current guard structure is already correct for Android AlertState and ConfirmationDialogState rendering. Here's why:

1. **`AlertState` and `ConfirmationDialogState`** -- completely unguarded, compile everywhere.

2. **`ButtonState`** -- the struct itself is unguarded. The `.animatedSend` case is correctly guarded out on Android (SwiftUI `Animation` doesn't exist in SkipUI). The `.send` case handles all non-animated actions.

3. **`TextState`** -- the struct compiles on Android with `.verbatim` and `.concatenated` storage. Rich text modifiers and localized string keys are guarded out, but AlertState only needs plain text for titles/messages.

4. **SwiftUI bridging** -- Android-specific `Text.init(_: TextState)`, `Button.init(_: ButtonState)`, and `ButtonRole.init(_: ButtonStateRole)` are already provided in the `#if os(Android)` blocks.

5. **View modifiers** -- Both `View.alert(_: Binding<AlertState?>)` and `View.confirmationDialog(_: Binding<ConfirmationDialogState?>)` in SwiftUINavigation are inside `#if canImport(SwiftUI)` (not `!os(Android)`), so they compile on Android.

6. **TCA modifiers** -- Both TCA's `View.alert(store:)` and `View.confirmationDialog(store:)` are inside `#if canImport(SwiftUI)` (not `!os(Android)`), available on Android.

---

## 4. Guards That MUST Stay

| Guard | Location | Reason |
|-------|----------|--------|
| `#if canImport(SwiftUI) && !os(Android)` on `_ActionType.animatedSend` | ButtonState.swift:161 | `SwiftUI.Animation` doesn't exist in SkipUI |
| `#if canImport(SwiftUI) && !os(Android)` on `import SwiftUI` | ButtonState.swift:5 | Replaced by `#if os(Android)` import at line 392 |
| `#if canImport(SwiftUI) && !os(Android)` on modifiers/rich text | TextState.swift:54-115, 288-404 | SwiftUI-specific types (`Font`, `Color`, `CGFloat`) not in SkipUI |
| `#if canImport(SwiftUI) && !os(Android)` on localization storage | TextState.swift:121-129 | `LocalizedStringKey` not available in SkipUI |
| `#if canImport(SwiftUI) && !os(Android)` on `Text.init(_ state:)` | TextState.swift:537-665 | Replaced by Android-specific `Text.init` at line 849 |
| `#if canImport(SwiftUI) && !os(Android)` on SwiftUI bridging | ButtonState.swift:260-357 | Replaced by Android-specific bridging at line 391 |
| `#if !os(Android)` on legacy `Alert.init` | Alert.swift:201-278 | `Alert` type doesn't exist in SkipUI |
| `#if !os(Android)` on legacy `ActionSheet.init` | ConfirmationDialog.swift:227-266 | `ActionSheet` type doesn't exist in SkipUI |
| `#if !os(Android)` on `.animatedSend` in TCA | TCA Alert.swift:91, TCA ConfirmationDialog.swift:96 | Matches `_ActionType` guard |

---

## 5. Risk Assessment

### Current Status: **AlertState rendering path is already unblocked on Android**

The fork has already been modified to support Android AlertState rendering. The evidence:

1. **Android `#if os(Android)` blocks exist** in both `ButtonState.swift` (lines 391-431) and `TextState.swift` (lines 849-874), providing the necessary SwiftUI bridging types.

2. **The modern alert/dialog view modifiers** use `#if canImport(SwiftUI)` (not `!os(Android)`), so they compile on Android where SkipUI provides SwiftUI types.

3. **The SwiftUINavigation `View.alert(_: Binding<AlertState?>)` modifier** (Alert.swift lines 152-168) calls `Text($0.title)`, `ForEach($0.buttons)`, `Button($0, action:)`, and `Text.init` for messages -- all of which resolve on Android via the provided bridging code.

### Potential Issues

| Issue | Risk | Details |
|-------|------|---------|
| **TextState loses rich formatting on Android** | Low | Android `Text.init(_ state:)` flattens to plain text via `_plainText`. Alert titles/messages are typically plain text anyway. |
| **No LocalizedStringKey support on Android** | Medium | `TextState` created with `LocalizedStringKey` init won't compile on Android. All alert text must use `TextState("string literal")` or `TextState(verbatim:)`. This affects any shared code that creates AlertState with localized keys. |
| **No animated button actions on Android** | Low | `.animatedSend` doesn't exist on Android. Only `.send` is available. This is cosmetic -- alerts don't typically need animated dismissal actions. |
| **Skip's `View.alert` signature mismatch** | Medium | Skip's alert modifier (Presentation.swift) takes `(Text, isPresented: Binding<Bool>, actions: () -> View)`. The SwiftUINavigation modifier calls SwiftUI's `.alert(_:isPresented:presenting:actions:message:)`. If SkipUI doesn't implement the `presenting:` overload, the SwiftUINavigation modifier may fail at runtime. Needs verification. |
| **`ForEach` with `ButtonState` on Android** | Medium | The SwiftUINavigation alert modifier uses `ForEach($0.buttons) { Button($0, action:) }`. This requires SkipUI's `ForEach` to work with `[ButtonState]` (which is `Identifiable`). Needs runtime verification. |

### Recommendation

No guard changes are needed in ButtonState.swift or TextState.swift for AlertState rendering. The blocking issue (if any) is more likely at the **SkipUI integration layer** -- specifically whether Skip's `.alert` modifier supports the `presenting:` parameter form that SwiftUINavigation's AlertState modifier calls. Investigation should focus on:

1. Whether `SwiftUI.View.alert(_:isPresented:presenting:actions:message:)` is implemented in SkipUI
2. Whether `SwiftUI.Button.init(role:action:label:)` works in SkipUI's alert context
3. Runtime testing of `ForEach` over `[ButtonState]` inside alert actions

---

## 6. Summary

```
                           ANDROID AVAILABILITY
                           ====================

AlertState<Action>              : AVAILABLE (no guards)
ConfirmationDialogState<Action> : AVAILABLE (no guards)
ButtonState<Action>             : AVAILABLE (struct unguarded)
ButtonStateAction<Action>       : AVAILABLE (.send only, no .animatedSend)
ButtonStateRole                 : AVAILABLE (no guards)
ButtonStateBuilder              : AVAILABLE (no guards)
TextState                       : AVAILABLE (verbatim + concatenated only)
ConfirmationDialogStateTitleVisibility : AVAILABLE (no guards)

Text.init(_ state: TextState)   : PROVIDED  (#if os(Android) block)
Button.init(_ : ButtonState)    : PROVIDED  (#if os(Android) block)
ButtonRole.init(_ : ButtonStateRole) : PROVIDED (#if os(Android) block)

View.alert(_: Binding<AlertState?>) : AVAILABLE (#if canImport(SwiftUI))
View.confirmationDialog(_: Binding<CDS?>) : AVAILABLE (#if canImport(SwiftUI))
TCA View.alert(store:)          : AVAILABLE (#if canImport(SwiftUI))
TCA View.confirmationDialog(store:) : AVAILABLE (#if canImport(SwiftUI))

BLOCKED ON ANDROID:
  - TextState rich text modifiers (bold, italic, font, etc.)
  - TextState LocalizedStringKey/LocalizedStringResource constructors
  - ButtonStateAction.animatedSend
  - Legacy Alert.init (deprecated anyway)
  - Legacy ActionSheet.init (deprecated anyway)
```
