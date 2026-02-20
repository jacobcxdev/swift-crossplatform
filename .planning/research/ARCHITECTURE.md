# Architecture Patterns

**Domain:** Cross-platform Swift framework — Observation bridge fix and TCA Android integration
**Researched:** 2026-02-20

## Recommended Architecture

The observation bridge fix requires coordinated changes across three layers: **skip-android-bridge** (Swift-side recording/replay), **skip-ui** (Compose-side hook invocation), and **swift-composable-architecture** (registrar wiring). The architecture already exists in partially-implemented form — the work is completing the integration, not designing from scratch.

### System Diagram

```
iOS Path (working):
  SwiftUI body eval
    -> withObservationTracking { body() } onChange: { scheduleRerender() }
    -> access() records keypath
    -> withMutation() fires onChange ONCE
    -> single re-render

Android Path (to be fixed):
  Compose recomposition
    -> Evaluate() in skip-ui/View.swift
      -> ViewObservation.startRecording()           [skip-ui Kotlin -> JNI -> skip-android-bridge Swift]
      -> body() evaluation (accesses @Observable state)
        -> ObservationRegistrar.access()             [skip-android-bridge Swift]
          -> if isRecording: recordAccess(replay:, trigger:)
          -> bridgeSupport.access() -> Java_access() [JNI -> MutableStateBacking.access()]
          -> registrar.access()                      [native Swift Observation]
      -> ViewObservation.stopAndObserve()            [JNI -> skip-android-bridge Swift]
        -> withObservationTracking { replay closures } onChange: { triggerSingleUpdate() }
        -> triggerSingleUpdate() -> Java_update(0)   [JNI -> MutableStateBacking.update()]
        -> Compose sees single MutableState change -> recomposition
    -> StateTracking.pushBody()/popBody()            [skip-model Lite-mode tracking, parallel path]
```

### Component Boundaries

| Component | Responsibility | Communicates With | Fork Status |
|-----------|---------------|-------------------|-------------|
| **skip-android-bridge/Observation.swift** | Record-replay pattern: captures access() calls during body eval, replays them inside withObservationTracking, bridges onChange to single MutableState update | skip-ui (via JNI exports), MutableStateBacking (via JNI calls), native Swift Observation (via ObservationModule) | **Forked** — contains the core fix implementation |
| **skip-ui/View.swift (Evaluate)** | Calls startRecording/stopAndObserve around body evaluation in Fuse mode | skip-android-bridge (via ViewObservation JNI), skip-model StateTracking | **Forked** — ViewObservation + Evaluate() hooks already present |
| **skip-ui/ViewObservation** | Kotlin object that loads native bridge library, exposes JNI external funs | skip-android-bridge JNI exports | **Forked** — init block auto-detects bridge presence |
| **swift-composable-architecture/ObservationStateRegistrar** | Selects correct registrar per platform: PerceptionRegistrar (iOS <17), Observation.ObservationRegistrar (visionOS), SkipAndroidBridge.Observation.ObservationRegistrar (Android) | skip-android-bridge (Android), swift-perception (iOS <17), Observation (iOS 17+/visionOS) | **Forked** — `#if os(Android)` already wired |
| **swift-composable-architecture/Store** | Holds _$observationRegistrar, drives state access/mutation for views | ObservationStateRegistrar, skip-android-bridge | **Forked** — Android registrar already selected |
| **swift-composable-architecture/ObservableState** | Protocol that TCA state types conform to; on Android conforms to Observable (not Perceptible) | ObservationStateRegistrar | **Forked** — `#if os(Android)` uses Observable |
| **skip-model/MutableStateBacking** | Kotlin-side Compose state wrapper; access(index)/update(index) drive recomposition | skip-android-bridge BridgeObservationSupport (via JNI) | **NOT forked** — used as-is from upstream skip-model |
| **skip-model/StateTracking** | Lite-mode body tracking (pushBody/popBody); runs in parallel with Fuse observation | skip-ui Evaluate() | **NOT forked** — used as-is |

### Key Architectural Insight: The Fix Is Already 90% Implemented

The codebase already contains:

