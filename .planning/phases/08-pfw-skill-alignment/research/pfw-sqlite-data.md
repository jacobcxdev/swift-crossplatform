# pfw-sqlite-data Canonical Patterns Research

Generated: 2026-02-23
Source: `/pfw-sqlite-data` skill invocation + PFW-AUDIT-RESULTS.md (H6, H7, H8, M7, M8, M9, M10)
Findings scope: 7 HIGH + 4 MEDIUM = 11 findings from the pfw-sqlite-data skill audit.

---

## Canonical Patterns

### imports

Always `import SQLiteData`. Never `import GRDB` in app or test code — GRDB is an internal implementation detail of SQLiteData.

```swift
// CORRECT
import SQLiteData

// WRONG — never do this in app or test code
import GRDB
```

### defaultDatabase()

Use `SQLiteData.defaultDatabase()` (not `DatabaseQueue(path:)`) to get a WAL-mode, multi-reader connection. Configuration is optional.

```swift
let database = try SQLiteData.defaultDatabase()
// or with config:
let database = try SQLiteData.defaultDatabase(configuration: configuration)
```

### bootstrapDatabase() — canonical shape

The function MUST be named exactly `bootstrapDatabase`. It is defined as a `mutating` method on `DependencyValues`. It calls `SQLiteData.defaultDatabase()`, builds a `DatabaseMigrator`, and assigns the result to `defaultDatabase`.

```swift
import Dependencies
import SQLiteData

extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif
        // Register migrations here...
        try migrator.migrate(database)
        defaultDatabase = database
    }
}
```

Rules:
- DO NOT name it anything other than `bootstrapDatabase`.
- DO NOT call `DatabaseQueue(path:)` or construct paths manually.
- DO NOT call `DatabaseQueue()` (in-memory) for production use.
- DO assign `defaultDatabase = database` at the end.

### bootstrapDatabase location — @main entry point

Invoke `prepareDependencies` + `bootstrapDatabase` in the `init()` of the `@main` App struct (or the equivalent cross-platform root entry point). This is the ONLY correct location.

```swift
@main struct MyApp: App {
    init() {
        prepareDependencies {
            try! $0.bootstrapDatabase()
        }
    }
    var body: some Scene { ... }
}
```

For a cross-platform project where `@main` is not a SwiftUI App struct, invoke it in the equivalent Swift entry point `init()` — NOT inside a View's `init()`.

Use `try!` only at the `@main` entry point because failure to open the database is unrecoverable at launch. Everywhere else use `withErrorReporting`.

### withErrorReporting for I/O errors

Use `withErrorReporting` (from IssueReporting, bundled with SQLiteData) instead of `try!` or `fatalError` for database I/O that happens after launch.

```swift
withErrorReporting {
    try database.write { db in
        try Note.upsert { draft }.execute(db)
    }
}
```

### #sql macro — DDL (migrations)

Use `#sql("""...""").execute(db)` for ALL SQL strings in migrations. Do NOT use `db.execute(sql:)`.

```swift
migrator.registerMigration("Create 'notes' table") { db in
    try #sql("""
        CREATE TABLE "notes" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            "title" TEXT NOT NULL DEFAULT '',
            "body" TEXT NOT NULL DEFAULT '',
            "category" TEXT NOT NULL DEFAULT 'general',
            "createdAt" REAL NOT NULL DEFAULT 0
        ) STRICT
        """)
        .execute(db)
}
```

### #sql macro — DML queries (SELECT with interpolation)

Use `#sql` for custom SELECT queries that need compile-time checking or safe value interpolation:

```swift
// With type inference
let results = try #sql(
    """
    SELECT \(Item.columns)
    FROM \(Item.self)
    WHERE \(Item.value) > \(bind: 10)
    ORDER BY \(Item.value)
    """,
    as: Item.self
).fetchAll(db)

// For @Selection aggregation
let results = try #sql(
    """
    SELECT "isActive", count(*) AS "itemCount"
    FROM "items"
    GROUP BY "isActive"
    ORDER BY "isActive"
    """,
    as: ItemSummary.self
).fetchAll(db)
```

