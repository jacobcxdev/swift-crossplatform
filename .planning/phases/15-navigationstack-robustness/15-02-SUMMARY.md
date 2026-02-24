---
phase: 15-navigationstack-robustness
plan: 02
subsystem: navigation
tags: [tca, navigationstack, android, jvm-type-erasure, skip-fuse-ui, stackstate, destination-key]

# Dependency graph
requires:
  - phase: 15-navigationstack-robustness
    plan: 01
    provides: "Fixed binding-driven push dispatch in _TCANavigationStack set closure"
  - phase: 10-skip-fuse-ui-integration
    provides: "_TCANavigationStack adapter with Binding<NavigationPath> bridge"
provides:
  - "NavigationDestinationKeyProviding protocol in skip-fuse-ui for JVM type erasure safety"
  - "Type-discriminating destinationKey on StackState.Component using _typeName"
  - "skip-fuse-ui destinationKeyTransformer and registration prefer protocol key over String(describing:)"
  - "3 new multi-destination type discrimination tests"
affects: [15-navigationstack-robustness]

# Tech tracking
tech-stack:
  added: []
  patterns: ["NavigationDestinationKeyProviding protocol for JVM-safe destination keys", "_typeName for fully qualified Swift type names in destination keys"]

key-files:
  created: []
  modified:
    - "forks/skip-fuse-ui/Sources/SkipSwiftUI/Containers/Navigation.swift"
    - "forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/NavigationStack+Observation.swift"
    - "examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift"

key-decisions:
  - "_typeName over String(describing:) for fully qualified type names -- String(describing:) on nested types produces short names (e.g. 'State') causing collisions between FeatureA.State and FeatureB.State"
  - "NavigationDestinationKeyProviding protocol in skip-fuse-ui with os(Android) conformance in TCA -- deployment target mismatch prevents canImport(SkipSwiftUI) on Darwin"
  - "Protocol-based approach over CustomStringConvertible -- separates navigation key concern from general description, both registration and lookup sides check explicitly"

patterns-established:
  - "NavigationDestinationKeyProviding: protocol for types needing JVM-safe navigation destination keys"
  - "destinationKey format: 'StackState.Component<ModuleName.TypeName>' using _typeName for full qualification"

requirements-completed: [TCA-32]

# Metrics
duration: 12min
completed: 2026-02-24
---

# Phase 15 Plan 02: JVM Type Erasure Fix Summary

**Type-discriminating destination key for multi-destination NavigationStack using _typeName and NavigationDestinationKeyProviding protocol, preventing JVM generic type erasure collisions**

## Performance

- **Duration:** 12 min
- **Started:** 2026-02-24T12:54:50Z
- **Completed:** 2026-02-24T13:07:00Z
- **Tasks:** 1
- **Files modified:** 3 (across 2 forks + test file)

## Accomplishments
- Added `NavigationDestinationKeyProviding` protocol to skip-fuse-ui with `static var destinationKey` and `var destinationKey` requirements
- Updated skip-fuse-ui's `destinationKeyTransformer` (lookup side) and `navigationDestination(for:)` (registration side) to prefer protocol key over `String(describing:)` which erases generics on JVM
- Added `destinationKey` static and instance properties to `StackState.Component` using `_typeName(Element.self)` for fully qualified names
- Added `NavigationDestinationKeyProviding` conformance for `StackState.Component` gated on `#if os(Android)`
- Added 3 new tests: multi-destination type discrimination, single-destination regression guard, destination key format validation
- All 267 Darwin tests pass with no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Add type-discriminating destination key for StackState.Component** - `f18bfd5` (feat)
   - skip-fuse-ui submodule: `6b5426d`
   - swift-composable-architecture submodule: `e954633`

## Files Created/Modified
- `forks/skip-fuse-ui/Sources/SkipSwiftUI/Containers/Navigation.swift` - Added NavigationDestinationKeyProviding protocol, updated destinationKeyTransformer and navigationDestination(for:) to prefer protocol key
- `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/NavigationStack+Observation.swift` - Added destinationKey properties to Component, static destinationKey to _NavigationDestinationViewModifier, os(Android) conformance to NavigationDestinationKeyProviding
- `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift` - Added 3 multi-destination tests + FeatureA/FeatureB test reducers

## Decisions Made
- **`_typeName` over `String(describing:)`**: `String(describing:)` on nested types (e.g. `FeatureA.State`) produces just the short name `"State"`, causing collisions. `_typeName` produces fully qualified names like `"ModuleName.FeatureA.State"` ensuring uniqueness.
- **Protocol-based approach**: `NavigationDestinationKeyProviding` protocol allows both registration (static) and lookup (instance) sides to use the same key. Cleaner than `CustomStringConvertible` which would affect general type description.
- **`#if os(Android)` conformance guard**: SkipSwiftUI has macOS 13+ deployment target while TCA targets macOS 10.15. `canImport(SkipSwiftUI)` is true on Darwin but causes a deployment target mismatch. `#if os(Android)` ensures the conformance only activates where needed.
- **Forward-facing implementation**: `StackState.Component` currently only exists inside `#if canImport(SwiftUI)` which is false on Android. The protocol conformance prepares for when the compilation guard is eventually unified. The `destinationKey` properties are testable on Darwin via `@_spi(Internals)`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] String(describing:) produces non-unique keys for nested types**
- **Found during:** Task 1 (test execution)
- **Issue:** `String(describing: FeatureA.State.self)` and `String(describing: FeatureB.State.self)` both produce `"State"`, making destination keys identical even on Darwin
- **Fix:** Switched to `_typeName(Element.self)` which produces fully qualified names
- **Files modified:** NavigationStack+Observation.swift
- **Verification:** All 3 new tests pass with distinct keys
- **Committed in:** f18bfd5

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix -- `String(describing:)` would have produced colliding keys even without JVM type erasure. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviation above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- JVM type erasure fix complete and tested
- NavigationDestinationKeyProviding protocol ready for Android runtime use
- Phase 15 plan 03 (dismiss timing) already completed
- Phase 15 fully complete after this plan

## Self-Check: PASSED

All files verified present. Commit f18bfd5 confirmed in git log.

---
*Phase: 15-navigationstack-robustness*
*Completed: 2026-02-24*
