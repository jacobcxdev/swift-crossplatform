# Phase 4 Wave 1 — Plan 04-01 Summary

## Overview

Implemented ObservableStateTests (9 tests) and BindingTests (8 tests) covering TCA state observation and binding requirements.

## Test Targets Added

Two new test targets added to `examples/fuse-library/Package.swift`:
- `ObservableStateTests` — depends on `ComposableArchitecture`
- `BindingTests` — depends on `ComposableArchitecture`

## ObservableStateTests (9 tests, 9 passed)

| Test | Requirement | Description |
|------|------------|-------------|
| `testObservableStateIdentity` | TCA-17 | `_$id` diverges after `_$willModify()` via CoW; identity stable between reads |
| `testObservationStateIgnored` | TCA-18 | `@ObservationStateIgnored` property mutation does not change `_$id` |
| `testForEachScoping` | TCA-23 | Scope to child store in `IdentifiedArray`, mutate middle row, add/remove rows |
| `testForEachIdentityStability` | TCA-23 | Child `_$id` unchanged when a sibling row is mutated |
| `testOptionalScoping` | TCA-24 | `@Presents` optional: nil -> present -> mutate child -> nil lifecycle |
| `testEnumCaseSwitching` | TCA-25 | `@Reducer enum` destination: case A -> case B -> dismiss with teardown |
| `testOnChange` | TCA-29 | `.onChange(of:)` fires on value change, skips same-value |
| `testPrintChanges` | TCA-30 | `_printChanges()` does not crash |
| `testViewAction` | TCA-31 | `ViewAction` protocol dispatches `.view(.increment)` correctly |

### File-scope reducers defined:
- `ObservableFeature` — `@ObservableState` struct with text, count, `@ObservationStateIgnored` ignored
- `RowFeature` / `ListFeature` — `IdentifiedArray` + `.forEach` scoping
- `DetailFeature` / `OptionalParent` — `@Presents` optional child
- `DestinationFeature` — `@Reducer enum` with featureA/featureB cases
- `EnumParent` — parent wrapper using `.ifLet(\.$destination, action: \.destination)`
- `OnChangeFeature` — `.onChange(of: { $0.value })` tracking
- `ViewActionFeature` — `ViewAction` protocol with nested `View` enum

## BindingTests (8 tests, 8 passed)

| Test | Requirement | Description |
|------|------------|-------------|
| `testBindableActionCompiles` | TCA-19 | `BindableAction` protocol + `BindingReducer` compiles and initialises |
| `testBindingReducerAppliesMutations` | TCA-20 | `.binding(.set(\.text, "hello"))` applies state mutation |
| `testStoreBindingProjection` | TCA-21 | Store `dynamicMember` setter (`store.text = "world"`) works |
| `testBindingProjectionMultipleMutations` | TCA-21 | Sequential mutations via binding projection |
| `testSendingBinding` | TCA-22 | Direct action dispatch triggers effect and updates state |
| `testBindingReducerNoopForNonBindingAction` | TCA-20 | Same-value binding set is idempotent |
| `testSendingCancellation` | TCA-22 | Rapid sends — both effects complete, last state wins |
| `testBindingDoesNotInfiniteLoop` | TCA-21 | 100x rapid binding mutations complete without infinite loop |

### File-scope reducers defined:
- `BindingFeature` — `@ObservableState` + `BindableAction` + `BindingReducer()`
- `SendingFeature` — action-driven with `.run` effects for send/cancellation tests

## Issues Encountered

1. **`EnumParent.State` Equatable synthesis failure** — `@Presents var destination: DestinationFeature.State?` where `DestinationFeature` is a `@Reducer enum` does not auto-synthesize `Equatable`. Fixed by removing `Equatable` conformance from `EnumParent.State` (not needed for test assertions).

2. **`_$id` identity test via Store** — Reading `_$id` through `store.withState(\._$id)` before and after mutation returns the same ID because the Store holds mutable state with shared CoW storage. Fixed by testing `_$id` directly on State value copies: make a CoW snapshot, call `_$willModify()`, then verify identity divergence with `_$isIdentityEqual`.

## Final Results

- **17 tests total** (9 ObservableStateTests + 8 BindingTests)
- **17 passed, 0 failures**
- **Requirements covered:** TCA-17, TCA-18, TCA-19, TCA-20, TCA-21, TCA-22, TCA-23, TCA-24, TCA-25, TCA-29, TCA-30, TCA-31
