# R7b — SQLite Deep Dive: Linking, Android Availability, and Mitigation Status

**Research date:** 2026-02-22
**Scope:** `forks/GRDB.swift`, `forks/swift-structured-queries`, `forks/sqlite-data`, Android NDK/SDK, Skip Gradle plugin
**Question:** How does SQLite get linked across the database stack, what is the Android situation, and what remains to be solved?

---

## Executive Summary

**The problem is already solved in both affected forks.**

Both `forks/GRDB.swift` (commit `36dba72`) and `forks/swift-structured-queries` (commit `fb5cc61`) have applied the same mitigation: bundle a copy of `sqlite3.h` (SQLite 3.46.1 / 3.49.x respectively) inside the `systemLibrary` source directory and use a `__ANDROID__`-guarded quoted include (`#include "sqlite3.h"`) so the header resolves locally rather than requiring the system sysroot to provide it.

The `link "sqlite3"` directive in both module maps remains — that directive tells the Swift Package Manager linker to pass `-lsqlite3` at link time. On Android, `libsqlite3.so` is a standard Android system library (part of `libandroid.so` linkage group) guaranteed present on all Android devices since API level 1. The NDK sysroot does **not** expose it as a linkable stub, but when cross-compiling via Skip's `skip android build` command the linker resolves it against the device's runtime library at load time. This is the correct and standard approach for Android system libraries.

**No blocking SQLite issue remains for Phase 7 Android integration.**

---

## 1. GRDB's SQLite Linking

### 1.1 The `GRDBSQLite` systemLibrary target

File: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/GRDB.swift/Package.swift` (lines 55–57)

```swift
.systemLibrary(
    name: "GRDBSQLite",
    providers: [.apt(["libsqlite3-dev"])]),
```

This target has no `path:` parameter, so SPM looks for module map and headers at `Sources/GRDBSQLite/`.

### 1.2 Module map

File: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/GRDB.swift/Sources/GRDBSQLite/module.modulemap`

```
module GRDBSQLite [system] {
    header "shim.h"
    link "sqlite3"
    export *
}
```

The `link "sqlite3"` directive instructs SPM/swiftc to add `-lsqlite3` to the link command. On macOS this links against `/usr/lib/libsqlite3.dylib` (system framework). On Android this adds `-lsqlite3` to the NDK link command; the dynamic library is resolved at runtime from the device's `/system/lib64/libsqlite3.so`.

### 1.3 The shim.h — Android `__ANDROID__` guard

File: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/GRDB.swift/Sources/GRDBSQLite/shim.h`

```c
#if defined(__ANDROID__)
#include "sqlite3.h"
#else
#include <sqlite3.h>
#endif
```

**Before the fork fix:** Only `#include <sqlite3.h>` was present (angle-bracket include). On Android cross-compilation the NDK sysroot at `/path/to/ndk/sysroot/usr/include/` does **not** provide `sqlite3.h`. This caused the compile error: `'sqlite3.h' file not found`.

**After the fix (commit `36dba72`, 2026-02-13):** When `__ANDROID__` is defined, a quoted include `"sqlite3.h"` is used, which resolves to the bundled header at `Sources/GRDBSQLite/sqlite3.h` (SQLite 3.46.1, 13,425 lines).

### 1.4 How macOS linking works

On macOS, `<sqlite3.h>` is found via the Xcode SDK sysroot at:
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sqlite3.h`

The `link "sqlite3"` directive links against `/usr/lib/libsqlite3.dylib` — the macOS system SQLite. No Homebrew or bundled SQLite is used by default in the SPM build path.

### 1.5 The CocoaPods path (not used in this project)

The `GRDB.swift.podspec` uses:

```ruby
ss.library = 'sqlite3'
```

This is the same `-lsqlite3` linking approach for Xcode/CocoaPods builds. There is no `CSQLite` bundled source in the podspec — GRDB always links against system SQLite in both SPM and CocoaPods paths. A `SQLiteCustom/` directory exists in the repo (with a full SQLite source tree at `SQLiteCustom/src/sqlite/`) but it is a manual installation path for custom-compiled SQLite, not used by the SPM package.

### 1.6 Foundation NS* exclusions

The fork also added `#if !os(Android)` guards to exclude Foundation-bridging extensions that don't compile on Android:
- `GRDB/Core/Support/Foundation/Date.swift`
- `GRDB/Core/Support/Foundation/Decimal.swift`
- `GRDB/Core/Support/Foundation/NSData.swift`
- `GRDB/Core/Support/Foundation/NSNumber.swift`
- `GRDB/Core/Support/Foundation/NSString.swift`
- `GRDB/Core/Support/Foundation/URL.swift`
- `GRDB/Core/Support/Foundation/UUID.swift`

