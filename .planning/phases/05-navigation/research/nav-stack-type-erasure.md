# NavigationStack Path Type Erasure Analysis

## Executive Summary

**Verdict: REQUIRES_ADAPTATION**

TCA's `NavigationStack` integration with Skip on Android faces two distinct incompatibilities:

1. **The modern TCA `NavigationStack.init(path:)` extension is entirely `#if !os(Android)` guarded** -- it does not compile on Android at all.
2. **The legacy `NavigationStackStore` compiles on Android** but passes a `Binding<StackState<State>.PathView>` to `NavigationStack(path:)`, which Skip receives as `Any` and force-casts to `Binding<[Any]>?`. This cast **will fail at runtime** because `PathView` is not `[Any]`.

Both paths are broken. The fix requires either adapting Skip's `NavigationStack` to accept `PathView`-like collections, or providing an Android-specific TCA adapter that bridges `PathView` into `[Any]`.

---

## 1. Skip's NavigationStack Implementation

### File: `forks/skip-ui/Sources/SkipUI/SkipUI/Containers/Navigation.swift`

Skip's `NavigationStack` is a non-generic struct (line 92):

```swift
// SKIP @bridge
public struct NavigationStack : View, Renderable {
    let root: ComposeBuilder
    let path: Binding<[Any]>?                          // line 94
    let navigationPath: Binding<NavigationPath>?       // line 95
    let destinationKeyTransformer: ((Any) -> String)?  // line 96
```

It provides three initializers:

| Init | Stores into |
|------|-------------|
| `init(root:)` (line 98) | `path = nil`, `navigationPath = nil` |
| `init(path: Binding<NavigationPath>, root:)` (line 105) | `navigationPath = path` |
| `init(path: Any, root:)` (line 112) | `path = path as! Binding<[Any]>?` |

**The critical initializer is the third one** (line 112-117). It receives `path` as `Any` and performs an unconditional force-cast:

```swift
public init(path: Any, @ViewBuilder root: () -> any View) {
    self.root = ComposeBuilder.from(root)
    self.path = path as! Binding<[Any]>?   // FORCE CAST
    self.navigationPath = nil
    self.destinationKeyTransformer = nil
}
```

This is an `as!` to `Binding<[Any]>?` (optional). If the incoming value is a `Binding<[Any]>`, it succeeds. If it's `nil`, it succeeds (producing `nil`). For **any other `Binding` type**, it crashes at runtime.

### How Skip uses the path binding

In `Navigator.navigateToPath()` (line 815-864), Skip:

1. Reads `self.path?.wrappedValue` to get `[Any]` (line 816)
2. Iterates elements comparing `state?.targetValue != path[pathIndex]` (line 832) -- **identity/equality comparison of `Any` values**
3. Calls `navigate(toKeyed: path[i])` for new elements (line 862), which looks up the destination by `type(of: targetValue)` as the key (line 704)

For `navigate(to:)` (line 689-697), Skip appends to the path binding:
```swift
func navigate(to targetValue: Any) {
    if let path {
        path.wrappedValue.append(targetValue)  // Appends Any to [Any]
    }
}
```

### Destination registration

`navigationDestination(for:destination:)` (line 1004) registers a destination keyed by the **data type**:

```swift
public func navigationDestination<D>(for data: D.Type, ...) -> any View where D: Any {
    let destinations: NavigationDestinations = [data: NavigationDestination(...)]
    return preference(key: NavigationDestinationsPreferenceKey.self, value: destinations)
}
```

The key is `D.Type` (the metatype). When navigating, Skip looks up `type(of: targetValue)` in this dictionary. This means **the runtime type of each path element must match a registered destination type**.

---

## 2. TCA's NavigationStack Integration

### Modern API: `NavigationStack.init(path:root:destination:)` -- UNAVAILABLE ON ANDROID

**File:** `forks/swift-composable-architecture/.../NavigationStack+Observation.swift`, line 150-192

This entire extension is guarded:

```swift
#if !os(Android)
@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension NavigationStack {
  public init<State, Action, Destination: View, R>(
    path: Binding<Store<StackState<State>, StackAction<State, Action>>>,
    @ViewBuilder root: () -> R,
    @ViewBuilder destination: @escaping (Store<State, Action>) -> Destination,
    ...
  )
  where
    Data == StackState<State>.PathView,
    Root == ModifiedContent<R, _NavigationDestinationViewModifier<State, Action, Destination>>
```

On iOS, this works because SwiftUI's real `NavigationStack` is generic:
```
NavigationStack<Data: RandomAccessCollection, Root: View> where Data.Element: Hashable
```

