# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.
**Current focus:** Phase 8 — PFW skill alignment (context gathered, ready for planning).

## Current Position

Phase: 7 of 7 (Integration Testing & Documentation) -- COMPLETE
Plan: 4 of 4 in current phase (07-01, 07-02, 07-03, 07-04 complete)
Status: All 4 plans complete. 17 forks documented in FORKS.md. 22 test targets reorganised into 6 feature-aligned groups. 247 tests pass. TEST-01..TEST-12 + DOC-01 all covered.
Last activity: 2026-02-23 -- Verifier gaps closed, Phase 7 marked complete.

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 13
- Average duration: ~9min
- Total execution time: ~2.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 3 - TCA Core | 2 | 14min | 7min |
| 4 - TCA State & Bindings | 3 | 15min | 5min |
| 5 - Navigation & Presentation | 3 | 20min | 7min |
| 6 - Database & Queries | 2 | 13min | 6.5min |
| 7 - Integration Testing | 4 | 29min | 7min |

**Recent Trend:**
- Last 5 plans: 06-02, 07-01, 07-02, 07-03, 07-04
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
- [Phase 07]: AtomicCounter (LockIsolated wrapper) for withObservationTracking onChange closures -- Swift 6 Sendable requirement
- [Phase 07]: Android emulator test blocked by pre-existing dlopen/dlsym missing imports in xctest-dynamic-overlay fork -- deferred to fork maintenance
- [Phase 07]: D8-c ViewModifier and D8-d bridge failure documented as manual verification steps (cannot automate)
- [Phase 07]: Phase 7 tests included in test reorganisation (plan table predated Wave 1-2 execution)
- [Phase 07]: #if !SKIP guards for TCA-dependent files in Skip-enabled test target
- [Phase 07]: Type renames (DumpUser, DataItem, EdgeCaseCancelInFlightFeature) to resolve target-merge name collisions

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
- **xctest-dynamic-overlay Android test build (Phase 7):** Fork needs `#if os(Android) import Android #endif` for `dlopen`/`dlsym` in `SwiftTesting.swift:643` and `IsTesting.swift:39`. Blocks `skip android test` for all test targets. Non-test Android build works fine. (Source: 07-02 Task 3)

### Roadmap Evolution

- Phase 8 added: PFW skill alignment

### Blockers/Concerns

- ~~Navigation on Android: `NavigationStack.init(path:root:destination:)` is fully guarded out on Android~~ RESOLVED — Guards minimised in Phase 5 Wave 1. Modern extensions unguarded, only deprecated Perception.Bindable stays guarded.
- `jniContext` thread attachment: verify `AttachCurrentThread()` handling for non-main threads (affects TCA effects in Phase 3)
- `swiftThreadingFatal` stub required until Swift 6.3 ships upstream fix (PR #77890)

## Session Continuity

Last session: 2026-02-23
Stopped at: Phase 8 context gathered — all 191 PFW audit findings in scope, no exceptions.
Resume file: .planning/phases/08-pfw-skill-alignment/08-CONTEXT.md
