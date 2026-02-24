# R1: TestStore on Android — Deep Investigation

**Date:** 2026-02-22
**File under analysis:** `forks/swift-composable-architecture/Sources/ComposableArchitecture/TestStore.swift`
**Existing parity tests:** `forks/swift-composable-architecture/Tests/ComposableArchitectureTests/AndroidParityTests.swift`

---

## Summary

TestStore has **5 platform divergence points** in `TestStore.swift`, all guarded by `#if !os(Android)`. The core divergence is the **synchronisation mechanism**: Apple platforms use `MainSerialExecutor` to serialise all async work onto the main thread, providing deterministic ordering. Android lacks `MainSerialExecutor` entirely and instead uses an `effectDidSubscribe` AsyncStream as a signalling mechanism to know when effects have started.

The `effectDidSubscribe` mechanism is **already functional** — it is the same fallback path that Apple platforms use when `useMainSerialExecutor` is set to `false`. The `TestReducer` class (line 2836) owns the stream and yields into it from two places:

1. **`.none` effects** (line 2880): Yields immediately — the reducer produced no effect, so `send()` can proceed.
2. **`.publisher`/`.run` effects** (lines 2885-2893): Yields after `Task.megaYield()` inside a `receiveSubscription` handler — the effect has been subscribed to and is now in-flight.

The `AndroidParityTests.swift` file contains **17 tests** covering Category A (behavioural parity) and Category B (SwiftUI integration compilation). The Category A tests exercise: merge, concatenate, cancellation, send/receive sequencing, exhaustivity, `.send` effect, dismiss effect, binding, and logger fallback.

---

## Platform Divergence Map

### Divergence 1: `useMainSerialExecutor` property (lines 477-483)

```swift
#if !os(Android)
public var useMainSerialExecutor: Bool {
  get { uncheckedUseMainSerialExecutor }
  set { uncheckedUseMainSerialExecutor = newValue }
}
private let originalUseMainSerialExecutor = uncheckedUseMainSerialExecutor
#endif
```

**Impact:** On Android, this property does not exist. Tests cannot opt into `MainSerialExecutor` serialisation. The `uncheckedUseMainSerialExecutor` global (from `ConcurrencyExtras`) is unavailable.

**Risk:** LOW. Android always uses the `effectDidSubscribe` path. No API surface is lost because this property is a testing convenience, not a functional requirement.

### Divergence 2: Initialiser sets `useMainSerialExecutor = true` (lines 558-560)

```swift
#if !os(Android)
self.useMainSerialExecutor = true
#endif
```

**Impact:** On Apple, TestStore defaults to serialising all async work. On Android, this line is skipped entirely. The `effectDidSubscribe` stream is always used instead.

**Risk:** LOW. The stream-based synchronisation is the designed fallback. However, it means Android tests may have **slightly different timing characteristics** — effects are not strictly serialised on the main thread, so ordering of concurrent effects could theoretically differ.

### Divergence 3: `deinit` restores original executor (lines 654-656)

```swift
#if !os(Android)
uncheckedUseMainSerialExecutor = self.originalUseMainSerialExecutor
#endif
```

**Impact:** On Apple, TestStore restores the executor state on teardown. On Android, nothing to restore — no executor state was modified.

**Risk:** NONE. Correct by construction.

### Divergence 4: `send()` synchronisation after dispatching action (lines 1006-1018)

```swift
#if !os(Android)
if uncheckedUseMainSerialExecutor {
  await Task.yield()
} else {
  for await _ in self.reducer.effectDidSubscribe.stream {
    break
  }
}
#else
for await _ in self.reducer.effectDidSubscribe.stream {
  break
}
#endif
```

**Impact:** This is the **critical divergence**. After sending an action to the store:

- **Apple (default):** `await Task.yield()` — because the main serial executor ensures deterministic ordering, a single yield is sufficient for the effect to start.
- **Apple (useMainSerialExecutor=false) and Android:** Waits for the `effectDidSubscribe` stream to yield — this is a proper async signal that the effect's publisher has been subscribed to (or that the reducer returned `.none`).

**Risk:** MEDIUM. The `effectDidSubscribe` path has a subtle timing dependency:
- For `.none` effects: The continuation yields synchronously during `reduce()`, so the stream has data immediately. Safe.
- For `.publisher`/`.run` effects: The continuation yields inside a `Task { await Task.megaYield(); effectDidSubscribe.continuation.yield() }` block within `receiveSubscription`. This introduces a small async gap where `Task.megaYield()` must complete before the signal arrives. If the Swift runtime on Android schedules tasks differently, this gap could theoretically cause issues with very fast effect chains.