### @FetchAll / @FetchOne — SwiftUI views

Use property wrappers directly in SwiftUI views for live-updating, observed data:

```swift
struct NotesView: View {
    @FetchAll var notes: [Note]
    // with query:
    @FetchAll(Note.where(\.isCompleted)) var completedNotes
    // omit explicit type when query is provided

    @FetchOne(Note.count()) var noteCount = 0
    @FetchOne var latestNote: Note?
}
```

Rules:
- `@FetchAll` / `@FetchOne` are for SwiftUI views only.
- In `@Observable` models, add `@ObservationIgnored` before `@FetchAll`/`@FetchOne`.
- Provide a default value for non-optional `@FetchOne` properties.
- Omit the explicit type annotation when a query argument is provided.

### @FetchAll / @FetchOne — @Observable models

```swift
@Observable final class NotesModel {
    @ObservationIgnored
    @FetchAll var notes: [Note]

    @ObservationIgnored
    @FetchOne(Note.count()) var noteCount = 0
}
```

### Dynamic queries

When the query depends on runtime state, initialise with `.none` and load in `.task`:

```swift
struct NotesView: View {
    @FetchAll(Note.none) var notes
    let category: String

    var body: some View {
        List(notes) { Text($0.title) }
            .task(id: category) {
                await withErrorReporting {
                    try await $notes.load(
                        Note.where { $0.category.eq(category) },
                        animation: .default
                    )
                }
            }
    }
}
```

### .dependencies trait for test suites

Add `DependenciesTestSupport` to the test target, then use the `.dependencies` trait on every `@Suite` that touches the database:

```swift
import DependenciesTestSupport

@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct NoteTests {
    @Test func addNote() async throws { ... }
}
```

Rules:
- Use `try` (not `try!`) inside the `.dependencies` closure — it already has a throwing context.
- Seed data inside the same `.dependencies` closure after bootstrapping:
  ```swift
  @Suite(
      .dependencies {
          $0.uuid = .incrementing
          try $0.bootstrapDatabase()
          try $0.defaultDatabase.write { db in
              try db.seed {
                  Note(id: -1, title: "Seed note", ...)
              }
          }
      }
  )
  ```
- Use negative integer IDs (`UUID(-1)`, `-1`, etc.) for seeded test data to avoid collisions with feature code.
- DO NOT share seed helpers between tests and app/preview code.

### Package.swift test target

```swift
.testTarget(
    name: "DatabaseTests",
    dependencies: [
        .product(name: "DependenciesTestSupport", package: "swift-dependencies")
    ]
)
```

---

## Current State

### H6: `import GRDB` in app/test code

| File | Line | Problem |
|------|------|---------|
| `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift` | 3 | `import GRDB` |
| `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` | 2 | `import GRDB` |
| `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift` | 3 | `import GRDB` |

### H7: No @FetchAll/@FetchOne in DatabaseView

`DatabaseFeature.swift:72-83` — `DatabaseView` polls the database once on `.onAppear` via two sequential `database.read` calls dispatched through the TCA reducer. The notes array goes stale after the initial load; the view does not react to background database changes. No `@FetchAll` or `@FetchOne` property wrappers are used anywhere in `DatabaseView`.

Relevant code (`DatabaseFeature.swift:72-83`):
```swift
case .onAppear:
    state.isLoading = true
    return .run { send in
        let notes = try await database.read { db in
            try Note.all.order { $0.createdAt.desc() }.fetchAll(db)
        }
        let count = try await database.read { db in
            try Note.all.fetchCount(db)
        }
        await send(.notesLoaded(notes))
        await send(.noteCountLoaded(count))
    }
```

### H8: `try!` in production non-entry-point code

`FuseApp.swift:24-29` — `bootstrapDatabase()` is invoked inside `prepareDependencies` in `FuseAppRootView.init()` using a do/catch + `reportIssue` pattern. This is acceptable (it uses `reportIssue` not `try!`), but the location is wrong: it is a SwiftUI `View`'s `init`, not a `@main` App struct `init`.

