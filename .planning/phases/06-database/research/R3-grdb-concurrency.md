# R3 — GRDB Concurrency Model: Android Deep-Dive

**Date:** 2026-02-22
**Scope:** `forks/GRDB.swift` — full audit of concurrency primitives, executor model, DatabasePool/DatabaseQueue, ValueObservation change detection, and Android compatibility.

---

## 1. The Actor/Executor Stack

### 1.1 `DispatchQueueActor` — The Root of All GRDB Concurrency

File: `GRDB/Core/DispatchQueueActor.swift`

```swift
import Dispatch

actor DispatchQueueActor {
    private let executor: DispatchQueueExecutor

    /// - precondition: the queue is serial, or flags contains `.barrier`.
    init(queue: DispatchQueue, flags: DispatchWorkItemFlags = []) {
        self.executor = DispatchQueueExecutor(queue: queue, flags: flags)
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func execute<T>(_ work: () throws -> T) rethrows -> T {
        try work()
    }
}

private final class DispatchQueueExecutor: SerialExecutor {
    private let queue: DispatchQueue
    private let flags: DispatchWorkItemFlags

    func enqueue(_ job: UnownedJob) {
        queue.async(flags: flags) {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func checkIsolated() {
        dispatchPrecondition(condition: .onQueue(queue))
    }
}

#if os(Linux) || os(Android)
    extension DispatchQueueExecutor: @unchecked Sendable {}
#endif
```

**Key observations:**

- Every async database operation in GRDB ultimately runs via `DispatchQueueActor.execute(_:)`, which dispatches work onto a `DispatchQueue` using `queue.async(flags:)`.
- `DispatchQueueExecutor` implements the Swift `SerialExecutor` protocol by wrapping a `DispatchQueue`. Jobs are enqueued as `DispatchQueue.async` calls, and `job.runSynchronously(on:)` executes the Swift concurrency job on that queue's thread.
- `checkIsolated()` calls `dispatchPrecondition(condition: .onQueue(queue))` — this is a libdispatch primitive that is fully supported on Android via the Swift SDK's bundled libdispatch.
- The `@unchecked Sendable` conformance is conditionally applied only for `Linux || Android` because Darwin's `DispatchQueueExecutor` already synthesises this conformance differently. This guard already exists in the fork — **no action needed here**.

### 1.2 `SerializedDatabase` — The Connection Serialiser

File: `GRDB/Core/SerializedDatabase.swift`

This is the central object that serialises all access to a single SQLite connection:

```swift
final class SerializedDatabase {
    private let db: Database
    private let actor: DispatchQueueActor   // async Swift concurrency path
    private let queue: DispatchQueue        // sync/callback path
    ...
    init(...) throws {
        // Force SQLite into multi-thread mode (not serialized):
        // GRDB's own serial queue provides all needed serialisation.
        config.threadingMode = .multiThread
        ...
        self.queue = configuration.makeWriterDispatchQueue(label: identifier)
        self.actor = DispatchQueueActor(queue: queue)
        SchedulingWatchdog.allowDatabase(db, onQueue: queue)
    }
}
```

The two dispatch paths:
- **Sync path** (`sync`, `reentrantSync`): Uses `queue.sync { }` directly — the classic GCD blocking call.
- **Async path** (`execute` async): Delegates to `actor.execute { }` which goes through `DispatchQueueActor` / `DispatchQueueExecutor`.
- **Fire-and-forget** (`async`): Uses `queue.async { }` directly.

SQLite threading mode is set to `.multiThread` (not `.serialized`) because the serial `DispatchQueue` guarantees single-threaded access to each connection. This is a correct and important optimisation.

---

## 2. `SchedulingWatchdog` — Queue Identity Tracking

File: `GRDB/Core/SchedulingWatchdog.swift`

```swift
#if !canImport(Darwin)
@preconcurrency
#endif
import Dispatch

final class SchedulingWatchdog: @unchecked Sendable {
    private static let watchDogKey = DispatchSpecificKey<SchedulingWatchdog>()

    static func allowDatabase(_ database: Database, onQueue queue: DispatchQueue) {
        let watchdog = SchedulingWatchdog(allowedDatabase: database)
        queue.setSpecific(key: watchDogKey, value: watchdog)
    }

    static var current: SchedulingWatchdog? {
        DispatchQueue.getSpecific(key: watchDogKey)
    }
}
```