1. **ObservationRecording** (skip-android-bridge) — full record-replay implementation with thread-local stack, frame management, and withObservationTracking replay
2. **ViewObservation** (skip-ui) — Kotlin object with JNI hooks that calls startRecording/stopAndObserve
3. **Evaluate()** (skip-ui) — already calls `ViewObservation.startRecording?()` before body eval and `ViewObservation.stopAndObserve?()` after
4. **ObservationRegistrar** (skip-android-bridge) — already checks `isRecording` in access() and records replay closures
5. **BridgeObservationSupport.triggerSingleUpdate()** — already implemented to call Java_update(0) for single recomposition
6. **willSet suppression** — when `isEnabled` is true, bridgeSupport.willSet() is suppressed (preventing per-mutation counter increments)
7. **JNI exports** — nativeEnable, nativeStartRecording, nativeStopAndObserve all implemented with @_cdecl

The remaining work is **integration testing and debugging** — verifying the end-to-end flow actually prevents the infinite recomposition loop with TCA's high-frequency mutations.

## Data Flow

### Observation Cycle (Fixed Architecture)

**Phase 1: Recording (during body evaluation)**

```
1. Compose calls Evaluate() on a View
2. Evaluate() calls ViewObservation.startRecording()
   -> JNI -> nativeStartRecording() -> ObservationRecording.startRecording()
   -> Pushes new Frame onto thread-local stack
3. body property is accessed
   -> TCA Store.state accessor calls _$observationRegistrar.access(self, keyPath: \.currentState)
   -> ObservationRegistrar.access() checks ObservationRecording.isRecording == true
   -> Records replay closure: { registrar.access(subject, keyPath: keyPath) }
   -> Records trigger closure: { bridgeSupport.triggerSingleUpdate() } (only first access per frame)
   -> Also calls bridgeSupport.access() -> Java_access(index) [registers Compose snapshot dependency]
   -> Also calls registrar.access() [registers native Observation dependency]
4. Body evaluation completes with rendered content
```

**Phase 2: Observation Setup (after body evaluation)**

```
5. Evaluate() calls ViewObservation.stopAndObserve()
   -> JNI -> nativeStopAndObserve() -> ObservationRecording.stopAndObserve()
   -> Pops Frame from stack
   -> Calls withObservationTracking({
        for closure in replayClosures { closure() }  // Re-registers access on all observed keypaths
      }, onChange: {
        trigger()  // = bridgeSupport.triggerSingleUpdate()
      })
   -> Native Observation now tracks all accessed keypaths
   -> onChange will fire ONCE on next mutation, then auto-cancel
```

**Phase 3: Mutation (state change)**

```
6. User action -> TCA Store.send(action)
7. Reducer mutates state
8. ObservationRegistrar.withMutation() is called
   -> isEnabled == true, so bridgeSupport.willSet() is SUPPRESSED
   -> registrar.withMutation() fires native Observation notification
9. Native Observation's onChange fires (from step 5)
   -> Calls triggerSingleUpdate()
   -> Java_update(0) -> MutableStateBacking.update(0) -> Compose MutableState incremented ONCE
10. Compose schedules recomposition
11. Go to step 1 (new Evaluate() cycle)
```

**Why This Fixes the Infinite Loop:**

- **Before fix:** Every withMutation() call incremented MutableStateBacking counter directly via bridgeSupport.willSet(). TCA's _$id UUID changes cause N mutations per state assignment, producing N counter increments and N recompositions.
- **After fix:** willSet() is suppressed when isEnabled=true. Only withObservationTracking's onChange fires, and it fires ONCE per observation cycle regardless of how many mutations occurred. One onChange -> one triggerSingleUpdate() -> one MutableState increment -> one recomposition.

### Data Flow Through TCA on Android

```
View (SwiftUI syntax)
  |
  v
Store<State, Action> [holds SkipAndroidBridge.Observation.ObservationRegistrar]
  |
  +-> .state accessor -> registrar.access() -> recording + JNI + native tracking
  |
  +-> .send(action) -> Reducer -> state mutation -> registrar.withMutation()
  |                                                    -> native Observation onChange
  |                                                    -> triggerSingleUpdate()
  |                                                    -> Compose recomposition
  v
Evaluate() [wraps body with startRecording/stopAndObserve]
  |
  v
Compose Renderable.Render()
```