Relevant code (`FuseApp.swift:23-29`):
```swift
/* SKIP @bridge */public init() {
    prepareDependencies {
        do {
            try $0.bootstrapDatabase()
        } catch {
            reportIssue(error)
        }
    }
}
```

Note: The original audit (H8) flagged `try! $0.bootstrapDatabase()` but the current file uses `reportIssue`. The location issue (M10) remains: it is in `FuseAppRootView.init()` (a View), not in a `@main` entry point `init()`.

### M7: Raw `db.execute(sql:)` instead of `#sql` macro

| File | Lines | Problem |
|------|-------|---------|
| `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift` | 28-36 | `try db.execute(sql: "CREATE TABLE IF NOT EXISTS note ...")` |
| `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` | 317-326 | `try db.execute(sql: "CREATE TABLE IF NOT EXISTS note ...")` in `createMigratedDatabase()` |
| `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` | 350 | `try db.execute(sql: "INSERT INTO note ...")` |
| `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift` | 26-33 | `try db.execute(sql: "CREATE TABLE ...")` in `setupSchema()` |
| `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift` | 69-71 | `try db.execute(sql: "CREATE TABLE ...")` in `testDatabaseInit()` |
| `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift` | 98-107 | `try db.execute(sql: "CREATE TABLE ...")` in `testDatabaseMigrator()` |
| `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift` | 41-55 | `try db.execute(sql: ...)` ×2 in `makeDatabase()` |

### M8: No `.dependencies` trait in test suites

All test suites in both `DatabaseTests` and `FuseAppIntegrationTests` are bare `XCTestCase` subclasses. They construct `DatabaseQueue()` inline with helper methods (`makeDatabase()`, `makeSeededDatabase()`, `createMigratedDatabase()`) rather than using `.dependencies { try $0.bootstrapDatabase() }`. This bypasses the dependency injection mechanism entirely.

| File | Pattern used |
|------|-------------|
| `SQLiteDataTests.swift:36-40` | `private func makeDatabase() throws -> DatabaseQueue` |
| `SQLiteDataTests.swift:44-56` | `private func makeSeededDatabase() throws -> DatabaseQueue` |
| `StructuredQueriesTests.swift:38-58` | `private func makeDatabase() throws -> DatabaseQueue` |
| `FuseAppIntegrationTests.swift:314-328` | `private func createMigratedDatabase() throws -> DatabaseQueue` |

### M9: `DatabaseQueue(path:)` instead of `SQLiteData.defaultDatabase()`

`DatabaseFeature.swift:16-21`:
```swift
let path = URL.applicationSupportDirectory.appending(component: "fuse-app.sqlite").path
try FileManager.default.createDirectory(
    at: URL.applicationSupportDirectory,
    withIntermediateDirectories: true
)
let database = try DatabaseQueue(path: path)
```

Manual path construction + `DatabaseQueue(path:)` bypasses WAL mode configuration, multi-reader setup, and all other opinionated defaults that `SQLiteData.defaultDatabase()` provides.

### M10: `bootstrapDatabase` invoked in View init, not @main

`FuseApp.swift:23` — `prepareDependencies` is called inside `FuseAppRootView.init()`, which is a SwiftUI `View`. This is wrong. The correct location is the `@main` App struct's `init()`. In this cross-platform project there may not be a traditional `@main` struct — the entry point mechanism needs investigation — but the bootstrap must not live in a View.

---

## Required Changes

### File: `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`

#### Change 1 — Remove `import GRDB` (H6)

Remove line 3:
```swift
// DELETE this line:
import GRDB
```

Also remove line 12 which exists only because of the GRDB import:
```swift
// DELETE this line — it exists only to paper over the GRDB import:
extension DatabaseQueue: @unchecked @retroactive Sendable {}
```

#### Change 2 — Replace `DatabaseQueue(path:)` with `SQLiteData.defaultDatabase()` (M9)

