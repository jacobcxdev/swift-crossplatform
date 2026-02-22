# Phase 4: TCA State & Bindings — Implementation Context

> Decisions from discuss-phase session (2026-02-22).
> These guide research and planning — downstream agents should not re-ask these questions.

## Phase Boundary

**In scope:** TCA-17..TCA-25, TCA-29..TCA-31, SHR-01..SHR-14 (26 requirements)
**Out of scope:** Navigation/presentation (Phase 5), database (Phase 6), TestStore (Phase 7)

## 1. @Shared Persistence Backends on Android

### appStorage (SHR-01)
- Skip bridges `UserDefaults` → Android `SharedPreferences`. **Validate exhaustively.**
- Test every value type TCA supports: Bool, Int, Double, String, Data, URL, Date, optionals, RawRepresentable enums.
- Edge cases required: nil optionals, large Data blobs, emoji/Unicode strings, concurrent read/write from different actors.
- Don't assume Skip's bridging is complete — prove each type round-trips correctly.

### fileStorage (SHR-02)
- **Investigate first** before committing to a strategy.
- Research: How does Skip handle `FileManager` and `URL` file operations on Android? Where do file URLs resolve? What about app sandboxing?
- TCA writes Codable JSON to a `URL`. Need to confirm the URL resolves to a writable Android path (likely `Context.getFilesDir()` equivalent).
- Decision on path strategy is deferred to research phase.

### inMemory (SHR-03)
- **Trivially portable.** Pure in-memory dictionary storage, no platform dependencies.
- Just validate it works — no deep investigation needed.

### Custom SharedKey (SHR-14)
- **Validate the extension point works.** Write a test custom `SharedKey` implementation that compiles and runs on Android.
- Proves third-party persistence backends are viable on the platform.

## 2. Binding Projection Mechanics

### Full Binding Chain (TCA-19..TCA-21)
- **End-to-end validation required** — test the full chain: store → @Bindable → $store.property → Compose recomposition.
- **Infinite recomposition regression test** — binding write → state change → binding read must NOT loop. This is the Phase 1 bug resurfacing at the binding layer.
- Verify exactly one recomposition per binding mutation.

### sending() API (TCA-22)
- **Full behavioral parity** with regular BindingAction bindings.
- Test: state updates correctly, effects triggered by the sent action execute, cancellation works.

### ForEach Scoping (TCA-23)
- **Validate identity stability** — IdentifiedArray IDs must map to stable Compose keys.
- Test: adding, removing, and reordering items preserves child store identity.
- Verify child stores are NOT recreated on reorder (would lose child state).

### Conditional Scoping (TCA-24, TCA-25)
- **Full lifecycle validation** for both patterns:
  - Optional: nil → non-nil → nil transitions. Verify child stores are created on non-nil, destroyed on nil.
  - Enum: case A → case B transitions. Verify old case's child store is torn down, new case's is created.
- Stale state after transition is the primary risk.

### $shared Bindings (SHR-05, SHR-06)
- Same binding chain validation applies — `$shared` creates a `Binding<T>` that must drive Compose recomposition correctly.

### Shared Projections (SHR-07, SHR-08)
- **Test via behavior** — keypath projection (`$parent.child`) and optional unwrapping (`Shared($optional)`) should just work.
- No need to investigate keypath runtime internals; Swift keypaths have been reliable on Android.

## 3. Combine Publisher for @Shared

### Strategy: OpenCombine (Already Patched)
- The library fork **already uses OpenCombine on Android** — this is an existing patch, not Skip's responsibility.
- Validate that `$shared.publisher` works correctly with OpenCombine on Android.
- **Both APIs are required:** `$shared.publisher` (Combine/OpenCombine) AND `Observations {}` async sequence (SHR-09). Cannot gate/exclude the publisher.

### Internal Combine Audit
- **Full audit** of all Combine usage in swift-sharing for Android compatibility.
- Grep every `import Combine`, `Publisher`, `Subject`, `sink`, `assign`, `debounce`, `throttle` callsite.
- Verify each works with OpenCombine or has an `#if canImport(Combine)` / `os(Android)` fallback.
- Known internal usage: debouncing file writes. May be others.

## 4. Macro-Synthesized Code Portability

### @ObservableState (TCA-17, TCA-18)
- **Test via behavior** — don't inspect macro output directly.
- Write tests that use `@ObservableState` structs and verify: property mutation triggers view update, `@ObservationStateIgnored` suppresses tracking, `_$id` identity is stable.
- Phase 1's ObservationStateRegistrar work should make this work, but prove it.

### @ViewAction (TCA-31)
- **Behavioral test** — verify `send()` dispatches the correct action to the store on Android.
- Pure Swift codegen, low risk, but confirm the runtime dispatch works.

### _printChanges (TCA-30)
- **Validate output format** on Android console.
- Uses `customDump` (validated in Phase 2), but verify the diff rendering is readable in Android logcat output.

### onChange (TCA-29)
- Pure reducer logic, **no concerns.** Standard behavioral test sufficient.

### @Reducer Enum Case Switching (TCA-25)
- **Explicit validation required.** `switch store.case {}` relies on:
  - `@Reducer` macro generating case reducer composition
  - `@CasePathable` enum metadata (validated in Phase 2)
  - `EnumMetadata.tag(of:)` for runtime case discrimination
- Phase 2 validated CasePaths and EnumMetadata ABI. Verify the full chain works when composed with Store scoping.

## 5. Cross-Cutting Concerns

### Double-Notification Prevention (SHR-11)
- **Dedicated regression test** required.
- Scenario: `@Observable` model containing `@ObservationIgnored @Shared` property.
- Verify exactly one notification per mutation, not two (one from Observable, one from Shared).

### Cross-Feature Sharing Thread Safety (SHR-12, SHR-13)
- **Thread safety focus** — explicitly test concurrent mutations from different features/actors.
- SHR-12: Multiple `@Shared` declarations with same key must synchronize.
- SHR-13: Child mutation of parent's `@Shared` must be immediately visible in parent.
- Verify locking primitives work correctly on Android's threading model.

## Deferred Ideas

*(Captured during discussion but out of Phase 4 scope)*

None — all discussion stayed within phase boundary.

## Next Steps

1. **Research phase** — investigate fileStorage URL bridging on Android, audit Combine usage in swift-sharing
2. **Plan phase** — break into 2 plans (likely: macros+bindings, then shared state+persistence)
