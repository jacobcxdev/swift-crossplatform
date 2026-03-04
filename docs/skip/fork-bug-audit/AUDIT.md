# SkipUI Fork Bug Audit

**Date:** 2026-03-04
**Method:** Manual side-by-side comparison using dual Android emulators
**Fork (broken):** `examples/skipapp-showcase-fuse` (emulator-5554, using local forks)
**Upstream (correct):** `/Users/jacob/Developer/misc/skipapp-showcase-fuse` (emulator-5556, upstream deps)
**App:** ShowcaseFuse (skipapp-showcase-fuse playground)

## Summary

Comprehensive audit of the SkipUI fork against upstream revealed widespread regressions across 40+ component categories. The issues cluster into several recurring patterns:

| Pattern | Severity | Affected Components | Likely Root Cause |
|---------|----------|--------------------|--------------------|
| **Row spacing** | High | 25+ components | VStack/HStack/ForEach layout changes |
| **Bordered button width** | Medium | 15+ components | Button `.bordered`/`.borderedProminent` padding |
| **Circles/shapes not rendering** | Medium | Background, Mask, Overlay | Shape rendering in background/overlay context |
| **Observable/state reactivity** | Critical | Environment, Observable, State, SQL, List | Observation bridge or PeerStore changes |
| **Frame `.infinity` broken** | High | Frame, Stacks | Frame modifier handling of `.infinity` values |
| **Crashes** | Critical | Grids (sectioned), List (sectioned) | LazyVGrid/LazyHGrid/List with sections |
| **Keyboard/List layout collapse** | Critical | Keyboard, List | Row layout in scrollable containers |

## Bug Categories

### P0 — Crashes

| Component | Trigger | Notes |
|-----------|---------|-------|
| Grids — LazyVGridView sectioned | Navigate to view | Immediate crash |
| Grids — LazyHGridView sectioned | Navigate to view | Immediate crash |
| List — Sectioned | Scroll to Section 0 header after Section 2 footer | Crash on scroll |

### P0 — Broken Reactivity (State/Observation)

| Component | Symptom |
|-----------|---------|
| Environment — EnvironmentObject | Tap count doesn't increment |
| Observable | Observation doesn't work at all |
| State — Observable tap count | Doesn't increment until view exit/re-entry |
| State — Repository item tap count | Doesn't increment until view exit/re-entry |
| State — Adding items/incrementing last | Doesn't work until view exit/re-entry |
| SQL — Items | Don't show after pressing plus until view exit/re-entry |
| List — Observable Plain Style EditActions | Toggles don't update until view exit/re-entry |

### P1 — Layout Completely Broken

These are not just spacing tweaks — the layout is fundamentally wrong.

#### Frame

| Example | Description | Images |
|---------|-------------|--------|
| HStack maxWidth: .infinity | Broken | ![fork](images/frame-hstack-maxwidth-infinity-fork.png) ![upstream](images/frame-hstack-maxwidth-infinity-upstream.png) |
| maxWidth: .infinity, maxHeight: .infinity | Broken | ![fork](images/frame-maxwidth-maxheight-infinity-fork.png) ![upstream](images/frame-maxwidth-maxheight-infinity-upstream.png) |
| minWidth: 300, minHeight: 100 / minHeight: 100, maxHeight: .infinity | Broken | ![fork](images/frame-minwidth300-minheight100-fork.png) ![upstream](images/frame-minwidth300-minheight100-upstream.png) |
| minWidth: 100, maxHeight: .infinity / maxWidth: .infinity, maxHeight: .infinity | Broken | ![fork](images/frame-minwidth100-maxheight-infinity-fork.png) ![upstream](images/frame-minwidth100-maxheight-infinity-upstream.png) |
| Full screen .topLeading — bottom text missing | Missing content | ![fork](images/frame-fullscreen-topleading-fork.png) ![upstream](images/frame-fullscreen-topleading-upstream.png) |
| Expanding container in scroll view | Broken | ![fork](images/frame-expanding-scrollview-fork.png) ![upstream](images/frame-expanding-scrollview-upstream.png) |

#### Stacks

| Example | Description | Images |
|---------|-------------|--------|
| Fixed vs Expanding (all) | Broken | ![fork](images/stacks-fixed-expanding-fork.png) ![upstream](images/stacks-fixed-expanding-upstream.png) |
| Spacer (all) | Broken | ![fork](images/stacks-spacer-fork.png) ![upstream](images/stacks-spacer-upstream.png) |
| Text | Broken | ![fork](images/stacks-text-fork.png) ![upstream](images/stacks-text-upstream.png) |
| Content sizes to stack | Broken | ![fork](images/stacks-content-sizes-fork.png) ![upstream](images/stacks-content-sizes-upstream.png) |
| Overflow | Broken | ![fork](images/stacks-overflow-fork.png) ![upstream](images/stacks-overflow-upstream.png) |
| Patterns | Broken | ![fork](images/stacks-patterns-fork.png) ![upstream](images/stacks-patterns-upstream.png) |