Replace lines 14-21 (the entire `bootstrapDatabase` body before the migrator) with:
```swift
extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1") { db in
            try #sql("""
                CREATE TABLE "note" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    "title" TEXT NOT NULL DEFAULT '',
                    "body" TEXT NOT NULL DEFAULT '',
                    "category" TEXT NOT NULL DEFAULT 'general',
                    "createdAt" REAL NOT NULL DEFAULT 0
                ) STRICT
                """)
                .execute(db)
        }
        try migrator.migrate(database)
        defaultDatabase = database
    }
}
```

#### Change 3 — Replace `db.execute(sql:)` with `#sql` in migration (M7)

Within the migration registered in `bootstrapDatabase`, replace:
```swift
// BEFORE
try db.execute(sql: """
    CREATE TABLE IF NOT EXISTS note (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT 'general',
        createdAt REAL NOT NULL DEFAULT 0
    )
    """)
```
with:
```swift
// AFTER
try #sql("""
    CREATE TABLE "note" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "title" TEXT NOT NULL DEFAULT '',
        "body" TEXT NOT NULL DEFAULT '',
        "category" TEXT NOT NULL DEFAULT 'general',
        "createdAt" REAL NOT NULL DEFAULT 0
    ) STRICT
    """)
    .execute(db)
```

Note: Remove `IF NOT EXISTS` — migrations run exactly once; the guard is unnecessary and masks bugs. Add `STRICT` for type enforcement. Quote all identifiers.

#### Change 4 — Add @FetchAll/@FetchOne to DatabaseView (H7)

`DatabaseView` currently receives its data from a TCA `Store`. The @FetchAll/@FetchOne wrappers are SwiftUI property wrappers that belong directly on SwiftUI views. The fix is to move note fetching from the reducer into the view:

Add `@FetchAll` and `@FetchOne` to `DatabaseView` and remove the polling-via-reducer pattern:

```swift
struct DatabaseView: View {
    let store: StoreOf<DatabaseFeature>

    @FetchAll(Note.order { $0.createdAt.desc() }) var notes
    @FetchOne(Note.count()) var noteCount = 0

    private let categories = ["all", "general", "work", "personal"]

    var body: some View {
        List {
            Section("Filter") {
                // ... picker unchanged ...
            }
            Section("Notes (\(noteCount))") {
                // Use `notes` from @FetchAll directly, not from store.notes
                ForEach(filteredNotes) { note in ... }
            }
        }
        .task { store.send(.onAppear) }
    }

    private var filteredNotes: [Note] {
        if store.selectedCategory == "all" { return notes }
        return notes.filter { $0.category == store.selectedCategory }
    }
}
```

Remove from `DatabaseFeature.State`: `var notes`, `var noteCount`, `var isLoading`.
Remove from `DatabaseFeature.Action`: `notesLoaded`, `noteCountLoaded`.
Remove the `.onAppear` `database.read` calls (or simplify `.onAppear` to only handle non-observable setup).
Remove `@Dependency(\.defaultDatabase)` from the reducer if the only uses were the read queries now handled by `@FetchAll`/`@FetchOne`.

Keep `addNoteTapped`, `deleteNote`, `categoryFilterChanged`, `noteAdded`, `noteDeleted` in the reducer — writes still go through `database.write`.

#### Change 5 — Wrap Effect.run errors with reportIssue (M15)

In every `Effect.run` closure in `DatabaseFeature`, add error handling. The current `.run { send in try await ... }` propagates thrown errors silently. Wrap with do/catch:

```swift
return .run { send in
    await withErrorReporting {
        let note = try await database.write { db in
            try Note.insert { Note.Draft(...) }.execute(db)
            ...
        }
        await send(.noteAdded(note))
    }
}
```

### File: `examples/fuse-app/Sources/FuseApp/FuseApp.swift`

#### Change 6 — Move bootstrapDatabase to correct entry point (M10)

The project uses `FuseAppRootView` as the cross-platform root, which is a SwiftUI `View`. `prepareDependencies` must not be called in a View's `init`. Locate the `@main` entry point (the iOS App struct or Android equivalent) and move `prepareDependencies` there.

