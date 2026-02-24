# R2: Observation Bridge — Integration Testing Research

**Created:** 2026-02-22
**Scope:** How to test the observation bridge for Phase 7 (TEST-10), covering architecture, diagnostics API, macOS vs Android testability, and recomposition counting.

---

## Summary

The observation bridge in `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` implements a record-replay pattern that captures `@Observable` property accesses during Compose body evaluation and replays them inside `withObservationTracking` to wire up native Swift observation to Compose recomposition. The entire bridge (`Observation.swift` and `ObservationModule.swift`) is gated behind `#if SKIP_BRIDGE`, a flag injected by Skip's `skipstone` build plugin — it is **not** defined in the Package.swift `swiftSettings`. This means on macOS `swift test`, the bridge code does not compile at all. Testing the bridge contract requires either running on Android via `skip test`, or testing the logical equivalent using native `withObservationTracking` on macOS (which the project already does via `ObservationVerifier`).

The bridge has a built-in diagnostics API (`diagnosticsEnabled`, `diagnosticsHandler`) that can count replay closures and measure timing per `stopAndObserve()` call. This is the instrument for programmatic recomposition counting on Android. On macOS, an equivalent mock-bridge approach can simulate the record-replay cycle without JNI.

---

## Bridge Architecture

### Three-file span

| File | Role | Platform Gate |
|------|------|---------------|
| `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` | `ObservationRecording` (record-replay stack) + `BridgeObservationSupport` (JNI calls) + JNI exports | `#if SKIP_BRIDGE` (entire file) |
| `forks/skip-android-bridge/Sources/SkipAndroidBridge/ObservationModule.swift` | Type aliases for `Observable`, `ObservationRegistrar`, `withObservationTracking` | `#if SKIP_BRIDGE` (entire file) |
| `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` | `ViewObservation` Kotlin object with `startRecording`/`stopAndObserve` closures; `Evaluate()` hooks | `#if !SKIP_BRIDGE` (Swift stubs on non-bridge platforms) |
| `forks/skip-ui/Sources/SkipUI/SkipUI/View/ViewModifier.swift` | Same `startRecording`/`stopAndObserve` hooks in `ViewModifier.Evaluate()` | `#if SKIP` (Compose-only) |
| `forks/swift-composable-architecture/.../ObservationStateRegistrar.swift` | TCA's registrar — uses `SkipAndroidBridge.Observation.ObservationRegistrar` on Android | `#if os(Android)` |

### Data flow (Android)

```
View.Evaluate()
  -> ViewObservation.startRecording()     [JNI -> ObservationRecording.startRecording()]
    -> Push new Frame onto thread-local stack
  -> body evaluation
    -> @Observable property access
      -> ObservationRegistrar.access()
        -> ObservationRecording.recordAccess(replay:trigger:)
          -> Append replay closure to current frame
          -> Set trigger closure (first access only per frame)
  -> ViewObservation.stopAndObserve()     [JNI -> ObservationRecording.stopAndObserve()]
    -> Pop frame from stack
    -> withObservationTracking { replay all closures } onChange: { trigger() }
    -> trigger() calls BridgeObservationSupport.triggerSingleUpdate()
      -> Java_update(0) -> MutableStateBacking.update(0)
      -> Compose recomposition of enclosing scope
```

### Key design decisions

1. **Thread-local stack via `pthread_key_t`**: Each thread gets its own recording stack. This handles concurrent Compose recomposition on different threads.

2. **Single trigger closure per frame**: All observables in one view body share a single recomposition trigger (`MutableStateBacking.update(0)`). The bridge does not track per-property recomposition — it's one trigger per view.

3. **`isEnabled` one-way flag**: Set once by `nativeEnable()` at app startup. When false, `BridgeObservationSupport.willSet()` fires directly (original non-bridge behavior). When true, `willSet()` is suppressed and `withObservationTracking` handles recomposition instead.

4. **`isEnabled` suppresses `bridgeSupport.willSet()` in `willSet()` and `withMutation()`**: See lines 37-39 and 48-50. This prevents double-triggering when the record-replay path is active.

---

## Diagnostics API

### Public surface (Observation.swift lines 93-99)

```swift
/// Opt-in diagnostics: logs every record/replay cycle with timing.
public static var diagnosticsEnabled = false

/// Callback for diagnostics consumers. Called on every stopAndObserve()
/// with the number of replayed closures and elapsed time in seconds.
public static var diagnosticsHandler: ((Int, TimeInterval) -> Void)?
```

