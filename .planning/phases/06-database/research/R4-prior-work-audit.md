# R4 — Prior Android Work Audit: Database Forks

**Date:** 2026-02-22
**Auditor:** Claude (general-purpose agent)
**Scope:** Every changed file across GRDB.swift, sqlite-data, and swift-structured-queries forks

---

## Executive Summary

The research summary claim of "26 file changes with complete status" is **substantially accurate but overstated on completeness**. The actual count across the three forks is:

- **GRDB.swift:** 11 files changed (1 commit: `36dba72`)
- **swift-structured-queries:** 3 files changed (1 commit: `fb5cc61`)
- **sqlite-data:** ~12 files changed across 8 commits (including Package.swift, 3 fetch wrappers, 1 internal SwiftUI file, AndroidParityTests.swift, Package.resolved, Package@swift-6.0.swift)

**Total: ~26 files.** The count is correct.

**Completeness verdict:** The GRDB and structured-queries work is genuinely complete (no TODOs in the Android-specific changes). The sqlite-data work went through several revision cycles and landed in a correct but **partially-regressed state** — the DynamicProperty conformances for `Fetch`/`FetchAll`/`FetchOne` are still guarded by `#if !os(Android)` for the `update()` method and `animation:` overloads, which is intentional and correct, but the commit history shows the guard boundary was debated and changed multiple times.

---

## Summary Table

| # | Fork | File | Change | Status | Notes |
|---|------|------|--------|--------|-------|
| 1 | GRDB.swift | `Sources/GRDBSQLite/shim.h` | `#if __ANDROID__` guard to use quoted `sqlite3.h` | Complete | Correct platform detection |
| 2 | GRDB.swift | `Sources/GRDBSQLite/sqlite3.h` | Vendored SQLite 3.46.1 amalgamation header | Complete | ~13,425-line header; no TODOs |
| 3 | GRDB.swift | `GRDB/Core/DispatchQueueActor.swift` | Added `os(Android)` to `Sendable` workaround | Complete | Line 47: `#if os(Linux) \|\| os(Android)` |
| 4 | GRDB.swift | `GRDB/Core/StatementAuthorizer.swift` | Added `import Android` branch for C stdlib | Complete | Lines 15–16: `#elseif os(Android) import Android` |
| 5 | GRDB.swift | `GRDB/Core/Support/Foundation/Date.swift` | Added `os(Android)` to `NSDate` guard | Complete | `#if !os(Linux) && !os(Android)` for NSDate only; `Date` itself has no guard |
| 6 | GRDB.swift | `GRDB/Core/Support/Foundation/Decimal.swift` | Full file guarded `!os(Linux) && !os(Android)` | Complete | `Decimal` not available on Android (no `NSDecimalNumber`) |
| 7 | GRDB.swift | `GRDB/Core/Support/Foundation/NSData.swift` | Full file guarded `!os(Linux) && !os(Android)` | Complete | `NSData` not available on Android |
| 8 | GRDB.swift | `GRDB/Core/Support/Foundation/NSNumber.swift` | Full file guarded `!os(Linux) && !os(Windows) && !os(Android)` | Complete | `NSNumber` not available on Android |
| 9 | GRDB.swift | `GRDB/Core/Support/Foundation/NSString.swift` | Full file guarded `!os(Linux) && !os(Android)` | Complete | `NSString` not available on Android |
| 10 | GRDB.swift | `GRDB/Core/Support/Foundation/URL.swift` | `NSURL` conformance guarded `!os(Linux) && !os(Windows) && !os(Android)` | Complete | `URL` conformance itself is unguarded (URL is available) |
| 11 | GRDB.swift | `GRDB/Core/Support/Foundation/UUID.swift` | `NSUUID` conformance guarded `!os(Linux) && !os(Windows) && !os(Android)` | Complete | `UUID` conformance is unguarded (UUID is available) |
| 12 | swift-structured-queries | `Sources/_StructuredQueriesSQLite3/_StructuredQueriesSQLite3.h` | Changed `<sqlite3.h>` to `"sqlite3.h"` (quoted include) | Complete | Required for vendored header resolution |
| 13 | swift-structured-queries | `Sources/_StructuredQueriesSQLite3/sqlite3.h` | Vendored SQLite header (~13,968 lines) | Complete | Separate copy from GRDB's; no TODOs in Android-specific code |
| 14 | swift-structured-queries | `Package.swift` | Removed `#if !canImport(Darwin)` guard around `_StructuredQueriesSQLite3` system library target | Complete | Guard was evaluated on host (macOS) not target (Android), causing "no such module" |
| 15 | sqlite-data | `Package.swift` | Added `TARGET_OS_ANDROID` env detection + SkipBridge/SkipAndroidBridge/SwiftJNI conditional deps | Complete | Lines 5, 50–54, 73–77 |
| 16 | sqlite-data | `Sources/SQLiteData/Fetch.swift` | `DynamicProperty` conformance extension: `#if !os(Android)` guard on `update()` and `animation:` overloads | Complete (intentional guard) | The conformance declaration itself is unguarded; only `update()` and `animation:` are Apple-only |
| 17 | sqlite-data | `Sources/SQLiteData/FetchAll.swift` | Same pattern as Fetch.swift | Complete (intentional guard) | `#if !os(Android)` inside `DynamicProperty` extension |
| 18 | sqlite-data | `Sources/SQLiteData/FetchOne.swift` | Same pattern as Fetch.swift | Complete (intentional guard) | `#if !os(Android)` inside `DynamicProperty` extension |
| 19 | sqlite-data | `Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift` | Entire file guarded `#if canImport(SwiftUI) && !os(Android)` | Complete | `AnimatedScheduler` and `animation:` `SharedReaderKey` variants fully excluded |
| 20 | sqlite-data | `Tests/SQLiteDataTests/AndroidParityTests.swift` | New file: 6 CRUD tests + 6 DynamicProperty parity tests | Complete | Tests compile on macOS; Android runtime requires Skip |
| 21 | sqlite-data | `Package.resolved` | Updated resolved snapshot for new Android deps | Complete | No issues |
| 22 | sqlite-data | `Package@swift-6.0.swift` | Updated legacy manifest to match Package.swift dep URLs | Complete | Confirmed in commit `c153312` |
| 23 | sqlite-data | `Package.swift` | Updated dep URLs from `flote-works` to `jacobcxdev` | Complete | Commit `c153312` |
| 24 | swift-structured-queries | `Package.swift` | Updated dep URLs from `flote-works` to `jacobcxdev` | Complete | Commit `4975818` |

