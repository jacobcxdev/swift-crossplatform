---
phase: 06-database
verified: 2026-02-22T18:34:49Z
status: gaps_found
score: 0/4 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 5/7
  gaps_closed: []
  gaps_remaining:
    - "SQL-09 coverage still missing rightJoin/fullJoin"
    - "SQL-11 coverage still missing avg()"
    - "SD-01..SD-12 still unchecked in REQUIREMENTS.md"
  regressions:
    - "Android/Skip-path verification was executed and currently fails (`skip test`)"
gaps:
  - truth: "@Table macro metadata and select/where/join/order/group/limit execute on Android"
    status: failed
    reason: "`skip test --filter StructuredQueriesTests` fails before Android/Skip tests complete due missing `swift-snapshot-testing` package path in skipstone output."
    artifacts:
      - path: "examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift"
        issue: "MacOS tests pass, but Android/Skip execution is blocked by build failure."
      - path: "/tmp/skip-test-2026-02-22T18:33:05Z.txt"
        issue: "XCSkipTests failure: missing folder `.../destination/skipstone/FuseLibrary/src/forks/swift-snapshot-testing`."
    missing:
      - "Fix skipstone package path/wiring so `skip test` succeeds for phase 06 targets."
  - truth: "DatabaseMigrator migrations and database.read/write transactions execute on Android"
    status: failed
    reason: "Android/Skip test run fails before validating SQLiteData behavior on Android."
    artifacts:
      - path: "examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift"
        issue: "Lifecycle tests pass on macOS only; Android verification blocked by skip failure."
    missing:
      - "Get phase tests green under `skip test` (or equivalent Android CI command)."
  - truth: "@FetchAll/@FetchOne observation macros trigger Android view updates"
    status: failed
    reason: "Tests validate `ValueObservation.tracking` callbacks, not wrapper-level `@FetchAll`/`@FetchOne`/`@Fetch` behavior in views."
    artifacts:
      - path: "examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift"
        issue: "No `@FetchAll`, `@FetchOne`, or `@Fetch` usage; only comment labels and GRDB `ValueObservation`."
    missing:
      - "Add wrapper-level observation integration tests proving macro-driven updates/recomposition on Android."
  - truth: "All phase requirement IDs are fully satisfied and reflected in tracking"
    status: partial
    reason: "All 27 IDs from plan frontmatter are present in REQUIREMENTS.md, but SQL-09 and SQL-11 are incompletely tested and SD-01..SD-12 remain unchecked."
    artifacts:
      - path: "examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift"
        issue: "`leftJoin` is present; `rightJoin`, `fullJoin`, and `avg()` are absent."
      - path: ".planning/REQUIREMENTS.md"
        issue: "SD-01..SD-12 are still `[ ]` unchecked at lines 190-201."
    missing:
      - "Add coverage for SQL-09 variants and SQL-11 avg aggregation."
      - "Update REQUIREMENTS.md SD checkboxes once validated."
---

# Phase 06: Database Verification Report (Codex)

**Phase Goal:** StructuredQueries type-safe query building and GRDB database lifecycle work on Android with observation-driven view updates  
**Verified:** 2026-02-22T18:34:49Z  
**Status:** gaps_found  
**Re-verification:** Yes

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | `@Table` + query operations execute on Android | ✗ FAILED | `StructuredQueriesTests` pass on macOS (`swift test --filter StructuredQueriesTests`), but `skip test` fails in `FuseLibraryTests.XCSkipTests/testSkipModule` due missing skipstone package path in `/tmp/skip-test-2026-02-22T18:33:05Z.txt:3253`. |
| 2 | `DatabaseMigrator` + `read`/`write` execute on Android | ✗ FAILED | `SQLiteDataTests` pass on macOS (`swift test --filter SQLiteDataTests`), but Android path blocked by the same `skip test` failure (`/tmp/skip-test-2026-02-22T18:33:05Z.txt:3389`). |
| 3 | `@FetchAll`/`@FetchOne` observation macros drive updates on Android | ✗ FAILED | Tests use `ValueObservation.tracking` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:251`, `examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:290`, `examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:328`) and do not exercise wrapper macros in view context. |
| 4 | `@Dependency(\.defaultDatabase)` injects DB into views/models on Android | ✗ FAILED | Dependency injection is tested in unit tests (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:376`, `examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:378`) but not in Android view/model execution; Android run currently fails. |

**Score:** 0/4 truths verified

## Must-Haves (Plan Frontmatter)