`DispatchQueue.setSpecific(key:value:)` / `DispatchQueue.getSpecific(key:)` are libdispatch TLS (thread-local-storage) equivalents, used to associate a watchdog with the queue's execution context. These are fully supported by libdispatch on Android. The `#if !canImport(Darwin)` guard adds `@preconcurrency` to the import to silence concurrency warnings on non-Darwin platforms — this is already in place.

---

## 3. `DatabasePool` — Concurrent Readers, Serialised Writer

File: `GRDB/Core/DatabasePool.swift`

### Architecture

```
DatabasePool
├── writer: SerializedDatabase          (single, serial writer queue)
└── readerPool: Pool<SerializedDatabase> (up to N concurrent readers)
```

**Writer:** A single `SerializedDatabase` on its own serial `DispatchQueue`. All writes are serialised through this one connection.

**Readers:** A `Pool<SerializedDatabase>` of up to `configuration.maximumReaderCount` connections (default 5), each on its own serial `DispatchQueue`. The pool manages availability via `DispatchSemaphore`.

**WAL mode:** `DatabasePool` always sets up WAL mode (unless readonly):

```swift
if !configuration.readonly {
    switch configuration.journalMode {
    case .default, .wal:
        try writer.sync {
            try $0.setUpWALMode()
        }
    }
}
```

This is unconditional — `DatabasePool` always runs in WAL mode. WAL is the mechanism that allows concurrent reads while a write is in progress.

### Isolation pattern for concurrent reads

```swift
// DatabasePool.asyncConcurrentRead (simplified):
let isolationSemaphore = DispatchSemaphore(value: 0)
let (reader, releaseReader) = try readerPool.get()
reader.async { db in
    try db.beginTransaction(.deferred)
    try db.clearSchemaCacheIfNeeded()
    isolationSemaphore.signal()      // unblock writer queue
    value(.success(db))
    // ... commit or rollback
}
_ = isolationSemaphore.wait(timeout: .distantFuture)  // writer blocks until snapshot established
```

`DispatchSemaphore` is a pure libdispatch primitive, fully available on Android.

### iOS-only memory management

```swift
#if os(iOS)
if configuration.automaticMemoryManagement {
    setupMemoryManagement()  // UIApplication notifications
}
#endif
```

The entire iOS memory-pressure handling (`UIApplicationDidReceiveMemoryWarningNotification`, `UIApplicationDidEnterBackgroundNotification`) is conditionally compiled out on Android. **No issue.**

### Database suspension (iOS app extension guard)

```swift
private func setupSuspension() {
    if configuration.observesSuspensionNotifications {
        let center = NotificationCenter.default
        suspensionObservers.append(center.addObserver(
            forName: Database.suspendNotification, ...
        ))
    }
}
```

Suspension uses `NotificationCenter` (Foundation, available on Android) and `sqlite3_interrupt()` (SQLite C API, always available). The `0xdead10cc` scenario is iOS-specific but the mechanism itself is cross-platform. **No issue.**

---

## 4. `DatabaseQueue` — Simplified Single-Connection Model

File: `GRDB/Core/DatabaseQueue.swift`

`DatabaseQueue` uses a single `SerializedDatabase` for both reads and writes. Reads block the writer queue:

```swift
public func read<T>(_ value: (Database) throws -> T) throws -> T {
    try writer.sync { db in
        try db.isolated(readOnly: true) { try value(db) }
    }
}
```

- No reader pool, no WAL requirement (defaults to `DELETE` journal mode).
- Can optionally use WAL: `configuration.journalMode = .wal`.
- All iOS-specific blocks are `#if os(iOS)` guarded.
- No Android-specific concerns: uses only `DispatchQueue.sync`, `DispatchQueue.async`, and SQLite C API.

---

## 5. `Pool<T>` — The Reader Pool Implementation

File: `GRDB/Utils/Pool.swift`

The pool uses these concurrency primitives:

```swift
final class Pool<T: Sendable>: Sendable {
    private let itemsSemaphore: DispatchSemaphore   // capacity limit
    private let itemsGroup: DispatchGroup            // barrier synchronisation
    private let barrierQueue: DispatchQueue          // concurrent queue for barriers
    private let barrierActor: DispatchQueueActor     // async barrier path
    private let semaphoreWaitingQueue: DispatchQueue // serial wait queue
    private let semaphoreWaitingActor: DispatchQueueActor
    private let contentLock: ReadWriteLock<Content>  // guards items array
}
```

Primitives used:
| Primitive | Android availability |
|-----------|---------------------|
| `DispatchSemaphore` | Full support (libdispatch) |
| `DispatchGroup` | Full support (libdispatch) |
| `DispatchQueue` (concurrent + serial) | Full support (libdispatch) |
| `DispatchQueue.sync(flags: .barrier)` | Full support (libdispatch) |
| `DispatchQueueActor` | See §1.1 above |

The barrier pattern for `releaseMemory()`:

```swift
readerPool?.barrier {
    readerPool?.removeAll()
}
```

This calls `barrierQueue.sync(flags: [.barrier]) { itemsGroup.wait(); barrier() }` — pure libdispatch, fully Android-compatible.

---

## 6. `ReadWriteLock<T>` — The Content Guard

File: `GRDB/Utils/ReadWriteLock.swift`

```swift
final class ReadWriteLock<T> {
    private var _value: T
    private var queue: DispatchQueue  // concurrent queue

    func read<U>(_ body: (T) throws -> U) rethrows -> U {
        try queue.sync { try body(_value) }           // concurrent read
    }

    func withLock<U>(_ body: (inout T) throws -> U) rethrows -> U {
        try queue.sync(flags: [.barrier]) { try body(&_value) }  // exclusive write
    }
}
```

This is a readers-writer lock implemented entirely via libdispatch barrier blocks. **Fully Android-compatible.** No `os_unfair_lock`, no `pthread_rwlock`, no Darwin-only primitives.

---

## 7. `Mutex<T>` — The General-Purpose Lock

File: `GRDB/Utils/Mutex.swift`

```swift
final class Mutex<T> {
    private var _value: T
    private var lock = NSLock()   // backed by pthread_mutex

    func withLock<U>(_ body: (inout T) throws -> U) rethrows -> U {
        lock.lock()
        defer { lock.unlock() }
        return try body(&_value)
    }
}
```

`NSLock` is Foundation, backed by `pthread_mutex_t`. Foundation's `NSLock` is available on Android via the Swift Android SDK. **No issue.**

The comment in the source notes this is a placeholder until SE-0433 `Mutex` (stdlib `Mutex`) is available. When that happens, the migration would be trivially cross-platform.

---

## 8. Android Guards Catalogue

### 8.1 `DispatchQueueActor.swift` — `@unchecked Sendable` conformance

```swift
#if os(Linux) || os(Android)
    extension DispatchQueueExecutor: @unchecked Sendable {}
#endif
```

**Purpose:** Darwin's Dispatch module marks its types differently for Swift Concurrency. On Linux/Android, explicit `@unchecked Sendable` is needed for the private executor class. **Already handled.**

### 8.2 `StatementAuthorizer.swift` — C stdlib import

```swift
#if canImport(string_h)
import string_h
#elseif os(Android)
import Android
#elseif os(Linux)
import Glibc
#elseif os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
import Darwin
#elseif os(Windows)
import ucrt
#endif
```

**Purpose:** Imports the C standard library for `memcmp` / `strlen` used in SQLite callback implementations. The `Android` module is correctly imported. **Already handled.**

### 8.3 Foundation type exclusions

The following files are entirely excluded on Android (and Linux):

| File | Guard | Excluded type |
|------|-------|---------------|
| `NSNumber.swift` | `!os(Linux) && !os(Windows) && !os(Android)` | `NSNumber: DatabaseValueConvertible` |
| `NSData.swift` | `!os(Linux) && !os(Android)` | `NSData: DatabaseValueConvertible` |
| `NSString.swift` | `!os(Linux) && !os(Android)` | `NSString: DatabaseValueConvertible` |
| `UUID.swift` | `!os(Linux) && !os(Windows) && !os(Android)` | `UUID: DatabaseValueConvertible` (ObjC UUID) |
| `Decimal.swift` | `!os(Linux) && !os(Android)` | `NSDecimalNumber: DatabaseValueConvertible` |
| `Date.swift` (partial) | `!os(Linux) && !os(Android)` | `NSDate: DatabaseValueConvertible` (ObjC bridged) |

