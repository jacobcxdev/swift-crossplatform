---
phase: 02-foundation-libraries
plan: 03
status: complete
started: 2026-02-21
completed: 2026-02-21
duration: ~10min
tasks_completed: 4
tasks_total: 4
key-decisions:
  - "CasePaths zero fork changes needed — @CasePathable macro output and EnumMetadata ABI are pure Swift"
  - "CustomDump zero fork changes needed — all Apple-only conformances already guarded with canImport"
  - "EnumMetadata ABI pointer arithmetic confirmed working on macOS (critical for TCA Phase 3)"
  - "CustomDump Optional formatting uses inline value display, not Optional(...) wrapper"
key-files:
  created:
    - examples/fuse-library/Tests/CasePathsTests/CasePathsTests.swift
    - examples/fuse-library/Tests/CustomDumpTests/CustomDumpTests.swift
  modified: []
---

# Phase 2 Plan 03: CasePaths & CustomDump Validation Summary

Validated CasePaths (including critical EnumMetadata ABI smoke test) and CustomDump on macOS with 21 new tests. Zero fork changes needed for either library. Android build confirmed successful with full 17-fork dependency graph.

## Tasks Completed

| # | Task | Status | Commit |
|---|------|--------|--------|
| 1 | Validate CasePaths and write tests including EnumMetadata ABI smoke test | Done | 168a579 |
| 2 | Audit CustomDump conformances for Android compatibility | Done | (no changes needed) |
| 3 | Write CustomDump test suite for Android validation | Done | 59cf00f |
| 4 | Full Android build validation of all 4 libraries | Done | (verified, no commit) |

## What Was Built

### CasePaths Validation (Task 1)

9 tests covering CP-01 through CP-08 plus the critical EnumMetadata ABI smoke test:
- `casePathableGeneratesAccessors` — @CasePathable macro generates AllCasePaths struct
- `isCheck` — `.is(\.caseName)` returns correct Bool
- `modifyInPlace` — `.modify(\.caseName)` mutates associated value
- `dynamicMemberLookupOptional` — @dynamicMemberLookup dot-syntax returns Optional
- `allCasePathsCollection` — allCasePaths iteration returns correct count
- `caseSubscriptExtractEmbed` — `[case:]` subscript extracts and embeds values
- `nestedCasePathable` — nested @CasePathable enums compose correctly
- `anyCasePathCustomClosures` — AnyCasePath with custom embed/extract works
- `enumMetadataABISmokeTest` — **CRITICAL**: AnyCasePath(unsafe:) exercises EnumMetadata pointer arithmetic that TCA uses in 6 core files. Passes without crash.

Zero fork changes needed. CasePaths is pure Swift — @CasePathable macro output has no platform dependencies, and EnumMetadata ABI layout uses dynamically computed pointer sizes.

### CustomDump Conformance Audit (Task 2)

Audited all conformance files:
- `Foundation.swift` — Already guarded with `#if !os(WASI)` (includes Android correctly) and `#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)` for Apple-only types
- `SwiftUI.swift` — Already guarded with `#if canImport(SwiftUI) && !os(Android)`
- `Swift.swift` — Already guarded with `#if os(iOS) || os(macOS)...` for Duration.formatted()
- `CoreImage.swift`, `CoreMotion.swift`, etc. — Already guarded with `#if canImport()`

**No changes needed.** All Apple-only conformances were already properly guarded.

### CustomDump Tests (Task 3)

12 tests covering CD-01 through CD-05 plus Mirror validation:
- `customDumpStructOutput` — struct produces labeled field output
- `customDumpEnumOutput` — enum with associated value dumps correctly
- `customDumpCollectionOutput` — arrays dump element values
- `customDumpOptionalNil` — nil Optional dumps as "nil"
- `stringCustomDumping` — String(customDumping:) convenience works
- `diffDetectsChanges` — diff returns non-nil for different values
- `diffReturnsNilForEqualValues` — diff returns nil for equal values
- `diffEnumChanges` — diff detects enum case changes
- `expectNoDifferencePassesForEqualValues` — no failure for equal values
- `expectNoDifferenceFailsForDifferentValues` — fires reportIssue (withKnownIssue)
- `expectDifferenceDetectsChanges` — validates state mutation matches expectation
- `customDumpNestedStruct` — nested struct Mirror output correct

### Android Validation (Task 4)

- `make android-build` succeeds with full 17-fork dependency graph (13.99s)
- All 34 macOS tests pass (7 observation + 9 CasePaths + 12 CustomDump + 6 IssueReporting + 7 IdentifiedCollections, minus 7 withKnownIssue expected failures)
- Skip test infrastructure limitation: `make skip-test` cannot run per-library tests on Android emulator (documented in 01-02-SUMMARY). Android runtime verification deferred to Phase 7.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed CustomDump Optional formatting assertion**
- **Found during:** Task 3
- **Issue:** Plan template assumed CustomDump formats optionals as `Optional("value")` or `.some("value")`. Actual output inlines the value directly.
- **Fix:** Simplified assertion to check for value presence (`output.contains("blob@example.com")`) instead of wrapper format
- **Files modified:** `examples/fuse-library/Tests/CustomDumpTests/CustomDumpTests.swift`
- **Commit:** 59cf00f

## Verification Results

- 38 upstream swift-case-paths tests pass on macOS (0 failures)
- Upstream swift-custom-dump tests pass on macOS (0 failures)
- 9 CasePaths per-library tests pass on macOS
- 12 CustomDump per-library tests pass on macOS
- 21 total new tests + all existing tests pass (0 regressions)
- Zero diff in swift-case-paths fork
- Zero diff in swift-custom-dump fork
- Android build succeeds with full dependency graph

## Self-Check: PASSED

- [x] All test files exist on disk
- [x] All task commits verified (168a579, 59cf00f)
- [x] 21 new tests pass on macOS
- [x] Upstream tests pass across both forks (0 regressions)
- [x] Zero diff in both forks (no changes needed)
- [x] Android build succeeds
