# Compose View Identity Gap

**Status:** Active workaround in skip-ui fork; transpiler-level fix proposed
**Affects:** Any SwiftUI View with inline-initialised `let` properties when bridged to Compose via Skip (Fuse mode)
**Tracking:** [skiptools/skipstone](https://github.com/skiptools/skipstone) — proposed change to `KotlinBridgeToKotlinVisitor.swift`

---

## Summary

SwiftUI and Compose have fundamentally different models for state persistence. Skip correctly maps `@State` to Compose's `rememberSaveable {}`, but `let` properties with inline initialisers on View structs are transpiled to plain Kotlin `val` — no `remember {}`, no persistence. When an ancestor composable recomposes (e.g. MaterialTheme change), the View struct is recreated, all `let` properties are reinitialised, and any stateful objects (Stores, formatters, coordinators) are replaced with fresh defaults.

This is a **class of problems**, not a single bug. Any SwiftUI pattern relying on implicit view identity preservation is at risk on Android through Skip.

---

## 1. The Impedance Mismatch

### How SwiftUI handles state persistence

SwiftUI maintains an **AttributeGraph** — a persistent render tree where each node is keyed by **view identity** (structural position in the ViewBuilder + explicit `.id()` modifier). This graph stores `@State` values externally, tracks the view struct's property values for diffing, and manages lifecycle.

Crucially, SwiftUI **does not re-execute a view's initialiser** unless:
1. The parent's body is re-evaluated (parent's inputs changed)
2. The child's identity changed (position shifted, `.id()` changed)
3. The child's inputs changed (compared via `Equatable` or byte-wise)

So `let store = Store(...)` on a root view is rarely reinitialised in practice — not because Swift preserves it, but because SwiftUI avoids recreating the struct when inputs haven't changed. The struct CAN be recreated (e.g. if the parent's body is re-evaluated), but in common TCA patterns with stable root views, this doesn't happen. Skip's Compose bridge recreates peers more aggressively during recomposition, exposing this difference.

### How Compose handles state persistence

Compose has no equivalent graph. Recomposition = re-execution of the composable function. All local variables are reinitialised. Persistence is **opt-in** via:

- `remember {}` — survives recomposition within the same composition
- `rememberSaveable {}` — survives recomposition AND configuration changes (rotation, theme)

Compose's "positional memoization" (keying `remember` by call-site position) is analogous to SwiftUI's structural identity, but only for values explicitly wrapped in `remember`.

### The gap

| Aspect | SwiftUI | Compose | Skip mapping |
|--------|---------|---------|--------------|
| `@State var x = 0` | Stored in render graph node | `rememberSaveable {}` | Correct — `Evaluate` override with `rememberSaveable` |
| `let x: T` (parent-provided) | Part of view struct; parent controls lifetime | Function parameter; parent provides on each call | Correct — plain `val`, parent provides fresh value |
| `let x = Expr()` (inline default) | Initialised once; SwiftUI never recreates struct unnecessarily | **Reinitialised every recomposition** | **Wrong** — plain `val`, no `remember` |

---

## 2. How the Skip Transpiler Works Today

### Property handling in Fuse/Bridge mode

The transpiler (`KotlinBridgeToKotlinVisitor.swift`) classifies View struct properties and generates different Compose code for each:

| Property type | Transpiled to | Persistence mechanism |
|---------------|---------------|----------------------|
| `let x: T` (no default) | `val x: T` | None — parent-provided |
| `let x: T = expr` | JNI getter (if bridgable) or omitted (if internal/private) | **None** — Swift peer recreated every recomposition, so value is fresh regardless |
| `@State var x = 0` | `var _x: State<Int>` + `Evaluate` override | `rememberSaveable(stateSaver)` |
| `@StateObject var x` | Same as `@State` | `rememberSaveable(stateSaver)` |
| `@Binding var x: T` | `var _x: Binding<T>` | None — references state owned elsewhere |
| `@Environment(\.key) var x` | JNI sync calls | Re-synced from environment each recomposition |
| `@FocusState var x` | Same pattern as `@State` | `rememberSaveable` |
| `@AppStorage("key") var x` | Same pattern as `@State` | `rememberSaveable` |

### The `Evaluate` override pattern

For `@State` properties, the transpiler generates an `Evaluate` override that uses `rememberSaveable`:

```kotlin
// Generated for a View with @State var count = 0
@Composable
override fun Evaluate(context: ComposeContext, options: Int): List<Renderable> {
    val rememberedCount = rememberSaveable(
        stateSaver = context.stateSaver as Saver<skip.ui.StateSupport, Any>
    ) { mutableStateOf(Swift_initState_count(swiftPeer)) }
    Swift_syncState_count(swiftPeer, rememberedCount.value)
    return super.Evaluate(context, options)
}
```

The Swift side provides init/sync JNI exports:
```swift
func Java_initState_count() -> SkipUI.StateSupport {
    return $count.valueBox!.Java_initStateSupport()
}
func Java_syncState_count(support: SkipUI.StateSupport) {
    $count.valueBox!.Java_syncStateSupport(support)
}
```

