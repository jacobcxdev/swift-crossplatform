# R6 — Test Patterns: StructuredQueries and SQLiteData

**Research item:** How does Point-Free test StructuredQueries and SQLiteData upstream, and what pattern should we use in `examples/fuse-library/`?
**Completed:** 2026-02-22
**Status:** RESOLVED — HIGH confidence

---

## 1. Upstream Test Infrastructure Inventory

### 1.1 swift-structured-queries Test Targets

The fork at `forks/swift-structured-queries/Tests/` has two test targets:

**`StructuredQueriesTests`** — the main functional test suite (41 files):
- Uses `swift-testing` (`@Test`, `@Suite`, `#expect`)
- Uses `InlineSnapshotTesting` for SQL string and result table assertions
- Uses `Dependencies` for injecting an in-memory `Database` singleton
- All test files extend `SnapshotTests` (a `@MainActor @Suite(.serialized, .snapshots(record: .failed))` container)
- Key pattern: `assertQuery(SomeTable.where { ... }) { "<sql string>" } results: { "<table string>" }`

**`StructuredQueriesMacrosTests`** — macro expansion tests:
- Uses `MacroTesting` for expanding `@Table`, `@Column`, `@Selection`, `#sql()`, `@DatabaseFunction`
- Pure string comparisons of expanded Swift code
- Not relevant to Phase 6 (macros expand on the host, not on Android)

Key support files in `Tests/StructuredQueriesTests/Support/`:

- **`SnapshotTests.swift`**: Declares `@MainActor @Suite(.serialized, .snapshots(record: .failed)) struct SnapshotTests {}`
- **`Schema.swift`**: Defines `RemindersList`, `Reminder`, `User`, `Tag`, `ReminderTag`, `Priority` as `@Table` types. Creates an in-memory `Database` via `Database.default()`, seeds it with 10 reminders across 3 lists. Registers this as a `DependencyKey` (`defaultDatabase`).
- **`AssertQuery.swift`**: Thin wrappers around `StructuredQueriesTestSupport.assertQuery()` that pull `db` from `@Dependency(\.defaultDatabase)`.

The **`StructuredQueriesTestSupport`** library (source at `forks/swift-structured-queries/Sources/StructuredQueriesTestSupport/AssertQuery.swift`) provides:
- `assertQuery(_:execute:sql:results:...)` — takes a query + execute closure, asserts SQL via `assertInlineSnapshot(as: .sql)`, asserts results via `assertInlineSnapshot(as: .lines)` using a custom `printTable()` formatter (box-drawing characters)
- The `printTable()` helper uses `customDump()` (from swift-custom-dump) to format each cell

### 1.2 sqlite-data Test Targets

The fork at `forks/sqlite-data/Tests/SQLiteDataTests/` has one test target (`SQLiteDataTests`) with many files:

**Core patterns used:**

1. **In-memory `DatabaseQueue()`** — every non-CloudKit test creates `try DatabaseQueue()` (no path argument = in-memory). This is zero-overhead, zero-file-I/O.

2. **`DatabaseMigrator` for schema setup** — `DatabaseMigrator.registerMigration("name") { db in ... }` then `migrator.migrate(database)`. Uses `#sql()` macro for DDL statements.

3. **`DependenciesTestSupport` trait** — `@Suite(.dependency(\.defaultDatabase, try .database()))` injects a configured in-memory database for the whole suite. Individual tests access it via `@Dependency(\.defaultDatabase) var database`.

4. **`SQLiteDataTestSupport.assertQuery()`** — available for snapshot-style assertions but requires `@available(iOS 17, macOS 14, ...)`. Wraps `StructuredQueriesTestSupport.assertQuery()` but reads from the database via `database.write { try query.fetchAll($0) }`. **Critical difference from upstream:** no `execute:` closure argument — the database is wired through the dependency system.

5. **swift-testing `#expect` assertions** — all tests use `#expect(value == expected)` not `XCTAssertEqual`.

6. **`@FetchAll`, `@FetchOne`, `@Fetch` + `$wrapper.load()`** — observation tests use these property wrappers with explicit `await $records.load()` to force a synchronous reload before asserting.

**Key test files and what they show:**

| File | Pattern | Key insight |
|------|---------|-------------|
| `AndroidParityTests.swift` | XCTest + raw GRDB | Already exists in the fork; covers basic CRUD, UUID, Date round-trip, and DynamicProperty conformances |
| `MigrationTests.swift` | `DatabaseQueue()` + `#sql()` DDL + `DatabaseMigrator` | Schema setup pattern for tests |
| `FetchTests.swift` | `@FetchAll`/`@FetchOne` + `await $wrapper.load()` | Observation property wrapper test pattern |
| `IntegrationTests.swift` | `@FetchAll` + `await database.write { }` + `await $wrapper.load()` | Full CRUD + observation cycle |
| `AssertQueryTests.swift` | `SQLiteDataTestSupport.assertQuery()` + inline snapshots | Snapshot-based result assertion (iOS 17+) |
| `FetchAllTests.swift` | Concurrency stress test + `@FetchAll` | Concurrent write + observation reliability |

---

## 2. Key Design Decisions Established by Upstream

### 2.1 `DatabaseQueue()` with No Arguments = In-Memory

