# Roadmap: Swift Cross-Platform

## Overview

This roadmap delivers TCA on Android via Skip Fuse mode. The observation bridge is the critical-path foundation -- every subsequent phase depends on it. From there, we build upward through foundation libraries, TCA core, state/bindings, navigation, database, and finally integration testing with documentation. Each phase delivers a coherent, testable capability that unblocks the next.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Observation Bridge** - Native Swift Observation works correctly on Android with record-replay pattern preventing infinite recomposition
- [ ] **Phase 2: Foundation Libraries** - CasePaths, IdentifiedCollections, CustomDump, and IssueReporting work on Android
- [x] **Phase 3: TCA Core** - Store, reducers, effects, and dependency injection work on Android (completed 2019-02-22)
- [x] **Phase 4: TCA State & Bindings** - ObservableState macro, bindings, and shared state persistence work on Android (completed 2019-02-22)
- [x] **Phase 5: Navigation & Presentation** - TCA navigation patterns and SwiftUI presentation lifecycle work on Android (completed 2019-02-22)
- [x] **Phase 6: Database & Queries** - StructuredQueries and GRDB/SQLiteData work on Android with observation-driven view updates (completed 2019-02-22)
- [x] **Phase 7: Integration Testing & Documentation** - End-to-end TCA app runs on both platforms; forks documented (completed 2019-02-22)
- [x] **Phase 11: Android Test Infrastructure** - Fix blockers preventing Android test execution: xctest-dynamic-overlay imports, skipstone plugin on all test targets, canonical XCGradleHarness (completed 2019-02-24)
- [x] **Phase 12: Swift Perception Android Port** - Fork swift-perception for Android; provide WithPerceptionTracking, Perceptible conformances TCA depends on (completed 2019-02-24)
- [x] **Phase 13: API Parity Gaps** - Implement Android equivalents for non-deprecated TCA APIs gated out without alternatives (completed 2019-02-24)
- [x] **Phase 14: Android Verification & Requirements Reset** - Run full Android test suite, re-verify all 169 pending requirements against actual results (completed 2019-02-24)
- [x] **Phase 15: NavigationStack Android Robustness** - Fix binding-driven push, JVM type erasure multi-destination, and dismiss JNI timing — all with test coverage (completed 2019-02-24)
- [x] **Phase 16: TCA API Parity Completion** - Enable gated Binding+Observation, Alert/Dialog, IfLetStore extensions on Android; resolve TextState CGFloat ambiguity — all with test coverage (completed 2019-02-24)
- [ ] **Phase 17: Test Evidence & Infrastructure Hardening** - Direct TEST-10/TEST-11 evidence, Robolectric pipeline fix, ObjC warning cleanup, swiftThreadingFatal version guard — all with test coverage
- [x] **Phase 18: Complete View Identity Layer Implementation** - ForEach key() wrapping for non-lazy Evaluate path, @Stable/skippability investigation and deferral (completed 2019-02-28)

## Phase Details

### Phase 1: Observation Bridge
**Goal**: Swift Observation semantics work correctly on Android -- view body evaluation triggers exactly one recomposition per observation cycle, not one per mutation
**Depends on**: Nothing (first phase)
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04, OBS-05, OBS-06, OBS-07, OBS-08, OBS-09, OBS-10, OBS-11, OBS-12, OBS-13, OBS-14, OBS-15, OBS-16, OBS-17, OBS-18, OBS-19, OBS-20, OBS-21, OBS-22, OBS-23, OBS-24, OBS-25, OBS-26, OBS-27, OBS-28, OBS-29, OBS-30, SPM-01, SPM-02, SPM-03, SPM-04, SPM-05, SPM-06
**Success Criteria** (what must be TRUE):
  1. An `@Observable` class property mutation in a view model triggers exactly one Compose recomposition (not hundreds) on Android
  2. Nested parent/child view hierarchies each independently track their own observed properties on Android
  3. `ViewModifier` bodies participate in observation tracking the same as `View` bodies on Android
  4. Bridge initialization failure produces a fatal error (crash with clear message) instead of silently falling back to broken counter-based observation
  5. All 17 fork packages compile for Android via Skip Fuse mode with correct SPM configuration
**Plans**: 2 plans in 2 waves

Plans:
- [x] 01-01-PLAN.md -- Bridge implementation fixes, diagnostics API, and observation tests (OBS-01 through OBS-30) ✓ 2019-02-21
- [x] 01-02-PLAN.md -- SPM compilation validation for all 14 forks and Android emulator integration tests (SPM-01 through SPM-06) ✓ 2019-02-21

### Phase 2: Foundation Libraries
**Goal**: Point-Free's utility libraries that TCA depends on work correctly on Android
**Depends on**: Phase 1
**Requirements**: CP-01, CP-02, CP-03, CP-04, CP-05, CP-06, CP-07, CP-08, IC-01, IC-02, IC-03, IC-04, IC-05, IC-06, CD-01, CD-02, CD-03, CD-04, CD-05, IR-01, IR-02, IR-03, IR-04
**Success Criteria** (what must be TRUE):
  1. `@CasePathable` enum pattern matching (`.is`, `.modify`, subscript extraction) works on Android
  2. `IdentifiedArrayOf` initializes, indexes by ID in O(1), and supports element removal on Android
  3. `customDump` and `diff` produce correct structured output for Swift values on Android
  4. `reportIssue` and `withErrorReporting` catch and surface runtime errors on Android
