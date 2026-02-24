---
phase: 12-swift-perception-android
plan: 01
subsystem: observation
tags: [swift-perception, WithPerceptionTracking, PerceptionRegistrar, SkipFuseUI, Android]

# Dependency graph
requires:
  - phase: 01-observation-bridge
    provides: BridgeObservationRegistrar and JNI observation bridge
  - phase: 10-navigationstack-path-android
    provides: SkipFuseUI conditional dependency pattern in Package.swift
provides:
  - WithPerceptionTracking Android passthrough View implementation
  - PerceptionRegistrar verified to compile on Android (delegates to ObservationRegistrar)
affects: [12-02, swift-composable-architecture, swift-navigation]

# Tech tracking
tech-stack:
  added: []
  patterns: [SkipFuseUI View passthrough for SwiftUI-dependent types on Android]

key-files:
  created: []
  modified:
    - forks/swift-perception/Sources/PerceptionCore/SwiftUI/WithPerceptionTracking.swift

key-decisions:
  - "PerceptionRegistrar requires no changes -- already compiles on Android via canImport(Observation) path"
  - "WithPerceptionTracking Android impl uses SkipFuseUI View (not SwiftUI -- canImport(SwiftUI) is false on Android)"
  - "Only View conformance on Android (no Scene, ToolbarContent, etc. -- not relevant on Android)"
  - "DEBUG builds set _PerceptionLocals.isInPerceptionTracking for TCA debug path compatibility"

patterns-established:
  - "Android SwiftUI type passthrough: #if os(Android) import SkipFuseUI block after main #if canImport(SwiftUI) block"

requirements-completed: [OBS-29, OBS-30]

# Metrics
duration: 2min
completed: 2026-02-24
---

# Phase 12 Plan 01: Swift Perception Android Port Summary

**WithPerceptionTracking Android passthrough via SkipFuseUI and PerceptionRegistrar verified to compile on Android with ObservationRegistrar delegation**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-24T05:33:43Z
- **Completed:** 2026-02-24T05:35:58Z
- **Tasks:** 2 (1 verification-only, 1 implementation)
- **Files modified:** 1

## Accomplishments
- Verified PerceptionRegistrar already compiles on Android without changes (struct and core methods are outside all platform guards; `canImport(Observation)` path creates native ObservationRegistrar)
- Added WithPerceptionTracking Android passthrough using SkipFuseUI View with two init overloads matching Darwin API surface
- Darwin build passes (no regression), Android build passes (SkipFuseUI import resolves)
- All 227 Darwin tests pass (9 known issues, pre-existing)

## Task Commits

Each task was committed atomically:

1. **Task 1: Enable PerceptionRegistrar on Android** - verification only, no commit (no code changes needed)
2. **Task 2: Add WithPerceptionTracking Android implementation** - `ba524c5` in fork, `e369b86` in parent (feat)

## Files Created/Modified
- `forks/swift-perception/Sources/PerceptionCore/SwiftUI/WithPerceptionTracking.swift` - Added `#if os(Android)` block with SkipFuseUI-based WithPerceptionTracking passthrough View
- `forks/swift-perception/Package.swift` - Already had SkipFuseUI dependency (no change needed)

## Decisions Made
- PerceptionRegistrar requires no changes -- the struct at line 19 is outside all `#if` guards, and the `canImport(Observation)` init path at line 42-46 creates a native `ObservationRegistrar` on Android
- Perception checking (MachO/dyld introspection) stays Darwin-only -- correctly gated with `#if DEBUG && canImport(SwiftUI) && !os(Android)`
- WithPerceptionTracking on Android only conforms to View (not Scene, ToolbarContent, Commands, etc.) since those SwiftUI content types are not relevant on Android
- DEBUG builds set `_PerceptionLocals.isInPerceptionTracking = true` so TCA's perception-checking debug paths know tracking is active

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Stale compiler cache caused initial `swift test` failure ("compiled module was created by a different version of the compiler"). Resolved with `swift package clean` -- pre-existing issue unrelated to changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- WithPerceptionTracking compiles on Android -- TCA code wrapping view bodies in `WithPerceptionTracking { }` will now compile
- PerceptionRegistrar confirmed functional on Android -- ready for Plan 02 (Store Perceptible conformance and ObservationStateRegistrar guard changes)
- Perception.Bindable remains gated out on Android (depends on SwiftUI ObservedObject) -- documented as expected

---
*Phase: 12-swift-perception-android*
*Completed: 2026-02-24*