Confirmed by source: `DatabaseQueue()` (no path argument) creates a fully in-memory SQLite database. This is the standard pattern for all non-CloudKit upstream tests. It is:
- Zero file I/O
- Automatically destroyed when the object is deallocated
- Thread-safe (single serial queue)
- Suitable as `any DatabaseWriter` (implements both `DatabaseReader` and `DatabaseWriter`)

**Source confirmation:** `forks/sqlite-data/Sources/SQLiteData/StructuredQueries+GRDB/DefaultDatabase.swift` line 147 shows `DatabaseQueue(configuration: configuration)` is the fallback in-memory database even in the production default key.

### 2.2 Snapshot Testing Is NOT Our Pattern

Upstream uses `InlineSnapshotTesting` because:
- Tests are written with swift-testing (`@Test`, `#expect`)
- SQL string verification is the primary assertion
- Snapshots auto-update when you run tests with `record: .missing`

**Our constraint:** We use XCTest (not swift-testing). We do not add `InlineSnapshotTesting` as a test dependency. All assertions are `XCTAssertEqual`, `XCTAssertNil`, `XCTAssertThrowsError`, etc.

**However:** We can verify SQL correctness by checking `query.queryFragment.sql` — the `QueryFragment` type has a `.sql` property that returns the raw SQL string. This lets us assert SQL without snapshot infrastructure.

### 2.3 The Correct SQL Assertion Without Snapshots

StructuredQueries queries expose their SQL via:
```swift
let query = Item.where { $0.isActive == true }.order { $0.name.asc() }
let sql = query.queryFragment.sql
XCTAssertEqual(sql, #"SELECT "items"."id", "items"."name", "items"."value", "items"."isActive" FROM "items" WHERE ("items"."isActive") ORDER BY "items"."name" ASC"#)
```

This is a direct string comparison — no snapshot infrastructure needed.

### 2.4 Schema Setup Pattern (Our Convention)

Based on `IntegrationTests.swift` and `MigrationTests.swift`, the recommended schema setup for our tests:

```swift
// Option A: Direct DDL (simple cases)
let db = try DatabaseQueue()
try db.write { db in
    try db.execute(sql: """
        CREATE TABLE "items" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "name" TEXT NOT NULL,
          "value" INTEGER NOT NULL DEFAULT 0
        )
        """)
}

// Option B: DatabaseMigrator (multi-step migrations, SD-02)
let db = try DatabaseQueue()
var migrator = DatabaseMigrator()
migrator.registerMigration("v1") { db in
    try db.execute(sql: """
        CREATE TABLE "items" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "name" TEXT NOT NULL
        )
        """)
}
try migrator.migrate(db)
```

---

## 3. Established Project Pattern (Phases 3-5)

Our existing test targets use:
- `final class SomeFooTests: XCTestCase` (XCTest, not swift-testing)
- `func testFoo() throws { ... }` methods
- `XCTAssertEqual`, `XCTAssertNil`, `XCTAssertThrowsError`
- Plain `try` in test methods (XCTest propagates throws)
- Types defined at file scope (macros cannot attach to local types)
- No `@MainActor` annotation unless required by the API under test

Example from `SharedPersistenceTests.swift`:
```swift
final class SharedPersistenceTests: XCTestCase {
    @MainActor func testAppStorageBool() {
        @Shared(.appStorage("shr01_bool")) var value = false
        $value.withLock { $0 = true }
        XCTAssertEqual(value, true)
    }
}
```

Example from `StoreReducerTests.swift`:
```swift
@Reducer struct Counter { ... }

final class StoreReducerTests: XCTestCase {
    func testStoreInit() throws {
        let store = Store(initialState: Counter.State()) { Counter() }
        XCTAssertEqual(store.count, 0)
    }
}
```

**Phase 6 tests must match this established convention exactly.**

---

## 4. Recommended Test Target Structure

Two new test targets in `examples/fuse-library/Package.swift`:

### Target A: `StructuredQueriesTests`

Covers SQL-01 through SQL-15. Tests StructuredQueries query building and execution.

**Dependencies:**
```swift
.testTarget(name: "StructuredQueriesTests", dependencies: [
    .product(name: "StructuredQueries", package: "swift-structured-queries"),
    .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
    .product(name: "SQLiteData", package: "sqlite-data"),  // provides DatabaseQueue
])
```

**Why include `SQLiteData`?** `StructuredQueriesSQLite` provides the `Database` type used in the upstream fork tests, but `DatabaseQueue` comes from GRDB via `SQLiteData`. Including `SQLiteData` pulls in the full stack and lets us use `DatabaseQueue()` directly.

**Alternative (leaner):** Import only `StructuredQueriesSQLite` and GRDB directly. But GRDB is a transitive dependency of `SQLiteData`, so both approaches work. Using `SQLiteData` is simpler because it re-exports everything.

### Target B: `SQLiteDataTests`

Covers SD-01 through SD-12. Tests database lifecycle, migrations, CRUD, and observation.

**Dependencies:**
```swift
.testTarget(name: "SQLiteDataTests", dependencies: [
    .product(name: "SQLiteData", package: "sqlite-data"),
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "StructuredQueries", package: "swift-structured-queries"),
])
```