**Purpose:** Objective-C bridging types (`NSNumber`, `NSData`, `NSString`, `NSDecimalNumber`, `NSDate`) are not available on Android. These exclusions are correct and complete.

**Impact on app code:** Users cannot store/fetch `NSNumber`, `NSData`, `NSString`, or `NSDecimalNumber` directly on Android. They must use Swift native types (`Int`, `Double`, `Data`, `String`, `Decimal`, `Date`). The Swift native equivalents (`Date`, `Data`, `String`) are available.

**Notable gap:** `UUID` from `Foundation` is excluded. Swift's `UUID` is a value type from Foundation that is available on Android (it does not require ObjC). However, the file guards use `!os(Android)` — this must be checked further to determine if the guard is overly broad and whether `UUID` as a `DatabaseValueConvertible` could be re-enabled on Android. Swift's `UUID` (not `NSUUID`) should compile on Android.

---

## 9. `DispatchSource` — Confirmed NOT Used

A full-text search for `DispatchSource` across all GRDB Swift source files returns **zero matches**.

GRDB does not use `DispatchSource` (file system event monitoring, timers, signal handlers) anywhere in the library. This is a significant positive finding: file-system-based change detection is not part of GRDB's architecture.

---

## 10. `pthread` and `os_unfair_lock` — Confirmed NOT Used

A full-text search across all GRDB Swift sources:
- `os_unfair_lock` — **zero matches**
- `pthread_mutex` — **zero matches**
- `pthread_rwlock` — **zero matches**
- `OSSpinLock` — **zero matches**

All synchronisation is done via:
- `NSLock` (Foundation, available Android) — used by `Mutex<T>` and `ValueConcurrentObserver`/`ValueWriteOnlyObserver`
- `DispatchQueue.sync` with `.barrier` flags — used by `ReadWriteLock<T>`
- `DispatchSemaphore` — used by `Pool<T>` and `asyncConcurrentRead`
- `DispatchGroup` — used by `Pool<T>` barrier

No Darwin-exclusive locking primitives are used anywhere. **Clean.**

---

## 11. ValueObservation Change Detection

### 11.1 Mechanism

ValueObservation does **not** use file system events, `DispatchSource`, kqueue, inotify, or any OS-level file monitoring. Change detection is entirely SQLite-hook-based:

```
sqlite3_update_hook  → DatabaseObservationBroker.databaseDidChange(with:)
sqlite3_commit_hook  → DatabaseObservationBroker.databaseDidCommit()
sqlite3_rollback_hook → DatabaseObservationBroker.databaseDidRollback()
```

These hooks fire in the SQLite connection's execution context (the writer dispatch queue), and the broker dispatches notifications to registered `TransactionObserver` objects.

The `TransactionObserver` protocol:
```swift
public protocol TransactionObserver: AnyObject {
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool
    func databaseDidChange(with event: DatabaseEvent)
    func databaseDidCommit(_ db: Database)
    func databaseDidRollback(_ db: Database)
}
```

`ValueConcurrentObserver` and `ValueWriteOnlyObserver` both implement this protocol. When `databaseDidCommit` fires, they schedule a fetch and reduce cycle.

### 11.2 `ValueConcurrentObserver` — DatabasePool path

The concurrent observer uses a three-stage pipeline:

```
[writer queue] databaseDidCommit() fires
    → setNeedsFetching()
    → [reader pool] asyncRead { fetch }       ← concurrent, non-blocking
    → [reduceQueue] reduce(fetchedValue)      ← separate serial queue
    → [scheduler] onChange(value)             ← user queue/actor
```

The `reduceQueue` is a dedicated serial `DispatchQueue` created per-observation. It guarantees that value notifications are delivered in transaction order even when fetches run concurrently on reader connections.