**`let` properties with defaults do not participate in this mechanism.** They are not included in the `Evaluate` override decision, so they get no `remember` wrapping.

### Key transpiler files

| File | Role |
|------|------|
| `Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift` | **Fuse/Bridge mode** — generates `Evaluate` overrides, JNI state sync. **This is where the fix goes.** |
| `Sources/SkipSyntax/Kotlin/KotlinSwiftUITransformer.swift` | Transpiled mode — handles `@State`, `@Binding`, `@ViewBuilder`, body translation |
| `Sources/SkipSyntax/HelperTypes.swift` | Defines `stateAttribute` (recognises `@State` and `@StateObject`) |
| `Sources/SkipSyntax/Kotlin/KotlinStructTransformer.swift` | Struct semantics (memberwise constructors, copy constructors) |

---

## 3. Case Study: TabView Appearance-Change Bug

### Reproduction

1. `FuseAppRootView` declares `let store: StoreOf<AppFeature> = Store(initialState: AppFeature.State()) { ... }`
2. User navigates to Settings tab (route 4), changes appearance (Light -> Dark)
3. `preferredColorScheme` change triggers MaterialTheme recomposition
4. MaterialTheme recomposition re-executes the entire composable tree
5. `let store` re-evaluates -> **creates a brand new Store** with default state (`selectedTab: .counter`)
6. The TCA selection binding reads from this new Store -> gets `.counter` (route 0) instead of `.settings` (route 4)
7. TabView's binding sync overwrites `savedRoute` with the stale value -> tab resets to Counter

### Confirmed via TAB_DEBUG logs

```
22:43:57.020 TAB_DEBUG: onItemClick: tabIndex=4, route=4     <- user taps Settings
22:43:57.033 TAB_DEBUG: savedRoute.value=4                    <- correct
22:43:59.648 TAB_DEBUG: binding sync: savedRoute 4 -> 0, selection=counter  <- STALE
22:43:59.649 TAB_DEBUG: navigateToCurrentRoute: CORRECTING 4 -> 0          <- tab resets
```

### Why `@State var store` fixes it

Skip maps `@State` to `rememberSaveable {}`, which preserves the Store across recompositions. The Store survives MaterialTheme recomposition, binding reads correct state, no stale value.

But `@State var store` isn't the canonical TCA pattern — TCA docs use `let store`. Requiring app developers to deviate from canonical patterns for Android compatibility shifts the burden to the wrong layer.

### What we tried that didn't work

- **SideEffect block**: Deferred the binding sync to `SideEffect` (runs after composition). The binding still reads stale because the Store IS genuinely recreated — it's a data issue, not a timing issue.

---

## 4. Current Workaround: Initial-Binding-Route Guard

**File:** `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/TabView.swift` (~line 236)

**Approach:** Track what the binding reads on first composition (`initialBindingRoute`). A recreated Store always produces the same initial state. On subsequent compositions, skip the binding->savedRoute sync when the binding reads back the initial value — this indicates a Store recreation (stale), not a genuine programmatic change.

```swift
// Track what the binding reads on first composition. A recreated Store
// (e.g. from MaterialTheme recomposition with `let store`) always produces
// this same initial value. We use it to filter stale reads.
let initialBindingRoute = rememberSaveable { mutableStateOf<String?>(nil) }

if let selection, let targetRoute = route(tagValue: selection.wrappedValue, in: tabRenderables) {
    if initialBindingRoute.value == nil {
        // First composition: record the initial binding route and sync savedRoute
        initialBindingRoute.value = targetRoute
        if savedRoute.value == nil {
            tabLog("initial sync: savedRoute nil -> \(targetRoute)")
            savedRoute.value = targetRoute
        }
    } else if targetRoute != initialBindingRoute.value {
        // Binding reads a value different from the initial default — this is
        // a genuine programmatic change (reducer action, deep link), not a
        // stale read from a recreated Store. Sync it.
        if savedRoute.value != targetRoute {
            tabLog("programmatic sync: savedRoute \(savedRoute.value ?? \"nil\") -> \(targetRoute), selection=\(selection.wrappedValue)")
            savedRoute.value = targetRoute
        }
    }
    // else: binding reads the initial value but savedRoute already has a
    // different value — likely a stale read from Store recreation. Skip.
}
```

### Why it works

A recreated Store always produces the same initial state. Genuine programmatic changes (reducer actions, deep links) produce a *different* value than the initial default.

### Known edge case

A programmatic change that sets the tab back to the *exact same* value as the Store's initial state would be incorrectly skipped. This is rare (programmatically navigating to the default tab) and acceptable for a workaround.

### Verification

After fix, logs show `savedRoute` preserved at `4` across all recompositions triggered by appearance changes — no `CORRECTING` messages, tab stays on Settings.

---

## 5. Fuse Mode Recomposition Lifecycle (Investigated)

### Full call chain

