# Phase 10: NavigationStack Path Binding on Android - Research

**Researched:** 2026-02-23
**Domain:** TCA NavigationStack path binding on Android via Skip Fuse mode
**Confidence:** HIGH

## Summary

Phase 10 enables TCA's `NavigationStack(path:root:destination:)` extension on Android by addressing the type erasure incompatibility between TCA's `Binding<StackState<State>.PathView>` and skip-ui's `NavigationStack(path: Any)` which force-casts to `Binding<[Any]>?`. The current state has three `#if !os(Android)` guards in `NavigationStack+Observation.swift` (lines 74, 111, 150) that disable TCA's store-powered NavigationStack on Android. ContactsFeature.swift has a `#if os(Android)` workaround that renders a plain `NavigationStack` without path binding, making contact detail navigation non-functional on Android.

The core challenge is NOT that skip-ui lacks NavigationStack support -- skip-ui has full NavigationStack with path binding (`Binding<[Any]>`), `.navigationDestination(for:destination:)`, push/pop animations, and back handling. The challenge is a **type mismatch**: TCA produces `Binding<StackState<State>.PathView>` (a custom `RandomAccessCollection` struct), but skip-ui's `NavigationStack(path: Any)` force-casts the incoming value to `Binding<[Any]>?`, which crashes because `PathView` is not `Array<Any>`. Additionally, TCA's modern `NavigationStack.init(path:root:destination:)` is an `extension NavigationStack where Data == StackState<State>.PathView` -- but skip-ui's `NavigationStack` is non-generic, so this extension cannot compile on Android.

The fix requires an Android-specific adapter that bridges TCA's `StackState.PathView` into `Binding<[Any]>` for skip-ui consumption, plus destination type routing verification.

**Primary recommendation:** Create a TCA-side Android adapter in `NavigationStack+Observation.swift` that provides an `#if os(Android)` alternative `NavigationStack.init(path:root:destination:)` overload. This overload accepts the same TCA `Binding<Store<StackState<State>, StackAction<State, Action>>>` signature but internally converts `PathView` to `Binding<[Any]>` and registers destinations via `navigationDestination(for:)`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NAV-01 | `NavigationStack` with `$store.scope(state: \.path, action: \.path)` renders on Android | Android adapter bridges `PathView` -> `Binding<[Any]>` for skip-ui's `NavigationStack(path:root:)` |
| NAV-02 | Path append pushes new destination onto stack on Android | Adapter's `set` closure maps `[Any]` count increase to `StackAction.push(id:state:)` |
| NAV-03 | Path removeLast pops top destination on Android | Adapter's `set` closure maps `[Any]` count decrease to `StackAction.popFrom(id:)` |
| TCA-32 | `StackState<Element>` initializes, appends, indexes by StackElementID on Android | Already verified in NavigationStackTests -- data layer works; this phase adds view-layer integration |
| TCA-33 | `StackAction` routes through `forEach` on Android | Already verified in NavigationStackTests -- data layer works; this phase adds view-layer integration |
</phase_requirements>

## Standard Stack

### Core

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| TCA NavigationStack+Observation | `forks/swift-composable-architecture/.../Observation/NavigationStack+Observation.swift` | `NavigationStack.init(path:root:destination:)` extension + `_NavigationDestinationViewModifier` + `Binding.scope` for StackState | The ONLY stack navigation integration layer between TCA and SwiftUI |
| TCA StackReducer | `forks/swift-composable-architecture/.../Reducer/Reducers/StackReducer.swift` | `.forEach` for stack, `StackState`/`StackAction` data types | Zero Android guards; data layer fully functional |
| Skip NavigationStack | `forks/skip-ui/.../Containers/Navigation.swift` (lines 92-129) | Non-generic NavigationStack with `Binding<[Any]>?` path, `Binding<NavigationPath>?`, Compose NavHost rendering | Skip's complete NavigationStack implementation |
| Skip Navigator | `forks/skip-ui/.../Containers/Navigation.swift` (lines 690-864) | `navigate(to:)`, `navigateBack()`, `navigateToPath()` -- manages Compose back stack sync with path binding | Skip's path binding sync engine |
| Skip navigationDestination | `forks/skip-ui/.../Containers/Navigation.swift` (line 1004) | `navigationDestination(for:destination:)` -- registers destinations keyed by `D.Type` metatype | Type-based destination routing |

### Supporting

