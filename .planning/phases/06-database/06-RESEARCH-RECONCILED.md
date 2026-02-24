# Phase 6 Database Research -- Reconciled Synthesis

**Reconciliation date:** 2026-02-22
**Source reports:** 8 deep-dive (R2-R8, P4, P6) + 5 proactive + 1 baseline + 1 context
**R1 status:** Timed out -- SQLite header findings synthesised from R4, R8, baseline, and PROACTIVE-package-wiring

---

## Executive Summary

Phase 6 brings three database forks (GRDB.swift, swift-structured-queries, sqlite-data) into the cross-platform build. Research across 14 deep-dive reports and 5 proactive investigations converges on a strong overall verdict: **the database stack is fundamentally Android-compatible, with most prior fork work already complete and correct.** The query-building layer (StructuredQueries) is pure Swift with zero platform risk. GRDB's concurrency model uses only libdispatch primitives available on Android. The observation chain from GRDB ValueObservation through SharedReader to Compose recomposition follows the same path validated for `@Shared` in Phase 4.

Three categories of issues emerged. First, **package wiring is the most immediate blocker**: sqlite-data's Package.swift references non-existent `flote/service-app` branches on `jacobcxdev` GitHub, and SPM identity conflicts between local-path and remote-URL references for shared dependencies must be resolved before any code compiles (PROACTIVE-package-wiring W1-W4). Second, **the observation chain has a nuanced but likely-safe gap**: `_PersistentReference` uses the stdlib `ObservationRegistrar` rather than the Phase 1 bridge's custom registrar, so the bridge's record-replay mechanism does not capture `@FetchAll`/`@FetchOne` reads (R2 Gap 1). However, P4's deep-dive raises confidence to HIGH that `StateTracking.pushBody()`/`popBody()` in SkipUI establishes a stdlib `withObservationTracking` scope that captures these reads -- the identical mechanism that makes `@Shared` work in Phase 4. Third, **threading risks exist but are manageable**: the private `ImmediateScheduler` in FetchKey delivers callbacks synchronously on GRDB's reduce queue, creating re-entrancy risk on Android's non-Combine path (PROACTIVE-threading-deadlocks Finding 7), and GRDB's `Pool.get()` can block threads via `DispatchSemaphore.wait()` which is more dangerous on Android's constrained thread pools.

Confidence is HIGH for 6 of 8 research items, with the observation chain at HIGH (revised up from MEDIUM-HIGH after P4 deep-dive) and threading at MEDIUM (several latent risks requiring stress testing). No fundamental architectural changes are needed. The primary work is mechanical: fix branch references, wire Package.swift, write validation tests, and run `make android-build` to confirm SQLite linking.

---

## Blockers (Must Fix Before or During Phase 6)

| ID | Severity | Description | Source | Recommended Fix |
|----|----------|-------------|--------|-----------------|
| B1 | CRITICAL | sqlite-data Package.swift references `branch: "flote/service-app"` for 5 deps; these branches do not exist on `jacobcxdev` GitHub. `flote-works` org returns 404. Standalone `swift build` in `forks/sqlite-data/` fails. | P6 | Change all 5 branch refs to `branch: "dev/swift-crossplatform"`. Run `swift package resolve` to regenerate Package.resolved. |
| B2 | CRITICAL | SPM identity conflicts: sqlite-data references GRDB, swift-structured-queries, swift-sharing, swift-perception, swift-dependencies, swift-custom-dump, xctest-dynamic-overlay via remote URLs; fuse-library has them as local paths. Duplicate package identity errors on `swift package resolve`. | PROACTIVE-package-wiring W1-W4 | Add all 4 database forks as local-path deps in fuse-library. SPM's local-path override (by package name identity) should suppress remote resolution. Verify with `swift package resolve` before writing any tests. |
| B3 | HIGH | swift-snapshot-testing may need to be added to fuse-library Package.swift for transitive resolution even though no test target uses it, or may cause Skip sandbox rejection if added without a target dependency. | PROACTIVE-package-wiring W9, PROACTIVE-skip-test-parity Finding 4 | Determine whether `swift-snapshot-testing` is needed. If yes, add as local path with a nominal target dependency. If no (SQLiteData product does not depend on it), omit entirely. |
| B4 | HIGH | `make android-build` must succeed after wiring database forks. `GRDBSQLite` and `_StructuredQueriesSQLite3` both declare `.systemLibrary` linking `libsqlite3`. If Swift Android SDK sysroot does not include `libsqlite3.so`, linker fails. | PROACTIVE-skip-test-parity Finding 3, PROACTIVE-package-wiring W6 | Run `make android-build` immediately after wiring forks (Wave 1). If linker fails, investigate SDK sysroot or vendor CSQLite. |
| B5 | MEDIUM | sqlite-data's transitive deps (swift-dependencies, swift-sharing) also reference `flote/service-app` in their own Package.swift for combine-schedulers, swift-clocks. These fail standalone but are overridden by fuse-library's local paths. | P6 Section 5 | Fix transitive refs in swift-dependencies and swift-sharing Package.swift for cleanliness. Not blocking for fuse-library builds but blocking for standalone fork builds. |

