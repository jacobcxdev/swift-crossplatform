# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.
**Current focus:** Phase 6: Database & Queries (planned)

## Current Position

Phase: 6 of 7 (Database & Queries) -- IN PROGRESS
Plan: 1 of 2 in current phase (Plan 06-01 complete, Plan 06-02 pending)
Status: Plan 06-01 complete. 4 database forks wired, 15 StructuredQueries tests pass (SQL-01..SQL-15). 95 total tests (80 existing + 15 new). Plan 06-02 next: SQLiteData lifecycle/observation (SD-01..SD-12).
Last activity: 2026-02-22 -- Plan 06-01 executed successfully.

Progress: [████████░░] 80%

## Performance Metrics

**Velocity:**
- Total plans completed: 9
- Average duration: ~10min
- Total execution time: ~1.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 3 - TCA Core | 2 | 14min | 7min |
| 4 - TCA State & Bindings | 3 | 15min | 5min |
| 5 - Navigation & Presentation | 3 | 20min | 7min |
| 6 - Database & Queries | 1 | 8min | 8min |

**Recent Trend:**
- Last 5 plans: 04-03, 05-01, 05-02, 05-03, 06-01
- Trend: stable, fast execution

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Skip sandbox only resolves deps used by targets — unused local path deps must be commented out or removed
- Fuse mode only (no Lite) for TCA apps -- counter-based observation incompatible
- Fix at bridge level (skip-android-bridge/skip-ui), not app level
- Use native `withObservationTracking` (not swift-perception) -- `libswiftObservation.so` ships with Android SDK
- Fork-first, upstream later -- Skip team endorsed this approach
- Bridge init/runtime JNI failures are fatal (fatalError) -- no silent degradation
- Counter path disabled when nativeEnable() active -- zero impact on non-observation Skip users
- PerceptionRegistrar is thin passthrough to native ObservationRegistrar on Android
- Hybrid SPM: SKIP_BRIDGE for Skip forks, simple #if os(Android) for PF forks
- All 17 forks must compile for Android (expanded from 14 in Phase 2)
- swiftThreadingFatal stub version-gated for auto-removal at Swift 6.3
- Android isTesting detection via process args + dlsym + env vars (not Darwin-specific checks)
- dlopen/dlsym uses os(Android) alongside os(Linux) for ELF dynamic linking
- IdentifiedCollections confirmed zero-change on Android (pure Swift data structures)
- DependenciesTestObserver replaced with DependenciesTestSupport (observer product is macOS-excluded)
- ifLet/ifCaseLet tests validate happy path only (TCA reports errors for nil-state child actions by design)
- Effect dependency tests require explicit withDependencies clock override (test context defaults to unimplemented)
- [Phase 03]: dismiss/openSettings not in swift-dependencies -- 16 built-in keys validated (not 19)
- [Phase 03]: @DependencyClient and @CasePathable macros require file-scope types (not private/local)
- [Phase 04]: FileStorageKey.swift enabled on Android with os(Android) guard, DispatchSource.FileSystemEvent polyfill, and no-op file system monitoring
- [Phase 04]: @ObservableState _$id identity testing requires CoW snapshot comparison (not through Store.withState)
- [Phase 04]: @Reducer enum DestinationFeature needs parent wrapper with .ifLet for enum case switching
- [Phase 04]: Shared mutations use $value.withLock { $0 = newValue } (direct setter unavailable)
- [Phase 04]: Binding($shared) requires @MainActor context (defined in SharedBinding.swift)
- [Phase 06]: Use GRDB DatabaseQueue + Statement.fetchAll/execute bridge (not _StructuredQueriesSQLite.Database) -- matches SQLiteData's re-exported API
- [Phase 06]: Import SQLiteData (which re-exports StructuredQueriesSQLite + GRDB via @_exported) not internal modules directly

### Pending Todos

- **Perception bypass on Android (Phase 3+):** `PerceptionRegistrar` delegates to native `ObservationRegistrar`, bypassing bridge `recordAccess` hooks. Raw `@Perceptible` views (without TCA) won't trigger Compose updates. Safe for TCA (uses bridge registrar directly). Verify no non-TCA code relies on Perception for view driving. (Source: Gemini verifier)
- **Android runtime verification (Phase 7):** 5 human tests deferred — single recomposition, nested independence, ViewModifier observation, fatal error on bridge failure, full 14-fork compilation. All require running emulator. (Source: all 3 verifiers)
- **~~Android runtime test execution (Phase 7):~~** RESOLVED — `skip test` now passes 21/21 (Swift + Kotlin) after removing unused fork deps that broke Skip's sandbox. All future phases should run `skip test` as part of validation.
- **MainSerialExecutor Android fallback validation (Phase 7):** Context suggested porting MainSerialExecutor; research determined existing `effectDidSubscribe` AsyncStream fallback is the intended Android path. Validate fallback under all effect types during Phase 7 TestStore testing. (Source: Codex verifier, Phase 3 plan check)
- **DEP-05 previewValue on Android (clarification):** DEP-05 requirement says "previewValue is used in preview context on Android" but previews don't exist on Android. Phase 3 test validates preview context is never active. If Android ever gains preview support, revisit. (Source: Codex verifier, Phase 3 plan check)
- **dismiss/openSettings dependency validation (Phase 7):** dismiss dependency validated at data layer in Phase 5 (DismissEffect + LockIsolated pattern). openSettings deferred to Phase 7 — requires active view hierarchy. (Source: Codex verifier gap #2, Phase 3 reconciliation)
- **Android UI rendering validation (Phase 7):** Phase 5 Codex verifier flagged that NavigationStack, sheet, alert, dialog, .task tests validate data layer only, not Android Compose rendering. All UI rendering assertions deferred to Phase 7 integration testing with emulator. (Source: Codex verifier, Phase 5)
- **Database observation wrapper-level testing (Phase 7):** Phase 6 Codex verifier flagged SD-09/SD-10/SD-11 tests use ValueObservation.start() directly, not @FetchAll/@FetchOne DynamicProperty wrappers. DynamicProperty.update() requires SwiftUI runtime (guarded out on Android). Wrapper-level integration testing deferred to Phase 7 with emulator. (Source: Codex verifier, Phase 6)
- **Database Android build verification (Phase 7):** Phase 6 Codex verifier flagged missing `skip test` / `make android-build` in plan verification. macOS-only testing is consistent with Phases 3-5. Android build validation deferred to Phase 7. (Source: Codex verifier, Phase 6)

### Blockers/Concerns

- ~~Navigation on Android: `NavigationStack.init(path:root:destination:)` is fully guarded out on Android~~ RESOLVED — Guards minimised in Phase 5 Wave 1. Modern extensions unguarded, only deprecated Perception.Bindable stays guarded.
- `jniContext` thread attachment: verify `AttachCurrentThread()` handling for non-main threads (affects TCA effects in Phase 3)
- `swiftThreadingFatal` stub required until Swift 6.3 ships upstream fix (PR #77890)

## Session Continuity

Last session: 2026-02-22
Stopped at: Completed 06-01-PLAN.md (StructuredQueries validation) -- 15 tests, 95 total
Resume file: /gsd:execute-phase 06 (Plan 06-02: SQLiteData lifecycle next)