| Component | Location | Purpose | When to Use |
|-----------|----------|---------|-------------|
| `StackState.PathView` | `NavigationStack+Observation.swift` (lines 532-577) | `RandomAccessCollection` of `Component` (id + element) | Passed as path data type to SwiftUI NavigationStack on iOS |
| `StackState.Component` | `NavigationStack+Observation.swift` (lines 511-530) | `Hashable` wrapper holding `StackElementID` + `Element` | Each stack entry; used as `navigationDestination(for:)` key type |
| `_NavigationDestinationViewModifier` | `NavigationStack+Observation.swift` (lines 194-218) | ViewModifier that registers `.navigationDestination(for: Component.self)` and scopes child stores | Wires destination routing to TCA store scoping |
| ContactsFeature | `examples/fuse-app/Sources/FuseApp/ContactsFeature.swift` | Full TCA navigation showcase with `#if os(Android)` workaround | Must be unified to single code path after fix |
| NavigationStackTests | `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift` | Existing data-layer stack tests (push, pop, child mutation, scope binding) | Must be extended with Android adapter tests |

## Architecture Patterns

### Pattern 1: Android NavigationStack Adapter (THE critical pattern)

**What:** An `#if os(Android)` alternative to the iOS `extension NavigationStack where Data == PathView` that cannot compile on Android because skip-ui's NavigationStack is non-generic.

**Why needed:** Three incompatibilities must be bridged:

| Layer | iOS (works) | Android (broken) | Fix |
|-------|-------------|-------------------|-----|
| NavigationStack generics | `NavigationStack<Data, Root>` where `Data == PathView` | `NavigationStack` is non-generic | Provide free function or View wrapper instead of extension |
| Path binding type | `Binding<PathView>` | `Binding<[Any]>?` via force-cast | Convert `PathView` -> `[Any]` in `Binding` get/set |
| Destination routing | `.navigationDestination(for: Component.self)` | `type(of: targetValue)` keyed lookup | Verify `Component` type identity preserved through JVM |

**Approach:** Add an `#if os(Android)` block inside `NavigationStack+Observation.swift` that provides a **View struct** (not an extension) with the same external API:

```swift
#if os(Android)
@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public struct _TCANavigationStack<State: ObservableState, Action, Root: View, Destination: View>: View {
    let pathBinding: Binding<Store<StackState<State>, StackAction<State, Action>>>
    let root: Root
    let destination: (Store<State, Action>) -> Destination
    let fileID: StaticString
    let filePath: StaticString
    let line: UInt
    let column: UInt

    public var body: some View {
        let store = pathBinding.wrappedValue
        let androidPath = Binding<[Any]>(
            get: {
                store.currentState.path.map { $0 as Any }
            },
            set: { newPath in
                let currentPath = store.currentState.path
                if newPath.count > currentPath.count,
                   let last = newPath.last as? StackState<State>.Component {
                    store.send(.push(id: last.id, state: last.element))
                } else if newPath.count < currentPath.count {
                    store.send(.popFrom(id: store.currentState.ids[newPath.count]))
                }
            }
        )
        NavigationStack(path: androidPath) {
            root
                .navigationDestination(for: StackState<State>.Component.self) { component in
                    destination(
                        store.scope(
                            component: component,
                            fileID: fileID,
                            filePath: filePath,
                            line: line,
                            column: column
                        )
                    )
                }
        }
    }
}
#endif
```

Then provide a convenience `NavigationStack` initializer via a **free function** or extend `View` with a method that returns `_TCANavigationStack` on Android:

```swift
#if os(Android)
@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public func NavigationStack<State: ObservableState, Action, Destination: View, R: View>(
    path: Binding<Store<StackState<State>, StackAction<State, Action>>>,
    @ViewBuilder root: () -> R,
    @ViewBuilder destination: @escaping (Store<State, Action>) -> Destination,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) -> some View {
    _TCANavigationStack(
        pathBinding: path, root: root(), destination: destination,
        fileID: fileID, filePath: filePath, line: line, column: column
    )
}
#endif
```

**Key consideration:** On iOS, `NavigationStack(path:root:destination:)` is an extension on `NavigationStack` struct itself. On Android, it must be a free function or separate View type because skip-ui's `NavigationStack` is non-generic and cannot be extended with generic constraints.

### Pattern 2: PathView to [Any] Binding Bridge

**What:** The `Binding<[Any]>` adapter that converts between TCA's `StackState.PathView` and skip-ui's expected `[Any]`.

**Critical details:**

