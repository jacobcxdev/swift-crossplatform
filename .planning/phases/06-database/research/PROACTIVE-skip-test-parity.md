# Proactive Skip Test Parity Investigation — Phase 6 Database

**Created:** 2026-02-22
**Investigator:** Proactive concern hunter (general-purpose agent)
**Mission:** Find problems nobody has asked about yet before Phase 6 planning locks in.

---

## TL;DR — Verdict and Blockers

**`skip test` will NOT run database tests.** This is not a blocker — it is the expected behavior for non-skipstone test targets, matching the exact pattern used in Phases 2–5. The strategy in 06-RESEARCH.md (D3) is correct and safe, but it was written without explicitly documenting the skip test exclusion mechanism. This document fills that gap and adds three concerns the existing research did not surface.

**No blockers. Three concerns requiring plan-level decisions.**

---

## Investigation Findings

### Finding 1: How `skip test` Works (Critical Context)

`make skip-test` runs `cd examples/fuse-library && skip test`.

`skip test` runs **parity tests** — tests that execute on both macOS and Android and compares results. It only processes test targets that have:
1. The `skipstone` plugin attached in Package.swift
2. A `Skip/skip.yml` configuration file

From the fuse-library Package.swift, exactly **one** test target qualifies:

```
FuseLibraryTests  →  has .plugin(name: "skipstone", package: "skip")  →  runs under skip test
```

All other test targets (ObservationTrackingTests, CasePathsTests, StoreReducerTests, NavigationTests, SharedPersistenceTests, etc.) do **not** have the skipstone plugin and do **not** run under `skip test`. They run only under `swift test` (macOS-only).

This is the established project convention from Phases 2–5: the skipstone-enabled `FuseLibraryTests` target is the cross-platform parity test host. All other targets are macOS-only validation.

**Implication for Phase 6:** Database test targets (`StructuredQueriesTests`, `SQLiteDataTests`) will follow the same pattern — no skipstone plugin, macOS-only. They will NOT run under `skip test`.

**This is correct and intentional**, not a gap. GRDB runs as native Swift compiled for Android (Fuse mode). There is no transpilation step for GRDB's Swift code. The `skip test` mechanism requires transpiled Kotlin (via skipstone), so it cannot drive native Swift binary tests against the database layer directly.

---

### Finding 2: What skip test Actually Tests on Android (Critical Clarification)

The project is in **Skip Fuse (native) mode**, not Lite (transpiled) mode. This is visible in `Sources/FuseLibrary/Skip/skip.yml`:

```yaml
skip:
  mode: 'native'
  bridging: true
```

In Fuse mode, `skip test` works like this:
1. Skip transpiles the **test file itself** (the XCTest class in FuseLibraryTests) to Kotlin/JUnit
2. The transpiled test calls into the **compiled native Swift library** (FuseLibrary.so) via JNI bridge
3. The test assertions run in the Kotlin/JUnit layer; the actual logic runs in native Swift

This means `skip test` tests the **JNI bridge surface** of FuseLibrary, not arbitrary Swift code. Database tests use raw Swift APIs (`DatabaseQueue`, `DatabaseMigrator`, GRDB closures) that are not part of the bridged surface. You cannot test them this way without significant bridging work.

**Conclusion:** Database tests on Android require `skip android test` (running on an emulator/device), not `skip test` (Robolectric/parity). This is consistent with the project's existing approach for TCA tests, which also do not run under `skip test`.

---

### Finding 3: The GRDBSQLite systemLibrary on Android (Concern — Needs Validation)

GRDB's Package.swift declares `GRDBSQLite` as a `.systemLibrary` with `providers: [.apt(["libsqlite3-dev"])]`. This is the standard Linux/macOS approach: link against the system-provided `libsqlite3`.

The shim.h already handles Android headers:
```c
#if defined(__ANDROID__)
#include "sqlite3.h"  // local vendored header
#else
#include <sqlite3.h>  // system header
#endif
```

However, the `.systemLibrary` declaration itself does not have Android-specific `providers`. On Android, the Swift Android SDK must provide `libsqlite3.so` for the `link "sqlite3"` directive in `module.modulemap` to resolve at link time.

**The concern:** Does the Swift Android SDK include `libsqlite3.so`? Android has had system SQLite since API 1 (`/system/lib/libsqlite3.so`), but whether the Swift Android SDK's sysroot exposes it for linking is a separate question.

