# Phase 1: Observation Bridge - Research

**Researched:** 2026-02-21
**Objective:** What do I need to know to PLAN this phase well?
**Phase scope:** 36 requirements (OBS-01 through OBS-30, SPM-01 through SPM-06)

---

## 1. Current State of the Implementation

### What Already Exists (Estimated ~90% Complete)

The observation bridge fix is not a greenfield implementation. The core record-replay infrastructure already exists across three forked repositories. The remaining work is integration verification, edge case handling, diagnostics, missing ViewModifier observation hooks, and SPM compilation validation.

**skip-android-bridge** (`forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`, 302 lines):
- `ObservationRecording` class: thread-local frame stack using `pthread_key_t`, `startRecording()` / `stopAndObserve()` / `recordAccess()` methods, `isEnabled` one-way flag
- `ObservationRegistrar`: dual-path registrar -- records access during body eval, bridges to `MutableStateBacking` via JNI, delegates to native `Observation.ObservationRegistrar`
- `BridgeObservationSupport`: JNI calls to `MutableStateBacking.access()` / `update()`, `triggerSingleUpdate()` for single-increment recomposition, `DispatchSemaphore`-protected JObject peer
- `willSet` suppression: when `isEnabled == true`, `bridgeSupport.willSet()` is skipped in both `willSet()` and `withMutation()` -- preventing per-mutation counter increments
- JNI exports: `nativeEnable`, `nativeStartRecording`, `nativeStopAndObserve` via `@_cdecl` with correct `Java_skip_ui_ViewObservation_*` naming
- `swiftThreadingFatal` stub: `@_cdecl("_ZN5swift9threading5fatalEPKcz")` workaround for `libswiftObservation.so` loading

**ObservationModule** (`forks/skip-android-bridge/Sources/SkipAndroidBridge/ObservationModule.swift`, 23 lines):
- Thin wrapper importing native `Observation` framework
- Exposes `ObservableType`, `ObservationRegistrarType`, `withObservationTrackingFunc` as public typealiases/functions
- Avoids direct import name collisions with the bridge's `Observation` namespace

**skip-ui** (`forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift`):
- `ViewObservation` struct: declared as Kotlin `object` via `// SKIP DECLARE: object ViewObservation`
- Kotlin init block: `try { nativeEnable(); startRecording = ::nativeStartRecording; stopAndObserve = ::nativeStopAndObserve } catch (_: Throwable) {}`
- `Evaluate()` method: calls `ViewObservation.startRecording?()` before body eval, `ViewObservation.stopAndObserve?()` after
- Hooks are nullable (optional closures) -- graceful fallback if native bridge fails to load

**skip-ui ViewModifier** (`forks/skip-ui/Sources/SkipUI/SkipUI/View/ViewModifier.swift`):
- `Evaluate()` does NOT call `ViewObservation.startRecording?()` / `stopAndObserve?()` -- **this is a gap** (OBS-06 requires ViewModifier observation)
- Currently only calls `StateTracking.pushBody()` / `popBody()` (Lite-mode tracking)

**swift-composable-architecture** (`forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift`):
- `#if os(Android)` selects `SkipAndroidBridge.Observation.ObservationRegistrar`
- `access()`, `mutate()`, `willModify()`, `didModify()` all delegate to the bridge registrar on Android
- `ObservableState` protocol: `#if os(Android)` conforms to `Observable` (not `Perceptible`)

**swift-perception** (`forks/swift-perception/Sources/PerceptionCore/Perception/PerceptionRegistrar.swift`):
- `PerceptionRegistrar` already has `#if !os(Android)` guards for SwiftUI-specific checks
- On Android, `PerceptionRegistrar` is not used by TCA (ObservationStateRegistrar uses bridge registrar instead)
- OBS-29/OBS-30 require `PerceptionRegistrar` to be a thin passthrough to native `ObservationRegistrar` on Android -- need to verify this path

### What Does NOT Exist Yet