```
Android Activity.setContent {}
  → PresentationRoot(context, content)                    // PresentationRoot.swift:32
    → MaterialTheme(colorScheme: materialColorScheme) {   // PresentationRoot.swift:39
        → content(context)                                // PresentationRoot.swift:85
          → rootView.Compose(context)                     // View.swift:53
            → rootView._ComposeContent(context)           // View.swift:65→76
              → rootView.Evaluate(context, options: 0)    // View.swift:77→86
                → [GENERATED OVERRIDE if @State etc.]
                  → rememberSaveable for @State           // BridgeToKotlinVisitor:1638
                  → Swift_syncState(Swift_peer, ...)      // BridgeToKotlinVisitor:1639
                → super.Evaluate()                        // View.swift:86
                  → ViewObservation.startRecording?()     // View.swift:90
                  → StateTracking.pushBody()              // View.swift:92
                  → body.Evaluate(context, options)       // View.swift:93 — recurses into body
                    → Swift_composableBody(Swift_peer)    // BridgeToKotlinVisitor:1751-1810
                      → Swift: peerSwiftTarget.body       // evaluates body on Swift side
                      → Swift: child.toJavaObject()       // creates NEW Kotlin proxy per child
                        → SwiftValueTypeBox(child)        // BridgeToKotlinVisitor:1309
                        → SwiftObjectPointer.pointer(to: box, retain: true)
                      → returns child Kotlin View
                    → childView.Compose(composectx)       // recurse
                  → StateTracking.popBody()               // View.swift:94
                  → ViewObservation.stopAndObserve?()     // View.swift:96
```

### Peer lifecycle

The `Swift_peer` is a raw `SwiftObjectPointer` stored on every bridged Kotlin class (`KotlinBridgeToKotlinVisitor.swift:1054-1062`). It has **no Compose lifecycle management** — no `remember{}`, no positional memoization.

| Event | What happens |
|-------|-------------|
| **Construction** | Kotlin constructor calls JNI `Swift_constructor(args...)` → allocates `SwiftValueTypeBox(MyView(...))` → returns retained pointer |
| **Peer constructor** | Alternative path: `constructor(Swift_peer, marker)` accepts pre-existing pointer (used by `toJavaObject`) |
| **Property access** | Kotlin getter calls JNI `Swift_get_propertyName(Swift_peer)` → reads from boxed Swift struct |
| **Disposal** | `finalize()` calls `Swift_release(Swift_peer)` → releases the boxed Swift value |

### Who creates the Swift struct during recomposition

**Every `body` evaluation creates fresh child Views.** When `Swift_composableBody(Swift_peer)` is called:

1. Swift dereferences `Swift_peer` to get the parent's Swift struct
2. Accesses `.body` — Swift evaluates the body, constructing child View structs as value types
3. Each child View is converted back to Kotlin via `toJavaObject()` (`BridgeToKotlinVisitor.swift:1301-1322`)
4. `toJavaObject()` creates a **new** `SwiftValueTypeBox` wrapping a **new** copy of the child struct
5. A new Kotlin proxy class is instantiated with the new `Swift_peer`

**For root views**, the same applies — if `FuseAppRootView()` is called inside a Compose lambda without `remember{}`, it's reconstructed on every recomposition.

### The MaterialTheme trigger

`PresentationRoot.swift:39` wraps the entire view tree in `MaterialTheme(colorScheme:)`. When `preferredColorScheme` changes (user changes appearance), `MaterialTheme` recomposes its entire content lambda. This triggers re-execution of the root view construction → fresh `Swift_peer` → fresh Swift struct → **fresh `let` property initialisers**.

### Critical finding: property-level `remember` is insufficient

The naive approach of remembering individual property values in `Evaluate` has a fundamental flaw: **body evaluation happens on the Swift side.** When `Evaluate` calls `super.Evaluate()` → `body` → `Swift_composableBody(Swift_peer)`, Swift reads `self.store` directly from the Swift struct — not through any Kotlin getter. A Kotlin-side `remember` of the property value cannot intercept the Swift-side read.

The fix must operate at the **peer level**, not the property level.

---

## 6. Approach Evaluation

### Approach A: Remember `Swift_peer` in `Evaluate` (Recommended)

Instead of remembering individual property values, remember the entire `Swift_peer` pointer. On subsequent recompositions, replace the fresh peer with the remembered one before `body` runs.

**Generated code:**
```kotlin
@Composable
override fun Evaluate(context: ComposeContext, options: Int): List<Renderable> {
    // Preserve the peer (and all its let properties) across recompositions
    val rememberedPeer = remember { Swift_peer }
    if (rememberedPeer != Swift_peer) {
        Swift_retain(rememberedPeer)       // +1 retain: this instance now also references remembered peer
        Swift_release(Swift_peer)          // release the freshly-created peer
        Swift_peer = rememberedPeer        // restore the original
    }
    // ... existing @State sync code ...
    return super.Evaluate(context, options)
}
```

**Retain/release accounting:** Each recomposition creates a new Kotlin View instance (via `toJavaObject`) with a fresh `Swift_peer`. The `Evaluate` override swaps it for the remembered peer. When the old Kotlin instance is GC'd, `finalize()` calls `Swift_release(Swift_peer)` — but `Swift_peer` was reassigned to the remembered peer, so without the extra `Swift_retain`, `finalize()` would decrement the remembered peer's retain count, eventually freeing it while still in use. The `Swift_retain` before the swap ensures balanced reference counting:

```
Instance A (first composition): peer1 created (retain=1), remembered
Instance B (recomposition):     peer2 created (retain=1)
  Evaluate: Swift_retain(peer1) → retain=2; Swift_release(peer2) → freed; B.Swift_peer = peer1
  GC of A:  finalize → Swift_release(peer1) → retain=1  ← still alive ✓
Instance C (recomposition):     peer3 created (retain=1)
  Evaluate: Swift_retain(peer1) → retain=2; Swift_release(peer3) → freed; C.Swift_peer = peer1
  GC of B:  finalize → Swift_release(peer1) → retain=1  ← still alive ✓
Composable leaves tree:
  GC of C:  finalize → Swift_release(peer1) → retain=0  ← freed ✓
```

**`Swift_retain` generation:** The transpiler currently generates `Swift_release` as a per-class private external JNI function (`KotlinBridgeToKotlinVisitor.swift:1095`). A matching `Swift_retain` must be generated alongside it:

```kotlin
private external fun Swift_retain(Swift_peer: skip.bridge.SwiftObjectPointer)
```

```swift
// Swift cdecl:
@_cdecl("Java_...Swift_retain")
func Swift_retain(peer: SwiftObjectPointer) {
    peer.retain(as: SwiftValueTypeBox<MyView>.self)  // or .reference for class types
}
```

**Why it works:**
- The remembered `Swift_peer` points to the original `SwiftValueTypeBox` containing the original Swift struct
- When `super.Evaluate()` calls `Swift_composableBody(Swift_peer)`, Swift reads `self.store` from the **original** struct
- All `let` properties with defaults are naturally preserved — no per-property handling needed
- `@State` properties continue to work via their existing `rememberSaveable` + JNI sync (they sync TO the remembered peer)

**Compose lifecycle alignment:**
- `remember {}` key is positional (call-site) — mirrors SwiftUI's structural identity
- Value is invalidated when the composable leaves the tree — matches SwiftUI View lifecycle
- `key()` wrapper resets `remember` — `.id()` already maps to `key()` in skip-ui (`AdditionalViewModifiers.swift:1412`)

**Scope limitation — `remember` vs `rememberSaveable`:** `remember {}` survives recomposition but NOT Android configuration changes (Activity recreation on rotation, locale change, etc.). On config change, the remembered peer is lost and a fresh one is created. This is acceptable because: (a) `rememberSaveable` cannot safely persist raw native pointers across process death, and (b) TCA's `Store` can be reconstructed from persisted state if needed. This should be documented as a known scope limit — full state preservation across config changes requires app-level state restoration, not peer pointer persistence.

**Alternative lifecycle strategy — `DisposableEffect`:** Instead of relying on `finalize()` for cleanup (GC-based ownership), an alternative is composition-scoped ownership via `DisposableEffect`. `DisposableEffect` is already used in skip-ui (e.g. `AdditionalViewModifiers.swift:908`, `Observable.swift:22`):

```kotlin
DisposableEffect(Unit) {
    Swift_retain(rememberedPeer)   // composition owns a reference
    onDispose {
        Swift_release(rememberedPeer)  // release when composable leaves tree
    }
}
```

**Important: this is an alternative to the `finalize()`-based approach, not an addition.** If both the `Evaluate` swap block (which retains on each recomposition) AND the `DisposableEffect` (which retains on first composition) are generated together, the retain counts will be inconsistent — `DisposableEffect(Unit)` fires once on first composition, but `finalize()` fires once per GC'd instance, leading to mismatched retain/release pairs. Choose one ownership strategy:

- **`finalize()`-based (recommended for Phase 1):** The `Evaluate` swap block handles retain/release. Each GC'd Kotlin instance's `finalize()` releases its `Swift_peer`. The trace in "Retain/release accounting" above is correct for this approach.
- **`DisposableEffect`-based:** The composition owns the reference. Simpler mental model but requires careful key management — for Phase 2, the `DisposableEffect` key must track `rememberedPeer.value` (not `Unit`) so that the effect re-fires when the remembered peer changes on input change.

**Phase 1 scope — zero-constructor-parameter views only:**

Phase 1 targets views with ONLY `let`-with-default properties and no constructor parameters. For these views, the peer is unconditionally remembered — there are no parent-provided inputs that could become stale. Views with constructor parameters MUST wait for Phase 2 (input-change detection) to avoid freezing parent-provided inputs.

**Complexity for views with constructor parameters (Phase 2):**

For views that have BOTH constructor args (parent-provided) AND `let`-with-default:

```swift
struct ChildView: View {
    let name: String              // parent-provided — must update
    let store = Store(...) { }    // internal default — must preserve
}
```

The transpiler needs to detect when parent-provided inputs change and accept a fresh peer in that case:

