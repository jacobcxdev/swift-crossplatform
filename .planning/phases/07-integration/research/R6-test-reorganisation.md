# R6: Test Reorganisation Strategy

**Created:** 2026-02-22
**Question:** How should the existing tests be reorganised into feature-aligned targets?

## Summary

The fuse-library test suite contains **226 test methods** across **20 test targets** (22 files), validating requirements from Phases 1-6. The tests split between two frameworks: 146 XCTest methods in 14 XCTestCase classes, and 80 Swift Testing methods (34 `@Test` free functions + 46 `func test*` in Swift Testing structs across 4 suites). All 226 pass on macOS (4 expected failures via `withKnownIssue`). Wall-clock time is ~25 seconds (13s user), dominated by compilation; test execution itself completes in ~11 seconds.

The current target structure is already well-aligned to feature areas and requirement groups. **No major reorganisation is needed.** The targets map cleanly to requirement prefixes, have minimal overlap, and follow consistent naming. The main recommendations are: (1) keep the existing structure as-is for fuse-library, (2) add Phase 7 fuse-app integration test targets separately, and (3) address the small ObservationTests/ObservationTrackingTests duplication.

## Current Test Inventory

### Test Targets (20 targets, 22 files, 226 methods)

| # | Target | File(s) | Framework | Methods | Req IDs | Phase |
|---|--------|---------|-----------|---------|---------|-------|
| 1 | FuseLibraryTests | FuseLibraryTests.swift | XCTest | 2 | (scaffold) | 1 |
| 2 | FuseLibraryTests | XCSkipTests.swift | XCTest | 1 | (skip harness) | 1 |
| 3 | FuseLibraryTests | ObservationTests.swift | XCTest | 19 | OBS-07..OBS-17 (implicit) | 1 |
| 4 | ObservationTrackingTests | ObservationTrackingTests.swift | XCTest | 7 | OBS-11..OBS-15 (implicit) | 1 |
| 5 | CasePathsTests | CasePathsTests.swift | Swift Testing | 9 | CP-01..CP-08 | 2 |
| 6 | IdentifiedCollectionsTests | IdentifiedCollectionsTests.swift | Swift Testing | 7 | IC-01..IC-06 | 2 |
| 7 | CustomDumpTests | CustomDumpTests.swift | Swift Testing | 12 | CD-01..CD-05 | 2 |
| 8 | IssueReportingTests | IssueReportingTests.swift | Swift Testing | 6 | IR-01..IR-04 | 2 |
| 9 | StoreReducerTests | StoreReducerTests.swift | XCTest | 11 | TCA-01..TCA-09, TCA-16 | 3 |
| 10 | EffectTests | EffectTests.swift | XCTest | 9 | TCA-10..TCA-16, DEP-12 | 3 |
| 11 | DependencyTests | DependencyTests.swift | XCTest | 19 | DEP-01..DEP-12 | 3 |
| 12 | ObservableStateTests | ObservableStateTests.swift | XCTest | 9 | TCA-17..TCA-25, TCA-29..TCA-31 | 4 |
| 13 | BindingTests | BindingTests.swift | XCTest | 8 | TCA-19..TCA-22 | 4 |
| 14 | SharedPersistenceTests | SharedPersistenceTests.swift | XCTest | 17 | SHR-01..SHR-04, SHR-14 | 4 |
| 15 | SharedBindingTests | SharedBindingTests.swift | XCTest | 7 | SHR-05..SHR-08, SHR-11 | 4 |
| 16 | SharedObservationTests | SharedObservationTests.swift | XCTest | 9 | SHR-09, SHR-10, SHR-12, SHR-13 | 4 |
| 17 | NavigationTests | NavigationTests.swift | Swift Testing | 18 | TCA-26..TCA-28, TCA-32..TCA-35, NAV-09..NAV-15 | 5 |
| 18 | NavigationStackTests | NavigationStackTests.swift | Swift Testing | 7 | NAV-01..NAV-04, NAV-16 | 5 |
| 19 | PresentationTests | PresentationTests.swift | Swift Testing | 9 | NAV-05..NAV-08, NAV-14 | 5 |
| 20 | UIPatternTests | UIPatternTests.swift | Swift Testing | 12 | UI-01..UI-08 | 5 |
| 21 | StructuredQueriesTests | StructuredQueriesTests.swift | XCTest | 15 | SQL-01..SQL-15 | 6 |
| 22 | SQLiteDataTests | SQLiteDataTests.swift | XCTest | 13 | SD-01..SD-12 | 6 |