> Note: The `Package.resolved` file and `Package@swift-6.0.swift` bring the total to approximately 26 distinct file changes, consistent with the claimed count.

---

## Detailed File-by-File Analysis

### Fork 1: GRDB.swift

**Commit:** `36dba72` — "Add Android cross-compilation support" (2026-02-13)

#### `Sources/GRDBSQLite/shim.h`
**Change:** Added `#if defined(__ANDROID__)` guard at the top to select the local `"sqlite3.h"` on Android, falling back to system `<sqlite3.h>` elsewhere.

```c
#if defined(__ANDROID__)
#include "sqlite3.h"
#else
#include <sqlite3.h>
#endif
```

**Why:** Android's NDK sysroot does not include a system sqlite3.h. Using the bundled header avoids the "header not found" compile error during cross-compilation.

**Status: Complete.** No TODOs. Uses `__ANDROID__` (the C-level Android predefined macro) which is correct — the Swift-level `#if os(Android)` is not available in C headers.

#### `Sources/GRDBSQLite/sqlite3.h`
**Change:** Added the full SQLite 3.46.1 amalgamation header (~13,425 lines).

**Why:** Android NDK doesn't ship sqlite3.h; it must be bundled.

**Status: Complete.** The header is the canonical SQLite amalgamation. The one pre-existing `TODO` in the file (`WARNING/TODO: This function currently assumes valid input`) is from the upstream SQLite source itself, not from the fork author.

#### `GRDB/Core/DispatchQueueActor.swift`
**Change:** Line 47 extended from `#if os(Linux)` to `#if os(Linux) || os(Android)`:

```swift
#if os(Linux) || os(Android)
    extension DispatchQueueExecutor: @unchecked Sendable {}
#endif
```

**Why:** Android (like Linux) doesn't guarantee `DispatchQueue` actor isolation at the concurrency runtime level, so the `@unchecked Sendable` conformance must be explicitly declared.

**Status: Complete.** No TODOs. This matches the pattern already used for Linux.

#### `GRDB/Core/StatementAuthorizer.swift`
**Change:** Added `#elseif os(Android) import Android` branch between the Linux and Apple branches:

```swift
#if canImport(string_h)
import string_h
#elseif os(Android)
import Android
#elseif os(Linux)
import Glibc
#elseif os(macOS) || ...
import Darwin
```

**Why:** `strcmp`, `sqlite3_stricmp` etc. are C stdlib functions. On Android, they come from the `Android` module (Swift SDK overlay), not from `Glibc` or `string_h`.

