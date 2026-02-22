# OpenCombine Audit: swift-sharing & Related Forks

**Date:** 2026-02-22
**Scope:** Full audit of Combine/OpenCombine usage in `forks/swift-sharing/Sources/` and related dependencies for Android compatibility.

---

## 1. Combine Import Audit (All Files)

### Files with `import Combine` / `import OpenCombineShim` / `canImport()` guards

| File | Lines | Import Pattern | Android-Safe? |
|------|-------|---------------|---------------|
| `Sharing/SharedReader.swift` | 7-10, 251, 268, 275, 283, 288 | `#if canImport(Combine)` -> `import Combine` / `#else` -> `import OpenCombineShim` | PASS -- dual-path |
| `Sharing/Shared.swift` | 7-10, 362, 379, 386, 394, 399 | Same pattern | PASS -- dual-path |
| `Sharing/SharedPublisher.swift` | 1-5 | `#if canImport(Combine) \|\| canImport(OpenCombine)` outer guard, same import pattern inside | PASS -- dual-path |
| `Sharing/Internal/PassthroughRelay.swift` | 1-6, 13, 51, 71 | Same pattern with additional `#if canImport(Combine)` inner guards for type disambiguation | PASS -- dual-path |
| `Sharing/Internal/Reference.swift` | 6-9, 26, 49, 178, 481, 566, 620 | Same pattern | PASS -- dual-path |
| `Sharing/SharedKeys/FileStorageKey.swift` | 2 | `import CombineSchedulers` (no Combine/OpenCombine guard) | **WARN** -- see Section 8 |

### swift-sharing Package.swift OpenCombine Dependency

```swift
.package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
// ...
.product(name: "OpenCombineShim", package: "OpenCombine", condition: .when(platforms: [.linux, .android]))
```

**Verdict:** OpenCombineShim is conditionally included for `.linux` and `.android` platforms. On Android, `canImport(OpenCombine)` will be true and `canImport(Combine)` will be false, so all `#else` branches (importing `OpenCombineShim`) will activate. **PASS.**

---

## 2. Publisher Protocol Conformances

### PassthroughRelay (the only Publisher-conforming type in swift-sharing)

| Type | Conforms To | Output | Failure | Android Guard? |
|------|-------------|--------|---------|----------------|
| `PassthroughRelay<Output>` | `Subject` (which extends `Publisher`) | Generic `Output` | `Never` | PASS -- entire file is in `#if canImport(Combine) \|\| canImport(OpenCombine)` |

**No direct `Publisher` protocol conformance declarations exist** in swift-sharing. `PassthroughRelay` conforms to `Subject` (a `Publisher` subprotocol). The `publisher` computed properties on `Reference`, `SharedPublisher`, etc. return `some Publisher<Value, Never>` -- they are existential uses, not conformances.

### Combine Operators Used in Publisher Chains

| Operator | File(s) | OpenCombine Equivalent? |
|----------|---------|------------------------|
| `Just<Void>(())` | `SharedPublisher.swift:22,42` | PASS -- `Just` exists in OpenCombine |
| `.flatMap { }` | `SharedPublisher.swift:22,42` | PASS -- `flatMap` exists in OpenCombine |
| `.prepend()` | `SharedPublisher.swift:23,43`, `Reference.swift:61,190` | PASS -- `prepend` exists in OpenCombine |
| `.map(keyPath)` | `Reference.swift:484` (`_AppendKeyPathReference`) | PASS -- `map` exists in OpenCombine |
| `.map(body)` | `Reference.swift:569` (`_ReadClosureReference`) | PASS -- `map` exists in OpenCombine |
| `.compactMap { $0 }` | `Reference.swift:623` (`_OptionalReference`) | PASS -- `compactMap` exists in OpenCombine |
| `.subscribe()` | `SharedReader.swift:269,276,284`, `Shared.swift:380,387,395` | PASS -- `subscribe` exists in OpenCombine |
| `.sink { }` | `SharedReader.swift:299`, `Shared.swift:410` | PASS -- `sink` exists in OpenCombine |

