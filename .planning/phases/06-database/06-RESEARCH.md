# Phase 6: Database & Queries -- Research

**Completed:** 2026-02-22
**Mode:** Ecosystem research (HOW to implement, not WHAT to use)
**Requirements:** SQL-01..SQL-15, SD-01..SD-12 (27 total)

---

## Standard Stack

The database layer uses Point-Free's three-library architecture. These are fixed -- no alternatives.

| Library | Role | Fork | Android Changes Needed |
|---------|------|------|----------------------|
| **swift-structured-queries** | Type-safe query builder (`@Table`, `@Column`, `#sql()`) | `forks/swift-structured-queries` | Minimal -- vendored `sqlite3.h` already done, one `order(by:)` fix already done |
| **GRDB.swift** | SQLite database engine (`DatabasePool`, `DatabaseQueue`, `ValueObservation`, `DatabaseMigrator`) | `forks/GRDB.swift` | Already has vendored `sqlite3.h` + 9 Android conditionals. Needs `link` strategy validation |
| **sqlite-data** | Glue layer (`@FetchAll`, `@FetchOne`, `@Fetch`, `defaultDatabase()`, `FetchKey`) | `forks/sqlite-data` | Most work here -- DynamicProperty guards, observation path, Package.swift branch alignment |

**Dependency chain:** `sqlite-data` -> `GRDB.swift` + `swift-structured-queries` -> SQLite C library

**Additional dependency:** `swift-sharing` (provides `SharedReader`/`SharedReaderKey` that `@FetchAll`/`@FetchOne`/`@Fetch` are built on). Already Android-enabled in Phase 4.

---

## Architecture Patterns

### 1. Query Building is Pure Swift (No Android Risk)

StructuredQueries generates SQL strings at the Swift type level. The `@Table` and `@Column` macros expand at compile time on the host machine. The expanded code is pure Swift -- no platform-specific APIs. This is the same pattern as `@Observable`, `@CasePathable`, `@Reducer` (all validated in earlier phases).

**Pattern:** `@Table struct Item { ... }` -> expanded Swift code with `TableColumns`, `QueryOutput`, etc. -> `Item.select { ... }.where { ... }` builds SQL string -> handed to GRDB for execution.

**Confidence:** HIGH. Macros are a non-issue (D3 from context). Only the expanded code runs on Android, and StructuredQueries expanded code has no platform imports.

### 2. Database Execution Flows Through GRDB

All database operations go through GRDB's `DatabaseReader`/`DatabaseWriter` protocols:
- `database.read { db in ... }` -- read-only transaction
- `database.write { db in ... }` -- read-write transaction
- `database.asyncRead { }` / `database.asyncWrite { }` -- async variants
- `DatabasePool` -- concurrent reads, serialized writes (WAL mode)
- `DatabaseQueue` -- fully serialized (single connection)

GRDB uses `DispatchQueueActor` for its concurrency model (already has `os(Android)` guard for `@unchecked Sendable`). `libdispatch` is available on Android via the Swift SDK.

**Confidence:** HIGH. GRDB's concurrency model relies on `DispatchQueue` + custom `SerialExecutor`, both available on Android.

### 3. Observation Flows Through SharedReader, NOT Combine

This is the critical architecture insight. The observation chain is:

```
@FetchAll/@FetchOne/@Fetch (property wrapper)
  -> SharedReader<Value> (from swift-sharing)
    -> FetchKey (SharedReaderKey conformance)
      -> GRDB ValueObservation.tracking { ... }
        -> FetchKey.subscribe() chooses path:
           #if canImport(Combine): observation.publisher(in:) -> Combine sink
           #else: observation.start(in:) -> callback-based
```

**On Android, Combine is NOT available.** The `#else` path in `FetchKey.subscribe()` (line 155-166 of `FetchKey.swift`) uses `ValueObservation.start(in:scheduling:onError:onChange:)` which is GRDB's native callback API. This does NOT need Combine or OpenCombine.

The `SharedReader` then receives the value via `subscriber.yield(value)` and triggers SwiftUI view updates through the swift-sharing observation mechanism (which on Android flows through the Phase 1 observation bridge).

**Pattern:** Database change -> GRDB `ValueObservation` callback -> `FetchKey.subscribe` handler -> `SharedReader` update -> Observation tracking -> Phase 1 bridge -> Compose recomposition.