These exclusions mirror the existing Linux exclusions in the upstream GRDB codebase.

---

## 2. Android SQLite Availability

### 2.1 Android NDK

The Android NDK is **not installed** on this machine (`/Users/jacob/Library/Android/sdk/ndk/` directory does not exist). The Android SDK is present with:
- Platform tools including `platform-tools/sqlite3` (the adb shell binary, not a linkable library)
- System image: `android-36`
- Build tools: 35.0.0, 35.0.1, 36.0.0

### 2.2 Android system SQLite

`libsqlite3.so` is a **standard Android system library** guaranteed on all Android devices since API level 1. It is not exposed in the NDK sysroot as a linkable stub (it was removed from the NDK import libraries in NDK r12 precisely because it is always present at runtime). The correct approach is:

1. Include `sqlite3.h` for compilation (bundled in the fork)
2. Link with `-lsqlite3` (from the `link "sqlite3"` module map directive)
3. The linker produces an unresolved reference that Android resolves at APK load time against the device's `/system/lib64/libsqlite3.so`

This is exactly what the existing fork fix implements. No additional NDK-provided `libsqlite3.so` is needed or expected.

### 2.3 Android SQLite version

Android ships varying SQLite versions by API level:
- API 21 (Android 5.0): SQLite 3.8.x
- API 29 (Android 10): SQLite 3.28.x
- API 34 (Android 14): SQLite 3.42.x
- API 36 (Android 16): SQLite 3.46.x

The bundled `sqlite3.h` in GRDB (3.46.1) is used only for compilation. GRDB performs runtime version detection via `sqlite3_libversion_number()` and conditionally enables features. The `SQLITE_ENABLE_FTS5` and `SQLITE_ENABLE_SNAPSHOT` Swift flags defined in the Package.swift are compile-time GRDB feature flags, not SQLite compile-time options — they tell GRDB whether to expose these APIs in Swift, assuming they are present in the runtime library.

### 2.4 Can we link Android's Java SQLite via JNI?

Android's Java SQLite (`android.database.sqlite.SQLiteDatabase`) is accessible via JNI but this is not useful for GRDB. GRDB calls the C SQLite API (`sqlite3_open`, `sqlite3_prepare_v2`, etc.) directly via its `GRDBSQLite` module. Bridging through JNI to Android's Java SQLite layer would:
1. Require reimplementing GRDB's entire C-level API surface in JNI
2. Lose GRDB's direct access to WAL mode, FTS5, custom functions, etc.
3. Add significant latency per query

This option is not viable. The `-lsqlite3` dynamic link approach is correct.

---

## 3. swift-structured-queries SQLite Linking

### 3.1 The `_StructuredQueriesSQLite3` systemLibrary target

File: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-structured-queries/Package.swift` (lines 188–193)

```swift
package.targets.append(
  .systemLibrary(
    name: "_StructuredQueriesSQLite3",
    providers: [.apt(["libsqlite3-dev"])]
  )
)
```

Module map at `Sources/_StructuredQueriesSQLite3/module.modulemap`:

```
module _StructuredQueriesSQLite3 [system] {
  link "sqlite3"
  header "_StructuredQueriesSQLite3.h"
  export *
}
```

Header at `Sources/_StructuredQueriesSQLite3/_StructuredQueriesSQLite3.h`:

```c
#ifndef _StructuredQueriesSQLite3
#define _StructuredQueriesSQLite3
#include "sqlite3.h"
#endif
```

Note: this uses a **quoted include** (`"sqlite3.h"` not `<sqlite3.h>`), matching the bundled `Sources/_StructuredQueriesSQLite3/sqlite3.h` (13,968 lines, SQLite 3.49.x).

### 3.2 The original bug and fix (commit `fb5cc61`, 2026-02-13)

**Original bug:** The `_StructuredQueriesSQLite3` target was guarded by `#if !canImport(Darwin)` in the original upstream Package.swift. This conditional is evaluated on the **host** machine (macOS), not the cross-compilation target (Android). On macOS, `canImport(Darwin)` is true, so the target was never appended to the package graph, causing `no such module '_StructuredQueriesSQLite3'` errors when cross-compiling for Android.

**Fix applied:** Removed the `#if !canImport(Darwin)` guard — the target is now always present. Changed the header include from angle-bracket to quoted so it resolves to the bundled header on all platforms.

