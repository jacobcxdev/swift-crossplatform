# RetainedAnimatedItems Implementation Plan (Section 3)

> Date: 2026-03-02
> Status: Finalised via Codex pair programming (4 iteration rounds)
> Prerequisite: [identity-unified-fix-design.md](identity-unified-fix-design.md)

## Summary

Replace the broken dual-path container animation logic (ANIMATED via `AnimatedContent` /
NON-ANIMATED via plain Column/Row/Box) with a single unified path using per-item
`AnimatedVisibility`. This fixes Section 3 where ForEach items wrapped with
`TagModifier(.tag)` never trigger the ANIMATED path because the container's `idMap` only
checks `TagModifier(.id)`.

---

## Prerequisites / Disk State

**Read this before starting.** The working tree has uncommitted changes that differ from git HEAD.
The implementation plan replaces all modified regions anyway, but a new session must be aware of
the current on-disk state to avoid confusion.

### VStack.swift (lines 52–188) — working tree differs from HEAD

The NON-ANIMATED path (lines 102–182) uses `renderable.identityKey` rather than `idMap` for
`composeKey`. This is an uncommitted revert (Plan 08 rollback). Additionally, lines 92–100 and
the per-item logging inside the loops (lines 105–106, 122–123, 137, 140–141, 158–159, 168–169,
172–173) contain verbose `ComposeIdentity` logging (PROBE-A, PROBE-B, PROBE-C log calls and
per-item key dumps). These are working-tree-only changes — they are not in git HEAD.

**The implementation plan deletes all of lines 52–299 and replaces them, so this uncommitted
state does not require a revert or stash first.**

### HStack.swift (lines 50–166) — working tree differs from HEAD

Same pattern: NON-ANIMATED path uses `renderable.identityKey` for `composeKey`, plus verbose
`ComposeIdentity` per-item log calls (lines 89–95 and inside the loops). Working-tree only.

**The implementation plan deletes all of lines 50–268 and replaces them.**

### ZStack.swift (lines 41–85) — working tree differs from HEAD

Same logging pattern (lines 53–59). The NON-ANIMATED path is already using `renderable.identityKey`.
Working-tree only.

**The implementation plan deletes all of lines 41–133 and replaces them.**

### AnimatedContentArguments.swift — working tree clean

File exists, 31 lines, no uncommitted changes. Will be deleted in Step 5.

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Non-composable `sync` | Stores `Transition?` and `Animation?` snapshots; materialisation at render time in `@Composable resolvedEnter/resolvedExit` |
| Animation captured at state-change time | `withAnimation` thread-local may be cleared by next recomposition; snapshot when `targetState` flips |
| Axis-aware default transitions | VStack: `fade+shrinkVertically`, HStack: `fade+shrinkHorizontally`, ZStack: `fadeOut` |
| Spacing skipped for exiting items | Exiting items don't participate in inter-item spacing; `shrink` handles slot collapse |
| No `animateContentSize()` | Would double-animate geometry already handled by `AnimatedVisibility` shrink |
| Baseline-aware initial visibility | `hasEstablishedBaseline = false` prevents initial population from enter-animating |
| `OpacityTransition.shared` NOT used as default | Replaced by axis-aware fade+shrink which correctly handles layout collapse |
| Re-insertion reuses same `RetainedAnimatedItem` | Flips `targetState` back to `true`, preserving internal composition state |
| `visibleState:` overload of `AnimatedVisibility` | Required for `isIdle`/`currentState` observability used by pruning logic |

---

## Implementation Steps

### Step 1: Create `RetainedAnimatedItems.swift`

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/RetainedAnimatedItems.swift` (new file)

**Language note:** This is Skip-flavoured Swift, compiled by skipstone to Kotlin. The file lives
inside a `#if SKIP` guard. Compose APIs (`MutableTransitionState`, `AnimatedVisibility`,
`EnterTransition`, `ExitTransition`, `fadeIn`, `fadeOut`, `expandVertically`,
`shrinkVertically`, `expandHorizontally`, `shrinkHorizontally`) are accessed directly — no
wrapper needed. The `@Composable` annotation works exactly as in upstream Skip files.

**All required imports** (goes inside the `#if SKIP` block):

```swift
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
```

**Complete file contents:**