| Plan Truth | Status | Details |
| --- | --- | --- |
| `@Table` metadata and query building works on macOS | ✓ VERIFIED | Covered by 15 passing `StructuredQueriesTests`. |
| All 15 StructuredQueries operations produce correct results via in-memory SQLite | ⚠️ PARTIAL | SQL-09 and SQL-11 requirement scope incomplete (`rightJoin`, `fullJoin`, `avg` missing). |
| Database forks compile with no regressions | ⚠️ PARTIAL | `swift test` passes, but `skip test` fails with skipstone package-path issue. |
| `DatabaseQueue` init and read/write on macOS | ✓ VERIFIED | Lifecycle tests pass on macOS. |
| `DatabaseMigrator` runs migrations | ✓ VERIFIED | `testDatabaseMigrator` passes. |
| Observation triggers value updates | ⚠️ PARTIAL | Verified at GRDB observation layer; not wrapper-level `@Fetch*` contract. |
| `@Dependency(\.defaultDatabase)` injection in test context | ✓ VERIFIED | Covered by `testDefaultDatabaseDependency`. |

## Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `examples/fuse-library/Package.swift` | 4 DB forks + test targets | ✓ VERIFIED | Fork deps present at lines 32-35; test targets at lines 100 and 103. |
| `examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift` | SQL-01..SQL-15 coverage | ⚠️ PARTIAL | File exists and tests pass; `rightJoin`, `fullJoin`, `avg()` absent (`rg` shows only `leftJoin` at line 262). |
| `examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift` | SD-01..SD-12 coverage | ⚠️ PARTIAL | Lifecycle tests present/passing; SD-09..SD-11 implemented via `ValueObservation` instead of `@Fetch*` wrappers. |
| `.planning/REQUIREMENTS.md` | Requirement tracking updated | ⚠️ PARTIAL | All 27 phase IDs exist, but SD-01..SD-12 remain unchecked (`.planning/REQUIREMENTS.md:190`-`.planning/REQUIREMENTS.md:201`). |

## Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `examples/fuse-library/Package.swift` | `forks/sqlite-data` | local path dependency | ✓ WIRED | `.package(path: "../../forks/sqlite-data")` at line 35. |
| `examples/fuse-library/Package.swift` | `StructuredQueriesTests` target | SPM test target | ✓ WIRED | Target present at line 100. |
| `examples/fuse-library/Package.swift` | `SQLiteDataTests` target | SPM test target | ✓ WIRED | Target present at line 103. |
| `examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift` | `SQLiteData` | import + DatabaseQueue execution | ✓ WIRED | Imports and query execution compile and pass on macOS. |
| `examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift` | `Dependencies` defaultDatabase | `@Dependency(\.defaultDatabase)` | ✓ WIRED | Injection used in tests at lines 66 and 378. |
| `examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift` | `@Fetch*` wrappers | direct wrapper usage | ✗ NOT_WIRED | No `@FetchAll`, `@FetchOne`, or `@Fetch` wrapper usage in file; only comment markers and `ValueObservation`. |
| skipstone output package graph | `forks/swift-snapshot-testing` | generated path resolution | ✗ NOT_WIRED | Missing path causes `skip test` failure (`/tmp/skip-test-2026-02-22T18:33:05Z.txt:3253`). |

## Requirements Coverage

Cross-reference result: **All IDs declared in plan frontmatter exist in `.planning/REQUIREMENTS.md`**. No orphaned phase-06 IDs were found.

