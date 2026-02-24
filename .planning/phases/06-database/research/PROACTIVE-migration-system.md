# Proactive Risk Analysis: GRDB DatabaseMigrator on Android

**Date:** 2026-02-22
**Scope:** `forks/GRDB.swift/GRDB/Migration/` — migration state storage, platform guards, failure modes, rollback, StructuredQueries integration

---

## 1. How Migration State Is Stored

**Bottom line: pure SQLite, no Apple platform APIs.**

`DatabaseMigrator` tracks applied migrations in a custom SQLite table called `grdb_migrations`:

```sql
CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)
```

This table is created on first migration run inside `runMigrations(_:upTo:)`:

```swift
// DatabaseMigrator.swift:615
try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
```

Every time a migration succeeds, its string identifier is inserted:

```swift
// Migration.swift:113
try db.execute(literal: "INSERT INTO grdb_migrations (identifier) VALUES (\(identifier))")
```

No `UserDefaults`, no Keychain, no plist, no NSUserActivity — migration state is entirely self-contained in the SQLite file. **This is safe on Android.**

---

## 2. Platform Conditionals in Migration Code

**The migration files themselves have zero platform guards.**

`DatabaseMigrator.swift` opens with `#if canImport(Combine)` only for the Combine publisher extension. The core migration logic — registration, running, state tracking, schema comparison — has no `#if os(Android)`, `#if os(Linux)`, or any other platform conditional.

`Migration.swift` has no platform conditionals at all.

The only Android-specific change in the GRDB fork (`36dba72a8`) touched:
- `GRDB/Core/DispatchQueueActor.swift` — `@unchecked Sendable` workaround
- `GRDB/Core/StatementAuthorizer.swift` — `import Android` for C stdlib
- `GRDB/Core/Support/Foundation/NS*.swift` — excluded `NSData`, `NSString`, `NSURL`, etc. on Android (same treatment as Linux)

None of these changes touch the migration system. **Migration code is platform-neutral.**

---

## 3. The `NSTemporaryDirectory()` Risk: `hasSchemaChanges(_:)` / `eraseDatabaseOnSchemaChange`

**This is the single concrete Android risk in the migration system.**

`hasSchemaChanges(_:)` creates a temporary on-disk database to compare schemas:

```swift
// DatabaseMigrator.swift:464-468
let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
defer {
    try? FileManager().removeItem(at: tmpURL)
}
let tmpDatabase = try DatabaseQueue(path: tmpURL.path, configuration: tmpConfig)
```

Three sub-risks:

### 3a. `NSTemporaryDirectory()` on Android
`NSTemporaryDirectory()` is a Foundation function. On Android, Swift Foundation is available (the open-source swift-foundation), so this call will not fail to compile. However, it returns `/tmp` on Linux/Android, which may not be writable in all Android sandbox configurations. On Android, the correct temp path is typically obtained from the app context (`getCacheDir()`). **The path returned may be correct but is not guaranteed to be the app's sandboxed temp directory.**

### 3b. `ProcessInfo.processInfo.globallyUniqueString`
This returns a unique string combining host, PID, and timestamp. `ProcessInfo` is available on Android via swift-foundation. Low risk — it will work but worth noting it depends on Foundation availability.

### 3c. `FileManager().removeItem(at:)`
Standard Foundation file operation. Available on Android. The `try?` means a cleanup failure is silently swallowed. Low risk.

**Trigger condition:** This code only runs when `hasSchemaChanges(_:)` is called, which only happens when `eraseDatabaseOnSchemaChange = true`. This flag is documented as a development-only tool:

```swift
// DatabaseMigrator.swift:100-109
/// - warning: This flag can destroy your precious users' data!
// ...
/// It is recommended to not ship it in the distributed application...
/// Use the `DEBUG` compilation condition:
```

**Verdict:** If `eraseDatabaseOnSchemaChange` is only enabled under `#if DEBUG`, the temporary database path issue is irrelevant in production. However, if it or `hasSchemaChanges(_:)` is called in production Android builds, the temp path behavior must be verified.