If the iOS `@main` entry point is in a platform-specific file, add:
```swift
@main struct FuseAppMain: App {
    init() {
        prepareDependencies {
            try! $0.bootstrapDatabase()
        }
    }
    var body: some Scene {
        WindowGroup { FuseAppRootView() }
    }
}
```

Remove the `prepareDependencies` call from `FuseAppRootView.init()` entirely.

If the project's cross-platform architecture makes a standard `@main` struct impossible, move the call to the earliest Swift execution point available (e.g. `FuseAppDelegate.onInit()` or `onLaunch()`). Do NOT leave it in a View.

### File: `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift`

#### Change 7 — Remove `import GRDB` (H6)

Remove line 2:
```swift
// DELETE
import GRDB
```

#### Change 8 — Replace inline DatabaseQueue with .dependencies trait (M8)

Migrate `DatabaseFeatureTests` from XCTest + manual `createMigratedDatabase()` to Swift Testing with `.dependencies` trait:

```swift
import DependenciesTestSupport
import Testing

@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
        try $0.defaultDatabase.write { db in
            // Seed test data here if needed
        }
    }
)
struct DatabaseFeatureTests {
    @Test func addNote() async throws {
        // Use @Dependency(\.defaultDatabase) or construct store with withDependencies
    }
}
```

Remove `createMigratedDatabase()` helper method entirely.
Replace `try! createMigratedDatabase()` call sites.
Replace `try db.execute(sql: "INSERT INTO note ...")` (line 350) with `try db.seed { Note(...) }` or a typed insert.

#### Change 9 — Replace `db.execute(sql:)` DDL with `#sql` (M7)

`FuseAppIntegrationTests.swift:317-326` — Replace:
```swift
// BEFORE
try db.execute(sql: """
    CREATE TABLE IF NOT EXISTS note (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ...
    )
    """)
```
with a call to `bootstrapDatabase()` via the `.dependencies` trait (this eliminates the need for manual DDL in tests entirely — the migrator handles it).

`FuseAppIntegrationTests.swift:350` — Replace:
```swift
// BEFORE
try db.execute(sql: "INSERT INTO note (id, title, body, category, createdAt) VALUES (42, 'Test', '', 'general', 0)")
```
with:
```swift
// AFTER
try Note.insert {
    Note.Draft(id: 42, title: "Test", body: "", category: "general", createdAt: 0)
}.execute(db)
```

### File: `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift`

#### Change 10 — Remove `import GRDB` (H6)

Remove line 3:
```swift
// DELETE
import GRDB
```

#### Change 11 — Replace inline DatabaseQueue helpers with .dependencies trait (M8)

Migrate from `XCTestCase` + `makeDatabase()` / `makeSeededDatabase()` helpers to Swift Testing `@Suite` with `.dependencies` trait. Each suite that exercises a schema needs `bootstrapDatabase()` called through the trait:

```swift
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
        try $0.defaultDatabase.write { db in
            try db.seed {
                DataItem(id: -1, name: "alpha", value: 5, isActive: true)
                DataItem(id: -2, name: "beta", value: 15, isActive: true)
                DataItem(id: -3, name: "gamma", value: 25, isActive: false)
            }
        }
    }
)
struct SQLiteDataTests { ... }
```

Remove `makeDatabase()`, `makeSeededDatabase()` entirely.

#### Change 12 — Replace `db.execute(sql:)` DDL with `#sql` (M7)

`SQLiteDataTests.swift:26-33` (setupSchema), `SQLiteDataTests.swift:69-71`, `SQLiteDataTests.swift:98-107` — all `db.execute(sql: "CREATE TABLE ...")` calls must be replaced with `#sql(...).execute(db)`. Since these will be handled by `bootstrapDatabase()` via the `.dependencies` trait, remove the inline DDL entirely.

#### Change 13 — Fix infix `==` in `.where` closure (H5)

