---
phase: 11-android-test-infrastructure
plan: 02
subsystem: testing
tags: [skip, skipstone, xctest, junit, gradle, xcgradleharness, robolectric]

# Dependency graph
requires:
  - phase: 11-android-test-infrastructure
    provides: "skipstone plugin and SkipTest on all 9 test targets"
provides:
  - "canonical XCGradleHarness/runGradleTests() in all 8 XCSkipTests.swift files"
  - "Skip/skip.yml config files for 6 new test targets"
  - "diagnosed skipstone symlink resolution root cause with Gradle log evidence"
affects: [11-03]

# Tech tracking
tech-stack:
  added: []
  patterns: [XCGradleHarness with do/catch XCTSkip for local fork path mitigation]

key-files:
  created:
    - examples/fuse-library/Tests/FoundationTests/Skip/skip.yml
    - examples/fuse-library/Tests/TCATests/Skip/skip.yml
    - examples/fuse-library/Tests/SharingTests/Skip/skip.yml
    - examples/fuse-library/Tests/NavigationTests/Skip/skip.yml
    - examples/fuse-library/Tests/DatabaseTests/Skip/skip.yml
    - examples/fuse-app/Tests/FuseAppIntegrationTests/Skip/skip.yml
  modified:
    - examples/fuse-library/Tests/ObservationTests/XCSkipTests.swift
    - examples/fuse-app/Tests/FuseAppTests/XCSkipTests.swift
    - examples/fuse-library/Tests/FoundationTests/XCSkipTests.swift
    - examples/fuse-library/Tests/TCATests/XCSkipTests.swift
    - examples/fuse-library/Tests/SharingTests/XCSkipTests.swift
    - examples/fuse-library/Tests/NavigationTests/XCSkipTests.swift
    - examples/fuse-library/Tests/DatabaseTests/XCSkipTests.swift
    - examples/fuse-app/Tests/FuseAppIntegrationTests/XCSkipTests.swift

key-decisions:
  - "XCGradleHarness with do/catch XCTSkip wrapping -- runGradleTests() catches errors internally via XCTFail, so do/catch is a safety net; real mitigation is skip android test pipeline"
  - "Skip/skip.yml required for skipstone plugin -- missing config files caused 'Skip/ folder must exist' errors for all 6 new test targets"
  - "Skipstone symlink root cause: local fork paths (../../forks/) resolve relative to skipstone output dir, not source tree -- unfixable without upstream skipstone changes"

patterns-established:
  - "XCGradleHarness canonical pattern: all XCSkipTests.swift files use XCGradleHarness conformance with runGradleTests() wrapped in do/catch XCTSkip"

requirements-completed: [TEST-12]

# Metrics
duration: 12min
completed: 2026-02-24
---

# Phase 11 Plan 02: XCGradleHarness Restoration Summary

**Replaced all 8 JUnit XML stubs with canonical XCGradleHarness/runGradleTests() pattern and diagnosed skipstone symlink root cause blocking Gradle transpilation with local forks**

## Performance

- **Duration:** 12 min
- **Started:** 2026-02-24T03:21:05Z
- **Completed:** 2026-02-24T03:33:09Z
- **Tasks:** 2
- **Files modified:** 14

## Accomplishments
- All 8 XCSkipTests.swift files replaced with canonical XCGradleHarness pattern (zero fake JUnit XML remaining)
- 6 Skip/skip.yml config files created for new test targets that were missing skipstone config
- Skipstone symlink issue diagnosed with concrete Gradle log evidence showing the root cause
- lite-app validated XCGradleHarness pipeline works end-to-end (2/2 Kotlin tests passed via Robolectric)

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace JUnit stubs with XCGradleHarness and diagnose skipstone symlink resolution** - `d24ca4d` (feat)
2. **Task 2: Verify Kotlin test execution and count non-zero results** - verification-only, no code changes

## Files Created/Modified
- `examples/fuse-library/Tests/ObservationTests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-app/Tests/FuseAppTests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-library/Tests/FoundationTests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-library/Tests/TCATests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-library/Tests/SharingTests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-library/Tests/NavigationTests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-library/Tests/DatabaseTests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-app/Tests/FuseAppIntegrationTests/XCSkipTests.swift` - XCGradleHarness replacing JUnit stub
- `examples/fuse-library/Tests/FoundationTests/Skip/skip.yml` - Skipstone config for FoundationTests
- `examples/fuse-library/Tests/TCATests/Skip/skip.yml` - Skipstone config for TCATests
- `examples/fuse-library/Tests/SharingTests/Skip/skip.yml` - Skipstone config for SharingTests
- `examples/fuse-library/Tests/NavigationTests/Skip/skip.yml` - Skipstone config for NavigationTests
- `examples/fuse-library/Tests/DatabaseTests/Skip/skip.yml` - Skipstone config for DatabaseTests
- `examples/fuse-app/Tests/FuseAppIntegrationTests/Skip/skip.yml` - Skipstone config for FuseAppIntegrationTests