#### Grids

| Example | Description | Images |
|---------|-------------|--------|
| LazyVGridView .flexible | Broken | ![fork](images/grids-lazyvgrid-flexible-fork.png) ![upstream](images/grids-lazyvgrid-flexible-upstream.png) |
| LazyVGridView .fixed | Broken | ![fork](images/grids-lazyvgrid-fixed-fork.png) ![upstream](images/grids-lazyvgrid-fixed-upstream.png) |
| LazyHGridView .flexible | Broken (same as VGrid, horizontal) | — |
| LazyHGridView .fixed | Broken (same as VGrid, horizontal) | — |

#### Keyboard

| Example | Description |
|---------|-------------|
| .scrollDismissesKeyboard pushed view | List collapsed: 12 rows rendered across 4, text overlapping (rows 1/5/9 in first row, etc.), text highlighted blue, missing chevrons |

#### Other Layout Breaks

| Component | Example | Description | Images |
|-----------|---------|-------------|--------|
| Animation | Layout | Incorrect layout beyond just spacing | ![fork](images/animation-layout-fork.png) ![upstream](images/animation-layout-upstream.png) |
| Image | Complex Layout (Landscape) | Broken | ![fork](images/image-complex-landscape-fork.png) ![upstream](images/image-complex-landscape-upstream.png) |
| Image | Complex Layout (Portrait) | Broken | ![fork](images/image-complex-portrait-fork.png) ![upstream](images/image-complex-portrait-upstream.png) |
| Image | No URL | Doesn't show | ![fork](images/image-no-url-fork.png) ![upstream](images/image-no-url-upstream.png) |
| Toolbar | Bottom labels | Labels overlap in centre instead of side-by-side | ![fork](images/toolbar-bottom-labels-fork.png) ![upstream](images/toolbar-bottom-labels-upstream.png) |
| ZIndex | With zIndex / before frame | Broken | ![fork](images/zindex-fork.png) ![upstream](images/zindex-upstream.png) |
| ProgressView | Linear HStack | Massive vertical padding, "Indeterminate linear" text missing | ![fork](images/progressview-linear-hstack-fork.png) ![upstream](images/progressview-linear-hstack-upstream.png) |
| ScrollView | Modifiers | Frame differs, "Hide Scroll Indicators" hidden by blue list, toggle unresponsive | ![fork](images/scrollview-modifiers-fork.png) ![upstream](images/scrollview-modifiers-upstream.png) |
| OnSubmit | Clear button | Centred instead of trailing edge | ![fork](images/onsubmit-clear-button-fork.png) ![upstream](images/onsubmit-clear-button-upstream.png) |
| List | Positioned — Content below | Does not display | ![fork](images/list-positioned-buttons-fork.png) ![upstream](images/list-positioned-buttons-upstream.png) |
| Transform | Vertical spacing | Incorrect | ![fork](images/transform-vertical-spacing-fork.png) ![upstream](images/transform-vertical-spacing-upstream.png) |

### P2 — Shapes/Circles Not Rendering

| Component | Example | Images |
|-----------|---------|--------|
| Background | Circles example | ![fork](images/background-circles-fork.png) ![upstream](images/background-circles-upstream.png) |
| Mask | VStack mask | ![fork](images/mask-vstack-fork.png) ![upstream](images/mask-vstack-upstream.png) |
| Overlay | Circles and .clipped() | Same pattern as Background circles (no images) |

### P2 — Row Spacing Incorrect

This is the most widespread issue. Rows in lists/forms have incorrect vertical spacing compared to upstream. Affects 25+ components.

**Reference images:**
- ![fork](images/animation-row-spacing-fork.png) ![upstream](images/animation-row-spacing-upstream.png)

