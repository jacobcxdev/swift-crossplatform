# Position Paper: Transpiler-First View Identity

> **Position:** The Skip transpiler (skipstone) should solve most identity problems at compile time.
> **Date:** 2026-03-01
> **Status:** Proposal

## Thesis

The transpiler already has the richest view of program structure available anywhere in the system. It parses the full Swift AST, understands type conformances, knows which properties are `let`-with-default vs constructor params vs `@State`, and controls the exact shape of every generated Kotlin class. Rather than scattering identity logic across 24+ container files in skip-ui -- each independently responsible for `key()` wrapping, each a potential site for omission -- the transpiler should inject identity metadata and key scopes directly into the generated code. The runtime becomes a consumer of identity, not its architect.

This paper argues that the transpiler can and should own structural identity injection, ViewBuilder conditional identity, ForEach key propagation, and the `stateVariables.isEmpty` guard fix. It identifies what genuinely cannot be solved at compile time and assesses the complexity cost.

---

## 1. What the Transpiler Already Generates

### 1.1 Peer Remembering (Phases 1 and 2)

The transpiler already performs sophisticated identity-aware code generation in `KotlinBridgeToKotlinVisitor.swift` (lines 1619-1793). For every bridged `View` struct, it:

1. **Classifies properties** into constructor params (bridgable and unbridged), `let`-with-default, and `@State`/`@Environment` variables.
2. **Phase 1** (`canRememberPeer`): For views with only `let`-with-default properties, generates:
   ```kotlin
   val peerHandle = remember { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }
   val swapped = peerHandle.peer != Swift_peer
   if (swapped) { peerHandle.swapFrom(Swift_peer); Swift_peer = peerHandle.peer }
   ```
3. **Phase 2** (`canRememberPeerWithInputCheck`): For mixed views, generates `Swift_inputsHash` cdecl and uses `remember(currentHash)` keyed remembering.
4. **Evaluate override**: Returns `listOf(this.asRenderable())` to defer body evaluation to the Render phase.
5. **`_ComposeContent` override**: Runs peer remembering + observation tracking + body evaluation inside the Render-phase composition scope.

This is already a transpiler-driven identity system. The peer's lifecycle is determined entirely by AST analysis at compile time. The runtime merely executes the generated `remember` calls.

### 1.2 ViewBuilder Lowering

The transpiler transforms `@ViewBuilder` bodies into `ComposeBuilder { composectx -> ... }` closures (`KotlinSwiftUITransformer.swift`, line 704-719). Each view expression in the body gets a `.Compose(composectx)` tail call appended. `if/else` branches become standard Kotlin `if/else` blocks inside the lambda.

At runtime, `ComposeBuilder.Evaluate()` collects renderables via a `Composer` callback into a flat `MutableList<Renderable>`. The `if/else` control flow executes directly -- whichever branch runs adds its renderables to the list. There is no `_ConditionalContent` wrapper, no branch tagging, no structural distinction between the two sides.

### 1.3 ForEach Transpilation

ForEach is not transpiled specially -- it is a runtime skip-ui type. The transpiler's only involvement is lowering the `@ViewBuilder content` closure parameter. ForEach's `Evaluate` method iterates the data collection, calls the content closure per item, and tags each iteration's renderables with the item's identity via `taggedRenderable()` / `taggedIteration()` (ForEach.swift lines 273-303).

The tagging uses `.tag()` modifiers, which containers must then read via `renderable.composeKey` and wrap with `key()`. This is the manual, container-by-container approach that the audit found 14 paths missing.

---

## 2. Transpiler-Injected Structural Identity

### 2.1 The `__structuralID` Concept

Every view expression in a `@ViewBuilder` body occupies a unique position in the AST. The transpiler can assign a deterministic string identifier based on this position:

```
<ModuleName>/<FileName>:<Line>:<Column>
```

For example, a view body:
```swift
var body: some View {
    if showHeader {
        HeaderView()        // ID: "MyApp/ContentView.swift:12:8"
    }
    CounterCard(store: s)   // ID: "MyApp/ContentView.swift:14:4"
}
```

The transpiler would inject this as a companion constant or inline string in the generated Kotlin:

```kotlin
// Generated for ContentView.body
ComposeBuilder { composectx ->
    if (showHeader) {
        HeaderView().Compose(composectx)  // structural position: branch-true:0
    }
    CounterCard(store = s).Compose(composectx)  // structural position: root:1
    ComposeResult.ok
}
```

### 2.2 ID Scheme: Type + Position, Not File Path

File path + line number is brittle across refactors. A better scheme uses the structural position within the view body's AST:

- **Root-level expressions**: `root:0`, `root:1`, `root:2` (ordinal position)
- **Conditional branches**: `if:0:true:0`, `if:0:false:0` (if-index, branch, child-index)
- **Switch cases**: `switch:0:case(value):0`
- **ForEach bodies**: inherit identity from the data's `id` (already handled)

This produces stable IDs that survive file moves and line number changes. The transpiler walks the AST and assigns these positionally.

### 2.3 How It Would Be Injected

**Option A: Wrap each view expression in `key()`**

The transpiler already adds `.Compose(composectx)` tail calls. It could wrap each in a `key()` scope:

```kotlin
ComposeBuilder { composectx ->
    androidx.compose.runtime.key("if:0:true") {
        if (showHeader) {
            HeaderView().Compose(composectx)
        }
    }
    androidx.compose.runtime.key("root:1") {
        CounterCard(store = s).Compose(composectx)
    }
    ComposeResult.ok
}
```

This is the most direct approach but changes the Compose group structure. The `key()` call creates a movable group that Compose can track across recompositions.

**Option B: Attach as metadata on the Renderable**

Add a `structuralID` property to every generated view class:

```kotlin
class ContentView_HeaderView(...) : View() {
    companion object {
        const val __structuralID = "ContentView:if:0:true:0"
    }
}
```

Containers then read `renderable.structuralID` instead of (or in addition to) `composeKey`. This is less invasive to the Compose tree but requires container cooperation -- the very thing the audit found unreliable.

**Recommendation: Option A for ViewBuilder bodies, Option B as fallback identity.** The transpiler wraps each top-level view expression in a `key()` during ViewBuilder lowering. This eliminates the need for every container to independently implement identity. For ForEach items, Option B provides identity metadata that containers can read without needing to understand tag semantics.

---

## 3. ViewBuilder Conditional Identity

### 3.1 The Problem

SwiftUI's `@ViewBuilder` uses `_ConditionalContent<TrueContent, FalseContent>` to give each `if/else` branch distinct structural identity. Toggling the condition destroys one branch's state and creates the other's.

The Skip transpiler lowers `if/else` to plain Kotlin control flow. The `ComposeBuilder.Evaluate()` method flattens everything into a `MutableList<Renderable>`. If an `if` branch adds a view, it shifts all subsequent views' positions, causing state migration.

### 3.2 The Transpiler Fix

The transpiler sees `if/else` as `IfExpressionSyntax` / `KotlinIf` nodes in the AST. During ViewBuilder lowering, it can wrap each branch in a `key()` scope:

```kotlin
// Swift source:
//   if flag { Text("A") }
//   Text("B")

// Current transpiler output:
ComposeBuilder { composectx ->
    if (flag) { Text("A").Compose(composectx) }
    Text("B").Compose(composectx)
    ComposeResult.ok
}

// Proposed transpiler output:
ComposeBuilder { composectx ->
    androidx.compose.runtime.key("branch:0:true") {
        if (flag) { Text("A").Compose(composectx) }
    }
    // Even when flag=false, the key scope exists but is empty.
    // Compose preserves the slot, so Text("B") stays at a stable position.
    androidx.compose.runtime.key("root:1") {
        Text("B").Compose(composectx)
    }
    ComposeResult.ok
}
```

The critical insight: the `key()` scope wraps the entire `if` block, not just the true branch. When the condition is false, the key scope still exists in the Compose slot table as an empty group. This means `Text("B")` always occupies the same structural position regardless of `flag`.

For `if/else`:
```kotlin
androidx.compose.runtime.key("branch:0") {
    if (flag) {
        androidx.compose.runtime.key("true") {
            TextFieldA().Compose(composectx)
        }
    } else {
        androidx.compose.runtime.key("false") {
            TextFieldB().Compose(composectx)
        }
    }
}
```