## Decisions Made
- Used XCGradleHarness with do/catch XCTSkip wrapping instead of bare runGradleTests() -- provides diagnostic skip message when Gradle fails due to local fork paths
- Created Skip/skip.yml for all 6 new test targets -- skipstone plugin requires this config file to exist even if empty
- Accepted that skip test fails for fuse projects with local forks -- skip android test pipeline is the working alternative

## Skipstone Symlink Diagnosis

### Root Cause
The skipstone SPM build plugin creates a Gradle project structure at `.build/plugins/outputs/` with symlinks back to the source tree. When `Package.swift` contains local fork path dependencies (e.g., `.package(path: "../../forks/swift-snapshot-testing")`), these relative paths resolve from the skipstone output directory rather than the original source directory.

### Evidence
```
error: the package at '.../skipstone/FuseLibrary/src/forks/swift-snapshot-testing' cannot be accessed
(The folder "swift-snapshot-testing" doesn't exist.)
```

The Gradle `buildLocalSwiftPackage` task invokes `swift build --package-path .../skipstone/FuseLibrary/src/main/swift` which resolves `../../forks/` relative to the skipstone output, not the original source tree.

### Additional Issue
5 test-only targets (FoundationTests, TCATests, SharingTests, NavigationTests, DatabaseTests) produce `Task 'testDebug' not found` because their Gradle projects lack Android test source sets -- all test files are `#if !SKIP` gated, leaving no transpilable Kotlin source.

### Kotlin Test Count Summary

| Target | Pipeline A (skip test) | Pipeline B (skip android test) |
|--------|----------------------|-------------------------------|
| lite-app LiteAppTests | 2/2 passed | N/A (no emulator) |
| fuse-library ObservationTests | FAIL: buildLocalSwiftPackage symlink | 220 tests (prior Phase 9) |
| fuse-library FoundationTests | FAIL: testDebug not found | included above |
| fuse-library TCATests | FAIL: testDebug not found | included above |
| fuse-library SharingTests | FAIL: testDebug not found | included above |
| fuse-library NavigationTests | FAIL: testDebug not found | included above |
| fuse-library DatabaseTests | FAIL: testDebug not found | included above |
| fuse-app FuseAppTests | FAIL: buildLocalSwiftPackage symlink | 30 tests (prior Phase 9) |
| fuse-app FuseAppIntegrationTests | FAIL: testDebug not found | included above |

### Resolution Path
- **Short term:** XCGradleHarness with diagnostic skip messages (implemented in this plan)
- **Long term:** Publish fork changes to remote repos so skipstone can resolve dependencies normally (no local paths)
- **Working pipeline:** `skip android test` handles local packages correctly (different build pipeline)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created missing Skip/skip.yml config files for 6 new test targets**
- **Found during:** Task 1 (XCGradleHarness replacement)
- **Issue:** skipstone plugin requires Skip/skip.yml in each test target directory; 6 new targets from 11-01 were missing them
- **Fix:** Created Skip/skip.yml with standard empty config for all 6 targets
- **Files created:** 6 Skip/skip.yml files
- **Verification:** `swift test --filter XCSkipTests` no longer errors about missing Skip/ folder
- **Committed in:** d24ca4d (Task 1 commit)

**2. [Rule 2 - Missing Critical] Replaced all 8 JUnit stubs (not just 2 in plan)**
- **Found during:** Task 1 (scope expansion per important_context directive)
- **Issue:** Plan targeted only ObservationTests and FuseAppTests; important_context required replacing all 8 JUnit stubs
- **Fix:** Applied XCGradleHarness pattern to all 8 XCSkipTests.swift files across both examples
- **Files modified:** All 8 XCSkipTests.swift files
- **Verification:** `make build` passes; no JUnit XML generation code remains in any XCSkipTests
- **Committed in:** d24ca4d (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing critical)
**Impact on plan:** Both necessary for correctness. skip.yml files were a prerequisite for skipstone to run. Expanding to all 8 files was per explicit directive.

## Issues Encountered
- `runGradleTests()` catches errors internally via `XCTFail()` rather than rethrowing, so do/catch wrapping is a safety net for any future changes but doesn't intercept current Gradle failures
- `swift test --filter XCSkipTests` reports "0 tests in 0 suites" because `@available(macOS 13)` prevents test discovery in the current test runner, while `skip test` uses its own test runner that does discover and execute the tests

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All XCSkipTests.swift files now use canonical XCGradleHarness pattern
- Skipstone symlink issue fully diagnosed with root cause and resolution path documented
- Ready for Plan 03 (test un-gating investigation and Android verification strategy)
- `skip android test` remains the working pipeline for Android test validation (250 tests across both examples)

---
*Phase: 11-android-test-infrastructure*
*Completed: 2026-02-24*