---

## Confirmed Findings by Topic

### SQLite C Library (R1/R4/R8)

R1 timed out, but R4 (prior work audit) and R8 (Combine paths) provide full coverage of the SQLite header situation.

**Both GRDB and swift-structured-queries vendor their own `sqlite3.h` headers for Android.** GRDB's `shim.h` uses `#if defined(__ANDROID__)` to include the local vendored header (SQLite 3.46.1, ~13,425 lines). swift-structured-queries changed `_StructuredQueriesSQLite3.h` from `#include <sqlite3.h>` to `#include "sqlite3.h"` to use its local vendored copy (SQLite 3.51.2, ~13,968 lines). Both `module.modulemap` files use `link "sqlite3"` which resolves to the system/SDK-provided `libsqlite3.so` at link time.

**No duplicate symbol risk.** Both link against the same runtime library. The vendored headers are compile-time only. Header version mismatch (3.46.1 vs 3.51.2) is acceptable because sqlite-data already bridges both modules successfully on macOS. The key remaining question is whether `libsqlite3.so` exists in the Swift Android SDK sysroot (see B4).

**Confidence:** HIGH for compilation. MEDIUM for Android linking (unverified until `make android-build`).

### Observation Chain (R2/P4)

R2 provides the most detailed finding in the entire research corpus: a full six-layer trace of the observation chain from `@FetchAll` through GRDB ValueObservation, SharedReader, _PersistentReference, PerceptionRegistrar, to Compose recomposition.

**The chain has six layers:**
1. Property wrappers (`FetchAll`/`FetchOne`/`Fetch`) hold a `SharedReader` and delegate everything to it.
2. `FetchKey` (a `SharedReaderKey`) establishes GRDB `ValueObservation`. On Android (no Combine), uses `ValueObservation.start(in:scheduling:onError:onChange:)` callback API.
3. `SharedReader`/`_PersistentReference` receives values via `subscriber.yield()`. The `wrappedValue` setter calls `withMutation` which hop-dispatches to `DispatchQueue.main.async` when called from a background thread.
4. `PerceptionRegistrar` on Android delegates to native `ObservationRegistrar` (from `libswiftObservation.so`).
5. Phase 1 bridge's `ObservationRecording` record-replay mechanism.
6. Skip's `View.Evaluate()` calls `ViewObservation.startRecording`/`stopAndObserve`.

**R2 identifies a critical gap (Gap 1):** `_PersistentReference` uses the native stdlib `ObservationRegistrar`, NOT the bridge's custom `ObservationRegistrar`. The bridge's `recordAccess` is never called for `@FetchAll` reads. `stopAndObserve()` bails early because `replayClosures` is empty.

**P4 resolves this gap with HIGH confidence:** The saving grace is `StateTracking.pushBody()`/`popBody()` in SkipUI, which wraps body evaluation. P4 demonstrates that `_PersistentReference`'s stdlib `ObservationRegistrar.access()` is captured by whatever `withObservationTracking` scope `StateTracking` establishes. This is the same mechanism that makes `@Shared` work in Phase 4 (50 tests passing, including 9 SharedObservation tests). The observation path through `_PersistentReference` -> `PerceptionRegistrar` -> stdlib `ObservationRegistrar` is identical for `@Shared` and `@FetchAll`.

**DynamicProperty.update() is correctly excluded on Android.** Skip's `DynamicProperty.swift` has the entire protocol definition commented out. Skip never calls `update()`. The subscription is established at init time in `_PersistentReference.init`, not at `update()` time. This is architecturally correct.

**Confidence:** HIGH (revised up from MEDIUM-HIGH).

### GRDB Concurrency (R3)