```swift
// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
#endif

#if SKIP
enum RetainedAnimatedAxis {
    case vertical
    case horizontal
    case overlay
}

class RetainedAnimatedItem {
    let key: Any
    var renderable: Renderable
    let visibility: MutableTransitionState<Bool>
    var transition: Transition?
    var animation: Animation?
    var previousOrder: Int

    init(key: Any, renderable: Renderable, visibility: MutableTransitionState<Bool>, transition: Transition?, animation: Animation?, previousOrder: Int) {
        self.key = key
        self.renderable = renderable
        self.visibility = visibility
        self.transition = transition
        self.animation = animation
        self.previousOrder = previousOrder
    }
}

class RetainedAnimatedItemsState {
    var items: kotlin.collections.MutableMap<Any, RetainedAnimatedItem> = mutableMapOf()
    var previousOrderedKeys: kotlin.collections.MutableList<Any> = mutableListOf()
    var hasEstablishedBaseline: Bool = false

    var isAnimating: Bool {
        return items.values.any { !$0.visibility.isIdle }
    }

    /// Core sync algorithm. Call once per recomposition before rendering.
    /// Not @Composable — reads Animation.current() state but does not emit nodes.
    func sync(renderables: kotlin.collections.List<Renderable>, animation: Animation?, keyExtractor: (Renderable, Int) -> Any) {
        var currentKeys = mutableListOf<Any>()
        var seenKeys = mutableSetOf<Any>()

        // Step 1: Walk current renderables, extract and disambiguate keys
        for i in 0..<renderables.size {
            let renderable = renderables[i]
            var key = keyExtractor(renderable, i)
            if !seenKeys.add(key) {
                android.util.Log.w("RetainedAnimatedItems", "Duplicate key \(key) at index \(i), disambiguating")
                key = "\(key)_dup\(i)"
                seenKeys.add(key)
            }
            currentKeys.add(key)
        }

        let currentKeySet = currentKeys.toSet()

        // Step 2: Process current renderables — update existing, create new
        for i in 0..<renderables.size {
            let renderable = renderables[i]
            let key = currentKeys[i]
            if let existing = items[key] {
                // Update renderable in case it changed
                existing.renderable = renderable
                if existing.visibility.targetState == false {
                    // Re-insertion: cancel exit by flipping targetState back to true
                    existing.visibility.targetState = true
                    if let animation {
                        existing.animation = animation
                        existing.transition = TransitionModifier.transition(for: renderable)
                    }
                } else {
                    // Update transition in case modifier changed
                    existing.transition = TransitionModifier.transition(for: renderable)
                }
            } else {
                // New item
                let initialVisible: Bool
                let startAnimation: Animation?
                if hasEstablishedBaseline, let animation {
                    initialVisible = false
                    startAnimation = animation
                } else {
                    initialVisible = true
                    startAnimation = nil
                }
                let visibility = MutableTransitionState(initialVisible)
                if !initialVisible {
                    visibility.targetState = true
                }
                let item = RetainedAnimatedItem(
                    key: key,
                    renderable: renderable,
                    visibility: visibility,
                    transition: TransitionModifier.transition(for: renderable),
                    animation: startAnimation,
                    previousOrder: i
                )
                items[key] = item
            }
        }

        // Step 3: Mark removed items for exit or remove immediately
        for (key, item) in items {
            if !currentKeySet.contains(key) && item.visibility.targetState == true {
                if let animation {
                    item.visibility.targetState = false
                    item.animation = animation
                } else {
                    items.remove(key)
                }
            }
        }

        // Step 4: Prune completed exits
        let toRemove = items.entries.filter { e in
            let v = e.value.visibility
            return v.isIdle && !v.currentState && !v.targetState
        }.map { $0.key }
        for key in toRemove {
            items.remove(key)
        }

        // Step 5: Update order for surviving items
        for i in 0..<currentKeys.size {
            items[currentKeys[i]]?.previousOrder = i
        }

        previousOrderedKeys = mergeRetainedOrder(currentKeys: currentKeys, priorOrderedKeys: previousOrderedKeys)
        hasEstablishedBaseline = true
    }

    /// Returns items in display order: current items + exiting items positioned
    /// before their next surviving right neighbour.
    func orderedItems() -> kotlin.collections.List<RetainedAnimatedItem> {
        var result = mutableListOf<RetainedAnimatedItem>()
        for key in previousOrderedKeys {
            if let item = items[key] {
                result.add(item)
            }
        }
        return result
    }

    /// Merge exiting keys into the ordered key list, anchored before next
    /// surviving right neighbour.
    private func mergeRetainedOrder(currentKeys: kotlin.collections.List<Any>, priorOrderedKeys: kotlin.collections.List<Any>) -> kotlin.collections.MutableList<Any> {
        let currentKeySet = currentKeys.toSet()
        // Collect exiting keys from prior order that are still in items (exit in progress)
        let exitingKeys = priorOrderedKeys.filter { !currentKeySet.contains($0) && items[$0] != nil }
        if exitingKeys.isEmpty {
            return currentKeys.toMutableList()
        }

        // For each exiting key, find its anchor: the first current key that appeared
        // after it in the previous order
        var result = currentKeys.toMutableList()
        for exitKey in exitingKeys.reversed() {
            let priorIndex = priorOrderedKeys.indexOf(exitKey)
            // Find the first current key that was to the right of exitKey in prior order
            var anchorIndex: Int = result.size
            for j in (priorIndex + 1)..<priorOrderedKeys.size {
                let candidate = priorOrderedKeys[j]
                let idx = result.indexOf(candidate)
                if idx >= 0 {
                    anchorIndex = idx
                    break
                }
            }
            result.add(anchorIndex, exitKey)
        }
        return result
    }
}

/// Extract the effective animation key for a renderable at a given index.
/// Priority: `.id` TagModifier value (as String) > `identityKey` > positional index.
func effectiveAnimatedKey(renderable: Renderable, index: Int) -> Any {
    if let idValue = TagModifier.on(content: renderable, role: .id)?.value {
        return normalizeKey(idValue)
    }
    if let identityKey = renderable.identityKey {
        return identityKey
    }
    return index
}

/// Materialise the enter transition for an item, using its snapshot or axis default.
@Composable func resolvedEnter(item: RetainedAnimatedItem, axis: RetainedAnimatedAxis) -> EnterTransition {
    let transition = item.transition
    let animation = item.animation
    if let transition, let animation {
        let spec = animation.asAnimationSpec()
        return transition.asEnterTransition(spec: spec)
    }
    // Axis-aware defaults
    switch axis {
    case .vertical:
        return fadeIn() + expandVertically()
    case .horizontal:
        return fadeIn() + expandHorizontally()
    case .overlay:
        return fadeIn()
    }
}

/// Materialise the exit transition for an item, using its snapshot or axis default.
@Composable func resolvedExit(item: RetainedAnimatedItem, axis: RetainedAnimatedAxis) -> ExitTransition {
    let transition = item.transition
    let animation = item.animation
    if let transition, let animation {
        let spec = animation.asAnimationSpec()
        return transition.asExitTransition(spec: spec)
    }
    // Axis-aware defaults
    switch axis {
    case .vertical:
        return fadeOut() + shrinkVertically()
    case .horizontal:
        return fadeOut() + shrinkHorizontally()
    case .overlay:
        return fadeOut()
    }
}

/// @Composable factory — call inside a Render method to get a remembered state instance.
@Composable func rememberRetainedAnimatedItemsState() -> RetainedAnimatedItemsState {
    return remember { RetainedAnimatedItemsState() }
}
#endif
#endif
```