## Patterns to Follow

### Pattern 1: Dual-Path Observation (Bridge + Native)

**What:** The ObservationRegistrar in skip-android-bridge maintains two parallel observation paths: JNI bridge to Compose MutableState AND native Swift Observation tracking.

**When:** Always on Android in Fuse mode. The bridge path handles Compose recomposition; the native path enables withObservationTracking's record-replay.

**Why this matters:** The record-replay pattern depends on native `withObservationTracking` working correctly on Android. `libswiftObservation.so` ships with the Swift Android SDK, so this is supported. The bridge path (BridgeObservationSupport) handles the actual Compose recomposition triggering.

```swift
// In ObservationRegistrar.access():
if ObservationRecording.isRecording {
    // Record for later replay inside withObservationTracking
    ObservationRecording.recordAccess(replay: { ... }, trigger: { ... })
}
bridgeSupport.access(subject, keyPath: keyPath)  // JNI -> Compose snapshot
registrar.access(subject, keyPath: keyPath)       // Native Observation tracking
```

### Pattern 2: Thread-Local Recording Stack

**What:** ObservationRecording uses pthread thread-local storage for a stack of recording frames, supporting nested Evaluate() calls.

**When:** Nested SwiftUI views where a parent body contains child Fuse-bridged views. Each Evaluate() pushes/pops its own frame.

**Why:** Compose can invoke Evaluate() on different threads concurrently. Thread-local storage ensures frames don't cross-contaminate between concurrent recompositions.

### Pattern 3: Conditional Compilation for Platform Divergence

**What:** `#if os(Android)` and `#if !os(visionOS) && !os(Android)` gates to select the correct registrar and protocol conformances.

**When:** Every file that touches observation machinery.

**Critical pattern in TCA:**
```swift
// ObservableState protocol
#if !os(visionOS) && !os(Android)
  public protocol ObservableState: Perceptible { ... }  // Uses swift-perception backport
#else
  public protocol ObservableState: Observable { ... }    // Uses native Observation
#endif

// ObservationStateRegistrar
#if !os(visionOS) && !os(Android)
  let registrar = PerceptionRegistrar()
#elseif os(Android)
  let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
#else
  let registrar = Observation.ObservationRegistrar()
#endif
```

### Pattern 4: One-Way Enable Flag

**What:** `ObservationRecording.isEnabled` is set once when ViewObservation loads the native bridge library. It gates willSet suppression.

**When:** App startup. The ViewObservation Kotlin object's init block calls nativeEnable() which sets isEnabled = true.

**Why:** This is a graceful degradation mechanism. If the native bridge fails to load (no Fuse mode), the flag stays false and the original counter-based willSet behavior continues (Lite mode compatibility).

## Anti-Patterns to Avoid

### Anti-Pattern 1: App-Level Observation Wrapping

**What:** Wrapping view bodies with `withPerceptionTracking` at the app or view level.
**Why bad:** Rejected by project architecture decision. The fix must be at the bridge level (skip-android-bridge/skip-ui) for platform parity. App-level wrappers would need to be added to every TCA view and would break the abstraction that Skip provides.
**Instead:** The bridge-level fix in Evaluate() + ObservationRecording handles all views uniformly.

### Anti-Pattern 2: Counter-Based Observation for TCA

**What:** Relying on MutableStateBacking integer counter increments per withMutation() call.
**Why bad:** TCA generates high-frequency mutations (UUID-based _$id changes on every state assignment). Counter-per-mutation causes O(N) recompositions instead of O(1).
**Instead:** The record-replay pattern collapses all mutations in a cycle to a single onChange -> single triggerSingleUpdate().

### Anti-Pattern 3: Modifying skip-model or MutableStateBacking