**Plans**: 3 plans in 3 waves

Plans:
- [x] 02-01-PLAN.md -- Fork housekeeping: branch rename (dev/swift-crossplatform), 3 new forks (swift-case-paths, swift-identified-collections, xctest-dynamic-overlay), Package.swift wiring for all 17 forks, per-library test targets (CP-01, CP-05, IC-01, IC-05) ✓ 2019-02-21
- [x] 02-02-PLAN.md -- IssueReporting three-layer Android fix (isTesting, dlsym, fallbacks) + IdentifiedCollections validation (IR-01 through IR-04, IC-01 through IC-06) ✓ 2019-02-21
- [x] 02-03-PLAN.md -- CasePaths validation + EnumMetadata ABI smoke test + CustomDump conformance guards and tests (CP-01 through CP-08, CD-01 through CD-05) ✓ 2019-02-21

### Phase 3: TCA Core
**Goal**: TCA Store, reducers, effects, and dependency injection work correctly on Android
**Depends on**: Phase 2
**Requirements**: TCA-01, TCA-02, TCA-03, TCA-04, TCA-05, TCA-06, TCA-07, TCA-08, TCA-09, TCA-10, TCA-11, TCA-12, TCA-13, TCA-14, TCA-15, TCA-16, DEP-01, DEP-02, DEP-03, DEP-04, DEP-06, DEP-07, DEP-08, DEP-09, DEP-10, DEP-11, DEP-12
**Success Criteria** (what must be TRUE):
  1. A TCA Store initializes, receives dispatched actions, and updates state on Android
  2. `store.scope(state:action:)` derives child stores that correctly reflect parent state changes on Android
  3. `Effect.run`, `.merge`, `.concatenate`, `.cancellable`, and `.cancel` execute async work and route actions on Android
  4. `@Dependency(\.keyPath)` resolves live values in production context and test values in test context on Android
  5. Child reducer scopes inherit parent dependency overrides on Android
**Plans**: 2 plans in 2 waves

Plans:
- [x] 03-01-PLAN.md — Store/Reducer/Effect validation + Package.swift test infrastructure with DependenciesTestSupport (TCA-01..TCA-16) ✓ 2019-02-22
- [x] 03-02-PLAN.md — Dependency injection validation: @Dependency, withDependencies, built-in deps, @DependencyClient, NavigationID (DEP-01..DEP-12) ✓ 2019-02-22

### Phase 4: TCA State & Bindings
**Goal**: ObservableState macro, two-way bindings, and shared state persistence drive correct view updates on Android
**Depends on**: Phase 3
**Requirements**: TCA-17, TCA-18, TCA-19, TCA-20, TCA-21, TCA-22, TCA-23, TCA-24, TCA-25, TCA-29, TCA-30, TCA-31, SHR-01, SHR-02, SHR-03, SHR-04, SHR-05, SHR-06, SHR-07, SHR-08, SHR-09, SHR-10, SHR-11, SHR-12, SHR-13, SHR-14
**Success Criteria** (what must be TRUE):
  1. `@ObservableState` struct property mutations propagate to views with no infinite recomposition on Android
  2. `$store.property` binding projection reads and writes state through the store, triggering exactly one view update on Android
  3. `@Shared(.appStorage)`, `@Shared(.fileStorage)`, and `@Shared(.inMemory)` persist and restore state across feature boundaries on Android
  4. `Observations { }` async sequence emits on every `@Shared` mutation on Android
  5. Multiple `@Shared` declarations with the same backing store synchronize updates on Android
**Plans**: 3 plans in 3 waves

Plans:
- [x] 04-01-PLAN.md (wave 1) — @ObservableState macro, binding projection chain, store scoping lifecycle (ForEach, optional, enum), onChange, _printChanges, @ViewAction (TCA-17..TCA-25, TCA-29..TCA-31) ✓ 2019-02-22
- [x] 04-02-PLAN.md (wave 2) — FileStorage Android enablement + @Shared persistence backend validation: appStorage, fileStorage, inMemory, custom SharedKey (SHR-01..SHR-04, SHR-14) ✓ 2019-02-22
- [x] 04-03-PLAN.md (wave 3) — @Shared binding projections, Observations async sequence, publisher emission, double-notification prevention, cross-feature synchronization (SHR-05..SHR-13) ✓ 2019-02-22