#### `sync` algorithm summary:

1. Walk current renderables, extract keys via `effectiveAnimatedKey`
2. Disambiguate duplicate keys with `"_dup\(index)"` suffix + warning log
3. For each key:
   - Existing + visible: update renderable and transition
   - Existing + exiting (re-insertion): flip `targetState` back to `true`
   - New + baseline established + animation active: create with `visibility = MutableTransitionState(false)`, set `targetState = true`
   - New + no baseline: create with `visibility = MutableTransitionState(true)` (no animation)
4. Mark removed items: if animation active → set `targetState = false`; if no animation → remove immediately
5. Prune completed exits: `isIdle && currentState == false && targetState == false`
6. Merge exiting items into display order anchored before next surviving right neighbour

#### Default transitions by axis:

| Axis | Enter | Exit |
|------|-------|------|
| `.vertical` | `fadeIn + expandVertically` | `fadeOut + shrinkVertically` |
| `.horizontal` | `fadeIn + expandHorizontally` | `fadeOut + shrinkHorizontally` |
| `.overlay` | `fadeIn` | `fadeOut` |

---

### Step 2: Replace VStack.swift

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/VStack.swift`
**Current total lines:** 417

#### Current state of lines 1–24 (file header + imports — shown for context, NOT changed):

```swift
// lines 1–24 (keep exactly as-is)
// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGFloat
import struct CoreGraphics.CGRect
import struct CoreGraphics.CGSize
#endif
```

#### Import change

Replace the `#if SKIP` import block (lines 4–18) with:

```swift
#if SKIP
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
```

Removed: `AnimatedContent`, `EnterTransition`, `ExitTransition`, `SizeTransform`, `togetherWith`, `snap`, `tween`, `remember`
Added: `AnimatedVisibility`
(`EnterTransition`/`ExitTransition` are now supplied by `RetainedAnimatedItems.swift`.)

#### What to delete

Delete lines 52–300 entirely (the `Render` method + `RenderAnimatedContent` method).
Keep lines 302–350 (`EmitAdaptiveSpacing` + `RenderSpaced`).

**Current lines 52–300 for reference (what is being deleted):**

```swift
// lines 52–189 — Render method (current working-tree version with logging + identityKey revert)
    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }
        let layoutImplementationVersion = EnvironmentValues.shared._layoutImplementationVersion

        var hasSpacers = false
        if layoutImplementationVersion > 0 {
            let firstNonSpacerIndex = renderables.indexOfFirst { !($0.strip() is Spacer) }
            let lastNonSpacerIndex = renderables.indexOfLast { !($0.strip() is Spacer) }
            for i in (firstNonSpacerIndex + 1)..<lastNonSpacerIndex {
                if let spacer = renderables[i].strip() as? Spacer {
                    hasSpacers = true
                    spacer.positionalMinLength = Self.defaultSpacing
                }
            }
            hasSpacers = hasSpacers || firstNonSpacerIndex > 0 || (lastNonSpacerIndex > 0 && lastNonSpacerIndex < renderables.size - 1)
        }

        let columnAlignment = alignment.asComposeAlignment()
        let columnArrangement: Arrangement.Vertical
        let adaptiveSpacing = spacing != 0.0 && (hasSpacers || (spacing == nil && renderables.any { $0.strip() is Text }))
        if adaptiveSpacing {
            columnArrangement = Arrangement.spacedBy(0.dp, alignment: androidx.compose.ui.Alignment.CenterVertically)
        } else {
            columnArrangement = Arrangement.spacedBy((spacing ?? Self.defaultSpacing).dp, alignment: androidx.compose.ui.Alignment.CenterVertically)
        }

        // lines 82–100: idMap / ids / rememberedIds / newIds / rememberedNewIds + logging — ALL DELETED
        let idMap: (Renderable) -> Any? = { TagModifier.on(content: $0, role: .id)?.value }
        let ids = renderables.mapNotNull(idMap)
        let rememberedIds = remember { mutableSetOf<Any>() }
        let newIds = ids.filter { !rememberedIds.contains($0) }
        let rememberedNewIds = remember { mutableSetOf<Any>() }
        rememberedNewIds.addAll(newIds)
        rememberedIds.clear()
        rememberedIds.addAll(ids)
        // ... (ComposeIdentity logging lines 92–100) ...

        // lines 102–188: dual-path branch — ALL DELETED
        if ids.size < renderables.size {
            // NON-ANIMATED path
            ...
        } else {
            // ANIMATED path
            ...
        }
    }

// lines 191–300 — RenderAnimatedContent method — ALL DELETED
    @Composable private func RenderAnimatedContent(...) { ... }
```

