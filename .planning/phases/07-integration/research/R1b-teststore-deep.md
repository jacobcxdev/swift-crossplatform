# R1b: TestStore `effectDidSubscribe` Deep Dive

**Created:** 2026-02-22
**Scope:** Exhaustive trace of every Android divergence in TestStore.swift, the effectDidSubscribe AsyncStream lifecycle, and gap analysis for Phase 7 test coverage.

---

## Summary

TestStore.swift contains **6 platform-conditional blocks** (5 using `#if !os(Android)` and 1 using `#if canImport(SwiftUI) && !os(Android)`). The core synchronisation divergence is that Apple uses `uncheckedUseMainSerialExecutor` (a global flag that serialises all async work onto the main thread) while Android uses an `effectDidSubscribe` AsyncStream as a rendezvous signal. This deep dive traces every code path, identifies 4 confirmed coverage gaps, and documents 5 additional edge cases that have not been considered in any prior research.

---

## 1. Complete Platform Guard Map

### Guard 1: `useMainSerialExecutor` property (line 477–483)

```swift
// TestStore.swift:477-483
#if !os(Android)
public var useMainSerialExecutor: Bool {
  get { uncheckedUseMainSerialExecutor }
  set { uncheckedUseMainSerialExecutor = newValue }
}
private let originalUseMainSerialExecutor = uncheckedUseMainSerialExecutor
#endif
```

**Apple:** Exposes a public property backed by the global `uncheckedUseMainSerialExecutor` from swift-concurrency-extras. This flag forces ALL Swift concurrency tasks to execute on the main serial executor, providing deterministic ordering.

**Android:** Property and backing store are entirely absent. No equivalent serialisation mechanism exists. The `uncheckedUseMainSerialExecutor` global does not exist in the Android runtime.

**Impact:** On Android, concurrent tasks genuinely execute concurrently. Effect ordering is non-deterministic for effects that are truly concurrent (e.g., `.merge` of two `.run` effects).

### Guard 2: init() sets useMainSerialExecutor (line 558–560)

```swift
// TestStore.swift:558-560
#if !os(Android)
self.useMainSerialExecutor = true
#endif
```

**Apple:** Every TestStore automatically enables main serial executor on init, making all tests deterministic by default.

**Android:** No equivalent. Tests rely entirely on the `effectDidSubscribe` stream for synchronisation.

**Impact:** On Android, the TestStore init does nothing special for concurrency. All synchronisation is deferred to the send/receive cycle.

### Guard 3: deinit restores original executor state (line 654–656)

```swift
// TestStore.swift:654-656
#if !os(Android)
uncheckedUseMainSerialExecutor = self.originalUseMainSerialExecutor
#endif
```

**Apple:** On TestStore deallocation, restores the previous value of `uncheckedUseMainSerialExecutor` (usually `false`), preventing test pollution between test methods.

**Android:** No-op. Nothing to restore.

**Impact:** No functional impact on Android — there's no global state to clean up.

### Guard 4: send() synchronisation (line 1006–1018) — THE CRITICAL DIVERGENCE

```swift
// TestStore.swift:1006-1018
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

**Apple (default path):** When `uncheckedUseMainSerialExecutor` is `true` (the default), a single `Task.yield()` is sufficient because all work is serialised — after yielding, the effect has already been subscribed and possibly completed.

**Apple (non-default path):** When `uncheckedUseMainSerialExecutor` is explicitly set to `false`, falls through to the same `effectDidSubscribe` stream mechanism used on Android.

**Android (only path):** Always waits on the `effectDidSubscribe` stream. This stream yields one `Void` value each time the TestReducer processes an action and its effect subscribes (or immediately for `.none` effects).

**Impact:** This is the single most important divergence point. The `Task.yield()` path on Apple is nearly instantaneous and deterministic. The `effectDidSubscribe` stream path on Android requires the effect's publisher to actually subscribe before the stream yields, introducing a real timing dependency.

### Guard 5: deinit calls mainActorNow (line 657)

```swift
// TestStore.swift:657
mainActorNow { self.completed() }
```

This line is NOT guarded, but `mainActorNow` itself may have platform-specific behaviour. The `completed()` method checks for unfinished effects and unhandled actions — this is identical on both platforms.

### Guard 6: bindings() extension (line 2580–2683)

```swift
// TestStore.swift:2580
#if canImport(SwiftUI) && !os(Android)
extension TestStore {
  public func bindings<ViewAction: BindableAction>(
    action toViewAction: CaseKeyPath<Action, ViewAction>
  ) -> BindingViewStore<State> where State == ViewAction.State, Action: CasePathable { ... }
}
// ... also bindings var
#endif
```

**Apple:** Provides `bindings(action:)` and `bindings` property for testing SwiftUI view bindings.

**Android:** Entirely absent. Cannot test binding view state.

**Impact:** Tests that use `store.bindings` will not compile on Android. Any Phase 7 test using bindings must be guarded with `#if canImport(SwiftUI) && !os(Android)`.