```kotlin
@Composable
override fun Evaluate(context: ComposeContext, options: Int): List<Renderable> {
    val rememberedPeer = remember { mutableStateOf(Swift_peer) }
    val rememberedHash = remember { mutableStateOf(Swift_inputsHash(Swift_peer)) }

    val currentHash = Swift_inputsHash(Swift_peer)
    if (currentHash != rememberedHash.value) {
        // Parent changed inputs — accept the new peer
        // Do NOT release the old remembered peer here: previous Kotlin instances
        // whose Swift_peer was swapped to it still hold references and will release
        // via finalize() when GC'd. Releasing here would cause a double-free.
        rememberedPeer.value = Swift_peer
        rememberedHash.value = currentHash
    } else if (rememberedPeer.value != Swift_peer) {
        // Same inputs, recomposition recreation — use remembered peer
        Swift_retain(rememberedPeer.value)
        Swift_release(Swift_peer)
        Swift_peer = rememberedPeer.value
    }

    return super.Evaluate(context, options)
}
```

The `Swift_inputsHash` JNI function would hash the constructor-provided properties. The transpiler can identify which properties are constructor parameters — see Phase 2, Step 5 for how to derive this information at bridge stage.

**Pros:**
- Fixes the entire bug class in one mechanism
- No per-property JNI functions needed for `let` defaults
- Natural Compose lifecycle alignment
- `@State` sync continues to work (syncs to the same peer)

**Cons:**
- Mixed views (constructor args + let defaults) need input-change detection
- `Swift_inputsHash` JNI function adds complexity for mixed views
- Remembered peer retains the `SwiftValueTypeBox` — must ensure no leaks

### Approach B: Shadow `let`-with-default as `var` in bridge

Convert `let store = Store(...)` to a mutable property in the bridge layer, then use `@State`-like init/sync JNI pairs.

**Rejected.** The Swift source declares `let` — the bridge would need to either use `UnsafeMutablePointer` to overwrite a `let` stored property (fragile, violates Swift memory safety) or generate the property as `var` in bridge code (changes the Swift API surface, breaks type-checker expectations). Too invasive for the benefit.

### Approach C: Remember View at construction call-site

Wrap every View construction in `remember(inputs) { ViewType(inputs) }` at the parent's body evaluation site.

**Rejected for now.** This would need to happen inside `Swift_composableBody` or the body bridge — but child views are constructed on the **Swift** side and returned via JNI. The Kotlin side only receives the `toJavaObject` result, with no access to per-child construction. Would require fundamental changes to how `toJavaObject` works for View types.

### Approach D: Per-property `remember` with JNI sync-back

Remember individual `let`-with-default values in `Evaluate`, generate JNI sync functions to write them back to the Swift peer.

**Rejected.** As explained in Section 5 ("Critical finding: property-level `remember` is insufficient"), the body runs on Swift side reading `self.store` directly. Writing back individual properties requires either (a) converting `let` to `var` in the bridge (Approach B problems) or (b) unsafe pointer tricks. Approach A achieves the same result more cleanly by preserving the entire peer.

### Approach E: Framework-level utility (no transpiler change)

Generalise the TabView workaround pattern into a skip-ui utility that components use to guard against stale binding reads.

**Viable as interim, not as permanent fix.** Each component must opt in, the guard logic is heuristic-based (relies on detecting "initial value" vs "genuine change"), and it doesn't fix the root cause. Current TabView workaround is this approach. Good as a safety net but not a substitute for the transpiler fix.

### Approach comparison

| Approach | Fixes root cause? | Complexity | Invasiveness | Mixed views? |
|----------|-------------------|-----------|--------------|--------------|
| **A: Remember peer** | **Yes** | Medium | Low (Evaluate override only) | Yes (with input hashing) |
| B: Shadow as var | Yes | High | High (unsafe memory or API change) | Yes |
| C: Call-site remember | Yes | Very high | High (toJavaObject rewrite) | N/A (natural) |
| D: Per-property sync | Yes | High | Medium | Yes |
| **E: Framework guard** | No (heuristic) | Low | Low | N/A |

**Recommendation: Approach A (remember peer) for the transpiler fix, with Approach E retained as defence-in-depth for components.**

---

## 7. Concrete Implementation Plan

### Phase 1: Simple case — views with only `let`-with-default properties (no constructor params)

This covers the primary bug (root views with `let store = Store(...)`).

#### Step 1: Detect `let`-with-default at decode time

**Detection subtlety:** By the time `addSwiftUIImplementation()` runs, bridgable `let` properties already have their `value` stripped (`updateDeclaration()` at line 346 sets `variableDeclaration.value = nil`). We cannot use `value != nil` to detect them in `addSwiftUIImplementation()`. Detection must happen earlier.

**Approach: Flag during the member traversal pass.**

**File:** `Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift` (in `update()`, ~line 152)

After `isSupportedConstant` check (line 161), before `updateDeclaration` strips the value (line 346), flag `let`-with-default properties on View structs:

```swift
// After line 163 — isSupportedConstant guard has exited (returned false),
// so this code only runs for properties that are NOT literal constants:
if variableDeclaration.isLet,
   variableDeclaration.value != nil,
   !variableDeclaration.modifiers.isStatic,
   classDeclaration?.swiftUIType != nil {
    variableDeclaration.isLetWithDefault = true  // new flag on KotlinVariableDeclaration
}
```