#### New `Render` method (replace lines 52–300 with this)

Insert immediately after the `isBridged = true` init (after line 49), replacing everything up to (but not including) the `EmitAdaptiveSpacing` method:

```swift
    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }
        let layoutImplementationVersion = EnvironmentValues.shared._layoutImplementationVersion

        var hasSpacers = false
        if layoutImplementationVersion > 0 {
            // Assign positional default spacing to any Spacer between non-Spacers
            let firstNonSpacerIndex = renderables.indexOfFirst { !($0.strip() is Spacer) }
            let lastNonSpacerIndex = renderables.indexOfLast { !($0.strip() is Spacer) }
            for i in (firstNonSpacerIndex + 1)..<lastNonSpacerIndex {
                if let spacer = renderables[i].strip() as? Spacer {
                    hasSpacers = true
                    spacer.positionalMinLength = Self.defaultSpacing
                }
            }
            hasSpacers = hasSpacers || firstNonSpacerIndex > 0 || (lastNonSpacerIndex > 0 && lastNonSpacerIndex < renderables.size - 1)
        }

        let columnAlignment = alignment.asComposeAlignment()
        let columnArrangement: Arrangement.Vertical
        // Compose's internal arrangement code puts space between all elements, but we do not want to add space
        // around `Spacers`. So we arrange with no spacing and add our own spacing elements. Additionally, we space
        // adaptively between adjacent Text elements
        let adaptiveSpacing = spacing != 0.0 && (hasSpacers || (spacing == nil && renderables.any { $0.strip() is Text }))
        if adaptiveSpacing {
            columnArrangement = Arrangement.spacedBy(0.dp, alignment: androidx.compose.ui.Alignment.CenterVertically)
        } else {
            columnArrangement = Arrangement.spacedBy((spacing ?? Self.defaultSpacing).dp, alignment: androidx.compose.ui.Alignment.CenterVertically)
        }

        let retainedState = rememberRetainedAnimatedItemsState()
        let animation = Animation.current(isAnimating: retainedState.isAnimating)
        retainedState.sync(renderables: renderables, animation: animation, keyExtractor: effectiveAnimatedKey)
        let retainedItems = retainedState.orderedItems()

        let contentContext = context.content()
        ComposeContainer(axis: .vertical, modifier: context.modifier) { modifier in
            if layoutImplementationVersion == 0 {
                // Maintain previous layout behavior for users who opt in
                Column(modifier: modifier, verticalArrangement: columnArrangement, horizontalAlignment: columnAlignment) {
                    let flexibleHeightModifier: (Float?, Float?, Float?) -> Modifier = { ideal, min, max in
                        var modifier: Modifier = Modifier
                        if max?.isFlexibleExpanding == true {
                            modifier = modifier.weight(Float(1)) // Only available in Column context
                        }
                        return modifier.applyNonExpandingFlexibleHeight(ideal: ideal, min: min, max: max)
                    }
                    EnvironmentValues.shared.setValues {
                        $0.set_flexibleHeightModifier(flexibleHeightModifier)
                        return ComposeResult.ok
                    } in: {
                        var lastWasText: Bool? = nil
                        var lastWasSpacer: Bool? = nil
                        for i in 0..<retainedItems.size {
                            let item = retainedItems[i]
                            // Only emit spacing for items that are (or will be) visible
                            if item.visibility.targetState == true {
                                let spacingResult = EmitAdaptiveSpacing(renderable: item.renderable, adaptiveSpacing: adaptiveSpacing, lastWasText: lastWasText, lastWasSpacer: lastWasSpacer, layoutImplementationVersion: layoutImplementationVersion)
                                lastWasText = spacingResult.0
                                lastWasSpacer = spacingResult.1
                            }
                            androidx.compose.runtime.key(item.key) {
                                AnimatedVisibility(
                                    visibleState: item.visibility,
                                    enter: resolvedEnter(item: item, axis: .vertical),
                                    exit: resolvedExit(item: item, axis: .vertical),
                                    label: "VStackItem"
                                ) {
                                    item.renderable.Render(context: contentContext)
                                }
                            }
                        }
                    }
                }
            } else {
                VStackColumn(modifier: modifier, verticalArrangement: columnArrangement, horizontalAlignment: columnAlignment) {
                    let flexibleHeightModifier: (Float?, Float?, Float?) -> Modifier = {
                        return Modifier.flexible($0, $1, $2) // Only available in VStackColumn context
                    }
                    EnvironmentValues.shared.setValues {
                        $0.set_flexibleHeightModifier(flexibleHeightModifier)
                        return ComposeResult.ok
                    } in: {
                        var lastWasText: Bool? = nil
                        var lastWasSpacer: Bool? = nil
                        for i in 0..<retainedItems.size {
                            let item = retainedItems[i]
                            // Only emit spacing for items that are (or will be) visible
                            if item.visibility.targetState == true {
                                let spacingResult = EmitAdaptiveSpacing(renderable: item.renderable, adaptiveSpacing: adaptiveSpacing, lastWasText: lastWasText, lastWasSpacer: lastWasSpacer, layoutImplementationVersion: layoutImplementationVersion)
                                lastWasText = spacingResult.0
                                lastWasSpacer = spacingResult.1
                            }
                            androidx.compose.runtime.key(item.key) {
                                AnimatedVisibility(
                                    visibleState: item.visibility,
                                    enter: resolvedEnter(item: item, axis: .vertical),
                                    exit: resolvedExit(item: item, axis: .vertical),
                                    label: "VStackItem"
                                ) {
                                    item.renderable.Render(context: contentContext)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
```