**What:** Forking skip-model to change the counter-based observation mechanism.
**Why bad:** skip-model is the Lite-mode observation layer. Changing it would break Lite mode apps. Marc's guidance: "Skip Lite layer must remain free of compiled Swift dependencies."
**Instead:** The fix lives entirely in Fuse-mode components (skip-android-bridge + skip-ui). StateTracking.pushBody()/popBody() continues to run in parallel without interference.

### Anti-Pattern 4: Using PerceptionRegistrar on Android

**What:** Using swift-perception's PerceptionRegistrar instead of SkipAndroidBridge.Observation.ObservationRegistrar on Android.
**Why bad:** PerceptionRegistrar is a backport for iOS <17 that wraps Observation when available. On Android, the bridge registrar is needed to perform JNI bridging to Compose MutableState. Native Observation alone cannot trigger Compose recomposition.
**Instead:** The TCA fork correctly uses `SkipAndroidBridge.Observation.ObservationRegistrar()` on Android.

## Component Change Map

### Where Changes Live

| Component | Needs Changes? | What Changes | Why |
|-----------|---------------|--------------|-----|
| **skip-android-bridge** (fork) | Likely minimal | ObservationRecording and BridgeObservationSupport already implemented. May need debugging/tuning of edge cases (e.g., async mutation timing, multiple observables per view) | Core recording infrastructure exists |
| **skip-ui** (fork) | Likely minimal | ViewObservation + Evaluate() hooks already present. May need adjustment if stopAndObserve timing relative to StateTracking is wrong | Hook points exist |
| **swift-composable-architecture** (fork) | Already done | ObservationStateRegistrar uses SkipAndroidBridge registrar; ObservableState conforms to Observable; Store uses bridge registrar | Platform-conditional wiring complete |
| **swift-perception** (fork) | None for bridge fix | Android code paths use native Observation, not Perception backport | Perception is iOS <17 only |
| **swift-navigation** (fork) | Possibly | Navigation views that use observation may need `#if os(Android)` guards for Perception.Bindable usage | Secondary — test after core fix works |
| **swift-sharing** (fork) | Possibly | SharedReader/Shared observation may need bridge awareness | Secondary — test after core fix works |
| **swift-dependencies** (fork) | None | Pure dependency injection, no observation involvement | No observation code |
| **Example apps** | Yes | Integration testing, verification that TCA counter/navigation work on Android | Validation layer |

### Layering Principle

```
Layer 1 (Foundation):  skip-android-bridge  [observation recording + JNI bridge]
Layer 2 (UI):          skip-ui              [ViewObservation hooks in Evaluate()]
Layer 3 (State Mgmt):  swift-composable-architecture  [registrar wiring]
Layer 4 (Support):     swift-perception, swift-navigation, swift-sharing  [platform guards]
Layer 5 (App):         example apps         [integration testing]
```

Changes flow bottom-up. Layer 1 must be correct before Layer 2 can be validated, etc.

## Build Order and Dependency Chain

### Dependency Graph (Fuse Mode, Observation-Relevant)

```
skip-android-bridge
  depends on: skip-bridge, skip-foundation, swift-jni, swift-android-native

skip-ui (with SKIP_BRIDGE=1)
  depends on: skip-model, skip-bridge
  NOTE: skip-ui does NOT depend on skip-android-bridge in Package.swift
        ViewObservation loads bridge library at RUNTIME via JNI System.loadLibrary()

swift-perception
  depends on: xctest-dynamic-overlay

swift-composable-architecture
  depends on: skip-android-bridge (Android), swift-perception, swift-navigation,
              swift-sharing, swift-dependencies, combine-schedulers,
              swift-case-paths, swift-custom-dump, swift-identified-collections,
              OpenCombine, skip-bridge, swift-jni, skip-fuse-ui

swift-navigation
  depends on: swift-perception, swift-case-paths, xctest-dynamic-overlay

swift-sharing
  depends on: swift-dependencies, swift-perception, combine-schedulers,
              swift-navigation, OpenCombine

combine-schedulers
  depends on: xctest-dynamic-overlay, OpenCombine
```

### Recommended Build/Test Order

