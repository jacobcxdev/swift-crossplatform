# FileStorage Android Enablement -- Deep Research

## 1. Exact Compilation Guard Locations

### FileStorageKey.swift (the only source file)

**File:** `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift`

There is exactly **one top-level guard** that gates the entire file:

```swift
// Line 1
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)
  // ... entire file contents (lines 2-432) ...
#endif
// Line 432
```

None of `AppKit`, `UIKit`, or `WatchKit` can be imported on Android, so **the entire file is compiled out**.

Inside the file there are three more platform-specific import guards, but these are purely for notification observation (not relevant to the core file storage logic):

```swift
// Line 7-15: Inner import guards (UI framework imports only)
#if canImport(AppKit)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif
#if canImport(WatchKit)
  import WatchKit
#endif
```

These inner guards are harmless -- they are already conditional. No change needed for them.

### FileStorageTests.swift

**File:** `forks/swift-sharing/Tests/SharingTests/FileStorageTests.swift`

Same guard pattern:
```swift
// Line 1
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)
  // ... entire test file ...
#endif
// Line 528
```

### Deprecations.swift (Data.stub)

**File:** `forks/swift-sharing/Sources/Sharing/Internal/Deprecations.swift`

The `Data.stub` extension used by `FileStorage.fileSystem.load` is guarded by:
```swift
#if canImport(Foundation)
```
This is fine -- Foundation is available on Android. No change needed.

### Required changes -- compilation guards

| File | Line | Current guard | Change to |
|------|------|--------------|-----------|
| `FileStorageKey.swift` | 1 | `#if canImport(AppKit) \|\| canImport(UIKit) \|\| canImport(WatchKit)` | `#if canImport(AppKit) \|\| canImport(UIKit) \|\| canImport(WatchKit) \|\| os(Android)` |
| `FileStorageTests.swift` | 1 | `#if canImport(AppKit) \|\| canImport(UIKit) \|\| canImport(WatchKit)` | `#if canImport(AppKit) \|\| canImport(UIKit) \|\| canImport(WatchKit) \|\| os(Android)` |

This follows the exact same pattern used by `AppStorageKey.swift` line 1:
```swift
#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit) || os(Android)
```

---

## 2. DispatchSource Usage

### Exact API calls

`DispatchSource` is used in exactly **one place** -- the `fileSystemSource` closure of `FileStorage.fileSystem` (lines 343-362):

```swift
fileSystemSource: {
  let fileDescriptor = open($0.path, O_EVTONLY)
  guard fileDescriptor != -1 else {
    struct FileDescriptorError: Error {}
    throw FileDescriptorError()
  }
  let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fileDescriptor,
    eventMask: $1,              // DispatchSource.FileSystemEvent
    queue: DispatchQueue.main
  )
  source.setEventHandler(handler: $2)
  source.setCancelHandler {
    close(source.handle)
  }
  source.resume()
  return SharedSubscription {
    source.cancel()
  }
}
```

**APIs used:**
- `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)` -- creates a kqueue-based file system watcher
- `DispatchSource.FileSystemEvent` -- event mask type (`.write`, `.rename`, `.delete`)
- `source.setEventHandler(handler:)` -- registers callback
- `source.setCancelHandler` -- cleanup on cancel
- `source.resume()` / `source.cancel()` -- lifecycle
- `open(path, O_EVTONLY)` -- opens file descriptor for events only (Darwin-specific flag)

### Android availability

**`DispatchSource.makeFileSystemObjectSource` is NOT available on Android.** It is a Darwin-only API that wraps `kqueue(2)`. The Swift Android SDK's `libdispatch` does not include file system object sources. The `O_EVTONLY` flag is also Darwin-specific.

The `DispatchSource.FileSystemEvent` type is also referenced in the `FileStorage` struct's `fileSystemSource` field signature (line 323-325):
```swift
let fileSystemSource:
  @Sendable (URL, DispatchSource.FileSystemEvent, @escaping @Sendable () -> Void) throws ->
    SharedSubscription
```

This type reference will also fail to compile on Android.

### Subscriber usage of fileSystemSource

The `subscribe()` method (lines 118-195) creates two file system sources:
1. **External source** -- watches for `.write` and `.rename` events (external modifications)
2. **Internal source** -- watches for `.delete` events (file deletion)

Both call `storage.fileSystemSource(url, events, handler)`.

---

## 3. FileStorage Struct -- Full Analysis

**File:** `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift`, lines 316-423

### Struct fields

