---
phase: 08-pfw-skill-alignment
plan: 01
subsystem: testing
tags: [structured-queries, issue-reporting, observable, pfw-alignment]

# Dependency graph
requires:
  - phase: 06-database
    provides: StructuredQueries test suite and DatabaseFeature reducer
  - phase: 07-integration
    provides: 122-test baseline across fuse-library and fuse-app
provides:
  - Named query function syntax (.eq/.gt) replacing infix operators in test files
  - Effect.run error handling with do/catch + reportIssue pattern
  - @available annotations on all @Observable classes
affects: [08-pfw-skill-alignment]

# Tech tracking
tech-stack:
  added: []
  patterns: [named-query-functions, effect-run-error-handling, observable-available-annotations]

key-files:
  created: []
  modified:
    - examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift
    - examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift
    - examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift
    - examples/fuse-library/Sources/FuseLibrary/ObservationModels.swift

key-decisions:
  - "No @Observable classes exist in fuse-app -- only @ObservableState structs (TCA pattern); annotations applied to fuse-library ObservationModels.swift instead"
  - "DatabaseFeature test failures (testAddNote, testDeleteNote) are pre-existing due to missing table schema in test setup, not caused by our changes"
  - "Test fixture @Observable classes in test files left without @available -- only source/library classes annotated"

patterns-established:
  - "Named query functions: use .eq()/.gt() instead of infix == and > in .where closures"
  - "Order by key-path: use order(by: \\.name) instead of .order { $0.name.asc() }"
  - "Effect.run error handling: wrap try blocks in do/catch with reportIssue(error)"

requirements-completed: []

# Metrics
duration: 8min
completed: 2026-02-23
---

# Phase 8 Plan 1: Wave 1 Atomic PFW Fixes Summary

**Named query functions (.eq/.gt), Effect.run error handling (do/catch + reportIssue), and @available annotations on @Observable classes**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-23T07:53:35Z
- **Completed:** 2026-02-23T08:01:54Z
- **Tasks:** 5 (including baseline verification)
- **Files modified:** 4

## Accomplishments
- Replaced all infix == and > operators with .eq()/.gt() named functions in StructuredQueries and SQLiteData test files
- Replaced all redundant .asc() calls with order(by: \.) key-path syntax (kept .desc() and collation closures)
- Wrapped all 3 Effect.run closures in DatabaseFeature.swift with do/catch + reportIssue(error)
- Added @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) to 4 @Observable classes in ObservationModels.swift
- Verified 91 fuse-library tests pass, 31 fuse-app tests run (29 pass, 2 pre-existing failures)

## Task Commits

Each task was committed atomically:

1. **Task 0: Wave 0 -- Verification Baseline** - no commit (verification only, baseline: 91 + 31 = 122 tests)
2. **Task 1: Replace infix operators with named query functions** - `fda8d09` (fix)
3. **Task 2: Add do/catch + reportIssue to Effect.run closures** - `f44f120` (fix)
4. **Task 3: Add @available annotations to @Observable classes** - `f706af0` (fix)
5. **Task 4: Final verification -- full test suite** - no commit (verification only)

## Files Created/Modified
- `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift` - Replaced infix ==, > with .eq(), .gt(); replaced .asc() with order(by:)
- `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift` - Replaced == with .eq() in fetchOne test
- `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift` - Wrapped 3 Effect.run closures with do/catch + reportIssue
- `examples/fuse-library/Sources/FuseLibrary/ObservationModels.swift` - Added @available to Counter, Parent, Child, MultiTracker

## Decisions Made
- No @Observable classes exist in fuse-app sources (only @ObservableState structs); applied annotations to fuse-library ObservationModels.swift instead
- DatabaseFeature test failures (testAddNote, testDeleteNote) are pre-existing -- "no such table: notes" due to missing schema bootstrap in test setup. Not caused by our changes; reportIssue now surfaces error properly.
- Collation ordering kept closure form (.order { $0.name.collate(.nocase) }) since key-path syntax cannot express collation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] @available annotations applied to fuse-library instead of fuse-app**
- **Found during:** Task 3
- **Issue:** Plan listed CounterFeature.swift and FuseApp.swift but neither contains @Observable class declarations. The @Observable classes are in fuse-library/Sources/FuseLibrary/ObservationModels.swift.
- **Fix:** Applied @available annotations to all 4 @Observable classes in ObservationModels.swift
- **Files modified:** examples/fuse-library/Sources/FuseLibrary/ObservationModels.swift
- **Verification:** swift build + swift test (91 tests pass)
- **Committed in:** f706af0

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Target file was different from plan but the intent ("all @Observable classes annotated") is fully satisfied.

## Issues Encountered
- DatabaseFeature tests (testAddNote, testDeleteNote) fail with "no such table: notes" -- pre-existing issue unrelated to our changes. The test setup doesn't call bootstrapDatabase(). Out of scope for this plan.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Wave 1 atomic fixes complete, safe foundation for Wave 2 structural changes (08-02)
- All 91 fuse-library tests pass
- Pre-existing DatabaseFeature test failures documented for future fix

---
*Phase: 08-pfw-skill-alignment*
*Completed: 2026-02-23*