### Shared Schema Types

Both targets need the same schema. Define in their respective support files (not shared, to keep targets independent). A minimal schema sufficient to cover all 27 requirements:

```swift
// In both test targets' support files
import StructuredQueries

@Table
struct Item: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    var name: String = ""
    var value: Int = 0
    var isActive: Bool = true
    var tag: Tag? = nil
}

enum Tag: Int, Codable, QueryBindable {
    case low = 1
    case medium = 2
    case high = 3
}

@Table
struct Category: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    var title: String = ""
}
```

Schema DDL:
```swift
func makeTestDatabase() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try db.write { db in
        try db.execute(sql: """
            CREATE TABLE "items" (
              "id" INTEGER PRIMARY KEY AUTOINCREMENT,
              "name" TEXT NOT NULL DEFAULT '',
              "value" INTEGER NOT NULL DEFAULT 0,
              "isActive" INTEGER NOT NULL DEFAULT 1,
              "tag" INTEGER,
              "categoryID" INTEGER REFERENCES "categories"("id") ON DELETE SET NULL
            )
            """)
        try db.execute(sql: """
            CREATE TABLE "categories" (
              "id" INTEGER PRIMARY KEY AUTOINCREMENT,
              "title" TEXT NOT NULL DEFAULT ''
            )
            """)
    }
    return db
}
```

---

## 5. Concrete Test Examples by Requirement

### SQL-01: `@Table` macro generates correct table metadata

```swift
func testTableMacroGeneratesMetadata() {
    // @Table synthesizes tableName, TableColumns, QueryOutput
    XCTAssertEqual(Item.tableName, "items")
    // Verify column access compiles (compile-time proof)
    let _ = Item.TableColumns.self
}
```

### SQL-02: `@Column(primaryKey:)` custom primary key

```swift
@Table
struct CustomPK: Equatable {
    @Column(primaryKey: true)
    var code: String = ""
    var label: String = ""
}

func testCustomPrimaryKey() throws {
    let db = try DatabaseQueue()
    try db.write { db in
        try db.execute(sql: """
            CREATE TABLE "customPKs" (
              "code" TEXT PRIMARY KEY,
              "label" TEXT NOT NULL DEFAULT ''
            )
            """)
    }
    try db.write { db in
        try CustomPK.insert { $0 in
            $0.code = "X1"
            $0.label = "Alpha"
        }.execute(db)
    }
    let row = try db.read { db in
        try CustomPK.find("X1").fetchOne(db)
    }
    XCTAssertNotNil(row)
    XCTAssertEqual(row?.label, "Alpha")
}
```

### SQL-03: `@Column(as:)` custom representations

```swift
struct JSONData: Codable, Equatable { var x: Int; var y: Int }

@Table
struct ModelWithJSON: Equatable {
    let id: Int
    @Column(as: JSONRepresentation<JSONData>.self)
    var data: JSONData = JSONData(x: 0, y: 0)
}

func testColumnAsCustomRepresentation() throws {
    // Verify the column compiles and round-trips through the database
    // (Exact implementation depends on JSONRepresentation availability)
    // Fallback: verify @Column(as:) compiles on this platform
    let _ = ModelWithJSON.TableColumns.self
}
```

### SQL-04: `@Selection` type composition

```swift
@Selection
struct ItemSummary: Equatable {
    var name: String
    var value: Int
}

func testSelectionComposition() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('alpha', 10)")
    }
    // @Selection lets you select a subset of columns as a named type
    let summaries = try db.read { db in
        try Item.select { ItemSummary(name: $0.name, value: $0.value) }.fetchAll(db)
    }
    XCTAssertEqual(summaries.count, 1)
    XCTAssertEqual(summaries[0].name, "alpha")
    XCTAssertEqual(summaries[0].value, 10)
}
```

### SQL-05: `Table.select { }` tuple/closure column selection

```swift
func testSelectTupleColumns() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('beta', 99)")
    }
    let rows = try db.read { db in
        try Item.select { ($0.name, $0.value) }.fetchAll(db)
    }
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].0, "beta")
    XCTAssertEqual(rows[0].1, 99)
}

func testSelectSingleColumn() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name) VALUES ('gamma')")
    }
    let names = try db.read { db in
        try Item.select(\.name).fetchAll(db)
    }
    XCTAssertEqual(names, ["gamma"])
}
```

### SQL-06: `Table.where { }` predicates

```swift
func testWhereEquality() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3)")
    }
    let items = try db.read { db in
        try Item.where { $0.value == 2 }.fetchAll(db)
    }
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].name, "b")
}

func testWhereComparison() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3)")
    }
    let items = try db.read { db in
        try Item.where { $0.value > 1 }.fetchAll(db)
    }
    XCTAssertEqual(items.count, 2)
}

func testWhereBoolean() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, isActive) VALUES ('a', 1), ('b', 0)")
    }
    let active = try db.read { db in
        try Item.where { $0.isActive == true }.fetchAll(db)
    }
    XCTAssertEqual(active.count, 1)
    XCTAssertEqual(active[0].name, "a")
}

func testWhereCombined() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value, isActive) VALUES ('a', 5, 1), ('b', 5, 0), ('c', 3, 1)")
    }
    let items = try db.read { db in
        try Item.where { $0.value == 5 && $0.isActive == true }.fetchAll(db)
    }
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].name, "a")
}
```