**Totals:** 20 targets, 22 files, 226 test methods

### Framework Split

| Framework | Targets | Files | Methods |
|-----------|---------|-------|---------|
| XCTest (XCTestCase) | 14 | 14 | 146 |
| Swift Testing (@Test / struct) | 8 | 8 | 80 |
| **Total** | **20** | **22** | **226** |

Note: Phase 2 foundation tests and Phase 5 navigation/UI tests use Swift Testing. Phase 1, 3, 4, 6 tests use XCTest. This inconsistency is cosmetic -- both frameworks run in the same `swift test` invocation and produce unified results.

### Platform-Conditional Tests

Only 3 files contain platform conditionals:

| File | Conditional | Purpose |
|------|-------------|---------|
| FuseLibraryTests.swift | `#if os(Android)` | `loadPeerLibrary` in setUp |
| ObservationTests.swift | `#if os(Android)` | `loadPeerLibrary` in setUp |
| DependencyTests.swift | `#if canImport(SwiftUI) && !os(Android)` | Guards OpenURL dependency test |
| FuseLibraryTests.swift | `#if canImport(OSLog)` | Logger import/usage |
| XCSkipTests.swift | `#if os(macOS) \|\| os(Linux)` | Skip transpiled test harness |

No test methods are entirely platform-gated. The conditionals are limited to setup code and one assertion branch. All 226 tests execute on macOS.

## Coverage Map

### Requirements with Tests (by prefix)

| Prefix | Total Reqs | Tested | Covered IDs | Untested IDs |
|--------|-----------|--------|-------------|--------------|
| OBS | 30 | 0 (explicit) | None explicitly tagged | OBS-01..OBS-30 |
| TCA | 35 | 26 | TCA-01..TCA-25, TCA-26..TCA-35 | None |
| DEP | 12 | 12 | DEP-01..DEP-12 | None |
| SHR | 14 | 14 | SHR-01..SHR-14 | None |
| NAV | 16 | 16 | NAV-01..NAV-16 | None |
| CP | 8 | 8 | CP-01..CP-08 | None |
| IC | 6 | 6 | IC-01..IC-06 | None |
| CD | 5 | 5 | CD-01..CD-05 | None |
| IR | 4 | 4 | IR-01..IR-04 | None |
| UI | 8 | 8 | UI-01..UI-08 | None |
| SQL | 15 | 15 | SQL-01..SQL-15 | None |
| SD | 12 | 12 | SD-01..SD-12 | None |
| TEST | 12 | 0 | None | TEST-01..TEST-12 |
| SPM | 6 | 0 | None | SPM-01..SPM-06 |
| DOC | 1 | 0 | None | DOC-01 |

**Notes on OBS requirements:** The ObservationTests and ObservationTrackingTests validate observation semantics (tracking, mutations, ignored properties, nesting, coalescing) but do not carry explicit `OBS-*` MARK comments. They implicitly cover OBS-07 through OBS-17 via property CRUD and ObservationVerifier calls. The OBS requirements are primarily Android bridge-level concerns (JNI, Compose recomposition) that require on-device testing -- Phase 7's TEST-10 scope.

**TEST, SPM, DOC:** These are Phase 7 deliverables. No existing tests cover them.

### Test Type Classification

| Type | Count | Description |
|------|-------|-------------|
| Unit (isolated) | 184 | Single-concern: one module, mock/test dependencies, no cross-target imports |
| Integration (multi-component) | 42 | Tests that exercise reducer + effects + dependencies together (DependencyTests inheritance chain, NavigationTests with presentation + dismiss + AlertState, SQLiteDataTests observation + DI) |