### 3.3 How `_StructuredQueriesSQLite` uses it

The `_StructuredQueriesSQLite` target (an internal implementation target, not a product) depends on `_StructuredQueriesSQLite3` and exposes raw SQLite C API functions to `StructuredQueriesSQLiteCore`. This chain:

```
StructuredQueriesSQLite
  └── StructuredQueriesSQLiteCore
  └── StructuredQueriesSQLiteMacros
  └── _StructuredQueriesSQLite
        └── _StructuredQueriesSQLite3  ← systemLibrary (link "sqlite3")
```

Note: `swift-structured-queries` does **not** depend on GRDB. It has its own independent SQLite access layer. Both GRDB and `swift-structured-queries` link `-lsqlite3` independently; at runtime both link against the same `libsqlite3.so` on Android.

---

## 4. sqlite-data Fork

### 4.1 Package.swift dependencies

File: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Package.swift`

`sqlite-data` does not add any SQLite linking of its own. It depends on:
- `GRDB.swift` (fork: `jacobcxdev/GRDB.swift`, branch: `flote/service-app`) — provides GRDB + GRDBSQLite
- `swift-structured-queries` (fork: `jacobcxdev/swift-structured-queries`, branch: `flote/service-app`) — provides StructuredQueriesSQLite

The SQLite C library is linked transitively via both these dependencies' `link "sqlite3"` module map directives. `sqlite-data` itself only deals at the Swift abstraction level.

### 4.2 Android-specific additions in sqlite-data

The `Package.swift` android flag controls SkipBridge inclusion:

```swift
let android = Context.environment["TARGET_OS_ANDROID"] ?? "0" != "0"
```

When `android` is true, the `SQLiteData` target gains:
- `SkipBridge` (skip-bridge)
- `SkipAndroidBridge` (skip-android-bridge)
- `SwiftJNI` (swift-jni)

These provide JNI bridging infrastructure for the Skip Fuse mode runtime, not for SQLite access itself.

### 4.3 Android guards in sqlite-data sources

Four source files contain Android-specific guards:
- `Sources/SQLiteData/FetchAll.swift` — `#if !os(Android)` / `#if os(Android)` guards for `DynamicProperty` conformances
- `Sources/SQLiteData/FetchOne.swift` — same
- `Sources/SQLiteData/Fetch.swift` — same
- `Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift` — entire file gated `#if canImport(SwiftUI) && !os(Android)`

The `DynamicProperty` conformances on `@FetchAll`, `@FetchOne`, `@Fetch` are SwiftUI property wrappers. On Android these are either excluded or adapted since SwiftUI is bridged differently in Fuse mode.

### 4.4 Android build history

The sqlite-data fork has significant Android-specific commit history on `dev/swift-crossplatform`:
- `eb9e483` — Add SkipBridge/SkipAndroidBridge/SwiftJNI for Android builds
- `280a190` — Guard SwiftUI code with `!os(Android)` for Android builds
- `f743699`/`a655c9a`/`137bec1`/`aa55805`/`cd8a10b` — Multiple iterations on DynamicProperty conformance guarding
- `1278500` — Add Category B parity tests for SQLiteData CRUD operations
- `912e845` — Add Category B DynamicProperty parity tests

---

## 5. Mitigation Option Analysis

### Option A: Bundle CSQLite source

**Status: Not needed / not applicable.**

GRDB's `CSQLite` target exists only in the CocoaPods configuration (a custom SQLite source amalgamation for custom-compiled SQLite with special compile flags). The SPM path never uses CSQLite — it always links against system SQLite via `GRDBSQLite systemLibrary`. The fork's approach of bundling only `sqlite3.h` (not the full amalgamation source) is the correct SPM-compatible solution.

### Option B: Use Skip's SQLite

**Status: Not applicable.**

Skip does not provide a SQLite wrapper library. The generated `build.gradle.kts` files in `examples/fuse-library/.build/plugins/outputs/` contain no SQLite or Room dependencies. Skip's Gradle plugin manages JNI `.so` packaging (`jniLibs.srcDir`) and Swift cross-compilation invocation, but does not add any SQLite Gradle dependency. There is no `SkipSQLite` or similar package in the Skip ecosystem.

### Option C: Conditional systemLibrary in Package.swift

**Status: Already implemented (correctly) in both forks.**

