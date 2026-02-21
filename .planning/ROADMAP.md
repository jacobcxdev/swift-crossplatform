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
- [ ] **Phase 3: TCA Core** - Store, reducers, effects, and dependency injection work on Android
- [ ] **Phase 4: TCA State & Bindings** - ObservableState macro, bindings, and shared state persistence work on Android
- [ ] **Phase 5: Navigation & Presentation** - TCA navigation patterns and SwiftUI presentation lifecycle work on Android
- [ ] **Phase 6: Database & Queries** - StructuredQueries and GRDB/SQLiteData work on Android with observation-driven view updates
- [ ] **Phase 7: Integration Testing & Documentation** - End-to-end TCA app runs on both platforms; forks documented

## Phase Details

### Phase 1: Observation Bridge
**Goal**: Swift Observation semantics work correctly on Android -- view body evaluation triggers exactly one recomposition per observation cycle, not one per mutation
**Depends on**: Nothing (first phase)
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04, OBS-05, OBS-06, OBS-07, OBS-08, OBS-09, OBS-10, OBS-11, OBS-12, OBS-13, OBS-14, OBS-15, OBS-16, OBS-17, OBS-18, OBS-19, OBS-20, OBS-21, OBS-22, OBS-23, OBS-24, OBS-25, OBS-26, OBS-27, OBS-28, OBS-29, OBS-30, SPM-01, SPM-02, SPM-03, SPM-04, SPM-05, SPM-06
**Success Criteria** (what must be TRUE):
  1. An `@Observable` class property mutation in a view model triggers exactly one Compose recomposition (not hundreds) on Android
  2. Nested parent/child view hierarchies each independently track their own observed properties on Android
  3. `ViewModifier` bodies participate in observation tracking the same as `View` bodies on Android
  4. Bridge initialization failure produces a visible error log instead of silently falling back to broken counter-based observation
  5. All 14 fork packages compile for Android via Skip Fuse mode with correct SPM configuration
**Plans**: TBD

Plans:
- [ ] 01-01: TBD
- [ ] 01-02: TBD

### Phase 2: Foundation Libraries
**Goal**: Point-Free's utility libraries that TCA depends on work correctly on Android
**Depends on**: Phase 1
**Requirements**: CP-01, CP-02, CP-03, CP-04, CP-05, CP-06, CP-07, CP-08, IC-01, IC-02, IC-03, IC-04, IC-05, IC-06, CD-01, CD-02, CD-03, CD-04, CD-05, IR-01, IR-02, IR-03, IR-04
**Success Criteria** (what must be TRUE):
  1. `@CasePathable` enum pattern matching (`.is`, `.modify`, subscript extraction) works on Android
  2. `IdentifiedArrayOf` initializes, indexes by ID in O(1), and supports element removal on Android
  3. `customDump` and `diff` produce correct structured output for Swift values on Android
  4. `reportIssue` and `withErrorReporting` catch and surface runtime errors on Android
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: TCA Core
**Goal**: TCA Store, reducers, effects, and dependency injection work correctly on Android
**Depends on**: Phase 2
**Requirements**: TCA-01, TCA-02, TCA-03, TCA-04, TCA-05, TCA-06, TCA-07, TCA-08, TCA-09, TCA-10, TCA-11, TCA-12, TCA-13, TCA-14, TCA-15, TCA-16, DEP-01, DEP-02, DEP-03, DEP-04, DEP-05, DEP-06, DEP-07, DEP-08, DEP-09, DEP-10, DEP-11, DEP-12
**Success Criteria** (what must be TRUE):
  1. A TCA Store initializes, receives dispatched actions, and updates state on Android
  2. `store.scope(state:action:)` derives child stores that correctly reflect parent state changes on Android
  3. `Effect.run`, `.merge`, `.concatenate`, `.cancellable`, and `.cancel` execute async work and route actions on Android
  4. `@Dependency(\.keyPath)` resolves live values in production context and test values in test context on Android
  5. Child reducer scopes inherit parent dependency overrides on Android
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

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
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

### Phase 5: Navigation & Presentation
**Goal**: TCA navigation patterns (stack, sheet, alert, confirmation dialog) and SwiftUI presentation lifecycle work on Android
**Depends on**: Phase 4
**Requirements**: NAV-01, NAV-02, NAV-03, NAV-04, NAV-05, NAV-06, NAV-07, NAV-08, NAV-09, NAV-10, NAV-11, NAV-12, NAV-13, NAV-14, NAV-15, NAV-16, TCA-26, TCA-27, TCA-28, TCA-32, TCA-33, TCA-34, TCA-35, UI-01, UI-02, UI-03, UI-04, UI-05, UI-06, UI-07, UI-08
**Success Criteria** (what must be TRUE):
  1. `NavigationStack` with TCA path binding pushes and pops destinations on Android
  2. `.sheet`, `.fullScreenCover`, and `.popover` present and dismiss content driven by optional TCA state on Android
  3. `AlertState` and `ConfirmationDialogState` render with correct titles, messages, buttons, and destructive roles on Android
  4. `@Presents` / `PresentationAction.dismiss` lifecycle correctly nils optional child state and closes presentation on Android
  5. `.task` modifier executes async work on view appearance without blocking recomposition on Android
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD

### Phase 6: Database & Queries
**Goal**: StructuredQueries type-safe query building and GRDB database lifecycle work on Android with observation-driven view updates
**Depends on**: Phase 1
**Requirements**: SQL-01, SQL-02, SQL-03, SQL-04, SQL-05, SQL-06, SQL-07, SQL-08, SQL-09, SQL-10, SQL-11, SQL-12, SQL-13, SQL-14, SQL-15, SD-01, SD-02, SD-03, SD-04, SD-05, SD-06, SD-07, SD-08, SD-09, SD-10, SD-11, SD-12
**Success Criteria** (what must be TRUE):
  1. `@Table` macro generates correct metadata and `Table.select/where/join/order/group/limit` queries execute on Android
  2. `DatabaseMigrator` runs migrations and `database.read/write` execute transactions on Android
  3. `@FetchAll` and `@FetchOne` observation macros trigger view updates when underlying database rows change on Android
  4. `@Dependency(\.defaultDatabase)` injects database connection into views and models on Android
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD

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
**Plans**: TBD

Plans:
- [ ] 07-01: TBD
- [ ] 07-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7
Note: Phase 6 (Database) depends only on Phase 1 and can run in parallel with Phases 2-5 if desired.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Observation Bridge | 0/2 | Not started | - |
| 2. Foundation Libraries | 0/1 | Not started | - |
| 3. TCA Core | 0/2 | Not started | - |
| 4. TCA State & Bindings | 0/2 | Not started | - |
| 5. Navigation & Presentation | 0/2 | Not started | - |
| 6. Database & Queries | 0/2 | Not started | - |
| 7. Integration Testing & Documentation | 0/2 | Not started | - |