This flag survives the value stripping and is available when `addSwiftUIImplementation()` runs later.

**Also handle non-bridgable properties:** In `StatementTypes.swift` (~line 1858), properties with `decodeLevel == .none` never reach `update()`. Add a new `UnbridgedMember` case:

```swift
case letWithDefault(String)  // property name
```

**Enum exhaustiveness:** The `UnbridgedMember` enum has computed properties (`isSwiftUIStateProperty`, `isObservable`, `suppressDefaultConstructorGeneration`) that switch over all cases. The new `letWithDefault` case must return `false` for all three — it is not a state property, not observable, and does not suppress constructor generation.

**Note:** The `letWithDefault` predicate (requires `initializer?.value != nil`) and the existing `uninitializedStructProperty` predicate (requires `initializer?.value == nil`) are mutually exclusive — ordering between them does not matter.

```swift
// In decodeLevel == .none guard, after existing checks:
} else if syntaxTree.isBridgeFile,
          context.memberOf?.type == .structDeclaration,
          !modifiers.isStatic,
          variableDecl.bindingSpecifier.text == "let",
          variableDecl.bindings.first?.initializer?.value != nil,
          attributes.stateAttribute == nil,
          attributes.environmentAttribute == nil,
          !attributes.contains(.focusState),
          !attributes.contains(.gestureState),
          !attributes.contains(.appStorage) {
    return [UnbridgedMemberDeclaration(member: .letWithDefault(name), ...)]
}
```

**Exclude literal constants:** `isSupportedConstant` returns `true` for Bool, Int, Double, String literals, and nil — these are re-declared on the Kotlin side (not bridged via JNI) and are cheap to recreate. They do NOT need `remember`. The `isLetWithDefault` flag is only set after the `isSupportedConstant` guard, so literals are excluded automatically.

#### Step 2: Generate `Swift_retain` alongside `Swift_release`

**File:** `Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift` (~line 1095)

After the existing `Swift_release` external function declaration, add `Swift_retain`:

```kotlin
private external fun Swift_retain(Swift_peer: skip.bridge.SwiftObjectPointer)
```

And generate the corresponding Swift cdecl (mirroring the `Swift_release` pattern at line 1146):

```swift
@_cdecl("Java_...Swift_retain")
func Swift_retain(peer: SwiftObjectPointer) {
    peer.retain(as: SwiftValueTypeBox<MyView>.self)
}
```

#### Step 3: Generate `remember { Swift_peer }` in Evaluate override

**File:** `Sources/SkipSyntax/Kotlin/KotlinBridgeToKotlinVisitor.swift`

**In `addSwiftUIImplementation()` (~line 1565):** Extend the `Evaluate` override trigger to also fire when peer remembering is applicable (Phase 1: zero-constructor-parameter views with `let`-with-default):

```swift
let stateVariables = classDeclaration.unbridgedMembers.compactMap { ... } // existing
let hasLetWithDefault = classDeclaration.unbridgedMembers.contains {
    if case .letWithDefault = $0 { return true } else { return false }
} || classDeclaration.members.contains {
    ($0 as? KotlinVariableDeclaration)?.isLetWithDefault == true  // bridgable path
}

// Phase 1 guard: only apply simple peer remembering to views with NO constructor
// parameters. Mixed views (constructor params + let-with-default) need input-change
// detection (Phase 2) to avoid freezing parent-provided inputs.
let hasConstructorParams = !classDeclaration.initializableVariableDeclarations.isEmpty
    // Note: initializableVariableDeclarations may need to be derived from constructor
    // signatures at bridge stage — see Phase 2, Step 5 for alternatives.
let canRememberPeer = hasLetWithDefault && !hasConstructorParams
```

**In `swiftUIEvaluate()` (~line 1619):** When `canRememberPeer` is true, insert peer remembering with correct retain/release before the existing state variable loop:

```kotlin
// Generated at top of Evaluate override:
val rememberedPeer = androidx.compose.runtime.remember { Swift_peer }
if (rememberedPeer != Swift_peer) {
    Swift_retain(rememberedPeer)
    Swift_release(Swift_peer)
    Swift_peer = rememberedPeer
}
```

The existing property getters/setters and `@State` sync functions all read from `Swift_peer` — by restoring the remembered peer, everything just works.

#### Step 4: Test

**File:** `forks/skipstone/Tests/SkipSyntaxTests/SwiftUITests.swift`

Add a transpilation test:
```swift
func testLetWithDefaultRememberPeer() async throws {
    try await check(supportingSwift: baseSupportingSwift, swift: """
    struct MyView: View {
        let store = Store()
        var body: some View { Text("hello") }
    }
    """, kotlin: """
    // Expected: Evaluate override with remember { Swift_peer }
    // ... verify the generated Kotlin contains peer remembering
    """)
}
```

Integration test: build fuse-app with the forked skipstone, deploy to emulator, verify TabView appearance-change bug is fixed.

### Phase 2: Mixed case — views with constructor params AND `let`-with-default

This extends the fix to views like:
```swift
struct DetailView: View {
    let title: String                // parent-provided
    let formatter = DateFormatter()  // internal default — should persist
}
```