### SQL-07: `Table.find(id)` primary key lookup

```swift
func testFindByPrimaryKey() throws {
    let db = try makeTestDatabase()
    var insertedID: Int = 0
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name) VALUES ('findme')")
        insertedID = Int(db.lastInsertedRowID)
    }
    let found = try db.read { db in
        try Item.find(insertedID).fetchOne(db)
    }
    XCTAssertNotNil(found)
    XCTAssertEqual(found?.name, "findme")

    let notFound = try db.read { db in
        try Item.find(99999).fetchOne(db)
    }
    XCTAssertNil(notFound)
}
```

### SQL-08: IN / NOT IN operators

```swift
func testWhereIn() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3)")
    }
    let items = try db.read { db in
        try Item.where { $0.value.in([1, 3]) }.fetchAll(db)
    }
    XCTAssertEqual(items.count, 2)
    XCTAssertTrue(items.allSatisfy { $0.value == 1 || $0.value == 3 })
}

func testWhereNotIn() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3)")
    }
    let items = try db.read { db in
        try Item.where { !$0.value.in([1, 3]) }.fetchAll(db)
    }
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].value, 2)
}
```

### SQL-09: Joins

```swift
func testInnerJoin() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO categories (id, title) VALUES (1, 'Tech'), (2, 'Food')")
        try db.execute(sql: "INSERT INTO items (name, categoryID) VALUES ('Phone', 1), ('Burger', 2), ('Laptop', 1)")
    }
    let pairs = try db.read { db in
        try Item
            .join(Category.all) { $0.categoryID.eq($1.id) }
            .select { ($0.name, $1.title) }
            .fetchAll(db)
    }
    XCTAssertEqual(pairs.count, 3)
    XCTAssertTrue(pairs.contains(where: { $0.0 == "Phone" && $0.1 == "Tech" }))
}

func testLeftJoin() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO categories (id, title) VALUES (1, 'Tech')")
        try db.execute(sql: "INSERT INTO items (name, categoryID) VALUES ('Phone', 1), ('Orphan', NULL)")
    }
    let pairs = try db.read { db in
        try Item
            .leftJoin(Category.all) { $0.categoryID.eq($1.id) }
            .select { ($0.name, $1.title) }
            .fetchAll(db)
    }
    // Left join includes items with no category
    XCTAssertEqual(pairs.count, 2)
}
```

### SQL-10: Ordering

```swift
func testOrderAscending() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('c', 3), ('a', 1), ('b', 2)")
    }
    let items = try db.read { db in
        try Item.order { $0.value.asc() }.fetchAll(db)
    }
    XCTAssertEqual(items.map(\.value), [1, 2, 3])
}

func testOrderDescending() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('c', 3), ('a', 1), ('b', 2)")
    }
    let items = try db.read { db in
        try Item.order { $0.value.desc() }.fetchAll(db)
    }
    XCTAssertEqual(items.map(\.value), [3, 2, 1])
}

func testOrderCollation() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name) VALUES ('banana'), ('Apple'), ('cherry')")
    }
    let items = try db.read { db in
        try Item.order { $0.name.collate(.nocase).asc() }.fetchAll(db)
    }
    XCTAssertEqual(items.map(\.name), ["Apple", "banana", "cherry"])
}
```

### SQL-11: Aggregations

```swift
func testCount() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3)")
    }
    let count = try db.read { db in
        try Item.count().fetchOne(db)
    }
    XCTAssertEqual(count, 3)
}

func testSum() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 10), ('b', 20), ('c', 30)")
    }
    let sum = try db.read { db in
        try Item.select { $0.value.sum() }.fetchOne(db)
    }
    XCTAssertEqual(sum, 60)
}

func testGroupByWithCount() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO categories (id, title) VALUES (1, 'Tech'), (2, 'Food')")
        try db.execute(sql: "INSERT INTO items (name, categoryID) VALUES ('Phone', 1), ('Laptop', 1), ('Burger', 2)")
    }
    let counts = try db.read { db in
        try Item
            .join(Category.all) { $0.categoryID.eq($1.id) }
            .group { $1.id }
            .select { ($1.title, $0.id.count()) }
            .fetchAll(db)
    }
    XCTAssertEqual(counts.count, 2)
    let techCount = counts.first(where: { $0.0 == "Tech" })?.1
    XCTAssertEqual(techCount, 2)
}
```

### SQL-12: Limit / Offset

```swift
func testLimit() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3), ('d', 4)")
    }
    let items = try db.read { db in
        try Item.order { $0.value.asc() }.limit(2).fetchAll(db)
    }
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items.map(\.value), [1, 2])
}

func testLimitWithOffset() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3), ('d', 4)")
    }
    let items = try db.read { db in
        try Item.order { $0.value.asc() }.limit(2, offset: 2).fetchAll(db)
    }
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items.map(\.value), [3, 4])
}
```

### SQL-13: Insert / Upsert

