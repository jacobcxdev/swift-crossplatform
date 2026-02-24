# Phase 7: Integration Testing & Documentation — Final Research

**Created:** 2026-02-22
**Sources:** Initial research + 10 first-pass agents (R1–R10) + 10 deep-dive agents (R1b–R10b)
**Methodology:** 20 parallel researcher agents, two-pass reconciliation
**Total research investment:** ~1M tokens across all agents

---

## How to Read This Document

This is the **definitive research output** for Phase 7 planning. It supersedes `07-RESEARCH-RECONCILED.md` (first-pass reconciliation). Deep-dive files in `research/R*b-*.md` contain exhaustive source-level traces for implementers who need line-number precision.

**Sections match what `plan-phase` expects:**
- [Standard Stack](#standard-stack) — Libraries and tools to use
- [Architecture Patterns](#architecture-patterns) — How to structure the work
- [Don't Hand-Roll](#dont-hand-roll) — What NOT to build from scratch
- [Common Pitfalls](#common-pitfalls) — Verified failure modes
- [Code Examples](#code-examples) — Copy-pasteable patterns

---

## Corrections to First-Pass Research

| # | Initial Claim | Corrected Finding | Source |
|---|--------------|-------------------|--------|
| C1 | "108 tests" (STATE.md) | **226 test methods** across 20 targets (146 XCTest + 80 Swift Testing) | R6 |
| C2 | `ProcessInfo.processInfo.physicalMemory` for memory | **Useless** — returns total system RAM. Use `mach_task_basic_info` (Darwin) / `/proc/self/status` VmRSS (Android) | R3b §3 |
| C3 | Fork commit count "rough estimates" | **157 total commits** across 17 forks (R5b corrects R5's 162 — base branch counting error) | R5b |
| C4 | `skip test` implied viable for bridge testing | **Cannot test bridge** — Robolectric runs transpiled Kotlin, not native Swift. Only `skip android test` exercises JNI bridge | R7, R9b §1 |
| C5 | Bridge failure = "fatalError" | **Silent no-op in Lite mode** — `Java_initPeer()` returns nil. **fatalError in Fuse mode** only on `nativeEnable()` failure | R2b §5 |
| C6 | GRDB upstream branch = `origin/main` | Uses **`origin/master`** (only fork that differs) | R5b §2.2 |
| C7 | Conditional guard count = 88 | **~125 Android-relevant guards** — R8 excluded `#if canImport(Combine)` (~32) and `#if SKIP_BRIDGE` (2) | R6b §7 |
| C8 | B4 "GRDB `link sqlite3` will fail on Android" | **Already solved** — both GRDB (commit `36dba72`) and swift-structured-queries (commit `fb5cc61`) bundle `sqlite3.h` with `__ANDROID__` guard. Fix applied 2026-02-13, before Phase 6 | R7b §1-2 |
| C9 | P1-3 "GRDB/sqlite-data Combine imports unguarded" | **False positive** — all Combine imports in GRDB are behind `#if canImport(Combine)`. sqlite-data same. OpenCombineShim handles TCA. No action needed | R6b §6, R10b §5 |
| C10 | 5 divergence points in TestStore.swift | **6 platform-conditional blocks** (R1b found additional `bindings()` guard at line 2580) | R1b §1 |
| C11 | 2 forks with zero changes not flagged | **`swift-case-paths` and `swift-identified-collections` have zero fork-specific commits** — stale snapshots 5 commits behind upstream | R5b §1 |

---

## Unified Blocker Assessment

### P0 — Must resolve before Phase 7 execution

| # | Blocker | Impact | Mitigation | Source |
|---|---------|--------|------------|--------|
| B1 | **fuse-app missing TCA fork dependencies** | Cannot write any TCA code. Current Package.swift has 4 deps; needs ~17 | Add 13 fork path dependencies + ComposableArchitecture/SQLiteData product references | R4b §3, R9 |
| B2 | **`@Shared(.fileStorage)` subscription no-op on Android** | File change monitoring dead — `DispatchSource` polyfill is compile-time only. Cross-instance notifications never fire | Test write-then-read path; document notification gap as known limitation | R6b §1 |
| B3 | **`@Shared(.appStorage)` subscription no-op on Android** | KVO-based UserDefaults subscription excluded. SharedPreferences changes invisible until manual read | Same as B2 — test persistence path, document subscription gap | R6b §2 |
| B4 | ~~GRDB `link sqlite3` on Android~~ | **RESOLVED** — both forks bundle `sqlite3.h` with `__ANDROID__` guard (2026-02-13). Never tested end-to-end on Android from this machine | Run `skip android build` from fuse-library to confirm | R7b |
| B5 | **TestStore non-determinism on Android** | `useMainSerialExecutor` fully disabled. `effectDidSubscribe` AsyncStream fallback handles sync but concurrent effect ordering may vary | Avoid assertions on concurrent effect ordering; use `store.timeout = 5_000_000_000` for emulator | R1b §Guard 4, R6b §5 |

### P1 — Should resolve during Phase 7

| # | Issue | Impact | Mitigation | Source |
|---|-------|--------|------------|--------|
| P1-1 | **41 SPM identity conflicts** (fuse-library) | Non-blocking but noisy (47 total warnings). Will grow to 30+ for fuse-app when TCA deps added | Fix: local path substitution in 12 fork Package.swift files (~2h effort, eliminates all 47 warnings) | R8b |
| P1-2 | **Makefile `android-test` undefined** | Declared in `.PHONY` but no rule body — silently succeeds doing nothing | Add rule body: `cd $(EXAMPLE_DIR) && skip android test` | R9b §6 |
| P1-3 | ~~GRDB/sqlite-data Combine imports unguarded~~ | **FALSE POSITIVE** — all Combine imports properly guarded behind `#if canImport(Combine)` | No action needed | R6b §6, R10b §5 |
| P1-4 | **`swiftThreadingFatal` stub fragility** | Required for `libswiftObservation.so` to load until Swift 6.3 | Monitor Swift 6.3 release; remove stub once upstream fix ships | R8 |
| P1-5 | **ObservationTrackingTests redundant** | 7 tests are exact duplicates of ObservationTests | Remove target; 226 → 219 unique tests | R6 |
| P1-6 | **Missing `clean` Makefile target** | Combined `.build/` at 3.8 GB, will grow to ~8 GB | Add `clean` target | R9 |
| P1-7 | **`[String]` appStorage crashes on Android** | `AndroidUserDefaults.stringArray(forKey:)` calls `fatalError()` | Avoid `@Shared(.appStorage("key"))` typed as `[String]` in showcase | R6b (new finding) |
| P1-8 | **Local fork paths incompatible with Gradle embedded build** | `skip android test` fails because Gradle's embedded Swift build can't resolve `../../forks/` paths | Two-step workaround: `skip android build` first, then `SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 skip android test` | R9b §5 |
| P1-9 | **Package.resolved gitignored** | Remote deps (Skip) have no upper bound. Builds non-reproducible if Skip 1.8.0 ships during Phase 7 | Consider committing Package.resolved or pinning `"1.7.2"..<"1.8.0"` | R10b §2 |

### P2 — Track but non-blocking

| # | Issue | Source |
|---|-------|--------|
| P2-1 | 6 unused fuse-library dependencies (intentional for transitive resolution) | R9 |
| P2-2 | Stale fuse-app Android build (Feb 20, never tested with TCA) | R9 |
| P2-3 | `swift-concurrency-extras` not declared as direct dep | R9 |
| P2-4 | `ObservedObject` is thin shim on Android (no change observation) | R8 |
| P2-5 | `TextState` renders plain strings only on Android (modifiers stripped) | R8 |
| P2-6 | 30+ SwiftUI binding/animation extensions excluded on Android | R8 |
| P2-7 | JNI `try!` force-unwraps in bridge code — crash on Java exception | R2b §5 |
| P2-8 | README.md stale (says 14 forks, actual 17; wrong branch name; resolved NavigationStack issue listed) | R10b §1 |
| P2-9 | REQUIREMENTS.md traceability table stale (Phases 1-2 still show "Pending") | R10b §6 |
| P2-10 | Swift 5/6 language mode mismatch — `swift-perception` and `swift-snapshot-testing` pinned to `.v5`, may produce Sendable warnings at call sites | R10b §1 |
| P2-11 | Swift Testing `@Test` transpilation via Skip untested — if skipstone can't handle it, Phase 7 tests must use XCTest | R10b §3 |
| P2-12 | Phase 7 scope includes 5 deferred human tests from Phase 1 (not just TEST-01..TEST-12 + DOC-01) | R10b §7 |

---

## Standard Stack

### TestStore Infrastructure (TEST-01..TEST-09)

**Use:** TCA's built-in `TestStore` with `effectDidSubscribe` fallback. No custom wrappers needed.

**6 platform-conditional blocks** in TestStore.swift (R1b mapped exhaustively):
1. Lines 477-483: `useMainSerialExecutor` property (absent on Android)
2. Lines 558-560: `init()` sets executor (no-op on Android)
3. Lines 654-656: `deinit` restores executor (no-op on Android)
4. Lines 1006-1018: `send()` synchronisation — **THE critical divergence** (Apple: `Task.yield()` on serial executor; Android: `effectDidSubscribe.stream`)
5. Lines 2580-2683: `bindings()` extensions (absent on Android, won't compile)
6. Implicit: `mainActorNow` at line 657 may have platform-specific behaviour

**effectDidSubscribe lifecycle (R1b §2):**
- Stream created at line 2839 via `AsyncStream.makeStream(of: Void.self, bufferingPolicy: .unbounded)`
- Yield Point A (line 2880): `.none` effects yield immediately — always deterministic
- Yield Point B (lines 2890-2892): `.publisher`/`.run` effects yield after `Task { megaYield; yield }` in `receiveSubscription` — timing-dependent

**4 confirmed coverage gaps for Phase 7 tests:**
1. Chained effects (effect → action → effect) — buffered yields may cause premature `send()` resume
2. `cancelInFlight` with rapid re-sends — brief zero-effect window between cancel and re-subscribe
3. Long-running effect + `finish()` timeout — polling loop uses `Task.yield()` which doesn't guarantee progress on Android
4. Non-exhaustive `receive` with `.off` — detached background task per polling iteration

**3 additional edge cases (R1b §3):**
- `@Dependency(\.dismiss)` with in-flight effects — effects removed from tracking but NOT cancelled
- StackState/StackAction pop cancellation — multiple concurrent `receiveCancel` handlers fire in unpredictable order
- Deep effect chains (4+ levels) — buffered yield accumulation

### Observation Bridge Testing (TEST-10)

**Two-tier strategy:**

**Tier 1 — macOS mock-bridge (R2b §6):**
- `ObservationRecording` has **zero JNI dependencies** — feasible to test on macOS
- Recommended approach: copy-paste extraction (~30 min) — extract recording/replay logic into testable module
- Enables 11 scenarios: recording lifecycle, nested frames, thread isolation, single-trigger-per-frame, diagnostics API, `isEnabled` switching
- ObservationRecording uses `pthread_key_t` thread-local stack — complete thread isolation, LIFO nesting

**Tier 2 — Android emulator (R9b):**
- 6 end-to-end tests: JNI initialisation, Compose recomposition trigger, observation bridge lifecycle, runtime linkage
- `skip android test` with `--testing-library` flag for targeted execution
- Two-step build workaround required (P1-8): `skip android build` first, then `SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 skip android test`

**Bridge architecture (R2b §1):**
- `access()` performs THREE actions: records to replay stack (if recording), calls `bridgeSupport.access()` (JNI), calls `registrar.access()` (native Observation)
- `willSet()` is conditionally suppressed by `isEnabled` one-way gate — prevents double-triggering when `withObservationTracking` onChange handler is active
- 19 documented failure modes (R2b §9), two CRITICAL: `try!` force-unwraps in JNI calls that crash on Java exceptions

### Stress Testing (TEST-11)

**Store.send() hot path (R3b §1):**
- For `.none` reducers: entirely synchronous, zero Task allocations
- Per-call overhead: ~330ns (Darwin), ~480ns (Android)
- Hidden costs: 1 `LockIsolated` heap allocation + 1 `UUID()` per call (even for `.none`)
- 5,000 iterations @ ~330ns = ~1.65ms total (Darwin), well within 1,000 mutations/sec requirement (100x+ margin)

**Memory measurement (R3b §3):**
- Darwin: `mach_task_basic_info` via `task_info()` (~1.5us per call)
- Android/Linux: `/proc/self/status` VmRSS parsing (~20-50us per call)
- **Sample start/end only** — per-iteration on Android costs 150ms for 5,000 calls

**Observation coalescing (R3b §5):**
- Single property, 5,000 mutations, one tracking scope: exactly 1 callback
- Multiple properties, one tracking scope: first willSet on ANY property fires onChange and cancels ALL
- Real-world UI coalesces at framework level (per-frame batching), not Observation level

**Clock API:** `ContinuousClock` available on Android via Swift Android SDK. Nanosecond resolution. Use instead of `XCTest.measure`.

### Fuse-App Showcase (TEST-12)

**Architecture (R4b):**
- All features as files within FuseApp target, NOT separate SPM targets (avoids Skip/Gradle module explosion)
- 6 features: Counter, Todos, Contacts, Database, Settings, App (tab-based root coordinator)
- 13 new files (9 source + 4 test), 2 deleted, 2 modified
- SyncUps patterns adopted: `@Shared` with `SharedKey` extension, `$shared.withLock {}`, delegate actions, `@Presents` + `@Reducer enum Destination`

**Package.swift changes (R4b §3):**
- Add 13 fork path dependencies (matching fuse-library's set)
- Add `ComposableArchitecture` and `SQLiteData` product references to FuseApp target
- Replace `FuseAppViewModelTests` with `FuseAppIntegrationTests`
- Expect ~20-30 SPM identity conflict warnings (cosmetic)

**SkipUI feasibility (R4b §6):**
- Supported: TabView, NavigationStack, List, Form, sheet, alert, confirmationDialog, fullScreenCover
- Partially supported: Popover (renders as sheet on Android) — use sheet fallback

**Build estimates:**
- First `swift build` with TCA: 60-120s
- First `skip android build` with TCA: 5-15 minutes (major unknown — never attempted)
- Incremental strategy: wire Package.swift first, add features one-at-a-time with `swift build` verification after each

### Fork Documentation (DOC-01)

**17 forks, 3 remote configurations (R5b §1):**
1. Skip-ecosystem (`skip-android-bridge`, `skip-ui`): base is `origin/dev/swift-crossplatform`
2. Point-Free with `flote-works` remote: upstream is `flote-works/main`
3. Single-remote (`swift-case-paths`, `swift-identified-collections`, `xctest-dynamic-overlay`, `GRDB.swift`): upstream is `origin/main`/`origin/master`

**Zero-change forks:** `swift-case-paths` and `swift-identified-collections` — stale snapshots, no fork-specific commits. Need upstream sync.

**Rebase risk (R5b §2):**
1. VERY HIGH: `swift-composable-architecture` (55 source files, 39 commits, 6 reverts)
2. HIGH: `swift-navigation` (13 source files, 27 commits, TextState/ButtonState bridges)
3. HIGH: `swift-sharing` (10 source files, runtime behavioural changes)

**Upstream PR candidates (R5b — Tier 1, likely accepted):**
- `xctest-dynamic-overlay` — `isTesting` Android dlsym detection
- `swift-custom-dump` — SwiftUI guard
- `combine-schedulers` — SwiftUI guard + OpenCombine
- `swift-dependencies` — OpenURL/AppEntryPoint guards
- `swift-clocks` — SwiftUI EnvironmentKey guard

**3-fork observation bridge chain (R5b):**
1. `skip-android-bridge` — `ObservationRecording` record-replay + `ObservationRegistrar` (163 lines)
2. `skip-ui` — wraps `View`/`ViewModifier` `Evaluate()` with `startRecording()`/`stopRecording()` (27 lines)
3. `swift-composable-architecture` — routes `ObservationStateRegistrar` to bridge registrar on Android (19 lines)

---

## Architecture Patterns

### Plan Structure (4 sub-plans recommended)

| Plan | Scope | Est. Time | Dependencies |
|------|-------|-----------|--------------|
| **07-01: TestStore Validation** | TEST-01..TEST-09: TestStore API tests, 4 gap tests, edge cases. All in fuse-library | 30-45 min | None |
| **07-02: Android Integration** | TEST-10: Emulator tests, bridge validation, observation diagnostics. B4 verification | 45-60 min | 07-01 (test infrastructure) |
| **07-03: Showcase & Stress** | TEST-11, TEST-12: fuse-app rebuild, 6 features, stress tests. B1 resolution | 60-90 min | 07-01 (TestStore patterns) |
| **07-04: Documentation** | DOC-01: docs/FORKS.md generation from R5b metadata. P1-5 cleanup. README fix | 20-30 min | 07-03 (final state known) |

### Test Organisation

**fuse-library (existing 226 tests, keep as-is):**
- Phase 7 adds TestStore gap tests (TEST-01..TEST-09) as new targets
- Remove ObservationTrackingTests (7 redundant tests → 219 unique)

**fuse-app (new for Phase 7):**
- Integration tests for showcase features (TEST-12)
- Stress tests with Swift Testing `@Test(.tags(.stress))` for filter exclusion (TEST-11)
- Android emulator tests via `skip android test` (TEST-10)

### Android Test Execution

**Two distinct paths (R9b §1):**

| Path | Trigger | Runner | Emulator | Bridge |
|------|---------|--------|----------|--------|
| Robolectric (JVM) | `skip test` | JUnit4 + Robolectric 4.16 | No | No (transpiled Kotlin) |
| On-device | `skip android test` | AndroidJUnitRunner | Yes | Yes (native Swift + JNI) |

**Per-test filtering (R9b §1):**
```bash
skip android test -- -Pandroid.testInstrumentationRunnerArguments.class=fuse.library.FuseLibraryTests#testFoo
```

**Emulator state:** Already booted — `emulator-5554`, API 36, arm64-v8a, 4GB RAM, ~2GB free.

### Conditional Compilation Landscape (~125 guards)

| Pattern | Count | Purpose |
|---------|-------|---------|
| `#if os(Android)` (positive) | 21 | Android-specific polyfills |
| `#if !os(Android)` (negative) | 40 | Exclude Apple-only code |
| `#if canImport(SwiftUI) && !os(Android)` | 28 | SwiftUI exclusions |
| `#if canImport(Combine)` | ~32 | Combine availability (OpenCombineShim fallback) |
| `#if SKIP_BRIDGE` | 2 | Bridge-level observation wrappers |
| `#if DEBUG && !os(Android)` | 2 | Debug-only Apple code |

**Categorisation (R6b §7):**
- ~45 guards: intentional SwiftUI API exclusions (Compose handles differently)
- ~32 guards: Combine availability with OpenCombineShim fallback
- ~10 guards: Android-specific polyfills (correct replacements)
- 3 guards: P0 no-op stubs (fileStorage subscription, appStorage subscription, TestStore serialisation)
- ~5 guards: ObjC runtime exclusions (KVO, selectors)
- ~8 guards: deprecated API phase-outs

---

## Don't Hand-Roll

1. **TestStore synchronisation** — use TCA's built-in `effectDidSubscribe` fallback; don't build custom synchronisation primitives
2. **Memory measurement** — use `mach_task_basic_info`/`/proc/self/status`; don't use `ProcessInfo` or `malloc_size` (R3b §3 has production-grade code)
3. **Test timing** — use `ContinuousClock`; don't use `XCTest.measure` (unavailable on Android) or `DispatchTime` (R3b §4)
4. **SQLite linking** — already solved in forks; don't add CSQLite or bundle libsqlite3.so (R7b)
5. **Observation recording** — use existing `ObservationRecording` from skip-android-bridge; don't rebuild the replay stack (R2b §4)
6. **Fork metadata** — R5b has complete git data for all 17 forks; don't re-run git commands during DOC-01 (R5b)
7. **SPM conflict suppression** — fix root cause (local path substitution in 12 fork Package.swift); don't add workarounds in example Package.swift (R8b)

---

## Common Pitfalls

### Verified (confirmed via source-level trace)

| # | Pitfall | Why It Fails | Correct Approach | Source |
|---|---------|-------------|-----------------|--------|
| 1 | Asserting concurrent effect ORDER on Android | `useMainSerialExecutor` absent → effects genuinely concurrent | Assert effect SET (all arrive) not SEQUENCE | R1b §Guard 4 |
| 2 | Using `XCTest.measure` for stress tests | Transpiled to JUnit → no `measure` equivalent | `ContinuousClock.now` before/after | R3b §4 |
| 3 | Calling `ProcessInfo.processInfo.physicalMemory` | Returns total system RAM (e.g. 48GB), not process RSS | `mach_task_basic_info` / `/proc/self/status` | R3b §3 |
| 4 | Testing bridge on macOS without mock | All bridge code behind `#if SKIP_BRIDGE` → won't compile | Copy-paste `ObservationRecording` into testable module (~30 min) | R2b §6 |
| 5 | Using `@Shared(.appStorage("key"))` with `[String]` type on Android | `AndroidUserDefaults.stringArray(forKey:)` calls `fatalError()` | Use `String` or `Data` types; avoid `[String]` | R6b (new) |
| 6 | Expecting `@Shared(.fileStorage)` subscription to fire on Android | `fileSystemSource` returns `SharedSubscription {}` — never fires | Test write-then-read path only; document gap | R6b §1 |
| 7 | Running `skip android test` without pre-building Swift | Gradle's embedded Swift build can't resolve `../../forks/` paths | Two-step: `skip android build` first, then `SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 skip android test` | R9b §5 |
| 8 | Copying test patterns from TCA's own test targets | TCA tests skip StrictConcurrency; fuse-library/app use Swift 6 default → Sendable errors at call sites | Add explicit `@Sendable` annotations or `nonisolated` as needed | R10b §1 |
| 9 | Using `$store.scope` binding syntax on Android | `bindings()` extensions (line 2580-2683) are `#if !os(Android)` | Use `store.scope(state:action:)` method directly | R1b §Guard 5 |
| 10 | Assuming `swift-case-paths`/`swift-identified-collections` have fork changes | Zero fork-specific commits — stale snapshots | Sync with upstream before documenting | R5b §1 |
| 11 | Per-iteration memory sampling on Android | `/proc/self/status` parsing costs ~20-50us × 5,000 = 100-250ms overhead | Sample start/end only for pass/fail | R3b §3 |
| 12 | Depending on `finish()` completing quickly on Android emulator | Polling loop uses `Task.yield()` without progress guarantee; slow emulators may timeout | Set `store.timeout = 5_000_000_000` (5s) | R1b §Gap 3 |
| 13 | Creating `Package.resolved` for reproducibility | Currently gitignored; remote deps have no upper bound | Consider committing or pinning `"1.7.2"..<"1.8.0"` | R10b §2 |

---

## Code Examples

### Memory Measurement (cross-platform)

```swift
#if canImport(Darwin)
import Darwin

func currentResidentMemoryBytes() -> UInt64? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
}

#elseif os(Android) || os(Linux)
func currentResidentMemoryBytes() -> UInt64? {
    guard let file = fopen("/proc/self/status", "r") else { return nil }
    defer { fclose(file) }
    var buffer = [CChar](repeating: 0, count: 256)
    while fgets(&buffer, Int32(buffer.count), file) != nil {
        let line = String(cString: buffer)
        if line.hasPrefix("VmRSS:") {
            let digits = line.filter(\.isNumber)
            guard let kb = UInt64(digits) else { return nil }
            return kb * 1024
        }
    }
    return nil
}
#endif
```

### Stress Test Timing Pattern

```swift
import Testing

@Test(.tags(.stress))
func stressSendNone() async {
    let store = Store(initialState: Counter.State()) { Counter() }
    let iterations = 5_000
    let clock = ContinuousClock()

    let startMem = currentResidentMemoryBytes()
    let elapsed = await clock.measure {
        for _ in 0..<iterations {
            store.send(.incrementButtonTapped)
        }
    }
    let endMem = currentResidentMemoryBytes()

    #expect(store.count == iterations)
    #expect(elapsed < .milliseconds(500)) // 100x margin on Darwin
    if let s = startMem, let e = endMem {
        #expect(e - s < 50 * 1024 * 1024) // <50MB growth
    }
}
```

### Android Emulator Test Execution

```bash
# Step 1: Build Swift for Android (SPM resolves forks correctly)
cd examples/fuse-library
skip android build --configuration debug --arch aarch64

# Step 2: Run tests, skipping embedded Swift build
SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 skip android test \
  --testing-library FuseLibraryTests -v

# Step 3: Per-test filtering via Gradle args
skip android test -- \
  -Pandroid.testInstrumentationRunnerArguments.class=fuse.library.FuseLibraryTests#testObservationBridge
```

### TestStore Gap Test (chained effects)

```swift
@Test func chainedEffectsSettleOnAndroid() async {
    let store = TestStore(initialState: ChainFeature.State()) {
        ChainFeature()
    }
    // Effect A returns action that triggers Effect B
    await store.send(.startChain)
    await store.receive(\.chainStepA) { $0.step = 1 }
    await store.receive(\.chainStepB) { $0.step = 2 }
    // On Android, effectDidSubscribe must yield for BOTH effects
}
```

---

## Research File Index

| File | Lines | Scope |
|------|-------|-------|
| `R1-teststore-android.md` | 294 | TestStore divergence overview |
| `R1b-teststore-deep.md` | 709 | **Exhaustive** TestStore guard map, effectDidSubscribe lifecycle, 9 test recommendations |
| `R2-observation-bridge.md` | 330 | Bridge architecture overview |
| `R2b-bridge-deep.md` | 1,106 | **Exhaustive** bridge source trace, mock-bridge feasibility, 19 failure modes |
| `R3-stress-testing.md` | 389 | Stress testing strategy |
| `R3b-stress-deep.md` | 973 | **Exhaustive** Store.send() hot path, memory measurement code, coalescing proof |
| `R4b-showcase-deep.md` | 1,063 | **Exhaustive** fuse-app architecture, Package.swift diff, 6-feature plan |
| `R5-fork-documentation.md` | 587 | Fork metadata overview |
| `R5b-forks-deep.md` | 1,018 | **Exhaustive** per-fork git metadata, remote configs, change classification |
| `R6-test-reorganisation.md` | 240 | Test inventory and overlap analysis |
| `R6b-parity-deep.md` | 808 | **Exhaustive** parity gap trace, all ~125 guards categorised |
| `R7-android-emulator.md` | 387 | Emulator testing overview |
| `R7b-sqlite-deep.md` | 507 | **Exhaustive** SQLite linking trace, Android availability proof |
| `R8-parity-gaps.md` | 227 | Parity gap overview |
| `R8b-spm-deep.md` | 507 | **Exhaustive** SPM conflict reproduction, fix recommendation |
| `R9-build-packaging.md` | 233 | Build/packaging risks |
| `R9b-emulator-deep.md` | ~500 | **Exhaustive** emulator infrastructure, fork path blocker, skip.yml config |
| `R10-scope-risks.md` | 193 | Scope risk overview |
| `R10b-crosscutting-deep.md` | 375 | **Exhaustive** blind spot analysis, 10 missed findings |

**Total research corpus:** ~8,700 lines across 19 files.

---

*Research completed: 2026-02-22*
*Method: 20 parallel researcher agents (10 first-pass + 10 deep-dive), two-pass reconciliation*
*Confidence: HIGH — all critical claims verified against source code with line numbers*
