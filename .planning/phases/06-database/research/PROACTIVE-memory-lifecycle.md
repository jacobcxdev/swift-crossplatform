# Proactive Memory & Lifecycle Investigation: Database Observation on Android

**Date:** 2026-02-22
**Investigator:** Proactive concern hunter (Claude, general-purpose agent)
**Scope:** Memory leaks, lifecycle risks, and subscription cleanup for `@FetchAll`/`@FetchOne` on Android via Skip

---

## Executive Summary

Seven distinct risks were identified. Two are **confirmed platform gaps specific to Android** (no memory-pressure relief, no `update()` subscription hookup). Three are **design-level risks** that exist on iOS too but have different failure modes on Android. Two are **non-issues** that appeared suspicious but proved safe on inspection.

---

## Observation Chain Reference Counting Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  STRONG REFERENCES (→ means "holds a strong reference to")                  │
│                                                                             │
│  SwiftUI View (struct, value type on stack)                                 │
│    → FetchAll (property wrapper, value type)                                │
│       → SharedReader (value type, contains Box)                             │
│          → Box (final class, strong)                                        │
│             → _PersistentReference<FetchKey<Value>> (final class, strong)  │
│                → FetchKey (value type stored in _PersistentReference.key)  │
│                   → DatabaseReader (protocol existential, strong ref to     │
│                                     DatabasePool or DatabaseQueue)          │
│                → SharedSubscription (value type, holds cancel closure)      │
│                   → AnyDatabaseCancellable (final class, strong)           │
│                      → cancel closure captures: GRDB observation internals  │
│                         (weak self in GRDB subscriber callbacks)            │
│                → callback closure (escaping, captures [weak self])          │
│                   → _PersistentReference (WEAK — no cycle here)            │
│                                                                             │
│  PersistentReferences (singleton, dependency-injected)                      │
│    → Weak<FetchKey<Value>> { weak _PersistentReference? }                  │
│       ↗ (weak — does NOT prevent deallocation)                             │
│                                                                             │
│  GRDB ValueObservation scheduler callback:                                  │
│    onChange: { [subscriber] newValue in subscriber.yield(value) }           │
│    → subscriber captures SharedSubscriber which captures callback           │
│       callback captures [weak self] _PersistentReference                   │
│       → NO CYCLE: GRDB holds strong ref to callback, callback holds weak   │
│         ref back to _PersistentReference                                    │
└─────────────────────────────────────────────────────────────────────────────┘

KEY LIFETIME QUESTION: When does _PersistentReference get released?
  - PersistentReferences holds only a WEAK ref
  - Box holds a STRONG ref
  - Box is owned by SharedReader (value type, stack-allocated per view render)
  - On iOS: SwiftUI State machinery keeps SharedReader (and thus Box) alive
    for the duration of the view's presence in the hierarchy
  - On Android: Skip's Compose-based DynamicProperty has different lifetime
    semantics — see RISK-2 below
```

---

## Finding 1: AnyDatabaseCancellable Has deinit-Based Auto-Cancel — SAFE

**File:** `forks/GRDB.swift/GRDB/ValueObservation/DatabaseCancellable.swift`

```swift
public final class AnyDatabaseCancellable: DatabaseCancellable {
    private let cancelMutex: Mutex<(@Sendable () -> Void)?>

    deinit {
        cancel()   // <-- automatic cancellation on deallocation
    }

    public func cancel() {
        let cancel = cancelMutex.withLock {
            let cancel = $0
            $0 = nil
            return cancel
        }
        cancel?()
    }
}
```

**Analysis:** `AnyDatabaseCancellable` calls `cancel()` in its `deinit`. The cancellable is stored inside `SharedSubscription`, which is stored as `_PersistentReference.subscription`. When `_PersistentReference` is deallocated, `subscription` is released, which triggers `AnyDatabaseCancellable.deinit`, which calls the cancel closure, which stops the GRDB observation. This chain is correct and complete — **no leak here at the GRDB level**.

**No retain cycle between GRDB observer and the cancellable:** GRDB's internal `ValueObservation` subscriber uses `[weak self]` captures in its callbacks (verified in `ValueObservation.swift` lines 581–582):
```swift
{ [weak self] error in self?.receiveCompletion(.failure(error)) },
{ [weak self] value in self?.receive(value) }
```

**Verdict:** GRDB observation cancellation is correct and does not leak.

---

## Finding 2 (RISK): `_PersistentReference` Lifetime on Android — MEDIUM-HIGH RISK

**Files:** `forks/swift-sharing/Sources/Sharing/Internal/PersistentReferences.swift`, `forks/swift-sharing/Sources/Sharing/Internal/Reference.swift`

### How the iOS lifecycle works

On iOS, `SharedReader` is a `DynamicProperty`. SwiftUI calls `update()` on every render pass:

```swift
// SharedReader.swift line 359–362
extension SharedReader: DynamicProperty {
    #if !os(Android)
    public func update() {
        box.subscribe(state: _generation)  // registers @State<Int> to drive re-renders
    }
    #endif
}
```

`box.subscribe(state:)` sets up a `swiftUICancellable` that increments a `@State<Int>` (`_generation`) on every value change — this is what keeps the view alive and subscribed. More critically, the `@State<Int>` is owned by SwiftUI's view identity graph, which keeps the `SharedReader` struct (and thus its `Box`) alive for the entire view lifetime.

### How Android is different

On Android (`#if !os(Android)` guards out `update()`), the `@State<Int>` generation counter mechanism is absent. The `SharedReader` is a plain struct passed by value during Compose recomposition. The `Box` (a class) survives recomposition as long as something holds a strong reference to it.

