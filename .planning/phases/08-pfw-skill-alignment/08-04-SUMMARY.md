---
phase: 08-pfw-skill-alignment
plan: 04
subsystem: testing
tags: [swift-testing, xctest-migration, expectNoDifference, confirmation, withKnownIssue]

# Dependency graph
requires:
  - phase: 08-pfw-skill-alignment
    provides: "Wave 1-3 code fixes that test files exercise"
provides:
  - "12 XCTestCase files migrated to Swift Testing @Suite/@Test pattern"
  - "XCTestExpectation -> confirmation() pattern for async tests"
  - "XCTExpectFailure -> withKnownIssue pattern"
  - "Inverted expectations -> nonisolated counter + Task.sleep pattern"
affects: [08-05-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns: ["@Suite(.serialized) @MainActor struct for TCA tests", "confirmation(expectedCount:) for async observation", "nonisolated(unsafe) var for onChange counters"]

key-files:
  created: []
  modified:
    - examples/fuse-library/Tests/SharingTests/SharedPersistenceTests.swift
    - examples/fuse-library/Tests/TCATests/StoreReducerTests.swift
    - examples/fuse-library/Tests/TCATests/ObservableStateTests.swift
    - examples/fuse-library/Tests/TCATests/BindingTests.swift
    - examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift
    - examples/fuse-library/Tests/TCATests/EffectTests.swift
    - examples/fuse-library/Tests/TCATests/TestStoreEdgeCaseTests.swift
    - examples/fuse-library/Tests/TCATests/TestStoreTests.swift
    - examples/fuse-library/Tests/TCATests/DependencyTests.swift
    - examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift
    - examples/fuse-library/Tests/SharingTests/SharedBindingTests.swift
    - examples/fuse-library/Tests/SharingTests/SharedObservationTests.swift
    - examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift

key-decisions:
  - "ObservationTests (FuseLibraryTests + ObservationTests) kept as XCTest -- Skip-transpiled target cannot use Swift Testing macros"
  - "@_spi(Reflection) import CasePaths kept in DependencyTests -- EnumMetadata requires SPI access"
  - "Combine publishers kept in SharedObservationTests -- Observations {} async sequence not available in swift-sharing"
  - "nonisolated(unsafe) var used for onChange counters in SharedBindingTests -- LockIsolated not available in SharingTests target"

patterns-established:
  - "@Suite(.serialized) @MainActor: standard pattern for all TCA test suites"
  - "confirmation(expectedCount:): replacement for XCTestExpectation + wait(for:)"
  - "withKnownIssue: replacement for XCTExpectFailure"
  - "Issue.record + return: replacement for XCTFail (non-stopping)"

requirements-completed: []

# Metrics
duration: 18min
completed: 2026-02-23
---

# Phase 8 Plan 4: Test Modernisation Summary

**12 XCTestCase files migrated to Swift Testing @Suite/@Test with confirmation() for async, withKnownIssue for expected failures, and 225 tests passing**

## Performance

- **Duration:** 18 min
- **Started:** 2026-02-23T08:43:53Z
- **Completed:** 2026-02-23T09:02:18Z
- **Tasks:** 5
- **Files modified:** 13

## Accomplishments
- Migrated 12 of 14 targeted XCTestCase files to Swift Testing (2 kept as XCTest due to Skip transpilation)
- All 225 fuse-library tests pass (9 known issues from withKnownIssue/exhaustivity checks)
- All 30 fuse-app tests pass (2 pre-existing DatabaseFeature failures unchanged)
- XCTestExpectation patterns replaced with confirmation() for async observation tests
- Inverted expectations replaced with counter + Task.sleep pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate purely mechanical test files (Batch 1)** - `b6a03e1` (feat)
2. **Task 2: Migrate async test files (Batch 2)** - `0abdbec` (feat)
3. **Task 3: Migrate complex test files (Batch 3)** - `b48a871` (feat)
4. **Task 4: Migrate expectation-heavy test files (Batch 4)** - `28d077c` (feat)
5. **Task 5: Final verification** - verification only, no commit

## Files Created/Modified
- `SharedPersistenceTests.swift` - 15 tests: XCTestCase -> @Suite, XCTAssertEqual -> #expect
- `StoreReducerTests.swift` - 11 tests: XCTestCase -> @Suite, added expectNoDifference for arrays
- `ObservableStateTests.swift` - 10 tests: XCTestCase -> @Suite
- `BindingTests.swift` - 8 tests: XCTestCase -> @Suite, added expectNoDifference
- `StructuredQueriesTests.swift` - 15 tests: XCTestCase -> @Suite, removed TODO marker
- `EffectTests.swift` - 9 tests: XCTestCase -> @Suite
- `TestStoreEdgeCaseTests.swift` - 4 tests: XCTestCase -> @Suite
- `TestStoreTests.swift` - 13 tests: hybrid XCTest+Testing -> pure @Suite
- `DependencyTests.swift` - 19 tests: XCTExpectFailure -> withKnownIssue, XCTFail -> Issue.record
- `FuseAppIntegrationTests.swift` - 30 tests: 7 XCTestCase classes -> 7 @Suite structs
- `SharedBindingTests.swift` - 7 tests: inverted expectations -> counter + sleep
- `SharedObservationTests.swift` - 9 tests: XCTestExpectation -> confirmation()
- `SQLiteDataTests.swift` - 14 tests: XCTestExpectation -> confirmation()

## Decisions Made
- **ObservationTests kept as XCTest:** The ObservationTests target uses Skip's `skipstone` plugin for Kotlin transpilation. Skip does not support Swift Testing macros (`#expect`, `@Suite`, `@Test`), so `FuseLibraryTests.swift` and `ObservationTests.swift` must remain as XCTestCase. This means 12 of 14 targeted files were migrated (not 14).
- **@_spi(Reflection) import kept:** The plan recommended removing `@_spi(Reflection) import CasePaths` (P14), but `EnumMetadata` used in the `navigationIDEnumMetadataTag` test requires this SPI. Kept the import.
- **Combine publishers kept:** The plan recommended replacing Combine with `Observations {}` async sequence (M14), but this API does not exist in swift-sharing. Kept `$count.publisher` pattern and migrated only the XCTest expectation machinery.
- **nonisolated(unsafe) var for counters:** `LockIsolated` (from Dependencies) is not available in the SharingTests target. Used `nonisolated(unsafe) var` for onChange counters in the inverted expectation replacement.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added import Foundation to migrated files**
- **Found during:** Task 1 (Batch 1 migration)
- **Issue:** Removing `import XCTest` lost implicit Foundation import; UUID, FileManager, Data, Date not in scope
- **Fix:** Added explicit `import Foundation` to files that use Foundation types
- **Files modified:** SharedPersistenceTests.swift, StoreReducerTests.swift, ObservableStateTests.swift
- **Verification:** Build succeeds, all tests pass
- **Committed in:** b6a03e1 (Task 1 commit)

**2. [Rule 1 - Bug] Kept ObservationTests as XCTest due to Skip transpilation**
- **Found during:** Task 2 (Batch 2 migration)
- **Issue:** ObservationTests target has skipstone plugin; Skip transpiler does not support `#expect` macro
- **Fix:** Reverted FuseLibraryTests.swift and ObservationTests.swift to original XCTest format
- **Files modified:** FuseLibraryTests.swift, ObservationTests.swift
- **Verification:** Build succeeds, Skip transpilation works
- **Committed in:** 0abdbec (Task 2 commit)

**3. [Rule 1 - Bug] Kept @_spi(Reflection) import for EnumMetadata**
- **Found during:** Task 3 (DependencyTests migration)
- **Issue:** Plan said to remove @_spi(Reflection) import CasePaths as "unused", but EnumMetadata requires it
- **Fix:** Kept @_spi(Reflection) import
- **Files modified:** DependencyTests.swift
- **Verification:** EnumMetadata test compiles and passes
- **Committed in:** b48a871 (Task 3 commit)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All fixes necessary for correctness. 12/14 files migrated instead of 14 (Skip constraint). No scope creep.

## Issues Encountered
- Pre-existing DatabaseFeature test failures (addNote, deleteNote) in fuse-app continue unchanged -- schema mismatch documented in Phase 08 decisions

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- 12 test files fully migrated to Swift Testing with proper traits and assertions
- 2 ObservationTests files remain XCTest (Skip constraint -- cannot change)
- Ready for 08-05 (fork cleanup + assertion sweep)

---
*Phase: 08-pfw-skill-alignment*
*Completed: 2026-02-23*
