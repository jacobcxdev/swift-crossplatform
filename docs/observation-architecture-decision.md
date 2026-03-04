# Observation Architecture Decision (2026-02-19)

## Decision: Use Perception as Unified Observation Layer, Native Observation in Fuse Mode

### Context

We're fixing an infinite recomposition loop on Android caused by skip-android-bridge's
counter-based ObservationRegistrar. Through investigation, we discovered:

1. Swift Observation runs NATIVELY on Android in Fuse mode (libswiftObservation.so ships with Android Swift SDK)
2. skip-model's observation was built for Lite (transpiled) mode where no Swift runtime exists
3. Fuse mode inherited the Lite infrastructure via a JNI bridge rather than using native Observation
4. The bridge's MutableStateBacking counter approach causes infinite loops with TCA's high-frequency mutations
5. The generated bridge code (`Swift_composableBody`) evaluates view bodies WITHOUT any observation tracking wrapper

### Root Cause (Confirmed)

The generated `Swift_composableBody` (in SkipBridgeGenerated/*_Bridge.swift) does:
```swift
let body = peer_swift.value.body  // RAW - no withObservationTracking wrapping
```

On iOS, SwiftUI wraps body eval with `withObservationTracking { body() } onChange: { rerender() }`.
On Android via Skip, there's NO equivalent wrapping. The only recomposition driver is
MutableStateBacking's integer counters, which increment on every withMutation() call without deduplication.

TCA's subscribeToDidSet fires withMutation for every state assignment (UUID-based _$id always
changes), creating thousands of counter increments → thousands of recompositions.

### Architecture Decision

#### Fuse Mode (Our App — Immediate)

```
TCA Store → PerceptionRegistrar → native Observation.ObservationRegistrar
                                    (works natively on Android)

View rendering: withObservationTracking/withPerceptionTracking {
                  body()
                } onChange: {
                  composeMutableState += 1  ← single Compose recomposition trigger
                }
```

- TCA uses PerceptionRegistrar on ALL platforms (drop #elseif os(Android) bridge registrar)
- PerceptionRegistrar delegates to native Observation on Android (same as iOS 17+)
- A Compose subscriber wraps body eval, bridging Observation onChange → Compose MutableState
- The subscriber is NOT in TCA or app code — it's in the bridge/view layer

#### Both Modes (Upstream — Long-term)

Perception serves as the unified API contract:

| Platform        | PerceptionRegistrar Backend                           |
|-----------------|------------------------------------------------------|
| iOS 17+         | Native Observation.ObservationRegistrar               |
| iOS 13-16       | Perception's own backport implementation              |
| Android Fuse    | Native Observation.ObservationRegistrar (same as iOS) |
| Android Lite    | skip-model MutableState backend (needs building)      |

For Lite mode, two options:
A) Make Perception transpilable to Kotlin (significant work)
B) Compile Perception as Fuse module, expose to Lite via Skip bridge (hybrid approach — Skip recommends mixing modes)

### Why Not skip-model's Observation?

- Counter-based, not value-based (every withMutation triggers recomposition)
- "Skip does not support calls to the generated access(keyPath:) and withMutation(keyPath:_:) functions"
- Deferred tracking (StateTracking) can lose initial mutations
- No withObservationTracking equivalent
- Built for Lite mode where Swift runtime doesn't exist — unnecessary in Fuse mode

### Why Not Native Observation Directly (Without Perception)?

- Works fine in Fuse mode, but no path to Lite mode support
- TCA uses PerceptionRegistrar everywhere for iOS backward compat
- Perception is the abstraction that bridges both worlds
- In Fuse mode, Perception just delegates to native Observation anyway — zero overhead

### Implementation Plan

#### Step 1: TCA Fork — Use PerceptionRegistrar on Android

In Store.swift and ObservationStateRegistrar.swift, change:
```swift
// FROM:
#if !os(visionOS) && !os(Android)
    let registrar = PerceptionRegistrar(...)
#elseif os(Android)
    let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
#else
    let registrar = Observation.ObservationRegistrar()
#endif

// TO:
#if !os(visionOS)
    let registrar = PerceptionRegistrar(...)
#else
    let registrar = Observation.ObservationRegistrar()
#endif
```

Note: Keep `import SkipAndroidBridge` for `swiftThreadingFatal` crash fix (needed for libswiftObservation.so).

#### Step 2: Build the Compose Subscriber

The subscriber wraps view body evaluation with withPerceptionTracking and bridges
onChange to a Compose MutableState counter. This is the "Observing" pattern but at the
BRIDGE level, not app level.

Location options (in order of preference):
1. skip-android-bridge fork — modify ObservationRegistrar to use withPerceptionTracking internally
2. skip-fuse-ui fork — modify Kotlin-side @Composable rendering to wrap JNI body call
3. Skip build plugin — modify generated Swift_composableBody (highest complexity)

The Observing.swift.bak in our app (Sources/ServiceApp/Observing.swift.bak) contains
the working pattern. It needs to be elevated to the bridge level.

#### Step 3: Verify on Both Platforms

- Build via Xcode (deploys to both iOS sim + Android emu)
- Verify no infinite loop on Android (logcat)
- Verify iOS behavior unchanged
- Verify items appear after Add button tap

### Key Files

- TCA Store registrar: `swift-composable-architecture/.../Store.swift` lines 119-125
- TCA ObservationStateRegistrar: `swift-composable-architecture/.../ObservationStateRegistrar.swift`
- Bridge registrar: `.build/checkouts/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`
- MutableStateBacking: `.build/checkouts/skip-model/Sources/SkipModel/MutableStateBacking.swift`
- Generated bridges: `.build/plugins/outputs/service-app/ServiceApp/destination/skipstone/SkipBridgeGenerated/`
- Observing pattern: `Sources/ServiceApp/Observing.swift.bak`
- swift-perception fork: `/Users/jacob/Developer/src/github/flote-works/swift-perception/`
- Full analysis: `.claude/observation-bridge-analysis.md`

### Current State

- Store.swift: ORIGINAL state (uses bridge registrar on Android) — reverted from PerceptionRegistrar experiment
- ObservationStateRegistrar.swift: ORIGINAL state (uses bridge registrar on Android) — reverted
- Observing.swift: backed up as .bak — NOT active
- Task #3 "Fix root cause" is in_progress
- Task #4 "Verify fix" is pending

### Skip Maintainer Feedback (2026-02-19)

Discussed with Dan Fabulich and Marc Prud'hommeaux (Skip inventor) in Slack.

**Key takeaways**:
- skip-model is Lite (transpiled) — can't depend on swift-perception directly
- skip-ui is also Lite and depends on skip-model
- skip-fuse-ui depends on BOTH skip-ui (→ skip-model) AND skip-android-bridge
- skip-ui has `SKIP_BRIDGE` conditional in Package.swift (lines 20-30) for Fuse-mode-only deps
- Dan suggested: make skip-ui depend on swift-perception only in Fuse mode via SKIP_BRIDGE
- Marc endorsed fork approach: "best first step" to get familiar with Lite/Fuse interplay
- For upstream: Fuse-mode fix gated behind SKIP_BRIDGE, Lite mode untouched

**Full dependency chain**:
```
service-app → skip-fuse-ui → skip-ui → skip-model (Lite, Kotlin-side MutableStateBacking)
                            → skip-android-bridge (Swift-side JNI to MutableStateBacking)
```

### Strategic Layering

1. **service-app** (ship now): Fork-only fixes acceptable
2. **TCA + deps** (upstream to pointfreeco): Depends on upstream Skip having proper observation
3. **Skip + deps** (upstream to skip-tools): Must maintain Lite compat for upstream acceptance

Upstream order: Skip → TCA → service-app drops forks.

### Skip Modes Reference

- Fuse (native): Swift compiles natively for Android, full Swift runtime available
- Lite (transpiled): Swift → Kotlin, no Swift runtime
- Skip recommends Fuse where possible, supports mixing both modes in one app
- Docs: https://skip.dev/docs/modes/
- skip-model API support: https://skip.dev/docs/modules/skip-model/#api-support
