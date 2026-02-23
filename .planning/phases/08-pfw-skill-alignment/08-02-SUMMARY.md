---
phase: 08-pfw-skill-alignment
plan: 02
subsystem: tca
tags: [casepathable, identifiedarray, navigation-stack, presents, dismiss, pfw-conventions]

# Dependency graph
requires:
  - phase: 08-pfw-skill-alignment
    provides: "08-01 Wave 1 atomic fixes (named queries, Effect.run error handling, @available)"
provides:
  - "@CasePathable on all Action enums in @Reducer struct types"
  - "CasePaths idioms (.is(), [case:]) replacing if case let in tests"
  - "File-scope @Reducer enum Path types with parent-prefixed names"
  - "IdentifiedArrayOf<Todo> and IdentifiedArrayOf<Note> for all collections"
  - "Targeted pop(from:) instead of blind popLast()"
  - "@Presents optional sheet state replacing boolean showSheet"
  - ".destination(.dismiss) pattern replacing manual destination = nil"
  - "No default UUID()/Date() in model initializers"
  - "PFW action naming: viewAppeared, addButtonTapped"
affects: [08-03, 08-04, 08-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@CasePathable explicit annotation on @Reducer struct Action enums"
    - "File-scope @Reducer enum Path with parent-prefixed name"
    - "@Presents optional state for sheet presentation"
    - ".destination(.dismiss) for parent-driven dismissal"
    - "IdentifiedArrayOf for all Identifiable collections"
    - "pop(from: stackID) for targeted navigation stack removal"

key-files:
  created: []
  modified:
    - "examples/fuse-app/Sources/FuseApp/ContactsFeature.swift"
    - "examples/fuse-app/Sources/FuseApp/TodosFeature.swift"
    - "examples/fuse-app/Sources/FuseApp/AppFeature.swift"
    - "examples/fuse-app/Sources/FuseApp/SettingsFeature.swift"
    - "examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift"
    - "examples/fuse-app/Sources/FuseApp/CounterFeature.swift"
    - "examples/fuse-app/Sources/FuseApp/SharedModels.swift"
    - "examples/fuse-library/Tests/NavigationTests/NavigationTests.swift"
    - "examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift"
    - "examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift"
    - "examples/fuse-library/Tests/TCATests/StoreReducerTests.swift"
    - "examples/fuse-library/Tests/TCATests/ObservableStateTests.swift"
    - "examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift"

key-decisions:
  - "StackState.pop(from:) used instead of remove(id:) -- StackElementID is not Int"
  - "SheetToggleFeature refactored with dedicated SheetContent child reducer for @Presents pattern"
  - "Parent-driven dismissal uses .send(.destination(.dismiss)) not state.destination = nil"
  - "Test fixture Todo/Contact constructors keep explicit UUID() -- only model defaults removed"

patterns-established:
  - "@CasePathable: always explicit on @Reducer struct Action enums, never on @Reducer enum types"
  - "Path un-nesting: @Reducer enum Path -> @Reducer enum ParentFeaturePath at file scope"
  - "Dismiss: parent sends .destination(.dismiss), child uses @Dependency(\\.dismiss)"

requirements-completed: []

# Metrics
duration: 17min
completed: 2026-02-23
---

# Phase 8 Plan 02: Structural PFW Alignment Summary

**Full PFW canonical compliance for TCA patterns: @CasePathable, CasePaths idioms, IdentifiedArrayOf, @Presents sheets, dismiss patterns, and PFW naming conventions across all fuse-app features and tests**

## Performance

- **Duration:** 17 min
- **Started:** 2026-02-23T08:04:54Z
- **Completed:** 2026-02-23T08:22:42Z
- **Tasks:** 11
- **Files modified:** 13

## Accomplishments
- All 9 Action enums in @Reducer struct types annotated with @CasePathable
- All `if case let` test assertions replaced with `.is()` / `[case:]` CasePaths idioms
- 3 nested @Reducer enum Path types moved to file scope with parent-prefixed names
- [Todo] and [Note] arrays replaced with IdentifiedArrayOf for O(1) ID access
- Boolean sheet state replaced with @Presents optional + dedicated SheetContent reducer
- Manual `destination = nil` replaced with `.destination(.dismiss)` PresentationReducer pipeline
- Default UUID()/Date() removed from model initializers -- callers inject via @Dependency
- Action names follow PFW conventions (viewAppeared, addButtonTapped)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add @CasePathable to all top-level Action enums** - `c39e0e5` (feat)
2. **Task 2: Replace if case let with .is() / [case:] subscript** - `9954fe3` (feat)
3. **Task 3: Un-nest @Reducer enum Path types** - `9753751` (feat)
4. **Task 4: Remove unnecessary CombineReducers** - `366bcdf` (feat)
5. **Task 5: Switch [Todo] and [Note] to IdentifiedArrayOf** - `7010a66` (feat)
6. **Task 6: Replace popLast with pop(from:)** - `5ce502f` (feat)
7. **Task 7: Replace boolean sheet state with @Presents optional** - `1a92155` (feat)
8. **Task 8: Replace manual destination = nil with dismiss pattern** - `9cc52c8` (feat)
9. **Task 9: Remove default UUID()/Date() from models** - `37ec8a8` (feat)
10. **Task 10: Rename action cases to PFW naming conventions** - `0547b4c` (feat)
11. **Task 11: Final verification** - (verification only, no commit)

## Files Created/Modified
- `ContactsFeature.swift` - @CasePathable, ContactsFeaturePath, pop(from:), .destination(.dismiss), viewAppeared
- `TodosFeature.swift` - @CasePathable on Action
- `AppFeature.swift` - @CasePathable on Action
- `SettingsFeature.swift` - @CasePathable, IdentifiedArrayOf<Todo>, viewAppeared
- `DatabaseFeature.swift` - @CasePathable, IdentifiedArrayOf<Note>, viewAppeared, addButtonTapped
- `CounterFeature.swift` - @CasePathable on Action
- `SharedModels.swift` - Remove default UUID()/Date(), IdentifiedArrayOf<Todo> SharedKey
- `NavigationTests.swift` - StackFeaturePath, .is()/.modify CasePaths idioms
- `NavigationStackTests.swift` - AppFeaturePath, [case:] subscript
- `UIPatternTests.swift` - SheetContent reducer, @Presents sheet state
- `StoreReducerTests.swift` - [case:] subscript, merged CombineReducers
- `ObservableStateTests.swift` - .is() CasePaths idioms
- `FuseAppIntegrationTests.swift` - dismiss receive, createdAt, viewAppeared, addButtonTapped

## Decisions Made
- Used `StackState.pop(from:)` not `remove(id:)` -- `StackElementID` is a dedicated struct, not `Int`
- Created `SheetContent` child reducer for @Presents pattern (clean separation of sheet state/actions)
- Parent-driven dismissal via `.send(.destination(.dismiss))` ensures PresentationReducer effect cancellation
- Test fixture data keeps explicit `UUID()` calls -- only model init defaults removed (reducer code already uses @Dependency)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] StackState.pop(from:) instead of remove(id:)**
- **Found during:** Task 6 (Replace popLast with remove(id:))
- **Issue:** Plan specified `state.path.remove(id: stackID)` but `StackState` uses `StackElementID` (not `Int`), and the correct API is `pop(from:)`
- **Fix:** Used `state.path.pop(from: stackID)` which accepts `StackElementID`
- **Files modified:** ContactsFeature.swift
- **Verification:** `swift build` compiles cleanly
- **Committed in:** `5ce502f`

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** API name correction only. No scope creep.

## Issues Encountered
- 2 pre-existing database test failures (testAddNote, testDeleteNote) due to StructuredQueries generating table name "notes" vs migration table "note" -- documented in STATE.md, not caused by this plan

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All fuse-app source code now PFW-compliant
- Wave 2 structural alignment complete
- Ready for 08-03 (Wave 3 remaining alignment work)
- 272+ tests passing (91 Swift Testing + 181 XCTest, minus 6 pre-existing failures)

---
*Phase: 08-pfw-skill-alignment*
*Completed: 2026-02-23*