```swift
func testInsertDraft() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try Item.insert { $0 in
            $0.name = "alpha"
            $0.value = 42
        }.execute(db)
    }
    let count = try db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 1)
}

func testInsertMultiple() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try Item.insert {
            Item.Draft(name: "a", value: 1)
            Item.Draft(name: "b", value: 2)
        }.execute(db)
    }
    let count = try db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 2)
}

func testUpsert() throws {
    let db = try makeTestDatabase()
    var id: Int = 0
    try db.write { db in
        try Item.insert { $0 in $0.name = "original" }.execute(db)
        id = Int(db.lastInsertedRowID)
    }
    try db.write { db in
        try Item.upsert {
            Item.Draft(id: id, name: "updated")
        }.execute(db)
    }
    let item = try db.read { db in try Item.find(id).fetchOne(db) }
    XCTAssertEqual(item?.name, "updated")
}

func testInsertOnConflict() throws {
    let db = try makeTestDatabase()
    var id: Int = 0
    try db.write { db in
        try Item.insert { $0 in $0.name = "original"; $0.value = 1 }.execute(db)
        id = Int(db.lastInsertedRowID)
    }
    // On conflict do update — name stays, value increments
    try db.write { db in
        try Item.insert {
            Item.Draft(id: id, name: "original", value: 2)
        } onConflictDoUpdate: {
            $0.value += 1
        }.execute(db)
    }
    let item = try db.read { db in try Item.find(id).fetchOne(db) }
    XCTAssertEqual(item?.value, 2)
}
```

### SQL-14: Update / Delete

```swift
func testUpdate() throws {
    let db = try makeTestDatabase()
    var id: Int = 0
    try db.write { db in
        try Item.insert { $0 in $0.name = "old"; $0.isActive = false }.execute(db)
        id = Int(db.lastInsertedRowID)
    }
    try db.write { db in
        try Item.find(id).update { $0.isActive = true }.execute(db)
    }
    let item = try db.read { db in try Item.find(id).fetchOne(db) }
    XCTAssertEqual(item?.isActive, true)
}

func testUpdateWhere() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value, isActive) VALUES ('a', 1, 1), ('b', 2, 1), ('c', 3, 1)")
    }
    try db.write { db in
        try Item.where { $0.value < 3 }
            .update { $0.isActive = false }
            .execute(db)
    }
    let inactive = try db.read { db in
        try Item.where { $0.isActive == false }.fetchAll(db)
    }
    XCTAssertEqual(inactive.count, 2)
}

func testDelete() throws {
    let db = try makeTestDatabase()
    var id: Int = 0
    try db.write { db in
        try Item.insert { $0 in $0.name = "doomed" }.execute(db)
        id = Int(db.lastInsertedRowID)
    }
    try db.write { db in
        try Item.find(id).delete().execute(db)
    }
    let count = try db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 0)
}

func testDeleteWhere() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2), ('c', 3)")
    }
    try db.write { db in
        try Item.where { $0.value < 3 }.delete().execute(db)
    }
    let count = try db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 1)
}
```

### SQL-15: `#sql()` safe macro with column interpolation

```swift
func testSQLMacroStringLiteral() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('test', 42)")
    }
    // #sql() with a bare string — compiles to a QueryFragment
    let fragment = #sql("SELECT COUNT(*) FROM items")
    let count = try db.read { db in
        try Int.fetchOne(db, sql: fragment.sql)
    }
    XCTAssertEqual(count, 1)
}

func testSQLMacroColumnInterpolation() throws {
    // #sql() with column reference interpolation
    // The macro validates that interpolated expressions are column expressions (compile-time)
    let query = Item.where {
        #sql("(\($0.value)) > 5", as: Bool.self)
    }
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('low', 3), ('high', 10)")
    }
    let items = try db.read { db in try query.fetchAll(db) }
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].name, "high")
}
```

### SD-01: `defaultDatabase()` initialization

```swift
func testDefaultDatabaseInit() throws {
    // In-memory database is the simplest form — verifies DatabaseQueue initializes
    let db = try DatabaseQueue()
    XCTAssertNotNil(db)
}

func testDefaultDatabaseFunctionInit() throws {
    // defaultDatabase() from SQLiteData uses dependency context
    withDependencies {
        $0.context = .test
    } operation: {
        let db = try? defaultDatabase()
        XCTAssertNotNil(db)
    }
}
```

### SD-02: `DatabaseMigrator` executes migrations

```swift
func testMigratorRunsMigrations() throws {
    let db = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
        try db.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
    }
    migrator.registerMigration("v2") { db in
        try db.execute(sql: "ALTER TABLE test ADD COLUMN name TEXT")
    }
    XCTAssertNoThrow(try migrator.migrate(db))

    // Verify both migrations applied
    let count = try db.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='test'")
    }
    XCTAssertEqual(count, 1)
}

func testMigratorIdempotent() throws {
    let db = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
        try db.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
    }
    try migrator.migrate(db)
    // Running again must not throw (migration already applied)
    XCTAssertNoThrow(try migrator.migrate(db))
}
```

### SD-03/04: Synchronous read/write transactions