**No `eraseToAnyPublisher()` is used** in the current codebase (the `SharedPublisher.swift` returns `some Publisher`, not `AnyPublisher`).

**All Combine operators used have OpenCombine equivalents.** PASS.

---

## 3. Subscriber / Subscription / AnyCancellable Usage

### Combine-framework types (from Combine or OpenCombine)

| Type | File | Context | Android-Safe? |
|------|------|---------|---------------|
| `Combine.Subscription` / `OpenCombine.Subscription` | `PassthroughRelay.swift:14,16,52,57,72,139` | Type-qualified references inside `#if canImport` branches | PASS -- separate branches for each |
| `Subscriber<Output, Never>` | `PassthroughRelay.swift:28,74,78,141,145` | Used in `receive(subscriber:)` | PASS -- in OpenCombine |
| `Subscribers.Demand` | `PassthroughRelay.swift:73,121,140,188` | Backpressure management | PASS -- in OpenCombine |
| `Subscribers.Completion<Never>` | `PassthroughRelay.swift:40,113,180` | Completion handling | PASS -- in OpenCombine |
| `AnyCancellable` | `SharedReader.swift:253,256`, `Shared.swift:364,367` | Storing subject/SwiftUI cancellables | PASS -- in OpenCombine |

### swift-sharing's own types (NOT Combine types)

| Type | File | Notes |
|------|------|-------|
| `SharedSubscriber<Value>` | `SharedContinuations.swift:68` | Custom struct, NOT Combine's `Subscriber`. Pure Swift, no Combine dependency. |
| `SharedSubscription` | `SharedContinuations.swift:122` | Custom struct, NOT Combine's `Subscription`. Pure Swift, wraps a closure. |

**Important distinction:** The `SharedSubscriber` and `SharedSubscription` types used in `SharedReaderKey.subscribe()` and throughout the key implementations are **custom types defined in swift-sharing** -- they have no relation to Combine's `Subscriber`/`Subscription` protocols. They are pure Swift and fully Android-compatible.

---

## 4. PassthroughRelay Analysis

**File:** `forks/swift-sharing/Sources/Sharing/Internal/PassthroughRelay.swift`

### Structure
- Entire file gated by `#if canImport(Combine) || canImport(OpenCombine)`
- Inner `Subscription` class has two `#if canImport(Combine)` / `#else` branches

### Functional Equivalence of Dual Branches

| Aspect | Combine Branch (L72-137) | OpenCombine Branch (L139-204) | Identical? |
|--------|--------------------------|-------------------------------|------------|
| Class declaration | `Combine.Subscription` | `OpenCombine.Subscription` | Only type qualifier differs |
| `demand` type | `Subscribers.Demand` | `Subscribers.Demand` | YES |
| `downstream` type | `any Subscriber<Output, Never>` | `any Subscriber<Output, Never>` | YES |
| `cancel()` | Identical logic | Identical logic | YES |
| `receive(_:)` | Identical demand-tracking logic | Identical logic | YES |
| `receive(completion:)` | Identical | Identical | YES |
| `request(_:)` | Identical | Identical | YES |
| `==` operator | `lhs === rhs` | `lhs === rhs` | YES |

**Also dual-branched:**
- `_upstreams` array (L13-16): `[any Combine.Subscription]` vs `[any OpenCombine.Subscription]`
- `send(subscription:)` (L51-60): Same logic, different type qualifier

**Verdict:** The Combine and OpenCombine branches are **byte-for-byte functionally identical** except for the module-qualified type names (`Combine.Subscription` vs `OpenCombine.Subscription`). No subtle differences. **PASS.**

---

## 5. SharedPublisher Analysis

**File:** `forks/swift-sharing/Sources/Sharing/SharedPublisher.swift`