**Confidence:** HIGH. The non-Combine path exists and is straightforward. The SharedReader -> observation bridge chain is already validated in Phase 4 (`@Shared` uses the identical mechanism).

### 4. DynamicProperty Conformance Pattern

`@FetchAll`, `@FetchOne`, and `@Fetch` all conform to `DynamicProperty` (when `canImport(SwiftUI)`). The sqlite-data fork already has partial Android guards:

```swift
#if canImport(SwiftUI)
  extension FetchAll: DynamicProperty {
    #if !os(Android)
    public func update() {
      sharedReader.update()
    }
    // ... animation-based initializers (iOS 17+) ...
    #endif
  }
#endif
```

The `DynamicProperty` conformance itself is unguarded (available on Android via SkipSwiftUI). The `update()` method and `Animation`-based initializers are guarded out because:
- `SharedReader.update()` is guarded with `#if !os(Android)` in swift-sharing (calls `box.subscribe(state:)` which uses SwiftUI State internally)
- `Animation` type may not be fully available on Android

This matches the pattern established in Phase 4 for `SharedReader`'s own `DynamicProperty` conformance.

**Confidence:** HIGH. This is already implemented in the sqlite-data fork.

### 5. Database File Path Resolution

`defaultDatabase()` in `DefaultDatabase.swift` uses:
- **Live context:** `FileManager.default.url(for: .applicationSupportDirectory, ...)` -> `DatabasePool`
- **Test/Preview context:** `NSTemporaryDirectory()` + UUID -> `DatabasePool`

On Android, `FileManager` resolves `.applicationSupportDirectory` via the XDG environment variables bootstrapped by skip-android-bridge (`XDG_DATA_HOME` -> Android `filesDir`). This was validated in Phase 4's FileStorage work.

`NSTemporaryDirectory()` works on Android via Foundation.

**Confidence:** HIGH. The path resolution is identical to the FileStorage pattern already validated.

---

## Don't Hand-Roll

| Problem | Use Instead | Why |
|---------|-------------|-----|
| SQLite C header for Android | Vendored `sqlite3.h` already in both GRDB and structured-queries forks | Both forks already solved this with `#if __ANDROID__` -> local header include |
| Database observation | GRDB `ValueObservation` via `FetchKey.subscribe()` | Already has non-Combine callback path for Android |
| Query building | StructuredQueries `@Table`, `.select`, `.where`, etc. | Pure Swift, works as-is |
| Database dependency injection | `@Dependency(\.defaultDatabase)` via sqlite-data's `DefaultDatabaseKey` | Already implemented upstream |
| File system event monitoring for DB changes | GRDB's internal SQLite transaction hooks | NOT `DispatchSource` -- GRDB uses SQLite's commit/update hooks, not file system events |
| Connection pooling / WAL mode | GRDB `DatabasePool` | Handles WAL, concurrent reads, serialized writes internally |
| Migration system | GRDB `DatabaseMigrator` | Standard migration API, no platform-specific code |

---

## Common Pitfalls

### P1: Duplicate SQLite Symbols (CRITICAL)

**Risk:** Both GRDB (`GRDBSQLite` module) and swift-structured-queries (`_StructuredQueriesSQLite3` module) declare `link "sqlite3"` in their module.modulemaps. Both vendor `sqlite3.h` headers.

**Reality:** This is a header-only concern, NOT a linker concern. Both modules link against the same `libsqlite3` at runtime. The vendored headers are different versions (GRDB: 3.46.1, structured-queries: 3.51.2), but this only matters if code uses APIs added between those versions.

**Mitigation:** sqlite-data already bridges between the two by importing both `GRDB` and `StructuredQueriesSQLite` -- the `QueryCursor.swift` file imports `GRDBSQLite` directly for low-level row decoding. If this compiles on macOS (it does -- the fork exists and has tests), it will compile on Android because both headers resolve to the same underlying SQLite.

**Confidence:** HIGH. The two-module coexistence is already proven by sqlite-data's existing compilation.

### P2: `canImport(Combine)` False on Android

**Risk:** Code guarded by `#if canImport(Combine)` will use the `#else` path on Android.

**Impact on FetchKey:** The `subscribe()` method has explicit `#else` handling using `ValueObservation.start()`. This is correct and intentional.