### Phase 5: Navigation & Presentation
**Goal**: TCA navigation patterns (stack, sheet, alert, confirmation dialog) and SwiftUI presentation lifecycle work on Android
**Depends on**: Phase 4
**Requirements**: NAV-01, NAV-02, NAV-03, NAV-04, NAV-05, NAV-06, NAV-07, NAV-08, NAV-09, NAV-10, NAV-11, NAV-12, NAV-13, NAV-14, NAV-15, TCA-26, TCA-27, TCA-28, TCA-32, TCA-33, TCA-34, TCA-35, UI-01, UI-02, UI-03, UI-04, UI-05, UI-06, UI-07, UI-08
**Success Criteria** (what must be TRUE):
  1. `NavigationStack` with TCA path binding pushes and pops destinations on Android
  2. `.sheet`, `.fullScreenCover`, and `.popover` present and dismiss content driven by optional TCA state on Android
  3. `AlertState` and `ConfirmationDialogState` render with correct titles, messages, buttons, and destructive roles on Android
  4. `@Presents` / `PresentationAction.dismiss` lifecycle correctly nils optional child state and closes presentation on Android
  5. `.task` modifier executes async work on view appearance without blocking recomposition on Android
**Plans**: 3 plans in 3 waves

Plans:
- [x] 05-01-PLAN.md (wave 1) — Guard removals (EphemeralState, Popover, NavigationStack+Observation) + data-layer navigation tests (TCA-26..TCA-28, TCA-32..TCA-35, NAV-09..NAV-15) ✓ 2019-02-22
- [x] 05-02-PLAN.md (wave 2) — NavigationStack Android adapter + presentation tests: sheet, fullScreenCover, popover, stack push/pop (NAV-01..NAV-08, NAV-16) ✓ 2019-02-22
- [x] 05-03-PLAN.md (wave 3) — SwiftUI pattern validation tests + full suite validation (UI-01..UI-08) ✓ 2019-02-22

### Phase 6: Database & Queries
**Goal**: StructuredQueries type-safe query building and GRDB database lifecycle work on Android with observation-driven view updates
**Depends on**: Phase 1
**Requirements**: SQL-01, SQL-02, SQL-03, SQL-04, SQL-05, SQL-06, SQL-07, SQL-08, SQL-09, SQL-10, SQL-11, SQL-12, SQL-13, SQL-14, SQL-15, SD-01, SD-02, SD-03, SD-04, SD-05, SD-06, SD-07, SD-08, SD-09, SD-10, SD-11, SD-12
**Success Criteria** (what must be TRUE):
  1. `@Table` macro generates correct metadata and `Table.select/where/join/order/group/limit` queries execute on Android
  2. `DatabaseMigrator` runs migrations and `database.read/write` execute transactions on Android
  3. `@FetchAll` and `@FetchOne` observation macros trigger view updates when underlying database rows change on Android
  4. `@Dependency(\.defaultDatabase)` injects database connection into views and models on Android
**Plans**: 2 plans in 2 waves

Plans:
- [x] 06-01-PLAN.md — Package.swift database fork wiring + StructuredQueries validation tests (SQL-01..SQL-15) ✓ 2019-02-22
- [x] 06-02-PLAN.md — SQLiteData lifecycle, GRDB transactions, observation macros, dependency injection (SD-01..SD-12) ✓ 2019-02-22

### Phase 7: Integration Testing & Documentation
**Goal**: A complete TCA app runs on both iOS and Android; all forks are documented with change rationale and upstream PR candidates
**Depends on**: Phase 5, Phase 6
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-06, TEST-07, TEST-08, TEST-09, TEST-10, TEST-11, TEST-12, DOC-01
**Success Criteria** (what must be TRUE):
  1. `TestStore` initializes, sends actions, receives effect actions, and asserts state changes on Android
  2. Integration tests confirm the observation bridge prevents infinite recomposition under real TCA workloads on Android emulator
  3. Stress tests confirm stability under >1000 TCA state mutations/second on Android
  4. A fuse-app example demonstrates full TCA app (store, reducer, effects, navigation, persistence) running on both iOS and Android
  5. FORKS.md documents every fork with upstream version, commits ahead, key changes, rationale, and upstream PR candidates
**Plans**: 4 plans in 4 waves

Plans:
- [x] 07-01-PLAN.md (wave 1) — TestStore API validation: init, send, receive, exhaustivity, finish, skipReceivedActions, dependencies, effectDidSubscribe edge cases (TEST-01..TEST-09) ✓ 2019-02-22
- [x] 07-02-PLAN.md (wave 2) — Observation bridge semantics + stress tests + Android emulator validation + deferred Phase 1 tests (TEST-10, TEST-11) ✓ 2019-02-22
- [x] 07-03-PLAN.md (wave 3) — Fuse-app showcase: 6 TCA features, integration tests, README, Android build verification (TEST-12) ✓ 2019-02-22
- [x] 07-04-PLAN.md (wave 4) — Fork documentation: FORKS.md + test reorganisation into 6 feature-aligned targets (DOC-01) ✓ 2019-02-22

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10 -> 11 -> 12 -> 13 -> 14 -> 15 -> 16 -> 17 -> 18
Note: Phase 6 (Database) depends only on Phase 1 and can run in parallel with Phases 2-5 if desired.
Note: Phases 12 and 13 could partially overlap once Phase 11 test infra is working; Phase 14 must come last.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Observation Bridge | 2/2 | Executed | - |
| 2. Foundation Libraries | 3/3 | Executed | 2019-02-21 |
| 3. TCA Core | 2/2 | Complete    | 2019-02-22 |
| 4. TCA State & Bindings | 3/3 | Complete | 2019-02-22 |
| 5. Navigation & Presentation | 3/3 | Complete | 2019-02-22 |
| 6. Database & Queries | 2/2 | Complete | 2019-02-22 |
| 7. Integration Testing & Documentation | 4/4 | Complete    | 2019-02-23 |
| 8. PFW Skill Alignment | 5/5 | Complete | 2019-02-23 |
| 9. Post-Audit Cleanup | 4/4 | Complete | 2019-02-23 |
| 10. skip-fuse-ui Integration & Audit | 8/8 | Complete    | 2019-02-24 |
| 11. Android Test Infrastructure | 3/3 | Complete   | 2019-02-24 |
| 12. Swift Perception Android Port | 2/2 | Complete    | 2019-02-24 |
| 13. API Parity Gaps | 2/2 | Complete    | 2019-02-24 |
| 14. Android Verification & Requirements Reset | 4/4 | Complete    | 2019-02-24 |
| 15. NavigationStack Android Robustness | 3/3 | Complete   | 2019-02-24 |
| 16. TCA API Parity Completion | 2/2 | Complete   | 2019-02-24 |
| 17. Test Evidence & Infrastructure Hardening | 0/0 | Planned | - |
| 18. Complete View Identity Layer | 1/1 | Complete    | 2019-02-28 |