### How it works

In `stopAndObserve()` (lines 155-168):
1. If `diagnosticsEnabled`, captures `startTime` before replay.
2. Replays closures inside `withObservationTracking`.
3. After replay, computes `elapsed` and calls `diagnosticsHandler?(closures.count, elapsed)`.

### What the handler receives

- **`Int` (closures.count)**: Number of replay closures recorded during body evaluation. This equals the number of distinct `@Observable` property accesses in that view's body. For a view accessing `model.count` and `model.label`, this would be 2.
- **`TimeInterval` (elapsed)**: Wall-clock time for the `withObservationTracking` replay, in seconds.

### Per-view tracking capability

The diagnostics handler fires once per `stopAndObserve()` call, which maps 1:1 to a view body evaluation. By setting a handler that accumulates results, you can count:
- Total recomposition events (handler call count)
- Per-view property access counts (closures.count per call)
- Timing distribution

**Limitation**: The handler does not identify *which* view triggered the call. To track per-view updates, you would need to correlate with the view hierarchy externally (e.g., via a test-specific wrapper).

---

## Testability Matrix

### What compiles and runs on macOS (`swift test`)

| Component | Available | Notes |
|-----------|-----------|-------|
| `ObservationRecording` | NO | Behind `#if SKIP_BRIDGE` |
| `ObservationRecording.diagnosticsEnabled` | NO | Behind `#if SKIP_BRIDGE` |
| `ObservationRecording.diagnosticsHandler` | NO | Behind `#if SKIP_BRIDGE` |
| `ObservationRecording.startRecording()` / `stopAndObserve()` | NO | Behind `#if SKIP_BRIDGE` |
| `BridgeObservationSupport` (JNI) | NO | Behind `#if SKIP_BRIDGE`, requires JNI |
| `Observation.ObservationRegistrar` (bridge) | NO | Behind `#if SKIP_BRIDGE` |
| `ViewObservation` (Swift stubs) | YES | `startRecording = nil`, `stopAndObserve = nil` — closures are nil on non-bridge |
| Native `withObservationTracking` | YES | Swift stdlib, works directly |
| `ObservationVerifier` | YES | Uses native `withObservationTracking` |
| TCA `ObservationStateRegistrar` | YES | Uses `PerceptionRegistrar` on macOS (not Android bridge) |
| TCA `Store`, `TestStore` | YES | Full TCA testing infrastructure |

### What compiles and runs on Android (`skip test`)

| Component | Available | Notes |
|-----------|-----------|-------|
| `ObservationRecording` | YES | `SKIP_BRIDGE` is defined by skipstone plugin |
| `ObservationRecording.diagnosticsEnabled` | YES | Settable from test code |
| `ObservationRecording.diagnosticsHandler` | YES | Receives (closureCount, elapsed) |
| `BridgeObservationSupport` (JNI) | YES | Requires JNI context (emulator) |
| JNI exports (`nativeEnable`, etc.) | YES | Called from Kotlin `ViewObservation` |
| TCA `ObservationStateRegistrar` | YES | Uses `SkipAndroidBridge.Observation.ObservationRegistrar` |
| Compose recomposition | YES | Full Compose runtime on emulator |

### What requires Android emulator specifically (not Robolectric)

- JNI calls to `MutableStateBacking` (Java class in skip-model)
- Actual Compose recomposition triggering
- `BridgeObservationSupport.triggerSingleUpdate()` (needs `isJNIInitialized`)
- Visual rendering verification

---

## macOS vs Android Testing Strategy

### Layer 1: macOS contract tests (already exist)

The `ObservationVerifier` in `examples/fuse-library/Sources/FuseLibrary/ObservationVerifier.swift` already validates the logical observation contract using native `withObservationTracking`:

- Basic property tracking, multi-property, computed property, ignored property
- Nested observables, sequential re-subscription
- Bulk mutation coalescing (single onChange per tracking scope)
- Multi-property single onChange

These 12 verifier methods run on both macOS (`swift test` via `ObservationTrackingTests`) and Android (`skip test` via `ObservationTests`). On Android, they execute as native Swift via JNI, proving the full observation pipeline works.

**Coverage gap**: These tests validate `withObservationTracking` behavior but do NOT test the record-replay bridge (`ObservationRecording`). The bridge's `startRecording` -> `recordAccess` -> `stopAndObserve` cycle is untested in isolation.

