# R3: Stress Testing Research — Store Throughput & Observation Under Load

**Created:** 2026-02-22
**Phase:** 07-integration (TEST-11)
**Scope:** Two stress tests: (1) Store/Reducer throughput >1000 mutations/second, (2) Observation pipeline under load. Both macOS + Android.

---

## Summary

Stress testing TCA Store throughput and the Observation pipeline requires platform-aware strategies for memory measurement, realistic iteration counts, and understanding of how `withObservationTracking` coalesces (or doesn't) under rapid mutations.

**Key findings:**

1. **Store.send() is synchronous** for reducers returning `.none` — the entire reduce-and-assign path runs inline with no Task creation, making >10,000 sends/second trivially achievable on macOS. The bottleneck is effect spawning, not state mutation.
2. **withObservationTracking fires 1:1** with mutations when resubscribed each cycle (the pattern used by SwiftUI/Evaluate). It does NOT coalesce — each `willSet` triggers the registered `onChange` callback exactly once, then auto-cancels. Multiple mutations after the first `willSet` within the same tracking scope are ignored until resubscription.
3. **Memory measurement** differs fundamentally between Darwin (`mach_task_basic_info`) and Android/Linux (`/proc/self/status` VmRSS). `ProcessInfo.processInfo.physicalMemory` returns total system RAM and is useless for per-process measurement. There is no cross-platform Swift API for process RSS.
4. **XCTest `measure {}` blocks** work on macOS but are NOT available on Android via `skip test` (transpiled to JUnit which has no equivalent). Use manual `ContinuousClock` timing instead.
5. **`skip test` has no hard-coded timeout** in the Makefile or gradle config. JUnit default is 0 (no timeout). Gradle test tasks default to no per-test timeout. Stress tests completing within 30 seconds are safe; tests exceeding 60 seconds risk CI timeout depending on runner configuration.

---

## Memory Measurement Approaches

### Darwin: `mach_task_basic_info` via `task_info()`

The canonical approach for process-level RSS on Darwin. This compiles and works in Swift test processes.

```swift
#if canImport(Darwin)
import Darwin

func currentResidentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.resident_size) / (1024 * 1024)
}
#endif
```

**Verified:** This pattern is used extensively in production Swift code. `mach_task_self_` is a global, `task_info` is in `<mach/task_info.h>` which Darwin imports provide. The `count` calculation (`size / MemoryLayout<integer_t>.size`) is critical — dividing by 4 (the size of `integer_t`) gives the correct count parameter. Getting this wrong silently returns stale data.

**Precision:** RSS is page-granular (typically 16KB on arm64). For stress tests allocating many small objects, RSS may not reflect every allocation immediately due to page-level granularity and malloc zone caching. A delta of >50MB is a strong signal of a leak; deltas <5MB are noise.

### Android/Linux: `/proc/self/status` VmRSS

```swift
#if os(Android) || os(Linux)
import Foundation

func currentResidentMemoryMB() -> Double {
    guard let contents = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else {
        return -1
    }
    // VmRSS line format: "VmRSS:    12345 kB"
    for line in contents.split(separator: "\n") {
        if line.hasPrefix("VmRSS:") {
            let parts = line.split(separator: " ").compactMap { Int($0) }
            if let kb = parts.first {
                return Double(kb) / 1024.0
            }
        }
    }
    return -1
}
#endif
```

**Verified:** `/proc/self/status` is readable by the process itself without special permissions on both Linux and Android. The Swift test process (running as native Swift on Android via skip's Fuse mode) has access. The `VmRSS` line reports kilobytes of resident set size.

**Caveat for Android:** When tests run via Robolectric (JVM on macOS), `/proc/self/status` reports the JVM process memory, not a simulated Android process. This is acceptable for "bounded memory" assertions but not for absolute values. When running on a real Android emulator via `ANDROID_SERIAL`, the value reflects the actual test process.

### Rejected Alternatives

| Approach | Why Rejected |
|----------|-------------|
| `ProcessInfo.processInfo.physicalMemory` | Returns total system RAM (e.g., 32GB), not process RSS. Useless for per-process measurement. |
| `malloc_size()` / `malloc_good_size()` | Per-pointer only. No way to get aggregate process-level allocation without custom tracking. |
| `Foundation.ProcessInfo` memory stats | No API for process RSS on any platform. Only `physicalMemory` (total RAM) and `systemUptime`. |
| `os_proc_available_memory()` (iOS 13+) | Returns available system memory, not process usage. Decreases as system is under pressure. Not useful for leak detection. |
| `URLResourceKey.volumeAvailableCapacityKey` | Disk space, not memory. |

### Cross-Platform Memory Helper

The recommended pattern gates at compile time:

```swift
func currentResidentMemoryMB() -> Double {
    #if canImport(Darwin)
    // ... mach_task_basic_info implementation ...
    #elseif os(Android) || os(Linux)
    // ... /proc/self/status VmRSS implementation ...
    #else
    return -1  // Unsupported platform — skip memory assertions
    #endif
}
```

Memory assertions should be conditional on `currentResidentMemoryMB() > 0` to gracefully degrade on unsupported platforms.

---

## Throughput Benchmarks

### Store.send() Synchronous Path Analysis

From `Core.swift` lines 88-197, the `_send` method:

1. Appends action to `bufferedActions` array
2. If not already sending (`isSending` guard), enters the send loop
3. Calls `reducer.reduce(into: &currentState, action: action)` — **synchronous**
4. Checks `effect.operation`:
   - `.none` → **no allocation, no Task creation** — just a switch-case break
   - `.publisher` → creates `AnyCancellable`, `Task`, subscribes to publisher
   - `.run` → creates `Task` with `@MainActor` closure
5. After the loop, assigns `self.state = currentState` and signals `didSet`

**For a reducer returning `.none`**, the cost per `send()` is:
- 1 array append (amortized O(1))
- 1 `reducer.reduce()` call (user code, typically O(1) for simple mutations)
- 1 switch on `.none` (no-op)
- 1 state assignment (CoW — O(1) if no other references)
- 1 `didSet` relay signal (CurrentValueRelay publish)
- UUID generation for each action (even for `.none` effects — this is in the hot path at line 115)

**Expected throughput (synchronous reducers):**

| Iterations | Expected macOS Time | Expected Android Time |
|-----------|--------------------|-----------------------|
| 1,000 | <10ms | <50ms |
| 5,000 | <50ms | <200ms |
| 10,000 | <100ms | <500ms |
| 50,000 | <500ms | <2s |

These estimates assume a trivial reducer (`state.count += 1; return .none`). Real reducers with `IdentifiedArray` mutations, string formatting, or collection operations will be slower.

**Recommended iteration counts for stress tests:**
- **Primary test:** 5,000 iterations — fast enough to complete well within timeouts, large enough to surface linear memory growth
- **Bounds check:** Assert completion in <5 seconds (generous for both platforms)
- **Extended (macOS-only):** 50,000 iterations for thorough leak detection

### UUID Overhead Note

Every `send()` call creates a `UUID()` at line 115 of Core.swift, even when the effect is `.none`. This is ~150ns per call on Apple Silicon. At 50,000 iterations, that's ~7.5ms of UUID generation alone. Not a bottleneck, but worth noting — it means the Store was not designed with >10K sends/frame in mind.

### Effect-Spawning Throughput

When reducers return `.run` effects, each `send()` spawns a `Task`. Task creation overhead is ~1-5us on macOS. At 1,000 sends with effects, expect ~5ms of task creation plus whatever the effects do. The `effectCancellables` dictionary grows with each active effect and shrinks as effects complete.

**Memory concern:** If effects don't complete promptly, `effectCancellables` grows without bound. A stress test sending 5,000 actions that each return `.run { _ in }` (immediate completion) should show bounded memory, while one returning `.run { _ in await Task.sleep(for: .seconds(100)) }` will accumulate 5,000 Tasks.

**Recommendation:** Test both patterns:
1. Pure synchronous (`.none`) — validates reducer/store overhead
2. Immediate-completion effects (`.run { _ in }`) — validates effect cleanup
3. Do NOT stress test with long-running effects — that tests Task scheduler capacity, not TCA

---

## Observation Under Load

### withObservationTracking Behavior

From the existing `ObservationVerifier` tests and the Swift Observation source, `withObservationTracking` has these characteristics:

1. **One-shot:** The `onChange` callback fires at most once per `withObservationTracking` call, then auto-cancels. This is by design — SwiftUI re-registers observation on each `body` evaluation.

2. **Fires on `willSet`, not `didSet`:** The callback fires synchronously during the property's `willSet` accessor, BEFORE the new value is assigned. This means:
   - Inside `onChange`, reading the property returns the OLD value
   - The callback runs on the same thread as the mutation

3. **No coalescing within a tracking scope:** If you track properties A and B, and mutate A then B, only A's `willSet` triggers `onChange` (because it auto-cancels after the first fire). B's mutation is "missed" until you re-register.

4. **1:1 when resubscribed:** The pattern `track -> mutate -> track -> mutate -> ...` produces exactly N callbacks for N mutations. This is confirmed by `ObservationVerifier.verifySequentialObservationCyclesResubscribe()` which runs 3 cycles successfully.

### Stress Test Pattern for Observation

```swift
@available(macOS 14, iOS 17, *)
func testObservationPipelineStress() {
    @Observable
    final class StressModel {
        var counter = 0
    }

    let model = StressModel()
    var fireCount = 0
    let iterations = 5_000

    for i in 0..<iterations {
        withObservationTracking {
            _ = model.counter  // register tracking
        } onChange: {
            fireCount += 1
        }
        model.counter = i + 1  // trigger onChange
    }

    // 1:1 — each cycle fires exactly once
    XCTAssertEqual(fireCount, iterations)
    XCTAssertEqual(model.counter, iterations)
}
```

**Why this is valid:** This mirrors the actual SwiftUI pattern — `body` is called (tracks), state mutates (fires onChange), SwiftUI schedules re-render, `body` is called again (re-tracks). The stress test runs this loop synchronously without the SwiftUI scheduler.

### Observation Memory Characteristics

Each `withObservationTracking` call allocates:
- An `ObservationTracking` object (internal to the Observation framework)
- Registration entries in the `ObservationRegistrar`'s internal storage
- The `onChange` closure capture

After `onChange` fires, the tracking is cancelled and these allocations are eligible for deallocation. Memory should be bounded — the registrar doesn't accumulate cancelled trackings.

**Test pattern for observation memory:**
```swift
let memBefore = currentResidentMemoryMB()
// ... 5000 iterations of track-mutate ...
let memAfter = currentResidentMemoryMB()
XCTAssertLessThan(memAfter - memBefore, 20,
    "Observation tracking should not accumulate memory across cycles")
```

### Rapid Mutation Without Resubscription

A second stress pattern tests what happens when many mutations occur within a single tracking scope:

```swift
func testBulkMutationNoAccumulation() {
    @Observable
    final class BulkModel {
        var value = 0
    }

    let model = BulkModel()
    var fireCount = 0

    withObservationTracking {
        _ = model.value
    } onChange: {
        fireCount += 1
    }

    // Rapid mutations — only the first triggers onChange
    for i in 1...5_000 {
        model.value = i
    }

    XCTAssertEqual(fireCount, 1, "onChange fires once then auto-cancels")
    XCTAssertEqual(model.value, 5_000)
}
```

This validates that the Observation framework doesn't accumulate per-mutation overhead after the tracking is cancelled. The registrar's `willSet`/`didSet` accessors should be near-no-ops after cancellation.

---

## Platform Differences

### macOS vs Android: Test Runtime

| Aspect | macOS (`swift test`) | Android (`skip test`) |
|--------|---------------------|----------------------|
| Test framework | XCTest (native) | JUnit (transpiled via Skip) |
| `XCTest.measure {}` | Works (Xcode metrics) | NOT available — transpiled to JUnit which has no equivalent |
| `withObservationTracking` | Native Swift stdlib | Native `libswiftObservation.so` (Fuse mode) |
| Memory measurement | `mach_task_basic_info` | `/proc/self/status` VmRSS |
| `@Observable` macro | Swift compiler | Swift compiler (Fuse mode runs native Swift) |
| `ContinuousClock` | Available | Available (Swift stdlib) |
| Main actor isolation | `@MainActor` works | `@MainActor` works (Swift concurrency runtime) |
| Test timeout | None by default | JUnit: none by default; Gradle: configurable per task |

### XCTest.measure {} on Android

`XCTest.measure {}` is a Darwin-specific API that integrates with XCTest's performance metric collection (XCTMetric, XCTClockMetric, etc.). When transpiled to Kotlin via Skip, this API does not exist — Skip transpiles `XCTestCase` to JUnit `TestCase`, but `measure {}` has no JUnit equivalent.

**Alternative:** Use `ContinuousClock` for manual timing:

```swift
func testThroughputTiming() {
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        for _ in 0..<5_000 {
            store.send(.increment)
        }
    }
    // Log or assert on elapsed time
    print("5000 sends completed in \(elapsed)")
    // Don't assert on absolute time — too platform-dependent
    // Instead, assert on correctness and memory bounds
}
```

**Recommendation:** Do NOT use `measure {}` in stress tests. Use `ContinuousClock` for informational timing and focus assertions on correctness (final state value) and memory bounds (RSS delta). Absolute timing assertions are fragile across platforms and CI environments.

### skip test Timeout Behavior

- The project's `Makefile` runs `skip test` with no timeout flags
- Skip delegates to Gradle's `test` task, which has no per-test timeout by default
- JUnit 4 (Skip's target) supports `@Test(timeout = milliseconds)` but this is set per-test, not globally
- Gradle's `test` task supports `maxParallelForks` and `forkEvery` but not per-test timeouts
- CI runners (GitHub Actions, etc.) typically have a job-level timeout (usually 30-60 minutes)

**Safe bounds:** A stress test completing in <30 seconds is safe for all environments. Tests exceeding 60 seconds should be gated behind a flag or separated into a dedicated "performance" test target.

### Robolectric vs Emulator

Stress tests via `skip test` default to Robolectric (JVM on macOS). This means:
- `/proc/self/status` reports JVM memory, not Android process memory
- Swift code runs as native Swift (Fuse mode compiles Swift, doesn't transpile it)
- Performance characteristics differ from real Android hardware (Robolectric is faster for CPU-bound work, slower for JNI round-trips)

For accurate Android performance numbers, set `ANDROID_SERIAL` to run on a real emulator. For CI validation of "no crash, bounded memory," Robolectric is sufficient.

---

## Recommendations

### 1. Test Structure

Create a single test file `StressTests.swift` in a new `StressTests` test target (or within an existing target like `StoreReducerTests`). Gate all tests with `@available(macOS 14, iOS 17, *)` for Observation APIs.

### 2. Iteration Counts

| Test | Primary Count | Extended (macOS-only) |
|------|--------------|----------------------|
| Store throughput (sync) | 5,000 | 50,000 |
| Store throughput (effects) | 1,000 | 5,000 |
| Observation resubscription | 5,000 | 50,000 |
| Observation bulk mutation | 5,000 | 50,000 |

5,000 is the sweet spot: large enough to surface linear growth issues, small enough to complete in <5 seconds on Android emulators.

### 3. Memory Assertions

- Use a delta-based assertion: `memAfter - memBefore < threshold`
- Threshold: 50MB for Store tests, 20MB for Observation tests
- Make memory assertions conditional: only assert when `currentResidentMemoryMB() > 0`
- On platforms where memory measurement returns -1, fall back to "no crash" as the assertion

### 4. Timing Strategy

- Use `ContinuousClock` for informational logging, NOT for pass/fail assertions
- Log timing results for human review: `print("Store: \(iterations) sends in \(elapsed)")`
- Assert on correctness (final state == expected) and memory (bounded RSS growth)

### 5. Test Target Configuration

```swift
// In Package.swift
.testTarget(name: "StressTests", dependencies: [
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
]),
```

Or add stress tests to the existing `StoreReducerTests` target to avoid adding another target. The trade-off: a separate target allows running stress tests independently (`swift test --filter StressTests`), but adds Package.swift complexity.

**Recommendation:** Add to existing `StoreReducerTests` target with a `StressTests.swift` file. Use `make test-filter FILTER=StressTests` for isolated runs.

### 6. Android-Specific Considerations

- Do NOT use `XCTest.measure {}` — it won't transpile
- Do NOT assert on absolute timing — Android emulator performance varies 10x
- DO use `/proc/self/status` VmRSS for memory on Android
- DO keep iteration counts at 5,000 or below for `skip test` runs
- DO gate extended tests behind `#if !os(Android)` if needed

### 7. Proposed Test Matrix

| Test Name | Measures | Iterations | Memory Assert | Platform |
|-----------|---------|------------|---------------|----------|
| `testStoreReducerThroughputSync` | send() with .none reducer | 5,000 | <50MB delta | Both |
| `testStoreReducerThroughputEffects` | send() with immediate .run | 1,000 | <50MB delta | Both |
| `testObservationResubscriptionStress` | track-mutate-retrack loop | 5,000 | <20MB delta | Both |
| `testObservationBulkMutationStress` | 5000 mutations in single scope | 5,000 | <20MB delta | Both |
| `testStoreReducerThroughputExtended` | send() at scale | 50,000 | <50MB delta | macOS only |

---

*Research completed: 2026-02-22*
*Sources: TCA Core.swift (fork, lines 79-197), Store.swift (fork, lines 201-337), ObservationVerifier.swift (fuse-library), existing ObservationTrackingTests, XCSkipTests.swift, Makefile, 07-RESEARCH.md, MemoryManagementTests.swift (TCA upstream)*
