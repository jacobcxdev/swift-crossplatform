# Proactive Concern Hunt: Threading & Deadlock Risks — Database on Android

**Created:** 2026-02-22
**Scope:** GRDB.swift fork + sqlite-data fork + interaction with TCA + Swift concurrency on Android
**Method:** Static analysis of fork source; no build or runtime verification performed

---

## Threading Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  THREAD / QUEUE / ACTOR TOPOLOGY                                    │
│                                                                     │
│  [Main Thread / @MainActor]                                         │
│    │  TCA Store processes actions here                              │
│    │  SwiftUI view body runs here                                   │
│    │  ImmediateValueObservationScheduler.immediateInitialValue()    │
│    │    checks Thread.isMainThread — MUST be called here            │
│    │  ImmediateScheduler (FetchKey fallback) delivers callbacks     │
│    │    synchronously on whatever thread calls schedule()           │
│    │                                                                │
│    │──► Effect.run { ... } suspends here, resumes on cooperative   │
│    │    thread pool via Swift concurrency                           │
│                                                                     │
│  [GRDB Writer DispatchQueue]  (serial)                              │
│    │  SerializedDatabase owns this queue                            │
│    │  All database writes, transaction commits, observer callbacks  │
│    │  asyncWriteWithoutTransaction delivers here                    │
│    │  TransactionObserver callbacks (databaseDidCommit) run here    │
│    │                                                                │
│    │──► On commit: notificationCallbacks are read under NSLock      │
│    │    Then fetched value is handed off to reduceQueue             │
│                                                                     │
│  [GRDB Reader Pool]  (concurrent DispatchQueue, up to N threads)    │
│    │  DatabasePool.asyncRead dispatches here                        │
│    │  Each reader connection is its own SerializedDatabase          │
│    │  Concurrent reads do NOT block the writer queue                │
│    │  Pool.get() uses DispatchSemaphore.wait() to limit concurrency │
│                                                                     │
│  [reduceQueue]  (serial DispatchQueue, one per ValueObservation)    │
│    │  ValueObservation reduces fetched values here                  │
│    │  Guarantees value ordering matches transaction ordering        │
│    │                                                                │
│    │──► After reducing: scheduler.schedule { onChange(value) }     │
│         scheduler determines which queue/actor the callback lands on│
│                                                                     │
│  [Scheduler-determined delivery]                                    │
│    ├── .immediate        → DispatchQueue.main.async (or sync first) │
│    ├── .mainActor        → DispatchQueue.main.async                 │
│    ├── .async(onQueue:q) → q.async                                  │
│    ├── .task             → Swift cooperative thread pool            │
│    └── ImmediateScheduler (FetchKey) → synchronous on caller        │
│                                                                     │
│  [DispatchQueueActor / SerialExecutor]                              │
│    │  Wraps the writer or reader DispatchQueue as a Swift actor     │
│    │  Used for async/await versions of read/write                   │
│    │  checkIsolated() uses dispatchPrecondition(condition:.onQueue) │
│    │  Android/Linux: DispatchQueueExecutor marked @unchecked        │
│    │    Sendable (suppresses concurrency checking)                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Finding 1 — CRITICAL: `ImmediateValueObservationScheduler` Kills Android App on Non-Main Start

**File:** `forks/GRDB.swift/GRDB/ValueObservation/ValueObservationScheduler.swift:112-116`

```swift
public func immediateInitialValue() -> Bool {
    GRDBPrecondition(
        Thread.isMainThread,
        "ValueObservation must be started from the main thread.")
    return true
}
```

**Problem:** `GRDBPrecondition` is implemented as `fatalError`. If any code calls `ValueObservation.start(in:scheduling:.immediate, ...)` from a non-main thread, the app crashes instantly.

**The path to this crash on Android:**

`FetchKey.subscribe()` defaults to `ImmediateScheduler()` (not `ImmediateValueObservationScheduler`) when no scheduler is provided — that's safe. But the documented GRDB API `scheduling: .immediate` is the `ImmediateValueObservationScheduler`. If any user code or sqlite-data layer constructs observations with `.immediate` from a background thread — for example from inside an `Effect.run {}` task body — the app will crash.

**The related `ImmediateScheduler` in FetchKey is subtly different:**