```
Phase 1: Foundation (no inter-fork dependencies)
  1. skip-android-bridge  — verify ObservationRecording works in isolation
     Test: Unit test that startRecording -> access -> stopAndObserve sets up
           withObservationTracking correctly

Phase 2: UI Hooks
  2. skip-ui  — verify Evaluate() calls ViewObservation hooks
     Test: Compose test that a simple @Observable view body triggers
           startRecording/stopAndObserve correctly

Phase 3: TCA Integration
  3. swift-composable-architecture  — verify Store with bridge registrar
     Test: AndroidParityTests with simple counter reducer

Phase 4: Full Stack
  4. Example fuse-app  — end-to-end TCA on Android
     Test: Counter increment, navigation, high-frequency mutation without infinite loop
```

### Version Coordination Strategy

All 14 forks use the `flote/service-app` branch. They coordinate via:

1. **Branch pinning:** TCA's Package.swift points to `branch: "flote/service-app"` for all jacobcxdev forks
2. **Exact version for upstream deps:** swift-case-paths, swift-concurrency-extras, xctest-dynamic-overlay use semver from upstream
3. **Range for Skip deps:** skip-bridge, skip-android-bridge, swift-jni use `"0.x.y"..<"2.0.0"` ranges

**Coordination risk:** Changes to skip-android-bridge's ObservationRegistrar API would break TCA's import. The current API is stable (access/willSet/didSet/withMutation match the Observation.ObservationRegistrar protocol), so this risk is low.

**Tagging strategy (post-fix):** Once the observation fix is validated:
1. Tag skip-android-bridge with a version
2. Tag skip-ui with a version
3. Update TCA Package.swift to pin tagged versions instead of branch
4. Tag all downstream forks
5. Document in FORKS.md

## Scalability Considerations

| Concern | Current (single TCA app) | At 10+ views deep | At 100+ observables |
|---------|-------------------------|-------------------|---------------------|
| Recording frame depth | 1-3 frames typical | Thread-local stack handles arbitrary nesting | Stack depth proportional to view hierarchy depth, not observable count |
| JNI call frequency | 1 access per observable per render | Linear: N accesses per body eval | N accesses recorded, replayed in single withObservationTracking call |
| Recomposition triggers | 1 per observation cycle | 1 per observation cycle (design goal) | 1 per observation cycle (onChange fires once, auto-cancels) |
| Thread safety | DispatchSemaphore on BridgeObservationSupport | pthread TLS for recording; semaphore for JNI calls | Contention on semaphore if many concurrent recompositions; consider switching to os_unfair_lock if profiling shows bottleneck |
| Memory | One FrameStack per thread, one BridgeObservationSupport per registrar | FrameStack cleanup via pthread destructor | AnyKeyPath -> Int dictionary in BridgeObservationSupport grows with unique keypaths; bounded by number of @Observable properties |

## Sources

- `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` — PRIMARY: full ObservationRecording + BridgeObservationSupport implementation (HIGH confidence)
- `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` — PRIMARY: ViewObservation + Evaluate() with hooks (HIGH confidence)
- `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift` — PRIMARY: platform-conditional registrar selection (HIGH confidence)
- `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservableState.swift` — PRIMARY: _$id UUID mutation pattern (HIGH confidence)
- `forks/swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` — PRIMARY: Store registrar wiring (HIGH confidence)
- `forks/swift-composable-architecture/Package.swift` — Dependency graph (HIGH confidence)
- `forks/skip-ui/Package.swift` — SKIP_BRIDGE conditional dependencies (HIGH confidence)
- `forks/skip-android-bridge/Package.swift` — Skip foundation dependencies (HIGH confidence)
- `.planning/PROJECT.md` — Project context and decisions (HIGH confidence)
- `.planning/codebase/ARCHITECTURE.md` — Existing architecture analysis (HIGH confidence)
- `.planning/codebase/CONCERNS.md` — Root cause analysis (HIGH confidence)
- `docs/skip/bridging.md` — Skip bridging reference (HIGH confidence)
- `docs/skip/modes.md` — Fuse vs Lite modes (HIGH confidence)

---

*Architecture analysis: 2026-02-20*