### The actual reference chain on Android

```
Compose recomposition:
  SwiftUI.View.body computed property evaluates
    → FetchAll (struct, re-created each recomposition in Skip's Kotlin translation)
       → SharedReader (struct, re-created)
          → Box (class — IS this the same Box across recompositions, or a new one?)
```

**Critical question:** Does Skip's translation of `@propertyWrapper` struct preserve the `Box` identity across recompositions?

**Analysis:** `SharedReader` is a value type. Each recomposition re-evaluates `body`, which re-accesses the `FetchAll` property wrapper's `sharedReader` stored property. In Skip's Kotlin translation, SwiftUI property wrappers backed by class types (`Box` is a class) are expected to maintain identity via Compose's `remember {}` mechanism. However, this depends on Skip correctly translating the `@propertyWrapper` lifecycle.

**If Skip's Compose translation does NOT keep the `Box` alive across recompositions:**
- `Box` is released
- `Box.deinit` cancels `subjectCancellable`
- `_PersistentReference` becomes weakly-referenced only (PersistentReferences holds `Weak<Key>`)
- `_PersistentReference` is deallocated
- `_PersistentReference.deinit` fires `onDeinit`, removing the key from PersistentReferences
- `subscription` (SharedSubscription holding AnyDatabaseCancellable) is released
- `AnyDatabaseCancellable.deinit` cancels the GRDB observation

**Net effect:** The observation would be cancelled and restarted on every recomposition — causing N × database reconnections per second and preventing the observation from ever delivering a stable value to the view.

**If Skip correctly preserves `Box` identity (the intended behavior):**
- The observation persists correctly across recompositions
- Values flow through the Phase 1 observation bridge as expected

**Risk level:** MEDIUM-HIGH. This requires empirical verification. The Phase 4 `@Shared` validation (referenced in 06-RESEARCH.md) uses the same mechanism, so if `@Shared` works on Android, `@FetchAll`/`@FetchOne` should too — but the database observation path has not been explicitly tested.

**Mitigation required:** Write an observation test that verifies the GRDB `ValueObservation` subscription survives multiple view recompositions without reconnecting.

---

## Finding 3 (RISK): No Explicit `DatabasePool.close()` Call — LOW-MEDIUM RISK

**File:** `forks/sqlite-data/Sources/SQLiteData/StructuredQueries+GRDB/DefaultDatabase.swift`

`defaultDatabase()` returns a `DatabasePool` stored in `@Dependency(\.defaultDatabase)`. There is no `close()` call anywhere in sqlite-data's non-CloudKit sources:

```
$ grep -rn "DatabasePool.close\|\.close()\|\.close()" forks/sqlite-data/Sources
(no matches in non-CloudKit sources)
```

**Analysis:**

`DatabasePool.deinit` closes connections automatically:
```swift
// DatabasePool.swift line 97–110
deinit {
    suspensionObservers.forEach(NotificationCenter.default.removeObserver(_:))
    NotificationCenter.default.removeObserver(self)
    readerPool = nil  // closes reader connections
    // writer closes via SerializedDatabase.deinit
}
```

The dependency-injected `DatabasePool` lives as long as `DependencyValues[DefaultDatabaseKey]` lives. In a Swift Dependencies setup with `prepareDependencies`, this is effectively the process lifetime.

**Android-specific gap:** On iOS, when the app is terminated by the OS, the process exits and ARC cleans up. On Android, the JVM may not call Swift object destructors in all termination scenarios (e.g., `Process.killProcess()`, OOM kill). In these cases, `DatabasePool.deinit` may not run, leaving WAL files dirty.

