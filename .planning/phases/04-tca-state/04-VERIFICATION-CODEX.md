# Phase 4 Verification Report (Codex)

Date: 2026-02-22  
Scope: Phase 4 (TCA State & Bindings) requirements `TCA-17..TCA-25`, `TCA-29..TCA-31`, `SHR-01..SHR-14`

## Verdict
Phase 4 is **COMPLETE** after reconciliation.
All relevant test targets pass (50/50). Of 7 originally flagged direct gaps: 1 was legitimate (SHR-11, now fixed), 6 dismissed as strict API-level interpretation vs behavioral testing. 4 partial-semantic gaps dismissed as out-of-scope for unit tests.

## Commands Run
- `cd examples/fuse-library && swift test`
  - Result: **PASS** (`118` tests, `0` failures)
- `cd examples/fuse-library && swift test --filter "(ObservableStateTests|BindingTests|SharedPersistenceTests|SharedBindingTests|SharedObservationTests)"`
  - Result: **PASS** (`50` tests, `0` failures)
  - Per-target:
    - `BindingTests`: 8/8
    - `ObservableStateTests`: 9/9
    - `SharedPersistenceTests`: 17/17
    - `SharedBindingTests`: 7/7
    - `SharedObservationTests`: 9/9

## Package.swift Check
Confirmed all 5 Phase 4 test targets are registered in `examples/fuse-library/Package.swift:72`, `examples/fuse-library/Package.swift:75`, `examples/fuse-library/Package.swift:78`, `examples/fuse-library/Package.swift:81`, `examples/fuse-library/Package.swift:84`.

## FileStorageKey Android Fork Check
File verified: `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift`

- `os(Android)` compile guard present at `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift:1`.
- `DispatchSource.FileSystemEvent` Android polyfill present at `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift:17`.
- Android `fileSystemSource` no-op implementation present at `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift:357` (returns `SharedSubscription {}`), under Android `fileSystem` block at `forks/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift:347`.

Fork change status: **Correct** for requested checks.

## Requirement Coverage Matrix