R3 provides an exhaustive audit of GRDB's concurrency primitives:

- **`DispatchQueueActor`/`DispatchQueueExecutor`:** Uses `DispatchQueue.async` and custom `SerialExecutor`. The `#if os(Linux) || os(Android)` guard for `@unchecked Sendable` is already in place.
- **`SerializedDatabase`:** Central connection serializer using both `DispatchQueue.sync` (sync path) and `DispatchQueueActor.execute` (async path). SQLite threading mode set to `.multiThread` (GRDB's serial queue provides all needed serialization).
- **`DatabasePool`:** Writer on its own serial queue, reader pool of up to N concurrent readers each on their own serial queue. Pool managed via `DispatchSemaphore`. iOS-only memory management (`UIApplicationDidReceiveMemoryWarningNotification`) is `#if os(iOS)` guarded.
- **`DatabaseQueue`:** Single `SerializedDatabase` for both reads and writes. No Android concerns.
- **Locking:** All via `NSLock` (Foundation, available on Android via pthread), `DispatchQueue.sync` with `.barrier`, `DispatchSemaphore`, `DispatchGroup`. No `os_unfair_lock`, no `pthread_rwlock`, no Darwin-exclusive primitives.
- **Change detection:** SQLite hooks (`sqlite3_update_hook`, `sqlite3_commit_hook`, `sqlite3_rollback_hook`). No `DispatchSource`, no file system monitoring.
- **`SQLITE_ENABLE_SNAPSHOT`:** Unavailable on Android. Falls back to secondary writer-queue fetch on observation start, causing documented double initial notification. Recommend `.removeDuplicates()`.
- **WAL mode:** Uses `FileManager.fileExists` and `URL.resourceValues(forKeys: [.fileSizeKey])` for WAL priming. Should work on Android but unvalidated.

**Notable finding:** `UUID` as `DatabaseValueConvertible` may be incorrectly excluded on Android. The guard `#if !os(Linux) && !os(Windows) && !os(Android)` in `UUID.swift` excludes Swift's `UUID` (a pure Swift value type available on Android). Only `NSUUID` needs exclusion. This may be fixable with `#if canImport(ObjectiveC)`.

**Confidence:** HIGH.

### Prior Work Completeness (R4)

R4 audited all ~26 changed files across three forks:

- **GRDB.swift:** 11 files changed (1 commit `36dba72`). All Android conditionals correct and complete. No TODOs from Android work.
- **swift-structured-queries:** 3 files changed (1 commit `fb5cc61`). Package.swift fix for `#if !canImport(Darwin)` guard (which evaluated on host, not target). Vendored header present. Complete.
- **sqlite-data:** ~12 files changed across 8 commits. DynamicProperty `update()` intentionally guarded on Android. AndroidParityTests with 12 tests (6 CRUD + 6 DynamicProperty). Package.swift has Android conditional deps. Went through 4 revision cycles before landing in correct state.

**Remaining gaps in sqlite-data:**
1. Package.swift branch references stale (`flote/service-app`) -- see B1
2. No StructuredQueries-based tests yet (existing tests use raw SQL)
3. No observation/FetchKey tests yet (existing tests are CRUD-only)

**Confidence:** HIGH for compilation correctness. Runtime behavior unverified on Android.

### File Paths (R5)

`defaultDatabase()` uses `FileManager.default.url(for: .applicationSupportDirectory, ...)`. On Android, skip-android-bridge bootstraps `XDG_DATA_HOME` -> Android `filesDir`, so `FileManager` resolves `.applicationSupportDirectory` correctly. This was validated in Phase 4 for `FileStorageKey`.

**The `absoluteString` bug:** `DefaultDatabase.swift` line 32 uses `.absoluteString` instead of `.path`. This returns a `file://` URI which SQLite accepts (URI filenames since 3.7.7). Benign but not canonical. Out of scope for Phase 6.

**Android concrete path:** `/data/user/0/<package>/files/Application Support/SQLiteData.db` with WAL sidecars in the same directory. Internal storage is always writable, no permissions needed, survives app updates, cleared on uninstall.

**Confidence:** HIGH. No changes needed to `DefaultDatabase.swift`.

### Test Patterns (R6)

R6 provides the most comprehensive test strategy document, with concrete test examples for all 27 requirements.

**Key decisions:**
- Use `DatabaseQueue()` (no arguments = in-memory) for all tests. Zero file I/O, isolated per test.
- Do NOT depend on `StructuredQueriesTestSupport` or `SQLiteDataTestSupport`. Keep test targets lightweight.
- Use standard `XCTAssertEqual` assertions. No `InlineSnapshotTesting`, no swift-testing.
- Two test targets: `StructuredQueriesTests` (SQL-01..SQL-15) and `SQLiteDataTests` (SD-01..SD-12).
- SQL string verification via `query.queryFragment.sql` for direct string comparison.
- Observation tests use `withDependencies { $0.defaultDatabase = db }` + `await $wrapper.load()`.
- Schema: two-table (`items` + `categories` with foreign key) covers all 27 requirements.
- ~40 test functions across 12 files.

**Database test targets are macOS-only** (`swift test` only). They do not have the skipstone plugin and do not run under `skip test`. This is consistent with Phases 2-5.

**Confidence:** HIGH.

### Perception Usage (R7)

sqlite-data imports `Perception` in exactly ONE file: `FetchSubscription.swift`. It uses `LockIsolated`, which actually comes from `ConcurrencyExtras` (a peer dependency), not from Perception. The `import Perception` is effectively misleading.

sqlite-data does NOT use `@Perceptible`, `PerceptionRegistrar`, or `withPerceptionTracking` directly. All Perception observation machinery is used transitively through swift-sharing's `_PersistentReference` (which conforms to both `Observable` and `Perceptible`).

The Phase 1 Android passthrough in `forks/swift-perception` correctly gates all incompatible code behind `#if !os(Android)`. On Android, `PerceptionRegistrar` delegates to native `ObservationRegistrar`.

CloudKit code (which has extensive `LockIsolated` usage) is entirely excluded on Android via `#if canImport(CloudKit)`.

**Confidence:** HIGH.

### Combine vs Callback (R8)

`FetchKey.subscribe()` has an explicit `#if canImport(Combine)` / `#else` branch:
- **Apple platforms:** `observation.publisher(in:scheduling:)` -> Combine sink
- **Android:** `observation.start(in:scheduling:onError:onChange:)` -> callback-based

The callback path is the canonical GRDB observation API that underpins the Combine publisher. The Combine publisher is implemented as a thin wrapper over `start()`. The callback path is complete, production-ready, and semantically equivalent.

**Missing `dropFirst` on Android:** The Combine path implements `dropFirst` for `.userInitiated` context (skipping the redundant first emission after an explicit `load()`). The callback path does not. This may cause one redundant but harmless `SharedReader` update. Low risk.

**OpenCombine is present transitively** (via `combine-schedulers`) but imported as `OpenCombineShim`, not `Combine`. `canImport(Combine)` correctly evaluates to false on Android.

**`AsyncValueObservation`** (`observation.values(in:)`) is available on Android and provides an `AsyncSequence` interface. Not currently used by sqlite-data but available for future use.

**Confidence:** HIGH.

### SharedReader.update() on Android (P4)

P4 is the deepest investigation, tracing the exact mechanism by which observation works without `DynamicProperty.update()`.

**Key findings:**
1. `update()` is a pre-iOS 17 fallback only. On iOS 17+, `subscribe(state:)` is a no-op via `guard #unavailable(iOS 17, ...)`.
2. Subscription is established at init time in `_PersistentReference.init`, not at `update()` time. `key.subscribe()` installs the GRDB `ValueObservation` during initialization.
3. Skip's `DynamicProperty.swift` has the entire protocol commented out. Skip never calls `update()`.
4. The saving grace for Compose recomposition is `StateTracking.pushBody()`/`popBody()`, which likely establishes a stdlib `withObservationTracking` scope during body evaluation. This captures `_PersistentReference.access()` calls.
5. `@Shared` uses the identical mechanism and was validated with 50 tests in Phase 4.

**Two notification channels active on Android:**
- **Channel A (primary):** Stdlib `withObservationTracking` via `StateTracking` captures `_PersistentReference.access()` reads and fires `onChange` on mutation.
- **Channel C (fundamental):** GRDB `ValueObservation` -> `subscriber.yield()` -> `_PersistentReference.wrappedValue` setter -> stdlib `ObservationRegistrar.willSet()`/`didSet()` -> any active `withObservationTracking` observer.

**Confidence:** HIGH (revised up from MEDIUM-HIGH).

### Branch Divergence (P6)

sqlite-data's Package.swift references `flote/service-app` branches on `jacobcxdev` forks. These branches do not exist on `jacobcxdev` GitHub. The `flote-works` org returns HTTP 404.

**For all 5 affected dependencies:**
- GRDB.swift: `dev/swift-crossplatform` is identical tip to `flote-works/flote/service-app`
- swift-dependencies: `dev/swift-crossplatform` is 1 commit ahead (URL rename)
- swift-perception: identical tip
- swift-sharing: 2 commits ahead (URL rename + FileStorageKey Android feature)
- swift-structured-queries: 1 commit ahead (URL rename)

`dev/swift-crossplatform` is strictly ahead in all cases. No content is lost by switching branch references. This is blocking for standalone sqlite-data builds and must be fixed at Phase 6 start.

---

## Proactive Concerns

### Package.swift Wiring (PROACTIVE-package-wiring)

12 findings (W1-W12), 4 of which are BLOCKERS:

| ID | Severity | Finding |
|----|----------|---------|
| W1 | BLOCKER | sqlite-data GRDB remote URL vs fuse-library local path -- SPM identity conflict |
| W2 | BLOCKER | sqlite-data references 6 shared deps via remote URLs that fuse-library has as local paths |
| W3 | BLOCKER | swift-structured-queries references swift-case-paths via pointfreeco URL; fuse-library has local path |
| W4 | BLOCKER | sqlite-data references swift-structured-queries via remote URL; fuse-library will have local path |
| W5 | WARNING | swift-structured-queries swift-dependencies version range vs local fork |
| W6 | WARNING | Two independent SQLite `.systemLibrary` targets both link `libsqlite3` |
| W7 | WARNING | swift-syntax version ranges compatible (all include 602.0.0) but sensitive to upgrades |
| W8 | WARNING | `TARGET_OS_ANDROID` env var pattern in sqlite-data -- same as TCA, known to work |
| W9 | INFO | swift-snapshot-testing transitive resolution needs clarification |
| W10 | INFO | swift-tagged, swift-concurrency-extras are net-new transitive deps (safe) |
| W11 | INFO | `StructuredQueriesCasePaths` trait not enabled by default (safe) |
| W12 | INFO | Skip sandbox ignores unused deps (safe, intentional) |

**Resolution strategy:** SPM's local-path override by package name identity should resolve W1-W4 automatically when all database forks are added as local paths in fuse-library. Must verify with `swift package resolve` before proceeding.

### Skip Test Parity (PROACTIVE-skip-test-parity)

**`skip test` will NOT run database tests.** This is expected behavior, not a gap. Database tests use raw Swift APIs (DatabaseQueue, GRDB closures) that are not part of the JNI-bridged surface. The project's established convention from Phases 2-5 is that only `FuseLibraryTests` (with skipstone plugin) runs under `skip test`.

Database validation on Android requires `make android-build` (compilation) and potentially `skip android test` (runtime on emulator/device), not `skip test` (Robolectric parity).

**Key actionable finding:** `swift-snapshot-testing` may not need to be in fuse-library's Package.swift. If `SQLiteData` product does not depend on it (only `SQLiteDataTestSupport` does), it can be omitted.

### Migration System (PROACTIVE-migration-system)

**Platform neutrality: CONFIRMED.** `DatabaseMigrator` stores state in a `grdb_migrations` SQLite table. No `UserDefaults`, no Keychain, no plist. Migration code has zero platform conditionals. Each migration runs inside an explicit SQLite transaction with atomic rollback. Pure SQLite semantics.

**One latent risk:** `hasSchemaChanges()` (triggered by `eraseDatabaseOnSchemaChange = true`) creates a temp database via `NSTemporaryDirectory()`. On Android, this may return `/tmp` rather than the app's sandboxed temp directory. This is a debug-only feature and should not be used in production.

**StructuredQueries has no migration system.** Schema creation inside `registerMigration` closures must be done manually with raw DDL. No automatic schema-from-struct generation.

### Threading & Deadlocks (PROACTIVE-threading-deadlocks)

11 findings, 3 HIGH, 6 MEDIUM, 2 LOW:

| # | Severity | Finding | Mitigation |
|---|----------|---------|------------|
| 1 | HIGH | `ImmediateValueObservationScheduler` fatal-errors if not on main thread. FetchKey's private `ImmediateScheduler` delivers synchronously on reduce queue without checking. | FetchKey uses its own `ImmediateScheduler` (no fatal), not GRDB's `.immediate`. Safe for current usage. Audit any custom scheduling calls. |
| 2 | HIGH | `Pool.get()` blocks via `DispatchSemaphore.wait()`. Deadlocks if reader pool full during barrier write. | Documented GRDB constraint: use `asyncRead` not `read` from within writes. Write stress test to validate. |
| 3 | HIGH | `DispatchQueue.main.async` used as scheduler default. Depends on Skip's main queue fidelity. | Skip maps `DispatchQueue.main` to Android main thread via libdispatch. Functionally correct but timing may differ. |
| 5 | MEDIUM | `syncStart` calls `reduceQueue.sync` while holding writer connection. Main thread blocked. | Only triggers with `ImmediateValueObservationScheduler` (not FetchKey's `ImmediateScheduler`). |
| 7 | MEDIUM | TCA Effect -> DB write -> `ImmediateScheduler` -> synchronous `subscriber.yield` on reduceQueue: re-entrancy risk on non-Combine path. | `subscriber.yield` sets `_PersistentReference.wrappedValue` which uses `lock.withLock`. No re-entrant GRDB call in this path. |
| 8 | MEDIUM | `DispatchQueueExecutor.checkIsolated` uses `dispatchPrecondition`. Android libdispatch fidelity unverified. | Validate with stress test. |
| 9 | MEDIUM | `Pool.barrier` async variant calls `itemsGroup.wait()` inside actor. Thread starvation risk. | Under normal use (few concurrent reads), not triggered. Stress test recommended. |

**No deadlock in the standard TCA + GRDB flow.** GRDB explicitly breaks writer queue ownership via `reduceQueue.async` before calling user code. The one scenario that would deadlock (synchronous `db.write` from within an observation callback) is prevented by always using async write APIs.

### Memory & Lifecycle (PROACTIVE-memory-lifecycle)

7 findings, 1 HIGH (requires verification), 2 confirmed Android gaps:

**Risk 2 (HIGH -- requires verification):** Box/SharedReader lifetime across Skip Compose recompositions. If Skip does not preserve `Box` identity across recompositions, the observation would be cancelled and restarted on every recompose. However, `@Shared` (same mechanism) works in Phase 4, so Box identity is preserved. Write an observation lifecycle test to confirm.

**Risk 4 (MEDIUM -- confirmed Android gap):** No memory management hook on Android. GRDB's iOS memory pressure handling (`UIApplication.didReceiveMemoryWarningNotification`) is `#if os(iOS)` guarded. On Android, reader connections remain open indefinitely when backgrounded. Future mitigation: wire Android's `onTrimMemory()` to call `database.releaseMemory()`.

**Risk 5 (LOW-MEDIUM -- confirmed Android gap):** No database suspension mechanism wired on Android. `observesSuspensionNotifications` is false by default. Future mitigation: wire `onPause()`/`onStop()` to post `Database.suspendNotification`.

**No retain cycles found.** GRDB subscribers use `[weak self]`. `_PersistentReference` callback uses `[weak self]`. `PersistentReferences` holds `Weak<Key>`. `AnyDatabaseCancellable.deinit` calls `cancel()` correctly.

---

## Disagreements Between Reports

### 1. Observation Chain Gap Severity

**R2** identifies Gap 1 as CRITICAL with "UNCERTAIN" confidence for Compose recomposition firing after database writes. R2's confidence table shows "MEDIUM-LOW" for `withObservationTracking` subscription establishment and "LOW" for record-replay capturing `_PersistentReference.access`.

**P4** revises confidence to HIGH, arguing that `StateTracking.pushBody()`/`popBody()` establishes a stdlib `withObservationTracking` scope that captures `_PersistentReference` reads. P4 bases this on: (a) `@Shared` uses the identical mechanism and has 50 passing tests; (b) Skip's DynamicProperty is commented out, confirming `update()` is never called; (c) subscription is init-time, not update-time.

**Reconciliation:** P4's analysis is more complete and accounts for the `StateTracking` mechanism that R2 flagged as "the critical question" but did not fully resolve. The revised HIGH confidence is warranted, with the caveat that `StateTracking` internals are opaque (SkipModel code, not in this repo's forks). The inference from `@Shared` working is strong but indirect.

### 2. `absoluteString` Bug Severity

**PROACTIVE-migration-system** flags `FileManager.url(for: .applicationSupportDirectory)` as HIGH risk on Android. **R5** (the dedicated file paths investigation) confirms this API works correctly on Android via XDG bootstrap and rates it as "no changes needed." **Baseline research** agrees with R5.

**Reconciliation:** R5 is correct. PROACTIVE-migration-system was written without awareness of the XDG bootstrap chain in skip-android-bridge. The `applicationSupportDirectory` path resolves correctly. The `absoluteString` bug is benign (SQLite accepts URI filenames).

### 3. `NSTemporaryDirectory()` on Android

**PROACTIVE-migration-system** rates this as MEDIUM risk. **R5** confirms `NSTemporaryDirectory()` works on Android via Foundation (maps to `getCacheDir()` + `/tmp/` or system temp). **PROACTIVE-skip-test-parity** confirms in-memory `DatabaseQueue()` is the correct pattern for tests (avoiding file paths entirely).

**Reconciliation:** Not a practical risk for Phase 6. Tests use `DatabaseQueue()` (in-memory). `NSTemporaryDirectory()` is only used by `defaultDatabase()` in test/preview contexts, which our tests bypass.

### 4. `UUID` DatabaseValueConvertible Exclusion

**R3** identifies the guard `#if !os(Linux) && !os(Windows) && !os(Android)` in `UUID.swift` as potentially overly broad, since Swift's `UUID` (not `NSUUID`) should be available on Android. **R4** reports the guard as "Complete" and correct.

**Reconciliation:** R4 verified the file-level guard is consistent and compiles correctly but did not assess whether the guard is overly broad. R3's analysis is more nuanced. The `UUID` conformance IS available on a separate line (line 51-103, unguarded in R4's analysis). The guarded-out code is for `NSUUID` specifically. Both reports agree the current state works correctly for app code using Swift's `UUID` type.