```swift
// forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift:194-199
private struct ImmediateScheduler: ValueObservationScheduler, Hashable {
  func immediateInitialValue() -> Bool { true }
  func schedule(_ action: @escaping @Sendable () -> Void) {
    action()  // runs synchronously on whatever thread calls schedule()
  }
}
```

This returns `true` from `immediateInitialValue()` without checking `Thread.isMainThread`. The initial value is then delivered synchronously — meaning it runs on the GRDB reduceQueue, not the main thread. If the `onChange` closure captures `@MainActor` state and mutates it, that mutation happens off-main without a hop, violating `@MainActor` isolation.

**Risk level:** HIGH — crash on `.immediate` with off-main start; silent isolation violation with `ImmediateScheduler`.

---

## Finding 2 — HIGH: `Pool.get()` Blocks the Calling Thread via `DispatchSemaphore.wait()`

**File:** `forks/GRDB.swift/GRDB/Utils/Pool.swift:95-119`

```swift
func get() throws -> ElementAndRelease {
    try barrierQueue.sync {
        itemsSemaphore.wait()   // <-- BLOCKS
        itemsGroup.enter()
        ...
    }
}
```

**Problem:** The synchronous `Pool.get()` does `barrierQueue.sync { itemsSemaphore.wait() }`. This means:

1. The calling thread blocks on `barrierQueue.sync`.
2. Inside that, the calling thread then blocks on `itemsSemaphore.wait()` until a reader connection becomes available.

**The async variant exists but has the same problem at a lower level:**

```swift
func get() async throws -> ElementAndRelease {
    try await semaphoreWaitingActor.execute {
        try self.get()   // <-- calls the blocking sync version
    }
}
```

The async `get()` offloads onto `semaphoreWaitingQueue` (a serial `DispatchQueue`) and then calls the blocking synchronous `get()`. While this avoids blocking the cooperative thread pool thread directly, it still parks a `DispatchQueue` thread. Under Android, thread pool limits may differ from Apple platforms. If all readers are consumed and the writer queue is waiting for a reader (e.g., in `barrierWriteWithoutTransaction`), this is a thread-parking chain that can cause starvation.

**Deadlock scenario — `barrierWriteWithoutTransaction` + full reader pool:**

```
[Writer queue] calls Pool.barrier { writer.sync { ... } }
  Pool.barrier does: barrierQueue.sync(flags: .barrier) { itemsGroup.wait() }
  itemsGroup.wait() blocks until all reader leases are returned.

  Meanwhile, all N reader connections are leased to concurrent reads
  that themselves are waiting for... the writer to finish.
  → DEADLOCK
```

This is a documented GRDB design constraint (use `asyncRead` not `read` from within writes), but it is especially dangerous on Android because:
- Android may have fewer available threads than Apple platforms
- Any async code that calls `barrierWriteWithoutTransaction` synchronously while readers are busy will deadlock

**Risk level:** HIGH — the pattern is safe under correct use but deadlocks silently under misuse, with no Android-specific protection.

---

## Finding 3 — HIGH: `DispatchQueue.main` Is Used as the Scheduler Default; Android Has No Cocoa Main Loop Guarantee

**Files:**
- `forks/GRDB.swift/GRDB/ValueObservation/ValueObservationScheduler.swift:120` — `ImmediateValueObservationScheduler.scheduleOnMainActor` calls `DispatchQueue.main.async`
- `forks/GRDB.swift/GRDB/ValueObservation/ValueObservationScheduler.swift:236` — `DelayedMainActorValueObservationScheduler.scheduleOnMainActor` calls `DispatchQueue.main.async`
- `forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift:30` — `AnimatedScheduler.schedule` calls `DispatchQueue.main.async`
- `forks/GRDB.swift/GRDB/Migration/DatabaseMigrator.swift:679` — `migratePublisher` defaults `receiveOn: DispatchQueue.main`

```swift
// DelayedMainActorValueObservationScheduler
public func scheduleOnMainActor(_ action: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async(execute: action)
}
```

**Problem:** On Apple platforms, `DispatchQueue.main` is backed by the run loop on the main thread. On Android, Swift's main thread exists but Cocoa-style main run loop integration is managed by Skip/JVM. `DispatchQueue.main.async` on Android dispatches to whatever Skip maps `DispatchQueue.main` to — typically the Android main (UI) thread via Skip's libdispatch emulation.