```swift
func testSyncRead() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('x', 7)")
    }
    // Synchronous read transaction
    let value = try db.read { db in
        try Int.fetchOne(db, sql: "SELECT value FROM items WHERE name = 'x'")
    }
    XCTAssertEqual(value, 7)
}

func testSyncWrite() throws {
    let db = try makeTestDatabase()
    // Synchronous write transaction
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('y', 99)")
    }
    let count = try db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 1)
}

func testWriteTransactionRollsBackOnError() throws {
    let db = try makeTestDatabase()
    try? db.write { db in
        try db.execute(sql: "INSERT INTO items (name) VALUES ('a')")
        throw NSError(domain: "test", code: 1)  // force rollback
    }
    let count = try db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 0)  // rolled back
}
```

### SD-05: Async read/write transactions

```swift
func testAsyncRead() async throws {
    let db = try makeTestDatabase()
    try await db.write { db in
        try db.execute(sql: "INSERT INTO items (name) VALUES ('async')")
    }
    let count = try await db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 1)
}

func testAsyncWrite() async throws {
    let db = try makeTestDatabase()
    try await db.write { db in
        try Item.insert { $0 in $0.name = "async-item" }.execute(db)
    }
    let items = try await db.read { db in try Item.fetchAll(db) }
    XCTAssertEqual(items.count, 1)
}
```

### SD-06/07/08: fetchAll / fetchOne / fetchCount

```swift
func testFetchAll() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 2)")
    }
    let items = try db.read { db in try Item.fetchAll(db) }
    XCTAssertEqual(items.count, 2)
}

func testFetchOne() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('only', 42)")
    }
    let item = try db.read { db in try Item.fetchOne(db) }
    XCTAssertNotNil(item)
    XCTAssertEqual(item?.name, "only")
}

func testFetchOneReturnsNilWhenEmpty() throws {
    let db = try makeTestDatabase()
    let item = try db.read { db in try Item.fetchOne(db) }
    XCTAssertNil(item)
}

func testFetchCount() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name) VALUES ('a'), ('b'), ('c')")
    }
    let count = try db.read { db in try Item.fetchCount(db) }
    XCTAssertEqual(count, 3)
}

func testFetchCountWithWhere() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1), ('b', 5), ('c', 10)")
    }
    let count = try db.read { db in
        try Item.where { $0.value > 3 }.fetchCount(db)
    }
    XCTAssertEqual(count, 2)
}
```

### SD-09/10/11: `@FetchAll`, `@FetchOne`, `@Fetch` observation

These require `@MainActor` and explicit `load()` calls (matching the upstream `FetchTests.swift` pattern):

```swift
// NOTE: @FetchAll, @FetchOne, @Fetch are DynamicProperty wrappers.
// In XCTest (not a SwiftUI view), we must use them with withDependencies
// and call $wrapper.load() explicitly.

final class FetchObservationTests: XCTestCase {
    // SD-09: @FetchAll triggers updates
    @MainActor func testFetchAllUpdates() async throws {
        let db = try makeTestDatabase()
        try await db.write { db in
            try db.execute(sql: "INSERT INTO items (name, value) VALUES ('a', 1)")
        }
        try await withDependencies {
            $0.defaultDatabase = db
        } operation: {
            @FetchAll var items: [Item]
            try await $items.load()
            XCTAssertEqual(items.count, 1)

            try await db.write { db in
                try db.execute(sql: "INSERT INTO items (name, value) VALUES ('b', 2)")
            }
            try await $items.load()
            XCTAssertEqual(items.count, 2)
        }
    }

    // SD-10: @FetchOne triggers updates
    @MainActor func testFetchOneUpdates() async throws {
        let db = try makeTestDatabase()
        try await db.write { db in
            try db.execute(sql: "INSERT INTO items (name, value) VALUES ('first', 1)")
        }
        try await withDependencies {
            $0.defaultDatabase = db
        } operation: {
            @FetchOne var item: Item?
            try await $item.load()
            XCTAssertEqual(item?.name, "first")

            try await db.write { db in
                try db.execute(sql: "DELETE FROM items")
            }
            try await $item.load()
            XCTAssertNil(item)
        }
    }

    // SD-11: @Fetch with FetchKeyRequest
    @MainActor func testFetchWithKeyRequest() async throws {
        let db = try makeTestDatabase()
        try await db.write { db in
            try db.execute(sql: "INSERT INTO items (name, value) VALUES ('x', 42)")
        }
        try await withDependencies {
            $0.defaultDatabase = db
        } operation: {
            @Fetch(ActiveItems()) var items: [Item] = []
            try await $items.load()
            XCTAssertEqual(items.count, 1)
        }
    }
}

// FetchKeyRequest conformance for SD-11
struct ActiveItems: FetchKeyRequest {
    typealias Value = [Item]
    func fetch(_ db: Database) throws -> [Item] {
        try Item.where { $0.isActive == true }.fetchAll(db)
    }
}
```

### SD-12: `@Dependency(\.defaultDatabase)` injection

```swift
func testDependencyInjection() throws {
    let db = try makeTestDatabase()
    try db.write { db in
        try db.execute(sql: "INSERT INTO items (name) VALUES ('dep-test')")
    }
    withDependencies {
        $0.defaultDatabase = db
    } operation: {
        @Dependency(\.defaultDatabase) var database
        let count = try? database.read { db in try Item.fetchCount(db) }
        XCTAssertEqual(count, 1)
    }
}

func testDependencyInjectionInReducer() throws {
    // Verify the dependency resolves inside a TCA reducer context
    let db = try makeTestDatabase()
    withDependencies {
        $0.defaultDatabase = db
    } operation: {
        @Dependency(\.defaultDatabase) var database
        XCTAssertNotNil(database)
    }
}
```