### Divergence 5: `bindings()` extension (lines 2580-2683)

```swift
#if canImport(SwiftUI) && !os(Android)
extension TestStore {
  public func bindings<ViewAction: BindableAction>(
    action toViewAction: CaseKeyPath<Action, ViewAction>
  ) -> BindingViewStore<State> where State == ViewAction.State, Action: CasePathable { ... }
}
#endif
```

**Impact:** The `bindings()` API is unavailable on Android. This is a SwiftUI testing convenience for verifying `BindingViewStore` state.

**Risk:** LOW for integration testing. Tests that use `store.bindings(action:)` cannot run on Android. Alternative: test binding state via `store.send(.binding(.set(...)))` which works on both platforms (already tested in `AndroidParityTests`).

---

## Effect Type Analysis

All effect types flow through `TestReducer.reduce(into:action:)` (line 2855), which matches on `effects.operation`:

### `.none` — No effect returned

**Mechanism:** `effectDidSubscribe.continuation.yield()` called synchronously (line 2880).
**Android behaviour:** Identical to Apple. The yield happens inline, so the waiting `for await` in `send()` resolves immediately.
**Risk:** NONE.

### `.run` — Async closure effect

**Mechanism:** `.run` effects are converted to `.publisher` via `_EffectPublisher`, which bridges the async `@Sendable (Send<Action>) async -> Void` closure into a Combine-compatible publisher. The `receiveSubscription` handler (line 2888) inserts the effect into `inFlightEffects` and signals `effectDidSubscribe` after `Task.megaYield()`.

**Android behaviour:** The `megaYield` before signalling means Android must wait for multiple cooperative scheduling points before `send()` resumes. The `Task.megaYield(count: 20)` at line 1049 (after state assertion in `send()`) provides additional buffer time.

**Risk:** LOW. Standard `.run` effects work correctly — the `AndroidParityTests` already verify `testEffectRunDeliversValues` and `testTestStoreSendReceive`.

### `.merge` — Parallel effects

**Mechanism:** When merging two effects:
- Two `.run` effects: Combined into a single `.run` using `withTaskGroup` (lines 288-297 of Effect.swift). This becomes a single `.run` operation at the TestReducer level.
- Mixed or `.publisher` effects: Combined via `Publishers.Merge` (lines 274-281). On Android without Combine, this uses the **hand-rolled `Publishers.Merge` polyfill** (lines 451-495 of Effect.swift) which uses `PassthroughSubject` and `NSLock`.

**Android behaviour:** The polyfill is functionally correct but uses `NSLock` instead of Apple's native `os_unfair_lock`. The `effectDidSubscribe` signal fires once for the merged publisher (not once per child). The signal timing depends on the outer `receiveSubscription`.

**Risk:** LOW-MEDIUM. The merge polyfill has been tested (`testMergeEffectDeliversAllValues`, `testMergeEffectWithRunAndSend`). The `NSLock` in the polyfill is sufficient for correctness. However, **ordering of merged values is non-deterministic** — on Apple with `MainSerialExecutor`, merged effects execute sequentially on the main thread. On Android, they run concurrently and ordering depends on scheduler behaviour. The existing tests account for this by asserting `.send` (synchronous) before `.run` (async).

### `.concatenate` — Sequential effects

**Mechanism:** When concatenating two effects:
- Two `.run` effects: Combined into a single `.run` where the second awaits the first (lines 347-365 of Effect.swift).
- Mixed or `.publisher` effects: Combined via `Publishers.Concatenate` (lines 337-344). On Android without Combine, this uses OpenCombine's `Publishers.Concatenate`.

**Android behaviour:** Sequential ordering is enforced by the implementation, not by the executor. The `effectDidSubscribe` signal fires for the concatenated publisher as a whole.

**Risk:** LOW. `testConcatenateDeliversSequentially` already verifies correct ordering. The sequential guarantee comes from the effect implementation, not from the synchronisation mechanism.

### `.cancellable` — Identified cancellable effect

**Mechanism:** `Cancellation.swift` wraps an effect with `handleEvents(receiveCancel:)` and registers it in a global `_cancellationCancellables` dictionary keyed by ID. **No Android-specific guards exist in Cancellation.swift.**