This is functionally correct for UI updates. However, there are two risks:

1. **`AnimatedScheduler` is gated `#if canImport(SwiftUI) && !os(Android)`** — this is handled correctly, the entire file is excluded on Android. No issue here.

2. **`migratePublisher(receiveOn: DispatchQueue.main)` default** — if migration is triggered via Combine on Android, the default delivery is `DispatchQueue.main`. Android may not have Combine at all (no `canImport(Combine)` on Android). GRDB gates all Combine code behind `#if canImport(Combine)`, so this is not reached on Android. Confirmed safe.

3. **`ImmediateValueObservationScheduler` and `DelayedMainActorValueObservationScheduler`** — both ultimately call `DispatchQueue.main.async`. If Skip's main queue dispatch has any latency difference compared to Apple's (e.g., requiring a JVM frame to drain the message queue), there can be subtle timing differences in when observation callbacks arrive relative to `@MainActor` mutations in TCA reducers.

**Risk level:** MEDIUM — functionally correct but depends on Skip's `DispatchQueue.main` fidelity.

---

## Finding 4 — HIGH: `DispatchQueue.isMain` Detection Uses `setSpecific` — Must Run Before Any Read Attempt

**File:** `forks/GRDB.swift/GRDB/Utils/Utils.swift:82-92`

```swift
extension DispatchQueue {
    private static let mainKey: DispatchSpecificKey<Void> = {
        let key = DispatchSpecificKey<Void>()
        DispatchQueue.main.setSpecific(key: key, value: ())  // called lazily
        return key
    }()

    static var isMain: Bool {
        DispatchQueue.getSpecific(key: mainKey) != nil
    }
}
```

**Problem:** This is a lazy static initializer. `DispatchQueue.main.setSpecific` is called the first time `DispatchQueue.isMain` is accessed. On Android, the JVM/Skip initialization order determines what "main queue" means at startup.

If `DispatchQueue.isMain` is first accessed from a background thread before the main queue specific has been set, `getSpecific` returns nil even on what would be the main thread. The key is set lazily on first access of `mainKey` — which triggers `DispatchQueue.main.setSpecific`. This is a one-time write. Since Swift static `let` initialization is thread-safe via `dispatch_once` internally, the write happens exactly once. Once the key is set, all subsequent `DispatchQueue.isMain` calls are correct.

However: if the `ImmediateValueObservationScheduler` uses `DispatchQueue.isMain` (it does not directly — it uses `Thread.isMainThread` instead), or if GRDB internally uses `DispatchQueue.isMain` to make scheduling decisions before the lazy init fires, there could be a window of incorrect behavior.

**Actual usage of `DispatchQueue.isMain` in GRDB:** Searched but found no production use — it appears to be an internal utility not currently called in the observable paths. This reduces the risk but the latent issue remains if future code relies on it.

**Risk level:** MEDIUM — latent, not currently triggered in the observable paths.

---

## Finding 5 — HIGH: `ValueWriteOnlyObserver.syncStart` Does `reduceQueue.sync` from the Writer Queue

**File:** `forks/GRDB.swift/GRDB/ValueObservation/Observers/ValueWriteOnlyObserver.swift:234-243`

```swift
private func syncStart(from writer: Writer) throws -> Reducer.Value {
    try writer.unsafeReentrantWrite { db in
        guard let fetchedValue = try fetchAndStartObservation(db) else {
            fatalError("can't start a cancelled or failed observation")
        }
        // Reduce
        return try reduceQueue.sync {       // <-- SYNC CALL from inside writer access
            guard let initialValue = try reducer._value(fetchedValue) else {
                fatalError("Broken contract: reducer has no initial value")
            }
            return initialValue
        }
    }
}
```

**Problem:** `syncStart` is called when `scheduler.immediateInitialValue()` returns `true`. It holds the writer connection open (via `unsafeReentrantWrite`) and then calls `reduceQueue.sync {}` from inside that writer context. This means:

- The writer queue thread is parked waiting for `reduceQueue` to complete.
- The `reduceQueue` is a freshly created serial queue, so there is no circular dependency here in isolation.
- **However:** `ImmediateValueObservationScheduler` asserts `Thread.isMainThread` before this path is taken. So this entire chain runs on the main thread, which then `sync`s into the writer queue (via `unsafeReentrantWrite`), which then `sync`s into the reduce queue.

On Apple platforms, the main thread is the main queue's thread, and `queue.sync` from the main thread to any non-main serial queue is safe. On Android, if the main thread / main queue relationship differs slightly, or if the writer queue is somehow also the main queue (unlikely but worth flagging), you get a deadlock.

**The `ValueConcurrentObserver` has the same pattern** (line 322 in ValueConcurrentObserver.swift):
```swift
let initialValue = try reduceQueue.sync {
    guard let initialValue = try reducer._value(fetchedValue) else { ... }
    return initialValue
}
```
This is called from inside a `DatabasePool.read {}` block. The read is on a reader connection queue. Reduce queue is a different queue, so no deadlock — but the reader connection is held open for the duration of the reduce.

**Risk level:** MEDIUM — safe under correct use but main-thread blocking is explicit and may interact poorly with Android's UI thread model.

---

## Finding 6 — HIGH: `SchedulingWatchdog` Uses `DispatchQueue.getSpecific` — Broken Under Swift Concurrency Hops

**File:** `forks/GRDB.swift/GRDB/Core/SchedulingWatchdog.swift`

```swift
static var current: SchedulingWatchdog? {
    DispatchQueue.getSpecific(key: watchDogKey)
}
```

`SchedulingWatchdog` detects "which database connection am I allowed to use" by reading a `DispatchSpecificKey` stored on the queue. `DispatchQueue.getSpecific` returns the value for the *current* queue.

**Problem:** When `await`-ing across a suspension point in Swift concurrency, the execution may resume on a different thread — but in a `DispatchQueueActor`, it resumes on the *same* DispatchQueue (because `DispatchQueueActor` uses `DispatchQueueExecutor` which calls `queue.async` to enqueue jobs). So within `actor.execute { }`, `DispatchQueue.getSpecific` should return the correct watchdog.

**The critical path is `SerializedDatabase.execute` (the async variant):**

```swift
func execute<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
    let cancelMutex = Mutex<(@Sendable () -> Void)?>(nil)
    return try await withTaskCancellationHandler {
        try await actor.execute {     // hopped to DispatchQueueActor
            defer {
                cancelMutex.store(nil)
                db.uncancel()
                preconditionNoUnsafeTransactionLeft(db)
            }
            cancelMutex.store(db.cancel)
            try Task.checkCancellation()
            return try block(db)      // SchedulingWatchdog.current is valid here
        }
    } onCancel: {
        cancelMutex.withLock { $0?() }
    }
}
```

Inside `actor.execute`, we are on the DispatchQueue that has the watchdog set. This is correct. The watchdog is only accessed inside the actor boundary, so Swift concurrency hops don't cause the watchdog to be read from the wrong queue.

**However:** Any code that calls `db.someMethod()` *outside* of the correct queue — e.g., storing the `Database` handle and using it from a Task that has moved to another thread — would see a nil or wrong watchdog and trigger the `GRDBPrecondition` fatal error. This is a pre-existing GRDB invariant, not Android-specific. But under Swift concurrency on Android, it is easier to accidentally violate because Task continuation queues are not fixed.

**Risk level:** MEDIUM — existing invariant, harder to accidentally violate than it looks because the DispatchQueueActor keeps you on the right queue.

---

## Finding 7 — MEDIUM: `ValueObservation` Callback → TCA Store Send → Potential Re-entrant Write

**The full data flow for a TCA + GRDB observation:**

```
1. TCA reducer dispatches Effect.run { await db.write { ... } }
   → runs on cooperative thread pool (not main actor)
   → writer.execute() hops to DispatchQueueActor (writer DispatchQueue)
   → database write commits
   → TransactionObserver.databaseDidCommit() fires on writer DispatchQueue

2. databaseDidCommit() fetches fresh value (from writer or reader connection)
   → hands fetchedValue to reduceQueue.async

3. reduceQueue runs reducer
   → scheduler.schedule { onChange(value) }

4. onChange delivers to the scheduler-specified destination:
   a. .task scheduler: delivers on Swift cooperative pool
   b. .mainActor scheduler: delivers on DispatchQueue.main
   c. .immediate (FetchKey default ImmediateScheduler): delivers synchronously
      on the reduceQueue thread (!)

5. onChange calls store.send(.dbLoaded(value))
   → TCA Store.send is @MainActor
   → If called from reduceQueue (case c), this is a cross-actor send
     → Swift concurrency correctly enqueues this on the MainActor
     → No deadlock, but the delivery is asynchronous despite the scheduler
        claiming to be "immediate"
```

