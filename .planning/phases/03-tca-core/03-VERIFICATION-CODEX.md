---
phase: 03-tca-core
type: verification
status: gaps_found
date: 2026-02-22
---

## Phase Goal
TCA Store, reducers, effects, and dependency injection should work correctly on Android (`.planning/ROADMAP.md:58`).

Verification outcome: core TCA and dependency behavior is strongly validated on macOS via targeted tests, and all Phase 3 requirement IDs in plan frontmatter are present in `REQUIREMENTS.md` (28/28 accounted for). However, multiple plan must-haves are not met exactly as written, so goal achievement is marked with gaps.

## Requirements Coverage
| ID | Description | Status | Evidence |
| --- | --- | --- | --- |
| TCA-01 | `Store.init(initialState:reducer:)` initializes correctly on Android | Satisfied | `testStoreInitialState` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:203`; suite pass (11/11). |
| TCA-02 | `Store.init(...withDependencies:)` applies prepareDependencies overrides | Satisfied | `testStoreInitWithDependencies` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:213`. |
| TCA-03 | `store.send` dispatches action and returns `StoreTask` | Satisfied | `testStoreSendReturnsStoreTask` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:229`. |
| TCA-04 | `store.scope(state:action:)` derives child store | Satisfied | `testStoreScopeDerivesChildStore` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:241`. |
| TCA-05 | `Scope(state:action:)` runs child reducer | Satisfied | `testScopeReducer` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:254`. |
| TCA-06 | `.ifLet` runs child reducer for non-nil optional state | Satisfied | `testIfLetReducer` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:267`. |
| TCA-07 | `.forEach` runs reducer per collection element | Satisfied | `testForEachReducer` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:290`. |
| TCA-08 | `.ifCaseLet` runs reducer when enum case matches | Satisfied | `testIfCaseLetReducer` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:310`. |
| TCA-09 | `CombineReducers` composes reducers in sequence | Satisfied | `testCombineReducers` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:334`. |
| TCA-10 | `Effect.none` has no side effects | Satisfied | `testEffectNone` in `examples/fuse-library/Tests/EffectTests/EffectTests.swift:210`. |
| TCA-11 | `Effect.run` executes async work and sends actions | Satisfied | `testEffectRun` and background-send variant in `examples/fuse-library/Tests/EffectTests/EffectTests.swift:221` and `examples/fuse-library/Tests/EffectTests/EffectTests.swift:234`. |
| TCA-12 | `Effect.merge` runs effects concurrently | Satisfied | `testEffectMerge` in `examples/fuse-library/Tests/EffectTests/EffectTests.swift:246`. |
| TCA-13 | `Effect.concatenate` runs effects sequentially | Satisfied | `testEffectConcatenate` in `examples/fuse-library/Tests/EffectTests/EffectTests.swift:261`. |
| TCA-14 | `Effect.cancellable(id:cancelInFlight:)` manages cancellable lifecycle | Satisfied | `testEffectCancellable` and `testEffectCancelInFlight` in `examples/fuse-library/Tests/EffectTests/EffectTests.swift:273` and `examples/fuse-library/Tests/EffectTests/EffectTests.swift:288`. |
| TCA-15 | `Effect.cancel(id:)` cancels in-flight effect | Satisfied | `testEffectCancel` in `examples/fuse-library/Tests/EffectTests/EffectTests.swift:303`. |
| TCA-16 | `Effect.send(_:)` dispatches synchronously | Satisfied | `testEffectSend` in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:346`. |
| DEP-01 | `@Dependency(\.keyPath)` resolves from `DependencyValues` | Satisfied | `testDependencyKeyPathResolution` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:100`. |
| DEP-02 | `@Dependency(Type.self)` resolves by type conformance | Satisfied | `testDependencyTypeResolution` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:111`. |
| DEP-03 | `DependencyKey.liveValue` used in live context | Satisfied | `testLiveValueInProductionContext` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:123`. |
| DEP-04 | `DependencyKey.testValue` used in test context | Satisfied | `testTestValueInTestContext` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:135`. |
| DEP-05 | `DependencyKey.previewValue` used in preview context | Partial | Only negative assertion (`context != .preview`) in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:147`; no direct preview-value path validation. |
| DEP-06 | Custom `DependencyValues` computed property registration works | Satisfied | `testCustomDependencyKeyRegistration` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:156`. |
| DEP-07 | `@DependencyClient` unimplemented defaults + implementation override work | Satisfied | `testDependencyClientUnimplementedReportsIssue` and `testDependencyClientImplementedEndpoint` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:361` and `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:376`. |
| DEP-08 | `Reducer.dependency(_:_:)` override applies in reducer scope | Satisfied | `testReducerDependencyModifier` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:388`. |
| DEP-09 | `withDependencies` scoping works in closures/TaskLocal flow | Satisfied | `testWithDependenciesSyncScoping` and `testTaskLocalPropagation` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:171` and `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:477`. |
| DEP-10 | `prepareDependencies` runs before dependency access | Satisfied | `testPrepareDependencies` in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:187`. |
| DEP-11 | Child scopes inherit parent dependency context | Satisfied | `testChildReducerInheritsDependencies` + grandchild case in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:205` and `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:224`. |
| DEP-12 | `@Dependency` in effect closures resolves overridden values | Satisfied | `testDependencyResolvesInEffectClosure` and merged-effects variant in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:405` and `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:426`. |