---

## Updated Confidence Matrix

| Topic | Initial Confidence | Updated Confidence | Change Reason |
|-------|-------------------|-------------------|---------------|
| SQLite C Library (R1) | HIGH (baseline) | HIGH (compilation) / MEDIUM (Android linking) | R4 confirms vendored headers complete; Android linking unverified |
| Observation Chain (R2) | UNCERTAIN (R2) | HIGH (P4) | P4 traces StateTracking path; @Shared analogy validated by Phase 4 tests |
| GRDB Concurrency (R3) | HIGH (baseline) | HIGH | R3 audit confirms all primitives Android-compatible |
| Prior Work (R4) | HIGH (baseline) | HIGH | R4 verifies 26 files, all correct |
| File Paths (R5) | HIGH (baseline) | HIGH | R5 traces full XDG chain, confirmed by Phase 4 |
| Test Patterns (R6) | HIGH (baseline) | HIGH | R6 provides concrete examples for all 27 requirements |
| Perception Usage (R7) | HIGH (baseline) | HIGH | R7 confirms minimal Perception usage, all Android-safe |
| Combine/Callback (R8) | HIGH (baseline) | HIGH | R8 confirms callback path is canonical GRDB API |
| SharedReader.update() (P4) | MEDIUM-HIGH (baseline) | HIGH (P4) | P4 traces init-time subscription, confirms Skip DynamicProperty is no-op |
| Branch Divergence (P6) | N/A | BLOCKER | P6 discovers non-existent branches on GitHub |
| Package Wiring | N/A | BLOCKER (W1-W4) | PROACTIVE-package-wiring discovers SPM identity conflicts |
| Threading | N/A | MEDIUM | PROACTIVE-threading finds latent risks requiring stress testing |
| Memory/Lifecycle | N/A | MEDIUM | PROACTIVE-memory finds 2 confirmed Android gaps (deferred) |
| Migration System | N/A | HIGH | PROACTIVE-migration confirms platform neutrality |
| Skip Test Parity | N/A | HIGH (expected behavior) | PROACTIVE-skip-test-parity confirms database tests are macOS-only by design |