**The deadlock scenario that does NOT happen (but looks like it could):**

A common fear: onChange fires on the writer queue, tries to send to the TCA store (MainActor), which runs a reducer that issues another `db.write`, which tries to acquire the writer queue → deadlock.

This does NOT deadlock because:
- `store.send` on `@MainActor` is always dispatched via the actor system, never synchronously calling back into GRDB.
- GRDB's transaction observer callbacks (`databaseDidCommit`) hand off to `reduceQueue.async`, breaking the writer queue's ownership chain before the user callback runs.
- The only synchronous path is `ValueWriteOnlyObserver.databaseDidCommit` which fetches from the writer db but then does `reduceQueue.async` — the writer queue is not held during the user onChange call.

**The scenario that IS a real risk — `ImmediateScheduler` in FetchKey:**

`FetchKey.subscribe()` uses `ImmediateScheduler` (the private one) as the default. `ImmediateScheduler.schedule` calls `action()` synchronously:

```swift
func schedule(_ action: @escaping @Sendable () -> Void) {
    action()  // synchronous!
}
```

This means `onChange(value)` runs synchronously on the `reduceQueue` thread. If the `onChange` closure does anything that tries to acquire a lock already held by the reduceQueue chain (e.g., calls back into `SharedReader` which calls back into the observation), you get a recursive lock.

More concretely: `FetchKey.subscribe` uses `observation.publisher(in: database, scheduling: scheduler)` (Combine path) or `observation.start(in: database, scheduling: scheduler)` (non-Combine). On Android there is no Combine, so the `#else` path runs:

```swift
let cancellable = observation.start(in: database, scheduling: scheduler) { error in
    subscriber.yield(throwing: error)
} onChange: { newValue in
    switch newValue {
    case .success(let value):
        subscriber.yield(value)   // <-- runs synchronously on reduceQueue
    ...
    }
}
```

`subscriber.yield(value)` calls into `Sharing`'s `SharedSubscriber`. If that triggers a synchronous re-read of the database (e.g., via another `SharedReader`), it could re-enter GRDB from the reduceQueue.

**Risk level:** MEDIUM — not a deadlock but a re-entrancy risk on Android (non-Combine path) via the synchronous `ImmediateScheduler`.

---

## Finding 8 — MEDIUM: `DispatchQueueExecutor.checkIsolated` May Behave Differently on Android

**File:** `forks/GRDB.swift/GRDB/Core/DispatchQueueActor.swift:42-44`

```swift
func checkIsolated() {
    dispatchPrecondition(condition: .onQueue(queue))
}
```

And:

```swift
#if os(Linux) || os(Android)
    extension DispatchQueueExecutor: @unchecked Sendable {}
#endif
```

`checkIsolated()` is called by the Swift runtime when `assumeIsolated` is used or when `@_unsafeInheritExecutor` paths need isolation verification. `dispatchPrecondition(condition: .onQueue(queue))` requires that `libdispatch` correctly identifies the current queue on Android.

On Android, `libdispatch` is provided by the Swift Android SDK's bundled libdispatch. `dispatchPrecondition` uses `DISPATCH_CURRENT_QUEUE_LABEL` or equivalent internal dispatch mechanism. If Skip's dispatch integration has any queue label aliasing or custom queue wrapping, `dispatchPrecondition` may fire a false positive (crash when actually on the correct queue) or false negative (pass when on the wrong queue).

The `@unchecked Sendable` suppression on Android/Linux means the Swift compiler will not verify thread safety for `DispatchQueueExecutor` on these platforms — this is an explicit opt-out from compile-time concurrency checking.

**Risk level:** MEDIUM — depends on libdispatch fidelity on Android; currently not validated.