### Phase 8: PFW Skill Alignment

**Goal:** Align all app code, test code, and fork code with Point-Free canonical API patterns as documented in `/pfw-*` skills. Address all 191 PFW audit findings with zero exceptions.
**Depends on:** Phase 7
**Requirements:** 191 PFW audit findings (no formal requirement IDs — scope defined by audit in 08-CONTEXT.md and 08-RESEARCH.md)
**Success Criteria** (what must be TRUE):
  1. All query predicates use named functions (.eq/.gt), not infix operators
  2. All test files migrated from XCTestCase to Swift Testing @Suite/@Test (except XCSkipTests.swift)
  3. All TCA patterns follow PFW conventions (action naming, Path un-nesting, @CasePathable, dismiss pattern, IdentifiedArrayOf)
  4. All database code uses import SQLiteData only, @FetchAll/@FetchOne for observation, #sql macro for migrations
  5. Fork namespace shadowing resolved; DispatchSemaphore replaced with os_unfair_lock
**Plans:** 5 plans in 5 waves

Plans:
- [x] 08-01-PLAN.md (wave 1) — Atomic single-file fixes: query syntax (.eq/.gt), Effect.run error handling, @available annotations ✓ 2019-02-23
- [x] 08-02-PLAN.md (wave 2) — Structural alignment: @CasePathable, Path un-nesting, CombineReducers, IdentifiedArrayOf, dismiss pattern, action naming ✓ 2019-02-23
- [x] 08-03-PLAN.md (wave 3) — Database & import cleanup: import SQLiteData only, defaultDatabase(), @FetchAll/@FetchOne, #sql macro, .dependencies trait ✓ 2019-02-23
- [x] 08-04-PLAN.md (wave 4) — Test modernisation: 12 XCTestCase files to Swift Testing, expectNoDifference, confirmation() replacing XCTestExpectation ✓ 2019-02-23
- [x] 08-05-PLAN.md (wave 5) — Fork cleanup + assertion sweep: bridge namespace rename, os_unfair_lock, final verification of all 191 findings ✓ 2019-02-23

### Phase 9: Post-Audit Cleanup
**Goal:** Close all gaps identified by the milestone audit — fix failing tests, fill test coverage holes, sync documentation, and verify Android test execution. All fixes must align with `/pfw-*` skills as canonical usage patterns.
**Depends on:** Phase 8
**Requirements:** Derived from MILESTONE-AUDIT.md gaps (no formal REQ-IDs — scope defined by audit findings)
**Canonical pattern references:** `/pfw-structured-queries` (SQL test patterns), `/pfw-sqlite-data` (database lifecycle & migrations), `/pfw-testing` (Swift Testing conventions), `/pfw-composable-architecture` (TCA test patterns), `/pfw-issue-reporting` (isTesting detection on Android)
**Success Criteria** (what must be TRUE):
  1. All 255 tests pass (0 failures) — DatabaseFeature test schema bootstrap fixed per `/pfw-sqlite-data` migration patterns, xctest-dynamic-overlay Android imports added per `/pfw-issue-reporting` platform guards
  2. SQL-09 (rightJoin/fullJoin) and SQL-11 (avg aggregation) have dedicated test assertions following `/pfw-structured-queries` query builder patterns
  3. REQUIREMENTS.md traceability table has all 184 requirements marked `[x]` with accurate status
  4. `skip android test` executes successfully after xctest-dynamic-overlay fork fix
  5. Empty `testOpenSettingsDependencyNoCrash` test removed or replaced with meaningful assertion following `/pfw-testing` @Test conventions
**Plans:** 4 plans in 4 waves