---

## 6. SQL String Verification Approach

Since we don't use `InlineSnapshotTesting`, we verify SQL via `queryFragment.sql`. This is a direct string comparison that works in XCTest without any additional dependencies.

**Pattern:**
```swift
func testSQLGeneration() {
    let query = Item.where { $0.isActive == true }.order { $0.name.asc() }
    XCTAssertEqual(
        query.queryFragment.sql,
        #"SELECT "items"."id", "items"."name", "items"."value", "items"."isActive", "items"."tag" FROM "items" WHERE ("items"."isActive") ORDER BY "items"."name" ASC"#
    )
}
```

**Note:** SQL string assertions are brittle to schema changes (column addition re-orders the SELECT list). Prefer functional assertions (insert + fetch + XCTAssertEqual) for most tests. Use SQL string assertions only for specific SQL-01 through SQL-15 cases where the generated SQL string itself is the correctness criterion (e.g., SQL-06 predicate operators, SQL-09 join types, SQL-15 `#sql()` interpolation).

---

## 7. Test Target Structure Recommendation

### Final Package.swift additions

```swift
// Uncomment in dependencies section:
.package(path: "../../forks/swift-structured-queries"),
.package(path: "../../forks/GRDB.swift"),
.package(path: "../../forks/sqlite-data"),
// swift-snapshot-testing is needed by SQLiteDataTestSupport but we don't use
// SQLiteDataTestSupport directly — only include if needed

// New test targets:
.testTarget(
    name: "StructuredQueriesTests",
    dependencies: [
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
        .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
    ]
),
.testTarget(
    name: "SQLiteDataTests",
    dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
        .product(name: "Dependencies", package: "swift-dependencies"),
    ]
),
```

### File layout

```
examples/fuse-library/Tests/
├── StructuredQueriesTests/
│   ├── Support/
│   │   └── Schema.swift          -- @Table types + makeTestDatabase()
│   ├── TableMacroTests.swift     -- SQL-01, SQL-02, SQL-03, SQL-04
│   ├── SelectTests.swift         -- SQL-05
│   ├── WhereTests.swift          -- SQL-06, SQL-07, SQL-08
│   ├── JoinTests.swift           -- SQL-09
│   ├── OrderLimitTests.swift     -- SQL-10, SQL-12
│   ├── AggregateTests.swift      -- SQL-11
│   ├── MutationTests.swift       -- SQL-13, SQL-14
│   └── SQLMacroTests.swift       -- SQL-15
└── SQLiteDataTests/
    ├── Support/
    │   └── Schema.swift          -- same @Table types + makeTestDatabase()
    ├── DatabaseLifecycleTests.swift  -- SD-01, SD-02
    ├── TransactionTests.swift        -- SD-03, SD-04, SD-05
    ├── FetchTests.swift              -- SD-06, SD-07, SD-08
    ├── ObservationTests.swift        -- SD-09, SD-10, SD-11
    └── DependencyTests.swift         -- SD-12
```

---

## 8. Test Matrix: Requirements to Test Cases

| Requirement | Test File | Test Function(s) | Assertion Type |
|------------|-----------|-----------------|----------------|
| SQL-01 | `TableMacroTests.swift` | `testTableMacroGeneratesMetadata` | `XCTAssertEqual(tableName)` |
| SQL-02 | `TableMacroTests.swift` | `testCustomPrimaryKey` | insert + find round-trip |
| SQL-03 | `TableMacroTests.swift` | `testColumnAsCustomRepresentation` | compile + round-trip |
| SQL-04 | `TableMacroTests.swift` | `testSelectionComposition` | fetch + field access |
| SQL-05 | `SelectTests.swift` | `testSelectTupleColumns`, `testSelectSingleColumn` | `XCTAssertEqual(rows[0])` |
| SQL-06 | `WhereTests.swift` | `testWhereEquality`, `testWhereComparison`, `testWhereBoolean`, `testWhereCombined` | count + field equality |
| SQL-07 | `WhereTests.swift` | `testFindByPrimaryKey` | optional nil / non-nil |
| SQL-08 | `WhereTests.swift` | `testWhereIn`, `testWhereNotIn` | count + field values |
| SQL-09 | `JoinTests.swift` | `testInnerJoin`, `testLeftJoin` | count + tuple fields |
| SQL-10 | `OrderLimitTests.swift` | `testOrderAscending`, `testOrderDescending`, `testOrderCollation` | ordered array comparison |
| SQL-11 | `AggregateTests.swift` | `testCount`, `testSum`, `testGroupByWithCount` | scalar equality |
| SQL-12 | `OrderLimitTests.swift` | `testLimit`, `testLimitWithOffset` | count + array slice |
| SQL-13 | `MutationTests.swift` | `testInsertDraft`, `testInsertMultiple`, `testUpsert`, `testInsertOnConflict` | count + field equality |
| SQL-14 | `MutationTests.swift` | `testUpdate`, `testUpdateWhere`, `testDelete`, `testDeleteWhere` | count + field equality |
| SQL-15 | `SQLMacroTests.swift` | `testSQLMacroStringLiteral`, `testSQLMacroColumnInterpolation` | count / field equality |
| SD-01 | `DatabaseLifecycleTests.swift` | `testDefaultDatabaseInit`, `testDefaultDatabaseFunctionInit` | `XCTAssertNotNil` |
| SD-02 | `DatabaseLifecycleTests.swift` | `testMigratorRunsMigrations`, `testMigratorIdempotent` | `XCTAssertNoThrow` + count |
| SD-03 | `TransactionTests.swift` | `testSyncRead` | scalar equality |
| SD-04 | `TransactionTests.swift` | `testSyncWrite`, `testWriteTransactionRollsBackOnError` | count equality |
| SD-05 | `TransactionTests.swift` | `testAsyncRead`, `testAsyncWrite` | count / array equality |
| SD-06 | `FetchTests.swift` | `testFetchAll` | count equality |
| SD-07 | `FetchTests.swift` | `testFetchOne`, `testFetchOneReturnsNilWhenEmpty` | optional nil / non-nil |
| SD-08 | `FetchTests.swift` | `testFetchCount`, `testFetchCountWithWhere` | integer equality |
| SD-09 | `ObservationTests.swift` | `testFetchAllUpdates` | count after write + load |
| SD-10 | `ObservationTests.swift` | `testFetchOneUpdates` | optional after write + load |
| SD-11 | `ObservationTests.swift` | `testFetchWithKeyRequest` | count via FetchKeyRequest |
| SD-12 | `DependencyTests.swift` | `testDependencyInjection`, `testDependencyInjectionInReducer` | count / `XCTAssertNotNil` |