---

## 2. TestReducer: The effectDidSubscribe Owner

### Location and structure

```swift
// TestStore.swift:2836-2950
class TestReducer<State: Equatable, Action>: Reducer {
  let base: Reduce<State, Action>
  var dependencies: DependencyValues
  let effectDidSubscribe = AsyncStream.makeStream(of: Void.self)  // line 2839
  var inFlightEffects: Set<LongLivingEffect> = []
  var receivedActions: [(action: Action, state: State)] = []
  var state: State
  weak var store: TestStore<State, Action>?
  // ...
}
```

### Stream creation (line 2839)

```swift
let effectDidSubscribe = AsyncStream.makeStream(of: Void.self)
```

This creates a tuple `(stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation)`. The stream is a **multi-consumer single-producer** channel. However, it is consumed by the TestStore's `send()` method which always does `for await _ in stream { break }` — consuming exactly one value per send.

**Key property:** `AsyncStream.makeStream` creates an unbuffered stream with a default buffering policy of `.unbounded`. This means yields accumulate if not consumed. If `effectDidSubscribe.continuation.yield()` is called before `send()` starts iterating the stream, the yield is buffered and `send()` will return immediately when it begins iterating.

### Yield points in reduce() (lines 2878–2912)

The `reduce(into:state:action:)` method has TWO yield points:

#### Yield Point A: .none effects (line 2880)

```swift
case .none:
  self.effectDidSubscribe.continuation.yield()
  return .none
```

When the reducer returns `.none` (no effect), the continuation yields **synchronously and immediately**. The `send()` method waiting on the stream will receive this yield and proceed.

**Timing:** This is always deterministic. The yield happens inline during `store.send()` → `self.store.send()` → `reducer.reduce()` → yield. By the time `send()` reaches the `for await` loop, the value is already buffered.

#### Yield Point B: .publisher/.run effects (lines 2883–2912)

```swift
case .publisher, .run:
  let effect = LongLivingEffect(action: action)
  return .publisher { [effectDidSubscribe, weak self] in
    _EffectPublisher(effects)
      .handleEvents(
        receiveSubscription: { _ in
          self?.inFlightEffects.insert(effect)
          Task {
            await Task.megaYield()  // line 2891
            effectDidSubscribe.continuation.yield()  // line 2892
          }
        },
        receiveCompletion: { [weak self] _ in
          self?.inFlightEffects.remove(effect)
        },
        receiveCancel: { [weak self] in
          self?.inFlightEffects.remove(effect)
        }
      )
      .map { /* wrap in TestAction */ }
  }
```

**Critical sequence:**
1. The TestReducer wraps the original effect in a new `.publisher` effect
2. When the Store subscribes to this publisher, `receiveSubscription` fires
3. Inside `receiveSubscription`, a new `Task` is spawned
4. That Task calls `await Task.megaYield()` (which yields to the scheduler multiple times)
5. Only AFTER megaYield completes does `effectDidSubscribe.continuation.yield()` fire
6. The `send()` method, waiting on the stream, receives this yield and proceeds

**Why the Task + megaYield?** The `receiveSubscription` callback runs synchronously during publisher subscription. The actual effect hasn't started executing yet — it will start after the subscription call returns. The `Task { megaYield; yield }` pattern defers the signal to give the effect's internal task time to start.

### End-to-end flow for send()