#### Kept unchanged: `EmitAdaptiveSpacing` (current lines 302–324) and `RenderSpaced` (current lines 326–350)

These methods are untouched. For reference, here is the current source of `EmitAdaptiveSpacing`:

```swift
// lines 302–324 — KEEP EXACTLY AS-IS
    /// Emit adaptive spacing before a renderable, outside any key scope.
    /// Returns (isText, isSpacer) tracking info, or (nil, nil) when not adaptive.
    @Composable private func EmitAdaptiveSpacing(renderable: Renderable, adaptiveSpacing: Bool, lastWasText: Bool?, lastWasSpacer: Bool?, layoutImplementationVersion: Int) -> (Bool?, Bool?) {
        guard adaptiveSpacing else {
            return (nil, nil)
        }
        let stripped = renderable.strip()
        let isText = stripped is Text && renderable.forEachModifier { $0.role == .spacing ? true : nil } == true
        let isSpacer = stripped is Spacer
        if layoutImplementationVersion == 0 {
            if let lastWasText {
                let spacing = lastWasText && isText ? (spacing ?? Self.textSpacing) : (spacing ?? Self.defaultSpacing)
                androidx.compose.foundation.layout.Spacer(modifier: Modifier.height(spacing.dp))
            }
        } else {
            // Add spacing before any non-Spacer
            if let lastWasSpacer, !lastWasSpacer && !isSpacer {
                let spacing = lastWasText == true && isText ? (spacing ?? Self.textSpacing) : (spacing ?? Self.defaultSpacing)
                androidx.compose.foundation.layout.Spacer(modifier: Modifier.height(spacing.dp))
            }
        }
        return (isText, isSpacer)
    }
```

---

### Step 3: Replace HStack.swift

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/HStack.swift`
**Current total lines:** 362

#### Current state of lines 1–23 (file header + imports — shown for context, NOT changed):

```swift
// lines 1–23
// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGFloat
import struct CoreGraphics.CGRect
import struct CoreGraphics.CGSize
#endif
```

#### Import change

Replace the `#if SKIP` import block (lines 4–18) with:

```swift
#if SKIP
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
```

Removed: `AnimatedContent`, `EnterTransition`, `ExitTransition`, `SizeTransform`, `togetherWith`, `snap`, `tween`, `remember`
Added: `AnimatedVisibility`

#### What to delete

Delete lines 50–268 (the `Render` method + `RenderAnimatedContent` method).
Keep lines 270–296 (`EmitAdaptiveSpacing` + `RenderSpaced`).

**Current lines 50–268 for reference (what is being deleted):**