**However:** SQLite WAL mode is designed to handle unclean shutdowns — on next open, the WAL is replayed and the database is recovered automatically. This is a **data safety non-issue** for SQLite.

**The real concern:** If a test or view creates a `DatabasePool` without going through `@Dependency` and does not explicitly close it, file descriptor leaks can accumulate. `DatabasePool` opens at minimum 2 file descriptors (1 writer + 1 reader). Android has a typical per-process fd limit of 1024.

**Verdict:** Low risk for production use with a single `defaultDatabase`. Medium risk if tests create many `DatabasePool` instances and rely on `deinit` for cleanup (which may be non-deterministic in test environments).

---

## Finding 4 (CONFIRMED ANDROID GAP): No Memory Management Hook — MEDIUM RISK

**File:** `forks/GRDB.swift/GRDB/Core/DatabasePool.swift` lines 90–94, 214–263

```swift
public init(...) throws {
    // ...
    #if os(iOS)
    if configuration.automaticMemoryManagement {
        setupMemoryManagement()
    }
    #endif
}

#if os(iOS)
private func setupMemoryManagement() {
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(applicationDidReceiveMemoryWarning),
        name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    center.addObserver(self, selector: #selector(applicationDidEnterBackground),
        name: UIApplication.didEnterBackgroundNotification, object: nil)
}

private func applicationDidEnterBackground(_ notification: NSNotification) {
    // Closes reader connections to release memory when app backgrounds
    releaseMemoryEventually()
}

private func applicationDidReceiveMemoryWarning(_ notification: NSNotification) {
    releaseMemoryEventually()
}
#endif
```

**Analysis:** On iOS, GRDB automatically listens for `UIApplication.didEnterBackgroundNotification` and `UIApplication.didReceiveMemoryWarningNotification`. When the app backgrounds, GRDB calls `releaseMemoryEventually()` which closes idle reader connections to free memory.

**On Android, this entire mechanism is absent.** The `#if os(iOS)` guard compiles it out completely. Android has its own backgrounding lifecycle (Activity `onPause()`/`onStop()`) and memory callbacks (`onLowMemory()`/`onTrimMemory()`), but GRDB does not hook into them.

**Consequences:**
1. **Background memory:** Reader connections (each holding a SQLite connection with page cache) remain open indefinitely when the Android app is backgrounded. A `DatabasePool` with default `maximumReaderCount` (5) holds up to 5 reader connections, each with its own page cache.
2. **Memory pressure:** Android's `onLowMemory()` callback is never forwarded to GRDB. Under memory pressure, SQLite's page cache is not released, making the app a more likely OOM kill target.
3. **Observations keep running:** Active `ValueObservation` subscriptions continue firing in the background, performing database reads on background threads. On iOS this is also true (GRDB does not suspend observations on background, only closes idle readers), but on Android the lack of idle reader cleanup compounds the issue.

**Mitigation options (for future consideration):**
- Integrate with Android's `ComponentCallbacks2.onTrimMemory()` via JNI/Skip bridge to call `database.releaseMemory()` on memory pressure signals
- Set `configuration.maximumReaderCount = 1` for Android builds to reduce idle connection overhead
- Post `Database.suspendNotification` / `Database.resumeNotification` from Android lifecycle callbacks (GRDB already has this mechanism, it just needs wiring)

**Severity:** Medium. The app will work correctly but use more memory than necessary in the background.

---

## Finding 5 (CONFIRMED ANDROID GAP): No Suspension Mechanism Wired — LOW-MEDIUM RISK

**File:** `forks/GRDB.swift/GRDB/Core/DatabasePool.swift` lines 318–334, `Configuration.swift` line 131

```swift
// Configuration.swift
public var observesSuspensionNotifications = false  // opt-in, off by default

// DatabasePool.swift
private func setupSuspension() {
    if configuration.observesSuspensionNotifications {
        let center = NotificationCenter.default
        suspensionObservers.append(center.addObserver(
            forName: Database.suspendNotification, ...
            using: { [weak self] _ in self?.suspend() }
        ))
        // ...
    }
}
```

GRDB has a database suspension mechanism (used on iOS when the app goes to background with `UIApplication.beginBackgroundTask` patterns). Suspension prevents the database from acquiring SQLite locks that would block the OS from suspending the process.

**On Android:** `observesSuspensionNotifications` is false by default so this is not activated. There is no Android-specific code to post `Database.suspendNotification` from Android lifecycle events.

**Consequence:** When the Android app is put to background, the database may hold WAL locks that prevent the OS from fully freezing the process. This is unlikely to cause correctness issues but could contribute to battery drain if the process is not properly frozen.