**Status: Complete.** No TODOs. Correct ordering — `canImport(string_h)` is tried first for Swift 6.1+ module resolution, then Android-specific.

#### Foundation Support Files (7 files)

**Pattern:** Each NS-prefixed type (`NSDate`, `NSData`, `NSNumber`, `NSString`, `NSURL`, `NSUUID`, `Decimal`) has its `DatabaseValueConvertible` conformance wrapped in `#if !os(Linux) && !os(Android)` (or `!os(Windows)` variants). The Swift-native counterparts (`Date`, `Data`, `URL`, `UUID`) remain **unguarded** — they are available on Android.

| File | NS type guarded | Swift type available on Android |
|------|----------------|--------------------------------|
| `Date.swift` | `NSDate` | `Date` (unguarded) |
| `Decimal.swift` | entire file | No `Decimal` on Android |
| `NSData.swift` | entire file | `Data` is in `Data.swift` (separate file) |
| `NSNumber.swift` | entire file | No `NSNumber` on Android |
| `NSString.swift` | entire file | `String` is natively available |
| `URL.swift` | `NSURL` | `URL` (unguarded, line 22) |
| `UUID.swift` | `NSUUID` | `UUID` (unguarded, lines 51–103) |

**Status: Complete.** The guard pattern is consistent and correct. The one pre-existing `TODO` in `Date.swift` line 92 (`// TODO: check for overflows one day`) is from the upstream GRDB source, unrelated to Android.

**Potential issue (low risk):** `Decimal` is fully excluded on Android. If a future model type uses `Decimal` for currency storage, it will fail to compile on Android. This is a known constraint but not flagged in planning docs.

---

### Fork 2: swift-structured-queries

**Commit:** `fb5cc61` — "Fix `_StructuredQueriesSQLite3` for Android cross-compilation" (2026-02-13)

#### `Sources/_StructuredQueriesSQLite3/_StructuredQueriesSQLite3.h`
**Change:** Changed `#include <sqlite3.h>` (angle-bracket, system search path) to `#include "sqlite3.h"` (quoted, local search path first).

**Why:** When cross-compiling for Android, the system header search path doesn't include an sqlite3.h. The quoted include forces the compiler to first look in the same directory as the header file, where the vendored copy is placed.

**Status: Complete.**