```swift
public struct FileStorage: Hashable, Sendable {
  let id: AnyHashableSendable
  let async: @Sendable (DispatchWorkItem) -> Void
  let asyncAfter: @Sendable (DispatchTimeInterval, DispatchWorkItem) -> Void
  let attributesOfItemAtPath: @Sendable (String) throws -> [FileAttributeKey: Any]
  let createDirectory: @Sendable (URL, Bool) throws -> Void
  let fileExists: @Sendable (URL) -> Bool
  let fileSystemSource:
    @Sendable (URL, DispatchSource.FileSystemEvent, @escaping @Sendable () -> Void) throws ->
      SharedSubscription
  let load: @Sendable (URL) throws -> Data
  let save: @Sendable (Data, URL) throws -> Void
}
```

### Android compatibility per field

| Field | Android status | Notes |
|-------|---------------|-------|
| `id` | OK | Generic hashable wrapper |
| `async` | OK | `DispatchWorkItem` is available in Android's libdispatch |
| `asyncAfter` | OK | `DispatchTimeInterval` and `DispatchWorkItem` are available |
| `attributesOfItemAtPath` | OK | `FileManager.default.attributesOfItem(atPath:)` works on Android |
| `createDirectory` | OK | `FileManager.default.createDirectory(at:withIntermediateDirectories:)` works |
| `fileExists` | OK | `FileManager.default.fileExists(atPath:)` works |
| **`fileSystemSource`** | **BROKEN** | Uses `DispatchSource.FileSystemEvent` in the **type signature** -- won't compile |
| `load` | OK | `Data(contentsOf:)` works on Android |
| `save` | OK | `Data.write(to:options:)` works on Android |

### The `.fileSystem` static property

The `fileSystem` implementation (lines 334-374) has two Android-incompatible parts:
1. **`fileSystemSource` closure** -- uses `DispatchSource.makeFileSystemObjectSource`, `O_EVTONLY`
2. **`DispatchQueue.main`** -- used as `id` and for dispatching; this IS available on Android

Everything else in `.fileSystem` (`FileManager`, `Data` I/O) works fine on Android.

---

## 4. CombineSchedulers Import

### Import location

```swift
// Line 2 (inside the outer #if guard)
import CombineSchedulers
```

The import is inside the `#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)` guard.

### Android compilation support

**CombineSchedulers DOES support Android.** From `forks/combine-schedulers/Package.swift` (line 40):

```swift
.product(
  name: "OpenCombineShim",
  package: "OpenCombine",
  condition: .when(platforms: [.linux, .android], traits: ["OpenCombineSchedulers"])
)
```

CombineSchedulers has an explicit Android platform condition using OpenCombine as the Combine backend. The `swift-sharing` Package.swift also already includes (line 45):

```swift
.product(name: "OpenCombineShim", package: "OpenCombine", condition: .when(platforms: [.linux, .android])),
```

**Conclusion:** `import CombineSchedulers` will resolve on Android. No issue here.

### Usage in FileStorageKey.swift

CombineSchedulers is only used in the `inMemory` implementation (line 386):
```swift
scheduler: AnySchedulerOf<DispatchQueue> = .immediate
```

It is used for testable time control -- not in the production `.fileSystem` path.

---

## 5. FileStorage.inMemory Variant

### Implementation (lines 380-414)

```swift
public static var inMemory: Self {
  inMemory(fileSystem: LockIsolated([:]))
}

public static func inMemory(
  fileSystem: LockIsolated<[URL: Data]>,
  scheduler: AnySchedulerOf<DispatchQueue> = .immediate
) -> Self {
  return Self(
    id: AnyHashableSendable(ObjectIdentifier(fileSystem)),
    async: { scheduler.schedule($0.perform) },
    asyncAfter: {
      scheduler.schedule(after: scheduler.now.advanced(by: .init($0)), $1.perform)
    },
    attributesOfItemAtPath: { _ in [:] },
    createDirectory: { _, _ in },
    fileExists: { fileSystem.keys.contains($0) },
    fileSystemSource: { url, event, handler in
      guard event.contains(.write)
      else { return SharedSubscription {} }
      return SharedSubscription {}
    },
    load: { /* ... */ },
    save: { data, url in
      fileSystem.withValue { $0[url] = data }
    }
  )
}
```

### Android compatibility

- **Does NOT use DispatchSource for monitoring** -- the `fileSystemSource` closure is a no-op stub
- **Uses CombineSchedulers** via `AnySchedulerOf<DispatchQueue>` for scheduling
- **BUT** the `fileSystemSource` field still has `DispatchSource.FileSystemEvent` in its TYPE SIGNATURE