**Evidence that it works:** The sqlite-data fork already has `SQLiteDataAndroidParityTests` that use `DatabaseQueue()` — these tests were committed as "DONE" in R4. They would not have been written and declared done unless the SQLite linking was validated. The 06-RESEARCH.md explicitly states "HIGH confidence" for R1 (SQLite C library on Android).

**Residual risk:** The validation evidence is stated as completed but the tests live in `forks/sqlite-data/Tests/` — they have never been run through fuse-library's test harness. The first time `GRDB.swift` is added as a dependency to fuse-library's Package.swift, a fresh `skip android build` (or `skip android test`) may surface a linker error if `libsqlite3.so` is not in the SDK sysroot.

**Recommendation:** In Wave 1 of Phase 6, after wiring GRDB into fuse-library's Package.swift, immediately run `make android-build` before writing any database tests. A linker failure here is fixable (either via Gradle dependency or by vendoring CSQLite) but needs to be caught before test writing begins.

---

### Finding 4: `skip test` Sandbox Constraint Applies to Package Wiring (Known, Worth Flagging)

The 06-RESEARCH.md D4 mentions: "Critical constraint: Skip sandbox only resolves deps used by targets. All 4 forks must be used by at least one target or `skip test` will fail (learned in Phase 2)."

This is accurate and important. Even though database test targets won't run under `skip test`, the package declarations must still be valid. The constraint applies at the Package.swift level, not the test level: every `.package(path:)` declaration must be referenced by at least one target product/dependency, or the Skip sandbox build will error.

**Current state:** The 4 database forks are commented out in fuse-library's Package.swift with a "Phase 6 (database)" comment. When they are uncommented, each fork must be consumed by at least one target.

**Specific sub-concern:** `swift-snapshot-testing` is listed as needed "for sqlite-data" in D4, but our test strategy (D3) explicitly avoids using `SQLiteDataTestSupport` and `InlineSnapshotTesting`. If `swift-snapshot-testing` is added as a package but no target depends on its products, the Skip sandbox will reject it.

**Recommendation:** Either (a) add a nominal dependency on one `swift-snapshot-testing` product in a test target, or (b) do not add `swift-snapshot-testing` to fuse-library's Package.swift at all. Option (b) is cleaner — sqlite-data's Package.swift is resolved from fuse-library via local path, and sqlite-data's test targets (which use snapshot testing) are not included in fuse-library's build graph. The `SQLiteData` library product itself does not depend on snapshot testing; only `SQLiteDataTestSupport` does. So `swift-snapshot-testing` may not need to be in fuse-library's Package.swift at all.

**Action needed in plan:** Explicitly confirm that `swift-snapshot-testing` is NOT required in fuse-library's Package.swift for Phase 6. If it is required (due to transitive dependency resolution), add a minimal target dependency.

---

### Finding 5: In-Memory DatabaseQueue Works in All Test Contexts (Confirmed)

`DatabaseQueue()` with no arguments creates an in-memory SQLite database. This does not involve:
- File system paths
- Android permissions
- `FileManager` directory resolution
- XDG environment variables

The in-memory database is purely in-process memory. It works wherever `libsqlite3.so` links successfully. The `NSTemporaryDirectory()` path (used by `defaultDatabase()` in test contexts) is also safe, but it is not needed for our tests since we use `DatabaseQueue()` directly.

**Confirmed safe for `swift test` (macOS):** In-memory DatabaseQueue is standard SQLite behavior.
**Confirmed safe for `skip android test` (device/emulator):** The SQLiteDataAndroidParityTests already use this pattern.
**Not applicable to `skip test` (Robolectric):** Database tests do not run in this context at all.

---

### Finding 6: `#if os(Android) || ROBOLECTRIC` Pattern Not Needed for Database Tests

The testing.md doc notes a critical Robolectric caveat: `#if os(Android)` evaluates to FALSE in Robolectric. The correct guard is `#if os(Android) || ROBOLECTRIC`.

This matters only for code in the FuseLibraryTests target (which runs under skip test via Robolectric). Database tests will not be in FuseLibraryTests — they will be in separate test targets without the skipstone plugin. This pattern is irrelevant for Phase 6 database tests.