---

## Finding 9 — MEDIUM: `Pool.barrier` Async Variant Does `itemsGroup.wait()` Inside an Actor

**File:** `forks/GRDB.swift/GRDB/Utils/Pool.swift:208-215`

```swift
func barrier<R: Sendable>(
    execute barrier: sending () throws -> sending R
) async rethrows -> sending R {
    try await barrierActor.execute {
        itemsGroup.wait()    // <-- BLOCKING WAIT inside async actor context
        return try barrier()
    }
}
```

`itemsGroup.wait()` is a synchronous blocking call. It is called inside `barrierActor.execute {}`, which runs on a DispatchQueue-backed actor. This means a DispatchQueue thread is parked while waiting for all pool elements to be returned.

**Problem:** Under Swift concurrency, parking a thread inside an actor context consumes a thread from the cooperative thread pool (or in this case, from the underlying DispatchQueue's thread pool). If the readers that are holding `itemsGroup` open are themselves waiting for something on the cooperative pool, you get a thread-starvation deadlock.

This is the async equivalent of Finding 2. Under Android, where the thread pool may be more constrained, this is more likely to manifest as starvation.

**Risk level:** MEDIUM — thread-starvation risk under high concurrency, worse on constrained Android thread pools.

---

## Finding 10 — LOW/INFO: `MainActor` in sqlite-data CloudKit Code Is iOS-Only

**File:** `forks/sqlite-data/Sources/SQLiteData/CloudKit/SyncEngine.swift:285`

```swift
Task { @MainActor in
    let taskIdentifier = UIApplication.shared.beginBackgroundTask()
    ...
}
```

All `@MainActor` uses in sqlite-data that access `UIApplication` are inside CloudKit code. CloudKit is not available on Android (no `CKSyncEngine` or `UIApplication`). This code is gated behind platform availability or will simply not compile on Android (no `UIKit`). Not a cross-platform threading risk.

**Risk level:** LOW — iOS-only code, no Android impact.

---

## Finding 11 — LOW/INFO: `FetchKey+SwiftUI.swift` Correctly Excluded on Android

**File:** `forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift:1`

```swift
#if canImport(SwiftUI) && !os(Android)
```

The `AnimatedScheduler` (which uses `DispatchQueue.main.async` and SwiftUI `Animation`) is entirely excluded on Android. This is correct.

**Risk level:** LOW — correctly handled.

---

## Summary Table

| # | Finding | Severity | Source File |
|---|---------|----------|-------------|
| 1 | `ImmediateValueObservationScheduler` fatal-errors if not called from main thread; `ImmediateScheduler` in FetchKey delivers synchronously on reduce queue | HIGH | `ValueObservationScheduler.swift`, `FetchKey.swift` |
| 2 | `Pool.get()` blocks thread via `DispatchSemaphore.wait()`; can deadlock if reader pool full during barrier write | HIGH | `Pool.swift` |
| 3 | `DispatchQueue.main.async` used as default scheduler delivery; depends on Skip's main queue fidelity | HIGH | `ValueObservationScheduler.swift` |
| 4 | `DispatchQueue.isMain` lazy-init using `setSpecific` has a one-time initialization window | MEDIUM | `Utils.swift` |
| 5 | `syncStart` calls `reduceQueue.sync` while holding writer connection; main thread blocked for duration | MEDIUM | `ValueWriteOnlyObserver.swift`, `ValueConcurrentObserver.swift` |
| 6 | `SchedulingWatchdog` uses `DispatchQueue.getSpecific`; correct within DispatchQueueActor but easy to misuse | MEDIUM | `SchedulingWatchdog.swift` |
| 7 | TCA Effect → DB write → databaseDidCommit → `ImmediateScheduler` → synchronous `subscriber.yield` on reduceQueue: re-entrancy risk on non-Combine (Android) path | MEDIUM | `FetchKey.swift`, `ValueWriteOnlyObserver.swift` |
| 8 | `DispatchQueueExecutor.checkIsolated` uses `dispatchPrecondition`; Android libdispatch fidelity unverified; `@unchecked Sendable` suppresses compiler checks | MEDIUM | `DispatchQueueActor.swift` |
| 9 | `Pool.barrier` async variant calls `itemsGroup.wait()` inside actor; thread starvation risk under Android's constrained thread pool | MEDIUM | `Pool.swift` |
| 10 | `@MainActor` + `UIApplication` in CloudKit code | LOW | `SyncEngine.swift` |
| 11 | `AnimatedScheduler` correctly excluded on Android | LOW | `FetchKey+SwiftUI.swift` |

---

## Recommended Actions (Ordered by Priority)

### Action 1 — Audit all `ValueObservation.start(scheduling:)` call sites (Finding 1)

Before any Android database work lands, grep all call sites that pass `scheduling: .immediate` or use `ImmediateValueObservationScheduler`. Verify they are started on the main actor. Add a runtime guard or document the constraint prominently.

Also audit `FetchKey`'s use of `ImmediateScheduler` (the private non-fatal version) to confirm `subscriber.yield` cannot re-enter GRDB from the reduceQueue (Finding 7).

### Action 2 — Replace `ImmediateScheduler` in FetchKey with `.async(onQueue: .main)` on Android (Findings 1, 7)

The private `ImmediateScheduler` in `FetchKey.swift` returns `true` from `immediateInitialValue()` unconditionally and calls `action()` synchronously. On Android (non-Combine path), this means observation callbacks run synchronously on the `reduceQueue`. Replace with:

```swift
#if os(Android)
let scheduler: any ValueObservationScheduler = scheduler ?? AsyncValueObservationScheduler(queue: .main)
#else
let scheduler: any ValueObservationScheduler = scheduler ?? ImmediateScheduler()
#endif
```

This makes Android behavior explicit and safe.

### Action 3 — Verify libdispatch / DispatchSemaphore behavior on Android under load (Finding 2, 9)

Write a stress test (in `examples/fuse-library`) that saturates the reader pool (e.g., N concurrent reads where N equals pool size) and then issues a barrier write. Verify no starvation occurs. This validates `Pool.get()` and `Pool.barrier` under Android's thread model.

### Action 4 — Validate `dispatchPrecondition` on Android (Finding 8)

Add a test that exercises `actor DispatchQueueActor.execute {}` and verifies no false-positive precondition fires. This validates that `DispatchQueueExecutor.checkIsolated()` works correctly with Android's libdispatch.

### Action 5 — Document scheduler choices for Android database observation (Findings 1, 3)

Add a note to `CLAUDE.md` or the Phase 6 context: on Android, use `scheduling: .async(onQueue: .main)` or `scheduling: .task` for `ValueObservation`. The `.immediate` scheduler requires a main-thread start and is unsafe to use from `Effect.run {}` bodies.

---

## Explicit Answer: The Deadlock Question

**Q: If a TCA reducer dispatches a database write via `Effect.run`, and the write triggers a `ValueObservation` callback, which thread does the callback arrive on? Could this cause a deadlock?**

**A:**

1. `Effect.run { await db.write { ... } }` runs on the Swift cooperative thread pool.
2. `writer.execute(_:)` (async) hops to the `DispatchQueueActor` (writer DispatchQueue).
3. The write commits. `TransactionObserver.databaseDidCommit` fires on the writer DispatchQueue.
4. `databaseDidCommit` enqueues a fetch, then does `reduceQueue.async { ... }`. The writer queue is released.
5. On the `reduceQueue`: reducer runs, then `scheduler.schedule { onChange(value) }`.
6. `onChange` arrives on:
   - `DispatchQueue.main` (if `.immediate` or `.mainActor` scheduler)
   - cooperative thread pool (if `.task` scheduler)
   - `reduceQueue` itself (if `ImmediateScheduler` from FetchKey, non-Combine path)

**No deadlock** occurs in the standard flow because GRDB explicitly breaks the writer queue's ownership before calling user code (via `reduceQueue.async`). The concern is re-entrancy (Finding 7) and main-thread blocking (Finding 5), not a circular wait.

**The one scenario that would deadlock:**

If `onChange` (on whatever thread) synchronously called `db.barrierWriteWithoutTransaction` or `db.write` (synchronous, non-async), and all readers were busy, the `Pool.barrier` would wait for readers to finish while the writer queue is occupied by the observation cleanup — creating a circular wait. This is prevented by always using `async/await` versions of write APIs from observation callbacks.