Plans:
- [x] 09-01-PLAN.md (wave 1) — Test fixes: xctest-dynamic-overlay Android imports (`/pfw-issue-reporting`), DatabaseFeature schema bootstrap (`/pfw-sqlite-data`), SQL-09/SQL-11 coverage (`/pfw-structured-queries`), empty test cleanup (`/pfw-testing`) ✓ 2019-02-23
- [x] 09-02-PLAN.md (wave 2) — Documentation sync: REQUIREMENTS.md 127 stale checkboxes, Perception bypass documentation ✓ 2019-02-23
- [x] 09-03-PLAN.md (wave 3) — Android verification: run `skip android test` after wave 1 fix, capture results, update STATE.md ✓ 2019-02-23
- [x] 09-04-PLAN.md (wave 4) — Gap closure: wrap 3 Android-failing tests with withKnownIssue, correct inaccurate SUMMARY, re-verify 0 real failures ✓ 2019-02-23

### Phase 10: skip-fuse-ui Fork Integration & Cross-Fork Audit
**Goal:** Resolve SPM dependency identity conflicts, perform comprehensive audit of all fork modifications against skip-fuse-ui counterparts, fix all gaps found, verify cross-platform parity, and update project documentation. Absorbs originally-proposed Phase 11 (Presentation Dismiss on Android).
**Depends on:** Phase 9
**Requirements:** NAV-01, NAV-02, NAV-03, TCA-32, TCA-33
> Note: Strengthening existing Complete status from iOS-only to cross-platform
**Gap Closure:** Closes M1-ANDROID-NAV-STACK (integration), M2-ANDROID-DISMISS (integration), Contacts deep navigation flow (E2E)
**Canonical pattern references:** `/pfw-composable-architecture` (NavigationStack path binding, PresentationAction.dismiss), `/pfw-swift-navigation` (path-driven navigation, dismiss dependency)
**Success Criteria** (what must be TRUE):
  1. Zero SPM identity conflict warnings on `swift package resolve` for both fuse-app and fuse-library
  2. All audit gaps addressed (counterparts created or documented as known limitation)
  3. Full test suite green on macOS for both fuse-app and fuse-library
  4. CLAUDE.md updated with gotchas, Makefile commands, env var documentation
  5. Makefile updated with smart defaults (both examples, both platforms)
  6. Presentation dismiss (`@Dependency(\.dismiss)`) status resolved on Android
  7. Roadmap updated with rescoped phase; Phase 11 removed
**Plans:** 8/8 plans complete

Plans:
- [x] 10-01-PLAN.md (wave 1) — CLAUDE.md + Makefile updates: gotchas, env vars, smart defaults ✓ 2019-02-24
- [x] 10-02-PLAN.md (wave 1) — SPM dependency resolution: convert remote URLs to local paths, remove unused deps ✓ 2019-02-24
- [x] 10-03-PLAN.md (wave 2) — Gap audit: skip-fuse-ui counterparts, TCA guards, dismiss, JVM type erasure ✓ 2019-02-24
- [x] 10-04-PLAN.md (wave 3) — Gap fixes + tests: implement fixes from gap report, verify dismiss, Android build ✓ 2019-02-24
- [x] 10-05-PLAN.md (wave 4) — Roadmap update + cleanup: update ROADMAP, STATE, REQUIREMENTS ✓ 2019-02-24
- [x] 10-06-PLAN.md (gap closure) — Apply CLAUDE.md + Makefile changes that were planned but never written to disk; correct STATE.md ✓ 2019-02-24
- [x] 10-07-PLAN.md (gap closure) — Fix XCSkipTests.testSkipModule failure in fuse-library: replace XCGradleHarness with JUnit results stub ✓ 2019-02-24
- [x] 10-08-PLAN.md (gap closure) — Administrative closure: 10-07 SUMMARY, STATE.md/ROADMAP corrections, known-limitation documentation ✓ 2019-02-24

### Phase 11: Android Test Infrastructure
**Goal:** Fix all blockers preventing Android test execution — xctest-dynamic-overlay imports, skipstone plugin coverage, canonical Skip testing pattern, and local package symlink compatibility
**Depends on:** Phase 10
**Requirements:** TEST-10, TEST-11, TEST-12
**Gap Closure:** Closes ANDROID-TESTING-BYPASS, NO-TCA-TESTS-ON-ANDROID, ANDROID-EMULATOR-NEVER-TESTED from v1.0-MILESTONE-AUDIT.md
**Canonical pattern references:** `/pfw-issue-reporting` (isTesting detection, platform guards), `/pfw-testing` (Swift Testing conventions)
**Success Criteria** (what must be TRUE):
  1. `#if os(Android) import Android` guards added to xctest-dynamic-overlay IsTesting.swift and SwiftTesting.swift — `skip android test` no longer blocked by dlopen/dlsym errors
  2. All test targets (TCATests, NavigationTests, FoundationTests, SharingTests, DatabaseTests, FuseAppIntegrationTests) have `skipstone` plugin in Package.swift
  3. XCSkipTests uses canonical `XCGradleHarness`/`runGradleTests()` pattern instead of fake JUnit XML stubs
  4. `skip test` and `skip android test` execute real Kotlin tests (non-zero test count in JUnit results)
  5. Skipstone local package symlink resolution works with fork path overrides
**Plans:** 3/3 plans complete