`SQLiteDataTests.swift:219`:
```swift
// BEFORE
try DataItem.where { $0.name == "nonexistent" }.limit(1).fetchOne(db)

// AFTER
try DataItem.where { $0.name.eq("nonexistent") }.limit(1).fetchOne(db)
```

### File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

#### Change 14 — Replace `db.execute(sql:)` DDL with `#sql` (M7)

`StructuredQueriesTests.swift:41-55` — `makeDatabase()` calls `db.execute(sql:)` twice. Replace with `#sql(...).execute(db)` or, once this test suite is migrated to Swift Testing, replace with `.dependencies { try $0.bootstrapDatabase() }`.

```swift
// BEFORE
try db.execute(sql: """
    CREATE TABLE "categories" ( ... )
    """)
try db.execute(sql: """
    CREATE TABLE "items" ( ... )
    """)

// AFTER — if keeping XCTest helper:
try #sql("""
    CREATE TABLE "categories" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "name" TEXT NOT NULL DEFAULT ''
    ) STRICT
    """).execute(db)
try #sql("""
    CREATE TABLE "items" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "name" TEXT NOT NULL DEFAULT '',
        "value" INTEGER NOT NULL DEFAULT 0,
        "isActive" BOOLEAN NOT NULL DEFAULT 1,
        "categoryId" INTEGER REFERENCES "categories"("id")
    ) STRICT
    """).execute(db)
```

#### Change 15 — Fix infix `>` in `.where` closures (H5)

`StructuredQueriesTests.swift:198`:
```swift
// BEFORE
try Item.where { $0.value > 10 && $0.isActive }

// AFTER
try Item.where { $0.value.gt(10) && $0.isActive }
```

`StructuredQueriesTests.swift:443`:
```swift
// BEFORE
try Item.where { $0.value > 20 }

// AFTER
try Item.where { $0.value.gt(20) }
```

`StructuredQueriesTests.swift:447`:
```swift
// BEFORE
try Item.where { $0.value == 999 }

// AFTER
try Item.where { $0.value.eq(999) }
```

---

## #sql Macro Specifics

### What #sql IS for

1. **DDL in migrations** — `CREATE TABLE`, `ALTER TABLE`, `CREATE INDEX`. This is the primary use case; every migration body must use `#sql`.
2. **Custom SELECT queries** that cannot be expressed with the StructuredQueries builder API (e.g. complex GROUP BY with aggregates used with `@Selection`).
3. **Safe value interpolation** — `\(bind: value)` interpolates a bound parameter (not inline SQL), `\(TableType.columnName)` interpolates a column reference safely.

### What #sql IS NOT for

- Queries that can be expressed with the StructuredQueries builder API (`.where`, `.order`, `.join`, `.select`, `.group`, `.limit`). Use the builder instead.
- Raw `INSERT` / `UPDATE` / `DELETE` DML — use `Table.insert { }`, `Table.update { }`, `Table.delete()`, `Table.upsert { }`.
- Test setup DDL when you are using `.dependencies { try $0.bootstrapDatabase() }` — bootstrapDatabase already runs the migrator which runs `#sql` internally. Do not duplicate DDL in tests.

### #sql syntax rules

```swift
// Execute DDL — always call .execute(db)
try #sql("""
    CREATE TABLE "tableName" (
        "columnName" TYPE CONSTRAINTS
    ) STRICT
    """)
    .execute(db)

// Query returning typed rows — append .fetchAll(db), .fetchOne(db), .fetchCount(db)
let rows = try #sql(
    """
    SELECT \(Table.columns)
    FROM \(Table.self)
    WHERE \(Table.column) > \(bind: value)
    """,
    as: Table.self
).fetchAll(db)

// Query returning @Selection type
let summaries = try #sql(
    """
    SELECT "col", count(*) AS "aliasMatchingSelectionProperty"
    FROM "table"
    GROUP BY "col"
    """,
    as: MySelection.self
).fetchAll(db)
```

### DDL conventions enforced by #sql pattern