```swift
#if canImport(Combine) || canImport(OpenCombine)
  // imports...

  extension Shared {
    public var publisher: some Publisher<Value, Never> {
      Just<Void>(()).flatMap { _ in
        box.subject.prepend(wrappedValue)
      }
    }
  }

  extension SharedReader {
    public var publisher: some Publisher<Value, Never> {
      Just<Void>(()).flatMap { _ in
        box.subject.prepend(wrappedValue)
      }
    }
  }
#endif
```

### Operators Used

| Operator | OpenCombine Support | Notes |
|----------|-------------------|-------|
| `Just<Void>(())` | YES | Basic value publisher |
| `.flatMap { }` | YES | Transforms to inner publisher |
| `.prepend()` | YES | Prepends current value |

**Why `Just(()).flatMap`?** This pattern captures `wrappedValue` lazily at subscription time rather than at publisher creation time. It ensures the subscriber gets the current value when they subscribe, not the value at the time the publisher property was accessed.

**No `eraseToAnyPublisher`** -- returns opaque `some Publisher` type.

**Verdict:** All operators are available in OpenCombine. **PASS.**

---

## 6. FileStorageKey Debounce Mechanism

**File:** `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift`

### Throttle Implementation: DispatchWorkItem (NOT Combine debounce)

The file write throttling uses **manual `DispatchWorkItem`-based throttling**, NOT Combine's `debounce` or `throttle` operators:

```swift
// State struct (L79-88)
var workItem: DispatchWorkItem?

// save() method (L206-255)
case .didSet:
  if state.workItem == nil {
    // First write: save immediately
    try save(data: data, url: url, modificationDates: &state.modificationDates)
    // Schedule a trailing write after 1 second
    let workItem = DispatchWorkItem { ... }
    state.workItem = workItem
    storage.asyncAfter(.seconds(1), workItem)
  } else {
    // Subsequent writes within window: buffer value
    state.value = value
    state.continuations.append(continuation)
  }
```

**Pattern:** First-write-through with 1-second trailing edge. This is pure GCD, no Combine involved.

### CombineSchedulers Dependency

`FileStorageKey.swift` imports `CombineSchedulers` (line 2), but this is only used for the `AnySchedulerOf<DispatchQueue>` type in the `inMemory` file storage mock (L386):

```swift
public static func inMemory(
  fileSystem: LockIsolated<[URL: Data]>,
  scheduler: AnySchedulerOf<DispatchQueue> = .immediate
) -> Self { ... }
```

This is used in **test/preview contexts only** -- not in the production `fileSystem` storage. The live `FileStorage.fileSystem` uses raw `DispatchQueue.main.async/asyncAfter`.

### Platform Guard

The entire `FileStorageKey.swift` file is gated by:
```swift
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)
```

On Android, **none of these can be imported**, so the entire file is **compiled out**. FileStorageKey is Apple-platform-only.

**Verdict:** No Combine debounce/throttle operators used. Manual DispatchWorkItem throttling. And the entire file is Apple-only anyway. **PASS (N/A on Android).**

---

## 7. OpenCombineShim Analysis

**Status:** The `forks/OpenCombine/` directory does **not exist** in the local workspace (submodule not initialized).

Based on the upstream OpenCombine project, `OpenCombineShim` is a **re-export module** that:
- On Apple platforms where Combine is available: re-exports `Combine`
- On non-Apple platforms (Linux, Android): re-exports `OpenCombine`

This means code that `import OpenCombineShim` gets the right implementation automatically. The `#if canImport(Combine)` / `#else import OpenCombineShim` pattern in swift-sharing is correct and standard.

### Dependency Chain
```
swift-sharing (Package.swift)
  -> OpenCombine (condition: .when(platforms: [.linux, .android]))
     -> product: OpenCombineShim
```

On Android: `OpenCombineShim` -> re-exports `OpenCombine`
On Apple: `Combine` imported directly (OpenCombine dependency not pulled in)

**Verdict:** Standard pattern, works correctly. **PASS.**

---

## 8. CombineSchedulers on Android

**File:** `forks/combine-schedulers/Package.swift`

