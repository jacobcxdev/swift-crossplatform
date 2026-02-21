# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.
**Current focus:** Phase 2: Foundation Libraries (in progress)

## Current Position

Phase: 2 of 7 (Foundation Libraries)
Plan: 1 of 3 in current phase
Status: Executing -- Plan 02-01 (fork housekeeping) complete, Plans 02-02 and 02-03 pending
Last activity: 2026-02-21 -- Plan 02-01 executed: branch rename, 3 new forks, 17-fork Package.swift wiring

Progress: [███░░░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: ~18min
- Total execution time: 0.6 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

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

### Pending Todos

- **Perception bypass on Android (Phase 3+):** `PerceptionRegistrar` delegates to native `ObservationRegistrar`, bypassing bridge `recordAccess` hooks. Raw `@Perceptible` views (without TCA) won't trigger Compose updates. Safe for TCA (uses bridge registrar directly). Verify no non-TCA code relies on Perception for view driving. (Source: Gemini verifier)
- **Android runtime verification (Phase 7):** 5 human tests deferred — single recomposition, nested independence, ViewModifier observation, fatal error on bridge failure, full 14-fork compilation. All require running emulator. (Source: all 3 verifiers)

### Blockers/Concerns

- Navigation on Android: `NavigationStack.init(path:root:destination:)` is fully guarded out on Android -- need to determine skip-ui Compose equivalent (affects Phase 5)
- `jniContext` thread attachment: verify `AttachCurrentThread()` handling for non-main threads (affects TCA effects in Phase 3)
- `swiftThreadingFatal` stub required until Swift 6.3 ships upstream fix (PR #77890)

## Session Continuity

Last session: 2026-02-21
Stopped at: Phase 2, Plan 02-01 complete, executing remaining plans
Resume file: /gsd:execute-phase 2
