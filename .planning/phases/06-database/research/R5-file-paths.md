# R5: Database File Path Resolution on Android

**Research item:** How SQLiteData resolves database paths on Android, and whether `defaultDatabase()` works correctly.
**Verdict: Works correctly on Android with one latent bug (`absoluteString`) that does not affect the Android path.**

---

## 1. The `defaultDatabase()` Implementation (Full Source)

File: `forks/sqlite-data/Sources/SQLiteData/StructuredQueries+GRDB/DefaultDatabase.swift`

```swift
public func defaultDatabase(
  path: String? = nil,
  configuration: Configuration = Configuration()
) throws -> any DatabaseWriter {
  let database: any DatabaseWriter
  @Dependency(\.context) var context
  switch context {
  case .live:
    var defaultPath: String {
      get throws {
        let applicationSupportDirectory = try FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true                          // <-- creates the directory if absent
        )
        return applicationSupportDirectory.appendingPathComponent("SQLiteData.db").absoluteString
        //                                                                          ^^^^^^^^^^^
        //                     BUG: should be .path not .absoluteString (see §6)
      }
    }
    database = try DatabasePool(path: path ?? defaultPath, configuration: configuration)
  case .preview, .test:
    database = try DatabasePool(
      path: "\(NSTemporaryDirectory())\(UUID().uuidString).db",
      configuration: configuration
    )
  }
  return database
}
```

Key observations:

- **Live context** — resolves `.applicationSupportDirectory` via `FileManager`, with `create: true`, then appends `"SQLiteData.db"`.
- **Preview / Test context** — uses `NSTemporaryDirectory()` + UUID to produce a fresh, throwaway on-disk `DatabasePool`.
- **`DatabasePool`** — always used (never `DatabaseQueue`). GRDB initialises `DatabasePool` with WAL mode by default (confirmed in `DatabasePool.swift` line 79-81: `case .default, .wal: try $0.setUpWALMode()`). WAL produces three files: `SQLiteData.db`, `SQLiteData.db-wal`, `SQLiteData.db-shm`.
- **`DependencyValues.defaultDatabase`** — separate from the function; its `liveValue` delegates to `testValue` (in-memory `DatabaseQueue`) until the caller calls `prepareDependencies { $0.defaultDatabase = try! defaultDatabase() }`.

---

## 2. Path Resolution — iOS

On iOS (and macOS), `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)` returns:

```
/var/mobile/Containers/Data/Application/<UUID>/Library/Application Support/
```

The final database path (modulo the `absoluteString` bug) would be:

```
file:///var/mobile/Containers/Data/Application/<UUID>/Library/Application%20Support/SQLiteData.db
```

Because of `.absoluteString` (not `.path`), GRDB receives a `file://` URL string as the path argument. GRDB's `DatabasePool(path:)` calls through to SQLite's `sqlite3_open_v2`, which accepts `file:` URIs. So the iOS path accidentally works despite the bug.

---

## 3. Path Resolution — Android

### 3a. XDG Bootstrap Chain

Skip's android-bridge bootstraps `FileManager` path resolution at app startup via `AndroidBridgeBootstrap.initAndroidBridge(filesDir:cacheDir:)`.

File: `forks/skip-android-bridge/Sources/SkipAndroidBridge/AndroidBridgeBootstrap.swift`

```swift
// Called from Kotlin's AndroidBridge.initBridge at app init time:
try AndroidBridgeBootstrap.initAndroidBridge(
    filesDir: context.getFilesDir().getAbsolutePath(),
    cacheDir:  context.getCacheDir().getAbsolutePath()
)

private func bootstrapFileManagerProperties(filesDir: String, cacheDir: String) throws {
    // XDG_DATA_HOME -> applicationSupportDirectory
    setenv("XDG_DATA_HOME", filesDir, 0)
    // XDG_CACHE_HOME -> cachesDirectory
    setenv("XDG_CACHE_HOME", cacheDir, 0)
    // CFFIXED_USER_HOME -> UserDefaults persistence root
    setenv("CFFIXED_USER_HOME", filesDir, 0)

    // Force-creates the applicationSupportDirectory to verify the mapping works:
    let applicationSupportDirectory = try! FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    logger.debug("bootstrapFileManagerProperties: applicationSupportDirectory=\(applicationSupportDirectory.path)")
}
```