**Severity:** Low. SQLite on Android has been used without suspension for years without serious consequence. The risk is theoretical battery/performance impact, not data corruption.

---

## Finding 6 (NON-ISSUE): FetchSubscription Does Not Hold Database Reference

**File:** `forks/sqlite-data/Sources/SQLiteData/FetchSubscription.swift`

```swift
public struct FetchSubscription: Sendable {
    let cancellable = LockIsolated<Task<Void, any Error>?>(nil)
    let onCancel: @Sendable () -> Void

    init<Value>(sharedReader: SharedReader<Value>) {
        onCancel = { sharedReader.projectedValue = SharedReader(value: sharedReader.wrappedValue) }
    }
```

**Analysis:** `FetchSubscription` does NOT hold a reference to the database. It holds:
1. A `LockIsolated<Task?>` — the async task waiting for cancellation
2. A closure that, when called, replaces the `SharedReader`'s reference with a plain value (disconnecting from the observation)

The closure captures `sharedReader` (a value type `SharedReader`) which contains a `Box` (class), which indirectly references `_PersistentReference`. This is a standard reference — no cycle because `FetchSubscription` is user-facing and not held by the observation chain itself.

**Verdict:** No leak risk from FetchSubscription.

---

## Finding 7 (NON-ISSUE): CloudKit UIApplication Observers Are Platform-Guarded

**File:** `forks/sqlite-data/Sources/SQLiteData/CloudKit/SyncEngine.swift` lines 278–304

```swift
// SyncEngine.swift
$0 = defaultNotificationCenter.addObserver(
    forName: UIApplication.willResignActiveNotification,
    // ...
    let taskIdentifier = UIApplication.shared.beginBackgroundTask()
```

These `UIApplication` lifecycle observers are inside `SyncEngine.swift`, which is guarded by `#if canImport(CloudKit)` at the module level. CloudKit is not available on Android, so this entire file is compiled out.

**Verdict:** No Android risk. Already correctly guarded.

---

## Finding 8: The `FetchKey.database` Strong Reference Pattern

**File:** `forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift` line 50

```swift
struct FetchKey<Value: Sendable>: SharedReaderKey {
    let database: any DatabaseReader   // STRONG reference to DatabasePool/DatabaseQueue
    // ...
}
```

`FetchKey` holds a strong reference to `DatabaseReader` (typically `DatabasePool`). `FetchKey` is stored inside `_PersistentReference.key`. The complete chain:

```
FetchAll (value type) → SharedReader (value type) → Box (class)
  → _PersistentReference (class)
     → key: FetchKey → database: DatabasePool (STRONG)
     → subscription: SharedSubscription → AnyDatabaseCancellable
```

**Analysis:** This means the `DatabasePool` is kept alive as long as `_PersistentReference` is alive, which is as long as any `SharedReader` with that key exists. This is **intentional and correct** — you do not want the database to close while observations are active.

**Potential issue:** If `prepareDependencies { $0.defaultDatabase = pool }` is called and then the app tries to swap the database (e.g., for testing), the old `_PersistentReference` instances (and their `FetchKey` with the old `DatabasePool`) continue to hold the old pool alive until they are deallocated. This is unlikely in production but could cause confusion in tests.

**Android-specific concern:** On Android, if `@FetchAll` is used without `prepareDependencies` (falling through to `DefaultDatabaseKey.testValue` which creates an in-memory `DatabaseQueue`), the view will silently use an empty database. The debug guard in `FetchKey.load()` returns `resumeReturningInitialValue()` for the default database, preventing a hang, but the user sees an empty list with no error. This is iOS behavior too, but on Android the absence of Xcode's runtime warning system means the debug message is less visible.

---

## Retain Cycle Analysis: None Found

The investigated chain has no retain cycles:

| Potential cycle | Verdict | Reason |
|----------------|---------|--------|
| GRDB observer → AnyDatabaseCancellable → GRDB observer | No cycle | GRDB subscribers use `[weak self]` captures |
| _PersistentReference → subscription → callback → _PersistentReference | No cycle | `_PersistentReference` init uses `[weak self]` in its callback closure |
| PersistentReferences → _PersistentReference | No cycle | PersistentReferences holds `Weak<Key>` (weak reference) |
| FetchKey → DatabasePool → FetchKey | No cycle | DatabasePool does not reference FetchKey |
| Box → subject publisher → Box | No cycle | PassthroughRelay does not hold back-reference to Box |

---

## Risk Summary Table