TCA constrains `Data == StackState<State>.PathView` and uses `navigationDestination(for: StackState<State>.Component.self)` to register routing by `Component` type.

**This cannot work on Android** because Skip's `NavigationStack` is non-generic and does not have the `Data` type parameter.

### Legacy API: `NavigationStackStore` -- PARTIALLY AVAILABLE ON ANDROID

**File:** `forks/swift-composable-architecture/.../SwiftUI/NavigationStackStore.swift`, line 33-211

`NavigationStackStore` is not guarded by `#if !os(Android)` except for one secondary initializer (line 104). The primary body (line 178-199) compiles on all platforms:

```swift
public var body: some View {
    NavigationStack(
      path: self.viewStore.binding(
        get: { $0.path },                    // Returns StackState<State>.PathView
        compactSend: { newPath in ... }
      )
    ) {
      self.root
        .navigationDestination(for: StackState<State>.Component.self) { ... }
    }
}
```

The `viewStore.binding(get:compactSend:)` call returns `Binding<StackState<State>.PathView>`.

This `Binding<PathView>` is what gets passed to `NavigationStack(path:)`.

---

## 3. Type Chain Analysis

### The full type chain on Android:

```
TCA Store<StackState<Path.State>, StackAction<Path.State, Path.Action>>
  -> ViewStore observes StackState<Path.State>
    -> .binding(get: { $0.path }) produces Binding<StackState<Path.State>.PathView>
      -> Passed to NavigationStack(path:)
        -> Skip receives as init(path: Any, root:)
          -> Force-cast: path as! Binding<[Any]>?
            -> CRASH: PathView is not [Any]
```

### Why the cast fails

`StackState<State>.PathView` is defined in `NavigationStack+Observation.swift` (line 534-578):

```swift
public struct PathView: MutableCollection, RandomAccessCollection,
    RangeReplaceableCollection
{
    var base: StackState
    public subscript(position: Int) -> Component { ... }
    // Element type is Component, NOT Any
}
```

`PathView` conforms to `RandomAccessCollection` where `Element == Component`. It is a **struct**, not an `Array`.

`Binding<PathView>` is `Binding<StackState<State>.PathView>`.

Skip's force-cast `path as! Binding<[Any]>?` requires the incoming type to literally be `Binding<Array<Any>>`. Swift's type system does not allow:
- Covariant casts of generic types (`Binding<PathView>` is not `Binding<[Any]>`)
- Bridging custom collections to `Array` through `as!`
- Even `Binding<[Component]>` would fail because `[Component]` is not `[Any]` in Swift's strict generics

**The cast will unconditionally crash.**

### Destination registration also breaks

Even if the path binding cast were fixed, `navigationDestination(for: StackState<State>.Component.self)` registers the destination keyed by `Component.Type`. But Skip's destination lookup uses `type(of: targetValue)` on the elements of the `[Any]` array. If we bridged `PathView` elements into `[Any]`, each element would be a `Component` value, and `type(of: component)` would return `StackState<Path.State>.Component` -- which **could** match the registered destination if the type identity is preserved through Kotlin/JVM generics. However, Skip uses erased `Any` type identity, so the JVM type would likely be the erased `StackState.Component` without the generic parameter, which may or may not match depending on Skip's generic erasure behavior.

---

## 4. Existing Test Coverage

### TCA tests

`forks/swift-composable-architecture/Tests/ComposableArchitectureTests/AndroidParityTests.swift` exists but does not contain NavigationStack-specific tests -- it focuses on observation parity.

The Integration test suite at `forks/swift-composable-architecture/Examples/Integration/` contains `NavigationStackTestCase.swift` and `LegacyNavigationTests.swift`, but these are iOS UI tests that would not run on Android.

### Skip tests

No dedicated NavigationStack path-binding tests were found in the skip-ui test suite.

**There are zero tests exercising NavigationStack with custom (non-Array, non-NavigationPath) path types on Android.**

---

## 5. Compatibility Verdict

### REQUIRES_ADAPTATION

There are **three layers** of incompatibility:

| Layer | Problem | Severity |
|-------|---------|----------|
| 1. Modern TCA API | `#if !os(Android)` -- does not compile | Blocking |
| 2. Legacy `NavigationStackStore` | `Binding<PathView>` force-cast to `Binding<[Any]>?` crashes | Blocking |
| 3. Destination routing | `Component` type registration vs Skip's `type(of:)` lookup | Unknown (needs runtime verification) |

---

## 6. Proposed Minimal Fix

### Option A: Adapt TCA's `NavigationStackStore` for Android (Recommended)