### Layer 2: macOS mock-bridge tests (NEW — recommended)

Since `ObservationRecording` is behind `#if SKIP_BRIDGE`, a macOS mock must replicate the record-replay logic. The key insight is that `ObservationRecording` is a pure Swift class with no JNI dependency in its core logic — the JNI is only in `BridgeObservationSupport` and the `@_cdecl` exports. The record-replay stack itself (`startRecording`, `recordAccess`, `stopAndObserve`) uses only:
- `pthread_key_t` (available on macOS)
- `withObservationTracking` (available on macOS via Observation framework)
- `ProcessInfo.processInfo.systemUptime` (available on macOS)
- `DispatchQueue.main.async` (available on macOS)

**Mock approach**: Extract the record-replay contract into a testable protocol or duplicate the core logic without the `#if SKIP_BRIDGE` gate in a test helper. Then test:

```swift
// Pseudo-test: mock bridge recording cycle
func testRecordReplayCycle() {
    // 1. Start recording
    MockObservationRecording.startRecording()

    // 2. Simulate property accesses (what ObservationRegistrar.access() does)
    var replayCount = 0
    var triggerFired = false
    MockObservationRecording.recordAccess(
        replay: { replayCount += 1 },
        trigger: { triggerFired = true }
    )

    // 3. Stop and observe — should replay inside withObservationTracking
    MockObservationRecording.stopAndObserve()

    XCTAssertEqual(replayCount, 1)
    // trigger fires asynchronously via DispatchQueue.main.async
}
```

**Alternative (simpler)**: Since `ObservationRecording` is a self-contained class, add a test-only compilation flag (e.g., `OBSERVATION_RECORDING_TESTABLE`) that includes the class on macOS without the JNI components. This avoids duplicating logic.

### Layer 3: Android diagnostics tests (NEW — recommended)

On Android via `skip test`, use the real diagnostics API:

```swift
func testBridgeDiagnosticsCountsReplay() {
    // Enable diagnostics
    ObservationRecording.diagnosticsEnabled = true
    defer {
        ObservationRecording.diagnosticsEnabled = false
        ObservationRecording.diagnosticsHandler = nil
    }

    var reports: [(Int, TimeInterval)] = []
    ObservationRecording.diagnosticsHandler = { count, elapsed in
        reports.append((count, elapsed))
    }

    // Simulate a view evaluation cycle
    ObservationRecording.startRecording()

    // Access two properties (simulated by calling recordAccess directly
    // or through an @Observable model's registrar)
    let model = SomeObservableModel()
    _ = model.propertyA  // triggers registrar.access -> recordAccess
    _ = model.propertyB  // triggers registrar.access -> recordAccess

    ObservationRecording.stopAndObserve()

    // Diagnostics should report 2 replay closures
    XCTAssertEqual(reports.count, 1)
    XCTAssertEqual(reports[0].0, 2)  // 2 property accesses replayed
    XCTAssertGreaterThan(reports[0].1, 0)  // non-zero elapsed time
}
```

**Important**: This test can only run on Android because `ObservationRecording` requires `#if SKIP_BRIDGE`. The `recordAccess` path is triggered when `isRecording` is true and a property is accessed through the bridge's `ObservationRegistrar`.

### Layer 4: Recomposition counting via diagnostics (Android only)

To count recompositions programmatically (not just replay closures):

```swift
func testSingleRecompositionPerMutation() {
    ObservationRecording.diagnosticsEnabled = true
    var recomposeCount = 0
    ObservationRecording.diagnosticsHandler = { _, _ in
        recomposeCount += 1
    }

    // Set up a view with observation recording
    ObservationRecording.startRecording()
    let model = SomeObservableModel()
    _ = model.count
    ObservationRecording.stopAndObserve()

    // Now mutate — onChange triggers recomposition
    // which calls Evaluate() again -> startRecording/stopAndObserve
    model.count = 42

    // After recomposition settles, diagnosticsHandler should have fired
    // once for the initial setup + once for the recomposition
    // (exact count depends on Compose scheduling)
}
```

**Limitation**: The `diagnosticsHandler` fires during `stopAndObserve()`, which happens during body evaluation (the replay phase). It does NOT fire when the mutation triggers recomposition — it fires when the *next* body evaluation happens after recomposition. So counting handler calls counts re-evaluations, not mutations. This is actually the right metric: one re-evaluation per recomposition boundary.