Now toggling `flag` destroys one inner key scope and creates the other, matching SwiftUI's `_ConditionalContent` semantics.

### 3.3 Implementation in the Transpiler

The `KotlinSwiftUITransformer` already walks the code block to add `.Compose(composectx)` tail calls. The modification is:

1. When processing a `KotlinIf` node inside a ViewBuilder context, wrap the entire `if` in `key("branch:<index>")`.
2. Wrap each branch body in `key("true")` / `key("false")` (or `key("case:<index>")` for multi-branch).
3. For standalone `if` (no `else`), still wrap in an outer `key()` so the conditional's presence/absence doesn't shift siblings.
4. For `switch`/`when` expressions, wrap each case in `key("case:<label>")`.

The AST traversal already distinguishes `KotlinIf` from other expressions. The change is additive -- wrap, don't restructure.

---

## 4. Transpiler-Generated ForEach `key()` Injection

### 4.1 The Current Problem

ForEach tags each renderable with `.tag(id)` during Evaluate. Containers must then:
1. Read `renderable.composeKey` (which extracts the tag value)
2. Wrap with `key(composeKey ?? i)` in their render loops

The audit found 14 render loop paths that omit this wrapping. Every new container or animation path is another potential omission.

### 4.2 Transpiler-Side Solution

The transpiler cannot directly modify ForEach (it is a runtime type, not a transpiled view). However, it can modify how the `_ComposeContent` render loop works for ALL transpiled views.

Currently, the transpiler generates (line 1789):
```kotlin
for (renderable in renderables) { renderable.Render(context = context) }
```

The transpiler could instead generate:
```kotlin
for ((i, renderable) in renderables.withIndex()) {
    val rKey = (renderable as? skip.ui.IdentifiedRenderable)?.identityKey ?: i
    androidx.compose.runtime.key(rKey) {
        renderable.Render(context = context)
    }
}
```

This applies to every transpiled view's `_ComposeContent`. Since transpiled views are the outermost containers that kick off rendering, this provides a baseline identity layer.

### 4.3 Extending to Runtime Containers

The transpiler fix above only covers transpiled views. Runtime containers (VStack, HStack, ZStack, etc.) still need their own `key()` wrapping. But the transpiler can help here too:

**Generate a utility function** that all containers call:
```kotlin
// Generated once in a support file
@Composable
fun RenderWithIdentity(
    renderables: List<Renderable>,
    context: ComposeContext,
    render: @Composable (Renderable, ComposeContext) -> Unit = { r, c -> r.Render(context = c) }
) {
    for ((i, renderable) in renderables.withIndex()) {
        val rKey = renderable.composeKey ?: i
        androidx.compose.runtime.key(rKey) { render(renderable, context) }
    }
}
```

This shifts the burden from 24 container files to one generated utility. Containers that need custom rendering (spacing, animation) can still use the utility with a custom `render` lambda.

This is a hybrid approach: the transpiler generates the utility, but runtime containers must adopt it. The advantage is that adoption is a one-line change per container rather than reimplementing the `key()` pattern each time.

---

## 5. Fixing the `stateVariables.isEmpty` Guard

### 5.1 The Problem

Line 1734 of `KotlinBridgeToKotlinVisitor.swift`:
```swift
if (canRememberPeer || canRememberPeerWithInputCheck) && stateVariables.isEmpty {
```

Views with both `@State` properties and `let`-with-default properties get state syncing (via `swiftUIEvaluate`) but NOT peer remembering. The `stateVariables.isEmpty` guard is mutually exclusive: you get one or the other.

A view like:
```swift
struct MyCard: View {
    @State private var count = 0
    let instanceID = UUID()  // let-with-default
    var body: some View { ... }
}
```

Gets `Evaluate` with `rememberSaveable` for `count`, but `instanceID` is recreated every recomposition because there is no `_ComposeContent` with `remember { SwiftPeerHandle }`.

### 5.2 The Transpiler Fix

The fix is to merge both code paths into a single `_ComposeContent` override. The transpiler already generates two separate overrides:

- **State path** (`swiftUIEvaluate`): Generates `Evaluate` with `rememberSaveable` init/sync calls
- **Peer path** (lines 1734-1793): Generates `Evaluate` returning `asRenderable()` + `_ComposeContent` with `remember`

The merged approach:

1. **Always generate `_ComposeContent`** when `canRememberPeer || canRememberPeerWithInputCheck` is true, regardless of `stateVariables`.
2. **Move `rememberSaveable` calls into `_ComposeContent`**, after the peer remembering block. State init/sync must happen in the Render phase anyway for `key()` scopes to be stable.
3. **The `Evaluate` override** returns `listOf(this.asRenderable())` in all cases (deferring everything to Render).

The generated code would look like:
```kotlin
override fun Evaluate(context: ComposeContext, options: Int): List<Renderable> {
    // State init (rememberSaveable)
    val count_state = rememberSaveable { mutableStateOf(Swift_initState_count(Swift_peer)) }
    Swift_syncState_count(Swift_peer, count_state.value)
    return listOf(this.asRenderable())
}

override fun _ComposeContent(context: ComposeContext) {
    // Peer remembering
    val peerHandle = remember { SwiftPeerHandle(Swift_peer, ::Swift_retain, ::Swift_release) }
    val swapped = peerHandle.peer != Swift_peer
    if (swapped) { peerHandle.swapFrom(Swift_peer); Swift_peer = peerHandle.peer }
    // Body evaluation
    ViewObservation.startRecording?.invoke()
    StateTracking.pushBody()
    val renderables = body().Evaluate(context = context, options = 0)
    StateTracking.popBody()
    ViewObservation.stopAndObserve?.invoke()
    for (renderable in renderables) { renderable.Render(context = context) }
}
```