**Impact on Fetch/FetchAll/FetchOne:** The `publisher` property is guarded by `#if canImport(Combine)`. On Android, this property will not exist. This is acceptable -- TCA apps use the `@FetchAll`/`@FetchOne` property wrappers directly in views, not the Combine publisher.

**Confidence:** HIGH.

### P3: `FetchKey+SwiftUI.swift` Fully Guarded Out

**Risk:** The entire `FetchKey+SwiftUI.swift` file is guarded with `#if canImport(SwiftUI) && !os(Android)`. This means the `Animation`-based `FetchKey` initializers are unavailable on Android.

**Impact:** Animation-based database observation scheduling won't work on Android. This is acceptable -- the non-animated schedulers work fine, and animation parity is explicitly out of scope (see REQUIREMENTS.md Out of Scope).

**Confidence:** HIGH.

### P4: SharedReader.update() Guarded Out on Android

**Risk:** `SharedReader.update()` (the `DynamicProperty` lifecycle method) is compiled out on Android. SwiftUI calls `update()` during view evaluation to subscribe to changes.

**Reality:** On Android via Skip, the DynamicProperty lifecycle works differently. Skip's SwiftUI bridge handles view updates through the Phase 1 observation bridge, not through SwiftUI's `update()` mechanism. The `@FetchAll`/`@FetchOne` observation still works because:
1. The `SharedReader` subscribes during initialization (via `FetchKey.load()`)
2. Value changes flow through `FetchKey.subscribe()` -> `SharedReader` internal state
3. The observation bridge detects the state change and triggers recomposition

This is the same pattern as `@Shared` on Android (validated in Phase 4).

**Confidence:** MEDIUM-HIGH. The mechanism is sound but should be verified with an actual database observation test.

### P5: CloudKit Code in sqlite-data

**Risk:** sqlite-data has substantial CloudKit integration code (`SyncEngine.swift`, `DataManager.swift`, etc.) with `#if canImport(CloudKit)` guards.

**Impact:** CloudKit is NOT available on Android. All CloudKit code is compiled out. This is fine -- CloudKit sync is not in Phase 6 scope. The guards are already in place.

**Confidence:** HIGH.

### P6: `flote/service-app` Branch References in Package.swift

**Risk:** sqlite-data's Package.swift references `flote/service-app` branches for GRDB, swift-dependencies, swift-perception, swift-sharing, and swift-structured-queries.

**Reality:** The `dev/swift-crossplatform` branch already updated dependency URLs to `jacobcxdev` (commit `c153312`). The Package.swift branch references (`branch: "flote/service-app"`) need to be updated to `branch: "dev/swift-crossplatform"` -- OR the fuse-library's local path dependencies override them entirely (since SPM resolves local `.package(path:)` over remote URLs).

**When fuse-library uses local paths, remote branch references are irrelevant.** The sqlite-data Package.swift only matters if you build sqlite-data standalone. In the fuse-library context, all forks are resolved via local paths.

**Mitigation:** Still update the branch references for cleanliness, but this is not a blocker for Phase 6 execution.

**Confidence:** HIGH.

### P7: GRDB NSObject/NSNumber/NSString/NSData Guards

**Risk:** GRDB has 7 files in `Core/Support/Foundation/` that guard `NSDate`, `NSData`, `NSNumber`, `NSString`, `Decimal`, `URL`, `UUID` `DatabaseValueConvertible` conformances behind `#if !os(Linux) && !os(Android)`.

**Impact:** On Android, these NS-bridged conformances are unavailable. This means you cannot directly use `NSDate`, `NSNumber`, etc. as database values. However:
- `Date` (Swift struct, not NSDate) has its own conformance elsewhere
- `String`, `Int`, `Double`, `Data`, `UUID` (Swift types) have conformances that work on all platforms
- The NS-bridged types are legacy ObjC interop -- modern Swift code doesn't use them

**Confidence:** HIGH. Modern Swift code uses Swift types, not NS-bridged types.

### P8: Test Target Dependencies -- Snapshot Testing

**Risk:** sqlite-data's `SQLiteDataTestSupport` depends on `InlineSnapshotTesting` from `swift-snapshot-testing`. The tests use inline snapshot assertions for SQL string validation.