Plans:
- [x] 11-01-PLAN.md — Add skipstone plugin + SkipTest to 6 missing test targets, create XCSkipTests.swift, gate non-transpilable code ✓ 2019-02-24
- [x] 11-02-PLAN.md — Replace JUnit stubs with canonical XCGradleHarness, diagnose/fix skipstone symlink resolution ✓ 2019-02-24
- [x] 11-03-PLAN.md — Android verification: TEST-10 observation bridge, TEST-11 stress stability, full suite validation ✓ 2019-02-24

### Phase 12: Swift Perception Android Port
**Goal:** Provide `WithPerceptionTracking`, `_PerceptionLocals`, and `Perceptible` protocol on Android so TCA binding/scoping infrastructure works correctly
**Depends on:** Phase 11
**Requirements:** OBS-29, OBS-30
**Gap Closure:** Closes SWIFT-PERCEPTION-EXCLUDED from v1.0-MILESTONE-AUDIT.md
**Canonical pattern references:** `/pfw-perception` (Perception API patterns), `/pfw-composable-architecture` (binding/scoping that depends on Perceptible)
**Success Criteria** (what must be TRUE):
  1. `WithPerceptionTracking` compiles and executes on Android (not gated by `#if canImport(SwiftUI) && !os(Android)`)
  2. `Perceptible` protocol conformances in TCA (Store, etc.) resolve on Android
  3. `_PerceptionLocals` thread-local storage functions correctly on Android
  4. TCA binding helpers (`$store.property`, `@Bindable`) that depend on perception infrastructure work on Android
**Plans:** 2/2 plans complete

Plans:
- [x] 12-01-PLAN.md — swift-perception fork: PerceptionRegistrar verification + WithPerceptionTracking Android passthrough (OBS-29, OBS-30)
- [x] 12-02-PLAN.md — TCA fork: ObservableState Perceptible inheritance on Android + full test verification (OBS-29, OBS-30)

### Phase 13: API Parity Gaps
**Goal:** Implement Android equivalents for all non-deprecated, current TCA APIs that are currently gated out with `#if !os(Android)` and no alternative
**Depends on:** Phase 12
**Requirements:** Derived from PARITY-GAPS-IN-CURRENT-APIS audit gap (affects NAV-05, NAV-07, NAV-08, TCA-25 and others)
**Gap Closure:** Closes PARITY-GAPS-IN-CURRENT-APIS from v1.0-MILESTONE-AUDIT.md
**Canonical pattern references:** `/pfw-composable-architecture` (SwitchStore, CaseLet, ViewActionSending), `/pfw-swift-navigation` (fullScreenCover, popover, NavigationStack path binding)
**Success Criteria** (what must be TRUE):
  1. `switch store.case {}` modern enum switching dispatches to correct reducer case on Android (SwitchStore/CaseLet are deprecated, out of scope)
  2. `ViewActionSending.send(_:animation:)` compiles on Android (animation parameter is no-op)
  3. `fullScreenCover` and `popover` presentation data-layer lifecycle (present/interact/dismiss) works on Android via `$store.scope` binding
  4. `TextState`/`ButtonState` data structures preserve content on Android (rich text formatting drops to plain text -- documented limitation)
  5. Sheet presentation lifecycle verified at data layer via TestStore
**Plans:** 2/2 plans complete

Plans:
- [x] 13-01-PLAN.md -- ViewActionSending animation no-op + store.case enum switching verification (TCA-25, TCA-31) ✓ 2019-02-24
- [x] 13-02-PLAN.md -- Presentation parity tests (sheet/fullScreenCover/popover) + TextState/ButtonState verification (NAV-05, NAV-07, NAV-08) ✓ 2019-02-24

### Phase 14: Android Verification & Requirements Reset
**Goal:** Run the full test suite on Android, re-verify all 169 pending requirements against actual Android test results, and update traceability to reflect evidence-backed status
**Depends on:** Phase 13
**Requirements:** All 169 requirements currently in Pending status (re-verification phase)
**Gap Closure:** Closes REQUIREMENTS-INTEGRITY from v1.0-MILESTONE-AUDIT.md
**Success Criteria** (what must be TRUE):
  1. `skip android test` runs successfully for both fuse-library and fuse-app with non-zero Kotlin test counts
  2. Android emulator validation completed for observation bridge, TCA Store, navigation, and database features
  3. All requirements with passing Android test evidence re-marked `[x]` with `Complete` status in traceability table
  4. Requirements that cannot pass on Android documented with rationale and tracked as known limitations
  5. Re-audit via `/gsd:audit-milestone` passes with no critical gaps
**Plans:** 4/4 plans complete

Plans:
- [x] 14-01-PLAN.md -- Run Android + Darwin test suites, capture output, create requirement evidence map ✓ 2019-02-24
- [x] 14-02-PLAN.md -- Update REQUIREMENTS.md traceability with evidence-backed statuses and known limitations ✓ 2019-02-24
- [x] 14-03-PLAN.md -- Final verification, STATE.md/ROADMAP.md closure ✓ 2019-02-24
- [x] 14-04-PLAN.md -- Gap closure: Android-transpilable Combine publisher tests (SHR-09/SHR-10) + TextState formatting rationale ✓ 2019-02-24