Most TCA tests are lightweight integration tests: they use `TestStore` or `Store` which inherently exercises Store + Reducer + Effect + Dependency. However, each test validates one specific API pattern, so they function as unit tests from a requirement perspective.

## Overlap Analysis

### Identified Overlaps

**1. ObservationTests vs ObservationTrackingTests (HIGH overlap)**

Both test the same `ObservationVerifier` static methods. ObservationTrackingTests has 7 methods that are exact subsets of ObservationTests' 19 methods:

| ObservationTrackingTests | ObservationTests equivalent |
|--------------------------|---------------------------|
| testBasicPropertyObservation | testVerifyBasicTracking |
| testMultiplePropertyObservation | testVerifyMultiplePropertyTracking |
| testObservationIgnoredTracking | testVerifyIgnoredProperty |
| testComputedPropertyObservation | testVerifyComputedPropertyTracking |
| testMultipleObservablesTracking | testVerifyMultipleObservables |
| testNestedObservableTracking | testVerifyNestedTracking |
| testSequentialObservations | testVerifySequentialTracking |

Both call identical `ObservationVerifier.verify*()` methods and assert `true`. The only difference is the test class name and file location. **ObservationTrackingTests is fully redundant** with the "bridge verification" section of ObservationTests.

**Recommendation:** Remove ObservationTrackingTests target entirely. Its 7 tests are duplicates. This reduces target count by 1 and removes 7 redundant tests.

**2. EffectTests TCA-11+DEP-12 vs DependencyTests DEP-12 (MINOR overlap)**

EffectTests has `testEffectRunWithDependencies` (TCA-11 + DEP-12) and DependencyTests has `testDependencyResolvesInEffectClosure` (DEP-12) and `testDependencyResolvesInMergedEffects` (DEP-12). Both validate DEP-12 but from different angles -- EffectTests validates the Effect.run path, DependencyTests validates the dependency resolution contract. **This is complementary, not redundant.** No action needed.

**3. NAV-14 in both NavigationTests and PresentationTests (MINOR overlap)**

NavigationTests has `testPresentationActionDismissNilsState` (NAV-14) and PresentationTests has `testDismissViaBindingNil` (NAV-14). Both test dismiss-via-nil but NavigationTests tests it through PresentationAction.dismiss, while PresentationTests tests via direct binding nil. **Complementary coverage of the same requirement.** No action needed.

### Redundancy with Future Integration Tests

Phase 7 adds TEST-01 through TEST-12 (TestStore, exhaustivity, stress tests, fuse-app showcase). These are **additive** and do not overlap with existing tests:

- TEST-01..TEST-09: TestStore API tests -- completely new. Existing tests use `Store` directly, not `TestStore`.
- TEST-10: Android integration test -- requires emulator, no overlap with macOS unit tests.
- TEST-11: Stress tests -- new category, no existing stress tests.
- TEST-12: fuse-app showcase -- app-level, not library-level.

**No existing tests become redundant** from Phase 7 additions.

## Package.swift Complexity

### Current State

- **108 lines** in Package.swift
- **20 test targets** defined (lines 41-106)
- **1 library target** (FuseLibrary)
- **16 package dependencies** (14 fork paths + 2 Skip URLs)
- Each test target averages 3-4 lines (name + dependencies array)

### Scalability Assessment

Swift Package Manager handles test targets efficiently. The current 20 test targets create no measurable build overhead -- SPM resolves them in parallel during the planning phase. Key considerations:

| Factor | Current | With Phase 7 additions | Concern? |
|--------|---------|----------------------|----------|
| Test targets | 20 | ~25-28 (est. +5-8 for fuse-app) | No -- SPM handles 50+ targets routinely |
| Package.swift lines | 108 | ~140-160 | No -- well within readable bounds |
| Dependency graph depth | 3-4 levels (TCA -> Dependencies -> XCTest-Dynamic-Overlay) | Same | No change |
| Build parallelism | Full (20 targets independent) | Full | No change |
| `swift package resolve` time | <2s | <2s (local path deps are instant) | No |

**Verdict:** Package.swift can comfortably accommodate 8-10 more test targets. The bottleneck is not target count but dependency compilation (TCA + all transitive deps). Adding test targets that share existing dependencies has negligible incremental cost.