The `inMemory` variant's logic is Android-compatible, but the `FileStorage` struct definition itself won't compile because the `fileSystemSource` field's type references `DispatchSource.FileSystemEvent`.

### Can it serve as a reference for Android?

Yes. The Android `.fileSystem` implementation should follow the same pattern as `.inMemory` for file monitoring: provide a no-op or polling-based `fileSystemSource` implementation. The key insight is that `.inMemory` proves the system works without real file system events.

---

## 6. URL Resolution on Android

### URL.documentsDirectory

`URL.documentsDirectory` is **NOT available** on Android's Foundation. The skip-android-bridge already polyfills related URLs:

**File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/AndroidBridgeBootstrap.swift` (lines 130-141):

```swift
#if os(Android)
extension URL {
    public static var applicationSupportDirectory: URL {
        try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }
    public static var cachesDirectory: URL {
        try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }
}
#endif
```

**Note:** There is NO `documentsDirectory` polyfill currently. One needs to be added. The implementation should be:

```swift
#if os(Android)
extension URL {
    public static var documentsDirectory: URL {
        try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
}
#endif
```

### FileManager bootstrapping

The bridge bootstraps XDG paths (lines 113-127) by setting environment variables:
- `XDG_DATA_HOME` -> `filesDir` (Android app's internal files directory)
- `XDG_CACHE_HOME` -> `cacheDir` (Android app's cache directory)
- `CFFIXED_USER_HOME` -> `filesDir` (for UserDefaults)

This means `FileManager.default.url(for: .documentDirectory, ...)` will resolve to the Android app's files directory, which is correct.

### URL(fileURLWithPath:) and Data I/O

These are standard Foundation APIs that work on Android. No bridging needed.

---

## 7. Debounced Write Coalescing

### Mechanism

The `save()` method (lines 206-255) uses a **`DispatchWorkItem`-based debounce** (not Combine):

1. First write to a key: saves immediately, then creates a `DispatchWorkItem` scheduled 1 second later
2. Subsequent writes within that 1-second window: stores the value in `state.value` and appends continuation to `state.continuations`
3. When the work item fires: writes the latest coalesced value and resumes all pending continuations
4. `userInitiated` saves (explicit `.load()` calls): cancel any pending work item and write immediately

```swift
// Line 240: Schedule debounced write
storage.asyncAfter(.seconds(1), workItem)
```

### Android compatibility

- **`DispatchWorkItem`** -- available on Android (part of libdispatch)
- **`DispatchQueue.main.asyncAfter`** -- available on Android
- **`DispatchTimeInterval.seconds(1)`** -- available on Android
- **No Combine involved** -- the debounce is purely DispatchWorkItem-based

**Conclusion:** The debounced write coalescing will work on Android without changes, provided the `FileStorage.async` and `FileStorage.asyncAfter` closures are implemented (they already use DispatchQueue).

---

## 8. Other Files Referencing FileStorage

### Source files (non-documentation)

| File | Reference | Guard needed? |
|------|-----------|--------------|
| `SharedReaderKey.swift` | Doc comment mentions `FileStorageKey` | No (just a string) |
| `SharedKey.swift` | Doc comment mentions `FileStorageKey` | No (just a string) |
| `Deprecations.swift` | `Data.stub` used by `FileStorage.fileSystem.load` | No (`#if canImport(Foundation)` already works) |

### Test files

| File | Reference | Guard needed? |
|------|-----------|--------------|
| `FileStorageTests.swift` | Entire file guarded by `#if canImport(AppKit) \|\| canImport(UIKit) \|\| canImport(WatchKit)` | **YES -- add `\|\| os(Android)`** |
| `SharedTests.swift` | Line 272: `@Shared(.fileStorage(URL(fileURLWithPath: "/"))) var count = 0` | Need to check if this line is inside a guard |

### Documentation files (no code changes needed)

- `Documentation.docc/Extensions/FileStorageKey.md`
- `Documentation.docc/Articles/Testing.md`
- `Documentation.docc/Sharing.md`
- `Documentation.docc/Articles/PersistenceStrategies.md`
- `Documentation.docc/Articles/TypeSafeKeys.md`
- `Documentation.docc/Articles/MigrationGuides/MigratingTo1.0.md`

### Example files

- `Examples/CaseStudies/GlobalRouter.swift` (line 187)
- `Examples/CaseStudies/FileStorageSharedState.swift` (line 19)

These are not compiled as part of the library target.

---

## Prescriptive Code Changes

### Change 1: Add `os(Android)` to FileStorageKey.swift outer guard

**File:** `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift`
**Line 1:**
```diff
-#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)
+#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit) || os(Android)
```

### Change 2: Replace DispatchSource.FileSystemEvent in the FileStorage struct type

The `fileSystemSource` field's type signature uses `DispatchSource.FileSystemEvent` which does not exist on Android. Two approaches:

**Option A (recommended): Create a platform-abstracted event type**

Add above the `FileStorage` struct:

```swift
#if os(Android)
  public struct FileSystemEvent: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let delete = FileSystemEvent(rawValue: 1 << 0)
    public static let write  = FileSystemEvent(rawValue: 1 << 1)
    public static let rename = FileSystemEvent(rawValue: 1 << 2)
  }
#else
  public typealias FileSystemEvent = DispatchSource.FileSystemEvent
#endif
```

Then change the `fileSystemSource` field type from `DispatchSource.FileSystemEvent` to `FileSystemEvent`.

**Option B: Conditional compilation within the struct**

Use `#if os(Android)` to provide a different type for the field on Android. More intrusive.

### Change 3: Provide Android-specific `.fileSystem` implementation

The `.fileSystem` static property needs an Android variant. Since `DispatchSource.makeFileSystemObjectSource` is unavailable, the Android implementation should provide a no-op file system source (like `.inMemory` does), or implement polling:

```swift
#if os(Android)
  public static let fileSystem = Self(
    id: AnyHashableSendable(DispatchQueue.main),
    async: { DispatchQueue.main.async(execute: $0) },
    asyncAfter: { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) },
    attributesOfItemAtPath: { try FileManager.default.attributesOfItem(atPath: $0) },
    createDirectory: {
      try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: $1)
    },
    fileExists: { FileManager.default.fileExists(atPath: $0.path) },
    fileSystemSource: { url, event, handler in
      // Android: no kqueue/DispatchSource file monitoring available.
      // File changes from external sources won't trigger subscriber updates.
      // Internal writes (via save()) still update shared state correctly.
      return SharedSubscription {}
    },
    load: { url in
      var data = try Data(contentsOf: url)
      if data == .stub {
        data = Data()
        try data.write(to: url, options: .atomic)
      }
      return data
    },
    save: { data, url in
      try data.write(to: url, options: .atomic)
    }
  )
#else
  // ... existing Darwin implementation ...
#endif
```

### Change 4: Add URL.documentsDirectory polyfill to skip-android-bridge

**File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/AndroidBridgeBootstrap.swift`

Add to the existing `#if os(Android)` URL extension block (after line 139):

```swift
public static var documentsDirectory: URL {
    try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
}
```

### Change 5: Add `os(Android)` to FileStorageTests.swift outer guard

**File:** `forks/swift-sharing/Tests/SharingTests/FileStorageTests.swift`
**Line 1:**
```diff
-#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)
+#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit) || os(Android)
```

Note: The `LiveTests` inner suite uses `DispatchSource`-dependent behavior (file watching from external writes). These tests will need additional `#if !os(Android)` guards or Android-specific expectations, since the no-op file system source means external file changes won't trigger subscriber updates.

### Change 6: Guard NSTemporaryDirectory() usage in tests

`NSTemporaryDirectory()` may behave differently on Android. Test URL helpers should use an Android-safe temporary path. This can be verified during implementation.

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|-----------|
| No file system event monitoring on Android | Medium | Save/load/debounce all work. Only external file modifications (from another process or manual edit) won't be detected. This is acceptable for TCA apps where all writes go through `@Shared`. |
| `URL.documentsDirectory` missing | High (crash) | Add polyfill to skip-android-bridge (Change 4) |
| `DispatchSource.FileSystemEvent` type not compiling | High (build break) | Abstract the type (Change 2) |
| CombineSchedulers on Android | Low | Already supported via OpenCombine |
| DispatchWorkItem/DispatchQueue on Android | None | Already available in Android libdispatch |

## Summary

The core blocker is the `#if canImport(AppKit) || canImport(UIKit) || canImport(WatchKit)` guard that excludes Android entirely. The fix requires:

1. **One guard change** on the outer `#if` (add `|| os(Android)`)
2. **Abstract away `DispatchSource.FileSystemEvent`** from the `FileStorage` struct's type signature
3. **Provide an Android `.fileSystem`** with no-op file monitoring (all other operations work)
4. **Add `URL.documentsDirectory`** polyfill to skip-android-bridge
5. **Update test guards** to include Android

The debounced write coalescing, CombineSchedulers integration, and all file I/O operations work on Android without changes.