State protection:
- `observationState` (region, isModified) — protected by writer serial queue (no lock needed)
- `databaseAccess`, `notificationCallbacks` — protected by `NSLock` (cross-queue access)
- `reducer` — protected by `reduceQueue` (serial queue)
- `fetchingStateMutex` — `Mutex<FetchingState>` (NSLock-backed)

### 11.3 `ValueWriteOnlyObserver` — DatabaseQueue / `requiresWriteAccess` path

Fetches always happen on the writer queue. Simpler but blocks concurrent writes during fetch.

### 11.4 `SQLITE_ENABLE_SNAPSHOT` — WAL snapshot optimisation

```swift
#if SQLITE_ENABLE_SNAPSHOT && !SQLITE_DISABLE_SNAPSHOT
// Use WALSnapshot to detect if DB changed between initial fetch and observation start
extension ValueConcurrentObserver {
    private func syncStart(from databaseAccess: DatabaseAccess) throws -> Reducer.Value {
        let initialFetchTransaction = try databaseAccess.dbPool.walSnapshotTransaction()
        // ... compare snapshots to detect unobserved window changes
    }
}
#else
extension ValueConcurrentObserver {
    // Falls back to always doing a secondary fetch from writer queue
    private func syncStart(from databaseAccess: DatabaseAccess) throws -> Reducer.Value {
        try syncStartWithoutWALSnapshot(from: databaseAccess)
    }
}
#endif
```

**Android impact:** The Swift Android SDK ships SQLite3 compiled without `SQLITE_ENABLE_SNAPSHOT`. The `#else` branch will be taken on Android, meaning:

- `ValueObservation` on a `DatabasePool` will **always** perform a secondary fetch from the writer connection when observation starts (in addition to the initial read-side fetch).
- This may result in the initial value being notified **twice** (documented behaviour — user can add `.removeDuplicates()`).
- No correctness issue, only a documented performance/UX characteristic.

---

## 12. WAL Mode — Android-Specific Concerns

### 12.1 WAL file setup

`DatabasePool.setUpWALMode()` in `Database.swift`:

```swift
func setUpWALMode() throws {
    let journalMode = try String.fetchOne(self, sql: "PRAGMA journal_mode = WAL")
    guard journalMode == "wal" else {
        throw DatabaseError(message: "could not activate WAL Mode at path: \(path)")
    }
    try execute(sql: "PRAGMA synchronous = NORMAL")

    // Ensures a non-empty WAL file exists to prevent SQLITE_ERROR on first snapshot
    let walPath = path + "-wal"
    if try FileManager.default.fileExists(atPath: walPath) == false
        || (URL(fileURLWithPath: walPath).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == 0
    {
        try inSavepoint {
            try execute(sql: """
                CREATE TABLE grdb_issue_102 (id INTEGER PRIMARY KEY);
                DROP TABLE grdb_issue_102;
                """)
            return .commit
        }
    }
}
```

**Android concern:** `FileManager.default.fileExists(atPath:)` and `URL.resourceValues(forKeys:)` are Foundation APIs. Both are available on Android via the Swift Foundation port. However, `URL.resourceValues(forKeys: [.fileSizeKey])` uses `URLResourceKey.fileSizeKey`, which depends on `stat()` under the hood. This should work on Android but has not been explicitly tested in this fork.

**Mitigation:** If `fileExists` or `resourceValues` fail on Android, GRDB will either skip the WAL prime write (if the condition is false-positive) or throw (if it gets a wrong size). The worst case is a harmless extra `CREATE/DROP TABLE` write on every pool open.

### 12.2 WAL mode and multiple processes

WAL mode on Android is safe for single-process use. Multi-process access to the same SQLite database (e.g., from an app and an app extension running simultaneously) is an iOS-specific concern. Android apps do not have app extensions in the same sense, so multi-process WAL concerns are not relevant by default.

### 12.3 WAL checkpointing

`Database.checkpoint()` calls `sqlite3_wal_checkpoint_v2()` — a standard SQLite C API with no platform dependencies.

### 12.4 `SQLITE_BUSY` in WAL readers

GRDB sets a 10-second busy timeout on reader connections in `DatabasePool`:

```swift
if configuration.readonlyBusyMode == nil {
    configuration.readonlyBusyMode = .timeout(10)
}
```

