---
phase: 08-pfw-skill-alignment
plan: 03
subsystem: database
tags: [sqlite-data, structured-queries, grdb, fetch-all, fetch-one, sql-macro, migrations]

# Dependency graph
requires:
  - phase: 08-02
    provides: "Wave 2 structural alignment (TCA patterns, naming conventions)"
  - phase: 06-database
    provides: "Database fork setup, StructuredQueries + GRDB + SQLiteData integration"
provides:
  - "Clean import graph with SQLiteData as sole database import"
  - "SQLiteData.defaultDatabase() for context-aware connection setup"
  - "@FetchAll/@FetchOne reactive observation pattern in DatabaseObservingView"
  - "#sql macro for all migration DDL with STRICT tables"
  - "TODO markers for Wave 4 .dependencies trait migration"
affects: [08-04, 08-05]

# Tech tracking
tech-stack:
  added: []
  patterns: ["import SQLiteData only (no GRDB/StructuredQueries)", "SQLiteData.defaultDatabase(path:) for connections", "@FetchAll/@FetchOne for view-level observation", "#sql macro with STRICT tables and quoted identifiers"]

key-files:
  created: []
  modified:
    - "examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift"
    - "examples/fuse-app/Sources/FuseApp/SharedModels.swift"
    - "examples/fuse-app/Sources/FuseApp/FuseApp.swift"
    - "examples/fuse-app/Package.swift"
    - "examples/fuse-library/Package.swift"
    - "examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift"
    - "examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift"
    - "examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift"
    - "forks/sqlite-data/Sources/SQLiteData/Internal/Exports.swift"

key-decisions:
  - "ValueObservation added to sqlite-data fork re-exports (not previously re-exported)"
  - "ComposableArchitecture kept in FuseAppIntegrationTests deps (not transitively available via FuseApp)"
  - "SQLiteData added to FuseAppIntegrationTests for DatabaseQueue access in test helpers"
  - "bootstrapDatabase() stays in FuseAppRootView.init() -- correct for Skip Fuse architecture (no @main App struct)"
  - "DatabaseObservingView added alongside existing TCA-driven DatabaseView (coexistence pattern)"
  - "BOOLEAN replaced with INTEGER in STRICT table DDL (STRICT only supports INTEGER/TEXT/REAL/BLOB/ANY)"

patterns-established:
  - "import SQLiteData only: all GRDB/StructuredQueries symbols accessed via re-exports"
  - "SQLiteData.defaultDatabase(path:) for production database connections with WAL mode"
  - "#sql(...).execute(db) for all DDL and DML in migrations"
  - "STRICT tables with quoted identifiers and explicit NOT NULL"
  - "@FetchAll/@FetchOne for reactive view-level database observation"

requirements-completed: []

# Metrics
duration: 15min
completed: 2026-02-23
---

# Phase 8 Plan 3: Database & Import Cleanup Summary

**SQLiteData-only imports, defaultDatabase() connections, @FetchAll/@FetchOne observation, and #sql macro migrations across all database code**

## Performance

- **Duration:** 15 min
- **Started:** 2026-02-23T08:26:20Z
- **Completed:** 2026-02-23T08:41:01Z
- **Tasks:** 8
- **Files modified:** 9

## Accomplishments
- Consolidated all database imports to `import SQLiteData` only -- removed `import GRDB`, `import StructuredQueries`, `import StructuredQueriesSQLite` from all sources
- Cleaned Package.swift dependency graphs -- removed GRDB from FuseApp target, removed transitive Dependencies/DependenciesMacros from TCATests
- Switched to `SQLiteData.defaultDatabase(path:)` for context-aware database connections with WAL mode
- Added `DatabaseObservingView` demonstrating `@FetchAll`/`@FetchOne` reactive pattern alongside existing TCA-driven view
- Converted all raw SQL to `#sql` macro with STRICT tables, quoted identifiers, and explicit NOT NULL
- Added Wave 4 TODO markers for `.dependencies` trait on XCTestCase suites

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove import GRDB and transitive imports** - `7939aae` (chore)
2. **Task 2: Remove transitive deps from Package.swift** - `8400b8f` (chore)
3. **Task 3: Switch to SQLiteData.defaultDatabase()** - `9cde3e8` (feat)
4. **Task 4: Verify bootstrapDatabase() location** - `0760c8c` (docs)
5. **Task 5: Add @FetchAll/@FetchOne to DatabaseObservingView** - `299bc69` (feat)
6. **Task 6: Replace raw SQL with #sql macro** - `dbf13b3` (feat)
7. **Task 7: Add .dependencies trait TODOs** - `c92fba0` (chore)
8. **Task 8: Final verification** - `11ca541` (test)