**Android behaviour:** Identical to Apple. The cancellation mechanism is purely publisher-based and does not depend on executor serialisation.

**Risk:** LOW. `testEffectCancellation` already verifies this path.

### `.cancel` — Cancel by ID

**Mechanism:** Returns an `Effect` that synchronously cancels all subscriptions registered under the given ID and then completes as `.none`.

**Android behaviour:** Identical to Apple.

**Risk:** LOW. Tested in `testEffectCancellation`.

### `.send` — Synchronous action dispatch

**Mechanism:** `Effect.send(_:)` wraps an action in a publisher that immediately emits and completes. On Apple, there's an `Effect.send(_:animation:)` variant that wraps in `withTransaction` — this is guarded by `#if canImport(SwiftUI) && !os(Android)` in `Effect.swift` (line 161).

**Android behaviour:** Only `Effect.send(_:)` (without animation) is available. The action is delivered synchronously via the publisher pipeline, so it becomes a `receivedAction` before `effectDidSubscribe` signals.

**Risk:** NONE. `testEffectSendDeliversAction` verifies this. The animation variant is correctly excluded.

---

## Edge Cases & Risks

### E1: Long-running effects

**Scenario:** An effect uses `Task.never()` or a long-lived `AsyncStream` that doesn't complete until cancelled.

**Android behaviour:** The `effectDidSubscribe` mechanism only signals when the effect **starts** (is subscribed to), not when it completes. Long-running effects are tracked in `inFlightEffects` and TestStore's `deinit`/`completed()` checks report them. The `finish(timeout:)` method polls `inFlightEffects.isEmpty` with a time-boxed loop — **no Android-specific path**.

**Risk:** LOW. The `finish()` mechanism is platform-agnostic. Tests must still use `task.cancel()` or `store.finish()` to clean up, same as Apple.

### E2: Cancelled effects

**Scenario:** An effect is cancelled via `.cancel(id:)` or `task.cancel()` before it produces any actions.

**Android behaviour:** The `receiveCancel` handler in `TestReducer` (line 2898) removes the effect from `inFlightEffects`. This is publisher-level cleanup, not executor-dependent.

**Risk:** LOW. `testEffectCancellation` covers this. However, there is a subtle edge case: if an effect is cancelled **between** `receiveSubscription` and the `effectDidSubscribe.continuation.yield()` call (which runs inside a `Task { await Task.megaYield(); ... }`), the yield still fires even though the effect was cancelled. This is harmless because `send()` only waits for one yield and then proceeds.

### E3: Effects that spawn child effects

**Scenario:** A `.run` effect sends an action whose reducer returns another effect.

**Android behaviour:** The child effect goes through the same `TestReducer.reduce()` path. The parent effect's `send` call dispatches via `store.send()` internally, which processes synchronously on the `@MainActor`. The child effect signals `effectDidSubscribe` independently.

**Risk:** MEDIUM. The `receive()` method's async variant (line 2200) uses a polling loop:
```swift
while !Task.isCancelled {
  await Task.detached(priority: .background) { await Task.yield() }.value
  // check receivedActions...
  // check timeout...
}
```
This polling loop is the **same on both platforms** — it does not use `effectDidSubscribe`. It simply waits until `receivedActions` is non-empty or times out. On Android, if the Swift runtime schedules the detached background task slowly, the polling could be slower, potentially hitting timeout boundaries more often.

**Recommendation:** Integration tests with chained effects should set a generous `timeout` on the TestStore.

### E4: Rapid-fire actions (stress scenario)

**Scenario:** Multiple `store.send()` calls in quick succession, each producing effects.

**Android behaviour:** Each `send()` awaits `effectDidSubscribe` before returning. The `AsyncStream.makeStream()` creates a **single stream** (line 2839) that is shared across all `send()` calls. Each `send()` consumes exactly one yield from the stream (via `for await _ in stream { break }`).

**Risk:** MEDIUM-HIGH. The `AsyncStream` is created once with `makeStream()` which returns a single `(stream, continuation)` pair. The `stream` property is accessed multiple times — once per `send()` call. **However**, `AsyncStream` supports multiple consumers only via `AsyncStream.makeStream()` where each call to `.stream` produces a new iteration. Looking at the code, `self.reducer.effectDidSubscribe.stream` is accessed as a property — this means each `send()` creates a new async iteration of the same stream. The continuation's yields are delivered to whichever iteration is currently awaiting.