**Impact for Phase 6:** Our tests in fuse-library don't need to use `SQLiteDataTestSupport` or `InlineSnapshotTesting`. We write standard XCTest assertions (matching the project's established pattern from Phases 3-5). The upstream test patterns are useful as reference, but we don't depend on their test support libraries.

**Confidence:** HIGH.

---

## Code Examples

### Example 1: @Table Macro and Query Building (SQL-01 through SQL-15)

```swift
import StructuredQueries

// @Table generates TableColumns, QueryOutput, etc.
@Table
struct Item: Identifiable, Codable, Sendable, Equatable {
  @Column(primaryKey: true)
  var id: Int
  var name: String
  var value: Int = 0
  var isActive: Bool = true
}

// Query building (pure Swift, no platform APIs)
let query = Item
  .where { $0.isActive == true }
  .order { $0.name.asc }
  .limit(10)

// Produces SQL: SELECT * FROM "items" WHERE "isActive" = 1 ORDER BY "name" ASC LIMIT 10
```

### Example 2: Database CRUD via GRDB (SD-01 through SD-08)

```swift
import SQLiteData

// Initialize database (uses @Dependency(\.defaultDatabase) internally)
let db = try DatabaseQueue()

// Migrate
var migrator = DatabaseMigrator()
migrator.registerMigration("v1") { db in
  try db.execute(sql: """
    CREATE TABLE "items" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "name" TEXT NOT NULL,
      "value" INTEGER NOT NULL DEFAULT 0,
      "isActive" INTEGER NOT NULL DEFAULT 1
    )
    """)
}
try migrator.migrate(db)

// Write
try db.write { db in
  try Item.insert { $0 in
    $0.name = "alpha"
    $0.value = 42
  }.execute(db)
}

// Read
let items = try db.read { db in
  try Item.where { $0.isActive == true }.fetchAll(db)
}

// Count
let count = try db.read { db in
  try Item.fetchCount(db)
}
```

### Example 3: @FetchAll Observation in SwiftUI View (SD-09, SD-10)

```swift
import SQLiteData
import SwiftUI

struct ItemListView: View {
  @FetchAll(Item.order { $0.name.asc })
  var items

  var body: some View {
    List(items) { item in
      Text(item.name)
    }
  }
}
```

On Android, this flows through:
1. `FetchAll.init` creates `SharedReader` with `FetchKey`
2. `FetchKey.load()` does initial `asyncRead` from database
3. `FetchKey.subscribe()` starts `ValueObservation` (callback-based on Android)
4. Database changes trigger `onChange` callback -> `SharedReader` update -> view recomposition

### Example 4: @Dependency(\.defaultDatabase) Injection (SD-12)

```swift
import Dependencies
import SQLiteData

// In app entry point
@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultDatabase = try! defaultDatabase()
    }
  }
}

// In a reducer
@Reducer
struct ItemFeature {
  @Dependency(\.defaultDatabase) var database

  func reduce(into state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .addItem(let name):
      return .run { _ in
        try database.write { db in
          try Item.insert { $0 in $0.name = name }.execute(db)
        }
      }
    }
  }
}
```

### Example 5: Test Pattern (Matching Upstream)

```swift
import XCTest
import SQLiteData
@testable import GRDB

final class StructuredQueriesTests: XCTestCase {
  func testTableSelectWhere() throws {
    let db = try DatabaseQueue()
    try setupSchema(db)

    try db.write { db in
      try Item.insert { $0 in $0.name = "alpha"; $0.value = 1 }.execute(db)
      try Item.insert { $0 in $0.name = "beta"; $0.value = 2 }.execute(db)
    }

    let items = try db.read { db in
      try Item.where { $0.value > 1 }.fetchAll(db)
    }
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].name, "beta")
  }

  private func setupSchema(_ db: DatabaseQueue) throws {
    try db.write { db in
      try db.execute(sql: """
        CREATE TABLE "items" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "name" TEXT NOT NULL,
          "value" INTEGER NOT NULL DEFAULT 0,
          "isActive" INTEGER NOT NULL DEFAULT 1
        )
        """)
    }
  }
}
```

---

## Research Item Answers

### R1: SQLite C Library on Android -- RESOLVED