1. **ViewModifier observation hooks** -- `ViewModifier.Evaluate()` missing `startRecording`/`stopAndObserve` calls (OBS-06)
2. **Diagnostics API** -- No `ObservationBridge.diagnosticsEnabled` flag or logging hooks (per context decision)
3. **MainActor dispatch for onChange** -- `triggerSingleUpdate()` is called directly from `withObservationTracking`'s onChange, not dispatched to main thread (per context decision: "dispatch to main via MainActor/DispatchQueue.main.async"). Current implementation may work if onChange always fires on main, but needs verification.
4. **Version-gated `swiftThreadingFatal`** -- Current stub is unconditional `#if os(Android)`, not `#if swift(<6.3)` as decided in context
5. **Android instrumented tests** -- Existing tests run on macOS; `skip test` integration tests for observation bridge don't exist
6. **SPM compilation validation** -- All 14 forks need verified Android compilation
7. **PerceptionRegistrar Android passthrough** -- Need to verify/implement OBS-29/OBS-30

---

## 2. Technical Deep Dive: The Record-Replay Pattern

### How It Works (End-to-End Flow)

```
iOS (reference behavior):
  SwiftUI wraps body eval with withObservationTracking
    -> access() records keypath
    -> onChange fires ONCE per cycle
    -> schedules single re-render

Android (bridge fix):
  Phase A: Recording (during Evaluate())
    1. Compose calls Evaluate() on a View
    2. ViewObservation.startRecording?() -> JNI -> ObservationRecording.startRecording()
       -> Pushes new Frame onto thread-local stack
    3. body.Evaluate() runs -> state property accesses fire
       -> ObservationRegistrar.access() detects isRecording == true
       -> Records replay closure: { registrar.access(subject, keyPath: keyPath) }
       -> Records trigger closure: { bridgeSupport.triggerSingleUpdate() } (first access only)
       -> Also calls bridgeSupport.access() -> Java_access(index) [Compose snapshot dependency]
       -> Also calls registrar.access() [native Observation tracking]
    4. Body evaluation completes

  Phase B: Observation Setup (after body)
    5. ViewObservation.stopAndObserve?() -> JNI -> ObservationRecording.stopAndObserve()
       -> Pops Frame from stack
       -> withObservationTracking({
            for closure in replayClosures { closure() }  // Re-register access
          }, onChange: {
            trigger()  // = bridgeSupport.triggerSingleUpdate()
          })
       -> Native Observation now tracks all accessed keypaths
       -> onChange fires ONCE then auto-cancels

  Phase C: Mutation
    6. User action -> TCA reducer mutates state
    7. ObservationRegistrar.withMutation() fires
       -> isEnabled == true, so bridgeSupport.willSet() SUPPRESSED
       -> registrar.withMutation() fires native Observation notification
    8. onChange from step 5 fires
       -> triggerSingleUpdate() -> Java_update(0) -> single MutableState increment
    9. Compose recomposition -> back to step 1
```

### Why This Prevents Infinite Recomposition

- **Before fix:** Every `withMutation()` call increments `MutableStateBacking` counter directly via `bridgeSupport.willSet()`. TCA's `_$id` UUID changes cause N mutations per state assignment -> N counter increments -> N recompositions -> infinite loop.
- **After fix:** `willSet()` suppressed when `isEnabled == true`. Only `withObservationTracking`'s `onChange` fires, and it fires ONCE per cycle. One onChange -> one `triggerSingleUpdate()` -> one counter increment -> one recomposition.

### Critical Invariant

During body evaluation (between `startRecording` and `stopAndObserve`), **zero** `MutableStateBacking.update()` calls must fire. All recomposition triggers must be deferred to the onChange callback. The `isEnabled` flag gates this.

---

## 3. Requirement Analysis

### Requirement Groupings (Natural Implementation Order)

**Group A: Core Bridge Infrastructure (OBS-01 through OBS-04, OBS-21 through OBS-28)**
These are the foundation. OBS-01 (single recomposition per cycle) is the primary bug fix. OBS-02 (willSet suppression), OBS-03 (single MutableStateBacking.update), OBS-21/22 (TLS frame stack, batched access), OBS-23/24 (JNI bridge calls), OBS-25/26/27 (JNI exports) already have implementations. OBS-04 (bridge init failure detection) and OBS-28 (swiftThreadingFatal) need minor adjustments.

**Status:** Mostly implemented. Needs testing and minor fixes (OBS-04 error logging, OBS-28 version gating).