### Phase 15: NavigationStack Android Robustness
**Goal:** Fix all P2 NavigationStack tech debt — binding-driven push, JVM type erasure for multi-destination, and dismiss JNI timing — with full test coverage replacing existing `withKnownIssue` wrappers
**Depends on:** Phase 14
**Requirements:** NAV-02, TCA-32 (strengthening from reducer-driven-only to full binding-driven push)
**Gap Closure:** Closes integration gap Phase 10 → Phase 5; closes 3 P2 tech debt items from v1.0-MILESTONE-AUDIT.md
**Canonical pattern references:** `/pfw-composable-architecture` (NavigationStack path binding, PresentationAction.dismiss), `/pfw-swift-navigation` (path-driven navigation, dismiss dependency)
**Success Criteria** (what must be TRUE):
  1. `NavigationLink(state:)` user-driven push dispatches `store.send(.push(...))` on Android — binding-driven push works, not just reducer-driven
  2. Multi-destination `NavigationStack` with multiple `navigationDestination(for:)` types resolves correctly on JVM without type erasure collisions
  3. `@Dependency(\.dismiss)` completes under full JNI effect pipeline timing on Android — `withKnownIssue` wrappers replaced with passing tests
  4. All three fixes validated by dedicated Android tests (not indirect evidence)
**Plans:** 3/3 plans complete

Plans:
- [ ] 15-01-PLAN.md — Fix binding-driven push in _TCANavigationStack adapter (NAV-02, TCA-32)
- [ ] 15-02-PLAN.md — Type-discriminating destination key for JVM type erasure safety (TCA-32)
- [ ] 15-03-PLAN.md — Fix dismiss JNI timing in PresentationReducer/StackReducer pipeline (NAV-02)

### Phase 16: TCA API Parity Completion
**Goal:** Enable all P3 gated TCA extensions on Android and resolve TextState CGFloat ambiguity — with test coverage for each enablement
**Depends on:** Phase 15
**Requirements:** Derived from PARITY-GAPS-IN-CURRENT-APIS tech debt (affects TCA-19, TCA-20, NAV-05, NAV-07)
**Gap Closure:** Closes 4 P3/cosmetic tech debt items from v1.0-MILESTONE-AUDIT.md
**Canonical pattern references:** `/pfw-composable-architecture` (Binding+Observation, IfLetStore deprecation), `/pfw-swift-navigation` (Alert/ConfirmationDialog observation)
**Success Criteria** (what must be TRUE):
  1. TCA `Binding+Observation` extensions (e.g. `$store.scope`, observation-backed bindings) compile and execute on Android without `#if !os(Android)` guard
  2. TCA `Alert`/`ConfirmationDialog` observation extensions work on Android via conditional SkipFuseUI import
  3. `IfLetStore` status resolved — either enabled on Android or documented as intentionally excluded (deprecated) with test proving `@Observable` alternative works
  4. `TextState` formatting modifiers resolve on Android without CGFloat ambiguity — or fallback path tested
  5. Each enablement validated by a dedicated test
**Plans:** 2/2 plans complete

Plans:
- [ ] 16-01-PLAN.md — Implement withTransaction in skip-fuse-ui + remove all Android guards from swift-navigation fork (ButtonState, TextState, Alert, ConfirmationDialog)
- [ ] 16-02-PLAN.md — Comprehensive TCA guard removal, BindingLocal cleanup, and enablement tests

### Phase 17: Test Evidence & Infrastructure Hardening
**Goal:** Provide direct test evidence for TEST-10/TEST-11, fix Robolectric pipeline, eliminate ObjC warnings, and add swiftThreadingFatal version guard — closing all remaining infra/cosmetic tech debt
**Depends on:** Phase 16
**Requirements:** TEST-10, TEST-11 (upgrading from indirect to direct evidence)
**Gap Closure:** Closes 4 infra/cosmetic tech debt items from v1.0-MILESTONE-AUDIT.md
**Canonical pattern references:** `/pfw-testing` (Swift Testing conventions), `/pfw-issue-reporting` (isTesting detection, platform guards)
**Success Criteria** (what must be TRUE):
  1. TEST-10 (observation bridge prevents infinite recomposition) verified by direct Android test — not gated behind `#if !SKIP`
  2. TEST-11 (stress stability >1000 mutations/sec) verified by direct Android test — not gated behind `#if !SKIP`
  3. `skip test` (Robolectric) pipeline runs successfully with skipstone symlink resolution for local fork paths
  4. ObjC duplicate class warnings eliminated from fuse-app macOS test output
  5. `swiftThreadingFatal` stub has version-gated test that asserts presence on Swift <6.3 and absence on Swift ≥6.3
**Plans:** 0/0 plans

### Phase 18: Complete View Identity Layer Implementation