Coverage accounting check:
- Plan-frontmatter IDs extracted from `03-01-PLAN.md` and `03-02-PLAN.md`: 28 IDs.
- IDs found in `REQUIREMENTS.md`: 28/28 (none missing).

## Must-Have Verification
### 03-01 must_haves (`.planning/phases/03-tca-core/03-01-PLAN.md:31`)
- PASS: Store init/send/scope/composition/effects/cancellation truths are covered by `StoreReducerTests` and `EffectTests` (`examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:203`, `examples/fuse-library/Tests/EffectTests/EffectTests.swift:210`).
- FAIL: `DependenciesTestObserver` wiring truth does not match code. Plan requires `DependenciesTestObserver` (`.planning/phases/03-tca-core/03-01-PLAN.md:40`), but `Package.swift` uses `DependenciesTestSupport` (`examples/fuse-library/Package.swift:68`).
- PASS: Artifact line minimums met: `StoreReducerTests.swift` 366 lines (min 150), `EffectTests.swift` 327 lines (min 120).
- PASS: Key-link patterns are present (`ComposableArchitecture` package product in `examples/fuse-library/Package.swift:60`, `Store(initialState:` usage in `examples/fuse-library/Tests/StoreReducerTests/StoreReducerTests.swift:204`, effect APIs in `examples/fuse-library/Tests/EffectTests/EffectTests.swift:218`).

### 03-02 must_haves (`.planning/phases/03-tca-core/03-02-PLAN.md:24`)
- PASS: Live/test dependency context behavior, withDependencies propagation, and child inheritance are validated (`examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:123`, `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:171`, `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:205`).
- PASS: `@DependencyClient` unimplemented/implemented behavior and EnumMetadata path are validated (`examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:361`, `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:448`).
- FAIL: “All 19 built-in dependency keys” truth is not met as written. Test suite covers 16 available keys + `openURL`, but not the full stated set including `reportIssue`, `dismiss`, and `openSettings` from the plan text (`.planning/phases/03-tca-core/03-02-PLAN.md:30`, `.planning/phases/03-tca-core/03-02-PLAN.md:131`, `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:243`).
- PASS: Artifact minimum met: `DependencyTests.swift` is 549 lines (min 200).
- PASS: Key-link patterns are present (`@Dependency(`, `EnumMetadata`, `DependencyKey`) in `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:47`, `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:451`, `examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:9`.

## Test Evidence
- `cd examples/fuse-library && swift build --build-tests` succeeded.
- `cd examples/fuse-library && swift test --filter StoreReducerTests` passed: 11/11 tests.
- `cd examples/fuse-library && swift test --filter EffectTests` passed: 9/9 tests.
- `cd examples/fuse-library && swift test --filter DependencyTests` passed: 19/19 tests.
  - Includes expected failure acceptance for unimplemented `@DependencyClient` endpoint (`Unimplemented: 'NumberClient.fetch'`).
- `cd examples/fuse-library && swift test` failed (exit 1) due Skip plugin Android packaging path error:
  - missing folder `.../src/forks/swift-snapshot-testing` during `:FuseLibrary:buildLocalSwiftPackage`.

## Gaps (if any)
1. `DependenciesTestObserver` must-have mismatch.
   - Expected by plan: `DependenciesTestObserver` wiring (`.planning/phases/03-tca-core/03-01-PLAN.md:40`).
   - Actual: `DependenciesTestSupport` used (`examples/fuse-library/Package.swift:68`).
2. Built-in dependency validation must-have mismatch.
   - Expected by plan: all 19 keys with 3 platform-specific documented (`.planning/phases/03-tca-core/03-02-PLAN.md:30`).
   - Actual: test implementation validates subset/variant (16 + `openURL`) and omits plan-listed `reportIssue`, `dismiss`, `openSettings` checks (`examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:243`).
3. DEP-05 evidence gap.
   - Requirement asks for previewValue behavior in preview context (`.planning/REQUIREMENTS.md:93`).
   - Current test only checks preview context is absent (`examples/fuse-library/Tests/DependencyTests/DependencyTests.swift:147`).
4. Full-suite regression signal.
   - `swift test` currently fails in plugin-driven Android packaging path (`buildLocalSwiftPackage`), so complete end-to-end suite health is not green.

## Summary
Phase 03 has strong macOS test validation for all TCA core mechanics and most dependency requirements, and all 28 plan requirement IDs are correctly accounted for in `REQUIREMENTS.md`. Status is `gaps_found` because must-have contract items are not met exactly as written (`DependenciesTestObserver`, full 19-key dependency validation), DEP-05 is only partially evidenced, and full-suite `swift test` is currently failing in plugin packaging.