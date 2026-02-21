---
phase: 02-foundation-libraries
plan: 02
status: complete
started: 2026-02-21
completed: 2026-02-21
duration: ~5min
tasks_completed: 3
tasks_total: 3
key-decisions:
  - "Android isTesting detection via process args, dlsym, and env vars (not Darwin-specific checks)"
  - "dlopen/dlsym os(Android) added alongside os(Linux) for ELF dynamic linking"
  - "IssueReportingTestSupport added as test dependency to enable proper test failure routing"
  - "IdentifiedCollections confirmed zero-change (pure Swift data structures work unchanged)"
key-files:
  created:
    - examples/fuse-library/Tests/IssueReportingTests/IssueReportingTests.swift
    - examples/fuse-library/Tests/IdentifiedCollectionsTests/IdentifiedCollectionsTests.swift
  modified:
    - forks/xctest-dynamic-overlay/Sources/IssueReporting/IsTesting.swift
    - forks/xctest-dynamic-overlay/Sources/IssueReporting/Internal/SwiftTesting.swift
    - examples/fuse-library/Package.swift
---

# Phase 2 Plan 02: IssueReporting Android Fix & IdentifiedCollections Validation Summary

Fixed IssueReporting's three-layer Android detection failure (isTesting, dlsym, fallback) with inline #if os(Android) guards and confirmed IdentifiedCollections works unchanged. 13 new tests all pass on macOS.

## Tasks Completed

| # | Task | Status | Commit |
|---|------|--------|--------|
| 1 | Fix IssueReporting test context detection for Android | Done | c513c9a |
| 2 | Write IssueReporting test suite for Android validation | Done | bf99b8e |
| 3 | Validate IdentifiedCollections and write tests | Done | 7c9f883 |

## What Was Built

### IssueReporting Android Fix (Task 1)

**Layer 1 -- isTesting detection (`IsTesting.swift`):**
Added `#if os(Android)` branch that detects the test context via three mechanisms:
1. Process arguments containing "xctest" or "XCTest" (swift-corelibs-xctest pattern)
2. dlsym check for loaded XCTest symbols
3. swift-corelibs-xctest environment variables (`XCTestBundlePath`, `XCTestConfigurationFilePath`)

This short-circuits before the Darwin-specific checks (Xcode env vars, `.xctest` path extension).

**Layer 2 -- dlsym resolution (`SwiftTesting.swift`):**
Changed `#if os(Linux)` to `#if os(Linux) || os(Android)` in the `unsafeBitCast(symbol:in:to:)` function. Android uses the same ELF dynamic linking as Linux (`dlopen("lib\(library).so", RTLD_LAZY)`). Without this, all symbol lookups fall through to `return nil`, making IssueReportingTestSupport and Swift Testing symbol resolution fail silently.

**Layer 3 -- Fallback paths (documented, no change needed):**
The `#if DEBUG && canImport(Darwin)` guards in `_recordIssue`/`_recordError`/`_withKnownIssue` are Darwin-only direct-dlsym fallbacks for when IssueReportingTestSupport isn't linked. On Android, the primary path through `function(for:)` -> `unsafeBitCast` will now work correctly since Layer 2 was fixed. The `#else` path prints an error message, which is acceptable for the edge case where the test support library isn't linked.

### IssueReporting Tests (Task 2)

6 tests covering IR-01 through IR-04:
- `reportIssueStringMessage` -- verifies string-based reportIssue causes test failure
- `reportIssueErrorInstance` -- verifies Error-based reportIssue causes test failure
- `withErrorReportingSyncCatchesErrors` -- verifies sync error catching and reporting
- `withErrorReportingAsyncCatchesErrors` -- verifies async error catching and reporting
- `reportIssueIncludesSourceLocation` -- verifies source location capture
- `withErrorReportingReturnsNilOnError` -- verifies nil return on error

All use `withKnownIssue` to verify reportIssue causes test failures without failing the suite.

### IdentifiedCollections Validation (Task 3)

7 tests covering IC-01 through IC-06 plus mutation:
- Array literal initialization, subscript read by ID, subscript write nil removes, remove by ID, ids property ordering, Codable conformance, subscript mutation

Zero fork changes needed -- IdentifiedCollections is pure Swift data structures over OrderedCollections. 40 upstream tests pass on macOS with 0 failures.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed withErrorReporting type annotation**
- **Found during:** Task 2
- **Issue:** `withErrorReporting` returns `Void?` (optional), not `Void`. Test code had `let _: Void = withErrorReporting { ... }` which caused a type error.
- **Fix:** Removed explicit type annotation, using bare `withErrorReporting { ... }` call
- **Files modified:** `examples/fuse-library/Tests/IssueReportingTests/IssueReportingTests.swift`
- **Commit:** bf99b8e

**2. [Rule 1 - Bug] Added missing Foundation import for JSONEncoder/JSONDecoder**
- **Found during:** Task 3
- **Issue:** `JSONEncoder` and `JSONDecoder` require `import Foundation` which was missing from the test file
- **Fix:** Added `import Foundation` to IdentifiedCollectionsTests.swift
- **Files modified:** `examples/fuse-library/Tests/IdentifiedCollectionsTests/IdentifiedCollectionsTests.swift`
- **Commit:** 7c9f883

**3. [Rule 2 - Missing functionality] Added IssueReportingTestSupport dependency**
- **Found during:** Task 2
- **Issue:** Without `IssueReportingTestSupport` as a test dependency, `reportIssue()` cannot properly route to test failure on non-Darwin platforms
- **Fix:** Added `.product(name: "IssueReportingTestSupport", package: "xctest-dynamic-overlay")` to the IssueReportingTests target in Package.swift
- **Files modified:** `examples/fuse-library/Package.swift`
- **Commit:** bf99b8e

## Verification Results

- 40 upstream xctest-dynamic-overlay tests pass on macOS (0 failures)
- 40 upstream swift-identified-collections tests pass on macOS (0 failures)
- 6 IssueReporting per-library tests pass on macOS
- 7 IdentifiedCollections per-library tests pass on macOS
- 13 total new tests + 28 existing tests all pass (1 pre-existing XCSkipTests.testSkipModule failure is unrelated Gradle build issue)
- Zero diff in swift-identified-collections fork
- IssueReporting fork changes are minimal inline `#if os(Android)` additions only

## Self-Check: PASSED

- [x] All 6 key files exist on disk
- [x] All 3 task commits verified (c513c9a, bf99b8e, 7c9f883)
- [x] 13 new tests pass on macOS
- [x] 80 upstream tests pass across both forks (0 regressions)
- [x] Zero diff in swift-identified-collections fork