**Goal:** Complete the view identity layer by adding Compose key() wrapping to ForEach's non-lazy Evaluate path and documenting the @Stable/skippability investigation
**Depends on:** Phase 15 (SwiftPeerHandle transpiler infrastructure)
**Requirements:** VIEWID-01, VIEWID-02
**Success Criteria** (what must be TRUE):
  1. ForEach items in non-lazy contexts (VStack, HStack) get Compose key() wrapping based on their identifier
  2. ForEach items in lazy contexts (List, LazyVStack) continue to work unchanged via LazyListScope.items(key:)
  3. ForEach .tag modifiers for Picker/TabView selection matching remain unchanged
  4. @Stable/skippability analysis is documented with a clear recommendation and rationale
**Plans:** 1/1 plans complete

Plans:
- [x] 18-01-PLAN.md -- ForEach key() wrapping in non-lazy Evaluate path + @Stable investigation documentation (VIEWID-01, VIEWID-02) ✓ 2019-02-28

### Phase 18.1: Implement canonical view identity system (INSERTED)

**Goal:** Implement the canonical view identity system — decouple structural identity (IdentityKeyModifier) from selection tagging (TagModifier), replace fragile composeKeyValue() with structural normalizeKey(), apply uniform container loop keying with duplicate-key protection, normalize AnimatedContent contentKey, fix transpiler stateVariables.isEmpty guard for mixed-view peer remembering, migrate lazy container keys to normalizeKey(), and provide comprehensive Identity tab acceptance surface
**Depends on:** Phase 18
**Requirements:** VIEWID-03, VIEWID-04, VIEWID-05, VIEWID-06, VIEWID-07, VIEWID-08, VIEWID-09, VIEWID-10, VIEWID-11
**Success Criteria** (what must be TRUE):
  1. normalizeKey() replaces composeKeyValue() for all identity normalization — handles Optional unwrapping structurally, Identifiable/RawRepresentable recursion, String/Int/Long passthrough
  2. IdentityKeyModifier carries structural identity through ModifiedContent chains, discovered via forEachModifier traversal
  3. ForEach produces dual wrapping (IdentityKeyModifier + TagModifier(.tag)) for non-lazy paths; lazy paths unchanged
  4. All eager container loops (VStack, HStack, ZStack) use key(identityKey ?? i) with seenKeys duplicate-key guard
  5. TagModifier .tag role is pure data annotation (no key() in Render); .id role uses normalizeKey()
  6. Picker/TabView read selectionTag for selection matching
  7. AnimatedContent contentKey normalized through normalizeKey()
  8. Transpiler stateVariables.isEmpty guard removed — mixed @State + let-with-default views get peer remembering
  9. Lazy containers (LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, List, Table) use composeBundleNormalizedKey() adapter wrapping normalizeKey()
  10. Identity tab in fuse-app provides 8-section acceptance surface covering all identity system facets
**Plans:** 14/14 plans complete

Plans:
- [x] 18.1-01-PLAN.md — Wave 1a (RED): TCA reducer scaffolding + /pfw alignment for Identity tab (VIEWID-03..VIEWID-11) ✓
- [x] 18.1-02-PLAN.md — Wave 1b (RED): Identity tab sections 1-4 UI + TCA TestStore tests (VIEWID-03, VIEWID-04, VIEWID-06) ✓
- [x] 18.1-03-PLAN.md — Wave 1c (RED): Identity tab sections 5-8 UI + tests — RED phase complete (VIEWID-05, VIEWID-07..VIEWID-11) ✓
- [x] 18.1-04-PLAN.md — Wave 2a (GREEN): Core identity architecture — normalizeKey, IdentityKeyModifier, ForEach refactor, container loops, TagModifier simplification, Picker/TabView migration (VIEWID-03..VIEWID-08) ✓
- [x] 18.1-05-PLAN.md — Wave 2b (GREEN, parallel with 2a): Transpiler stateVariables.isEmpty guard fix + mixed-view codegen test (VIEWID-10) ✓
- [x] 18.1-06-PLAN.md — Wave 3 (GREEN): AnimatedContent contentKey normalization + animated loop key() wrapping + explicitResetKey checkpoint (VIEWID-05, VIEWID-09) ✓
- [x] 18.1-07-PLAN.md — Wave 4 (GREEN): Lazy container composeBundleString migration to composeBundleNormalizedKey() adapter (VIEWID-11) ✓
- [x] 18.1-08-PLAN.md — Wave 5 (GAP CLOSURE): Fix AnimatedContent idMap to read identityKey as fallback — activates animated path for ForEach content (VIEWID-05, VIEWID-09) ✓ 2026-03-02
- [x] 18.1-09-PLAN.md — Wave 5 (GAP CLOSURE): UAT expectation updates for lazy disposal + tab switch platform differences; VIEWID-03..VIEWID-11 requirements traceability (VIEWID-03..VIEWID-11) ✓ 2026-03-02
- [x] 18.1-10-PLAN.md — Wave 6 (GAP CLOSURE): PeerStore integration — parent-scoped peer cache for survival across LazyColumn scroll-off and TabView tab switch (VIEWID-12, VIEWID-13) ✓ 2026-03-02
- [ ] 18.1-11-PLAN.md — Wave 7 (GAP CLOSURE): RetainedAnimatedItems — replace AnimatedContent dual-path with unified per-item AnimatedVisibility