This is implemented via `sqlite3_busy_timeout()` — no platform concerns.

---

## 13. `Configuration` — Android-Relevant Settings

File: `GRDB/Core/Configuration.swift`

```swift
#if !canImport(Darwin)
@preconcurrency
#endif
import Dispatch
```

The `#if !canImport(Darwin)` guard adds `@preconcurrency` to the Dispatch import on Linux/Android to silence Sendable warnings.

`Configuration.makeWriterDispatchQueue` and `makeReaderDispatchQueue` create `DispatchQueue` instances with QoS levels — fully Android-compatible.

`Configuration.observesSuspensionNotifications` defaults to `false`. Users must opt in. On Android there are no iOS-style `0xdead10cc` concerns, so this should remain disabled (or simply never called).

---

## 14. `NSLock.synchronized` — Extension Pattern

File: `GRDB/Utils/Utils.swift`

```swift
extension NSLocking {
    func synchronized<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}
```

`NSLocking` / `NSLock` are Foundation types. Foundation on Android supports `NSLock` (backed by `pthread_mutex`). This pattern is used extensively throughout the observers. **No issue.**

Also notable in `Utils.swift`:

```swift
#if !canImport(ObjectiveC)
@inlinable func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result { try body() }
#endif
```

Android does not have Objective-C, so `autoreleasepool` is a no-op shim. GRDB uses `autoreleasepool` in some fetch loops to manage memory. On Android this compiles as a straight call-through. **No issue.**

---

## 15. Summary of All Android Guards in the Fork

| File | Guard pattern | Reason |
|------|---------------|--------|
| `DispatchQueueActor.swift` | `os(Linux) \|\| os(Android)` | `@unchecked Sendable` for executor |
| `StatementAuthorizer.swift` | `os(Android)` | C stdlib import (`import Android`) |
| `NSNumber.swift` | `!os(Linux) && !os(Windows) && !os(Android)` | ObjC-only type excluded |
| `NSData.swift` | `!os(Linux) && !os(Android)` | ObjC-only type excluded |
| `NSString.swift` | `!os(Linux) && !os(Android)` | ObjC-only type excluded |
| `UUID.swift` | `!os(Linux) && !os(Windows) && !os(Android)` | ObjC UUID bridging excluded |
| `Decimal.swift` | `!os(Linux) && !os(Android)` | `NSDecimalNumber` excluded |
| `Date.swift` | `!os(Linux) && !os(Android)` | `NSDate` ObjC bridging excluded |
| `Configuration.swift` | `!canImport(Darwin)` | `@preconcurrency` import |
| `SchedulingWatchdog.swift` | `!canImport(Darwin)` | `@preconcurrency` import |
| `Utils.swift` | `!canImport(Darwin)` | `@preconcurrency` import |
| `DatabasePool.swift` | `os(iOS)` | UIKit memory management |
| `DatabaseQueue.swift` | `os(iOS)` | UIKit memory management |

---

## 16. Risk Assessment for Android Deployment

### Risk Matrix

| Area | Risk Level | Notes |
|------|-----------|-------|
| `DispatchQueueActor` / `SerialExecutor` | **LOW** | libdispatch fully available; `os(Android)` guard already in place |
| `DispatchSemaphore` / `DispatchGroup` | **LOW** | Core libdispatch, supported on Android |
| `NSLock` / `NSLocking` | **LOW** | Foundation pthread wrapper, available on Android |
| `ReadWriteLock` (barrier queues) | **LOW** | Pure libdispatch, no Darwin specifics |
| `DispatchSource` | **N/A** | Not used anywhere in GRDB |
| `os_unfair_lock` / `pthread_rwlock` | **N/A** | Not used anywhere in GRDB |
| WAL mode setup | **LOW-MEDIUM** | `FileManager` + `URL.resourceValues` need Android validation |
| `SQLITE_ENABLE_SNAPSHOT` | **LOW** | Falls back gracefully; causes documented double-notification at start |
| `NSNumber`/`NSData`/`NSString` unavailable | **MEDIUM** | API surface reduction; Swift native types still work |
| `UUID` DatabaseValueConvertible | **MEDIUM** | Guard may be overly broad — Swift `UUID` (not `NSUUID`) may be available |
| `Date`/`DateFormatter` | **LOW** | Swift `Date` conformance is unconditional; only `NSDate` excluded |
| iOS memory management | **N/A** | Entirely `#if os(iOS)` guarded |
| Database suspension | **LOW** | Mechanism is cross-platform; iOS scenario (0xdead10cc) does not apply |
| `NotificationCenter` (suspension) | **LOW** | Foundation NotificationCenter available on Android |
| `autoreleasepool` shim | **LOW** | No-op on Android; correct behaviour |
| Combine publishers | **N/A** | `#if canImport(Combine)` — Combine not available on Android |
| `DatabasePool` concurrent reads | **LOW** | Pure DispatchQueue/Semaphore/Group |
| `SchedulingWatchdog` | **LOW** | `DispatchSpecificKey` (libdispatch TLS) fully supported |

