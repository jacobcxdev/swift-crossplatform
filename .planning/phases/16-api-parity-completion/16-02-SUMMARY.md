---
phase: 16-api-parity-completion
plan: 02
subsystem: ui
tags: [TCA, guard-removal, BindingLocal, animation, IfLetStore, ButtonState, TextState]

# Dependency graph
requires:
  - phase: 16-api-parity-completion
    plan: 01
    provides: "withTransaction delegates to withAnimation on Android; ButtonState.animatedSend enabled"
provides:
  - "All removable Android guards removed from TCA fork (16 files)"
  - "BindingLocal deduplicated to single definition per platform"
  - "Animation chain (Store.send -> Transaction -> withTransaction) fully functional on Android"
  - "Enablement tests for guard removals"
affects: [16-03-final-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "BindingLocal defined in Core.swift for non-SwiftUI platforms, ViewStore.swift for SwiftUI platforms (mutually exclusive via canImport)"
    - "Popover falls back to sheet on Android (architectural, not guard-related)"

key-files:
  created: []
  modified:
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Core.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/ViewStore.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Effect.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Effects/Animation.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Dependencies/Dismiss.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/IfLetStore.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/NavigationStackStore.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/Binding.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/Alert.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/ConfirmationDialog.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/Alert+Observation.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ViewAction.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/NavigationStack+Observation.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/TestStore.swift
    - forks/swift-composable-architecture/Sources/ComposableArchitecture/Internal/Deprecations.swift
    - examples/fuse-library/Tests/TCATests/BindingTests.swift
    - examples/fuse-library/Tests/TCATests/StoreReducerTests.swift
    - examples/fuse-library/Tests/NavigationTests/TextStateButtonStateTests.swift

key-decisions:
  - "Popover.swift Android guard kept as-is -- not a missing API guard but an architectural Android fallback to sheet (Material3)"
  - "BindingLocal defined once per platform context: Core.swift (#if !canImport(SwiftUI)) and ViewStore.swift (inside #if canImport(SwiftUI)) -- mutually exclusive"
  - "Store.swift, Effect.swift, Dismiss.swift animation guards changed from canImport(SwiftUI) && !os(Android) to canImport(SwiftUI)"
  - "ViewAction.swift Android fallback removed entirely -- withTransaction now works on Android, so animation/transaction delegates through properly"
  - "Deprecated file guards (SwitchStore, NavigationLinkStore, LegacyAlert, ActionSheet) left as-is -- entire files gated, not individual blocks"

patterns-established:
  - "Guard removal pattern: #if canImport(SwiftUI) && !os(Android) -> #if canImport(SwiftUI) for animation APIs"
  - "Guard removal pattern: #if !os(Android) -> removed entirely for non-animation blocks that compile on both platforms"

requirements-completed: [TCA-19, TCA-20, NAV-05, NAV-07]

# Metrics
duration: 9min
completed: 2026-02-24
---

# Phase 16 Plan 02: TCA Guard Removal and Enablement Tests Summary

**All removable Android guards removed from TCA fork (16 files, 52 lines deleted); BindingLocal deduplicated; animation chain fully enabled; 6 enablement tests passing**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-24T15:18:33Z
- **Completed:** 2026-02-24T15:27:07Z
- **Tasks:** 2
- **Files modified:** 19

## Accomplishments
- Removed all `#if !os(Android)` and `#if canImport(SwiftUI) && !os(Android)` guards from 16 TCA source files
- Deduplicated BindingLocal (Core.swift for non-SwiftUI, ViewStore.swift for SwiftUI -- mutually exclusive)
- Animation chain (Store.send -> Transaction -> withTransaction -> withAnimation) fully functional on Android
- IfLetStore, NavigationStackStore, Binding, Alert, ConfirmationDialog all unguarded
- ViewAction animation/transaction delegates now route through proper animation path on both platforms
- 6 new enablement tests all passing (273 total, 9 pre-existing known issues)

## Task Commits

Each task was committed atomically:

1. **Task 1: Comprehensive TCA guard removal and BindingLocal cleanup** - `bdb8a4d` (feat)
2. **Task 2: Enablement tests for all guard removals** - `cfb71ac` (test)

## Files Created/Modified
- `Core.swift` - BindingLocal guard changed from `!canImport(SwiftUI) || os(Android)` to `!canImport(SwiftUI)`
- `ViewStore.swift` - BindingLocal guard removed; 2 send-with-animation guards removed
- `Store.swift` - send(_:animation:) and send(_:transaction:) changed to `#if canImport(SwiftUI)`
- `Effect.swift` - Effect.send(_:animation:) and Send.callAsFunction animation overloads changed to `#if canImport(SwiftUI)`
- `Animation.swift` - File guard changed to `#if canImport(SwiftUI)`
- `Dismiss.swift` - Animation dismiss overloads changed to `#if canImport(SwiftUI)`
- `IfLetStore.swift` - 3 `#if !os(Android)` guards removed
- `NavigationStackStore.swift` - 1 `#if !os(Android)` guard removed (SwitchStore destination init)
- `Binding.swift` - 2 `#if !os(Android)` guards removed (ViewStore extension, BindingViewState)
- `Alert.swift` - animatedSend guard removed
- `ConfirmationDialog.swift` - animatedSend guard removed
- `Alert+Observation.swift` - 2 animatedSend guards removed
- `ViewAction.swift` - Android fallback replaced with direct animation/transaction delegation
- `NavigationStack+Observation.swift` - NavigationStack extension unguarded (line 150)
- `TestStore.swift` - BindingViewStore extension changed to `#if canImport(SwiftUI)`
- `Deprecations.swift` - 2 SwiftUI guards changed to `#if canImport(SwiftUI)`
- `BindingTests.swift` - Added testIfLetStoreAlternativePattern (@Presents + .ifLet pattern)
- `StoreReducerTests.swift` - Added testSendWithAnimation and testEffectAnimation
- `TextStateButtonStateTests.swift` - Added testTextStateModifiersCompileAndExecute, testButtonStateAnimatedAction, testButtonStateAnimatedNilAction

## Decisions Made
- Popover.swift Android guard kept -- it's an architectural Android fallback (popover -> sheet) not a missing API guard
- BindingLocal deduplication uses mutually exclusive `canImport(SwiftUI)` guards rather than a single definition
- Deprecated file-level guards (SwitchStore.swift, NavigationLinkStore.swift, LegacyAlert.swift, ActionSheet.swift) left as-is -- entire deprecated files, not individual blocks
- TextState modifier test gated with `#if !os(Android)` because modifiers require SwiftUI (CGFloat ambiguity on Android per Phase 14 decision)
- ViewAction.swift Android no-op fallback removed entirely since withTransaction now works

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Extended guard removal to Store.swift, Effect.swift, Dismiss.swift, TestStore.swift, Deprecations.swift**
- **Found during:** Task 1 (comprehensive audit)
- **Issue:** Plan listed specific files but grep revealed additional `canImport(SwiftUI) && !os(Android)` guards in Store.swift (send with animation/transaction), Effect.swift (Effect.send with animation, Send.callAsFunction), Dismiss.swift (animated dismiss), TestStore.swift (BindingViewStore), and Deprecations.swift
- **Fix:** Changed all to `#if canImport(SwiftUI)` consistently
- **Files modified:** Store.swift, Effect.swift, Dismiss.swift, TestStore.swift, Deprecations.swift
- **Verification:** Both example projects build cleanly
- **Committed in:** bdb8a4d (Task 1 commit)

**2. [Rule 1 - Bug] Fixed ButtonState generic inference in test**
- **Found during:** Task 2 (enablement tests)
- **Issue:** `ButtonState(action: .send(.confirm, animation: .default))` couldn't infer generic parameter
- **Fix:** Added explicit generic: `ButtonState<TestAlertAction>(...)`
- **Files modified:** TextStateButtonStateTests.swift
- **Verification:** Test compiles and passes

**3. [Rule 1 - Bug] Fixed Effect.animation type inference in test**
- **Found during:** Task 2 (enablement tests)
- **Issue:** Inline Reduce closure with `.send(.doubled).animation(.default)` couldn't infer types
- **Fix:** Added explicit type annotations to Store, Reduce, and Effect
- **Files modified:** StoreReducerTests.swift
- **Verification:** Test compiles and passes

---

**Total deviations:** 3 auto-fixed (1 missing critical scope, 2 test compilation bugs)
**Impact on plan:** Deviation 1 expanded scope appropriately for comprehensive audit. Deviations 2-3 were test compilation fixes. No scope creep.

## Issues Encountered
None beyond the compilation fixes documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- TCA fork fully unguarded (except documented preserved guards)
- All animation APIs enabled on Android via withTransaction chain
- Ready for Plan 03 (final verification) if it exists, or phase completion

---
*Phase: 16-api-parity-completion*
*Completed: 2026-02-24*
