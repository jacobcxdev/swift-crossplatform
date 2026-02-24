# Phase 14: Test Execution Results
**Date:** 2026-02-24
**Emulator available:** yes (emulator-5554)

## Darwin Results

### fuse-library
- Total tests: 256
- Passed: 256
- Failed: 0
- Known issues: 9
- Test suites (22): StructuredQueriesTests, "Stress Tests", "Observation Bridge Semantics", "TextState and ButtonState Parity Tests", NavigationStackTests, NavigationTests, ViewActionAnimationTests, PresentationTests, SharedObservationTests, UIPatternTests, EnumCaseSwitchingTests, "Presentation Parity Tests", SharedBindingTests, ObservableStateTests, StoreReducerTests, BindingTests, TestStoreEdgeCaseTests, SharedPersistenceTests, TestStoreTests, DependencyTests, SQLiteDataTests, EffectTests

### fuse-app
- Total tests: 30
- Passed: 30
- Failed: 0
- Known issues: 0
- Test suites (7): DatabaseFeatureTests, TodosFeatureTests, CounterFeatureTests, AppFeatureTests, SettingsFeatureTests, ContactDetailFeatureTests, ContactsFeatureTests

## Android Results

### fuse-library
- Total Kotlin tests: 251
- Passed: 250
- Failed: 1
- Known issues: 9
- Test suites (22): StructuredQueriesTests ✓, "Stress Tests" ✓, "Observation Bridge Semantics" ✓, "TextState and ButtonState Parity Tests" ✓, NavigationStackTests ✓, NavigationTests ✓, ViewActionAnimationTests ✓, PresentationTests ✓, SharedObservationTests ✓, UIPatternTests ✓, EnumCaseSwitchingTests ✓, "Presentation Parity Tests" ✓, SharedBindingTests ✓, ObservableStateTests ✓, StoreReducerTests ✓, BindingTests ✓, TestStoreEdgeCaseTests ✓, SharedPersistenceTests ✓, TestStoreTests ✓ (1 known issue), DependencyTests ✓ (1 known issue), SQLiteDataTests ✓, EffectTests ✗ (1 real failure)

**Single failure:** `effectRun()` in EffectTests — `store.withState(\.value)` returned `""` instead of `"hello"`. Likely an async timing issue on Android where the effect closure completes but the state isn't flushed before assertion. All other Effect tests (effectRunFromBackgroundThread, effectRunWithDependencies, effectMerge, effectConcatenate, effectCancellable, effectCancel, effectCancelInFlight, effectSend, effectNone) pass.

**Known issues (9):** All are `withKnownIssue`-wrapped expected behaviors: 5 IssueReporting tests (reportIssueStringMessage, reportIssueErrorInstance, reportIssueIncludesSourceLocation, withErrorReportingSyncCatchesErrors, withErrorReportingAsyncCatchesErrors), 1 CustomDump test (expectNoDifferenceFailsForDifferentValues), 1 TestStore test (exhaustivityOnDetectsUnassertedChange), 1 Dependency test (dependencyClientUnimplementedReportsIssue), 1 withErrorReportingReturnsNilOnError.

### fuse-app
- Total Kotlin tests: 30
- Passed: 30
- Failed: 0
- Known issues: 4
- Test suites (7): DatabaseFeatureTests ✓, TodosFeatureTests ✓, CounterFeatureTests ✓, AppFeatureTests ✓, SettingsFeatureTests ✓, ContactDetailFeatureTests ✓ (2 known issues), ContactsFeatureTests ✓ (2 known issues)

**Known issues (4):** All are dismiss-related JNI pipeline timing issues in ContactDetailFeatureTests (editSavesContact) and ContactsFeatureTests (addContactSaveAndDismiss) — destination.dismiss action not delivered within timeout. Tests still pass because they use `withKnownIssue`.

## Test File Gating Analysis

Test files in examples/ (excluding .build/ and checkouts/):

| Test File | Has #if !SKIP | Runs on Android | Notes |
|-----------|---------------|-----------------|-------|
| FuseAppIntegrationTests.swift | Yes | Yes (partial) | Some sections gated, but 30 tests transpile |
| FuseLibraryTests.swift | No | Yes | Entry point for library tests |
| ObservationTests.swift | No | Yes | Core observation bridge tests |
| ObservationBridgeTests.swift | Yes | Yes (partial) | Bridge semantics tests transpile |
| StressTests.swift | Yes | Yes (partial) | Stress tests transpile |
| CasePathsTests.swift | Yes | Yes | CasePath tests transpile |
| CustomDumpTests.swift | Yes | Yes | CustomDump tests transpile |
| IdentifiedCollectionsTests.swift | Yes | Yes | IC tests transpile |
| IssueReportingTests.swift | Yes | Yes | IR tests transpile |
| NavigationStackTests.swift | Yes | Yes | Navigation stack tests transpile |
| NavigationTests.swift | Yes | Yes | Navigation tests transpile |
| PresentationParityTests.swift | Yes | Yes | Presentation parity transpile |
| PresentationTests.swift | Yes | Yes | Presentation tests transpile |
| TextStateButtonStateTests.swift | Yes | Yes | TextState/ButtonState transpile |
| UIPatternTests.swift | Yes | Yes | UI pattern tests transpile |
| SharedBindingTests.swift | Yes | Yes | Shared binding tests transpile |
| SharedObservationTests.swift | Yes | Yes | Shared observation transpile |
| SharedPersistenceTests.swift | Yes | Yes | Shared persistence transpile |
| BindingTests.swift | Yes | Yes | Binding tests transpile |
| DependencyTests.swift | Yes | Yes | Dependency tests transpile |
| EffectTests.swift | Yes | Yes | Effect tests transpile (1 failure) |
| EnumCaseSwitchingTests.swift | Yes | Yes | Enum case switching transpile |
| ObservableStateTests.swift | Yes | Yes | Observable state transpile |
| StoreReducerTests.swift | Yes | Yes | Store/reducer tests transpile |
| TestStoreEdgeCaseTests.swift | Yes | Yes | TestStore edge cases transpile |
| TestStoreTests.swift | Yes | Yes | TestStore tests transpile |
| ViewActionAnimationTests.swift | Yes | Yes | ViewAction animation transpile |
| SQLiteDataTests.swift | Yes | Yes | SQLite data tests transpile |
| XCSkipTests.swift (x8) | No | Yes | Android test entry points |

**Key finding:** Although 27 of 35 source test files contain `#if !SKIP` guards, these guards wrap SPECIFIC SECTIONS (Swift Testing macros, imports) rather than entire files. The test methods themselves ARE transpiled by skipstone and execute on Android. This is why 251 Android tests run despite the gating — the guards protect non-transpilable code snippets while allowing test logic to compile for Kotlin.

## Raw Output Excerpts

### fuse-library Android summary line
```
✘ Test run with 251 tests in 22 suites failed after 3.327 seconds with 10 issues (including 9 known issues).
```

### fuse-app Android summary line
```
✘ Test run with 30 tests in 7 suites passed after 10.372 seconds with 4 known issues.
```

### fuse-library Darwin summary line
```
Test run with 256 tests in 22 suites passed after 2.038 seconds with 9 known issues.
```

### fuse-app Darwin summary line
```
Test run with 30 tests in 7 suites passed after 0.107 seconds.
```

### Darwin vs Android delta
- fuse-library: 256 Darwin vs 251 Android = 5 tests macOS-only (gated sections that don't transpile)
- fuse-app: 30 Darwin vs 30 Android = exact parity