| Requirement | Plan | Status | Evidence |
| --- | --- | --- | --- |
| SQL-01 | 06-01 | ✓ SATISFIED (macOS) | `testTableMacro` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:89`) |
| SQL-02 | 06-01 | ✓ SATISFIED (macOS) | `testColumnPrimaryKey` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:101`) |
| SQL-03 | 06-01 | ✓ SATISFIED (macOS) | `testColumnCustomRepresentation` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:123`) |
| SQL-04 | 06-01 | ✓ SATISFIED (macOS) | `testSelectionTypeComposition` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:147`) |
| SQL-05 | 06-01 | ✓ SATISFIED (macOS) | `testSelectColumns` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:174`) |
| SQL-06 | 06-01 | ✓ SATISFIED (macOS) | `testWherePredicates` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:193`) |
| SQL-07 | 06-01 | ✓ SATISFIED (macOS) | `testFindById` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:210`) |
| SQL-08 | 06-01 | ✓ SATISFIED (macOS) | `testWhereInOperator` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:224`) |
| SQL-09 | 06-01 | ⚠️ PARTIAL | `join` + `leftJoin` only (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:241`, line 262); no `rightJoin`/`fullJoin`. |
| SQL-10 | 06-01 | ✓ SATISFIED (macOS) | `testOrderBy` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:274`) |
| SQL-11 | 06-01 | ⚠️ PARTIAL | `count/sum/min/max` tested (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:312`), no `avg()`. |
| SQL-12 | 06-01 | ✓ SATISFIED (macOS) | `testLimitOffset` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:351`) |
| SQL-13 | 06-01 | ✓ SATISFIED (macOS) | `testInsertAndUpsert` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:369`) |
| SQL-14 | 06-01 | ✓ SATISFIED (macOS) | `testUpdateAndDelete` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:407`) |
| SQL-15 | 06-01 | ✓ SATISFIED (macOS) | `testSqlMacro` (`examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift:435`) |
| SD-01 | 06-02 | ⚠️ PARTIAL | Dependency override path tested (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:64`), no direct `SQLiteData.defaultDatabase()` invocation. |
| SD-02 | 06-02 | ✓ SATISFIED (macOS) | `testDatabaseMigrator` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:94`) |
| SD-03 | 06-02 | ✓ SATISFIED (macOS) | `testSyncRead` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:124`) |
| SD-04 | 06-02 | ✓ SATISFIED (macOS) | `testSyncWrite` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:138`) |
| SD-05 | 06-02 | ✓ SATISFIED (macOS) | `testAsyncRead`/`testAsyncWrite` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:158`, `examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:170`) |
| SD-06 | 06-02 | ✓ SATISFIED (macOS) | `testFetchAll` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:189`) |
| SD-07 | 06-02 | ✓ SATISFIED (macOS) | `testFetchOne` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:207`) |
| SD-08 | 06-02 | ✓ SATISFIED (macOS) | `testFetchCount` (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:226`) |
| SD-09 | 06-02 | ⚠️ PARTIAL | `ValueObservation` callback test exists (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:248`), but no `@FetchAll` wrapper execution. |
| SD-10 | 06-02 | ⚠️ PARTIAL | `ValueObservation` single-row callback test exists (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:287`), but no `@FetchOne` wrapper execution. |
| SD-11 | 06-02 | ⚠️ PARTIAL | Composite `ValueObservation` exists (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:324`), but no `@Fetch` + `FetchKeyRequest` wrapper execution. |
| SD-12 | 06-02 | ⚠️ PARTIAL | Dependency injection tested in unit test context (`examples/fuse-library/Tests/SQLiteDataTests/SQLiteDataTests.swift:372`), not proven in Android views/models. |

**Tracking mismatch:** SD-01..SD-12 still unchecked in `.planning/REQUIREMENTS.md:190` through `.planning/REQUIREMENTS.md:201`.

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift` | 262 | Join coverage only includes `leftJoin`; no `rightJoin`/`fullJoin` | ⚠️ Warning | SQL-09 requirement scope is not fully validated. |
| `examples/fuse-library/Tests/StructuredQueriesTests/StructuredQueriesTests.swift` | 312 | No `avg()` aggregation assertion | ⚠️ Warning | SQL-11 requirement scope is not fully validated. |
| `.planning/REQUIREMENTS.md` | 190 | SD entries still unchecked | ⚠️ Warning | Requirements tracking is out of sync with current test evidence. |
| `/tmp/skip-test-2026-02-22T18:33:05Z.txt` | 3253 | Missing generated package path for `swift-snapshot-testing` | 🛑 Blocker | Android/Skip phase-goal validation currently fails. |

No TODO/FIXME/placeholder stubs were found in the phase test artifacts.

## Human Verification Required

### 1. Android Runtime Observation Semantics

**Test:** Run phase tests on a working Android/Skip pipeline after fixing skipstone path resolution, then validate `@Fetch*` wrappers in a real view/model context.  
**Expected:** Database mutations trigger wrapper-driven view updates on Android without manual GRDB observation scaffolding.  
**Why human:** Runtime view recomposition semantics cannot be fully established by current unit tests and currently cannot run due skip build blocker.

## Gaps Summary

Phase 06 is functionally strong on macOS but does not yet satisfy the Android goal contract.

1. Android/Skip verification is currently blocked by a skipstone path resolution failure for `swift-snapshot-testing`.
2. SQL requirement coverage is incomplete for SQL-09 (`rightJoin`/`fullJoin`) and SQL-11 (`avg`).
3. SD observation requirements are validated at the GRDB observation layer rather than the `@Fetch*` wrapper contract named in requirements.
4. SD requirement checkboxes in `.planning/REQUIREMENTS.md` are still not updated.

---

_Verified: 2026-02-22T18:34:49Z_  
_Verifier: Codex (gsd-verifier)_