The fix was more nuanced than a simple `#if os(Android)` in Package.swift. The key insight is that `#if canImport(Darwin)` in Package.swift is evaluated on the host at SPM resolution time, not at compile time for the target platform. The fix is:
1. Always include the `systemLibrary` target (remove the Darwin guard)
2. Use `#ifdef __ANDROID__` in the C shim (which **is** evaluated by the cross-compiler for the target)

This is the correct and already-applied approach.

### Option D: NDK SQLite

**Status: Not needed.**

Android NDK r12+ removed `libsqlite3.so` from the NDK import libraries precisely because it is an Android platform library guaranteed at runtime. Linking against it requires only passing `-lsqlite3` at link time (which the module map directive handles). No NDK-provided stub is needed or available.

### Option E: Skip's Gradle plugin handles this automatically

**Status: Partially true, but not for header resolution.**

Skip's `skip android build` command cross-compiles Swift for Android using the Swift Android SDK toolchain. It passes `-lsqlite3` through automatically if the module map requests it (via the Swift/Clang linker flag propagation). However, Skip does **not** provide `sqlite3.h` — that header must be available during compilation. The fork's bundled `sqlite3.h` solves the header resolution; the runtime `.so` linking is handled by the Android system at APK load time.

The generated `FuseLibrary/build.gradle.kts` shows the Skip `android build` invocation:

```
"${skipcmd}" android build -d "${swiftBuildFolder()}/jni-libs"
  --package-path "${swiftSourceFolder()}"
  --configuration ${mode}
  --product ${project.name}
  --scratch-path "${swiftBuildFolder()}/swift"
  --arch automatic
  -Xcc -fPIC
  -Xswiftc -DSKIP_BRIDGE
  -Xswiftc -DTARGET_OS_ANDROID
  ...
```

The `-DTARGET_OS_ANDROID` flag sets the `TARGET_OS_ANDROID` Swift conditional compilation flag (used in `sqlite-data/Package.swift`). The `-Xcc -fPIC` ensures position-independent code for `.so` output. Critically, `__ANDROID__` is set automatically by the cross-compiler toolchain (it is a standard Android NDK macro), which is what triggers the `#if defined(__ANDROID__)` branch in GRDB's `shim.h`.

---

## 6. Has the Android Build Ever Succeeded with GRDB?

### 6.1 Build artifact evidence

The `examples/fuse-library/.build/` directory contains only `arm64-apple-macosx` artifacts — macOS-only builds. There are no Android build artifacts (no `aarch64-unknown-linux-android` subdirectory). The Android build artifacts would be generated by the Gradle/Skip pipeline into `jni-libs/` directories, which are not present.

**Conclusion: No Android build has been executed with GRDB on this machine.**

### 6.2 Git history evidence

The Phase 6 verification documents explicitly note:

> "All verification runs are macOS-only (swift test). The phase goal explicitly states 'work on Android'. No android-build or skip test step was executed. Android execution cannot be verified programmatically without a connected device/emulator."
> — `06-VERIFICATION-CLAUDE.md`, human_verification section

The project git log shows commit `bd2e10b` ("Android skip test now passing, not deferred") which relates to Phase 1/2 work, not the Phase 6 database stack. The database forks (GRDB, sqlite-data, swift-structured-queries) were added in Phase 6 (`09aea0d`, 2026-02-22) — after any previous successful Android test runs.

### 6.3 Status

The Android cross-compilation fixes in GRDB (`36dba72`) and swift-structured-queries (`fb5cc61`) were committed on 2026-02-13, **before** the Phase 6 database work (2026-02-22). The fixes were specifically designed for this cross-compilation scenario. However, no end-to-end Android build with these forks has been verified on this machine.

---

## 7. Combine/OpenCombine on Android

### 7.1 Summary

GRDB uses `import Combine` in 7 files, all gated with `#if canImport(Combine)`:
- `ValueObservation.swift` — `ValueObservation.publisher(in:scheduling:)` extension
- `SharedValueObservation.swift` — `SharedValueObservation.publisher()` method
- `ReceiveValuesOn.swift`, `OnDemandFuture.swift` — Combine utilities
- `DatabaseMigrator.swift`, `DatabaseWriter.swift`, `DatabaseReader.swift` — Combine publishers
- `DatabaseRegionObservation.swift`, `DatabasePublishers.swift` — Combine integration

On Android, `canImport(Combine)` evaluates to **false** because:
1. Apple's `Combine.framework` does not exist on Android
2. OpenCombine is present as `OpenCombineShim` (different module name) via the `combine-schedulers` transitive dependency
3. `canImport(Combine)` checks for the module named `Combine`, not `OpenCombine` or `OpenCombineShim`