**Complexity note:** The state init/sync calls currently live in `Evaluate` because `rememberSaveable` needs a composition scope. Moving them requires verifying that the Evaluate-phase composition scope (provided by the parent container's `Compose` call) is equivalent to the `_ComposeContent` Render-phase scope. Since `_ComposeContent` is `@Composable`, this should work, but it needs testing for `rememberSaveable` key stability.

An alternative is to keep state init in `Evaluate` (where it currently works) and only add peer remembering in `_ComposeContent`. This means `Evaluate` still runs for state sync but returns `asRenderable()` to defer body evaluation:

```kotlin
override fun Evaluate(context: ComposeContext, options: Int): List<Renderable> {
    val count_state = rememberSaveable { mutableStateOf(Swift_initState_count(Swift_peer)) }
    Swift_syncState_count(Swift_peer, count_state.value)
    return listOf(this.asRenderable())
}
```

This is a smaller change and preserves the existing state sync behaviour.

---

## 6. What Cannot Be Solved at Compile Time

### 6.1 Dynamic Data Identity

ForEach iterates runtime data collections. The identity of each item (`id` keypath or `Identifiable` conformance) is a runtime value. The transpiler cannot know at compile time that item 3 will have UUID `abc-123`. It can generate the key-wrapping infrastructure, but the actual key values must come from runtime.

### 6.2 User-Applied `.id()` and `.tag()`

When a developer writes `.id(someValue)` or `.tag(selection)`, the value is a runtime expression. The transpiler can ensure the modifier machinery exists, but cannot predict the value or validate uniqueness.

### 6.3 Container Render Loop Customisation

Runtime containers like VStack, HStack, ZStack, and LazyVStack have custom render logic (spacing, animation, measurement). The transpiler does not generate these containers -- they are hand-written skip-ui code. The transpiler can provide utilities (Section 4.3), but cannot force adoption.

### 6.4 Cross-Recomposition State Migration

When Compose recomposes, it matches slot table entries by position + key. The transpiler can inject keys, but the actual matching is Compose's internal algorithm. Edge cases like duplicate keys, key type mismatches, or slot table corruption are runtime Compose behaviour that the transpiler cannot control.

### 6.5 AnyView Type Erasure

`AnyView` erases the wrapped view's type at runtime. The transpiler generates the wrapping code, but cannot know at compile time which concrete type will be wrapped. Identity for `AnyView` contents must be runtime-determined.

### 6.6 Observation and Recomposition Timing

When a `@State` or `@Observable` value changes, Compose schedules recomposition. The transpiler controls the observation registration code, but the timing and scope of recomposition is Compose's runtime decision.

---

## 7. Feasibility Assessment

### 7.1 Complexity Budget

| Change | Transpiler Files | Estimated LOC | Risk |
|--------|-----------------|---------------|------|
| ViewBuilder branch `key()` wrapping | KotlinSwiftUITransformer.swift | ~60 | Medium -- must handle nested if/else, switch, guard |
| `_ComposeContent` render loop keying | KotlinBridgeToKotlinVisitor.swift | ~15 | Low -- additive change to existing generation |
| `stateVariables.isEmpty` guard removal | KotlinBridgeToKotlinVisitor.swift | ~40 | Medium -- state sync timing change needs testing |
| `RenderWithIdentity` utility generation | New generated support file or inline | ~25 | Low -- pure addition, no existing code changes |
| Structural ID companion constants | KotlinBridgeToKotlinVisitor.swift | ~30 | Low -- metadata only, no behavioural change |

**Total: ~170 lines of transpiler changes.** Compare this to the audit's remediation plan, which requires touching 15+ skip-ui container files with 30+ individual `key()` insertions, each a potential source of bugs.

### 7.2 Risk Analysis

**Transpiler bugs are high-blast-radius.** A bug in `KotlinBridgeToKotlinVisitor` affects every generated view. However:

- The peer remembering phases (1 and 2) already demonstrate that complex code generation in this file works reliably.
- The changes are additive wrapping (inserting `key()` around existing expressions), not restructuring.
- Every change produces observable Kotlin output that can be inspected and tested via `BridgeToKotlinTests.swift`.
- The existing test infrastructure (`SkipSyntaxTests/BridgeToKotlinTests.swift`) validates generated Kotlin shapes.

**Compose `key()` interaction risks:**
- Excessive `key()` nesting could theoretically impact performance, but Compose is designed for key-heavy usage (LazyColumn uses keys on every item).
- Duplicate structural IDs would cause Compose exceptions. The positional scheme (`root:0`, `branch:0:true`) is deterministic and unique within a body, so duplicates should not occur.

**Backwards compatibility:**
- All changes produce strictly more `key()` scopes in generated code. Existing code that works without keys will continue to work -- keys are additive.
- Views that previously lost state due to missing keys will now preserve it. This is a behavioural change, but it is the *correct* behaviour.

### 7.3 Testing Strategy

1. **Unit tests in BridgeToKotlinTests.swift**: Assert that generated Kotlin for `if/else` bodies contains `key()` wrappers. Assert that views with `@State` + `let`-with-default get both state sync and peer remembering.
2. **Integration tests**: The existing `fuse-app` IdentityFeature exercises ForEach deletion. Add cases for conditional branches and mixed stateful/let-with-default views.
3. **Snapshot testing**: Capture generated Kotlin for representative view patterns and snapshot-test for regressions.

---

## 8. Summary: What the Transpiler Should Own

| Concern | Current Owner | Proposed Owner | Rationale |
|---------|--------------|----------------|-----------|
| Peer lifecycle (`remember`) | Transpiler | Transpiler (no change) | Already working |
| ViewBuilder branch identity | None (gap) | Transpiler | AST has branch structure; runtime flat list does not |
| ForEach item identity keying | 24 container files | Transpiler utility + containers | Transpiler generates utility; containers adopt it |
| `@State` + let-with-default | Broken (gap) | Transpiler | Guard removal is a transpiler-only change |
| Structural ID metadata | None | Transpiler | Only the transpiler knows AST position |
| `.id()` / `.tag()` normalisation | Runtime (skip-ui) | Runtime (skip-ui) | Values are runtime; transpiler cannot help |
| Container-specific rendering | Runtime (skip-ui) | Runtime (skip-ui) | Custom layout logic is inherently runtime |

The transpiler should own everything that can be determined from the AST. The runtime should own everything that depends on dynamic values. The current system puts too much identity logic in the runtime, where it is fragile and manually maintained. Shifting the balance toward the transpiler reduces the surface area for identity bugs from 24 container files to 2 transpiler files, with deterministic, testable output.
