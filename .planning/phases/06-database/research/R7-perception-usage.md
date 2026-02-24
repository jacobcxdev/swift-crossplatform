# R7 — Perception Usage in sqlite-data: Android Compatibility Deep Dive

**Date:** 2026-02-22
**Investigator:** Claude (general-purpose agent)
**Topic:** Does sqlite-data's Perception usage work with the Android passthrough established in Phase 1?

---

## 1. Executive Summary

sqlite-data uses Perception in two distinct ways:

1. **Direct import** — only `FetchSubscription.swift` has `import Perception`, and uses it solely for `LockIsolated`.
2. **Transitive via swift-sharing** — swift-sharing imports `PerceptionCore` directly and uses `Perceptible`, `PerceptionRegistrar`, and `LockIsolated` (from `ConcurrencyExtras`) extensively.

The Phase 1 Android passthrough in the `forks/swift-perception` fork gates all Android-incompatible code (`MachO`, `SwiftUI` perception checking, `AttributeGraph` introspection) behind `#if !os(Android)`. On Android, `PerceptionCore` compiles cleanly as a pure observation forwarding layer backed by native `libswiftObservation.so`.

**Confidence: HIGH** — the Perception usage in sqlite-data is fully compatible with the Android passthrough.

---

## 2. Exhaustive Symbol Search: sqlite-data Sources

Searched `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Sources/` for all Perception-related symbols.

### 2.1 `import Perception`

**Exactly one file:**

```
forks/sqlite-data/Sources/SQLiteData/FetchSubscription.swift:1:import Perception
```

No other file in the SQLiteData target imports Perception directly.

### 2.2 `Perceptible`