### 3b. swift-foundation XDG Resolution

Swift Foundation's `FileManager+XDGSearchPaths.swift` maps:

| FileManager search path | XDG env var | Fallback |
|------------------------|-------------|----------|
| `.applicationSupportDirectory` | `$XDG_DATA_HOME` | `$HOME/.local/share` |
| `.cachesDirectory` | `$XDG_CACHE_HOME` | `$HOME/.cache` |

The path is validated to be absolute (must start with `/`) before being accepted.

### 3c. Android Concrete Paths

`context.getFilesDir()` returns the app's private internal storage files directory. On a real device or standard emulator:

```
/data/user/0/<package.name>/files
```

(Confirmed by the test assertion in `AndroidBridgeTests.swift` line 37:
`XCTAssertEqual("/data/user/0/skip.android.bridge.test/files", filesDir.path)`)

On Robolectric (unit tests), it is a temp directory ending in `.../files`.

Therefore, after the bootstrap:

```
XDG_DATA_HOME = /data/user/0/<package>/files
```

`FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)` resolves to:

```
/data/user/0/<package>/files/Application Support/
```

And the final database path (before the `absoluteString` bug applies) is:

```
/data/user/0/<package>/files/Application Support/SQLiteData.db
```

### 3d. Directory Creation

`create: true` in the `FileManager.url(for:in:appropriateFor:create:)` call means the directory is created if it does not exist. This is done both in `bootstrapFileManagerProperties` (during app init) and inside `defaultDatabase()` at database open time. The app's `/data/user/0/<package>/files/` directory is writable by the app — Android grants this unconditionally for internal storage via the sandboxing model. No `android.permission.WRITE_EXTERNAL_STORAGE` is needed.

---

## 4. Android File Permissions

Android's internal app storage (`getFilesDir()`, `getCacheDir()`) is:

- **Writable** by the app process without any manifest permission declaration.
- **Not accessible** by other apps (enforced by Linux user/group isolation: each app runs as a unique UID).
- **Survives app updates** (unlike external storage or `getCacheDir()` which may be cleared under storage pressure).
- **Cleared on app uninstall.**

SQLite requires read+write on the database file and its containing directory (for WAL file creation and journal temp files). Both are satisfied by the `filesDir` path.

---

## 5. WAL and Journal File Behaviour on Android