**Group B: Observable Semantics (OBS-05 through OBS-20)**
These verify that standard `@Observable` patterns work correctly through the bridge: nested views (OBS-05), ViewModifiers (OBS-06), ObservationRegistrar lifecycle (OBS-07 through OBS-10), `withObservationTracking` delegation (OBS-11), macro-generated hooks (OBS-12/13), single-update coalescing (OBS-14/15), async safety (OBS-16), `@ObservationIgnored` (OBS-17), optional observable (OBS-18), Equatable identity (OBS-19), bindings (OBS-20).

**Status:** Most are inherently satisfied by the bridge registrar's delegation to native `Observation.ObservationRegistrar`. OBS-06 (ViewModifier) needs code changes. OBS-16 (async/actor safety) needs investigation. OBS-18/20 depend on higher-level SwiftUI patterns that may be Phase 5 concerns but need basic bridge verification here.

**Group C: Perception Passthrough (OBS-29, OBS-30)**
`PerceptionRegistrar` must delegate 1:1 to native `ObservationRegistrar` on Android. `withPerceptionTracking` must call `withObservationTracking`.

**Status:** Need to verify the swift-perception fork's Android code path. The `PerceptionRegistrar` already has `#if canImport(Observation)` paths that delegate to `ObservationRegistrar` when available.

**Group D: SPM Configuration (SPM-01 through SPM-06)**
All 14 forks must compile for Android. SPM-01 (`SKIP_BRIDGE` env var), SPM-02 (dynamic libraries), SPM-03 (skipstone plugin), SPM-04 (macro targets), SPM-05 (local path overrides), SPM-06 (swift settings propagation).