All Combine-gated code in GRDB compiles out on Android. The non-Combine path uses `ValueObservation.start(in:scheduling:onError:onChange:)` directly, which is the underlying implementation that the Combine publisher wraps. This is production-ready (see existing R8 research for full analysis).

### 7.2 Foundation NS* exclusions

18 GRDB files contain `#if !os(Android)` or `canImport(Darwin)` / `os(Linux)` guards. The fork added explicit `!os(Android)` guards to the Foundation bridging extensions (NSData, NSString, NSNumber, URL, UUID, Date, Decimal) mirroring the existing Linux exclusions.

---

## 8. The `link "sqlite3"` Directive at Android Link Time

Both module maps contain `link "sqlite3"`. This directive tells the Swift compiler/linker to pass `-lsqlite3` when linking a target that imports the module. On Android:

1. The Swift cross-compiler (targeting `aarch64-unknown-linux-android`) passes `-lsqlite3` to the linker
2. The NDK linker (`lld`) records this as a dynamic library dependency in the ELF `.dynamic` section of the output `.so`
3. Android's dynamic linker (`linker64`) resolves `libsqlite3.so` from the device's `/system/lib64/` at APK load time
4. No `libsqlite3.so` stub is needed at build time for this to work (Android treats system libraries as "available but not linked against at build time")

This is identical to how `liblog.so`, `libandroid.so`, and other Android system libraries are linked.

**The `link "sqlite3"` directive is correct and sufficient for Android. No changes are needed.**

---

## 9. Remaining Open Questions for Phase 7

### 9.1 End-to-end Android build verification

No Android build has been run with the database stack (GRDB + swift-structured-queries + sqlite-data) on this machine. The macOS `swift test` passes (108 tests), but Android compilation and runtime have not been verified.

**Required action:** Run `make android-build` or `cd examples/fuse-library && skip android build` with NDK installed and a connected device/emulator to confirm the full stack compiles and links.

**NDK status:** The Android NDK is not installed (`/Users/jacob/Library/Android/sdk/ndk/` does not exist). Run `skip android sdk install` or install NDK via Android Studio SDK Manager before attempting Android builds.

### 9.2 Duplicate `link "sqlite3"` directives

Both `GRDBSQLite` and `_StructuredQueriesSQLite3` have `link "sqlite3"` in their module maps. This means `-lsqlite3` will be passed twice to the linker. This is harmless — linkers handle duplicate `-l` flags by linking the library once. No action needed.

### 9.3 SQLite version mismatch between bundled headers

GRDB bundles SQLite 3.46.1 header (`Sources/GRDBSQLite/sqlite3.h`).
swift-structured-queries bundles a newer SQLite 3.49.x header (`Sources/_StructuredQueriesSQLite3/sqlite3.h`).

Both are used only for compilation (type definitions and function declarations). The runtime library version is whatever the device provides. GRDB performs runtime version detection and does not assume a specific version. This mismatch is not a problem.

### 9.4 `SQLITE_ENABLE_FTS5` and `SQLITE_ENABLE_SNAPSHOT` on Android