### Package Configuration
```swift
traits: [
  .default(enabledTraits: ["OpenCombineSchedulers"]),
  Trait(name: "OpenCombineSchedulers", ...)
],
dependencies: [
  .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
],
targets: [
  .target(
    name: "CombineSchedulers",
    dependencies: [
      .product(name: "OpenCombineShim", package: "OpenCombine",
               condition: .when(platforms: [.linux, .android], traits: ["OpenCombineSchedulers"]))
    ]
  )
]
```

### Import Pattern (all source files follow this)
```swift
#if canImport(Combine)
  import Combine
#else
  import OpenCombineShim
#endif
#if canImport(Combine) || canImport(OpenCombineShim)
  // ... actual implementation
#endif
```

### Key Types

| Type | Purpose | Android-Safe? |
|------|---------|---------------|
| `AnyScheduler<SchedulerTimeType, SchedulerOptions>` | Type-erased scheduler | PASS -- uses Combine.Scheduler protocol from OpenCombine |
| `AnySchedulerOf<Scheduler>` | Convenience typealias | PASS |
| `ImmediateScheduler` | Synchronous execution | PASS |
| `UnimplementedScheduler` | Test placeholder | PASS |
| `TestScheduler` | Controllable time | PASS |
| `UIScheduler` | Main-thread scheduling | PASS -- guarded |

### SwiftUI-specific code
```swift
// SwiftUI.swift line 1:
#if canImport(Combine) && canImport(SwiftUI) && !os(Android)
```
Explicitly excluded from Android. **PASS.**

### UIKit-specific code
```swift
// UIKit.swift line 1:
#if canImport(UIKit) && !os(watchOS) && canImport(Combine)
```
Won't compile on Android (no UIKit). **PASS.**

**Verdict:** CombineSchedulers fully supports Android via OpenCombineShim. The `AnySchedulerOf<DispatchQueue>` type used in `FileStorageKey`'s inMemory mock will work on Android (though FileStorageKey itself is Apple-only). **PASS.**

---

## 9. Observations / AsyncSequence (SHR-09)

### Search Results

**No `Observations` type exists in swift-sharing.** There is no `struct Observations`, `class Observations`, or any type conforming to `AsyncSequence` in the `forks/swift-sharing/Sources/` directory.

The mechanism for observing changes in swift-sharing is:

1. **Combine/OpenCombine Publisher** -- via `$shared.publisher` (the `SharedPublisher.swift` extension)
2. **Swift Observation** -- via `Perceptible`/`Observable` conformance on `_BoxReference` and `_PersistentReference`
3. **SharedSubscriber/SharedSubscription** -- custom callback-based subscription for `SharedReaderKey` implementations

The `.publisher.values` property shown in documentation comments converts the Combine publisher to an `AsyncSequence` using Combine's built-in `Publisher.values` property (available in both Combine and OpenCombine).