```swift
// lines 50–166 — Render method (current working-tree version with logging)
    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }
        let layoutImplementationVersion = EnvironmentValues.shared._layoutImplementationVersion

        var hasSpacers = false
        if layoutImplementationVersion > 0 {
            let firstNonSpacerIndex = renderables.indexOfFirst { !($0.strip() is Spacer) }
            let lastNonSpacerIndex = renderables.indexOfLast { !($0.strip() is Spacer) }
            for i in (firstNonSpacerIndex + 1)..<lastNonSpacerIndex {
                if let spacer = renderables[i].strip() as? Spacer {
                    hasSpacers = true
                    spacer.positionalMinLength = Self.defaultSpacing
                }
            }
            hasSpacers = hasSpacers || firstNonSpacerIndex > 0 || (lastNonSpacerIndex > 0 && lastNonSpacerIndex < renderables.size - 1)
        }

        let rowAlignment = alignment.asComposeAlignment()
        let rowArrangement: Arrangement.Horizontal
        let adaptiveSpacing = spacing != 0.0 && hasSpacers
        if adaptiveSpacing {
            rowArrangement = Arrangement.spacedBy(0.dp, alignment: androidx.compose.ui.Alignment.CenterHorizontally)
        } else {
            rowArrangement = Arrangement.spacedBy((spacing ?? Self.defaultSpacing).dp, alignment: androidx.compose.ui.Alignment.CenterHorizontally)
        }

        // lines 79–95: idMap / ids / rememberedIds + logging — ALL DELETED
        let idMap: (Renderable) -> Any? = { TagModifier.on(content: $0, role: .id)?.value }
        ...

        // lines 97–165: dual-path branch — ALL DELETED
        if ids.size < renderables.size { ... } else { ... }
    }

// lines 168–268 — RenderAnimatedContent method — ALL DELETED
    @Composable private func RenderAnimatedContent(...) { ... }
```

#### New `Render` method (replace lines 50–268 with this)

Insert immediately after the `isBridged = true` init (after line 47), replacing everything up to (but not including) the `EmitAdaptiveSpacing` method:

```swift
    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }
        let layoutImplementationVersion = EnvironmentValues.shared._layoutImplementationVersion

        var hasSpacers = false
        if layoutImplementationVersion > 0 {
            // Assign positional default spacing to any Spacer between non-Spacers
            let firstNonSpacerIndex = renderables.indexOfFirst { !($0.strip() is Spacer) }
            let lastNonSpacerIndex = renderables.indexOfLast { !($0.strip() is Spacer) }
            for i in (firstNonSpacerIndex + 1)..<lastNonSpacerIndex {
                if let spacer = renderables[i].strip() as? Spacer {
                    hasSpacers = true
                    spacer.positionalMinLength = Self.defaultSpacing
                }
            }
            hasSpacers = hasSpacers || firstNonSpacerIndex > 0 || (lastNonSpacerIndex > 0 && lastNonSpacerIndex < renderables.size - 1)
        }

        let rowAlignment = alignment.asComposeAlignment()
        let rowArrangement: Arrangement.Horizontal
        // Compose's internal arrangement code puts space between all elements, but we do not want to add space
        // around `Spacers`. So we arrange with no spacing and add our own spacing elements
        let adaptiveSpacing = spacing != 0.0 && hasSpacers
        if adaptiveSpacing {
            rowArrangement = Arrangement.spacedBy(0.dp, alignment: androidx.compose.ui.Alignment.CenterHorizontally)
        } else {
            rowArrangement = Arrangement.spacedBy((spacing ?? Self.defaultSpacing).dp, alignment: androidx.compose.ui.Alignment.CenterHorizontally)
        }

        let retainedState = rememberRetainedAnimatedItemsState()
        let animation = Animation.current(isAnimating: retainedState.isAnimating)
        retainedState.sync(renderables: renderables, animation: animation, keyExtractor: effectiveAnimatedKey)
        let retainedItems = retainedState.orderedItems()

        let contentContext = context.content()
        ComposeContainer(axis: .horizontal, modifier: context.modifier) { modifier in
            if layoutImplementationVersion == 0 {
                // Maintain previous layout behavior for users who opt in
                Row(modifier: modifier, horizontalArrangement: rowArrangement, verticalAlignment: rowAlignment) {
                    let flexibleWidthModifier: (Float?, Float?, Float?) -> Modifier = { ideal, min, max in
                        var modifier: Modifier = Modifier
                        if max?.isFlexibleExpanding == true {
                            modifier = modifier.weight(Float(1)) // Only available in Row context
                        }
                        return modifier.applyNonExpandingFlexibleWidth(ideal: ideal, min: min, max: max)
                    }
                    EnvironmentValues.shared.setValues {
                        $0.set_flexibleWidthModifier(flexibleWidthModifier)
                        return ComposeResult.ok
                    } in: {
                        var lastWasSpacer: Bool? = nil
                        for i in 0..<retainedItems.size {
                            let item = retainedItems[i]
                            // Only emit spacing for items that are (or will be) visible
                            if item.visibility.targetState == true {
                                lastWasSpacer = EmitAdaptiveSpacing(renderable: item.renderable, adaptiveSpacing: adaptiveSpacing, lastWasSpacer: lastWasSpacer)
                            }
                            androidx.compose.runtime.key(item.key) {
                                AnimatedVisibility(
                                    visibleState: item.visibility,
                                    enter: resolvedEnter(item: item, axis: .horizontal),
                                    exit: resolvedExit(item: item, axis: .horizontal),
                                    label: "HStackItem"
                                ) {
                                    item.renderable.Render(context: contentContext)
                                }
                            }
                        }
                    }
                }
            } else {
                HStackRow(modifier: modifier, horizontalArrangement: rowArrangement, verticalAlignment: rowAlignment) {
                    let flexibleWidthModifier: (Float?, Float?, Float?) -> Modifier = {
                        return Modifier.flexible($0, $1, $2) // Only available in HStackRow context
                    }
                    EnvironmentValues.shared.setValues {
                        $0.set_flexibleWidthModifier(flexibleWidthModifier)
                        return ComposeResult.ok
                    } in: {
                        var lastWasSpacer: Bool? = nil
                        for i in 0..<retainedItems.size {
                            let item = retainedItems[i]
                            // Only emit spacing for items that are (or will be) visible
                            if item.visibility.targetState == true {
                                lastWasSpacer = EmitAdaptiveSpacing(renderable: item.renderable, adaptiveSpacing: adaptiveSpacing, lastWasSpacer: lastWasSpacer)
                            }
                            androidx.compose.runtime.key(item.key) {
                                AnimatedVisibility(
                                    visibleState: item.visibility,
                                    enter: resolvedEnter(item: item, axis: .horizontal),
                                    exit: resolvedExit(item: item, axis: .horizontal),
                                    label: "HStackItem"
                                ) {
                                    item.renderable.Render(context: contentContext)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
```