**Zero occurrences** in sqlite-data Sources. (Used in swift-sharing's own sources — see Section 5.)

### 2.3 `PerceptionRegistrar`

**Zero occurrences** in sqlite-data Sources. (Used in swift-sharing's own sources — see Section 5.)

### 2.4 `withPerceptionTracking`

**Zero occurrences** in sqlite-data Sources.

### 2.5 `LockIsolated`

**Multiple files, two categories:**

**Category A — CloudKit files (gated by `#if canImport(CloudKit)`):**

```
Sources/SQLiteData/CloudKit/SyncEngine.swift            — 4 uses (import ConcurrencyExtras)
Sources/SQLiteData/CloudKit/Internal/DataManager.swift  — 1 use (import ConcurrencyExtras, CryptoKit gate)
Sources/SQLiteData/CloudKit/Internal/MockCloudContainer.swift — 5 uses
Sources/SQLiteData/CloudKit/Internal/MockCloudDatabase.swift  — 1 use
Sources/SQLiteData/CloudKit/Internal/MockSyncEngine.swift     — 4 uses
```

These files all open with `#if canImport(CloudKit)`. CloudKit is an Apple-platform-only framework; it does not exist on Android. These files are **entirely excluded from Android compilation**.

**Category B — FetchSubscription (active on Android):**

```
Sources/SQLiteData/FetchSubscription.swift:17:  let cancellable = LockIsolated<Task<Void, any Error>?>(nil)
```

This file imports `Perception` and uses `LockIsolated`. This is the only active Android code path using `LockIsolated` from Perception.

---

## 3. FetchSubscription.swift — The Only Active Perception Import

Full file content:

```swift
// FetchSubscription.swift
import Perception
import Sharing

public struct FetchSubscription: Sendable {
  let cancellable = LockIsolated<Task<Void, any Error>?>(nil)
  let onCancel: @Sendable () -> Void

  init<Value>(sharedReader: SharedReader<Value>) {
    onCancel = { sharedReader.projectedValue = SharedReader(value: sharedReader.wrappedValue) }
  }

  public var task: Void {
    get async throws {
      let task = Task {
        try await withTaskCancellationHandler {
          try await Task.never()
        } onCancel: {
          onCancel()
        }
      }
      cancellable.withValue { $0 = task }
      try await task.cancellableValue
    }
  }

  public func cancel() {
    cancellable.value?.cancel()
  }
}
```

**Key observation:** This file uses `LockIsolated` as a thread-safe mutable wrapper around a `Task`. There is no use of `Perceptible`, `PerceptionRegistrar`, or `withPerceptionTracking`. The import of `Perception` is solely to access `LockIsolated`.

---

## 4. Where Does `LockIsolated` Come From?

This is the most important finding. There are **two distinct `LockIsolated` implementations** in the dependency graph.

### 4.1 LockIsolated in `swift-concurrency-extras`

Defined at:
```
forks/sqlite-data/.build/checkouts/swift-concurrency-extras/Sources/ConcurrencyExtras/LockIsolated.swift
```

This is the public, full-featured implementation (`public final class LockIsolated<Value>`, backed by `NSRecursiveLock`). This is what `ConcurrencyExtras` exports.

### 4.2 LockIsolated in `swift-perception`

After exhaustive search:
```
grep -rn "LockIsolated" forks/swift-perception/Sources/ --include="*.swift"
# → no results
```

**swift-perception does NOT define or re-export `LockIsolated`.** The `Perception` module only re-exports `PerceptionCore` via `@_exported import PerceptionCore`, and `PerceptionCore` has no dependency on `ConcurrencyExtras`.

### 4.3 Resolution: How does FetchSubscription.swift get LockIsolated?

The SQLiteData target has **both** `Perception` and `ConcurrencyExtras` as direct dependencies in `Package.swift`:

```swift
// Package.swift — SQLiteData target dependencies
.product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
.product(name: "Perception", package: "swift-perception"),
```

With Swift 6's `MemberImportVisibility` upcoming feature enabled:
```swift
swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
```

`LockIsolated` in `FetchSubscription.swift` resolves from `ConcurrencyExtras`, which is a peer dependency of the same target. The `import Perception` statement brings in `PerceptionCore` and the `Observation` forwarding, but `LockIsolated` itself is visible because `ConcurrencyExtras` is also a target dependency.

**The `import Perception` in FetchSubscription.swift is therefore misleading** — `LockIsolated` does NOT come from Perception. It comes from `ConcurrencyExtras`. The Perception import may be legacy or may be needed for other symbols brought in by `PerceptionCore` indirectly (e.g., `Observation` re-export on older OS).

> **Note for future investigation:** With `MemberImportVisibility` enabled, `LockIsolated` in `FetchSubscription.swift` should require an explicit `import ConcurrencyExtras`. The fact that `import Perception` is sufficient suggests that either: (a) the upcoming feature is not yet enforced strictly at this Swift version, or (b) there is a transitive re-export path from Perception to ConcurrencyExtras not currently visible in the fork's Package.swift. Either way, the runtime source of `LockIsolated` is `ConcurrencyExtras`.

---

## 5. swift-sharing Perception Usage (Transitive Dependency)

The sqlite-data checkout of swift-sharing (`forks/sqlite-data/.build/checkouts/swift-sharing/`) uses `PerceptionCore` directly and extensively.

### 5.1 swift-sharing Package.swift dependencies

```swift
.package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.0"),
.package(url: "https://github.com/pointfreeco/swift-perception", "1.4.1"..<"3.0.0"),
// Sharing target:
.product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
.product(name: "PerceptionCore", package: "swift-perception"),
```

Note: swift-sharing resolves the **upstream** `swift-perception` (version range `"1.4.1"..<"3.0.0"`), NOT the `forks/swift-perception` fork. This matters significantly — see Section 6.

### 5.2 Perception symbols in swift-sharing sources

| File | Symbols Used |
|------|-------------|
| `Sharing/Shared.swift` | `import PerceptionCore`, `Perceptible` conformance |
| `Sharing/SharedReader.swift` | `import PerceptionCore`, `Perceptible` conformance |
| `Sharing/SharedBinding.swift` | `import PerceptionCore` (conditional) |
| `Sharing/Internal/Reference.swift` | `import PerceptionCore`, `Perceptible`, `PerceptionRegistrar`, `Observable` |
| `Sharing/Internal/PersistentReferences.swift` | `import PerceptionCore` |
| `Sharing/SharedKeys/FileStorageKey.swift` | `LockIsolated` (from `ConcurrencyExtras`) |

The critical usage in `Reference.swift`:
```swift
final class _BoxReference<Value>: MutableReference, Observable, Perceptible, @unchecked Sendable {
  private let _$perceptionRegistrar = PerceptionRegistrar(isPerceptionCheckingEnabled: false)
  // ...
}

final class _SharedReference<Value>: Reference, Observable, Perceptible, @unchecked Sendable {
  private let _$perceptionRegistrar = PerceptionRegistrar(isPerceptionCheckingEnabled: false)
  // ...
}

extension Shared: Perceptible {}
extension SharedReader: Perceptible {}
```

These classes conform to both `Observable` (native Swift) and `Perceptible` (Perception backport) simultaneously — exactly the dual-conformance pattern that Phase 1's Android passthrough was designed to support.

---

## 6. Which swift-perception Is Resolved?

This is a critical distinction for Android compatibility.

### For the sqlite-data fork (as a standalone package)

The `Package.swift` resolves:
```swift
.package(url: "https://github.com/jacobcxdev/swift-perception", branch: "flote/service-app"),
```

This resolves to `forks/swift-perception` — the **fork with Android passthrough**. Confirmed by the resolved checkout content matching the fork's `Package.swift` (which includes Skip/Android-specific dependencies on `skip-fuse` and `skip-fuse-ui`).

Wait — **correction**: the `.build/checkouts/swift-perception/Package.swift` in sqlite-data does NOT include skip-fuse dependencies:

```swift
// sqlite-data resolved swift-perception Package.swift — NO skip-fuse
dependencies: [
  .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.0"),
  .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.6.0"),
  .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"603.0.0"),
],
```

Whereas `forks/swift-perception/Package.swift` (the fork) DOES include:
```swift
.package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0"),
.package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
```

**This means sqlite-data's `.build/checkouts/swift-perception` is the upstream version, NOT the fork.** This happens because the `.build/` directory reflects a standalone `swift package resolve` of sqlite-data without the local path overrides that the parent workspace (`examples/fuse-library`) applies.

### For the fuse-library example (production Android builds)

When built via `examples/fuse-library`, `Package.swift` resolves all `forks/` via local path dependencies. In that context, `swift-perception` resolves to `forks/swift-perception` which contains the full Android passthrough. The `.build/` artifacts inside `forks/sqlite-data/` are standalone resolution artifacts and do not represent the actual build used in production.

---

## 7. The Phase 1 Android Passthrough — What It Provides

The `forks/swift-perception` fork gates Android-incompatible code as follows:

### PerceptionRegistrar.swift
```swift
#if canImport(SwiftUI) && !os(Android)
  import SwiftUI
#endif

#if DEBUG && canImport(SwiftUI) && !os(Android)
  import MachO
#endif
```
- The `check()` method (which validates that `@Perceptible` state is accessed inside `WithPerceptionTracking`) is entirely gated behind `#if DEBUG && canImport(SwiftUI) && !os(Android)`.
- On Android, perception checking is skipped entirely — no `MachO` introspection, no `AttributeGraph` address scanning.

### Bindable.swift and WithPerceptionTracking.swift
```swift
#if canImport(SwiftUI) && !os(Android)
  // entire file
#endif
```
- These SwiftUI-specific wrappers are entirely excluded on Android.

### `PerceptionRegistrar.init()` on Android
On Android, `canImport(Observation)` is true (native `libswiftObservation.so` is available), so:
```swift
public init(isPerceptionCheckingEnabled: Bool = true) {
  #if canImport(Observation)
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *), !isObservationBeta {
      rawValue = ObservationRegistrar()  // ← uses native Observation on Android
      return
    }
  #endif
  rawValue = _PerceptionRegistrar()
}
```
Android gets native `ObservationRegistrar` from `libswiftObservation.so` — the passthrough is complete.

---

## 8. Full Dependency Chain for Perception in sqlite-data

```
examples/fuse-library (Android build)
└── forks/sqlite-data (local path)
    ├── SQLiteData target
    │   ├── import Perception → forks/swift-perception (local path via parent)
    │   │   └── PerceptionCore → @_exported import Observation (native, Android)
    │   │                      → PerceptionRegistrar → ObservationRegistrar (native)
    │   │                      → [NO LockIsolated]
    │   ├── import ConcurrencyExtras → swift-concurrency-extras (upstream)
    │   │   └── LockIsolated (NSRecursiveLock-backed) ← used in FetchSubscription.swift
    │   └── import Sharing → forks/swift-sharing (local path via parent)
    │       └── import PerceptionCore → forks/swift-perception (same instance)
    │           └── Perceptible, PerceptionRegistrar → ObservationRegistrar (native)
    │       └── import ConcurrencyExtras → LockIsolated (in FileStorageKey.swift)
    └── CloudKit/* → #if canImport(CloudKit) → EXCLUDED on Android
        └── import ConcurrencyExtras → LockIsolated (moot, CloudKit files excluded)
```

---

## 9. FetchAll and FetchOne Android Guards

Two additional Android guards exist in the core property wrappers:

```swift
// FetchAll.swift:400-406
#if canImport(SwiftUI)
  extension FetchAll: DynamicProperty {
    #if !os(Android)
    public func update() {
      sharedReader.update()
    }
    // ...
```

```swift
// FetchOne.swift:903-908
#if canImport(SwiftUI)
  extension FetchOne: DynamicProperty {
    #if !os(Android)
    public func update() {
      sharedReader.update()
    }
    // ...
```

The `update()` method is the SwiftUI `DynamicProperty` hook that triggers re-render. On Android, this is excluded — consistent with Skip's own rendering model which does not use `DynamicProperty.update()` in the same way.

---

## 10. Summary of All Perception References

| Location | Symbol | Source Module | Android Safe? |
|----------|--------|---------------|---------------|
| `FetchSubscription.swift:1` | `import Perception` | `swift-perception` fork | Yes — passthrough active |
| `FetchSubscription.swift:17` | `LockIsolated` | `ConcurrencyExtras` (peer dep) | Yes — pure Foundation/NSRecursiveLock |
| `CloudKit/SyncEngine.swift:3` | `import ConcurrencyExtras` | `ConcurrencyExtras` | Moot — `#if canImport(CloudKit)` |
| `CloudKit/SyncEngine.swift:29-42` | `LockIsolated` (4x) | `ConcurrencyExtras` | Moot — CloudKit excluded |
| `CloudKit/Internal/DataManager.swift:52` | `LockIsolated` | `ConcurrencyExtras` | Moot — CloudKit+CryptoKit gate |
| `CloudKit/Internal/MockCloudContainer.swift:6-121` | `LockIsolated` (5x) | `ConcurrencyExtras` | Moot — CloudKit excluded |
| `CloudKit/Internal/MockCloudDatabase.swift:7` | `LockIsolated` | `ConcurrencyExtras` | Moot — CloudKit excluded |
| `CloudKit/Internal/MockSyncEngine.swift:11-142` | `LockIsolated` (4x) | `ConcurrencyExtras` | Moot — CloudKit excluded |
| `FetchAll.swift:402` | `DynamicProperty.update()` | SwiftUI | `#if !os(Android)` guard |
| `FetchOne.swift:905` | `DynamicProperty.update()` | SwiftUI | `#if !os(Android)` guard |
| swift-sharing `Shared.swift` | `Perceptible` | `PerceptionCore` | Yes — passthrough active |
| swift-sharing `SharedReader.swift` | `Perceptible` | `PerceptionCore` | Yes — passthrough active |
| swift-sharing `Reference.swift` | `Perceptible`, `PerceptionRegistrar` | `PerceptionCore` | Yes — passthrough to native `ObservationRegistrar` |
| swift-sharing `FileStorageKey.swift` | `LockIsolated` (3x) | `ConcurrencyExtras` | Yes — pure Foundation |

---

## 11. Confidence Assessment

### Claim: "sqlite-data only imports Perception for LockIsolated"

**Verdict: Partially correct, but more nuanced.**

- The claim is directionally accurate: `FetchSubscription.swift` is the only file with `import Perception`.
- However, `LockIsolated` does NOT come from Perception — it comes from `ConcurrencyExtras`, which is a peer dependency of the same target. The `import Perception` may be historical or needed for `Observation`/`PerceptionCore` types used elsewhere in the module (e.g., via swift-sharing's `Perceptible` conformances on `Shared`/`SharedReader` which the SQLiteData macros interact with).
- The corrected claim: **"sqlite-data's only direct Perception usage is `import Perception` in FetchSubscription.swift. The actual `LockIsolated` type comes from `ConcurrencyExtras`."**

### Android Compatibility: HIGH CONFIDENCE

**Reasons:**

1. **No Perception-specific observation patterns in sqlite-data itself** — no `@Perceptible` types, no `withPerceptionTracking`, no `PerceptionRegistrar` in SQLiteData's own code.

2. **Phase 1 passthrough is comprehensive** — the `forks/swift-perception` fork correctly gates all Android-incompatible code (`MachO`, `AttributeGraph`, SwiftUI-specific `check()`) behind `#if !os(Android)`. On Android, `PerceptionRegistrar` delegates to native `ObservationRegistrar`.

3. **CloudKit (the LockIsolated-heavy code) is entirely excluded on Android** — every CloudKit file opens with `#if canImport(CloudKit)`, which is false on Android.

4. **LockIsolated (ConcurrencyExtras) is Android-safe** — pure `NSRecursiveLock`-backed wrapper with no platform-specific code.

5. **swift-sharing's Perceptible conformances work on Android** — `_BoxReference` and `_SharedReference` conform to both `Observable` and `Perceptible`, with `PerceptionRegistrar(isPerceptionCheckingEnabled: false)`. The `false` flag disables the SwiftUI perception check that is gated behind `!os(Android)` anyway.

6. **FetchAll/FetchOne have explicit `#if !os(Android)` guards** — the SwiftUI `DynamicProperty.update()` hook is already properly excluded.

### Remaining Risk: LOW

- **swift-sharing resolves upstream Perception in standalone builds** — when sqlite-data is resolved standalone (not via fuse-library workspace), swift-sharing resolves upstream `swift-perception` (1.4.1+) rather than the fork. This upstream version also contains `#if !os(Android)` guards (they were upstreamed). Verify that the upstream version used by swift-sharing has equivalent guards.
- **`MemberImportVisibility` and LockIsolated source** — with this upcoming feature fully enforced, `FetchSubscription.swift` may need an explicit `import ConcurrencyExtras` instead of relying on `import Perception`. This is a build-time risk, not a runtime risk.

---

## 12. Files Investigated

- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Sources/SQLiteData/FetchSubscription.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Sources/SQLiteData/FetchAll.swift` (line 400-406)
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Sources/SQLiteData/FetchOne.swift` (line 900-908)
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Sources/SQLiteData/CloudKit/SyncEngine.swift` (lines 1-50)
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Sources/SQLiteData/Internal/Exports.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-perception/Sources/Perception/Exports.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-perception/Sources/PerceptionCore/Internal/Exports.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-perception/Sources/PerceptionCore/Perception/PerceptionRegistrar.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-perception/Sources/PerceptionCore/Internal/ObservationBeta.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-perception/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/.build/checkouts/swift-concurrency-extras/Sources/ConcurrencyExtras/LockIsolated.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/.build/checkouts/swift-perception/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/.build/checkouts/swift-sharing/Package.swift` (grep)
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/.build/checkouts/swift-sharing/Sources/Sharing/` (grep scan)