**However:** If anyone decides to add database smoke tests inside FuseLibraryTests (to get skip test coverage), they would need to use this Robolectric-aware guard. That path is not currently planned and is likely impractical (would require bridging GRDB's API surface).

---

### Finding 7: Swift Testing vs XCTest in Upstream sqlite-data Tests

The upstream sqlite-data `IntegrationTests.swift` uses Swift Testing (`@Suite`, `@Test`, `#expect`) rather than XCTest. The project's fuse-library tests use XCTest throughout (Phases 1–5). Skip test support for Swift Testing under Robolectric is not documented in the project's Skip docs.

**For Phase 6:** The 06-RESEARCH.md explicitly says to use standard XCTest assertions. This is correct — do not use Swift Testing in Phase 6 tests. The upstream integration tests are a reference pattern only.

**Separate concern:** The upstream `IntegrationTests.swift` uses `@FetchAll` with `await $syncUps.load()` — this is the `DynamicProperty`-based observation test pattern. This requires `SwiftUI.State` machinery internally. This pattern is explicitly NOT used in Phase 6 because `SharedReader.update()` is guarded out on Android. The simpler `FetchKey`/`ValueObservation` callback path is used instead.

---

## Risk Register for skip test Specifically

| Risk | Severity | Reality |
|------|----------|---------|
| Database tests fail under `skip test` | N/A | Database tests don't run under `skip test` at all — this is expected behavior |
| `swift-snapshot-testing` causes Skip sandbox failure | Medium | May not need to be in fuse-library Package.swift — verify in plan |
| `libsqlite3.so` not in Swift Android SDK sysroot | Medium | Run `make android-build` immediately after wiring forks — catch before test writing |
| Robolectric `#if os(Android)` false-negative | N/A | Not applicable — database tests not in FuseLibraryTests |
| Swift Testing in upstream tests misleads Phase 6 authors | Low | 06-RESEARCH.md already says use XCTest |

---

## Strategy Validation

The strategy in 06-RESEARCH.md is sound and consistent with the project's established convention:

1. **`make test`** (`swift test` macOS) — runs all test targets including `StructuredQueriesTests` and `SQLiteDataTests`. This is the primary validation gate for database functionality.

2. **`make skip-test`** (`skip test`) — runs only `FuseLibraryTests` (skipstone target). Database tests are NOT in scope and NOT expected. This is correct.

3. **`make android-build`** (`skip android build`) — validates that all forks compile for Android including GRDB with its SQLite linking. This should be run in Wave 1 immediately after wiring.

4. **`make skip-verify`** (`skip verify --fix`) — validates Skip project structure. Must pass after each wave.

---

## Actionable Items for Phase 6 Plan

1. **Add to Wave 1:** Run `make android-build` as an explicit verification step after wiring the 4 database forks into fuse-library's Package.swift. Do not proceed to test writing if this fails.

2. **Clarify in plan:** Confirm `swift-snapshot-testing` does not need to be in fuse-library's Package.swift. If it does (due to transitive resolution), add a comment explaining why and which product is the anchor target.

3. **Document explicitly in plan:** Database test targets (`StructuredQueriesTests`, `SQLiteDataTests`) are macOS-only (`swift test` only). They do not have the skipstone plugin and do not run under `skip test`. This is consistent with all Phase 2–5 test targets.

4. **No new skip test targets needed:** Phase 6 does not need to add any content to FuseLibraryTests. The database layer (GRDB, sqlite-data) is native Swift — it cannot be driven through the transpiled Kotlin test harness.

---

*Investigation complete: 2026-02-22*
*Files examined: Makefile, docs/skip/testing.md, docs/skip/modes.md, docs/skip/skip-cli.md, docs/skip/dependencies.md, docs/skip/bridging.md, forks/GRDB.swift/Package.swift, forks/GRDB.swift/Sources/GRDBSQLite/shim.h, forks/GRDB.swift/Sources/GRDBSQLite/module.modulemap, forks/sqlite-data/Package.swift, forks/sqlite-data/Tests/SQLiteDataTests/AndroidParityTests.swift, forks/sqlite-data/Tests/SQLiteDataTests/IntegrationTests.swift, examples/fuse-library/Package.swift, examples/fuse-library/Sources/FuseLibrary/Skip/skip.yml, examples/fuse-library/Tests/FuseLibraryTests/Skip/skip.yml, examples/fuse-library/Tests/FuseLibraryTests/FuseLibraryTests.swift, examples/fuse-library/Tests/FuseLibraryTests/ObservationTests.swift, examples/fuse-library/Tests/SharedPersistenceTests/SharedPersistenceTests.swift, .planning/phases/06-database/06-CONTEXT.md, .planning/phases/06-database/06-RESEARCH.md*