**Status:** Most forks already compile (they've been building for months). The validation task is confirming all 14 resolve and compile together, not implementing SPM support from scratch.

### Requirements That Need Code Changes

| Requirement | What Needs to Change | Where |
|-------------|---------------------|-------|
| OBS-04 | Add visible error logging when `nativeEnable()` fails (currently silently caught by Kotlin try-catch) | `skip-ui/View.swift` ViewObservation init block |
| OBS-06 | Add `ViewObservation.startRecording?()` / `stopAndObserve?()` to `ViewModifier.Evaluate()` | `skip-ui/ViewModifier.swift` |
| OBS-28 | Version-gate `swiftThreadingFatal` with `#if swift(<6.3)` | `skip-android-bridge/Observation.swift` |
| OBS-29 | Verify PerceptionRegistrar delegates to ObservationRegistrar on Android | `swift-perception/PerceptionRegistrar.swift` |
| OBS-30 | Verify withPerceptionTracking delegates to withObservationTracking on Android | `swift-perception/PerceptionTracking.swift` |

### Requirements Satisfied by Existing Code (Need Tests Only)

OBS-01, OBS-02, OBS-03, OBS-05, OBS-07, OBS-08, OBS-09, OBS-10, OBS-11, OBS-12, OBS-13, OBS-14, OBS-15, OBS-17, OBS-19, OBS-21, OBS-22, OBS-23, OBS-24, OBS-25, OBS-26, OBS-27, SPM-01, SPM-02, SPM-03, SPM-05, SPM-06.

### Requirements That Need Investigation

| Requirement | Question | Risk |
|-------------|----------|------|
| OBS-16 | Does `async` method execution on `@Observable` classes work safely across actors on Android? Is `jniContext` thread-safe? | MEDIUM -- `jniContext` may already call `AttachCurrentThread()` |
| OBS-18 | Does optional `@Observable` model correctly drive sheet/cover presentation on Android? | LOW -- primarily a SwiftUI pattern; may defer full testing to Phase 5 |
| OBS-20 | Do `$model.property` bindings sync correctly? | LOW -- primarily a SwiftUI pattern; bridge-level behavior is already correct |
| SPM-04 | Do macro targets with SwiftSyntax compile for Android? | MEDIUM -- macros run at compile time on the host, but target metadata matters |

---

## 4. Key Decisions Already Made (From Context)

These decisions from the context session constrain the plan and must not be re-debated:

1. **Bridge init failure is fatal** -- `fatalError()` with clear message if `nativeEnable()` fails or JNI exports don't resolve
2. **Runtime JNI failures are fatal per call** -- `fatalError()` if `nativeStartRecording()` or `nativeStopAndObserve()` fails mid-session
3. **Opt-in diagnostics API** -- `ObservationBridge.diagnosticsEnabled = true` logs every record/replay cycle with timing in skip-android-bridge
4. **Multi-thread TLS isolation** -- Each thread gets its own TLS recording stack (already implemented)
5. **Independent frame per ViewModifier** -- Each `ViewModifier.body()` pushes/pops its own frame
6. **Natural stack reentrancy** -- Reentrant recordings handled by frame stack push/pop
7. **onChange dispatches to main immediately** -- When onChange fires from arbitrary thread, dispatch to main via `MainActor`/`DispatchQueue.main.async`
8. **Disable counter path when bridge active** -- willSet/didSet skip `MutableStateBacking` JNI when `isEnabled == true`
9. **Counter path gated on nativeEnable()** -- Apps that never call `nativeEnable()` retain counter behavior
10. **PerceptionRegistrar is thin passthrough** -- Delegates 1:1 to native `ObservationRegistrar` on Android
11. **Hybrid SPM pattern** -- SKIP_BRIDGE for Skip forks, `#if os(Android)` for PF forks
12. **All 14 forks must compile for Android** in Phase 1
13. **Version-gated swiftThreadingFatal** -- `#if swift(<6.3)` auto-removal
14. **Research Kotlin rendering path** -- Must trace `Swift_composableBody` -> Evaluate() path
15. **Full Android instrumented tests** -- Tests via `skip test` on Android emulator
16. **Extend existing fuse-library tests** with bridge-specific cases

---

## 5. Risks and Pitfalls

### Critical (Could Block Phase Completion)

**Risk 1: onChange Thread Safety**
The context decision says "dispatch to main via MainActor/DispatchQueue.main.async" when onChange fires from an arbitrary thread. The current implementation calls `triggerSingleUpdate()` directly, which uses `DispatchSemaphore` for thread safety on the JNI call but does NOT dispatch to main. If `MutableStateBacking.update()` must be called from the Compose main thread (Android's UI thread), calling from a background thread could crash or silently fail.

*Mitigation:* Test with mutations from background threads. If Compose requires main thread for state updates, wrap `triggerSingleUpdate()` in main dispatch. This is a small code change.

**Risk 2: Kotlin Rendering Path Unknown**
The Kotlin `@Composable` function generated by skipstone that calls `Swift_composableBody` has not been examined. We need to understand: (a) whether Evaluate() is always called on the Compose main thread, (b) how MutableState reading interacts with Compose snapshot system, (c) whether the nullable closure calls in ViewObservation work correctly from Kotlin.

*Mitigation:* The context decision explicitly calls for a research task to trace this path. Should be an early task in the plan.

**Risk 3: DispatchSemaphore Deadlock on Main Thread**
`BridgeObservationSupport` uses `DispatchSemaphore(value: 1)` for JNI call protection. If `triggerSingleUpdate()` is dispatched to main and `Java_access()` is called from main simultaneously, the semaphore could deadlock the UI thread. Android ANR after 5 seconds.

*Mitigation:* Profile contention during testing. If deadlocks occur, replace `DispatchSemaphore` with `os_unfair_lock` or `NSLock` (non-blocking alternatives).

### Moderate (May Slow Progress)

**Risk 4: `skip test` Android Emulator Setup**
Running `skip test` requires a configured Android emulator. If the emulator environment is not set up or flaky, test iteration will be slow.

*Mitigation:* `skip doctor --native` verifies environment. May need `skip android sdk install` if not already done.

**Risk 5: SPM Resolution with 14 Forks**
All 14 forks resolving together can produce opaque SPM errors. Any version conflict or circular dependency causes long resolution times.

*Mitigation:* Build incrementally -- verify skip-android-bridge alone, then skip-ui, then TCA, then the full example project. Use `swift package resolve --verbose` to debug.

**Risk 6: ViewObservation Init Block Failure is Silent**
The Kotlin init block wraps `nativeEnable()` in `try { ... } catch (_: Throwable) {}` -- swallowing ALL errors. Per the context decision, bridge init failure should be fatal. The current implementation silently falls back to broken counter-based observation.

*Mitigation:* Modify the SKIP INSERT init block to log the error and/or call a native fatal function on failure instead of empty catch.

### Low (Unlikely to Block)

**Risk 7: `#if swift(<6.3)` Syntax**
The `#if swift(<6.3)` conditional may not be supported (Swift compiler checks use `#if swift(>=X.Y)` syntax, not `<`). Need to verify syntax or use `#if !swift(>=6.3)`.

*Mitigation:* Use `#if !swift(>=6.3)` which is the standard negation pattern.

**Risk 8: Macro Target Android Compilation (SPM-04)**
SwiftSyntax-dependent macro targets may have platform-specific issues. However, macros run at compile time on the host machine, not on the target -- so this may be a non-issue for Android.

*Mitigation:* Test by building TCA (which has macro targets) for Android. If macro expansion fails, it will surface immediately.

---

## 6. Dependencies and Ordering Constraints

### External Dependencies

| Dependency | Status | Blocking? |
|-----------|--------|-----------|
| Swift Android SDK 6.1+ | Installed (Skip uses it) | No |
| Android SDK/NDK | Installed (prerequisite per CLAUDE.md) | No |
| Skip 1.7.2+ | Installed (`brew install skiptools/skip/skip`) | No |
| Android emulator | Needs verification (`skip devices`) | May slow testing |
| `libswiftObservation.so` | Ships with Swift Android SDK | No |

### Internal Dependencies (Fork Build Order)

```
Layer 1: skip-android-bridge (no fork dependencies)
  -> Must build and pass unit tests first

Layer 2: skip-ui (runtime dependency on skip-android-bridge via JNI)
  -> ViewObservation loads bridge library at runtime
  -> Must verify Evaluate() hooks work

Layer 3: swift-perception (independent, but needed by TCA)
  -> Verify PerceptionRegistrar Android passthrough

Layer 4: swift-composable-architecture (depends on skip-android-bridge, swift-perception)
  -> ObservationStateRegistrar uses bridge registrar
  -> Compile verification, not code changes

Layer 5: All remaining forks (compile-only validation)
  -> swift-navigation, swift-sharing, swift-dependencies, swift-clocks,
     combine-schedulers, swift-custom-dump, swift-snapshot-testing,
     swift-structured-queries, GRDB.swift, sqlite-data

Layer 6: examples/fuse-library (depends on all above)
  -> Integration tests, observation bridge validation
```

### Task Ordering Constraints

1. Kotlin rendering path research must happen BEFORE any changes to View.swift/ViewModifier.swift
2. ViewModifier.Evaluate() fix (OBS-06) must happen BEFORE nested modifier observation tests
3. `swiftThreadingFatal` version gating can happen any time (independent)
4. SPM compilation validation should happen AFTER bridge code changes are complete (to avoid re-validation)
5. Android instrumented tests should be the LAST task (validates everything)

---

## 7. Testing Strategy

### Existing Test Infrastructure

**fuse-library example project** (`examples/fuse-library/`):
- `FuseLibraryTests/ObservationTests.swift` -- 14 tests: property CRUD (7) + ObservationVerifier bridge tests (7)
- `ObservationTrackingTests/ObservationTrackingTests.swift` -- 7 tests: macOS-only `withObservationTracking` verification
- `ObservationVerifier.swift` -- Test helper that runs `withObservationTracking` in native Swift code, callable from transpiled Kotlin
- `Counter`, `Parent`, `MultiTracker` model types -- `@Observable` classes for testing

**TCA fork** (`forks/swift-composable-architecture/Tests/`):
- `AndroidParityTests.swift` -- Existing tests for TCA patterns on Android (Store, effects, bindings, cancellation)

### Test Plan for Phase 1

**Unit tests (macOS, `swift test`):**
- Verify `ObservationRecording` frame stack: push/pop, nested frames, thread isolation
- Verify `ObservationRegistrar` willSet suppression when `isEnabled == true`
- Verify `ObservationRegistrar` willSet fires when `isEnabled == false`
- Verify `recordAccess` captures replay and trigger closures correctly
- Verify `stopAndObserve` replays closures inside `withObservationTracking`
- Verify sequential observation cycles re-register independently

**Integration tests (Android emulator, `skip test`):**
- Single property mutation -> exactly one recomposition (OBS-01, OBS-03, OBS-14)
- Bulk mutations coalesce into single update (OBS-15)
- Nested parent/child views track independently (OBS-05)
- ViewModifier bodies participate in tracking (OBS-06)
- `@ObservationIgnored` suppresses tracking (OBS-17)
- Sequential observation cycles each fire (OBS-11)
- Bridge initialization succeeds and sets `isEnabled` (OBS-25)
- `swiftThreadingFatal` symbol resolves (OBS-28)

**SPM compilation tests:**
- Each of the 14 forks resolves and compiles for Android (`skip android build` or equivalent)
- Full fuse-library example builds and runs tests

### Test Location

New bridge-specific tests should go in `examples/fuse-library/Tests/FuseLibraryTests/` alongside existing `ObservationTests.swift`. The `ObservationVerifier` pattern (native Swift callable from transpiled Kotlin) is the correct pattern for bridge tests.

---

## 8. File Change Map

### Files Requiring Code Changes

| File | Change | Requirements |
|------|--------|-------------|
| `forks/skip-ui/Sources/SkipUI/SkipUI/View/ViewModifier.swift` | Add `ViewObservation.startRecording?()` before and `ViewObservation.stopAndObserve?()` after body eval in `Evaluate()` | OBS-06 |
| `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` | Modify ViewObservation init block to log/fatal on nativeEnable() failure instead of silent catch | OBS-04 |
| `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` | (a) Add MainActor dispatch to triggerSingleUpdate onChange path, (b) Version-gate swiftThreadingFatal with `#if !swift(>=6.3)`, (c) Add diagnostics API hooks | OBS-01, OBS-28, diagnostics decision |
| `forks/swift-perception/Sources/PerceptionCore/Perception/PerceptionRegistrar.swift` | Verify/ensure Android passthrough to ObservationRegistrar | OBS-29 |
| `forks/swift-perception/Sources/PerceptionCore/PerceptionTracking.swift` | Verify/ensure withPerceptionTracking delegates to withObservationTracking on Android | OBS-30 |
| `examples/fuse-library/Sources/FuseLibrary/ObservationVerifier.swift` | Add bridge-specific verification methods (coalescing, nested views, modifier tracking) | Testing |
| `examples/fuse-library/Tests/FuseLibraryTests/ObservationTests.swift` | Add bridge-specific test cases | Testing |

### Files Requiring Verification Only (No Changes Expected)

| File | What to Verify |
|------|---------------|
| `forks/skip-android-bridge/Sources/SkipAndroidBridge/ObservationModule.swift` | Correctly imports native Observation |
| `forks/swift-composable-architecture/.../ObservationStateRegistrar.swift` | Android registrar selection works |
| `forks/swift-composable-architecture/.../ObservableState.swift` | Android Observable conformance |
| `forks/swift-composable-architecture/.../Store.swift` | Bridge registrar wiring |
| All 14 `forks/*/Package.swift` | Compile for Android |

---

## 9. Kotlin Rendering Path (Research Task)

The context decision explicitly requires researching the Kotlin side. Key questions:

1. **Where is `Swift_composableBody` generated?** -- By the `skipstone` build plugin, in `.build/plugins/outputs/`. These are generated JNI functions that Kotlin calls to evaluate Swift view bodies.

2. **What does the Kotlin `@Composable` wrapper look like?** -- It calls `Swift_composableBody()` which eventually invokes `View.Evaluate()`. The generated code is in the build output, not in source.

3. **Thread model:** Compose typically runs composition on the main thread, but recomposition can be scheduled differently. Need to verify that `Evaluate()` (and therefore `startRecording`/`stopAndObserve`) always runs on the same thread within a single evaluation.

4. **MutableState snapshot system:** When `BridgeObservationSupport.access()` calls `Java_access(index)`, this reads the `MutableStateBacking` counter inside the Compose snapshot system. Need to verify this read registers a Compose dependency so the composable recomposes when the counter changes.

5. **ViewObservation as Kotlin object:** The `// SKIP DECLARE: object ViewObservation` makes it a Kotlin singleton. The init block runs on first access. Need to verify the native library load (System.loadLibrary) happens before the first `Evaluate()` call.

**How to research:** Build the fuse-library example for Android (`make android-build`), then inspect `.build/plugins/outputs/` for the generated Kotlin/bridge code. Alternatively, search the skip-ui and skip-bridge source for `Swift_composableBody` generation patterns.

---

## 10. Plan Structure Recommendation

Based on the analysis, Phase 1 naturally splits into two plans:

### Plan 01-01: Bridge Implementation & Verification
**Focus:** Get the observation bridge working end-to-end
- Research Kotlin rendering path (decision prerequisite)
- Fix ViewModifier.Evaluate() observation hooks (OBS-06)
- Implement onChange main thread dispatch (decision)
- Implement bridge init failure detection (OBS-04)
- Version-gate swiftThreadingFatal (OBS-28)
- Add diagnostics API (decision)
- Verify PerceptionRegistrar passthrough (OBS-29, OBS-30)
- Write and run macOS unit tests for bridge internals
- Write and run Android integration tests for observation semantics

### Plan 01-02: SPM Compilation & Full Validation
**Focus:** All 14 forks compile, all requirements verified
- Validate SPM configuration for all 14 forks (SPM-01 through SPM-06)
- Build full dependency graph for Android
- Run fuse-library example on Android emulator
- Verify all 30 OBS requirements pass (many are test-only)
- Stress test high-frequency mutations
- Validate no iOS regressions (`swift test` on macOS)

---

## 11. Open Questions for Planning

1. **Is the Android emulator environment already configured?** -- Need to verify with `skip doctor --native` and `skip devices`. If not, setup is a prerequisite task.

2. **How to inspect generated Kotlin bridge code?** -- The skipstone-generated code in `.build/plugins/outputs/` is the key to understanding the Kotlin rendering path. Is it available from a previous build?

3. **Should diagnostics API be in Plan 01-01 or 01-02?** -- It is an opt-in feature, not a correctness requirement. Could be deferred to 01-02 if 01-01 is large.

4. **OBS-18 and OBS-20 (optional observable, bindings) -- how deep to go?** -- These are primarily SwiftUI patterns that depend on skip-ui's implementation. Basic bridge-level verification (the observation tracking works) is Phase 1; full SwiftUI behavior testing is Phases 4-5.

5. **PerceptionRegistrar passthrough -- new code or existing?** -- Need to read the swift-perception fork more carefully. If `#if canImport(Observation)` already delegates, this may be test-only.

---

## Sources

### Primary (Direct Code Analysis, HIGH Confidence)
- `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` -- Core bridge implementation (302 lines)
- `forks/skip-android-bridge/Sources/SkipAndroidBridge/ObservationModule.swift` -- Native Observation wrapper (23 lines)
- `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` -- ViewObservation struct + Evaluate() hooks
- `forks/skip-ui/Sources/SkipUI/SkipUI/View/ViewModifier.swift` -- ViewModifier.Evaluate() (missing hooks)
- `forks/skip-ui/Package.swift` -- SKIP_BRIDGE conditional dependencies
- `forks/skip-android-bridge/Package.swift` -- Bridge package dependencies
- `forks/swift-composable-architecture/.../ObservationStateRegistrar.swift` -- Android registrar wiring
- `forks/swift-perception/.../PerceptionRegistrar.swift` -- Perception bridge code
- `examples/fuse-library/Sources/FuseLibrary/ObservationVerifier.swift` -- Test helper pattern
- `examples/fuse-library/Tests/FuseLibraryTests/ObservationTests.swift` -- Existing observation tests
- `examples/fuse-library/Package.swift` -- Example project configuration

### Planning Documents (HIGH Confidence)
- `.planning/phases/01-observation-bridge/01-CONTEXT.md` -- 11 implementation decisions
- `.planning/REQUIREMENTS.md` -- 36 requirements for this phase
- `.planning/ROADMAP.md` -- Phase structure and success criteria
- `.planning/STATE.md` -- Current project state
- `.planning/PROJECT.md` -- Project context and constraints

### Research Documents (HIGH Confidence)
- `.planning/research/ARCHITECTURE.md` -- System architecture analysis
- `.planning/research/PITFALLS.md` -- 15 domain pitfalls with mitigations
- `.planning/research/STACK.md` -- Technology stack details
- `.planning/research/FEATURES.md` -- Feature landscape and priorities
- `.planning/research/SUMMARY.md` -- Research summary

### Codebase Analysis (HIGH Confidence)
- `.planning/codebase/ARCHITECTURE.md` -- Codebase architecture
- `.planning/codebase/CONCERNS.md` -- Known issues and risks
- `.planning/codebase/TESTING.md` -- Test framework and patterns

---

*Phase: 01-observation-bridge*
*Research completed: 2026-02-21*