1. **get direction** (`PathView` -> `[Any]`): Map each `Component` to `Any`. Skip's `navigateToPath()` iterates `path[pathIndex]` comparing with `state?.targetValue`. The `targetValue` equality check uses `!=` on `Any` -- this works if `Component` has correct `Equatable`/`Hashable` conformance (it does, via `StackElementID`).

2. **set direction** (`[Any]` -> TCA actions): When skip-ui modifies the path (e.g., user presses back), it calls `path.wrappedValue.popLast()`. The `set` closure must compare old/new counts and dispatch `.push` or `.popFrom` actions. The `set` closure receives `[Any]` where elements are `Component` values (cast from `Any`).

3. **Destination registration:** `navigationDestination(for: StackState<State>.Component.self)` registers `Component` as the type key. When skip-ui calls `navigate(toKeyed:)`, it looks up `type(of: targetValue)` in the destination dictionary (line 704). The runtime type of each `[Any]` element must be `StackState<State>.Component` -- which it is, because we put `Component` values into the array.

**Risk:** JVM generic type erasure in Kotlin may affect `type(of:)` lookup. On JVM, `StackState<PathA.State>.Component` and `StackState<PathB.State>.Component` may erase to the same type. This is a runtime-only risk that must be verified on Android emulator.

### Pattern 3: ContactsFeature Unification

**What:** Remove the `#if os(Android)` / `#else` branch in `ContactsView.body` (lines 276-303) and use a single `NavigationStack(path:root:destination:)` code path for both platforms.

**Before (current):**
```swift
#if os(Android)
NavigationStack {
    contactsList
}
// ... sheet only, no path binding, no destination routing
#else
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
    contactsList
} destination: { store in
    switch store.case { ... }
}
// ... full navigation
#endif
```

**After:**
```swift
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
    contactsList
} destination: { store in
    switch store.case {
    case let .detail(detailStore):
        ContactDetailView(store: detailStore)
    }
}
.sheet(
    item: $store.scope(state: \.destination?.addContact, action: \.destination.addContact)
) { addStore in
    NavigationStack {
        AddContactView(store: addStore)
    }
}
```

Also remove the TODO comment at lines 23-27 of ContactsFeature.swift.

### Anti-Patterns to Avoid

- **DO NOT try to make skip-ui's `NavigationStack` generic** -- it is deliberately non-generic in the Skip transpiler. The adaptation must happen on the TCA side.
- **DO NOT use `NavigationStackStore`** (deprecated) -- it uses `ViewStore`/`ObservedObject` patterns that are deprecated. The fix must target the modern `NavigationStack(path:root:destination:)` API.
- **DO NOT enable the `ObservedObject.Wrapper` scope extension** (line 74 guard) -- `ObservedObject.Wrapper` is deprecated-era TCA. Keep it guarded.
- **DO NOT enable the `Perception.Bindable` scope extension** (line 111 guard) -- `Perception.Bindable` type does not exist on Android. Keep it guarded.
- **DO NOT remove the `store.send(_:animation:)` guards** -- `withTransaction` is `fatalError()` on Android.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stack navigation | Custom Compose NavHost | skip-ui NavigationStack + TCA adapter | Skip handles animations, back button, state restoration |
| Path binding sync | Manual path watcher | Skip's `Navigator.navigateToPath()` via `Binding<[Any]>` | Skip's sync algorithm handles push/pop/diff correctly |
| Destination routing | Custom destination map | `navigationDestination(for:destination:)` | Skip aggregates via PreferenceKey, handles type matching |
| Store scoping per element | Manual child store creation | `store.scope(component:)` (existing TCA internal) | TCA's `IfLetCore` handles element lifecycle correctly |
| NavigationLink state wrapping | Manual Component creation | TCA's existing `NavigationLink(state:)` extension | Already wraps state in `Component` with `@Dependency(\.stackElementID)` |

**Key insight:** All the pieces exist. TCA has the data layer (StackState, StackAction, store scoping, NavigationLink wrapping). Skip has the view layer (NavigationStack, Navigator, destination routing). The only missing piece is the type bridge between `PathView` and `[Any]`.

## Common Pitfalls

### Pitfall 1: PathView-to-[Any] Force Cast Crash

**What goes wrong:** `NavigationStack(path: anyBinding)` where `anyBinding` is `Binding<PathView>` -- skip-ui does `path as! Binding<[Any]>?` which crashes because `PathView` is not `[Any]`.
**Why it happens:** Swift generics are invariant. `Binding<PathView>` cannot be cast to `Binding<[Any]>` even though `PathView` is a collection.
**How to avoid:** Always create a fresh `Binding<[Any]>` with explicit get/set closures that convert between types. Never pass TCA's native `Binding<PathView>` directly to skip-ui.
**Warning signs:** Runtime crash at `Navigation.swift:114` with `as! Binding<[Any]>?` cast failure.

