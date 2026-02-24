# R6b: Definitive Android Parity Deep-Dive

> Phase 7 research artifact. Traces every conditional compilation guard, every no-op stub, and every divergence across all 17 fork submodules.

---

## Table of Contents

1. [@Shared(.fileStorage) -- Full Android Path](#1-sharedfilestorage----full-android-path)
2. [@Shared(.appStorage) -- Full Android Path](#2-sharedappstorage----full-android-path)
3. [All Other Shared Keys on Android](#3-all-other-shared-keys-on-android)
4. [DynamicProperty.update() Exclusions](#4-dynamicpropertyupdate-exclusions)
5. [TestStore Non-Determinism -- Deep Analysis](#5-teststore-non-determinism----deep-analysis)
6. [Combine Import Issue (P1-3)](#6-combine-import-issue-p1-3)
7. [Complete Guard Catalogue](#7-complete-guard-catalogue)
8. [Summary: Parity Gap Matrix](#8-summary-parity-gap-matrix)

---

## 1. @Shared(.fileStorage) -- Full Android Path

**File:** `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift`

### Platform gate

The entire file is wrapped in:
```swift
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit) || os(Android)
```
Android is explicitly included -- the file compiles on Android.

### DispatchSource polyfill (lines 17-28)

```swift
#if os(Android)
  extension DispatchSource {
    struct FileSystemEvent: OptionSet, Sendable {
      let rawValue: UInt
      static let write = FileSystemEvent(rawValue: 1 << 0)
      static let delete = FileSystemEvent(rawValue: 1 << 1)
      static let rename = FileSystemEvent(rawValue: 1 << 2)
    }
  }
#endif
```

This is a **compile-time polyfill only**. `DispatchSource.FileSystemEvent` does not exist on Android (no `kqueue`/`FSEvents`). The polyfill lets the `FileStorageKey` struct compile but the event values are never actually dispatched by the OS.

### FileStorage.fileSystem -- the critical divergence (lines 347-406)

**iOS path:** Uses `DispatchSource.makeFileSystemObjectSource()` with `O_EVTONLY` file descriptors. Two sources are created per subscription:
- External source: watches `.write` and `.rename` events
- Internal source: watches `.delete` events

**Android path:**
```swift
#if os(Android)
  public static let fileSystem = Self(
    ...
    fileSystemSource: { _, _, _ in
      // No DispatchSource file monitoring on Android -- return no-op subscription
      SharedSubscription {}
    },
    load: { url in try Data(contentsOf: url) },
    save: { data, url in try data.write(to: url, options: .atomic) }
  )
#else
```

### What works on Android

| Operation | Works? | Notes |
|-----------|--------|-------|
| `load()` | YES | `Data(contentsOf: url)` works via Foundation |
| `save()` (write) | YES | `data.write(to: url, options: .atomic)` works via Foundation |
| `subscribe()` | NO-OP | Returns `SharedSubscription {}` -- never fires |
| Write-then-immediate-read | YES | Data persists to filesystem correctly |
| Cross-instance notifications | NO | No file system event monitoring |
| Debounced save (1s coalescence) | YES | Uses `DispatchQueue.main.asyncAfter` which works |

### Precise impact

- **Write path:** Fully functional. `FileStorageKey.save()` encodes data, calls `storage.save(data, url)` which calls `data.write(to: url, options: .atomic)`. The debounce work item fires via `DispatchQueue.main.asyncAfter`. All of this works on Android.
- **Read path:** Fully functional. `FileStorageKey.load()` calls `storage.load(url)` which calls `Data(contentsOf: url)`.
- **Subscription path:** Broken. `subscribe()` calls `storage.fileSystemSource()` which returns a no-op `SharedSubscription`. This means:
  - If Process A writes to the file, Process B will never be notified
  - If an external process modifies the file, the in-app `@Shared` value won't update
  - Within the same process, writes via `@Shared` update the in-memory value directly (bypassing the file watcher), so single-process usage works fine

### Potential workaround: Android FileObserver via JNI

Android's `android.os.FileObserver` monitors file system events (inotify-based). A JNI bridge could:
1. Create a `FileObserver` subclass in Kotlin
2. Export `onEvent(event: Int, path: String?)` via JNI callback
3. Map `MODIFY`, `DELETE`, `MOVED_FROM`/`MOVED_TO` to the callback closures

This would be a non-trivial implementation requiring a new JNI bridge in `skip-android-bridge`.

### Recommended test for write-then-read validation

```swift
@Test func fileStorageWriteThenRead() async throws {
  let url = FileManager.default.temporaryDirectory.appending(component: "test-\(UUID()).json")
  defer { try? FileManager.default.removeItem(at: url) }

  @Shared(.fileStorage(url)) var value = 0
  $value.withLock { $0 = 42 }
  try await $value.save()  // Force immediate save

  // Re-load from disk to prove persistence
  @Shared(.fileStorage(url)) var reloaded = 0
  try await $reloaded.load()
  #expect(reloaded == 42)
}
```

---

## 2. @Shared(.appStorage) -- Full Android Path

**File:** `forks/swift-sharing/Sources/Sharing/SharedKeys/AppStorageKey.swift`

### Platform gate

Same as fileStorage: `#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit) || os(Android)`

### Android UserDefaults implementation

**File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/AndroidUserDefaults.swift`

Skip provides `AndroidUserDefaults`, a subclass of `Foundation.UserDefaults` backed by `skip.foundation.UserDefaults` (which wraps Android `SharedPreferences`). Key features:

| Method | Status | Notes |
|--------|--------|-------|
| `object(forKey:)` | Works | Via `UserDefaultsAccess` bridge |
| `set(_:forKey:)` | Works | All typed overloads (Int, Float, Double, Bool, String, URL, Data) |
| `removeObject(forKey:)` | Works | |
| `string(forKey:)` | Works | |
| `integer(forKey:)` | Works | |
| `double(forKey:)` | Works | |
| `bool(forKey:)` | Works | |
| `url(forKey:)` | Works | |
| `data(forKey:)` | Works | |
| `array(forKey:)` | UNAVAILABLE | Marked `@available(*, unavailable)` |
| `stringArray(forKey:)` | UNAVAILABLE | Marked `@available(*, unavailable)` |
| `dictionary(forKey:)` | UNAVAILABLE | Marked `@available(*, unavailable)` |
| `synchronize()` | Returns `true` | No-op (SharedPreferences commits immediately) |
| KVO observation | NOT SUPPORTED | No `NSObject` KVO on Android |

### Subscribe no-op (lines 457-461)

```swift
#if os(Android)
// Android's UserDefaults (SharedPreferences via Skip) doesn't support KVO.
// Return a no-op subscription; values are read correctly on load, and
// TCA's Observing wrapper handles Compose recomposition.
return SharedSubscription {}
#else
```

The `subscribe()` method in `AppStorageKey` has two iOS subscription paths:
1. **KVO path** (standard keys): Uses `store.addObserver(_:forKeyPath:)` -- requires NSObject KVO
2. **NotificationCenter path** (keys with `.` or `@`): Uses `UserDefaults.didChangeNotification`

Neither is available on Android. The subscription returns a no-op.

### Debug suite check exclusion (line 315)

```swift
#if DEBUG && !os(Android)
  if store.responds(to: Selector(("_identifier"))) ...
```

The `_identifier` selector check uses Objective-C runtime (`responds(to:)`, `perform()`), unavailable on Android. Excluded entirely.

### NSObject Observer class exclusion (lines 547-563)

```swift
#if !os(Android)
private final class Observer: NSObject, Sendable { ... }
#endif
```

The KVO `Observer` class inherits from `NSObject` and implements `observeValue(forKeyPath:of:change:context:)`. This is Objective-C runtime machinery unavailable on Android.

### UserDefaults.inMemory (lines 628-645)

```swift
#if os(Android)
suiteName = "co.pointfree.Sharing.\(UUID().uuidString)"
#else
// NB: Due to a bug in iOS 16 and lower ...
if #unavailable(iOS 17, ...) {
  suiteName = "co.pointfree.Sharing.\(UUID().uuidString)"
} else {
  suiteName = "\(NSTemporaryDirectory())co.pointfree.Sharing.\(UUID().uuidString)"
}
#endif
```

Android always uses the simple UUID-based suite name (no temp directory prefix). This is cosmetic -- both paths create a fresh, isolated UserDefaults.

### Suites debug tracking (line 778)

```swift
#if DEBUG && !os(Android)
  private let suites = Mutex<[String: ObjectIdentifier]>([:])
#endif
```

Another ObjC-dependent debug check excluded on Android.

### What works on Android

| Operation | Works? | Notes |
|-----------|--------|-------|
| `load()` / read | YES | Via `AndroidUserDefaults.object(forKey:)` |
| `save()` / write | YES | Via `AndroidUserDefaults.set(_:forKey:)` |
| Write-then-immediate-read | YES | SharedPreferences commits synchronously |
| Cross-instance subscription | NO | KVO/NotificationCenter unavailable |
| `[String]` arrays | NO | `stringArray(forKey:)` marked unavailable |
| `inMemory` for tests | YES | Uses UUID-based suite name |

### Recommended test for write-then-read validation

```swift
@Test func appStorageWriteThenRead() {
  let store = UserDefaults.inMemory
  @Shared(.appStorage("testKey", store: store)) var value = 0
  $value.withLock { $0 = 99 }

  @Shared(.appStorage("testKey", store: store)) var reloaded = 0
  #expect(reloaded == 99)
}
```

**WARNING:** `@Shared(.appStorage("key"))` with `Value == [String]` will crash on Android at runtime because `AndroidUserDefaults.stringArray(forKey:)` calls `fatalError()`. The `CastableLookup` will attempt to read via `store.object(forKey:) as? [String]` which may work for the generic path, but the typed `stringArray` overload is fatal. This is a **P1 gap** that should be documented.

---

## 3. All Other Shared Keys on Android

**Directory:** `forks/swift-sharing/Sources/Sharing/SharedKeys/`

### Complete key inventory

| Key Type | File | Android Status | Notes |
|----------|------|---------------|-------|
| `InMemoryKey<Value>` | `InMemoryKey.swift` | FULL PARITY | No platform guards. Pure in-memory `Mutex<[String: any Sendable]>` storage. `subscribe()` returns no-op on ALL platforms. |
| `_SharedKeyDefault<Base>` | `DefaultKey.swift` | FULL PARITY | No platform guards. Wrapper that adds default values to any base key. Delegates all operations to `base`. |
| `AppStorageKey<Value>` | `AppStorageKey.swift` | PARTIAL | Write/read works. Subscription no-op. See Section 2. |
| `FileStorageKey<Value>` | `FileStorageKey.swift` | PARTIAL | Write/read works. File system monitoring no-op. See Section 1. |

### InMemoryKey -- detailed analysis

`InMemoryKey` has zero platform conditionals. It uses:
- `Mutex<[String: any Sendable]>` for thread-safe storage
- `subscribe()` returns `SharedSubscription {}` on ALL platforms (not just Android)
- `save()` simply writes to the dictionary
- `load()` reads from the dictionary with optional default

This means `@Shared(.inMemory("key"))` has **identical behavior** on iOS and Android.

### CustomPersistenceKey

There is no `CustomPersistenceKey` file in the SharedKeys directory. Custom persistence is achieved by conforming to `SharedKey` or `SharedReaderKey` protocols directly. Any custom key's Android behavior depends entirely on its implementation.

---

## 4. DynamicProperty.update() Exclusions

### What DynamicProperty.update() does

`DynamicProperty` is a SwiftUI protocol. Its `update()` method is called by SwiftUI before each view body evaluation. It allows property wrappers to synchronize with SwiftUI's internal state management system.

In the Point-Free ecosystem, `update()` is used to bridge Combine publishers to SwiftUI's `@State` for triggering re-renders on pre-iOS 17 (before native `@Observable` support).

### The 5 excluded instances

All 5 follow the same pattern:

```swift
#if canImport(SwiftUI)
  extension <Type>: DynamicProperty {
    #if !os(Android)
      public func update() {
        box.subscribe(state: _generation)  // or sharedReader.update()
      }
    #endif
  }
#endif
```

| # | Type | File | What `update()` does |
|---|------|------|---------------------|
| 1 | `Shared<Value>` | `swift-sharing/.../Shared.swift:496-502` | Calls `box.subscribe(state: _generation)` which sinks the Combine subject to increment a `@State var generation` counter, forcing SwiftUI re-render |
| 2 | `SharedReader<Value>` | `swift-sharing/.../SharedReader.swift:357-363` | Same as Shared |
| 3 | `Fetch<Value>` | `sqlite-data/.../Fetch.swift:167-171` | Calls `sharedReader.update()` which chains to SharedReader's update |
| 4 | `FetchOne<Value>` | `sqlite-data/.../FetchOne.swift:904-908` | Same delegation |
| 5 | `FetchAll<Element>` | `sqlite-data/.../FetchAll.swift:401-405` | Same delegation |

### Why excluded on Android

On Android, SwiftUI views are rendered by SkipUI's Compose backend. The `@State var generation` trick is an Apple-SwiftUI-specific mechanism for forcing re-renders on pre-iOS 17:

1. The `Box.subscribe(state:)` method checks `#unavailable(iOS 17, macOS 14, ...)` -- on iOS 17+ it returns early (native Observation handles it)
2. On iOS < 17, it sinks the Combine subject into `state.wrappedValue &+= 1` which triggers a SwiftUI state change

On Android:
- There is no `@State` in the Apple sense -- SkipUI maps it to Compose's `mutableStateOf`
- The observation bridge (`ObservationRecording` + `BridgeObservationSupport`) handles Compose recomposition directly via JNI
- The `@State var generation` field is excluded entirely: `#if canImport(SwiftUI) && !os(Android)` around `@State private var generation = 0`

### Observable behavior difference

**None in practice.** The `update()` mechanism is only needed for pre-iOS 17 Combine-to-SwiftUI bridging. On Android, the observation bridge handles this via `MutableStateBacking.update()` JNI calls which trigger Compose recomposition directly. The lifecycle timing differs (SwiftUI calls `update()` synchronously before body; Compose recomposition is asynchronous) but the end result -- UI updates when observed state changes -- is the same.

### Does this cause bugs?

No known bugs. The `DynamicProperty` conformance is still declared (just without the `update()` method body). SwiftUI/SkipUI still treats these types as dynamic properties. The default `update()` implementation (which is a no-op) is used on Android.

---

## 5. TestStore Non-Determinism -- Deep Analysis

**File:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/TestStore.swift`

### Three Android-specific guards in TestStore

#### Guard 1: `useMainSerialExecutor` property (lines 477-483)

```swift
#if !os(Android)
public var useMainSerialExecutor: Bool {
  get { uncheckedUseMainSerialExecutor }
  set { uncheckedUseMainSerialExecutor = newValue }
}
private let originalUseMainSerialExecutor = uncheckedUseMainSerialExecutor
#endif
```

On iOS, `TestStore` sets `useMainSerialExecutor = true` in `init()`, which serializes all async work to the main thread. This is the **primary determinism mechanism**.

On Android, `uncheckedUseMainSerialExecutor` is not available (it's a Swift runtime hook). The property is excluded entirely.

#### Guard 2: Init serialization (lines 558-560)

```swift
#if !os(Android)
self.useMainSerialExecutor = true
#endif
```

On iOS, the initializer forces serial execution. On Android, this line is skipped.

#### Guard 3: effectDidSubscribe path (lines 1006-1018)

```swift
#if !os(Android)
if uncheckedUseMainSerialExecutor {
  await Task.yield()
} else {
  for await _ in self.reducer.effectDidSubscribe.stream {
    break
  }
}
#else
for await _ in self.reducer.effectDidSubscribe.stream {
  break
}
#endif
```

This is the critical divergence in the `send()` method:

- **iOS with serial executor:** After sending an action, it simply `await Task.yield()` to let effects start. Since everything is on the main serial executor, one yield is sufficient.
- **iOS without serial executor:** Waits for `effectDidSubscribe.stream` to emit, signaling that the effect has actually subscribed.
- **Android:** Always uses the `effectDidSubscribe.stream` path (since there's no serial executor).

#### Guard 4: deinit cleanup (lines 654-656)

```swift
#if !os(Android)
uncheckedUseMainSerialExecutor = self.originalUseMainSerialExecutor
#endif
```

Restores the original serial executor state. N/A on Android.

#### Guard 5: TestStore binding view store (line 2580)

```swift
#if canImport(SwiftUI) && !os(Android)
extension TestStore { ... }
```

The `ViewStore`-based test helper for binding assertions. Excluded because `ObservedObject`/`ViewStore` machinery is not available on Android.

### The non-determinism mechanism

The `effectDidSubscribe` stream is an `AsyncStream<Void>` that the `TestReducer` yields into whenever an effect subscribes (starts executing). The flow:

1. `store.send(.action)` dispatches the action
2. The reducer runs synchronously, returns an `Effect`
3. The effect is subscribed (started) by the store's internal machinery
4. `effectDidSubscribe` yields
5. TestStore's `send()` resumes after receiving from the stream

The problem on Android: without the main serial executor, effects may interleave. If an effect spawns a child task, the child might not have subscribed by the time `effectDidSubscribe` fires for the parent effect.

### Specific patterns that could fail

```swift
// Pattern 1: Effect that immediately sends back
return .run { send in
  await send(.response(data))  // Might not be received before next assertion
}

// Pattern 2: Multiple concurrent effects
return .merge(
  .run { send in await send(.a) },
  .run { send in await send(.b) }
)
// Order of .a and .b is non-deterministic on Android

// Pattern 3: Effect with internal concurrency
return .run { send in
  async let x = fetchX()
  async let y = fetchY()
  let (xVal, yVal) = await (x, y)
  await send(.loaded(xVal, yVal))
}
// The internal ordering of fetchX/fetchY may differ
```

### Making Android TestStore more deterministic

**Option A: Custom serial executor.** Implement a `SerialExecutor` that queues all tasks:
```swift
final class AndroidSerialExecutor: SerialExecutor {
  private let queue = DispatchQueue(label: "test-store-serial")
  func enqueue(_ job: consuming ExecutorJob) {
    queue.async { job.runSynchronously(on: self.asUnownedSerialExecutor()) }
  }
}
```
Then wrap test body in `Task(executorPreference: serialExecutor) { ... }`.

**Option B: Increase `Task.megaYield` count.** The current code does `await Task.megaYield(count: 20)` after send. Increasing this gives more time for effects to settle.

**Option C: Use `.exhaustivity = .off`.** For Android-only tests, use non-exhaustive mode which is more tolerant of ordering.

### Recommended test to expose non-determinism

```swift
@Test func effectOrderingDivergence() async {
  let store = TestStore(initialState: Feature.State()) {
    Feature()
  }
  // This pattern relies on deterministic ordering:
  await store.send(.fetch)
  await store.receive(\.responseA)  // May arrive after .responseB on Android
  await store.receive(\.responseB)
}
```

---

## 6. Combine Import Issue (P1-3)

### OpenCombineShim architecture

The Point-Free ecosystem uses `OpenCombineShim` as a cross-platform Combine replacement. This package:
- On Apple platforms: re-exports Apple's `Combine` framework
- On Linux/Android: re-exports `OpenCombine` (pure Swift implementation)

**Package dependency:** `https://github.com/OpenCombine/OpenCombine.git` (from: "0.14.0")

### Import pattern across forks

#### swift-composable-architecture

Uses `import OpenCombineShim` **directly** (not `import Combine`). This is the correct cross-platform pattern. Found in 30+ source files including:
- `Store.swift`, `Core.swift`, `Effect.swift`, `TestStore.swift`
- `ViewStore.swift`, `PresentationModifier.swift`
- All effect files: `Cancellation.swift`, `Debounce.swift`, `Throttle.swift`, `Publisher.swift`
- All test files

#### swift-sharing

Uses conditional imports:
```swift
#if canImport(Combine)
  import Combine
#else
  import OpenCombineShim
#endif
```

Found in: `Shared.swift`, `SharedReader.swift`, `PassthroughRelay.swift`, `Reference.swift`, `SharedPublisher.swift`

Internal code uses `#if canImport(Combine) || canImport(OpenCombine)` for feature gates.

#### combine-schedulers

Uses:
```swift
#if canImport(Combine)
  import Combine
#elseif canImport(OpenCombineShim)
  import OpenCombineShim
#endif
#if canImport(Combine) || canImport(OpenCombineShim)
  // actual code
#endif
```

This double-gate pattern ensures code compiles on all platforms.

#### GRDB.swift

Uses `import Combine` **directly** with `#if canImport(Combine)` gates:
- `DatabaseMigrator.swift`
- `ValueObservation.swift`
- `DatabaseWriter.swift`, `DatabaseReader.swift`
- `DatabaseRegionObservation.swift`
- `ReceiveValuesOn.swift`, `OnDemandFuture.swift`

**On Android:** `canImport(Combine)` is FALSE. All Combine-dependent GRDB code is compiled out. This means:
- `ValueObservation` publisher extensions are unavailable
- `DatabaseRegionObservation` publisher is unavailable
- `DatabaseReader.readPublisher()` / `DatabaseWriter.writePublisher()` are unavailable

**Impact on sqlite-data:** The `sqlite-data` fork wraps GRDB and uses `#if canImport(Combine)` for its own Combine publishers (in `Fetch.swift`, `FetchOne.swift`, `FetchAll.swift`, `FetchKey.swift`). These are compiled out on Android.

However, the core fetch functionality uses async/await (`SharedReaderKey` protocol) which works on all platforms. Combine publishers are an optional convenience layer.

#### sqlite-data

Uses conditional imports:
```swift
#if canImport(Combine)
  import Combine
#endif
```

The Combine-dependent code (publisher conversions) is excluded on Android. Core functionality (fetch, subscribe via `SharedReaderKey`) uses async/await and works cross-platform.

### What exactly breaks on Android

**Nothing breaks at compile time.** All forks use conditional imports (`#if canImport(Combine)`) or `OpenCombineShim`. The code compiles.

**At runtime on Android:**
- Combine publisher APIs on GRDB are unavailable (compiled out)
- `OpenCombineShim` provides `OpenCombine` which is a functional replacement
- `swift-sharing` and `swift-composable-architecture` use `OpenCombine` seamlessly

### Full `import Combine` map across forks

| Fork | Files with `import Combine` | Guarded? | Android impact |
|------|---------------------------|----------|----------------|
| GRDB.swift | 8 source + 5 test files | `#if canImport(Combine)` | Publisher APIs compiled out |
| sqlite-data | 4 source files | `#if canImport(Combine)` | Publisher APIs compiled out |
| combine-schedulers | 12 source + 5 test files | `#if canImport(Combine)` / `canImport(OpenCombineShim)` | Falls back to OpenCombine |
| swift-sharing | 4 source + 2 test files | `#if canImport(Combine)` / `import OpenCombineShim` | Falls back to OpenCombine |
| swift-composable-architecture | 0 (uses `OpenCombineShim`) | N/A | Works via OpenCombine |
| swift-dependencies | 1 test file | `#if canImport(Combine)` | Test compiled out |
| skip-ui | 1 file (`Observable.swift`) | `import Combine` unconditionally | **Potential issue** -- needs verification |
| swift-perception | 1 test file | `#if canImport(Combine)` | Test compiled out |

**Note on skip-ui:** `forks/skip-ui/Sources/SkipUI/SkipUI/View/Observable.swift` has `import Combine` without a guard. This file likely relies on SkipUI's own build configuration handling.

---

## 7. Complete Guard Catalogue

### Legend

- **IE** = Intentional Exclusion (feature doesn't exist on Android, correct behavior)
- **NS** = No-op Stub (compiles but functionality missing)
- **MI** = Missing Implementation (could be implemented but isn't)
- **PF** = Polyfill (replacement implementation provided)
- **DP** = Debug-only exclusion (no runtime impact)

### 7.1 `#if os(Android)` guards (positive inclusion)

| # | File | Line | Category | Description |
|---|------|------|----------|-------------|
| 1 | `swift-sharing/.../FileStorageKey.swift` | 17 | PF | `DispatchSource.FileSystemEvent` polyfill struct |
| 2 | `swift-sharing/.../FileStorageKey.swift` | 347 | NS | `FileStorage.fileSystem` with no-op `fileSystemSource` |
| 3 | `swift-sharing/.../AppStorageKey.swift` | 457 | NS | `subscribe()` returns no-op (no KVO on Android) |
| 4 | `swift-sharing/.../AppStorageKey.swift` | 631 | PF | `UserDefaults.inMemory` uses simple UUID suite name |
| 5 | `swift-navigation/.../Binding+Internal.swift` | 6 | PF | Binding helper uses Android-compatible path |
| 6 | `swift-navigation/.../Binding.swift` | 81 | PF | Optional binding init uses Android-compatible path |
| 7 | `swift-navigation/.../Binding.swift` | 120 | PF | Collection binding uses Android-compatible path |
| 8 | `swift-navigation/.../TextState.swift` | 849 | PF | `TextState` Android replacement for SwiftUI Text |
| 9 | `swift-navigation/.../ButtonState.swift` | 391 | PF | `ButtonState.Role` Android shim |
| 10 | `xctest-dynamic-overlay/.../IsTesting.swift` | 30 | PF | Android test detection via process args / dlsym |
| 11 | `skip-android-bridge/.../AndroidBridgeBootstrap.swift` | 29 | PF | Bridge initialization |
| 12 | `skip-android-bridge/.../AndroidBundle.swift` | 7,54,308 | PF | Android bundle resource loading |
| 13 | `skip-android-bridge/.../Observation.swift` | 288 | PF | JNI exports for ViewObservation |
| 14 | `skip-android-bridge/.../Observation.swift` | 310 | PF | `swiftThreadingFatal` stub (Swift < 6.3 only) |
| 15 | `skip-android-bridge/.../AndroidUserDefaults.swift` | 3 | PF | Full AndroidUserDefaults implementation |
| 16 | `skip-android-bridge/.../AssetURLProtocol.swift` | 3 | PF | Android asset URL handling |
| 17 | `swift-composable-architecture/.../ObservationStateRegistrar.swift` | 1,11 | PF | Uses `SkipAndroidBridge.Observation.ObservationRegistrar` |
| 18 | `swift-composable-architecture/.../Store.swift` | 7,123 | PF | Uses Android observation registrar |
| 19 | `swift-composable-architecture/.../ObservedObjectShim.swift` | 6 | PF | `@ObservedObject` polyfill for Android |
| 20 | `swift-snapshot-testing/.../AssertSnapshot.swift` | 305 | PF | Android snapshot path handling |
| 21 | `swift-snapshot-testing/.../RecordTests.swift` | 165 | PF | Android test recording path |

### 7.2 `#if !os(Android)` guards (negative exclusion)

| # | File | Line | Category | Description |
|---|------|------|----------|-------------|
| 1 | `swift-sharing/.../AppStorageKey.swift` | 315 | DP | Debug suite identity check (ObjC runtime) |
| 2 | `swift-sharing/.../AppStorageKey.swift` | 547 | IE | `Observer: NSObject` KVO class |
| 3 | `swift-sharing/.../AppStorageKey.swift` | 778 | DP | Debug suites tracking |
| 4 | `swift-sharing/.../Shared.swift` | 22 | IE | `@State private var generation` (SwiftUI internal) |
| 5 | `swift-sharing/.../Shared.swift` | 366 | IE | `Box.swiftUICancellable` (SwiftUI Combine bridge) |
| 6 | `swift-sharing/.../Shared.swift` | 402,406 | IE | `Box.subscribe(state:)` (pre-iOS 17 bridge) |
| 7 | `swift-sharing/.../Shared.swift` | 497 | IE | `DynamicProperty.update()` body |
| 8 | `swift-sharing/.../SharedReader.swift` | 21 | IE | `@State private var generation` |
| 9 | `swift-sharing/.../SharedReader.swift` | 255,291,295 | IE | Box SwiftUI Combine bridge |
| 10 | `swift-sharing/.../SharedReader.swift` | 358 | IE | `DynamicProperty.update()` body |
| 11 | `swift-composable-architecture/.../TestStore.swift` | 477 | MI | `useMainSerialExecutor` property |
| 12 | `swift-composable-architecture/.../TestStore.swift` | 558 | MI | `useMainSerialExecutor = true` in init |
| 13 | `swift-composable-architecture/.../TestStore.swift` | 654 | MI | `useMainSerialExecutor` restore in deinit |
| 14 | `swift-composable-architecture/.../TestStore.swift` | 1006 | MI | effectDidSubscribe vs Task.yield branch |
| 15 | `swift-composable-architecture/.../Binding+Observation.swift` | 14 | IE | `ObservedObject.Wrapper` extension |
| 16 | `swift-composable-architecture/.../Binding+Observation.swift` | 47 | IE | `UIBinding` extension |
| 17 | `swift-composable-architecture/.../Binding+Observation.swift` | 290 | IE | Perception `@Bindable` extensions |
| 18 | `swift-composable-architecture/.../Binding+Observation.swift` | 373 | IE | Perception `@Bindable` store scoping |
| 19 | `swift-composable-architecture/.../Alert+Observation.swift` | 27,70 | IE | Alert `message:` parameter (iOS 15+) |
| 20 | `swift-composable-architecture/.../NavigationStack+Observation.swift` | 74,111 | IE | `NavigationStackStore` deprecated inits |
| 21 | `swift-composable-architecture/.../ViewAction.swift` | 31 | IE | `@ObservedObject` ViewAction extension |
| 22 | `swift-composable-architecture/.../Store+Observation.swift` | 197 | IE | `ObservedObject.Wrapper.scope()` |
| 23 | `swift-composable-architecture/.../Store+Observation.swift` | 317 | IE | Additional ObservedObject scoping |
| 24 | `swift-composable-architecture/.../Binding.swift` (SwiftUI) | 303,340 | IE | Binding ViewStore extensions |
| 25 | `swift-composable-architecture/.../Popover.swift` | 4 | IE | Entire popover file (popover API) |
| 26 | `swift-composable-architecture/.../ViewStore.swift` | 251,365 | IE | ViewStore publisher extensions |
| 27 | `swift-composable-architecture/.../ViewStore.swift` | 632 | IE | `BindingLocal` (defined in Core.swift for Android) |
| 28 | `swift-composable-architecture/.../Exports.swift` | 14 | IE | `@_exported import UIKitNavigation` |
| 29 | `swift-composable-architecture/.../ConfirmationDialog.swift` | 96 | IE | ConfirmationDialog `message:` (iOS 15+) |
| 30 | `swift-composable-architecture/.../Alert.swift` | 91 | IE | Alert `message:` (iOS 15+) |
| 31 | `swift-composable-architecture/.../NavigationStackStore.swift` | 104 | IE | NavigationStackStore deprecated init |
| 32 | `swift-composable-architecture/.../IfLetStore.swift` | 54,145,240 | IE | IfLetStore deprecated inits |
| 33 | `swift-perception/.../WithPerceptionTracking.swift` | 127 | IE | `AccessibilityRotorContent`, `Commands`, `Scene`, `TableColumnContent` conformances |
| 34 | `swift-navigation/.../ConfirmationDialog.swift` | 227 | IE | ConfirmationDialog `message:` overloads |
| 35 | `swift-navigation/.../Alert.swift` | 201 | IE | Alert `message:` overloads |
| 36 | `swift-navigation/.../Bind.swift` | 62,75 | IE | `AccessibilityFocusState`, `AppStorage`, `FocusedBinding`, `FocusState`, `SceneStorage` `_Bindable` conformances |
| 37 | `sqlite-data/.../Fetch.swift` | 168 | IE | `DynamicProperty.update()` |
| 38 | `sqlite-data/.../FetchOne.swift` | 905 | IE | `DynamicProperty.update()` |
| 39 | `sqlite-data/.../FetchAll.swift` | 402 | IE | `DynamicProperty.update()` |
| 40 | `swift-snapshot-testing/.../AssertSnapshot.swift` | 372,525 | IE | Diffing tool path (macOS/iOS specific) |

### 7.3 `#if SKIP_BRIDGE` guards

| # | File | Line | Category | Description |
|---|------|------|----------|-------------|
| 1 | `skip-android-bridge/.../ObservationModule.swift` | 3 | PF | Observation module type aliases for bridge |
| 2 | `skip-android-bridge/.../Observation.swift` | 3 | PF | Full observation bridge (ObservationRegistrar, ObservationRecording, BridgeObservationSupport, JNI exports) |

### 7.4 `#if canImport(SwiftUI) && !os(Android)` guards

| # | File | Line | Category | Description |
|---|------|------|----------|-------------|
| 1 | `swift-sharing/.../SharedReader.swift` | 21 | IE | `@State var generation` |
| 2 | `swift-sharing/.../SharedReader.swift` | 255,291,295 | IE | Box SwiftUI-specific machinery |
| 3 | `swift-sharing/.../Shared.swift` | 22 | IE | `@State var generation` |
| 4 | `swift-sharing/.../Shared.swift` | 366,402,406 | IE | Box SwiftUI-specific machinery |
| 5 | `swift-navigation/.../NavigationLink.swift` | 1 | IE | Entire file -- `NavigationLink` not available on Android |
| 6 | `swift-navigation/.../Popover.swift` | 1 | IE | Entire file -- popover API |
| 7 | `swift-navigation/.../TextState.swift` | 4,54,121,143,192,209,259,288,409,674,693,742,758 | IE | SwiftUI `Text` interop (13 guards in one file) |
| 8 | `swift-navigation/.../ButtonState.swift` | 5,66,86,129,137,150,161,209,238,260 | IE | SwiftUI Button interop (10 guards) |
| 9 | `swift-perception/.../WithPerceptionTracking.swift` | 1 | IE | Entire file |
| 10 | `swift-perception/.../Bindable.swift` | 1 | IE | Entire file |
| 11 | `swift-perception/.../PerceptionRegistrar.swift` | 3 | IE | SwiftUI-specific registrar extensions |
| 12 | `swift-custom-dump/.../SwiftUI.swift` | 1 | IE | SwiftUI type dumping |
| 13 | `sqlite-data/.../FetchKey+SwiftUI.swift` | 1 | IE | Animation-based fetch scheduling |
| 14 | `swift-composable-architecture/.../Store.swift` | 205 | IE | `send(_:animation:)` / `send(_:transaction:)` |
| 15 | `swift-composable-architecture/.../Effect.swift` | 161,215 | IE | `Effect.send(_:animation:)` and `Send.callAsFunction(_:animation:)` |
| 16 | `swift-composable-architecture/.../Dismiss.swift` | 90,122 | IE | SwiftUI dismiss integration |
| 17 | `swift-composable-architecture/.../TestStore.swift` | 2580 | IE | ViewStore-based test helpers |
| 18 | `swift-composable-architecture/.../SwitchStore.swift` | 1 | IE | Entire file |
| 19 | `swift-composable-architecture/.../Animation.swift` | 1 | IE | Effect animation extension |
| 20 | `swift-composable-architecture/.../Deprecations.swift` | 123,138 | IE | Deprecated SwiftUI helpers |
| 21 | `swift-composable-architecture/.../NavigationLinkStore.swift` | 1 | IE | Deprecated NavigationLink |
| 22 | `swift-composable-architecture/.../ActionSheet.swift` | 1 | IE | Deprecated ActionSheet |
| 23 | `swift-composable-architecture/.../LegacyAlert.swift` | 1 | IE | Deprecated Alert |
| 24 | `swift-dependencies/.../WithDependencies.swift` | 84 | IE | Preview app entry point detection |
| 25 | `swift-dependencies/.../AppEntryPoint.swift` | 3 | IE | Entire file |
| 26 | `swift-dependencies/.../Deprecations.swift` | 1,7 | IE | Deprecated SwiftUI helpers |
| 27 | `swift-dependencies/.../OpenURL.swift` | 1 | IE | `openURL` dependency (UIApplication) |
| 28 | `combine-schedulers/.../SwiftUI.swift` | 1 | IE | SwiftUI animation scheduler |

### 7.5 `#if canImport(Combine)` guards (Combine availability)

| # | Fork | File count | Description |
|---|------|-----------|-------------|
| 1 | GRDB.swift | 8 source + 7 test | Publisher extensions for ValueObservation, DatabaseRegionObservation, reader/writer |
| 2 | sqlite-data | 4 source | Combine publisher extensions for Fetch/FetchOne/FetchAll/FetchKey |
| 3 | combine-schedulers | 12 source + 5 test | All scheduler types (falls back to OpenCombineShim) |
| 4 | swift-sharing | 5 source + 2 test | Publisher bridging (falls back to OpenCombineShim) |
| 5 | swift-dependencies | 3 source | MainQueue, MainRunLoop dependencies |

### Total guard count

| Guard pattern | Count |
|--------------|-------|
| `#if os(Android)` | 21 |
| `#if !os(Android)` | 40 |
| `#if SKIP_BRIDGE` | 2 |
| `#if canImport(SwiftUI) && !os(Android)` | 28 |
| `#if canImport(Combine)` (Android-relevant) | ~32 |
| `#if DEBUG && !os(Android)` | 2 |
| **TOTAL** | **~125** |

(The R8 count of 88 likely excluded `#if canImport(Combine)` guards and `SKIP_BRIDGE` guards. Including all Android-relevant conditionals, the true total is approximately 125.)

---

## 8. Summary: Parity Gap Matrix

### P0 -- Critical (blocks TCA features on Android)

| # | Gap | Impact | Workaround | Fix effort |
|---|-----|--------|------------|------------|
| P0-1 | `@Shared(.fileStorage)` subscription no-op | Cross-instance/external file changes never propagated | None for external; single-process works fine | HIGH -- Requires Android FileObserver JNI bridge |
| P0-2 | `@Shared(.appStorage)` subscription no-op | Cross-instance UserDefaults changes never propagated | None for external; single-process works fine | MEDIUM -- Could implement SharedPreferences.OnSharedPreferenceChangeListener via JNI |
| P0-3 | TestStore non-determinism | Effect ordering may differ, causing test failures | Use `.exhaustivity = .off` or increase timeout | HIGH -- Needs custom serial executor for Android |

### P1 -- Significant (functionality reduced but app works)

| # | Gap | Impact | Workaround |
|---|-----|--------|------------|
| P1-1 | `useMainSerialExecutor` unavailable | TestStore tests may be flaky | Run tests with generous timeouts |
| P1-2 | `Effect.send(_:animation:)` excluded | No animated effect sends | Use `.run { send in withAnimation { send(.action) } }` (if SkipUI supports it) |
| P1-3 | `Store.send(_:animation:)` excluded | No animated store sends | Same as above |
| P1-4 | GRDB Combine publishers compiled out | No reactive database queries via Combine | Use async/await `ValueObservation` instead |
| P1-5 | `[String]` appStorage crashes | `stringArray(forKey:)` marked unavailable on AndroidUserDefaults | Avoid `@Shared(.appStorage("k"))` with `[String]` type |
| P1-6 | `ViewStore` publisher APIs excluded | Legacy `ViewStore.publisher` unavailable | Use `@Observable` pattern instead (recommended anyway) |

### P2 -- Minor (cosmetic or deprecated feature gaps)

| # | Gap | Impact |
|---|-----|--------|
| P2-1 | `ObservedObject.Wrapper` extensions excluded | Legacy SwiftUI pattern; `@Bindable` works |
| P2-2 | `UIBinding` extensions excluded | UIKit-specific; not relevant on Android |
| P2-3 | `NavigationLink` init extensions excluded | Android navigation uses different patterns |
| P2-4 | `Popover` excluded entirely | Android uses different sheet/dialog patterns |
| P2-5 | `SwitchStore` excluded entirely | Deprecated; use modern pattern matching |
| P2-6 | `WithPerceptionTracking` secondary conformances (Scene, Commands, etc.) excluded | Not available in SkipUI |
| P2-7 | `AccessibilityFocusState`, `FocusState`, `SceneStorage` `_Bindable` conformances excluded | Not available in SkipUI |
| P2-8 | SwiftUI `Text` interop on `TextState` excluded (13 guards) | Uses Android-specific `TextState` shims instead |
| P2-9 | SwiftUI `Button` interop on `ButtonState` excluded (10 guards) | Uses Android-specific `ButtonRole` shim |
| P2-10 | Debug suite identity check excluded | Debug-only; no user impact |

### IE -- Intentional & Correct (no gap)

| Category | Count | Notes |
|----------|-------|-------|
| SwiftUI-specific API bridges | ~45 guards | Correctly excluded; Android uses Compose equivalents |
| ObjC runtime dependencies (KVO, selectors) | ~5 guards | Not available on Android; correct exclusion |
| Deprecated API exclusions | ~8 guards | Old patterns being phased out anyway |
| OpenCombine fallbacks | ~32 guards | Working correctly via OpenCombineShim |
| Observation bridge (SKIP_BRIDGE) | 2 guards | Working replacement implementation |
| Polyfills (UserDefaults, isTesting, etc.) | ~10 guards | Correct Android-specific implementations |

---

## Appendix A: Files with most Android guards

| File | Guard count | Categories |
|------|-------------|-----------|
| `swift-navigation/.../TextState.swift` | 15 | IE (SwiftUI Text interop) |
| `swift-navigation/.../ButtonState.swift` | 12 | IE (SwiftUI Button interop) |
| `swift-composable-architecture/.../Binding+Observation.swift` | 4 | IE (ObjC binding wrappers) |
| `swift-sharing/.../Shared.swift` | 5 | IE + NS (DynamicProperty, Box) |
| `swift-sharing/.../SharedReader.swift` | 5 | IE + NS (DynamicProperty, Box) |
| `swift-sharing/.../AppStorageKey.swift` | 5 | NS + DP (subscription, debug checks) |
| `swift-composable-architecture/.../TestStore.swift` | 5 | MI (serial executor) |
| `swift-composable-architecture/.../Store.swift` | 3 | PF + IE (registrar, animation) |
| `swift-composable-architecture/.../Effect.swift` | 2 | IE (animation sends) |

## Appendix B: Recommended Phase 7 parity tests

```swift
// 1. FileStorage write-then-read (validates P0-1 write path)
@Test func fileStorage_writeThenRead_Android()

// 2. AppStorage write-then-read (validates P0-2 write path)
@Test func appStorage_writeThenRead_Android()

// 3. InMemoryKey full parity (validates no regression)
@Test func inMemoryKey_crossPlatformParity()

// 4. TestStore basic send/receive (validates P0-3 baseline)
@Test func testStore_basicSendReceive_Android()

// 5. TestStore concurrent effects (exposes P0-3 non-determinism)
@Test func testStore_concurrentEffects_orderIndependent()

// 6. AppStorage [String] guard (documents P1-5 crash)
@Test func appStorage_stringArray_unavailableOnAndroid()

// 7. OpenCombine integration (validates P1-4 fallback)
@Test func openCombine_publisherChain_works()
```