#### Step 5: Generate `Swift_inputsHash` JNI function

The transpiler needs to identify which properties are constructor parameters (parent-provided inputs). Note: `initializableVariableDeclarations` is local to `KotlinStructTransformer` and not directly available in the bridge visitor. The input set must be derived from the **constructor signatures** visible at bridge stage — specifically, the parameters of bridged constructors generated in `KotlinBridgeToKotlinVisitor.swift:493-531`. Alternatively, persist this metadata on `KotlinClassDeclaration` during struct transformation so it's available later.

Generate a JNI function that hashes the constructor-provided property values:

```swift
@_cdecl("Java_...Swift_inputsHash")
func Swift_inputsHash(peer: SwiftObjectPointer) -> Int64 {
    let target: DetailView = peer.pointee()!.value
    var hasher = Hasher()
    hasher.combine(target.title)
    return Int64(hasher.finalize())
}
```

#### Step 6: Extend Evaluate with input-change detection

```kotlin
@Composable
override fun Evaluate(context: ComposeContext, options: Int): List<Renderable> {
    val rememberedPeer = remember { mutableStateOf(Swift_peer) }
    val rememberedHash = remember { mutableStateOf(Swift_inputsHash(Swift_peer)) }

    val currentHash = Swift_inputsHash(Swift_peer)
    if (currentHash != rememberedHash.value) {
        // Inputs changed — accept new peer (don't release old: finalize() handles it)
        rememberedPeer.value = Swift_peer
        rememberedHash.value = currentHash
    } else if (rememberedPeer.value != Swift_peer) {
        // Same inputs, recomposition — restore remembered peer
        Swift_retain(rememberedPeer.value)
        Swift_release(Swift_peer)
        Swift_peer = rememberedPeer.value
    }

    // ... existing @State sync ...
    return super.Evaluate(context, options)
}
```

#### Hashability requirement

Constructor parameters must be `Hashable` for `Swift_inputsHash` to work. The transpiler should emit a warning if a constructor parameter type is not `Hashable`. In practice, most View constructor parameters are `String`, `Int`, `Bool`, `Binding<T>`, or `Hashable` enums — the coverage is broad.

### Phase 3: Verify `.id()` → `key()` cooperates with peer remembering

**Status:** `.id()` already maps to Compose `key()` in skip-ui (`AdditionalViewModifiers.swift:1412-1413`). When `.id()` changes, `key()` resets all `remember`'d values inside its scope — including the remembered peer. This is the correct behaviour (matches SwiftUI discarding and recreating a view when explicit identity changes).

**What to verify:** The remembered peer is inside the `key()` scope, so it's invalidated when `.id()` changes. A new peer is created for the new identity. Test this interaction explicitly.

### Phase 4: Performance — input diffing / skippable composables

Only if profiling shows unnecessary recompositions. Compose's `@Stable` annotation and function skippability could be leveraged to skip recomposition entirely when inputs haven't changed, but this is an optimisation beyond correctness.

### Transpiler modification points (summary)

| File | Line(s) | Change | Phase |
|------|---------|--------|-------|
| `KotlinStatementTypes.swift` | ~2735 | Add `isLetWithDefault: Bool` flag on `KotlinVariableDeclaration` | 1 |
| `StatementTypes.swift` | ~1735 | Add `UnbridgedMember.letWithDefault(String)` case + update computed properties (`isSwiftUIStateProperty`, `isObservable`, `suppressDefaultConstructorGeneration`) to handle new case | 1 |
| `StatementTypes.swift` | ~1858 | Add detection predicate for non-bridgable `let`-with-default | 1 |
| `KotlinBridgeToKotlinVisitor.swift` | ~163 | Set `isLetWithDefault` flag for bridgable `let`-with-default | 1 |
| `KotlinBridgeToKotlinVisitor.swift` | ~1095 | Generate `Swift_retain` external function alongside `Swift_release` | 1 |
| `KotlinBridgeToKotlinVisitor.swift` | ~1146 | Generate `Swift_retain` cdecl (mirroring `Swift_release` pattern) | 1 |
| `KotlinBridgeToKotlinVisitor.swift` | ~1570 | Extend `addSwiftUIImplementation` to trigger on `letWithDefault` | 1 |
| `KotlinBridgeToKotlinVisitor.swift` | ~1619 | Extend `swiftUIEvaluate` with `remember { Swift_peer }` + retain/release | 1 |
| `KotlinBridgeToKotlinVisitor.swift` | ~1461 | Add `Swift_inputsHash` JNI declaration | 2 |
| `KotlinBridgeToKotlinVisitor.swift` | ~1554 | Add `Swift_inputsHash` closure implementation | 2 |

### Test strategy