- Always use `STRICT` tables (enforces column types at SQLite level).
- Always quote table names and column names with double-quotes.
- Use `NOT NULL` on every non-nullable column.
- Use `ON CONFLICT REPLACE` on `NOT NULL` columns in `ALTER TABLE ADD COLUMN` migrations (new tables do not need this).
- Use `DEFAULT (uuid())` for UUID primary keys; use `AUTOINCREMENT` for integer primary keys.
- Remove `IF NOT EXISTS` from `CREATE TABLE` in migrations — the migrator tracks which migrations have run.
- Add `ON DELETE CASCADE` on foreign key columns where appropriate.

---

## Ordering Dependencies

The following changes have ordering constraints. Execute them in this sequence:

### Phase A — Must be done first (unblocks everything)

1. **Remove `import GRDB`** from all three files (H6). This is the foundation; other fixes may introduce compilation errors until GRDB is removed.
   - `DatabaseFeature.swift:3`
   - `FuseAppIntegrationTests.swift:2`
   - `SQLiteDataTests.swift:3`

2. **Remove `extension DatabaseQueue: @unchecked @retroactive Sendable {}`** from `DatabaseFeature.swift:12` — this exists only to suppress a GRDB warning and is no longer needed.

### Phase B — Database setup (after Phase A)

3. **Replace `DatabaseQueue(path:)` with `SQLiteData.defaultDatabase()`** in `DatabaseFeature.swift` (M9). This is the correct production database connection. Do this before touching migrations.

4. **Replace `db.execute(sql:)` with `#sql` in `bootstrapDatabase` migration** in `DatabaseFeature.swift` (M7). Do this immediately after step 3 since you are rewriting the function body anyway. A single edit covers both M9 and M7 for this file.

5. **Move `prepareDependencies` to `@main` entry point** (M10). This can be done in parallel with steps 3-4 but must be done before step 6 (because the test suite `.dependencies` trait depends on the same `bootstrapDatabase()` function being well-formed).

### Phase C — Test migration (after Phase B)

6. **Add `.dependencies { try $0.bootstrapDatabase() }` trait to `DatabaseFeatureTests`** in `FuseAppIntegrationTests.swift` (M8). This requires that `bootstrapDatabase()` is correct (step 4) before it can be used in tests.

7. **Remove `createMigratedDatabase()` and `db.execute(sql:)` DDL in `FuseAppIntegrationTests.swift`** (M7). These are redundant once step 6 is done.

8. **Migrate `SQLiteDataTests` and `StructuredQueriesTests` to Swift Testing `@Suite` with `.dependencies` trait** (M8). Remove all `makeDatabase()` / `makeSeededDatabase()` helpers and inline DDL.

### Phase D — View observation (after Phase B, can be parallel with Phase C)

9. **Add `@FetchAll` / `@FetchOne` to `DatabaseView`** (H7). This requires that `SQLiteData.defaultDatabase()` is correctly wired (step 3) so the database dependency resolves at view render time.

10. **Remove polling state from `DatabaseFeature.State` and `DatabaseFeature` reducer** — `notes`, `noteCount`, `isLoading`, `notesLoaded`, `noteCountLoaded` — after step 9 is complete and view compilation is verified.

### Phase E — Error handling (after Phase D)

11. **Wrap `Effect.run` database calls with `withErrorReporting`** (M15). Do this last; it is a contained change per action case and has no ordering dependency on other SQLiteData changes, but it is safest to do after the database connection and observation patterns are correct.

### Summary order

```
A1: Remove import GRDB (3 files)
A2: Remove DatabaseQueue Sendable extension
B3: defaultDatabase() in bootstrapDatabase
B4: #sql in migration body
B5: Move prepareDependencies to @main
C6: .dependencies trait in DatabaseFeatureTests
C7: Remove createMigratedDatabase() + raw DDL from integration tests
C8: Migrate SQLiteDataTests + StructuredQueriesTests to @Suite
D9: Add @FetchAll/@FetchOne to DatabaseView
D10: Remove polling state from DatabaseFeature
E11: withErrorReporting in Effect.run closures
```