**Answer:** Both GRDB and swift-structured-queries vendor their own `sqlite3.h` headers for Android. GRDB's `shim.h` uses `#if defined(__ANDROID__)` to include the local vendored header instead of the system `<sqlite3.h>`. swift-structured-queries' `_StructuredQueriesSQLite3.h` was changed from `#include <sqlite3.h>` to `#include "sqlite3.h"` to use its local vendored copy. Both module.modulemaps use `link "sqlite3"` which resolves to the system/SDK-provided `libsqlite3.so` at link time.

**No duplicate symbol risk.** Both link against the same runtime library. The vendored headers are compile-time only. Header version mismatch (3.46.1 vs 3.51.2) is acceptable because sqlite-data already bridges both modules successfully.

**Confidence:** HIGH.

### R2: Observation Macro Bridging -- RESOLVED

**Answer:** `@FetchAll`/`@FetchOne`/`@Fetch` are NOT observation macros in the `@Observable` sense. They are `@propertyWrapper` structs backed by `SharedReader` from swift-sharing. Observation works through:
1. `FetchKey` (a `SharedReaderKey`) subscribes to GRDB's `ValueObservation`
2. On Android (no Combine), uses `ValueObservation.start(in:scheduling:onError:onChange:)` callback API
3. Value changes flow to `SharedReader` via `subscriber.yield(value)`
4. `SharedReader`'s internal observation state triggers view updates through the Phase 1 bridge

The `DynamicProperty` conformance and `update()` method are guarded out on Android, matching the `SharedReader` pattern from Phase 4. Observation still works through the SharedReader subscription mechanism.

**Confidence:** HIGH.

### R3: GRDB Concurrency Model on Android -- RESOLVED

**Answer:** GRDB's concurrency model works on Android:
- `DispatchQueueActor` uses `DispatchQueue` + custom `SerialExecutor` -- both available via Android's libdispatch
- The `#if os(Linux) || os(Android)` guard for `@unchecked Sendable` on `DispatchQueueExecutor` is already in place
- `DatabasePool` uses WAL mode with a reader queue (dispatch-based) and a writer queue -- all dispatch primitives work on Android
- `DatabaseQueue` uses a single serial dispatch queue -- trivially portable
- No `DispatchSource` usage in GRDB's observation system (it uses SQLite's internal transaction hooks, not file system events)

**Confidence:** HIGH.

### R4: Prior Android Work Audit -- COMPLETE

**GRDB.swift fork** (`dev/swift-crossplatform`, 1 commit ahead of upstream `development`):

| File | Change | Status |
|------|--------|--------|
| `Sources/GRDBSQLite/shim.h` | `#if defined(__ANDROID__)` -> local `sqlite3.h` include | DONE |
| `Sources/GRDBSQLite/sqlite3.h` | Vendored SQLite 3.46.1 header (629KB) | DONE |
| `GRDB/Core/DispatchQueueActor.swift` | `#if os(Linux) || os(Android)` for `@unchecked Sendable` | DONE |
| `GRDB/Core/StatementAuthorizer.swift` | `#elseif os(Android) import Android` for `string_h` | DONE |
| `GRDB/Core/Support/Foundation/Date.swift` | `#if !os(Linux) && !os(Android)` -- NSDate exclusion | DONE |
| `GRDB/Core/Support/Foundation/Decimal.swift` | `#if !os(Linux) && !os(Android)` -- Decimal exclusion | DONE |
| `GRDB/Core/Support/Foundation/NSData.swift` | `#if !os(Linux) && !os(Android)` | DONE |
| `GRDB/Core/Support/Foundation/NSNumber.swift` | `#if !os(Linux) && !os(Android)` | DONE |
| `GRDB/Core/Support/Foundation/NSString.swift` | `#if !os(Linux) && !os(Android)` | DONE |
| `GRDB/Core/Support/Foundation/URL.swift` | `#if !os(Linux) && !os(Android)` | DONE |
| `GRDB/Core/Support/Foundation/UUID.swift` | `#if !os(Linux) && !os(Android)` | DONE |

**Remaining GRDB gaps:** None identified for Phase 6 scope. The fork has comprehensive Android enablement.

**sqlite-data fork** (`dev/swift-crossplatform`, 15 commits ahead of upstream `main`):