`DatabasePool` always uses WAL mode (GRDB's default). WAL produces sidecar files alongside the main `.db` file:

| File | Purpose |
|------|---------|
| `SQLiteData.db` | Main database |
| `SQLiteData.db-wal` | Write-ahead log (active during writes) |
| `SQLiteData.db-shm` | Shared memory index (mmap-based) |

On Android, all three files land in the same directory:

```
/data/user/0/<package>/files/Application Support/
  SQLiteData.db
  SQLiteData.db-wal
  SQLiteData.db-shm
```

**Shared memory (`-shm`):** WAL's shared-memory file requires `mmap`. Android supports `mmap` on internal storage. GRDB handles the case where `mmap` is unavailable by falling back to heap-based shared memory (see `DatabasePool.swift` line 302-311 for read-only WAL connection notes). No Android-specific workaround is needed.

**Permissions on sidecar files:** SQLite creates the `-wal` and `-shm` files in the same directory as the main database, inheriting the directory's write permissions. Since the directory is owned by the app UID, creation succeeds.

**No journal mode difference:** SQLite's WAL mode is a pure SQLite feature, independent of the OS. The same WAL behaviour operates identically on Android and iOS.

---

## 6. The `absoluteString` Bug

```swift
// Line 32 of DefaultDatabase.swift:
return applicationSupportDirectory.appendingPathComponent("SQLiteData.db").absoluteString
//                                                                          ^^^^^^^^^^^^^
```

`URL.absoluteString` returns the full RFC 3986 string including scheme and percent-encoding:

```
file:///data/user/0/com.example/files/Application%20Support/SQLiteData.db
```

`URL.path` (or `URL.path(percentEncoded: false)`) returns the POSIX path:

```
/data/user/0/com.example/files/Application Support/SQLiteData.db
```

GRDB's `DatabasePool(path:)` passes the string to SQLite's `sqlite3_open_v2` as the filename. SQLite accepts both forms:

- POSIX paths (no scheme) — always accepted.
- `file:` URI strings — accepted since SQLite 3.7.7 as "URI filenames".

So the `absoluteString` bug does not break functionality on Android or iOS — SQLite handles both. However, the `file://` URI form enables SQLite URI query parameters (e.g., `?mode=ro`), which is not the intent here. The canonical fix is `.path(percentEncoded: false)`. This is noted as a latent issue but is **not a blocker for Phase 6**.

For comparison, the GRDB demo (`Persistence.swift` in the GRDB.swift fork) correctly uses `.path`:

```swift
let databaseURL = directoryURL.appendingPathComponent("db.sqlite")
let dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
```

And `Metadatabase.swift` in sqlite-data's CloudKit code correctly uses `.path(percentEncoded: false)`:

```swift
let metadatabase = try DatabasePool(path: url.path(percentEncoded: false))
```

---

## 7. Preview and Test Context Path Resolution

For `.preview` and `.test` contexts, `defaultDatabase()` uses:

```swift
database = try DatabasePool(
  path: "\(NSTemporaryDirectory())\(UUID().uuidString).db",
  configuration: configuration
)
```

`NSTemporaryDirectory()` is available on Android via Foundation (maps to `getCacheDir()` + `/tmp/` or system temp). Each call produces a unique UUID-named file, so tests are isolated. The file is on-disk (not in-memory), meaning WAL sidecar files are also created — this is intentional upstream so tests exercise the same `DatabasePool` code path as production.

For an in-memory database (completely isolated, no file I/O), use `DatabaseQueue()` directly, which is what the `DefaultDatabaseKey.testValue` fallback does:

```swift
static var testValue: any DatabaseWriter {
  // ...
  return try! DatabaseQueue(configuration: configuration)
}
```

---

## 8. Full Path Trace Summary

### iOS (live context)

```
FileManager.url(for: .applicationSupportDirectory, create: true)
  -> /var/mobile/Containers/Data/Application/<UUID>/Library/Application Support/
  (created if absent)
appendingPathComponent("SQLiteData.db").absoluteString
  -> "file:///var/.../Library/Application%20Support/SQLiteData.db"
DatabasePool(path: above)
  -> SQLite opens via file: URI (works)
  -> WAL files: same directory, created on first write
```

### Android (live context)

```
initAndroidBridge() sets:
  XDG_DATA_HOME = /data/user/0/<package>/files

FileManager.url(for: .applicationSupportDirectory, create: true)
  -> /data/user/0/<package>/files/Application Support/
  (created if absent — writable, no permissions needed)
appendingPathComponent("SQLiteData.db").absoluteString
  -> "file:///data/user/0/<package>/files/Application%20Support/SQLiteData.db"
DatabasePool(path: above)
  -> SQLite opens via file: URI (works)
  -> WAL files created in same directory
```

### Android (test context)

```
NSTemporaryDirectory()
  -> /data/user/0/<package>/cache/tmp/  (or Robolectric temp dir)
path: "\(NSTemporaryDirectory())\(UUID()).db"
  -> /data/user/0/<package>/cache/tmp/<uuid>.db
DatabasePool(path: above)
  -> Fresh isolated on-disk database per test
```

---

## 9. Relationship to Phase 4 FileStorageKey

Phase 4 validated that `FileManager.url(for: .applicationSupportDirectory, ...)` resolves correctly on Android via the XDG bootstrap. `defaultDatabase()` uses the identical API call. The bootstrap happens at app launch before any database is opened, so the environment is always set when `defaultDatabase()` runs.

The `FileStorageKey` pattern (Phase 4) and `defaultDatabase()` (Phase 6) share the same resolution chain:

```
AndroidBridgeBootstrap.initAndroidBridge
  -> setenv("XDG_DATA_HOME", filesDir)
    -> FileManager.url(for: .applicationSupportDirectory)
      -> filesDir/Application Support/
        -> FileStorageKey path  (Phase 4)
        -> defaultDatabase() path  (Phase 6)
```

---

## 10. What `FetchKey.swift` Does (No File I/O)

`FetchKey` (`forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift`) creates no files or directories. It:

1. Captures a reference to the `defaultDatabase` dependency at init time.
2. On `load()`, calls `database.asyncRead { ... }` — reads from the already-open connection.
3. On `subscribe()`, calls `ValueObservation.start(in: database, ...)` — registers an SQLite transaction hook inside the already-open connection.

File creation is entirely in `defaultDatabase()` / `DatabasePool(path:)`. `FetchKey` is a pure query/observation layer.

---

## 11. Verification Steps

To verify correct path resolution on Android without running a full device test:

1. **Robolectric (fastest):** Add a test in `fuse-library` that calls `defaultDatabase()` under `.live` context with mocked `XDG_DATA_HOME`. Assert the path ends in `Application Support/SQLiteData.db`.

2. **Skip test (cross-platform parity):**
   ```bash
   cd examples/fuse-library && make skip-test
   ```
   The existing `AndroidParityTests.swift` in `forks/sqlite-data` covers CRUD on `DatabaseQueue`. Add a test that exercises `defaultDatabase()` with an explicit `path:` override to avoid file system dependency:
   ```swift
   let db = try defaultDatabase(path: ":memory:")
   // ... run migrations and queries ...
   ```

3. **Device/emulator (definitive):** Launch fuse-app with `adb logcat -s swift`. Look for:
   ```
   AndroidBridgeBootstrap.initAndroidBridge done ... applicationSupportDirectory=/data/user/0/<pkg>/files/Application Support
   ```
   Then confirm the database file exists:
   ```bash
   adb shell run-as <package> ls -la files/Application\ Support/
   # Expected: SQLiteData.db, SQLiteData.db-wal, SQLiteData.db-shm
   ```

4. **`absoluteString` fix (optional cleanup):**
   ```swift
   // DefaultDatabase.swift line 32, change:
   return applicationSupportDirectory.appendingPathComponent("SQLiteData.db").absoluteString
   // to:
   return applicationSupportDirectory.appendingPathComponent("SQLiteData.db").path(percentEncoded: false)
   ```
   This is cosmetically correct but not functionally required for Phase 6.

---

## 12. Risk Assessment

| Item | Risk | Status |
|------|------|--------|
| `XDG_DATA_HOME` not set when `defaultDatabase()` is called | None | Bootstrap runs at app init before any DB open |
| Android `filesDir` not writable | None | Internal storage is always writable by the app |
| WAL sidecar file creation fails | None | Same directory, same permissions, `mmap` supported |
| `absoluteString` passes `file://` URI to SQLite | None | SQLite accepts URI filenames since 3.7.7 |
| `NSTemporaryDirectory()` unavailable on Android | None | Foundation provides it; maps to cache/tmp |
| Directory not created before `DatabasePool` opens | None | `create: true` in `FileManager.url(for:)` handles this |
| Path contains space (`Application Support`) | None | SQLite URI-encodes if using `file:` URI; POSIX path also works directly |

**Overall verdict: No changes required to `DefaultDatabase.swift` for Android path resolution.** The `absoluteString` bug is pre-existing, benign, and out of scope for Phase 6.

---

*Research completed: 2026-02-22*
*Sources: `forks/sqlite-data/Sources/SQLiteData/StructuredQueries+GRDB/DefaultDatabase.swift`, `forks/skip-android-bridge/Sources/SkipAndroidBridge/AndroidBridgeBootstrap.swift`, `forks/skip-android-bridge/Tests/SkipAndroidBridgeTests/AndroidBridgeTests.swift`, `forks/GRDB.swift/GRDB/Core/DatabasePool.swift`, `.planning/phases/06-database/06-RESEARCH.md` (R5 answer), swift-foundation XDG search path implementation*