### Identified Issues Requiring Action

**Issue 1 — UUID `DatabaseValueConvertible` may be incorrectly excluded (MEDIUM risk)**

The guard `#if !os(Linux) && !os(Windows) && !os(Android)` in `UUID.swift` excludes Swift `UUID` as a `DatabaseValueConvertible` on Android. However, Swift's `UUID` is a pure Swift value type available on Android. The exclusion might be copied from Linux guards that predate Android support. If confirmed, this should be fixed by using `#if canImport(ObjectiveC)` instead to target the correct Objective-C dependency.

**Issue 2 — WAL initialisation uses `URL.resourceValues(forKeys:)` (LOW-MEDIUM risk)**

`Database.setUpWALMode()` uses `URL(fileURLWithPath: walPath).resourceValues(forKeys: [.fileSizeKey])` to check if the WAL file is empty. This is an NSURL bridging API. It should work on Android but requires validation. If it fails silently (returns nil), GRDB will harmlessly perform an extra CREATE/DROP TABLE write. If it throws unexpectedly, it could prevent pool initialisation.

**Issue 3 — `SQLITE_ENABLE_SNAPSHOT` unavailable causes double initial notification (LOW risk)**

Without WAL snapshots, `ValueObservation` on a `DatabasePool` always does a secondary writer-queue fetch on startup. This results in the first observed value being emitted twice. Users must add `.removeDuplicates()` to avoid spurious UI updates. This is documented GRDB behaviour but should be highlighted to app developers.

**Issue 4 — Combine publisher support absent on Android (N/A, by design)**

`#if canImport(Combine)` correctly excludes all Combine-based APIs. The `AsyncValueObservation` (Swift Concurrency `AsyncSequence`) path and the callback-based `start(in:scheduling:onError:onChange:)` path both work without Combine and are the recommended paths for Android.

**Issue 5 — `NSRecursiveLock` in Combine `ValueSubscription` (iOS/macOS only)**

The `ValueSubscription` class inside `DatabasePublishers.Value` uses `NSRecursiveLock`. Since the entire Combine block is `#if canImport(Combine)`, this does not compile on Android. **No action needed.**

### Overall Android Deployment Assessment

**Verdict: GRDB's concurrency model is fundamentally Android-compatible.**

The core design — `DispatchQueue`-backed serial executor, libdispatch semaphores/groups/barriers, `NSLock`-backed mutex, SQLite hook-based change detection — uses no Darwin-exclusive concurrency primitives. Every critical path has either been explicitly guarded for Android or uses cross-platform APIs.

The existing Android guards in the fork are correct and complete for the concurrency layer. The primary action items are:

1. Validate `UUID` `DatabaseValueConvertible` guard scope.
2. Test WAL mode initialisation on Android (specifically the `FileManager`/`URL.resourceValues` path).
3. Document the double-initial-notification behaviour for `DatabasePool` + `ValueObservation` on Android and recommend `.removeDuplicates()` in app-level observation setup.
4. Use `DatabasePool` (not `DatabaseQueue`) for production — WAL concurrent reads are essential for responsive UI on Android (same as iOS).
5. Avoid `requiresWriteAccess = true` on observations where possible — this forces the `ValueWriteOnlyObserver` path which blocks the writer queue during fetch.