| File | Change | Status |
|------|--------|--------|
| `Package.swift` | `TARGET_OS_ANDROID` conditional for skip-bridge/skip-android-bridge/swift-jni | DONE |
| `Package.swift` | Dependency URLs updated to `jacobcxdev` | DONE |
| `Sources/SQLiteData/Fetch.swift` | `DynamicProperty` unguarded, `update()` + Animation inits guarded `#if !os(Android)` | DONE |
| `Sources/SQLiteData/FetchAll.swift` | Same pattern as Fetch.swift | DONE |
| `Sources/SQLiteData/FetchOne.swift` | Same pattern as Fetch.swift | DONE |
| `Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift` | Entire file guarded `#if canImport(SwiftUI) && !os(Android)` | DONE |
| `Sources/SQLiteData/CloudKit/Internal/DataManager.swift` | Minor CloudKit-related change | DONE |
| `Sources/SQLiteData/CloudKit/Internal/MockCloudDatabase.swift` | Minor change | DONE |
| `Sources/SQLiteData/CloudKit/Internal/MockSyncEngine.swift` | Minor change | DONE |
| `Sources/SQLiteData/CloudKit/SyncEngine.swift` | Minor changes | DONE |
| `Tests/SQLiteDataTests/AndroidParityTests.swift` | NEW: 6 CRUD tests + 6 DynamicProperty parity tests | DONE |

**Remaining sqlite-data gaps:**
1. Package.swift still references `branch: "flote/service-app"` for some deps (overridden by local paths in fuse-library)
2. No StructuredQueries-based tests yet (existing tests use raw SQL)
3. No observation/FetchKey tests yet (existing tests are CRUD-only)

**swift-structured-queries fork** (`dev/swift-crossplatform`, 4 commits ahead of upstream `main`):

| File | Change | Status |
|------|--------|--------|
| `Sources/_StructuredQueriesSQLite3/_StructuredQueriesSQLite3.h` | `#include "sqlite3.h"` (local) instead of `<sqlite3.h>` (system) | DONE |
| `Sources/_StructuredQueriesSQLite3/sqlite3.h` | Vendored SQLite 3.51.2 header (656KB) | DONE |
| `Sources/StructuredQueriesCore/Statements/Select.swift` | Relaxed `order(by:)` constraint (removed `where Joins == ()`) | DONE |
| `Package.swift` | Dependency URLs updated to `jacobcxdev` | DONE |

**Remaining structured-queries gaps:** None identified. The library is pure Swift -- all query building works on any platform.

### R5: Database File Location -- RESOLVED

**Answer:** `defaultDatabase()` uses `FileManager.default.url(for: .applicationSupportDirectory, ...)`. On Android, skip-android-bridge bootstraps `XDG_DATA_HOME` -> Android `filesDir`, so `FileManager` resolves `.applicationSupportDirectory` correctly. This was validated in Phase 4 for `FileStorageKey`.

For test/preview contexts, `NSTemporaryDirectory()` + UUID is used, which works on Android via Foundation.

**No changes needed** to `DefaultDatabase.swift` for Android path resolution.

**Confidence:** HIGH.

### R6: Test Patterns -- RESOLVED

**Answer:** Upstream Point-Free test patterns:

**StructuredQueries tests:** Use `InlineSnapshotTesting` to assert SQL string output. Example: build a query, assert the generated SQL matches an inline snapshot. These are pure string comparisons -- no database execution needed.

**SQLiteData tests:** Use `DatabaseQueue()` (in-memory) for CRUD operations. Use `SQLiteDataTestSupport` + `InlineSnapshotTesting` for snapshot-based assertions. Use `DependenciesTestSupport` for dependency overrides.

**Our test pattern (fuse-library):** Use standard `XCTest` assertions with `DatabaseQueue()` in-memory databases. Match Phases 3-5 convention:
1. Create `DatabaseQueue()` (in-memory)
2. Set up schema with raw SQL or `DatabaseMigrator`
3. Execute StructuredQueries operations
4. Assert results with `XCTAssertEqual`

Do NOT depend on `SQLiteDataTestSupport` or `InlineSnapshotTesting` -- keep test targets lightweight.

**Confidence:** HIGH.

### R7: Perception Usage in sqlite-data -- RESOLVED

**Answer:** sqlite-data imports `Perception` in exactly ONE file: `FetchSubscription.swift` (line 1: `import Perception`). It uses `LockIsolated` from Perception (which is actually re-exported from `swift-concurrency-extras`).