| # | Risk | Android-Specific | Severity | Likelihood | Action Required |
|---|------|-----------------|----------|-----------|-----------------|
| 1 | AnyDatabaseCancellable auto-cancel in deinit | No | — | — | None (correct by design) |
| 2 | Box/SharedReader lifetime across Skip recompositions | YES | HIGH | Medium | Write observation lifecycle test |
| 3 | No explicit DatabasePool.close() call | Partially | LOW | Low | Document; add test cleanup |
| 4 | No memory management hook on Android background | YES | MEDIUM | High | Future: wire onTrimMemory |
| 5 | No suspension mechanism on Android background | YES | LOW | Medium | Future: wire onPause/onStop |
| 6 | FetchSubscription database reference | No | — | — | None (no cycle) |
| 7 | CloudKit UIApplication observers | No | — | — | None (already guarded) |
| 8 | FetchKey strong reference to DatabasePool | No | LOW | Low | Document expected behavior |

---

## Recommended Actions for Phase 6

### Immediate (block on Phase 6 acceptance)

**A1 — Observation Lifecycle Test (addresses Risk 2)**

Write a test that:
1. Creates a `DatabaseQueue` with schema + initial data
2. Creates a `FetchKey` / starts `ValueObservation` via `subscribe()`
3. Simulates N recompositions (by re-accessing `wrappedValue` multiple times)
4. Mutates the database
5. Asserts the observation callback fires exactly once (not N times), proving the subscription was not recreated

This is the critical integration test that validates the observation bridge survives Skip's Compose lifecycle.

**A2 — Connection Count Assertion (addresses Risk 3)**

In tests that create `DatabasePool` instances, explicitly call `try pool.close()` in `tearDown()` rather than relying on `deinit`. This prevents file descriptor accumulation in long test runs on Android.

### Deferred (post-Phase 6, tracked as TODOs)

**D1 — Android Memory Pressure Integration (addresses Risk 4)**

In `skip-android-bridge`, add a JNI-exported function called from Android's `ComponentCallbacks2.onTrimMemory()` that posts a notification or calls `database.releaseMemory()`. This requires knowing which `DatabasePool` instance to target — the `@Dependency(\.defaultDatabase)` singleton is the natural target.

**D2 — Android Suspension Integration (addresses Risk 5)**

In `skip-android-bridge`, wire Android's Activity `onPause()`/`onStop()` to post `Database.suspendNotification` and `onResume()` to post `Database.resumeNotification`. This is opt-in via `configuration.observesSuspensionNotifications = true`. Only needed if WAL lock contention becomes a real problem in practice.

**D3 — maximumReaderCount for Android (addresses Risk 4 partially)**

Consider setting `configuration.maximumReaderCount = 2` (or even 1) for Android builds to reduce idle connection memory overhead. Add to `defaultDatabase()`:
```swift
#if os(Android)
configuration.maximumReaderCount = 2
#endif
```

---

## Files Investigated

| File | Key Finding |
|------|-------------|
| `forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift` | subscribe() returns SharedSubscription wrapping AnyDatabaseCancellable; FetchKey holds strong DatabaseReader ref |
| `forks/sqlite-data/Sources/SQLiteData/FetchSubscription.swift` | No database reference; cleanup via onCancel closure replacing SharedReader |
| `forks/swift-sharing/Sources/Sharing/Internal/Reference.swift` | _PersistentReference uses [weak self] in callback; subscription stored as property; deinit fires onDeinit |
| `forks/swift-sharing/Sources/Sharing/Internal/PersistentReferences.swift` | Holds WEAK ref to _PersistentReference; removed from storage on deinit |
| `forks/swift-sharing/Sources/Sharing/SharedReader.swift` | Box.deinit cancels subjectCancellable; update() guarded #if !os(Android) |
| `forks/GRDB.swift/GRDB/ValueObservation/DatabaseCancellable.swift` | AnyDatabaseCancellable.deinit calls cancel() — correct auto-cleanup |
| `forks/GRDB.swift/GRDB/ValueObservation/ValueObservation.swift` | GRDB subscriber uses [weak self] — no retain cycle |
| `forks/GRDB.swift/GRDB/Core/DatabasePool.swift` | Memory management iOS-only; suspension opt-in; deinit closes connections |
| `forks/sqlite-data/Sources/SQLiteData/StructuredQueries+GRDB/DefaultDatabase.swift` | No close() call; relies on deinit; Android path resolution correct |
| `forks/sqlite-data/Sources/SQLiteData/CloudKit/SyncEngine.swift` | UIApplication observers present but guarded by CloudKit canImport |

---

*Investigation completed: 2026-02-22*
*No retain cycles found. Two confirmed Android platform gaps (memory management, suspension). One high-priority verification needed (Box lifetime across Compose recompositions).*