Add an `#if os(Android)` path inside `NavigationStackStore.body` that converts `PathView` to `[Any]`:

```swift
public var body: some View {
    #if os(Android)
    // Bridge PathView -> [Any] for Skip's NavigationStack
    let pathBinding = Binding<[Any]>(
        get: {
            self.viewStore.state.path.map { $0 as Any }
        },
        set: { newPath in
            // Reverse-map: compare counts to detect push/pop
            let currentPath = self.viewStore.state.path
            if newPath.count > currentPath.count, let last = newPath.last as? StackState<State>.Component {
                self.viewStore.send(.push(id: last.id, state: last.element))
            } else if newPath.count < currentPath.count {
                self.viewStore.send(.popFrom(id: currentPath[newPath.count].id))
            }
        }
    )
    NavigationStack(path: pathBinding) {
        self.root
            .navigationDestination(for: StackState<State>.Component.self) { component in
                NavigationDestinationView(component: component, destination: self.destination)
            }
    }
    #else
    // Existing iOS implementation
    NavigationStack(
        path: self.viewStore.binding(
            get: { $0.path },
            compactSend: { ... }
        )
    ) { ... }
    #endif
}
```

**Risk:** The `set` closure receives `[Any]` from Skip. When Skip calls `path.wrappedValue.append(targetValue)`, the appended value comes from a `NavigationLink`'s `targetValue`, which would need to be a `Component`. This requires that `NavigationLink(state:)` wraps the state in a `Component` before pushing -- which TCA already does on iOS (line 297 of `NavigationStack+Observation.swift`), but that code is also `#if !os(Android)` guarded.

### Option B: Adapt Skip's `NavigationStack` to accept `RandomAccessCollection`

Modify Skip's `init(path: Any, root:)` to handle any `RandomAccessCollection`:

```swift
public init(path: Any, @ViewBuilder root: () -> any View) {
    self.root = ComposeBuilder.from(root)
    if let arrayBinding = path as? Binding<[Any]> {
        self.path = arrayBinding
    } else {
        // Attempt to bridge any Binding<C> where C: RandomAccessCollection
        self.path = Self.bridgePathBinding(path)
    }
    self.navigationPath = nil
    self.destinationKeyTransformer = nil
}
```

**Risk:** Skip transpiles Swift to Kotlin. Runtime reflection over generic `Binding` types in Kotlin may not preserve the Swift generic parameter, making the bridging unreliable.

### Option C: Hybrid approach (Most robust)

1. In TCA: provide an Android-specific `NavigationStack.init(path:root:destination:)` overload that:
   - Accepts `Binding<Store<StackState<State>, StackAction<State, Action>>>`
   - Internally converts to `Binding<[Any]>` where elements are `Component` values
   - Registers destinations via Skip's `navigationDestination(for:destination:)` using `Component` as the data type

2. In Skip: ensure `navigationDestination(for:)` correctly matches `StackState<State>.Component` types through JVM generics erasure. May need a `destinationKeyTransformer` override.

### Recommended implementation order

1. **Phase 5a:** Implement Option A in `NavigationStackStore` as the quickest unblock
2. **Phase 5b:** Port the modern `NavigationStack.init(path:)` extension with Android adaptation
3. **Phase 5c:** Verify destination routing with integration tests on Android emulator
4. **Phase 5d:** If destination type matching fails, add `destinationKeyTransformer` support to TCA's Android path

---

## 7. Key Code References

| What | File | Lines |
|------|------|-------|
| Skip `NavigationStack` struct | `forks/skip-ui/.../Containers/Navigation.swift` | 92-129 |
| Skip force-cast `as! Binding<[Any]>?` | Same file | 114 |
| Skip `Navigator.navigateToPath()` | Same file | 815-864 |
| Skip `navigationDestination(for:)` | Same file | 1004-1011 |
| Skip destination key lookup by `type(of:)` | Same file | 700-707 |
| TCA `NavigationStack.init(path:)` extension (iOS only) | `forks/swift-composable-architecture/.../NavigationStack+Observation.swift` | 150-192 |
| TCA `PathView` definition | Same file | 534-578 |
| TCA `Component` definition | Same file | 513-532 |
| TCA `NavigationStackStore.body` | `forks/swift-composable-architecture/.../SwiftUI/NavigationStackStore.swift` | 178-199 |
| TCA `#if !os(Android)` guards | `NavigationStack+Observation.swift` | 74, 111, 150, 264 |
| TCA `NavigationLink(state:)` wrapping | `NavigationStack+Observation.swift` | 287-307 |