1. `TestStore.send(.someAction)` is called
2. `self.store.send(TestAction(origin: .send(.someAction), ...))` dispatches to `RootCore._send()`
3. `RootCore._send()` calls `TestReducer.reduce(into:action:)` with `.send(.someAction)`
4. TestReducer calls `self.base.reduce()` (the user's reducer), gets an `Effect`
5. TestReducer switches on the effect's `.operation`:
   - `.none` → yields to effectDidSubscribe immediately, returns `.none`
   - `.publisher`/`.run` → wraps in instrumented publisher, returns it
6. Back in `RootCore._send()`, the effect is subscribed (via `.sink()` or `.run` Task)
7. Subscription triggers `receiveSubscription` → Task → megaYield → effectDidSubscribe yield
8. Meanwhile, `TestStore.send()` is `await`ing on `for await _ in effectDidSubscribe.stream { break }`
9. When the yield arrives, `send()` proceeds to state comparison and assertion

### What happens after send() resumes

```swift
// TestStore.swift:1047-1050
// NB: Give concurrency runtime more time to kick off effects so users don't need to manually
//     instrument their effects.
await Task.megaYield(count: 20)
return .init(rawValue: task.rawValue, timeout: self.timeout)
```

After state assertion, `send()` calls `Task.megaYield(count: 20)` — 20 consecutive yields to the scheduler. This gives effects time to execute and send actions back into the system. This is identical on both platforms.

---

## 3. The 4 Confirmed Coverage Gaps

### Gap 1: Chained Effects

**Scenario:** Action A → Effect sends Action B → Effect sends Action C.

**Apple path:** With `useMainSerialExecutor`, the chain executes deterministically:
1. `send(.a)` → reducer returns effect
2. `Task.yield()` — effect runs, sends `.b` back
3. `.b` is processed, effect sends `.c`
4. All actions appear in `receivedActions` in order

**Android path:** With `effectDidSubscribe`:
1. `send(.a)` → reducer returns effect → `effectDidSubscribe.yield()` after subscription
2. `send()` resumes after one yield — but the effect may not have executed yet
3. `Task.megaYield(count: 20)` gives time, but is that enough for a 2-level chain?
4. If `.b`'s effect hasn't subscribed by the time `receive(.b)` is called, `receiveAction(matching:timeout:)` enters its polling loop

**Risk:** The polling loop in `receiveAction(matching:timeout:)` (line 2200-2264) uses:
```swift
await Task.detached(priority: .background) { await Task.yield() }.value
```
This creates a detached background task just to yield, which is a relatively slow operation. On a slow Android emulator, this could hit the default 1-second timeout before the chain completes.

**Test needed:** A 3-level chain: `.start` → effect sends `.step1` → effect sends `.step2` → effect sends `.step3`. Assert all three are received in order.

### Gap 2: cancelInFlight with Rapid Re-sends

**Scenario:** Same cancellable effect sent twice in rapid succession.

**Apple path:** With serialised execution:
1. `send(.search("a"))` → effect starts, `cancelInFlight` doesn't cancel anything
2. `send(.search("ab"))` → `cancelInFlight` cancels first effect, starts new one
3. All synchronous — ordering is deterministic

**Android path:** Without serialised execution:
1. `send(.search("a"))` → waits for `effectDidSubscribe` yield
2. But `effectDidSubscribe` yield comes from the subscription handler in a Task
3. Between the subscription and the yield, `send(.search("ab"))` is called
4. The second send also waits on `effectDidSubscribe.stream`
5. But the stream is shared — what if the first yield is consumed by the second send?

**Detailed trace of the race condition:**

The `effectDidSubscribe` stream has `.unbounded` buffering. Yields accumulate. Each `send()` does `for await _ in stream { break }` consuming exactly ONE value. So:

1. First send: dispatches to store, reducer returns effect
2. Effect subscribes → Task { megaYield; yield } (call this Yield-1)
3. First send: `for await _ in stream { break }` — waits for Yield-1
4. Yield-1 arrives → first send resumes, does state assertion, calls megaYield(count:20)
5. Second send: dispatches to store, but `cancelInFlight` cancels first effect
6. Cancellation fires `receiveCancel` handler, removing from `inFlightEffects`
7. New effect subscribes → Task { megaYield; yield } (Yield-2)
8. Second send: `for await _ in stream { break }` — waits for Yield-2
9. Yield-2 arrives → second send resumes

**The race:** If step 4's `megaYield(count: 20)` doesn't complete before step 5, things still work because sends are sequential from the test's perspective (`await store.send()` must complete before the next `await store.send()` starts). The real risk is if the cancellation handler fires its own yield somehow. Reviewing the code: cancellation does NOT yield to `effectDidSubscribe`. Only `receiveSubscription` yields. So this should be safe.

**However:** What about the `inFlightEffects` tracking? When cancellation removes an effect from `inFlightEffects`, `finish()` won't wait for it. But the new effect is added. The `receiveCancel` handler:
```swift
receiveCancel: { [weak self] in
  self?.inFlightEffects.remove(effect)
}
```
This runs on the publisher's cancellation chain, which is synchronous. The new effect's `receiveSubscription` hasn't fired yet. So there's a brief window where `inFlightEffects` has ZERO effects between cancel and new subscribe. If `finish()` is called during this window, it would think everything is done.

**Test needed:** Rapid cancel-and-replace, then verify the replacement effect completes.

### Gap 3: Long-running Effect + finish() Timeout

**Scenario:** An effect uses `Task.sleep` or a `TestClock`, and `finish()` is called.

**Apple path:** `finish()` (line 604-651) does:
```swift
await Task.megaYield()
while !self.reducer.inFlightEffects.isEmpty {
  guard start.distance(to: DispatchTime.now().uptimeNanoseconds) < nanoseconds
  else { /* timeout error */ return }
  await Task.yield()
}
```
With `useMainSerialExecutor`, each `Task.yield()` processes the next queued work item. The effect completes when the clock advances.

**Android path:** Same `finish()` code, but `Task.yield()` doesn't guarantee anything about what runs next. On Android, yielding just gives up the current timeslice. The effect's Task might not get scheduled for several milliseconds. On a slow emulator, the polling could timeout.

**Risk factor:** The default timeout is 1 second (`1_000_000_000` nanoseconds, line 556). On an Android emulator, a `TestClock.advance()` followed by `store.finish()` might race because the clock advancement's effect needs multiple scheduling rounds to propagate.

**Test needed:** Effect that completes asynchronously after a TestClock advance, followed by `store.finish()` with a reasonable timeout.

### Gap 4: Non-exhaustive receive with .off

**Scenario:** `store.exhaustivity = .off`, then use `store.receive(...)`.

**Code path analysis for receive():**

All `receive()` overloads follow the same pattern (e.g., line 1420-1464):
```swift
public func receive(_ expectedAction: Action, timeout nanoseconds: UInt64? = ..., ...) async {
  await _withIssueContext(...) {
    guard !self.reducer.inFlightEffects.isEmpty
    else {
      // No in-flight effects — try to match from receivedActions immediately
      _ = { self._receive(expectedAction, ...) }()
      return
    }
    // Wait for action to arrive
    await self.receiveAction(matching: { expectedAction == $0 }, timeout: nanoseconds, ...)
    _ = { self._receive(expectedAction, ...) }()
    await Task.megaYield()
  }
}
```

The `receiveAction(matching:timeout:)` polling loop (line 2200-2264):
```swift
while !Task.isCancelled {
  await Task.detached(priority: .background) { await Task.yield() }.value

  switch self.exhaustivity {
  case .on:
    guard self.reducer.receivedActions.isEmpty else { return }  // ANY action triggers return
  case .off:
    guard !self.reducer.receivedActions.contains(where: { predicate($0.action) }) else { return }  // MATCHING action triggers return
  }
  // ... timeout check
}
```

**Key difference with `.off`:** In non-exhaustive mode, the loop doesn't return on ANY received action — it returns only when a MATCHING action is found. This means if multiple effects fire sending different actions, the loop keeps polling until the specific expected action appears.

**Android risk:** The `Task.detached(priority: .background) { await Task.yield() }.value` pattern is slow. Each iteration creates a new detached task and waits for it. On Android without serialised execution, this could take milliseconds per iteration. If many non-matching actions arrive before the matching one, the cumulative delay could approach the timeout.

**Additionally:** The `skipReceivedActions` path in `send()` (line 988-992):
```swift
case .off(showSkippedAssertions: true):
  await self.skipReceivedActions(strict: false)
case .off(showSkippedAssertions: false):
  self.reducer.receivedActions = []
```

When `showSkippedAssertions: false`, pending received actions are silently discarded. When `true`, they're logged but still cleared. This is identical on both platforms, but interacts with the timing: if Android effects are still in flight when `send()` clears received actions, those actions might arrive after clearing, causing them to accumulate again.

**Test needed:** Non-exhaustive TestStore, send action that produces multiple effects, receive only one specific action, verify others are properly skipped.

---

## 4. Additional Edge Cases

### Edge Case A: TestStore.send() from within an Effect's Closure

This is architecturally impossible in TCA. Effects return actions via `Send`, which calls `self?.send(effectAction)` on the Store (via `RootCore`). This feeds back into the reducer, which processes the action and produces new effects. The TestReducer wraps this by receiving the action as `.receive(action)` (line 2873-2875):

```swift
case .receive(let action):
  effects = reducer.reduce(into: &state, action: action)
  self.receivedActions.append((action, state))
```

The received action's effects are also wrapped and instrumented. Each new effect subscription yields to `effectDidSubscribe`. However, the `TestStore.send()` method's `for await` loop only consumes ONE yield, so these secondary yields accumulate in the buffer.

**On Android:** The buffer grows with each chained effect. This is fine because each subsequent `receive()` call triggers the polling loop which checks `receivedActions` — it doesn't consume from `effectDidSubscribe`. Only `send()` consumes from the stream.

**Potential issue:** If a very deep chain produces many buffered yields, the next `send()` call will immediately consume the first buffered yield rather than the one from its own effect. This could cause `send()` to resume BEFORE its effect has actually subscribed.

**Severity:** LOW for shallow chains (1-2 levels). MODERATE for chains deeper than 3. The `Task.megaYield(count: 20)` after send provides a safety buffer.

### Edge Case B: `store.withExhaustivity(.off) { }` Scoped Blocks

```swift
// TestStore.swift:815-850
public func withExhaustivity<R>(
  _ exhaustivity: Exhaustivity,
  operation: () throws -> R
) rethrows -> R {
  let previous = self.exhaustivity
  defer { self.exhaustivity = previous }
  self.exhaustivity = exhaustivity
  return try operation()
}
```

This is purely synchronous state mutation — no platform divergence. The exhaustivity is a simple enum stored on TestStore. The scoped block changes it, runs the operation, then restores it.

**Android-specific concern:** If the operation inside `withExhaustivity(.off)` calls `await store.send()`, the send's synchronisation mechanism uses the CURRENT exhaustivity value. Since `withExhaustivity` changes `self.exhaustivity` before the operation runs, the send will see `.off`. This is correct on both platforms.

**No additional test needed** — this is pure synchronous Swift with no platform-specific code paths.

### Edge Case C: `@Dependency(\.dismiss)` inside TestStore

From `TestStore.swift:2857-2864`:
```swift
func reduce(into state: inout State, action: TestAction) -> Effect<TestAction> {
  var dependencies = self.dependencies
  let dismiss = dependencies.dismiss.dismiss
  dependencies.dismiss = DismissEffect { [weak store] in
    store?.withExhaustivity(.off) {
      dismiss?()
      store?._skipInFlightEffects(strict: false)
      store?.isDismissed = true
    }
  }
  // ...
}
```

TestReducer overrides the `dismiss` dependency to:
1. Call the original dismiss closure
2. Skip all in-flight effects (non-strict)
3. Mark the store as dismissed

From `Dismiss.swift:90-119`, the `callAsFunction()` has a platform guard:
```swift
#if canImport(SwiftUI) && !os(Android)
await self.callAsFunction(animation: nil, ...)
#else
guard let dismiss = self.dismiss else { /* report issue */ return }
dismiss()
#endif
```

**Android difference:** No animation/transaction wrapping. The dismiss closure is called directly. Inside TestStore, the closure is the custom one from TestReducer (above), so the actual DismissEffect's platform branch is irrelevant — TestReducer replaces it.

**However:** If a test creates a TestStore and the reducer uses `@Dependency(\.dismiss)`, and the effect calls `await self.dismiss()`, on Android the dismiss returns synchronously (no `withTransaction`). The TestReducer's custom closure calls `_skipInFlightEffects(strict: false)`, which directly clears `inFlightEffects` to `[]` (line 2545).

**Risk:** If there are in-flight effects when dismiss is called, they're removed from tracking but NOT cancelled. Their underlying Tasks continue running. If those effects send actions later, the `receivedActions` array accumulates, and `completed()` in deinit will report unexpected actions.

**Test needed:** Reducer that starts a long-running effect, then dismisses. Verify no spurious failures.

### Edge Case D: StackState/StackAction with TestStore

TestStore.swift has NO direct references to `StackState` or `StackAction`. Navigation stack testing works through the standard TestStore API because `StackReducer` is just a regular reducer that manages an `IdentifiedArray` of child states internally.

**Android concern:** `StackReducer` (in `StackReducer.swift`) uses `navigationIDPath` dependencies for cancellation scoping. Each pushed child gets a unique navigation ID. When a child is popped, effects scoped to that navigation ID are cancelled via `_cancellationCancellables`.

The cancellation mechanism (`Cancellation.swift:313-320`) is platform-independent:
```swift
func cancel(id: some Hashable, path: NavigationIDPath) {
  let cancelID = _CancelID(id: id, navigationIDPath: path)
  self.storage[cancelID]?.forEach { $0.cancel() }
  self.storage[cancelID] = nil
}
```

**No Android-specific code** in StackReducer or its cancellation. But the timing of cancellation effects through `effectDidSubscribe` means that on Android, a pop that cancels multiple child effects could cause multiple `receiveCancel` handlers to fire asynchronously, briefly reducing `inFlightEffects` count in unpredictable order.

**Test needed (low priority):** Push 2 children, pop both, verify effects are properly cancelled without timeout.

### Edge Case E: Store.send() Re-entrancy and BufferedActions

From `Core.swift:88-107`, `RootCore._send()` has a crucial re-entrancy guard:

```swift
private func _send(_ action: Root.Action) -> Task<Void, Never>? {
  self.bufferedActions.append(action)
  guard !self.isSending else { return nil }

  self.isSending = true
  // ... process all buffered actions ...
  defer {
    // ... if new actions were buffered during processing, send the last one
    if !self.bufferedActions.isEmpty {
      if let task = self.send(self.bufferedActions.removeLast()) {
        tasks.withValue { $0.append(task) }
      }
    }
  }
}
```

**Critical detail:** When a publisher-based effect's `receiveValue` callback fires (line 133-139 of Core.swift):
```swift
receiveValue: { [weak self] effectAction in
  guard let self else { return }
  if let task = continuation.yield({
    self.send(effectAction)  // RE-ENTRANT CALL
  }) {
    tasks.withValue { $0.append(task) }
  }
}
```

This calls `self.send(effectAction)` which is a re-entrant call. If `isSending` is still `true`, the action is buffered. The current send loop processes it in the defer block.

**Android impact:** Publisher-based effects (`.send()`, `.publisher {}`) use `receive(on: UIScheduler.shared)` (line 125 of Core.swift). The `UIScheduler` is the Combine equivalent of MainActor scheduling. On Android, `UIScheduler.shared` schedules onto the main run loop. If the main run loop isn't spinning (e.g., in a test without a UI), this could delay delivery.

For `.run` effects, the closure runs in a `Task { @MainActor in ... }`, so the Send closure calls `self?.send(effectAction)` which IS re-entrant (same MainActor context).

**No additional test needed** — this re-entrancy is the same on both platforms. The UIScheduler concern applies only to publisher-based effects in tests, which typically use `.send()` (synchronous publisher) rather than `.publisher {}`.

---

## 5. Comprehensive Android Guard Inventory (All of TCA)

Beyond TestStore.swift, the full inventory of `#if !os(Android)` / `#if os(Android)` guards across TCA:

| File | Line | Guard | Purpose |
|------|------|-------|---------|
| **TestStore.swift** | 477 | `#if !os(Android)` | `useMainSerialExecutor` property |
| **TestStore.swift** | 558 | `#if !os(Android)` | init sets executor |
| **TestStore.swift** | 654 | `#if !os(Android)` | deinit restores executor |
| **TestStore.swift** | 1006 | `#if !os(Android)` | send() sync mechanism |
| **TestStore.swift** | 2580 | `#if canImport(SwiftUI) && !os(Android)` | bindings() extensions |
| **Core.swift** | 14 | `#if !canImport(SwiftUI) \|\| os(Android)` | Standalone `BindingLocal` |
| **Store.swift** | 7 | `#if os(Android)` | `import SkipAndroidBridge` |
| **Store.swift** | 119 | `#if !os(visionOS) && !os(Android)` | Perception registrar |
| **Store.swift** | 205 | `#if canImport(SwiftUI) && !os(Android)` | animation/transaction send |
| **Effect.swift** | 161 | `#if canImport(SwiftUI) && !os(Android)` | `send(_:animation:)` |
| **Effect.swift** | 215 | `#if canImport(SwiftUI) && !os(Android)` | `send(_:transaction:)` |
| **Dismiss.swift** | 90 | `#if canImport(SwiftUI) && !os(Android)` | Dismiss with animation |
| **Dismiss.swift** | 122 | `#if canImport(SwiftUI) && !os(Android)` | Dismiss callAsFunction(animation:) |
| **Binding+Observation.swift** | 14, 47, 290, 373 | `#if !os(Android)` | Various binding extensions |
| **ObservableState.swift** | 9 | `#if !os(visionOS) && !os(Android)` | Perception tracking |
| **ObservationStateRegistrar.swift** | 1 | `#if os(Android)` | Android-specific registrar path |
| **ViewStore.swift** | 251, 365, 632 | `#if !os(Android)` | Binding, BindingLocal |
| **ViewAction.swift** | 31 | `#if !os(Android)` | ViewAction binding support |
| **Store+Observation.swift** | 8, 197, 317 | `#if !os(visionOS) && !os(Android)` | Perception extensions |
| **IfLetStore.swift** | 54, 145, 240 | `#if !os(Android)` | State restoration modifiers |
| **NavigationStackStore.swift** | 104 | `#if !os(Android)` | NavigationLink support |
| **NavigationStack+Observation.swift** | 74, 111 | `#if !os(Android)` | Observation navigation |
| **Alert.swift** | 91 | `#if !os(Android)` | Alert tint colour |
| **ConfirmationDialog.swift** | 96 | `#if !os(Android)` | Dialog tint colour |
| **Popover.swift** | 4 | `#if !os(Android)` | Entire file |
| **SwitchStore.swift** | 1 | `#if canImport(SwiftUI) && !os(Android)` | Entire file |
| **Binding.swift** | 303, 340 | `#if !os(Android)` | SwiftUI Binding extensions |
| **Exports.swift** | 14 | `#if !os(Android)` | Re-export of Perception |
| **ObservedObjectShim.swift** | 6 | `#if os(Android)` | Shim for ObservedObject |
| **Deprecated/ files** | 1 | `#if canImport(SwiftUI) && !os(Android)` | Deprecated SwiftUI types |

---

## 6. receive() Polling Mechanics on Android

The `receiveAction(matching:timeout:)` method (line 2200-2264) is the heart of how `receive()` waits for effect actions on Android:

```swift
private func receiveAction(
  matching predicate: (Action) -> Bool,
  timeout nanoseconds: UInt64?,
  ...
) async {
  let nanoseconds = nanoseconds ?? self.timeout

  await Task.megaYield()
  let start = DispatchTime.now().uptimeNanoseconds
  while !Task.isCancelled {
    await Task.detached(priority: .background) { await Task.yield() }.value

    switch self.exhaustivity {
    case .on:
      guard self.reducer.receivedActions.isEmpty else { return }
    case .off:
      guard !self.reducer.receivedActions.contains(where: { predicate($0.action) }) else { return }
    }

    guard start.distance(to: DispatchTime.now().uptimeNanoseconds) < nanoseconds
    else { /* timeout */ return }
  }
}
```

**Important:** This method does NOT consume from `effectDidSubscribe`. It polls `receivedActions` in a busy-wait loop. Each iteration:

1. Creates a detached background-priority Task
2. That task yields once
3. Awaits the task's completion
4. Checks if any received actions match the predicate
5. Checks timeout

**On Apple with MainSerialExecutor:** Each `Task.yield()` is a cooperative yield on the single serial executor. Work progresses deterministically. The detached task's yield processes the next unit of work, which might be the effect sending its action.

**On Android without MainSerialExecutor:** The detached background-priority Task may not get scheduled immediately. The main actor might be idle between iterations. The effect's action delivery depends on:
- For `.run` effects: The Task running the effect's closure, which is on `@MainActor`. It needs to be scheduled.
- For `.publisher` effects: The publisher's sink, which uses `receive(on: UIScheduler.shared)`.

**Worst case timing:** On an Android emulator with limited CPU, each polling iteration could take 10-50ms. With a 1-second timeout, that's 20-100 iterations. For effects that complete within one scheduling round, this is sufficient. For effects that require multiple scheduling rounds (e.g., TestClock → sleep → advance → wake → send), the margin is tighter.

---

## 7. finish() Mechanics on Android

```swift
// TestStore.swift:611-651
public func finish(timeout nanoseconds: UInt64? = nil, ...) async {
  self.assertNoReceivedActions(...)
  Task.cancel(id: OnFirstAppearID())
  let nanoseconds = nanoseconds ?? self.timeout
  let start = DispatchTime.now().uptimeNanoseconds
  await Task.megaYield()
  while !self.reducer.inFlightEffects.isEmpty {
    guard start.distance(to: DispatchTime.now().uptimeNanoseconds) < nanoseconds
    else { /* timeout error */ return }
    await Task.yield()
  }
  self.assertNoSharedChanges(...)
}
```

Same busy-wait pattern as `receiveAction`. On Android, `Task.yield()` gives up the current timeslice but doesn't guarantee that the in-flight effect's completion handler runs before the next check.

**Key interaction:** When an effect completes, `receiveCompletion` fires:
```swift
receiveCompletion: { [weak self] _ in
  self?.inFlightEffects.remove(effect)
}
```
This removes from `inFlightEffects`. But this handler runs on whatever scheduler the publisher uses. For the TestReducer's wrapped publisher, there's no explicit scheduler — it inherits from the upstream. The upstream (`_EffectPublisher`) for `.run` effects completes with `subscriber.send(completion: .finished)` on `@MainActor`.

**Android risk:** The completion handler is synchronous on the subscriber's thread. Since `.run` effects complete on `@MainActor`, the `inFlightEffects.remove()` also runs on MainActor. The `finish()` loop's `Task.yield()` should allow this to interleave correctly, since both are on MainActor.

**Verdict:** `finish()` should work correctly on Android for typical effects. The risk is primarily with very slow effects that don't complete within the timeout window.

---

## 8. Recommended Tests for Phase 7

### Priority 1 (Must have)

| Test | Description | Gap |
|------|-------------|-----|
| `testChainedEffects` | Action → Effect → Action → Effect → Action. Assert all received in order. | Gap 1 |
| `testCancelInFlightReplace` | Send cancellable effect, immediately re-send. Assert only replacement effect completes. | Gap 2 |
| `testFinishWithAsyncEffect` | Effect completes after short async delay. Call `finish()`, assert it succeeds within timeout. | Gap 3 |
| `testNonExhaustiveReceive` | `.off` exhaustivity, multiple effects, receive only specific one. | Gap 4 |

### Priority 2 (Should have)

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testDismissWithInFlightEffect` | Start effect, dismiss feature, verify clean teardown. | Edge Case C |
| `testDeepChain` | 4+ level effect chain, verify all received. | Edge Case A |
| `testConcurrentMergeOrdering` | `.merge` of 3+ `.run` effects, verify all delivered (order may vary). | General |

### Priority 3 (Nice to have)

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testStackPushPopCancellation` | Push/pop children, verify effect cancellation. | Edge Case D |
| `testNonExhaustiveSendClearsActions` | `.off(showSkippedAssertions: false)`, verify actions cleared on next send. | Gap 4 variant |

---

## 9. Key Code References

| Concept | File | Lines |
|---------|------|-------|
| TestStore class declaration | TestStore.swift | 434 |
| useMainSerialExecutor property | TestStore.swift | 477–483 |
| TestStore.init() | TestStore.swift | 533–562 |
| TestStore.finish() | TestStore.swift | 604–651 |
| TestStore.deinit | TestStore.swift | 653–658 |
| TestStore.send() — sync divergence | TestStore.swift | 1006–1018 |
| TestStore.send() — megaYield(count:20) | TestStore.swift | 1049 |
| receiveAction (sync matcher) | TestStore.swift | 2092–2198 |
| receiveAction (async polling) | TestStore.swift | 2200–2264 |
| skipReceivedActions | TestStore.swift | 2395–2456 |
| bindings (Apple-only) | TestStore.swift | 2580–2683 |
| TestReducer class | TestStore.swift | 2836–2950 |
| effectDidSubscribe stream | TestStore.swift | 2839 |
| Yield Point A (.none) | TestStore.swift | 2880 |
| Yield Point B (.publisher/.run) | TestStore.swift | 2885–2893 |
| RootCore._send() | Core.swift | 88–215 |
| RootCore bufferedActions reentrant | Core.swift | 101–107 |
| Effect.cancellable (publisher path) | Cancellation.swift | 36–85 |
| Effect.cancellable (run path) | Cancellation.swift | 86–98 |
| _EffectPublisher | Publisher.swift | 13–45 |
| DismissEffect Android path | Dismiss.swift | 98–119 |
| AndroidParityTests | AndroidParityTests.swift | 1–581 |

---

## 10. Conclusion

The `effectDidSubscribe` mechanism is fundamentally sound for Android. It correctly signals when an effect has subscribed, allowing `send()` to resume. The main risks are:

1. **Timing margins** — Android lacks the deterministic scheduling of `useMainSerialExecutor`, so multi-step chains and rapid cancel-replace patterns have wider timing windows.
2. **Buffered yield accumulation** — Deep effect chains buffer yields in the `effectDidSubscribe` stream, potentially causing the next `send()` to resume prematurely. The `megaYield(count: 20)` mitigates but doesn't eliminate this.
3. **Polling-based receive** — The `receiveAction` polling loop is inherently non-deterministic on Android, relying on `Task.yield()` for progress. Slow emulators may hit timeouts.

All 4 originally identified gaps are confirmed. 5 additional edge cases are documented, 2 of which warrant dedicated tests (dismiss with in-flight effects, deep chains). The remaining 3 are architectural properties that don't need separate testing.