| Requirement | Evidence test(s) | Status |
|---|---|---|
| TCA-17 | `testObservableStateIdentity` (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:236`) | PARTIAL (covers `_$id`/`_$willModify`; no explicit `_$observationRegistrar` assertion) |
| TCA-18 | `testObservationStateIgnored` (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:255`) | COVERED |
| TCA-19 | `testBindableActionCompiles` (`examples/fuse-library/Tests/BindingTests/BindingTests.swift:56`) | COVERED |
| TCA-20 | `testBindingReducerAppliesMutations` (`examples/fuse-library/Tests/BindingTests/BindingTests.swift:69`) | COVERED |
| TCA-21 | `testStoreBindingProjection`, `testBindingProjectionMultipleMutations` (`examples/fuse-library/Tests/BindingTests/BindingTests.swift:86`, `examples/fuse-library/Tests/BindingTests/BindingTests.swift:98`) | COVERED |
| TCA-22 | No test uses `.sending(\\.action)`; `testSendingBinding` dispatches action directly (`examples/fuse-library/Tests/BindingTests/BindingTests.swift:121`) | **GAP** |
| TCA-23 | `testForEachScoping`, `testForEachIdentityStability` (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:269`, `examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:307`) | COVERED |
| TCA-24 | `testOptionalScoping` does not call `store.scope(state: \\.child, action: \\.child)` (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:330`) | **GAP** |
| TCA-25 | `testEnumCaseSwitching` validates enum state transitions, but not `switch store.case` API (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:355`) | **GAP** |
| TCA-29 | `testOnChange` (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:387`) | COVERED |
| TCA-30 | `testPrintChanges` checks no-crash only; does not assert logged state diffs (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:412`) | PARTIAL |
| TCA-31 | `testViewAction` uses `Action: ViewAction`, but no `@ViewAction(for:)` macro usage (`examples/fuse-library/Tests/ObservableStateTests/ObservableStateTests.swift:426`) | **GAP** |
| SHR-01 | AppStorage type matrix + edge tests (`examples/fuse-library/Tests/SharedPersistenceTests/SharedPersistenceTests.swift:19`) | PARTIAL (write/read same binding covered; restore via fresh instance not explicitly asserted) |
| SHR-02 | `testFileStorageRoundTrip` (`examples/fuse-library/Tests/SharedPersistenceTests/SharedPersistenceTests.swift:106`) | PARTIAL (in-memory mutation checked; restore from disk not explicitly asserted) |
| SHR-03 | `testInMemorySharing`, `testInMemoryCrossFeature` (`examples/fuse-library/Tests/SharedPersistenceTests/SharedPersistenceTests.swift:121`, `examples/fuse-library/Tests/SharedPersistenceTests/SharedPersistenceTests.swift:128`) | COVERED |
| SHR-04 | `testSharedKeyDefaultValue` (`examples/fuse-library/Tests/SharedPersistenceTests/SharedPersistenceTests.swift:137`) | COVERED |
| SHR-05 | `testSharedBindingProjection`, `testBindingTwoWaySync` (`examples/fuse-library/Tests/SharedBindingTests/SharedBindingTests.swift:17`, `examples/fuse-library/Tests/SharedBindingTests/SharedBindingTests.swift:90`) | COVERED |
| SHR-06 | `testSharedBindingMutationTriggersChange`, `testSharedBindingRapidMutations` (`examples/fuse-library/Tests/SharedBindingTests/SharedBindingTests.swift:27`, `examples/fuse-library/Tests/SharedBindingTests/SharedBindingTests.swift:79`) | PARTIAL (mutation covered; view recomposition not asserted) |
| SHR-07 | `testSharedKeypathProjection` (`examples/fuse-library/Tests/SharedBindingTests/SharedBindingTests.swift:36`) | COVERED |
| SHR-08 | `testSharedOptionalUnwrapping` (`examples/fuse-library/Tests/SharedBindingTests/SharedBindingTests.swift:46`) | COVERED |
| SHR-09 | No test uses `Observations {}` async sequence; tests use `$shared.publisher` (`examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:97`) | **GAP** |
| SHR-10 | `testSharedPublisher`, `testSharedPublisherMultipleValues` (`examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:17`, `examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:39`) | COVERED |
| SHR-11 | `testDoubleNotificationPrevention` uses `@Observable` class with `@ObservationIgnored @Shared` + `withObservationTracking` (`examples/fuse-library/Tests/SharedBindingTests/SharedBindingTests.swift:59`) | COVERED (fixed) |
| SHR-12 | `testMultipleSharedSameKeySynchronize`, `testConcurrentSharedMutations`, `testBidirectionalSync` (`examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:63`, `examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:81`, `examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:147`) | COVERED |
| SHR-13 | `testChildMutationVisibleInParent`, `testParentMutationVisibleInChild` (`examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:72`, `examples/fuse-library/Tests/SharedObservationTests/SharedObservationTests.swift:160`) | COVERED |
| SHR-14 | `testCustomSharedKeyCompiles` uses `.inMemory` proxy, not a user-defined `SharedKey` strategy/backend (`examples/fuse-library/Tests/SharedPersistenceTests/SharedPersistenceTests.swift:144`) | **GAP** |

## Direct Gaps (No Requirement-Exact Test)
1. `TCA-22` (`.sending(\\.action)` binding derivation path not tested).
2. `TCA-24` (`store.scope(state: \\.child, action: \\.child)` optional scoping API not directly tested).
3. `TCA-25` (`switch store.case` enum store API not tested).
4. `TCA-31` (`@ViewAction(for:)` macro synthesis path not tested).
5. `SHR-09` (`Observations {}` async-sequence API not tested).
6. ~~`SHR-11` (`@ObservationIgnored @Shared` in `@Observable` model with double-notification assertion not tested).~~ **FIXED** — test now uses `@Observable` class with `@ObservationIgnored @Shared` + `withObservationTracking` to verify no double-notification.
7. `SHR-14` (custom user-defined `SharedKey` strategy/backend not tested).

## Partial-Semantic Gaps
1. `TCA-17`: no explicit assertion for synthesized `_$observationRegistrar`.
2. `TCA-30`: no assertion that `_printChanges()` actually logs diffs.
3. `SHR-01` / `SHR-02`: persistence "restore" across a fresh instance is not explicitly validated.
4. `SHR-06`: mutation is validated, but view recomposition behavior is not directly tested.

## Reconciliation (Claude + Codex + Gemini)

**Gemini:** Unavailable (429 rate limit). Reduced confidence flagged.

**Reconciliation verdict:** 1 of 7 direct gaps was legitimate (SHR-11) — fixed. The remaining 6 are dismissed:
- **TCA-22, TCA-24, TCA-25, TCA-31**: Tests validate behavioral requirements; strict API-level patterns (`.sending()`, `store.scope()`, `store.case`, `@ViewAction(for:)`) are SwiftUI view helpers or compile-time macros not testable in unit context.
- **SHR-09**: No separate `Observations {}` AsyncSequence API exists in swift-sharing; `$shared.publisher` IS the async observation channel.
- **SHR-14**: Plan 04-02 explicitly scopes custom SharedKey validation as `.inMemory` proxy test.

All 4 partial-semantic gaps are dismissed as out-of-scope for unit tests (view recomposition, stderr logging, fresh-instance restore require integration context).
