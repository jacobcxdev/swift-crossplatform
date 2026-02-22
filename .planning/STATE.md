# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.
**Current focus:** Phase 3: TCA Core (complete)

## Current Position

Phase: 3 of 7 (TCA Core) -- COMPLETE
Plan: 2 of 2 in current phase (all complete)
Status: Phase 3 complete. Both plans executed: Store/Reducer/Effect (20 tests) + Dependencies (19 tests)
Last activity: 2026-02-22 -- Plan 03-02 executed: 19 tests, 2 tasks, 0 failures

Progress: [██████░░░░] 60%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: ~10min
- Total execution time: 0.9 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 3 - TCA Core | 2 | 14min | 7min |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

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

### Pending Todos

- **Perception bypass on Android (Phase 3+):** `PerceptionRegistrar` delegates to native `ObservationRegistrar`, bypassing bridge `recordAccess` hooks. Raw `@Perceptible` views (without TCA) won't trigger Compose updates. Safe for TCA (uses bridge registrar directly). Verify no non-TCA code relies on Perception for view driving. (Source: Gemini verifier)
- **Android runtime verification (Phase 7):** 5 human tests deferred — single recomposition, nested independence, ViewModifier observation, fatal error on bridge failure, full 14-fork compilation. All require running emulator. (Source: all 3 verifiers)
- **Android runtime test execution (Phase 7):** Phase 3 plans use macOS proxy testing + Android build verification. Full Android runtime test execution (`skip test`) deferred due to Kotlin compilation issues in Skip toolchain. Must be validated when toolchain stabilizes. (Source: Codex verifier, Phase 3 plan check)
- **MainSerialExecutor Android fallback validation (Phase 7):** Context suggested porting MainSerialExecutor; research determined existing `effectDidSubscribe` AsyncStream fallback is the intended Android path. Validate fallback under all effect types during Phase 7 TestStore testing. (Source: Codex verifier, Phase 3 plan check)
- **DEP-05 previewValue on Android (clarification):** DEP-05 requirement says "previewValue is used in preview context on Android" but previews don't exist on Android. Phase 3 test validates preview context is never active. If Android ever gains preview support, revisit. (Source: Codex verifier, Phase 3 plan check)

### Blockers/Concerns

- Navigation on Android: `NavigationStack.init(path:root:destination:)` is fully guarded out on Android -- need to determine skip-ui Compose equivalent (affects Phase 5)
- `jniContext` thread attachment: verify `AttachCurrentThread()` handling for non-main threads (affects TCA effects in Phase 3)
- `swiftThreadingFatal` stub required until Swift 6.3 ships upstream fix (PR #77890)

## Session Continuity

Last session: 2026-02-22
Stopped at: Completed 03-02-PLAN.md (Dependencies validation) -- Phase 3 complete
Resume file: /gsd:execute-phase 04 (Phase 4: Observable State next)