### Pitfall 2: JVM Generic Type Erasure in Destination Lookup

**What goes wrong:** `navigationDestination(for: StackState<Path.State>.Component.self)` registers `Component` with a specific generic parameter. But at runtime on JVM, `type(of: component)` may return an erased type without the generic parameter, causing destination lookup to fail.
**Why it happens:** JVM erases generic type parameters at runtime. `StackState<A>.Component` and `StackState<B>.Component` may be the same type on JVM.
**How to avoid:** Test with a single path type first (simplest case). If lookup fails, use skip-ui's `destinationKeyTransformer` parameter to provide string-based keys instead of relying on `type(of:)`.
**Warning signs:** Push navigates but shows blank screen. `Navigator.navigate(toKeyed:)` returns false (no matching destination).

### Pitfall 3: Back Button Pop Not Reflected in TCA State

**What goes wrong:** User presses Android back button, Compose NavHost pops, but TCA `StackState` still has the popped element.
**Why it happens:** Skip's `Navigator.navigateBack()` calls `path.wrappedValue.popLast()` on the `[Any]` binding. If the binding's `set` closure doesn't dispatch `StackAction.popFrom`, TCA state diverges from UI.
**How to avoid:** The `Binding<[Any]>` set closure MUST dispatch `.popFrom` when count decreases. Verify with a test: push, then pop via the binding setter, then assert TCA path count.
**Warning signs:** TCA state shows 2 elements but only 1 screen is visible. Re-pushing fails because IDs don't match.

### Pitfall 4: Component Equality Through [Any]

**What goes wrong:** Skip's `navigateToPath()` compares `state?.targetValue != path[pathIndex]` using `Any` inequality. If `Component`'s `Equatable` conformance is not invoked (because the values are boxed as `Any`), every sync cycle looks like a diff.
**Why it happens:** `Any != Any` in Swift uses reference equality or crashes if Equatable is not dynamically dispatched. On JVM/Kotlin, `equals()` is used, which may work differently.
**How to avoid:** Verify that `Component` values cast to `Any` and back still compare equal via their `Hashable`/`Equatable` conformance. If not, provide a `destinationKeyTransformer` that extracts `component.id` as the string key.
**Warning signs:** NavigationStack constantly re-navigates (infinite push loop). Log shows `navigateToPath` running every recomposition.

### Pitfall 5: Free Function Shadowing NavigationStack Struct

**What goes wrong:** The Android free function `NavigationStack(path:root:destination:)` may conflict with skip-ui's `NavigationStack.init(path:root:)` at call sites, causing ambiguous overload resolution.
**Why it happens:** Swift resolves call sites by looking at both type initializers and free functions with the same name.
**How to avoid:** Use a distinct name for the Android adapter (e.g., `_TCANavigationStack`) and provide a `NavigationStack` overload only if testing confirms no ambiguity. Alternatively, use a View extension method like `.tcaNavigationStack(path:destination:)` if naming conflicts arise.
**Warning signs:** Compilation error about ambiguous use of `NavigationStack`.

## Code Examples

### TCA NavigationStack on Android (after fix)

```swift
// This compiles and works on BOTH platforms after the adapter
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            RootView()
        } destination: { store in
            switch store.case {
            case let .detail(detailStore):
                DetailView(store: detailStore)
            }
        }
    }
}
```

### Android Binding Bridge (internal implementation)

```swift
// Inside the Android adapter
let androidPath = Binding<[Any]>(
    get: {
        store.currentState.path.map { $0 as Any }
    },
    set: { newPath in
        let currentCount = store.currentState.count
        if newPath.count > currentCount,
           let component = newPath.last as? StackState<State>.Component {
            store.send(.push(id: component.id, state: component.element))
        } else if newPath.count < currentCount {
            store.send(.popFrom(id: store.currentState.ids[newPath.count]))
        }
    }
)
NavigationStack(path: androidPath) { ... }
```

### NavigationLink with State (already works)

```swift
// TCA's NavigationLink(state:) wraps in Component automatically
NavigationLink(state: AppFeaturePath.State.detail(
    DetailFeature.State(title: "Item")
)) {
    Text("Go to Detail")
}
```

### Destination Registration