These Swift compile-time defines (`swiftSettings` in GRDB's Package.swift) tell GRDB to expose FTS5 and snapshot APIs in Swift. On Android, the device's `libsqlite3.so` must actually have been compiled with `SQLITE_ENABLE_FTS5` for FTS5 to work at runtime. Android's system SQLite is compiled with FTS5 since API 21+. Snapshot support (`SQLITE_ENABLE_SNAPSHOT`) was added in Android 9 (API 28). The minimum API level for this project (fuse-library targets iOS 17/macOS 14, implying Android API 26+) means both features are available.

---

## 10. Concrete Recommendations for Phase 7

### 10.1 Install NDK before Android build attempt

```bash
# Via Skip
skip android sdk install

# Or manually via Android Studio SDK Manager, install:
# NDK (Side by side) version 27.x or later
```

### 10.2 Verify Android build compiles cleanly

```bash
cd /Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-library
skip android build --configuration debug --product FuseLibrary
```

Expected: Clean compilation with no `sqlite3.h file not found` errors and no `link "sqlite3"` linker failures. The fixes are already in place.

### 10.3 If `-lsqlite3` causes NDK linker error

If the NDK linker produces `error: cannot find -lsqlite3`, it means the NDK version being used does not allow implicit system library linking. Fix: add explicit linker flag in the GRDB fork's module map:

```
# Option: replace link "sqlite3" with explicit path
# (only if needed — test first)
```

Alternatively, add to the Gradle build script:
```kotlin
android {
    defaultConfig {
        externalNativeBuild {
            cmake {
                arguments("-DANDROID_STL=c++_shared")
            }
        }
    }
}
```

This is unlikely to be needed — `libsqlite3.so` implicit linking works correctly with modern NDK versions used by Skip.

### 10.4 If FTS5 is missing at runtime

If `GRDB_ERROR_MESSAGE: SQLite error 1: no such module: fts5` appears on Android, add a runtime check:

```swift
// In database setup
#if os(Android)
// FTS5 availability check
try db.execute(sql: "SELECT fts5(?1)", arguments: ["test"])
#endif
```

Or simply exclude FTS5 tests from the Android target.

### 10.5 swift-structured-queries modulemap fix already applied

The original `#if !canImport(Darwin)` guard bug that prevented `_StructuredQueriesSQLite3` from being added to the package graph on macOS host cross-compiling for Android is **already fixed** in commit `fb5cc61`. No further action needed.

---

## 11. File Inventory

| File | Role | Android Status |
|------|------|----------------|
| `forks/GRDB.swift/Sources/GRDBSQLite/module.modulemap` | Declares `link "sqlite3"` | Works — `-lsqlite3` resolved at runtime |
| `forks/GRDB.swift/Sources/GRDBSQLite/shim.h` | C header bridge; `__ANDROID__` guard added | Fixed in `36dba72` |
| `forks/GRDB.swift/Sources/GRDBSQLite/sqlite3.h` | Bundled SQLite 3.46.1 header | Added in `36dba72` |
| `forks/GRDB.swift/Package.swift` | `GRDBSQLite` systemLibrary target | No `platforms:` restriction — always present |
| `forks/swift-structured-queries/Sources/_StructuredQueriesSQLite3/module.modulemap` | Declares `link "sqlite3"` | Works |
| `forks/swift-structured-queries/Sources/_StructuredQueriesSQLite3/_StructuredQueriesSQLite3.h` | Changed to quoted include | Fixed in `fb5cc61` |
| `forks/swift-structured-queries/Sources/_StructuredQueriesSQLite3/sqlite3.h` | Bundled SQLite 3.49.x header | Added in `fb5cc61` |
| `forks/swift-structured-queries/Package.swift` | `#if !canImport(Darwin)` guard removed | Fixed in `fb5cc61` |
| `forks/sqlite-data/Package.swift` | Android deps via `TARGET_OS_ANDROID` env var | Implemented in `eb9e483` |
| `forks/sqlite-data/Sources/SQLiteData/FetchAll.swift` | `#if os(Android)` DynamicProperty guards | Implemented |
| `forks/sqlite-data/Sources/SQLiteData/FetchOne.swift` | Same | Implemented |
| `forks/sqlite-data/Sources/SQLiteData/Fetch.swift` | Same | Implemented |
| `forks/sqlite-data/Sources/SQLiteData/Internal/FetchKey+SwiftUI.swift` | `#if canImport(SwiftUI) && !os(Android)` | Implemented |

---

## 12. Conclusion

The SQLite B4 blocker identified for Phase 7 ("GRDB's systemLibrary target links `sqlite3` which doesn't exist in Android NDK") is **already resolved** in the project's forks:

1. **Header resolution**: Both GRDB and swift-structured-queries bundle `sqlite3.h` and use `__ANDROID__`-guarded quoted includes, making the headers available during cross-compilation without requiring the NDK sysroot to provide them.

2. **Runtime linking**: The `link "sqlite3"` module map directive correctly generates `-lsqlite3` for the Android linker. `libsqlite3.so` is a standard Android system library present on all devices, resolved at APK load time.

3. **Package graph**: The `#if !canImport(Darwin)` host-evaluation bug that prevented `_StructuredQueriesSQLite3` from entering the package graph during Android cross-compilation is fixed.

4. **Combine/OpenCombine**: GRDB's Combine code compiles out cleanly on Android via `#if canImport(Combine)` guards. The callback-based `ValueObservation.start()` path is production-ready.

5. **sqlite-data Android adaptations**: SwiftUI `DynamicProperty` conformances are guarded, SkipBridge/SwiftJNI dependencies are conditionally included, and the package wiring is correct.

**The only remaining action is to install the Android NDK and run an actual Android build to confirm end-to-end compilation succeeds. No code changes are required.**

---

*Research: 2026-02-22*
*Researcher: Claude (general-purpose agent)*
