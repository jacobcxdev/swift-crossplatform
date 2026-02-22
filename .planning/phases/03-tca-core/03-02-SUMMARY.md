---
phase: 03-tca-core
plan: 02
subsystem: testing
tags: [tca, dependencies, dependency-injection, dependency-client, navigation-id, swift, xctest]

# Dependency graph
requires:
  - phase: 03-tca-core
    plan: 01
    provides: "DependencyTests target wired with DependenciesTestSupport"
provides:
  - "DependencyTests: 19 tests validating all 12 DEP requirements"
  - "@Dependency key path and type-based resolution validated"
  - "@DependencyClient macro runtime behavior validated"
  - "NavigationID EnumMetadata.tag(of:) code path validated"
  - "Built-in dependency keys (16) all resolve without crashes"
affects: [04-observable-state, 07-testing]

# Tech tracking
tech-stack:
  added: ["@_spi(Reflection) CasePaths for EnumMetadata access"]
  patterns: [XCTExpectFailure for @DependencyClient unimplemented validation, withDependencies context override for live/test switching, Effect.merge dependency propagation]

key-files:
  created: []
  modified:
    - examples/fuse-library/Tests/DependencyTests/DependencyTests.swift

key-decisions:
  - "dismiss/openSettings not in swift-dependencies -- only 16 built-in keys available (not 19 as plan estimated)"
  - "NumberClient defined at file scope (not private) -- @DependencyClient macro generates private inits that become inaccessible"
  - "@CasePathable enum defined at file scope -- macros cannot attach to local types in Swift"

patterns-established:
  - "XCTExpectFailure for @DependencyClient: wrap unimplemented calls in XCTExpectFailure to validate reportIssue behavior"
  - "withDependencies context override: set $0.context = .live to test live dependency values in test environment"
  - "@_spi(Reflection) EnumMetadata: use CasePaths SPI to validate enum tag extraction"

requirements-completed: [DEP-01, DEP-02, DEP-03, DEP-04, DEP-05, DEP-06, DEP-07, DEP-08, DEP-09, DEP-10, DEP-11, DEP-12]

# Metrics
duration: 6min
completed: 2026-02-22
---

# Phase 3 Plan 2: Dependency Injection Validation Summary

**19 tests validating TCA's complete dependency injection system -- @Dependency resolution, withDependencies scoping, @DependencyClient macro, built-in keys, NavigationID EnumMetadata, and @TaskLocal propagation on the forked dependency graph**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-22T06:05:23Z
- **Completed:** 2026-02-22T06:11:46Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- 12 core dependency tests covering @Dependency key path resolution (DEP-01), type-based resolution (DEP-02), live context (DEP-03), test context (DEP-04), preview context exclusion (DEP-05), custom key registration (DEP-06), withDependencies sync scoping (DEP-09), Store prepareDependencies (DEP-10), child/grandchild reducer inheritance at 2 and 3 levels (DEP-11), and sibling isolation (DEP-11)
- All 16 available built-in dependency keys validated: uuid, date, continuousClock, suspendingClock, calendar, timeZone, locale, context, assert, fireAndForget, withRandomNumberGenerator, mainQueue, mainRunLoop, notificationCenter, urlSession, openURL
- @DependencyClient macro runtime validation: unimplemented endpoint reports issue via reportIssue (DEP-07), implemented endpoint resolves correct value (DEP-07)
- Reducer .dependency modifier overrides dependency for scoped reducer (DEP-08)
- Dependency resolution inside Effect.run and Effect.merge closures (DEP-12)
- NavigationID EnumMetadata.tag(of:) validated with @CasePathable enum -- consistent tags per case, distinct tags between cases, correct case name extraction
- @TaskLocal propagation through async Task closures confirmed (DEP-09)
- Zero regressions on existing test suites (68 XCTest + 34 Swift Testing tests pass)

## Task Commits

Each task was committed atomically:

1. **Task 1: Write core dependency injection and built-in dependency tests** - `dd20305` (feat)
2. **Task 2: Write @DependencyClient, effects, and NavigationID tests** - `2d077c0` (feat)

## Files Created/Modified

- `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift` - 19 tests covering all 12 DEP requirements (from placeholder to 548 lines)

## Decisions Made

- **Built-in key count adjustment:** Plan mentioned 19 built-in keys including dismiss and openSettings, but these are in swift-navigation, not swift-dependencies. Actual count is 16 keys in swift-dependencies DependencyValues directory. All 16 validated.
- **NumberClient at file scope:** @DependencyClient macro generates initializers with the same access level as the struct. Using `private` made the init inaccessible from test methods. Moved to file scope (internal).
- **@CasePathable at file scope:** Swift macros cannot be attached to local types defined inside functions. TestAction enum moved to file scope.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wrong key path for NotificationCenter**
- **Found during:** Task 1
- **Issue:** Used `\.defaultNotificationCenter` instead of `\.notificationCenter`
- **Fix:** Changed to correct key path `\.notificationCenter`
- **Files modified:** examples/fuse-library/Tests/DependencyTests/DependencyTests.swift
- **Committed in:** dd20305 (Task 1 commit)

**2. [Rule 1 - Bug] Missing @MainActor on Store-interacting tests**
- **Found during:** Task 1
- **Issue:** Store.send and Store.withState are @MainActor-isolated; tests calling them synchronously need @MainActor annotation
- **Fix:** Added @MainActor to all test methods that interact with Store
- **Files modified:** examples/fuse-library/Tests/DependencyTests/DependencyTests.swift
- **Committed in:** dd20305 (Task 1 commit)

**3. [Rule 3 - Blocking] @DependencyClient private access level**
- **Found during:** Task 2
- **Issue:** `private struct NumberClient` caused macro-generated init to be private, inaccessible from test methods
- **Fix:** Changed to internal (file-scope) struct
- **Files modified:** examples/fuse-library/Tests/DependencyTests/DependencyTests.swift
- **Committed in:** 2d077c0 (Task 2 commit)

**4. [Rule 3 - Blocking] @CasePathable cannot attach to local types**
- **Found during:** Task 2
- **Issue:** Swift macros cannot be applied to types defined inside function bodies
- **Fix:** Moved TestAction enum to file scope
- **Files modified:** examples/fuse-library/Tests/DependencyTests/DependencyTests.swift
- **Committed in:** 2d077c0 (Task 2 commit)

**5. [Rule 1 - Bug] NumberClient missing Sendable conformance**
- **Found during:** Task 2
- **Issue:** TestDependencyKey requires Sendable; NumberClient's closure property needed @Sendable annotation
- **Fix:** Added Sendable conformance and @Sendable to closure type
- **Files modified:** examples/fuse-library/Tests/DependencyTests/DependencyTests.swift
- **Committed in:** 2d077c0 (Task 2 commit)

---

**Total deviations:** 5 auto-fixed (2 blocking, 3 bugs)
**Impact on plan:** All fixes were necessary for compilation and test correctness. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 12 DEP requirements validated with 19 passing tests
- Phase 3 complete (both plans executed: Store/Reducer/Effect + Dependencies)
- Ready for Phase 4: Observable State (@ObservableState, ViewStore, Perception)
- Test patterns established for dependency injection validation

---
*Phase: 03-tca-core*
*Completed: 2026-02-22*