```swift
// _NavigationDestinationViewModifier registers Component as destination type
.navigationDestination(for: StackState<State>.Component.self) { component in
    destination(
        store.scope(component: component, fileID: ..., filePath: ..., line: ..., column: ...)
    )
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NavigationStackStore` (deprecated) | `NavigationStack(path: $store.scope(...))` | TCA 1.7+ | Modern observable API; deprecated version guarded out |
| `Perception.Bindable` (backport) | `SwiftUI.Bindable` | iOS 17 / Skip Android | Perception unavailable on Android; SwiftUI.Bindable provided by Skip |
| `#if os(Android)` workaround in ContactsView | Single code path with adapter | This phase | Eliminates platform divergence in app code |

## Open Questions

1. **JVM generic type erasure for `Component` destination matching**
   - What we know: Skip's `navigationDestination(for:)` registers `D.Type` as key; `navigate(toKeyed:)` uses `type(of: targetValue)` for lookup
   - What's unclear: Whether `StackState<Path.State>.Component` preserves its full generic type identity on JVM at runtime
   - Recommendation: Test with a real Android build. If lookup fails, use `destinationKeyTransformer` with `String(describing: type(of: component))`

2. **Free function vs extension naming for Android adapter**
   - What we know: Extension on non-generic `NavigationStack` cannot add generic constraints; free function works but may shadow
   - What's unclear: Whether Swift/Skip resolves `NavigationStack(path:root:destination:)` to the free function without ambiguity
   - Recommendation: Start with free function. If ambiguous, rename to `_TCANavigationStack(...)` and use `typealias` or wrapper

3. **NavigationLink(state:) on Android**
   - What we know: TCA's `NavigationLink(state:label:)` extension (lines 264-359) wraps state in `Component` and passes to `NavigationLink(value:)`; Skip's NavigationLink supports `value:` parameter
   - What's unclear: Whether Skip's `NavigationLink.init(value:label:)` correctly calls `navigator.navigate(to: value)` with the `Component` value, triggering the registered destination
   - Recommendation: Verify with integration test. The extension is currently `#if !os(Android)` guarded (line 150 outer guard covers it implicitly) -- may need selective unguarding

4. **Store path subscript setter for NavigationStack binding**
   - What we know: `Store` has a subscript (lines 441-489) that converts `PathView` writes to `.push`/`.popFrom` actions
   - What's unclear: Whether this subscript is invoked on Android or only on iOS through SwiftUI's `NavigationStack` binding mechanism
   - Recommendation: The Android adapter bypasses this subscript by creating its own `Binding<[Any]>` with explicit push/pop logic. This is deliberate -- the subscript assumes `PathView` which skip-ui cannot provide.

## Sources

### Primary (HIGH confidence)
- Direct source analysis: `NavigationStack+Observation.swift` -- all 3 `#if !os(Android)` guards verified at lines 74, 111, 150
- Direct source analysis: `Navigation.swift` (skip-ui) -- `NavigationStack` struct (lines 92-129), `init(path: Any)` force-cast (line 114), `navigateToPath()` (lines 815-864), `navigationDestination(for:)` (line 1004), `navigate(toKeyed:)` type lookup (line 704)
- Direct source analysis: `ContactsFeature.swift` -- `#if os(Android)` workaround (lines 276-303), TODO comment (lines 23-27)
- Direct source analysis: `NavigationStackStore.swift` -- deprecated but shows the `PathView`-to-binding pattern (lines 178-199)
- Phase 5 research: `05-RESEARCH.md` -- full type erasure analysis, verified incompatibility
- Phase 5 deep dive: `research/nav-stack-type-erasure.md` -- detailed type chain analysis confirming crash

### Secondary (MEDIUM confidence)
- skip.dev documentation: NavigationStack listed as "high support" with path binding
- Phase 8 research: `research/pfw-swift-navigation.md` -- Android NavigationStack gap analysis, workaround documentation
- Milestone audit: `v1.0-MILESTONE-AUDIT.md` -- M1-ANDROID-NAV-STACK gap documented

### Tertiary (LOW confidence)
- JVM generic type erasure behavior for `type(of:)` lookup -- needs runtime verification on Android emulator

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components verified via direct source reading; skip-ui NavigationStack implementation fully traced
- Architecture patterns: HIGH -- adapter pattern derived from Phase 5 research and verified against skip-ui internals
- Pitfalls: HIGH for type erasure crash (source-verified); MEDIUM for JVM generic erasure (runtime-only); HIGH for back button sync (code path traced)
- Code examples: HIGH -- patterns derived from existing TCA code and skip-ui implementation

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (stable -- fork code under project control, skip-ui NavigationStack API unlikely to change)