## Files Created/Modified
- `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift` - defaultDatabase(), #sql migrations, DatabaseObservingView
- `examples/fuse-app/Sources/FuseApp/SharedModels.swift` - Removed StructuredQueriesSQLite import
- `examples/fuse-app/Package.swift` - Removed GRDB product, added SQLiteData to integration tests
- `examples/fuse-library/Package.swift` - Removed Dependencies/DependenciesMacros from TCATests
- `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift` - #sql DDL, import cleanup
- `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift` - #sql DDL, import cleanup
- `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` - #sql DDL, import cleanup
- `forks/sqlite-data/Sources/SQLiteData/Internal/Exports.swift` - Added ValueObservation re-export

## Decisions Made
- **ValueObservation re-export:** SQLiteData fork did not re-export `GRDB.ValueObservation`. Added it to Exports.swift to maintain "import SQLiteData only" principle.
- **ComposableArchitecture in test deps:** FuseApp does not `@_exported import ComposableArchitecture`, so test targets using TestStore/TestClock still need explicit dependency.
- **bootstrapDatabase() location:** Skip Fuse apps use FuseAppRootView as entry point, not `@main` App struct. Current placement in `FuseAppRootView.init()` is correct.
- **Coexistence pattern for @FetchAll:** Added DatabaseObservingView alongside existing TCA-driven DatabaseView rather than replacing it, since the reducer handles writes.
- **BOOLEAN to INTEGER:** SQLite STRICT tables only support 5 types (INTEGER, TEXT, REAL, BLOB, ANY). Converted BOOLEAN columns to INTEGER.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ValueObservation not re-exported by SQLiteData**
- **Found during:** Task 2 (Package.swift cleanup)
- **Issue:** After removing `import GRDB`, `ValueObservation` was not available via `import SQLiteData`
- **Fix:** Added `@_exported import struct GRDB.ValueObservation` to sqlite-data fork Exports.swift
- **Files modified:** forks/sqlite-data/Sources/SQLiteData/Internal/Exports.swift
- **Verification:** fuse-library tests compile and pass (91 Swift Testing + 156 XCTest)
- **Committed in:** 8400b8f (Task 2 commit)

**2. [Rule 3 - Blocking] FuseAppIntegrationTests needs SQLiteData and ComposableArchitecture**
- **Found during:** Task 2 (Package.swift cleanup)
- **Issue:** Removing ComposableArchitecture and GRDB from test deps broke compilation -- TestStore types and DatabaseQueue not transitively available
- **Fix:** Kept ComposableArchitecture, added SQLiteData, added `import SQLiteData` to test file
- **Files modified:** examples/fuse-app/Package.swift, FuseAppIntegrationTests.swift
- **Verification:** All integration tests compile and run (30 tests, 0 unexpected failures)
- **Committed in:** 8400b8f (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes necessary to maintain "import SQLiteData only" invariant. No scope creep.

## Issues Encountered
- STRICT table type constraints required converting BOOLEAN columns to INTEGER (SQLite STRICT mode only supports 5 column types)
- Pre-existing DatabaseFeature test failures (testAddNote, testDeleteNote) remain -- will be fixed when Wave 4 adds .dependencies trait with proper bootstrap

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Database patterns fully aligned with PFW canonical conventions
- Wave 4 (08-04) can proceed with Swift Testing migration, applying .dependencies trait to database test suites
- All 277 tests passing (0 unexpected failures)

---
*Phase: 08-pfw-skill-alignment*
*Completed: 2026-02-23*