If two `send()` calls are in-flight simultaneously (which shouldn't happen because they're sequential `await` calls), there could be a race. But since `send()` is `@MainActor` and each `send()` is `await`-ed, they are sequential by construction.

**Recommendation:** Verify with a rapid-fire stress test that the single `effectDidSubscribe` stream correctly serves sequential `send()` calls without lost signals.

### E5: `receive()` with no in-flight effects

**Scenario:** `store.receive()` is called when `inFlightEffects` is empty.

**Android behaviour:** All `receive()` variants check `self.reducer.inFlightEffects.isEmpty` first (e.g., line 1430). If empty, they call the synchronous `_receive()` directly without waiting. This path is **identical on both platforms**.

**Risk:** NONE.

### E6: Non-exhaustive test store

**Scenario:** `store.exhaustivity = .off` — skipped assertions, auto-cleared received actions.

**Android behaviour:** The exhaustivity logic is entirely platform-agnostic. The `skipReceivedActions()` and `skipInFlightEffects()` methods (lines 2395, 2484) have no Android guards. They call `Task.megaYield()` and then manipulate `receivedActions`/`inFlightEffects` directly.

**Risk:** NONE.

### E7: `Task.megaYield()` behaviour differences

**Scenario:** `Task.megaYield()` is called extensively throughout TestStore (12 call sites).

**Android behaviour:** `megaYield()` (from `ConcurrencyExtras`) performs multiple cooperative scheduling yields. On Android, the Swift concurrency runtime may have different scheduling characteristics than on Apple platforms (different thread pool size, different priority handling).

**Risk:** LOW-MEDIUM. The `megaYield(count: 20)` at line 1049 provides a generous buffer after state assertion. If the Android runtime requires more yields for effects to propagate, this count may need to be increased. This is a **tuning parameter**, not a correctness issue.

---

## Recommendations

### R1: TestStore is ready for Android integration testing

The `effectDidSubscribe` mechanism is well-designed and already tested by 10+ parity tests. The five `#if !os(Android)` guards are all correct and necessary. No code changes are needed in TestStore for Phase 7.

### R2: Test all effect types with generous timeouts

Per Decision D9 from 07-CONTEXT.md, every effect type needs its own integration test. The existing `AndroidParityTests` already cover most effect types. Remaining gaps:

| Effect Type | Existing Test | Gap |
|---|---|---|
| `.run` | `testEffectRunDeliversValues` | None |
| `.merge` | `testMergeEffectDeliversAllValues`, `testMergeEffectWithRunAndSend` | None |
| `.concatenate` | `testConcatenateDeliversSequentially` | None |
| `.cancellable` | `testEffectCancellation` | None |
| `.cancel` | `testEffectCancellation` | None |
| `.send` | `testEffectSendDeliversAction` | None |
| Chained effects (effect -> action -> effect) | `testTestStoreSendReceive` (one level) | **Need multi-level chain test** |
| `cancelInFlight: true` | None | **Need test** |
| Long-running + finish() | None | **Need test** |
| Non-exhaustive receive | None | **Need test** |

### R3: Set `store.timeout` higher for Android emulator tests

The default timeout is 1 second (`1 * 1_000_000_000` nanoseconds, line 556). On Android emulators, which run in a VM, this may be too tight for effects that involve multiple `Task.megaYield()` round-trips. Recommend setting `store.timeout = 5 * 1_000_000_000` for emulator tests.

### R4: `bindings()` API needs alternative test approach

The `store.bindings(action:)` API is unavailable on Android. Tests that verify binding view state should use `store.send(.binding(.set(\.field, value)))` instead, which is already the pattern in `AndroidParityTests.testBindingReducerMutatesState`.

### R5: Stress test the `effectDidSubscribe` stream

Edge case E4 identifies a theoretical risk with the single `AsyncStream` serving sequential `send()` calls. A stress test should:
1. Send 100+ actions in sequence, each producing a `.run` effect
2. Verify all effects complete and all received actions are accounted for
3. Run on both macOS and Android emulator

### R6: No changes needed to the `effectDidSubscribe` mechanism

The mechanism is sound. It correctly handles:
- `.none` effects (immediate yield)
- `.publisher`/`.run` effects (deferred yield after subscription)
- Cancellation (yield still fires, harmlessly)
- Sequential `send()` calls (each consumes exactly one yield)

The only consideration is timing sensitivity on Android, which is addressed by timeout tuning (R3).