#### Kept unchanged: `EmitAdaptiveSpacing` (current lines 272–281) and `RenderSpaced` (current lines 283–296)

For reference, the current source of `EmitAdaptiveSpacing` in HStack (simpler than VStack — returns `Bool?` not tuple, no text tracking):

```swift
// lines 272–281 — KEEP EXACTLY AS-IS
    /// Emit adaptive spacing before a renderable, outside any key scope.
    /// Returns isSpacer tracking info, or nil when not adaptive.
    @Composable private func EmitAdaptiveSpacing(renderable: Renderable, adaptiveSpacing: Bool, lastWasSpacer: Bool?) -> Bool? {
        guard adaptiveSpacing else {
            return nil
        }
        let isSpacer = renderable.strip() is Spacer
        if let lastWasSpacer, !lastWasSpacer && !isSpacer {
            androidx.compose.foundation.layout.Spacer(modifier: Modifier.width((spacing ?? Self.defaultSpacing).dp))
        }
        return isSpacer
    }
```

---

### Step 4: Replace ZStack.swift

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/ZStack.swift`
**Current total lines:** 188

#### Current state of lines 1–19 (file header + imports — shown for context, NOT changed):

```swift
// lines 1–19
// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGRect
import struct CoreGraphics.CGSize
#endif
```

#### Import change

Replace the `#if SKIP` import block (lines 4–16) with:

```swift
#if SKIP
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
```

Removed: `AnimatedContent`, `EnterTransition`, `ExitTransition`, `SizeTransform`, `togetherWith`, `snap`, `tween`, `remember`
Added: `AnimatedVisibility`

#### What to delete

Delete lines 41–133 (the `Render` method + `RenderAnimatedContent` method).
ZStack has no `EmitAdaptiveSpacing` — the `#else` body and closing `#endif`/`#endif` survive unchanged.

**Current lines 41–133 for reference (what is being deleted):**

```swift
// lines 41–85 — Render method (current working-tree version with logging)
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }
        let idMap: (Renderable) -> Any? = { TagModifier.on(content: $0, role: .id)?.value }
        let ids = renderables.mapNotNull(idMap)
        let rememberedIds = remember { mutableSetOf<Any>() }
        let newIds = ids.filter { !rememberedIds.contains($0) }
        let rememberedNewIds = remember { mutableSetOf<Any>() }

        rememberedNewIds.addAll(newIds)
        rememberedIds.clear()
        rememberedIds.addAll(ids)

        // lines 53–59: ComposeIdentity logging — DELETED
        android.util.Log.d("ComposeIdentity", "ZStack.Render: ...")
        for i in 0..<renderables.size { ... }

        if ids.size < renderables.size {
            // NON-ANIMATED path
            rememberedNewIds.clear()
            let contentContext = context.content()
            ComposeContainer(eraseAxis: true, modifier: context.modifier) { modifier in
                Box(modifier: modifier, contentAlignment: alignment.asComposeAlignment()) {
                    var seenKeys = mutableSetOf<Any>()
                    for i in 0..<renderables.size {
                        let renderable = renderables[i]
                        var composeKey: Any = renderable.identityKey ?? i
                        if !seenKeys.add(composeKey) {
                            composeKey = "\(composeKey)_dup\(i)"
                        }
                        androidx.compose.runtime.key(composeKey) {
                            renderable.Render(context: contentContext)
                        }
                    }
                }
            }
        } else {
            // ANIMATED path
            ComposeContainer(eraseAxis: true, modifier: context.modifier) { modifier in
                let arguments = AnimatedContentArguments(...)
                RenderAnimatedContent(context: context, modifier: modifier, arguments: arguments)
            }
        }
    }

// lines 87–133 — RenderAnimatedContent — ALL DELETED
    @Composable private func RenderAnimatedContent(...) { ... }
```

#### New `Render` method (replace lines 41–133 with this)