---

## Gaps Remaining

### What R1 Would Have Answered

R1 (SQLite C Library on Android) timed out. The following questions are partially answered by other reports but would have been definitively resolved by R1:

1. **Does the Swift Android SDK sysroot include `libsqlite3.so`?** R4 and baseline research assume yes (citing existing AndroidParityTests as evidence). PROACTIVE-package-wiring W6 and PROACTIVE-skip-test-parity Finding 3 flag this as unverified. **Resolution:** Run `make android-build` as the first Wave 1 step. If it fails, the fix is either a Gradle dependency or vendoring CSQLite.

2. **Does skip-sql (if in the dependency graph) vendor its own SQLite?** If skip-sql is brought in transitively via skip-fuse or skip-foundation, there could be three providers of `sqlite3_*` symbols. **Resolution:** Check the fuse-library dependency graph for skip-sql after wiring database forks.

3. **Exact behavior of `link "sqlite3"` in `.systemLibrary` targets on Android.** Do both `GRDBSQLite` and `_StructuredQueriesSQLite3` resolve to the same `.so`, or does the linker complain about duplicate link directives? **Resolution:** Answered by `make android-build`.

### Other Unresolved Items

4. **StateTracking internals are opaque.** `StateTracking.pushBody()`/`popBody()` are in `SkipModel` (not in this repo's forks). The claim that `StateTracking` establishes a stdlib `withObservationTracking` scope is inferred from `@Shared` working, not directly verified. A test that calls `withObservationTracking` on a `_PersistentReference` and verifies `onChange` fires would close this gap at the macOS level.

5. **`DispatchQueue.main` fidelity on Android.** Skip maps `DispatchQueue.main` to Android's main Looper. Timing differences (e.g., requiring a JVM frame to drain the message queue) could cause subtle observation delivery timing differences vs iOS. Not a correctness issue.

6. **Missing `dropFirst` on Android callback path.** `FetchKey.subscribe()` non-Combine path does not implement `dropFirst` for `.userInitiated` context. This may cause one redundant `SharedReader` update after explicit `load()` calls. Low risk.

---

## Recommendations for Planning

Ordered by priority. The planner should incorporate these into the Phase 6 plan.

1. **Wave 1, Step 1 (BLOCKING): Fix sqlite-data branch references.** Change all 5 `branch: "flote/service-app"` to `branch: "dev/swift-crossplatform"` in `forks/sqlite-data/Package.swift`. Run `swift package resolve` to regenerate Package.resolved. Commit both files.

2. **Wave 1, Step 2 (BLOCKING): Wire all 4 database forks into fuse-library Package.swift.** Add as local paths: GRDB.swift, swift-structured-queries, sqlite-data. Determine if swift-snapshot-testing is needed (check if `SQLiteData` product has a transitive dependency on it). Run `swift package resolve` to verify no SPM identity conflicts.

3. **Wave 1, Step 3 (BLOCKING): Run `make android-build`.** This validates SQLite linking on Android. If it fails, debug before proceeding to test writing.

4. **Wave 1, Step 4: Run `make test` and `make skip-test`.** Verify existing tests still pass with the new forks wired in. No new test code yet.

5. **Wave 2: Write StructuredQueriesTests (SQL-01..SQL-15).** ~20 test functions. Pure query building and execution against in-memory `DatabaseQueue()`. No observation, no DynamicProperty.

6. **Wave 3: Write SQLiteDataTests (SD-01..SD-12).** ~20 test functions. Database lifecycle, migrations, CRUD, observation. Observation tests use `withDependencies` + `await $wrapper.load()`.

7. **Wave 3, critical test: Observation without `update()`.** Write a test that verifies `withObservationTracking` on a `_PersistentReference` fires `onChange` on database mutation. This validates the "saving grace" hypothesis at the macOS level.

8. **Deferred (post-Phase 6):** Wire Android memory pressure (`onTrimMemory()` -> `database.releaseMemory()`). Wire Android lifecycle (`onPause()`/`onStop()` -> `Database.suspendNotification`). Consider `configuration.maximumReaderCount = 2` for Android. Fix `absoluteString` -> `.path(percentEncoded: false)` in `DefaultDatabase.swift`.

9. **Do NOT enable** `SQLiteDataTagged` trait or `StructuredQueriesCasePaths` trait. Keep `swift-tagged` out of the dependency graph.

10. **Do NOT use** `eraseDatabaseOnSchemaChange` in production Android builds (`NSTemporaryDirectory()` path uncertainty).

11. **Do NOT add** database tests to `FuseLibraryTests` (skipstone target). Database tests are macOS-only via `swift test`, consistent with Phases 2-5.

12. **Document** that `Decimal` columns must use `String` or `Double` on Android (GRDB's `Decimal` conformance is fully excluded).

---

*Reconciliation completed: 2026-02-22*
*All 14 deep-dive reports + 5 proactive reports + 1 baseline + 1 context read in full*
*Total source material: ~5,800 lines across 16 documents*