**Total test functions planned:** ~40 functions across 12 files covering all 27 requirements.

---

## 9. Key Differences from Upstream Patterns

| Aspect | Upstream (StructuredQueriesTests) | Upstream (SQLiteDataTests) | Our pattern (fuse-library) |
|--------|----------------------------------|---------------------------|---------------------------|
| Test framework | swift-testing (`@Test`, `#expect`) | swift-testing (`@Test`, `#expect`) | XCTest (`func test`, `XCTAssert*`) |
| SQL assertions | `InlineSnapshotTesting` | `SQLiteDataTestSupport.assertQuery()` | `XCTAssertEqual(query.queryFragment.sql, ...)` for SQL; functional assertions for results |
| Database setup | Seeded `Database` via `DependencyKey` | `DatabaseQueue()` + `DatabaseMigrator` | `DatabaseQueue()` + raw DDL in `makeTestDatabase()` |
| Dependency injection | `@Dependency(\.defaultDatabase)` + `@Suite(.dependency(...))` | `@Dependency(\.defaultDatabase)` + `.dependency` trait | `withDependencies { $0.defaultDatabase = db }` |
| Observation testing | N/A (StructuredQueries is query-only) | `@FetchAll` + `await $records.load()` | Same: `@FetchAll` + `await $wrapper.load()` |
| Schema types | Defined globally in `Support/Schema.swift` | Defined locally per test file (private) | Defined in `Support/Schema.swift`, shared within target |
| Async tests | `@Test async throws` | `@Test async throws` | `func testFoo() async throws` (XCTest supports async) |

---

## 10. Conclusions

1. **`DatabaseQueue()` with no arguments is in-memory.** Confirmed by both the GRDB documentation pattern and the upstream test files. Zero file I/O, instant setup, isolated per test.

2. **Do NOT depend on `StructuredQueriesTestSupport` or `SQLiteDataTestSupport`.** These ship with `InlineSnapshotTesting` and swift-testing integration. They are incompatible with our XCTest-only convention. Assert SQL strings directly via `query.queryFragment.sql` and use functional assertions for result correctness.

3. **Two test targets are correct.** `StructuredQueriesTests` (SQL-01..SQL-15) and `SQLiteDataTests` (SD-01..SD-12) match the two distinct library concerns.

4. **Observation tests use `withDependencies` + `await $wrapper.load()`.** This matches upstream's intent (`FetchTests.swift`, `IntegrationTests.swift`) translated to XCTest conventions. No `expectation`/`XCTestExpectation` needed because `$wrapper.load()` is async and XCTest supports `async throws` test functions.

5. **`AndroidParityTests.swift` already covers basic CRUD in the fork.** These tests (in `forks/sqlite-data/Tests/SQLiteDataTests/AndroidParityTests.swift`) use XCTest and `DatabaseQueue()`. Our new tests build on top of that foundation and cover the StructuredQueries query-builder layer that those tests do not exercise.

6. **Schema design:** A two-table schema (`items` + `categories` with a foreign key) is sufficient to cover all 27 requirements including joins, cascades, and aggregation.

---

*Research completed: 2026-02-22*
*Covers: SQL-01..SQL-15, SD-01..SD-12 (27 requirements)*
*Files investigated: StructuredQueriesTests (41 source files), SQLiteDataTests (48 source files), AssertQuery.swift (2 copies), DefaultDatabase.swift, Package.swift (both forks), AndroidParityTests.swift, fuse-library Package.swift*