```swift
    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }

        let retainedState = rememberRetainedAnimatedItemsState()
        let animation = Animation.current(isAnimating: retainedState.isAnimating)
        retainedState.sync(renderables: renderables, animation: animation, keyExtractor: effectiveAnimatedKey)
        let retainedItems = retainedState.orderedItems()

        let contentContext = context.content()
        ComposeContainer(eraseAxis: true, modifier: context.modifier) { modifier in
            Box(modifier: modifier, contentAlignment: alignment.asComposeAlignment()) {
                for i in 0..<retainedItems.size {
                    let item = retainedItems[i]
                    androidx.compose.runtime.key(item.key) {
                        AnimatedVisibility(
                            visibleState: item.visibility,
                            enter: resolvedEnter(item: item, axis: .overlay),
                            exit: resolvedExit(item: item, axis: .overlay),
                            label: "ZStackItem"
                        ) {
                            item.renderable.Render(context: contentContext)
                        }
                    }
                }
            }
        }
    }
```

No spacing logic, no flexible dimension environment, no `layoutImplementationVersion` branching — ZStack is the simplest container.

---

### Step 5: Delete AnimatedContentArguments.swift

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/AnimatedContentArguments.swift`

This file exists (31 lines). Its complete current content:

```swift
// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if SKIP
import androidx.compose.runtime.Stable
import androidx.compose.ui.Modifier

/// Used in our containers to prevent recomposing animated content unnecessarily.
@Stable
struct AnimatedContentArguments: Equatable {
    let renderables: kotlin.collections.List<Renderable>
    let idMap: (Renderable) -> Any?
    let ids: kotlin.collections.List<Any>
    let rememberedIds: MutableSet<Any>
    let newIds: kotlin.collections.List<Any>
    let rememberedNewIds: MutableSet<Any>
    let isBridged: Bool

    static func ==(lhs: AnimatedContentArguments, rhs: AnimatedContentArguments) -> Bool {
        // In bridged mode there are cases where a content renderable (e.g. List/ForEach) will not recompose on its own
        // when the renderable's state changes, so shortcutting the AnimatedContent when the IDs compare equal results in
        // showing stale content. We have to shortcut in non-bridged mode, however, because otherwise we may see glitches
        // in animated content when the keyboard hides/shows. The reason for this is unknown, as is the reason we do
        // not see these glitches in bridged mode
        guard !isBridged else {
            return lhs === rhs
        }
        return lhs.ids == rhs.ids && lhs.rememberedIds == rhs.rememberedIds && lhs.newIds == rhs.newIds && lhs.rememberedNewIds == rhs.rememberedNewIds
    }
}
#endif
```

**Action:** Delete the file entirely. It is no longer referenced after the `RenderAnimatedContent` methods are removed from all three containers.

```bash
rm forks/skip-ui/Sources/SkipUI/SkipUI/Containers/AnimatedContentArguments.swift
```

---

## Edge Cases

| Edge Case | Handling |
|-----------|----------|
| Duplicate keys | Disambiguated with `"_dup\(index)"` suffix + warning log |
| Rapid add+remove | Reuses same `RetainedAnimatedItem`, flips `targetState` back |
| No `.transition()` modifier | Axis-aware defaults (fade+shrink for V/H, fade for Z) |
| `.transition(.identity)` | Respected — no-op enter/exit |
| Explicit non-size transition (e.g. `.slide`) | Slot stays full-size until exit completes |
| No identity key (positional fallback) | Supports append/remove-at-end; middle deletion may lose state |
| Empty renderables | All retained items exit (if animated) or remove immediately |
| `isBridged` content | Bridged content renders same as non-bridged through `AnimatedVisibility` |

---

## Test Plan

### Unit tests (`Tests/SkipUITests`)

- First sync: no enter animation (baseline)
- Removal: retained until exit completes
- Re-insertion before prune: cancels exit
- Anchor ordering: removed key stays before next surviving right neighbour
- Duplicate keys: uniquified deterministically

### Section 3 integration test (emulator)

- Increment counters on multiple cards
- Delete first, middle, last cards with `withAnimation`
- Verify deleted card animates out (opacity + vertical shrink)
- Verify remaining cards retain counter values
- Rapid delete/undo preserves state

### Container-specific tests

- HStack middle removal: item shrinks horizontally
- ZStack removal: item fades out only

### Transition coverage

- `.transition(.opacity)`: opacity only (no shrink)
- `.transition(.slide)`: slides, slot stays full-size
- `.transition(.identity)`: no animation
- No explicit transition: axis-aware default

### Regression checks

- No `withAnimation`: immediate remove, no retention
- Section 5 (tab selection), Section 8 (explicit `.id()`) still work

---

## Open Questions

1. **`AnimatedVisibilityScope` receiver in Skip**: The `visibleState:` overload provides `AnimatedVisibilityScope` as a receiver. If Skip doesn't handle this, may need `visible: Boolean` overload with separate `isIdle` observation. Test early.

2. **`FiniteAnimationSpec<IntSize>` cast**: Pattern `spec as! FiniteAnimationSpec<IntSize>` relies on Kotlin type erasure. `Float` and `IntOffset` casts exist in codebase; `IntSize` is new. Verify at runtime.

3. **`RenderSpaced` dead code**: Both VStack and HStack have unused `RenderSpaced` methods. Not touching in this change; clean up in follow-up.