### Recommendation for Phase 7

Phase 7 fuse-app tests should live in `examples/fuse-app/Package.swift`, not fuse-library. This keeps:
- **fuse-library tests**: API isolation tests (existing 226, minus 7 redundant = 219)
- **fuse-app tests**: Feature integration tests, TestStore tests, stress tests (new TEST-* requirements)

This avoids bloating fuse-library's Package.swift and maintains the dual-test-focus from D4 (library isolation + app integration).

## Build Time Assessment

### Current Metrics (macOS, M-series, incremental build warm)

| Phase | Time | Notes |
|-------|------|-------|
| `swift test` total wall clock | **~25s** | From invocation to final result |
| Compilation (incremental) | ~14s | Dominated by macro expansion + TCA compilation |
| XCTest execution | ~11s | 146 tests, 10.88s reported |
| Swift Testing execution | ~0.13s | 80 tests, 0.128s reported |
| Total test execution | ~11s | Overlap between frameworks |

### Breakdown by Test Suite (execution time)

| Suite | Time | Bottleneck |
|-------|------|-----------|
| EffectTests | 1.56s | Async effect scheduling (Task.sleep in cancel/merge tests) |
| DependencyTests | 0.25s | withDependencies scoping overhead |
| SQLiteDataTests | 0.32s | Database I/O + async observation |
| SharedObservationTests | 0.09s | Combine publisher async sequences |
| SharedBindingTests | 0.13s | MainActor async scheduling |
| All other XCTest suites | <0.02s each | Pure CPU, no I/O |
| Swift Testing (all 80) | 0.13s | All fast, no I/O |

### Impact of Adding Phase 7 Tests

- **TestStore tests (TEST-01..TEST-09):** Expected ~1-2s additional (TestStore has internal scheduling). Negligible.
- **Stress tests (TEST-11):** Could take 5-30s depending on mutation count (1000+ actions). Should be tagged or separated to allow `--filter` exclusion during normal development.
- **Android emulator tests:** Separate `skip test` invocation, not part of `swift test` timing.

**Projection:** Post-Phase 7, `swift test` on fuse-library should remain under 30s. Stress tests, if added to fuse-library, could push to 45-60s -- recommend placing them in fuse-app or behind a filter.

## Recommendations

### 1. Keep existing fuse-library structure as-is

The 20 test targets are already well-organised by feature area. Each maps to a clear requirement group. Renaming or merging targets would add churn with no benefit.

### 2. Remove ObservationTrackingTests (7 redundant tests)

This target is fully redundant with ObservationTests. Remove the target from Package.swift and delete `Tests/ObservationTrackingTests/`. Net result: 19 targets, 219 unique tests.

### 3. Place Phase 7 tests in fuse-app, not fuse-library

- TEST-01..TEST-09 (TestStore): Add to fuse-app test targets (they test the app's features via TestStore)
- TEST-10 (Android integration): fuse-app `skip test` cases
- TEST-11 (Stress tests): fuse-app test target, filterable
- TEST-12 (Showcase): fuse-app is the showcase itself

### 4. Do not harmonise XCTest vs Swift Testing

The framework split (XCTest for Phases 1/3/4/6, Swift Testing for Phases 2/5) is an artifact of progressive development. Both work correctly in the same test run. Migrating would be pure churn. New Phase 7 tests can use either framework based on developer preference (Swift Testing recommended for new work).

### 5. Add explicit OBS-* MARK comments to ObservationTests

The 19 ObservationTests methods implicitly validate OBS requirements but lack MARK comments. Adding `// MARK: OBS-07`, etc. would improve traceability without changing test logic. Low priority but improves auditability.

### 6. Consider test tagging for stress tests

If stress tests (TEST-11) land in fuse-library, use Swift Testing's `@Test(.tags(.stress))` or XCTest naming convention (`StressTests` prefix) to allow `--filter` exclusion during rapid iteration.

---

*Research completed: 2026-02-22*
*Data sources: Package.swift analysis, grep of all 22 test files, `swift test` execution with timing, REQUIREMENTS.md cross-reference*