---

## Recommendations

### R1: Keep macOS tests as contract validation (no change)

The existing `ObservationVerifier` + `ObservationTests` + `ObservationTrackingTests` provide excellent coverage of the observation contract. They run on both platforms. No changes needed.

### R2: Add a macOS-testable mock of ObservationRecording

Create a test helper that replicates `ObservationRecording`'s stack-based record-replay logic without the `#if SKIP_BRIDGE` gate. This allows testing:
- Stack push/pop correctness (startRecording/stopAndObserve)
- Nested recording frames (parent view contains child view)
- Empty frame handling (no accesses recorded)
- Multiple accesses coalesce to single trigger
- Thread-local isolation (different threads don't interfere)

**Implementation**: Copy the core `ObservationRecording` logic into a `MockObservationRecording` class in the test target, removing `#if SKIP_BRIDGE` and replacing `BridgeObservationSupport.triggerSingleUpdate()` with a test-observable closure. Alternatively, use a build flag to conditionally compile the real class.

### R3: Add Android-only diagnostics integration tests

Create tests gated with `#if os(Android)` that:
1. Enable `ObservationRecording.diagnosticsEnabled`
2. Exercise the full pipeline (create `@Observable` model, start recording, access properties, stop and observe)
3. Assert `diagnosticsHandler` receives correct closure counts
4. Verify timing is non-zero and reasonable

These tests validate the bridge end-to-end on the actual runtime.

### R4: Use diagnosticsHandler for stress test observation counting

For TEST-11 (stress testing), the diagnostics handler is the instrument for verifying observation pipeline behavior under load on Android:
- Rapid mutations should not cause unbounded handler calls
- Each `stopAndObserve()` should complete in bounded time
- Memory should not grow unbounded (thread-local stacks are cleaned up)

### R5: Do NOT attempt to test JNI layer on macOS

The JNI calls (`Java_access`, `Java_update`, `Java_initPeer`) require a running JVM with skip-model classes loaded. There is no value in mocking the JNI layer itself — the contract between Swift and Kotlin is best validated on the actual Android runtime. Focus macOS tests on the pure-Swift observation logic.

### R6: Document the two-tier test strategy

Phase 7 bridge tests should be clearly organized:
- **Tier 1 (macOS)**: Contract tests via `ObservationVerifier`, mock record-replay tests
- **Tier 2 (Android)**: Diagnostics API tests, end-to-end recomposition tests, JNI integration

This matches the project's existing pattern where `ObservationTrackingTests` (macOS-only) and `ObservationTests` (cross-platform) coexist.

### R7: Consider extracting ObservationRecording core as a testable module

Long-term, the record-replay logic in `ObservationRecording` (lines 84-186 of Observation.swift) has no inherent JNI dependency. The JNI coupling is in `BridgeObservationSupport` and the `@_cdecl` exports. If the `#if SKIP_BRIDGE` gate were narrowed to only wrap the JNI-dependent code, `ObservationRecording` could be tested directly on macOS. This would require a fork change but would significantly improve testability.

Specifically:
- `ObservationRecording` class: Pure Swift (pthread, withObservationTracking, DispatchQueue) — could compile on macOS
- `BridgeObservationSupport` class: JNI-dependent — must stay behind `#if SKIP_BRIDGE`
- `@_cdecl` JNI exports: JNI-dependent — must stay behind `#if os(Android)`
- `Observation.ObservationRegistrar`: Depends on `BridgeObservationSupport` — must stay behind `#if SKIP_BRIDGE`

The gate restructuring would be:
```swift
#if SKIP_BRIDGE
// BridgeObservationSupport, ObservationRegistrar, etc.
#endif

// ObservationRecording — no gate, compiles everywhere
@available(macOS 14.0, iOS 17.0, ...)
public final class ObservationRecording { ... }

#if os(Android)
// JNI exports
#endif
```

This is a code change recommendation, not a test-only change. Evaluate whether it's worth the fork modification for Phase 7.

---

*Research completed: 2026-02-22*
*Sources: Observation.swift, ObservationModule.swift, View.swift, ViewModifier.swift, ObservationStateRegistrar.swift, ObservationVerifier.swift, ObservationTests.swift, ObservationTrackingTests.swift, skip-android-bridge Package.swift, 07-RESEARCH.md*