---

## 4. Rollback Behavior on Partial Failure

**Rollback is solid. Each migration is individually transactional.**

From `Migration.swift`, every migration runs inside an explicit SQLite transaction:

```swift
// Migration.swift:57-61 (immediate foreign key path)
private func runWithImmediateForeignKeysChecks(_ db: Database, mergedIdentifiers: Set<String>) throws {
    try db.inTransaction(.immediate) {
        try migrate(db, mergedIdentifiers)
        try updateAppliedIdentifier(db)
        return .commit
    }
}
```

`updateAppliedIdentifier` (which writes to `grdb_migrations`) is inside the same transaction as the migration body. If the migration closure throws, the transaction is rolled back — the schema changes AND the `grdb_migrations` entry are both undone atomically. Tested and verified in `DatabaseMigratorTests.testMigrationFailureTriggersRollback()`:

```
// The first migration should be committed.
// The second migration should be rollbacked.
```

All three foreign-key check modes (`deferred`, `immediate`, `disabled`) follow this same transactional pattern. **Rollback works correctly on Android because it is pure SQLite semantics with no platform-specific code.**

**What happens to later migrations after a failure:** `runMigrations` iterates sequentially and throws on the first failure, stopping all subsequent migrations. The database is left at the last successfully committed migration. This is correct behavior.

---

## 5. File System Operations During Migration

Two file system operations occur in the migration system:

### 5a. Temporary database for schema comparison (already discussed in §3)
Only triggered by `hasSchemaChanges` / `eraseDatabaseOnSchemaChange`.

### 5b. `erase()` — the SQLite backup API
When `eraseDatabaseOnSchemaChange = true` and schema changes are detected, `migrate(_:upTo:)` calls `db.erase()`:

```swift
// DatabaseMigrator.swift:653-655
if needsErase {
    try db.erase()
}
```

`Database.erase()` (non-SQLCipher path) uses the SQLite online backup API to restore from a fresh empty `DatabaseQueue()`:

```swift
// Database.swift:1885
try DatabaseQueue().backup(to: self)
```

This calls `sqlite3_backup_init` / `sqlite3_backup_step` / `sqlite3_backup_finish` — pure C SQLite API with no platform dependencies. **This is safe on Android.**

The SQLCipher path (`#if SQLITE_HAS_CODEC`) uses `DROP TABLE` in a transaction instead. Not relevant to this project unless SQLCipher is used.

**No WAL checkpointing, no file renaming, no `rename(2)` syscalls happen in the migration path.** WAL management is a concern of `DatabasePool` open/close, not migrations.

---

## 6. StructuredQueries Migration Support

**StructuredQueries has no migration system. It is GRDB's responsibility entirely.**

The `swift-structured-queries` fork contains:
- No `DatabaseMigrator` type or equivalent
- No migration registration or tracking
- No `@Table`-to-schema generation for migrations

The "migration guides" in `StructuredQueriesCore/Documentation.docc/Articles/MigrationGuides/` are Swift API migration guides (upgrading from one version of the library to another), not database schema migrations.

The `TableDefinition.swift` in StructuredQueries generates SQL fragments for query building, not for DDL schema creation within migrations.

**Implication:** The app code must manually write `db.create(table:)` calls inside `registerMigration` closures. StructuredQueries provides no automatic schema-from-struct generation. This is a design gap to be aware of — if a `@Table` struct changes, there is no automatic migration generated; the developer must write it.

---

## 7. sqlite-data Fork Integration

The `sqlite-data` fork re-exports `DatabaseMigrator` directly:

```swift
// sqlite-data/Sources/SQLiteData/Internal/Exports.swift:7
@_exported import struct GRDB.DatabaseMigrator
```

The `defaultDatabase()` function in `DefaultDatabase.swift` has **two Android risks**:

### 7a. `FileManager.default.url(for: .applicationSupportDirectory, ...)`
```swift
// DefaultDatabase.swift:26-32
let applicationSupportDirectory = try FileManager.default.url(
  for: .applicationSupportDirectory,
  in: .userDomainMask,
  appropriateFor: nil,
  create: true
)
```
`.applicationSupportDirectory` on Android via swift-foundation may return an incorrect or unexpected path (typically `/data/user/0/<package>/files` is the Android equivalent, accessed via the Android context object). The standard `FileManager` search path API may not map correctly to Android's sandboxed storage model. **This needs testing and likely needs an Android-specific path override.**

### 7b. `NSTemporaryDirectory()` in preview/test path
```swift
// DefaultDatabase.swift:38
path: "\(NSTemporaryDirectory())\(UUID().uuidString).db",
```
Same issue as §3a — the temp path may not be correct on Android, though for tests this is lower risk since `/tmp` often works in development emulator contexts.

### 7c. CloudKit integration is Apple-only
The CloudKit sync engine (`SyncEngine.swift`, `PrimaryKeyMigration.swift`) uses `CKSyncEngine`, which does not exist on Android. These must be guarded. The `sqlite-data` fork has not yet been examined for `#if canImport(CloudKit)` guards — this is a separate concern from migration but the `PrimaryKeyMigration` helper (which does schema migration work for UUID primary keys) will need to be excluded or redesigned for Android.

---

## 8. No Android-Specific Tests

The GRDB fork contains `Tests/GRDBTests/DatabaseMigratorTests.swift` with 20+ test functions. None have Android-specific variants or platform guards. The tests cover:
- Empty migrator (sync, async, publisher)
- Sequential migration application
- Failure and rollback
- Foreign key check modes
- `eraseDatabaseOnSchemaChange`
- Merged migrations

These tests only run on Apple platforms (XCTest with `GRDBTestCase`). **There are no Android migration tests.** The correctness of GRDB migration behavior on Android is entirely unvalidated by automated tests.

---

## 9. Risk Summary

| Risk | Severity | Trigger | Notes |
|------|----------|---------|-------|
| `NSTemporaryDirectory()` returns wrong path on Android | Medium | `hasSchemaChanges()` / `eraseDatabaseOnSchemaChange = true` | Compile-safe; runtime path may be wrong. Debug-only feature. |
| `FileManager.url(for: .applicationSupportDirectory)` wrong on Android | High | `defaultDatabase()` in sqlite-data | Production code path. DB file will open at unexpected location or fail. |
| `NSTemporaryDirectory()` in `defaultDatabase()` preview/test path | Low | Preview/test context on Android | Only affects non-production contexts. |
| CloudKit `PrimaryKeyMigration` not guarded for Android | Medium | Any use of `sqlite-data` CloudKit APIs | Must be excluded on Android; CKSyncEngine does not exist. |
| No Android migration tests | Medium | Always | GRDB migration behavior on Android is untested. |
| `grdb_migrations` table name collision | Low | App defines own table named `grdb_migrations` | User naming collision, not platform-specific. |

---

## 10. Recommendations

1. **Verify `applicationSupportDirectory` on Android** before using `defaultDatabase()` from sqlite-data. Consider providing an Android-specific `defaultDatabase(path:)` override that takes the path from the Android context (passed in via JNI or a Skip bridge).

2. **Do not use `eraseDatabaseOnSchemaChange` in production** (already documented upstream). On Android, the temp database it creates may land in `/tmp` rather than the app's sandboxed temp directory. In `#if DEBUG` builds, test this path explicitly.

3. **Write Android migration integration tests** in `examples/fuse-library`. The GRDB fork migration code is platform-neutral Swift/SQLite, so it should work, but this is unverified. A test that: opens a GRDB database, registers and runs a migration, kills and reopens the database, then verifies the migration was not re-applied, would give confidence.

4. **Guard CloudKit types in sqlite-data** with `#if canImport(CloudKit)`. `PrimaryKeyMigration` and `SyncEngine` must not compile on Android.

5. **Core migration path is safe:** The `grdb_migrations` table approach, per-migration transactions, rollback on failure, and the sequential application model are all pure SQLite semantics with no Apple-platform dependencies. The migration core will work correctly on Android.