**All affected components:**
- Animation
- Background
- BlendMode
- Blur
- Border
- Color
- Color Effects (also sizing: ![fork](images/color-effects-spacing-fork.png) ![upstream](images/color-effects-spacing-upstream.png))
- Environment (Custom key rows)
- Form (Complex content button, also Picker .navigationLink pushed view: ![fork](images/form-picker-navlink-fork.png) ![upstream](images/form-picker-navlink-upstream.png))
- Gesture
- Icons
- Image
- List (EditActions rows with toggles)
- Lottie Animation
- Mask
- Notifications (also copy button missing, vertical spacing around text field: ![fork](images/notifications-buttons-fork.png) ![upstream](images/notifications-buttons-upstream.png))
- Offset/Position
- Overlay
- Pasteboard (also copy button missing, vertical spacing around text field — same as Notifications)
- Picker (pushed views via navigation link)
- ProgressView
- Redacted (also image row spacing)
- ScrollView
- Shadow
- Shape
- ShareLink
- Spacer (Before After, minLength: ![fork](images/spacer-minlength-fork.png) ![upstream](images/spacer-minlength-upstream.png))
- Stepper
- Storage
- Symbol
- Toolbar
- Tracking
- Transform
- Transition
- ZIndex

### P2 — Bordered Button Width Differences

Buttons with `.bordered` and `.borderedProminent` styles have different widths compared to upstream. This affects both standalone buttons and buttons within forms/lists.

**Reference images:**
- ![fork](images/button-bordered-width-fork.png) ![upstream](images/button-bordered-width-upstream.png)

**All affected components:**
- BlendMode (allowsHitTesting button: ![fork](images/blendmode-button-width-fork.png) ![upstream](images/blendmode-button-width-upstream.png))
- Button (all bordered variants: .bordered, .borderedProminent, .disabled, .foregroundStyle, .tint)
- DisclosureGroup (Toggle Group button)
- Document and Media Pickers
- Form (bordered button: ![fork](images/form-button-spacing-fork.png) ![upstream](images/form-button-spacing-upstream.png))
- Haptic Feedback
- Link (.buttonStyle(.bordered))
- Menu (.buttonStyle(.bordered))
- NavigationStack (.buttonStyle)
- Notifications
- Redacted
- Shadow
- ShareLink
- State (Push binding pushed view buttons)
- Stepper
- Transition

## Suspected Root Causes by Fork

### High Risk — skip-ui (23 files changed, +732 net lines)

Most layout regressions likely trace here:

1. **VStack/HStack rewrite (RetainedAnimatedItems)** — unified animation path replaced dual ANIMATED/NON-ANIMATED rendering. Could affect spacing, overflow, content sizing.
2. **ForEach identity key changes** — `.tag` role, composite keys, namespace UUIDs. Could affect list/grid item identity and section handling.
3. **PeerStore integration** — parent-scoped peer caching in TabView, List. Could cause the reactivity failures (observation not connecting properly).
4. **List changes** — PeerStore provider wrapping, scroll handling. Could cause sectioned list crashes and layout collapse.
5. **Button bordered padding fix** — specific padding changes for `.bordered` variants. Direct cause of button width differences.

### Medium Risk — skipstone (transpiler)

1. **BridgeToKotlinVisitor** — peer remembering, `SwiftPeerHandle`, `Swift_inputsHash`. Could affect observation lifecycle.
2. **StatementTypes** — `composeKey` extraction, `TagModifier` handling. Could affect ForEach/List keying.

### Medium Risk — skip-fuse-ui

1. **Animation/Navigation fixes** — could interact with RetainedAnimatedItems changes.
2. **Accessibility additions** — unlikely to cause layout issues but worth checking.

### Lower Risk — swift-composable-architecture, swift-perception

1. **BridgeObservationRegistrar** — if broken, would explain all reactivity failures.
2. **Store Android gating** — unlikely unless gating is too aggressive.

## Triage Strategy

1. **Row spacing (P2, 25+ components):** Single root cause in VStack/HStack layout. Fix once, fixes everywhere.
2. **Reactivity (P0, 7 components):** Likely single root cause in observation bridge or PeerStore lifecycle.
3. **Crashes (P0, 3 components):** Likely related to sectioned container handling in ForEach/List changes.
4. **Frame .infinity (P1):** Frame modifier handling regression.
5. **Stacks layout (P1):** Related to VStack/HStack rewrite — may resolve with row spacing fix.
6. **Button widths (P2):** Specific Button padding change — isolated fix.
7. **Shapes not rendering (P2):** Background/overlay shape rendering path.

## Notes

- Images are stored in `images/` subdirectory with descriptive names: `{component}-{detail}-{fork|upstream}.png`
- Fork images show the broken behaviour, upstream images show the correct behaviour
- Image pair numbering from original audit: 1-72 (25-26 were skipped in original numbering)
- This audit was performed on the full ShowcaseFuse playground app which exercises the complete SkipUI API surface