| Level | What | How |
|-------|------|-----|
| **Unit (transpiler)** | Verify generated Kotlin contains `remember { Swift_peer }` | `SwiftUITests.swift` `check()` with `swift:` / `kotlin:` comparison |
| **Unit (transpiler)** | Verify `let`-with-default triggers Evaluate override | Same pattern, verify override is generated |
| **Unit (transpiler)** | Verify `let` without default does NOT trigger | Negative test case |
| **Integration (build)** | Build fuse-app with forked skipstone | `make ios fuse-app` (compile-time correctness) |
| **Integration (runtime)** | TabView appearance-change bug | Emulator: change appearance on Settings tab, verify tab doesn't reset |
| **Regression** | `@State` still works | Existing counter feature tests |
| **Regression** | Combined `@State` + `let`-with-default | View with both `@State var count` and `let store = Store(...)` — verify peer swap precedes `@State` sync in generated `Evaluate` |
| **Regression** | Parent-provided `let` still updates | Verify views with constructor args receive new values |
| **Edge case** | `.id()` resets remembered peer | View with `.id(value)` — change `value`, verify peer is recreated |
| **Edge case** | `ForEach`/`List` with stable identity | Multiple instances with `let`-with-default, insert/reorder, verify correct peer per position |
| **Edge case** | `ForEach`/`List` without explicit `id` | Verify remembered peers follow positional identity correctly |
| **Scope limit** | Config change (rotation) recreates peer | Document-only: verify Store can be reconstructed from persisted state |

Test files: `forks/skipstone/Tests/SkipSyntaxTests/SwiftUITests.swift` (transpilation), `examples/fuse-app/Tests/` (integration). Run with `cd forks/skipstone && swift test --disable-experimental-prebuilts` and `make test fuse-app`.

---

## 8. Affected Components

### Known

| Component | Status | Notes |
|-----------|--------|-------|
| `TabView` (binding->savedRoute sync) | **Workaround applied** | Initial-binding-route guard in skip-ui fork |
| `NavigationStack` | **Untested** | May have similar binding sync issues if Store is recreated |
| Any component reading `Binding` during composition | **At risk** | Audit needed |

### Detection checklist

When investigating a new "state resets on recomposition" bug:

1. Is a `let` property creating a stateful object (Store, Observable, etc.)?
2. Does a parent composable trigger recomposition (MaterialTheme, configuration change)?
3. Does the component read a binding during composition (not just in event handlers)?
4. Does the binding source (Store) get recreated with default state?

If all four: you've hit the view identity gap. Apply the initial-value-guard pattern or use `@State`.

---

## 9. References

### SwiftUI view identity
- [WWDC 2021 — Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/) — structural vs explicit identity, view lifecycle
- [WWDC 2021 — Demystify SwiftUI (Identifier Stability)](https://developer.apple.com/videos/play/wwdc2021/10022/?time=753) — why identity stability matters for state preservation

### Compose state model
- [State and Jetpack Compose](https://developer.android.com/develop/ui/compose/state) — `remember`, `rememberSaveable`, state hoisting
- [Lifecycle of composables](https://developer.android.com/develop/ui/compose/lifecycle) — recomposition, positional memoization, `key()`
- [Compose stability](https://developer.android.com/develop/ui/compose/performance/stability) — `@Stable`, `@Immutable`, skippable functions

### Skip transpiler
- [skiptools/skipstone](https://github.com/skiptools/skipstone) — `KotlinBridgeToKotlinVisitor.swift` (Fuse mode View transpilation)
- [Skip bridging reference](https://skip.dev/docs/bridging/) — supported/unsupported bridging patterns
- [Skip modes](https://skip.dev/docs/modes/) — Fuse vs Lite mode differences

### Skip runtime
- `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` — `Compose()`, `_ComposeContent()`, `Evaluate()` base implementations
- `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/PresentationRoot.swift` — root composition entry, `MaterialTheme` wrapper

### This project
- `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/TabView.swift` — workaround implementation
- `.planning/research/PITFALLS.md` Pitfall 5 — cross-reference entry

---

## 10. Implementation Roadmap

| Priority | Phase | What | Where | Dependency |
|----------|-------|------|-------|------------|
| **1 (now)** | Phase 1 | `letWithDefault` classification + `remember { Swift_peer }` in Evaluate | `KotlinStatementTypes.swift`, `StatementTypes.swift`, `KotlinBridgeToKotlinVisitor.swift` | None |
| **2 (next)** | Phase 2 | Input-change detection for mixed views (constructor params + let defaults) | `KotlinBridgeToKotlinVisitor.swift` (add `Swift_inputsHash`) | Phase 1 |
| **3 (next)** | Phase 3 | Verify `.id()` ↔ `key()` cooperates with peer remembering | skip-ui tests | Phase 1 (`.id()` already maps to `key()` — verify integration) |
| **4 (when needed)** | — | ForEach identity — `id:` → Compose `key` in `items()` | skip-ui | None (independent) |
| **5 (when profiling)** | Phase 4 | Input diffing — skip recomposition for unchanged inputs | skipstone | Phase 1 |

Phase 1 delivers ~90% of the practical value. Most views with `let`-with-default properties are root or near-root views with no constructor parameters (the `let store = Store(...)` pattern). The transpiler already generates `Evaluate` overrides with `rememberSaveable` for `@State` — extending this to `remember { Swift_peer }` for `let`-with-default follows the same structural pattern.

Phase 2 adds robustness for the less common mixed case. Phases 3-5 are incremental correctness and performance improvements.