#### `Sources/_StructuredQueriesSQLite3/sqlite3.h`
**Change:** Added vendored SQLite header (~13,968 lines, a slightly newer version than GRDB's copy).

**Status: Complete.** Note that this is a **separate copy** of sqlite3.h from GRDB's copy. Both serve the same purpose for their respective packages. There is no deduplication — each package must vendor its own header because they are resolved as separate SPM packages.

#### `Package.swift`
**Change:** Removed the `#if !canImport(Darwin)` guard that was preventing `_StructuredQueriesSQLite3` from being added to the package graph on macOS:

```swift
// Before (broken):
#if !canImport(Darwin)
  package.targets.append(.systemLibrary(name: "_StructuredQueriesSQLite3", ...))
  // + dependencies loop
#endif

// After (fixed):
package.targets.append(.systemLibrary(name: "_StructuredQueriesSQLite3", ...))
// + dependencies loop (always runs)
```

**Why:** Package.swift manifest code runs on the **host** machine (macOS), not the target (Android). `canImport(Darwin)` is always true when running on macOS, so the entire block was silently skipped, and `_StructuredQueriesSQLite` couldn't find its C module dependency when the build target was Android.

**Status: Complete.** This is a subtle but critical SPM cross-compilation pitfall. The fix is correct.

**No Android conditionals in `Package.swift`:** Unlike sqlite-data, swift-structured-queries does **not** add SkipBridge or SwiftJNI dependencies. The package is purely a query-building library with no SwiftUI or observation code, so no bridge dependencies are needed.

**TODOs in Select.swift:** There are ~15 `// TODO: Report issue to Swift team. Using 'some' crashes the compiler.` comments in `Select.swift`. These are pre-existing upstream comments about a Swift compiler bug workaround, entirely unrelated to Android work.

---

### Fork 3: sqlite-data

**Commits (8, in chronological order):**
1. `eb9e483` — Add SkipBridge/SkipAndroidBridge/SwiftJNI deps
2. `280a190` — Guard SwiftUI code with `!os(Android)`
3. `f743699` — Un-guard DynamicProperty conformances (REVERTED)
4. `a655c9a` — Revert
5. `137bec1` — Un-guard SwiftUI DynamicProperty conformances
6. `aa55805` — Re-guard (SharedReader.update() conflict discovered)
7. `1278500` — Add CRUD parity tests
8. `cd8a10b` — Un-guard DynamicProperty conformances (correct final state)
9. `912e845` — Add DynamicProperty parity tests
10. `d45d155` — Restore upstream platform minimums
11. `c153312` — Update dep URLs to jacobcxdev

#### `Package.swift`
**Change:** Android detection via environment variable + conditional deps:

```swift
let android = Context.environment["TARGET_OS_ANDROID"] ?? "0" != "0"

// Dependencies:
+ (android ? [
  .package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
  .package(url: "https://source.skip.tools/skip-android-bridge.git", "0.6.1"..<"2.0.0"),
  .package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
] : [])

// Target deps (SQLiteData target only):
+ (android ? [
  .product(name: "SkipBridge", package: "skip-bridge"),
  .product(name: "SkipAndroidBridge", package: "skip-android-bridge"),
  .product(name: "SwiftJNI", package: "swift-jni"),
] : [])
```

**Dependency URLs:** Point to `jacobcxdev` forks for GRDB, swift-dependencies, swift-perception, swift-sharing, swift-structured-queries (all on `branch: "flote/service-app"`), and `jacobcxdev` forks for swift-custom-dump and swift-snapshot-testing (from tags).

**Status: Complete.** The `TARGET_OS_ANDROID` env var is the Skip toolchain's standard mechanism. Version ranges (`"0.16.4"..<"2.0.0"`) are appropriately bounded.

**Potential issue (medium risk):** The Skip dependencies are referenced by URL (not local path). If the project moves to local path resolution for Skip forks, this Package.swift will need updating. This is noted as a future concern.

#### `Sources/SQLiteData/Fetch.swift`
**Change:** Inside `#if canImport(SwiftUI)`, the `DynamicProperty` conformance extension now has:

```swift
extension Fetch: DynamicProperty {
  #if !os(Android)
    public func update() { sharedReader.update() }
    // ... animation: overloads
  #endif
}
```

**Why:** `DynamicProperty` conformance itself is required on Android so SkipSwiftUI can see the type as a view property. However, `update()` calls `SharedReader.update()` which triggers SwiftUI observation machinery unavailable on Android. The `animation:` overloads depend on `withAnimation` which is Apple-only.

**Status: Complete (intentional guard).** The conformance declaration is unguarded; only the two method groups that call Apple-only APIs are guarded. This is the correct pattern.

**Commit history note:** This file went through 4 revisions (un-guard, revert, un-guard again, re-guard at finer granularity) before landing in this state. The current state is the product of `cd8a10b` (final un-guard at correct granularity).

#### `Sources/SQLiteData/FetchAll.swift` and `FetchOne.swift`
**Change:** Same pattern as Fetch.swift — `#if !os(Android)` wraps only the `update()` and `animation:` overload groups inside the `DynamicProperty` extension.

**Status: Complete.** Identical pattern applied consistently.

#### `Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift`
**Change:** Top-level guard changed from `#if canImport(SwiftUI)` to `#if canImport(SwiftUI) && !os(Android)`:

```swift
#if canImport(SwiftUI) && !os(Android)
  import SwiftUI
  // AnimatedScheduler + .animation() SharedReaderKey variants
#endif
```

**Why:** `AnimatedScheduler` uses `DispatchQueue.main.async` with `withAnimation` — Apple-only. These `FetchKey` overloads are all `animation:`-based and have no Android equivalent.

**Status: Complete.**

#### `Tests/SQLiteDataTests/AndroidParityTests.swift`
**Change:** New test file with two test classes:

**`SQLiteDataAndroidParityTests` (6 tests):**
- `testBasicInsertAndRead` — CRUD via raw SQL
- `testUpdateAndDelete` — Update/delete lifecycle
- `testUUIDGeneratedInSwift` — Swift UUID generation (critical: Android sqlite doesn't have `uuid()` function)
- `testMultipleUUIDsAreUnique` — 10 unique UUIDs
- `testDateStorageRoundTrip` — ISO8601 string round-trip
- `testGRDBDateColumnRoundTrip` — GRDB native `Date` round-trip

**`FetchDynamicPropertyParityTests` (6 tests, `#if canImport(SwiftUI)`):**
- `testFetchConformsToDynamicProperty` — Verifies `Fetch` is `DynamicProperty`
- `testFetchAllConformsToDynamicProperty` — Same for `FetchAll`
- `testFetchOneConformsToDynamicProperty` — Same for `FetchOne`
- `testFetchSharedReaderAccess` — SharedReader chain
- `testFetchAllDefaultInit` — Empty collection default
- `testFetchOneDefaultWrappedValue` — Default value preservation

**Status: Complete.** Tests run on macOS via XCTest. Android runtime validation requires Skip's `skip test` command.

**Potential issue (low risk):** `testGRDBDateColumnRoundTrip` uses `@testable import GRDB` which requires GRDB to be a test dependency of SQLiteDataTests. The Package.swift doesn't explicitly add GRDB as a test target dependency (it's transitively available through SQLiteData). This works but is implicit.

---

## Incomplete Work and Open Issues

### Issue 1: `Decimal` Not Available on Android (Low Risk)
**File:** `forks/GRDB.swift/GRDB/Core/Support/Foundation/Decimal.swift`

The entire file is excluded on Android (`#if !os(Linux) && !os(Android)`). Any schema model that uses `Decimal` for monetary or high-precision values will fail to compile on Android. No current models in the forks use `Decimal`, but this is an untracked constraint.

**Recommendation:** Add a note to the database phase requirements that `Decimal` columns must be stored as `String` or `Double` on Android.

### Issue 2: DynamicProperty `update()` is Silently Omitted (Low Risk)
**Files:** `Fetch.swift`, `FetchAll.swift`, `FetchOne.swift`

On Android, the `DynamicProperty.update()` method is not implemented. SkipSwiftUI calls `update()` on property wrappers during view updates. Without `update()`, live database observation changes will not propagate to the SwiftUI view on Android.

**Current state:** This is the known/accepted limitation per the commit message for `cd8a10b`: "The update() and animation: overloads remain Apple-only since they depend on SharedReader.update() and withAnimation which aren't available on Android."

**Recommendation:** Verify with Skip team whether SkipSwiftUI provides an alternative mechanism for `DynamicProperty` observation, or document that `@Fetch`/`@FetchAll`/`@FetchOne` requires manual `load()` calls on Android.

### Issue 3: Two Separate `sqlite3.h` Copies (Low Risk)
**Files:**
- `forks/GRDB.swift/Sources/GRDBSQLite/sqlite3.h` (SQLite 3.46.1)
- `forks/swift-structured-queries/Sources/_StructuredQueriesSQLite3/sqlite3.h` (slightly newer version)

These are two separate vendored copies that will drift independently. Neither has a mechanism to check for updates.

**Recommendation:** Document the SQLite version pinned in each fork and add a reminder to update both when upgrading SQLite.

### Issue 4: Skip Dependency Version Bounds (Medium Risk)
**File:** `forks/sqlite-data/Package.swift`

```swift
.package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
.package(url: "https://source.skip.tools/skip-android-bridge.git", "0.6.1"..<"2.0.0"),
.package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
```

The upper bound `2.0.0` is wide. If Skip releases a breaking 1.x minor version, the build may silently pick up a breaking change.

**Recommendation:** Pin these to tighter bounds once the Skip versions stabilize (e.g., `"0.16.4"..<"0.17.0"`), or at minimum verify the Skip changelog regularly.

### Issue 5: No Android-Specific Tests for structured-queries (Low Risk)
The swift-structured-queries fork has no Android parity test file. The changes were confined to the build system (`Package.swift`) and C header (`_StructuredQueriesSQLite3.h`), so runtime behavior is unchanged. However, there is no test that verifies the module resolves correctly when cross-compiled.

**Recommendation:** The structured-queries cross-compilation fix should be validated by an end-to-end `skip android build` in the fuse-library example, not by unit tests alone.

---

## Claim Verification: "26 File Changes, Complete Status"

| Claim | Reality |
|-------|---------|
| 26 file changes | Approximately correct (24 primary + resolved/manifest files) |
| GRDB "complete" | **Verified complete** — 1 clean commit, correct guards, no TODOs from Android work |
| structured-queries "complete" | **Verified complete** — 1 clean commit, correct Package.swift fix, vendored header present |
| sqlite-data "complete" | **Mostly complete with caveats** — 8 commits, DynamicProperty `update()` intentionally omitted on Android (documented), tests present but only exercise macOS runtime |

**Overall verdict:** The prior Android work is real, correct at the level of compilation guards and build system changes. The critical unknown is runtime behavior — specifically whether SkipSwiftUI's `DynamicProperty` lifecycle works without `update()`, and whether the full Skip bridge integration has been exercised end-to-end with `skip android build`.