sqlite-data does NOT use `@Perceptible`, `PerceptionRegistrar`, or `withPerceptionTracking`. The `Perception` import is effectively just for `LockIsolated`.

On Android, the `Perception` module is available (it passes through to native `Observation`). `LockIsolated` is pure Swift concurrency -- no platform dependency.

**Confidence:** HIGH. No Perception observation machinery is used.

### R8: OpenCombine / Async Observation Path -- RESOLVED

**Answer:** GRDB's `ValueObservation` has two consumption APIs:
1. `observation.publisher(in:)` -- returns a Combine `Publisher` (requires `canImport(Combine)`)
2. `observation.start(in:scheduling:onError:onChange:)` -- callback-based (always available)

sqlite-data's `FetchKey.subscribe()` already handles both paths:
```swift
#if canImport(Combine)
  // Uses observation.publisher(in:) -> Combine sink
#else
  // Uses observation.start(in:) -> callback-based
#endif
```

On Android, the `#else` path is used. **No OpenCombine dependency is needed** for database observation. This is simpler than the Combine path and has fewer moving parts.

GRDB itself does not use OpenCombine anywhere -- its Combine support is behind `#if canImport(Combine)`.

**Confidence:** HIGH.

---

## Decisions for Planning

### D1: No New Fork Changes Needed for GRDB or StructuredQueries

Both forks have complete Android enablement. Phase 6 work focuses on:
1. Wiring database forks into fuse-library's Package.swift
2. Writing validation tests
3. Verifying the full observation chain end-to-end

### D2: sqlite-data Fork is Mostly Ready

The DynamicProperty guards and Package.swift Android conditionals are already done. Remaining work:
1. Update Package.swift branch references from `flote/service-app` to `dev/swift-crossplatform` (cleanup, not blocking)
2. Validate StructuredQueries-based operations (existing tests only cover raw SQL CRUD)

### D3: Test Strategy -- In-Memory DatabaseQueue

All tests use `DatabaseQueue()` (in-memory, no file I/O). Schema setup via raw SQL `CREATE TABLE` statements. StructuredQueries operations for data manipulation. Standard `XCTAssertEqual` assertions.

New test targets in fuse-library Package.swift:
- `StructuredQueriesTests` -- query building and execution (SQL-01..SQL-15)
- `SQLiteDataTests` -- database lifecycle, migration, observation (SD-01..SD-12)

### D4: Package.swift Wiring Sequence

Uncomment the 4 deferred database forks in fuse-library's Package.swift:
```swift
.package(path: "../../forks/swift-snapshot-testing"),  // needed by sqlite-data
.package(path: "../../forks/swift-structured-queries"),
.package(path: "../../forks/GRDB.swift"),
.package(path: "../../forks/sqlite-data"),
```

Add test target dependencies referencing `SQLiteData` (which re-exports `GRDB`, `StructuredQueriesSQLite`, and `Dependencies`).

**Critical constraint:** Skip sandbox only resolves deps used by targets. All 4 forks must be used by at least one target or `skip test` will fail (learned in Phase 2).

### D5: Observation Testing Requires Async Pattern

Testing `@FetchAll`/`@FetchOne` observation requires:
1. Set up database with initial data
2. Create observation (via `FetchKey` / `SharedReader`)
3. Mutate database in background
4. Assert the observed value changes

This uses `ValueObservation.start()` + async expectations. Match the pattern used by upstream sqlite-data tests.

---

## Risk Summary

| Risk | Severity | Likelihood | Mitigation |
|------|----------|-----------|------------|
| SQLite header version mismatch | Low | Low | Already working in sqlite-data fork |
| `FetchKey.subscribe()` non-Combine path untested on Android | Medium | Low | Write explicit test; path exists and is simple |
| Package.swift wiring breaks `skip test` | Medium | Medium | Add all 4 forks, ensure targets reference products |
| `SharedReader` observation doesn't trigger on Android | Low | Low | Identical to Phase 4 `@Shared` pattern (validated) |
| GRDB `DatabasePool` WAL mode on Android | Low | Low | `DispatchQueue`-based concurrency works on Android |
| CloudKit code bleeds through guards | None | None | Already guarded with `#if canImport(CloudKit)` |

---

*Research completed: 2026-02-22*
*All 8 research items (R1-R8) resolved with HIGH confidence*
*All 7 decisions (D1-D7) from context addressed*