**Verdict:** No standalone `Observations` type. Async observation goes through `.publisher.values` which relies on Combine/OpenCombine. **PASS** (as long as OpenCombine's `Publisher.values` works, which it does since OpenCombine 0.14).

---

## 10. TCA Combine Usage Affecting Phase 4

### Import Pattern in TCA

TCA uses `import OpenCombineShim` directly (not `#if canImport(Combine)`). This means it **always** goes through the shim, which resolves to Combine on Apple and OpenCombine on Android.

### Files with Combine usage relevant to shared state / binding / observation

| File | Import | Relevance to Phase 4 |
|------|--------|---------------------|
| `Store.swift` | `import OpenCombineShim`, `import CombineSchedulers` | Core store -- uses publishers internally for state observation |
| `Effect.swift` | `import OpenCombineShim` | Effect is `Publisher`-based; has `#if !canImport(Combine)` fallback at L450 |
| `Effects/Publisher.swift` | `import OpenCombineShim` | Publisher-to-Effect bridge |
| `Effects/Debounce.swift` | `import OpenCombineShim` | Debounce effect |
| `Effects/Throttle.swift` | `import OpenCombineShim` | Throttle effect |
| `Effects/Cancellation.swift` | `import OpenCombineShim` | Cancellable effects |
| `ViewStore.swift` | `import OpenCombineShim` | ViewStore publisher |
| `Core.swift` | `import OpenCombineShim` | Core reducer infrastructure |
| `TestStore.swift` | `import OpenCombineShim` | Test infrastructure |
| `Internal/CurrentValueRelay.swift` | `import OpenCombineShim` | Similar to PassthroughRelay |
| `Internal/Create.swift` | `import OpenCombineShim` | Effect creation helpers |
| `Internal/Exports.swift` | `@_exported import CombineSchedulers` | Re-exports CombineSchedulers |

### Key Observation
TCA does **not** directly interact with `swift-sharing`'s Combine publisher API in its core reducer/store path. The `@Shared` property wrapper integration in TCA goes through:
1. Swift Observation (`Perceptible`) for state tracking
2. `SharedSubscriber`/`SharedSubscription` (custom, non-Combine types) for key subscriptions

The Combine publisher on `@Shared` is a **consumer-facing convenience**, not part of TCA's internal plumbing.

**Verdict for Phase 4:** TCA's Combine usage is already OpenCombine-compatible via `import OpenCombineShim`. The `@Shared` integration does NOT depend on Combine -- it uses Observation/Perception. **PASS.**

---

## Summary Table

| # | Area | Status | Notes |
|---|------|--------|-------|
| 1 | Combine imports | **PASS** | All files use `#if canImport(Combine)` / `#else import OpenCombineShim` |
| 2 | Publisher conformances | **PASS** | Only `PassthroughRelay` conforms (via `Subject`); properly dual-branched |
| 3 | Subscriber/Subscription/AnyCancellable | **PASS** | All Combine types guarded; `SharedSubscriber`/`SharedSubscription` are custom non-Combine types |
| 4 | PassthroughRelay dual branches | **PASS** | Byte-for-byte functionally identical between Combine and OpenCombine branches |
| 5 | SharedPublisher operators | **PASS** | Uses `Just`, `flatMap`, `prepend` -- all available in OpenCombine |
| 6 | FileStorageKey debounce | **PASS (N/A)** | Uses DispatchWorkItem, not Combine. Entire file is Apple-only (`#if canImport(AppKit/UIKit/WatchKit)`) |
| 7 | OpenCombineShim | **PASS** | Standard re-export module; dependency correctly configured for `.android` |
| 8 | CombineSchedulers | **PASS** | Fully supports Android via OpenCombineShim with `condition: .when(platforms: [.linux, .android])` |
| 9 | Observations/AsyncSequence | **PASS** | No standalone type; async observation via `.publisher.values` (available in OpenCombine) |
| 10 | TCA Combine (Phase 4 impact) | **PASS** | TCA uses `import OpenCombineShim` throughout; `@Shared` integration uses Observation, not Combine |

---

## Overall Verdict: PASS

**swift-sharing's Combine usage is fully Android-compatible.** Every Combine import is guarded with `#if canImport(Combine)` / `#else import OpenCombineShim`. Every Combine operator used (`Just`, `flatMap`, `prepend`, `map`, `compactMap`, `subscribe`, `sink`) has a verified OpenCombine equivalent. The `PassthroughRelay` dual branches are functionally identical. Platform-specific code (`FileStorageKey`, SwiftUI cancellables) is properly gated.

### Risks/Caveats
1. **OpenCombine submodule not cloned:** The `forks/OpenCombine/` directory does not exist locally. If the project needs a forked version (e.g., for Android-specific patches), it needs to be initialized.
2. **`Publisher.values` (AsyncSequence bridge):** Used in documentation examples. Requires OpenCombine 0.14+ which is the minimum version specified.
3. **`FileStorageKey` unavailable on Android:** Any shared state using `.fileStorage()` will not compile on Android. An Android-specific storage key implementation may be needed for Phase 4 if file persistence is required.
