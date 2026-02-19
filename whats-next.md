<original_task>
Fix the infinite recomposition loop on Android when using TCA (The Composable Architecture) with Skip Fuse mode. The app works correctly on iOS but enters an infinite body evaluation loop on Android due to how Skip bridges Swift Observation to Compose's recomposition system.
</original_task>

<work_completed>

## Root Cause Identified and Confirmed

The root cause is in Skip's generated bridge code. For each view, the skipstone build plugin generates a `Swift_composableBody` JNI function that evaluates the view body **without any observation tracking wrapper**:

```swift
// .build/plugins/outputs/service-app/ServiceApp/destination/skipstone/SkipBridgeGenerated/ContentView_Bridge.swift
@_cdecl("Java_service_app_ContentView_Swift_1composableBody")
public func ContentView_Swift_composableBody(...) -> JavaObjectPointer? {
    let peer_swift: SwiftValueTypeBox<ContentView> = Swift_peer.pointee()!
    return SkipBridge.assumeMainActorUnchecked {
        let body = peer_swift.value.body  // ← RAW — no withObservationTracking
        return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
    }
}
```

On iOS, SwiftUI internally wraps body evaluation with `withObservationTracking { body() } onChange: { scheduleRerender() }` — fires once, auto-cancels, re-enters on next body eval. On Android, there's NO equivalent. The only recomposition driver is MutableStateBacking's integer counters (from skip-model, via skip-android-bridge), which increment on **every** `withMutation()` call without deduplication.

TCA's `@ObservableState` macro generates high-frequency `withMutation` calls (UUID-based `_$id` changes on every state assignment, `removeDuplicates()` never filters), causing thousands of counter increments → thousands of recompositions → infinite loop.

## Deep Investigation of Observation Architecture

Analyzed the full observation stack across multiple packages:

1. **skip-android-bridge** (`Observation.swift`): Bridge ObservationRegistrar that delegates to BOTH:
   - `bridgeSupport` (JNI → MutableStateBacking counters on Kotlin side)
   - `registrar` (native Swift Observation — but nobody subscribes to it)

2. **skip-model** (`MutableStateBacking.swift`): Kotlin-side `MutableList<MutableState<Int>>` counters. `access()` reads counter (registers Compose dependency), `update()` increments counter (triggers recomposition). Counter-based, not value-based — every update always triggers.

3. **skip-model** (`StateTracking.swift`): Manages bodyDepth and deferred tracking during view construction. Can lose initial mutations.

4. **swift-perception** (our fork at `/Users/jacob/Developer/src/github/flote-works/swift-perception/`): Complete backport of Swift Observation. Per-keypath tracking, `withPerceptionTracking` with fire-once onChange. Works natively on Android (pthread-based, no iOS deps for core).

5. **skip-fuse-ui** (`Fuse/Observation.swift`): Just re-exports: `@_exported import Observation` and `@_exported import SkipAndroidBridge`.

## Dependency Chain Mapped

The FULL Fuse-mode dependency chain:
```
service-app → skip-fuse-ui → skip-ui → skip-model (Lite/transpiled)
                            → skip-android-bridge → skip-bridge, swift-jni
```

**Critical insight**: skip-fuse-ui depends on BOTH skip-ui (Lite, which pulls in skip-model) AND skip-android-bridge. skip-model IS in the Fuse dependency graph — it comes through skip-ui. The Kotlin-side MutableStateBacking that receives JNI calls from skip-android-bridge lives in skip-model.

## Architecture Decision Reached

Use native Swift `withObservationTracking` (or `withPerceptionTracking`) to wrap body evaluation in Fuse mode. This matches iOS semantics exactly:
- One onChange per tracking scope
- Natural deduplication (fires once, auto-cancels)
- Compose MutableState counter only increments once per observation cycle

```
View body eval:   withObservationTracking {
                    body()                    ← tracks keypath accesses
                  } onChange: {
                    composeMutableState += 1  ← ONE Compose recomposition trigger
                  }
```

## Skip Maintainer Validation (Slack Thread — 2026-02-19)

Opened thread in Skip's Slack. Key participants: **Dan Fabulich** and **Marc Prud'hommeaux** (Skip inventor).

**Dan's key insights**:
- skip-model is Lite (transpiled) — can't directly depend on swift-perception
- skip-ui is also Lite and depends on skip-model
- skip-ui has a `SKIP_BRIDGE` section in Package.swift (lines 20-30) that adds conditional Fuse-mode dependencies
- Suggested two paths:
  1. Extend transpiler keypath support to make skip-model's `access(keyPath:)` work in Lite
  2. Make skip-ui depend on swift-perception only in Fuse mode via the `SKIP_BRIDGE` mechanism
- Noted keypaths are "partially supported" in Lite: works for `@Environment` keys and implicit closure params, but "✕ Other uses"

**Marc's key insights**:
- Confirmed Dan's analysis
- Acknowledged the limitation: "Many of our Observation limitations fall out of the fact that compiled Skip Fuse is built on top of transpiled Skip Lite"
- **Endorsed the fork approach**: "I do think this will be the best first step. If nothing else, it will get you familiarized with the interplay between the Lite and Fuse sides."

**skip-ui's SKIP_BRIDGE section** (the upstream integration point):
```swift
// .build/checkouts/skip-ui/Package.swift lines 20-30
if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    package.dependencies += [.package(url: "https://source.skip.tools/skip-bridge.git", "0.0.0"..<"2.0.0")]
    package.targets.forEach({ target in
        target.dependencies += [.product(name: "SkipBridge", package: "skip-bridge")]
    })
    package.products = package.products.map({ product in
        guard let libraryProduct = product as? Product.Library else { return product }
        return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
    })
}
```

## Strategic Layering Established

Three layers of work, with upstream dependencies flowing bottom-up:

1. **service-app** (primary deliverable): Ship the app. Fork-only fixes acceptable.
2. **TCA + deps** (upstream to pointfreeco): Make TCA 1.0 Skip-compatible. Depends on upstream Skip having proper observation.
3. **Skip + deps** (upstream to skip-tools): Fix observation in Fuse mode. Must maintain Lite compatibility for upstream acceptance.

Upstream order: Skip fixes first → TCA depends on upstream Skip → TCA upstream → service-app drops forks.

## Slack Reply Sent

Comprehensive reply sent to Dan/Marc covering:
- The specific root cause (Swift_composableBody without withObservationTracking)
- Native Observation works in Fuse mode, nobody's subscribing
- Fork plan for immediate fix
- SKIP_BRIDGE conditional as upstream path
- Asked about PR vs issue preference

## Analysis Documents Created

- `.claude/observation-bridge-analysis.md` — Full root cause, loop chain, skip-model vs swift-perception comparison, implementation paths
- `.claude/observation-architecture-decision.md` — Architecture decision, implementation plan, key files, current state

## Previous Experiment (Reverted)

Previously attempted switching TCA to PerceptionRegistrar + app-level Observing wrapper. User correctly rejected this — the plan mandates bridge-level fixes, not app-level workarounds. All changes reverted:
- Store.swift → back to bridge registrar on Android
- ObservationStateRegistrar.swift → back to bridge registrar on Android
- Observing.swift → renamed to .bak (not active)

</work_completed>

<work_remaining>

## Immediate: Fork-Based Fix (for service-app)

### Step 1: Set Up Local Skip Dev Environment
- Clone/fork skip-android-bridge, skip-fuse-ui, and potentially skip-ui
- Set up so service-app uses local checkouts of these packages
- Dan recommended this: "you'd want a dev environment in which you'd built your own local copy of Skip"

### Step 2: Understand the Kotlin Side
- **NOT YET DONE**: We haven't examined the Kotlin-side code that calls `Swift_composableBody`
- Need to find where in skip-fuse-ui or skip-ui the `@Composable` function lives that invokes the JNI body eval
- This is where the `withObservationTracking` wrapper (or its Compose equivalent) needs to go
- Search `.kt` files in skip-fuse-ui and skip-android-bridge for the Composable rendering path
- Specifically look for how `MutableStateBacking` counters are read during @Composable rendering

### Step 3: Implement the Compose Subscriber
The subscriber wraps body evaluation with `withObservationTracking` and bridges onChange → Compose MutableState. Three location options (in order of preference):

1. **skip-android-bridge fork** — Modify ObservationRegistrar to use withObservationTracking internally
   - access() still reads MutableState (for Compose dependency registration)
   - withMutation() becomes a no-op for Compose — native Observation handles notification
   - When Observation onChange fires, increment MutableState counter ONCE

2. **skip-fuse-ui fork** — Modify Kotlin-side @Composable rendering to wrap JNI body call
   - Closer to how iOS works (wrapping at view rendering level)
   - Requires modifying Kotlin code

3. **Skip build plugin (skipstone)** — Modify generated Swift_composableBody
   - Cleanest solution but highest complexity (forking the code generator)

The working pattern already exists in `Sources/ServiceApp/Observing.swift.bak`:
```swift
struct Observing<Content: View>: View {
    let content: () -> Content
    @State var token = 0
    var body: some View {
        let _ = token
        withPerceptionTracking(content, onChange: {
            Task { @MainActor in token += 1 }
        })
    }
}
```
This needs to be elevated to the bridge level.

### Step 4: TCA Fork Change
In Store.swift and ObservationStateRegistrar.swift, switch from bridge registrar to PerceptionRegistrar on Android:
```swift
// FROM:
#if !os(visionOS) && !os(Android)
    let registrar = PerceptionRegistrar(...)
#elseif os(Android)
    let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
// TO:
#if !os(visionOS)
    let registrar = PerceptionRegistrar(...)
```
**Note**: Whether this is needed depends on Step 3's approach. If the bridge-level fix wraps body eval with withObservationTracking, the bridge registrar's dual notification might still work (native Observation side would actually have a subscriber). But the counter-based side would still increment on every withMutation. Needs testing.

**Alternative**: Keep bridge registrar but disable the MutableStateBacking side (`bridgeSupport.willSet()` becomes no-op). Let native Observation + the new subscriber handle everything.

### Step 5: Verify
- Build via Xcode (deploys to both iOS sim + Android emu simultaneously)
- Verify no infinite loop on Android (check logcat)
- Verify iOS behavior unchanged
- Verify items appear after Add button tap
- Verify state changes propagate correctly (add item, toggle, etc.)

## Future: Upstream Path

### For Skip (layer 3)
- Implement the Fuse-mode observation fix gated behind `SKIP_BRIDGE` in skip-ui's Package.swift
- Ensure Lite mode is untouched (still uses skip-model)
- PR or issue to skip-tools — Marc endorsed this approach
- May need to coordinate with Skip team on the Kotlin-side Compose integration

### For TCA (layer 2)
- Once Skip upstream has proper observation, PR TCA Android support against upstream Skip
- TCA upstream can't depend on flote-works forks
- Much of TCA 1.0 work should transfer to TCA 2.0 (which drops Combine)

</work_remaining>

<attempted_approaches>

## 1. PerceptionRegistrar + App-Level Observing Wrapper (REJECTED)
- Changed Store.swift and ObservationStateRegistrar.swift to use PerceptionRegistrar on Android
- Added Observing.swift wrapper in app code that uses withPerceptionTracking + @State token
- **User rejected**: Violates the plan's core philosophy. The fix must be at the BRIDGE level, not in TCA or app code. The Observing wrapper was a workaround, not a proper fix.
- All changes reverted.

## 2. Adding SkipFuseUI as Fork Dependency (FAILED — 2026-02-18)
- Tried adding skip-fuse-ui as a direct dependency of Point-Free fork packages so `import SwiftUI` would work
- SPM doesn't propagate CJNI's C module map through dynamic library boundaries (SwiftJNI is .dynamic)
- Failed on clean builds — `import SwiftUI` in fork packages requires SkipSwiftUI as a declared dependency, but the CJNI module map doesn't propagate

## 3. Investigating skip-model as Standalone Fix
- Explored whether skip-model's observation could be fixed in isolation
- Discovered skip-model explicitly documents: "Skip does not support calls to the generated access(keyPath:) and withMutation(keyPath:_:) functions"
- Counter-based approach is fundamentally incompatible with TCA's high-frequency mutation pattern
- Dead end for fixing within skip-model itself

</attempted_approaches>

<critical_context>

## The Core Philosophy
"Parity means parity" — TCA code should work identically on both platforms without platform-specific workarounds in app code. The fix MUST be at the bridge level.

## Why Native Observation Works on Android
- `libswiftObservation.so` ships with the Android Swift SDK
- `withObservationTracking`, `ObservationRegistrar`, `access()`, `withMutation()` all compile and run correctly
- The gap is NOT that Observation doesn't work — it's that nobody SUBSCRIBES to it
- Compose uses its own MutableState/snapshot system and doesn't know about Swift Observation
- The "bridge" connects Swift Observation's change notifications to Compose's recomposition

## Why Perception vs Native Observation
- In Fuse mode: Perception just delegates to native Observation — zero overhead, unnecessary indirection
- For upstream/Lite story: Perception serves as unified API contract across all platforms/modes
- For immediate fork fix: native `withObservationTracking` is sufficient
- TCA uses PerceptionRegistrar everywhere for iOS backward compat (iOS 13-16), but on Android it's just a passthrough

## Dependency Chain (CRITICAL)
```
service-app → skip-fuse-ui → skip-ui → skip-model (Lite/transpiled, Kotlin-side MutableStateBacking)
                            → skip-android-bridge (Swift-side JNI calls to MutableStateBacking)
```
skip-model IS in the Fuse dependency graph via skip-ui. The two halves of the observation bridge span two packages: Swift-side JNI in skip-android-bridge, Kotlin-side MutableStateBacking in skip-model.

## SKIP_BRIDGE Mechanism
skip-ui's Package.swift has a conditional block (lines 20-30) that activates when `SKIP_BRIDGE` env var is set (Fuse mode). This adds skip-bridge as a dependency and makes libraries dynamic. This is the exact hook for adding Fuse-mode-only dependencies like swift-perception or native Observation integration.

## Skip Maintainer Endorsement
Marc Prud'hommeaux (Skip inventor) endorsed the fork approach as "the best first step." Dan Fabulich outlined the SKIP_BRIDGE approach for upstream. Both are aware of the work and receptive.

## Building and Running
- **Xcode handles BOTH iOS simulator AND Android emulator** via Skip's build plugin (skipstone)
- `skip android build` is ONLY for confirming Android compilation passes — uses DIFFERENT toolchain than Xcode
- App package: `works.flote.serviceApp`
- Clean build verification: `rm -f Package.resolved && swift package update && skip android build`

## Key File Locations
- TCA Store registrar: `swift-composable-architecture/Sources/ComposableArchitecture/Store.swift` lines 119-125
- TCA ObservationStateRegistrar: `swift-composable-architecture/Sources/ComposableArchitecture/ObservationStateRegistrar.swift`
- Bridge registrar (Swift side): `.build/checkouts/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`
- MutableStateBacking (Kotlin side): `.build/checkouts/skip-model/Sources/SkipModel/MutableStateBacking.swift`
- StateTracking: `.build/checkouts/skip-model/Sources/SkipModel/StateTracking.swift`
- Generated bridge code: `.build/plugins/outputs/service-app/ServiceApp/destination/skipstone/SkipBridgeGenerated/`
- skip-fuse-ui Observation re-export: `.build/checkouts/skip-fuse-ui/Sources/SkipSwiftUI/Fuse/Observation.swift`
- skip-ui Package.swift (SKIP_BRIDGE): `.build/checkouts/skip-ui/Package.swift` lines 20-30
- Observing wrapper backup: `Sources/ServiceApp/Observing.swift.bak`
- swift-perception fork: `/Users/jacob/Developer/src/github/flote-works/swift-perception/`
- Analysis docs: `.claude/observation-bridge-analysis.md`, `.claude/observation-architecture-decision.md`

## Slack Thread
Active thread in Skip's Slack (started 2026-02-19 ~5:36 PM) with Dan Fabulich and Marc Prud'hommeaux. They're engaged and supportive. Continue coordinating there for upstream strategy.

## What We Haven't Explored Yet
- The Kotlin-side code that actually calls `Swift_composableBody` from a `@Composable` context — this is where the subscriber needs to go
- Whether skip-android-bridge's ObservationRegistrar can be modified to use withObservationTracking internally without breaking other Skip users
- The exact mechanism by which MutableStateBacking counters are read during Compose rendering

</critical_context>

<current_state>

## Code State
- **Store.swift**: ORIGINAL state — uses `SkipAndroidBridge.Observation.ObservationRegistrar()` on Android
- **ObservationStateRegistrar.swift**: ORIGINAL state — uses bridge registrar on Android
- **Observing.swift**: Backed up as `Sources/ServiceApp/Observing.swift.bak` — NOT active
- **No Skip package forks created yet** — skip-android-bridge, skip-fuse-ui, skip-ui are all upstream checkouts in `.build/`
- All Point-Free dependency forks are on `flote/service-app` branches at `/Users/jacob/Developer/src/github/flote-works/`

## Task Status
- Task #1 (Instrument reducer): COMPLETED
- Task #2 (Deploy and analyze): COMPLETED
- Task #3 (Fix root cause): IN PROGRESS — root cause identified, architecture decided, implementation not started
- Task #4 (Verify fix): PENDING — blocked on #3

## Branch
- Current branch: `dev/next`
- Git status: Modified README.md, untracked .claude/, .gitignore, Android/, Darwin/, Package.swift, Sources/, Tests/, etc.

## Decision Status
- Root cause: CONFIRMED
- Architecture: DECIDED (native withObservationTracking at bridge level)
- Implementation approach: DECIDED (fork skip-android-bridge and/or skip-fuse-ui)
- Upstream strategy: DISCUSSED with Skip maintainers, SKIP_BRIDGE mechanism identified
- **Implementation: NOT STARTED** — next session should begin here

## Open Questions
1. Where exactly on the Kotlin side does the `@Composable` function live that calls `Swift_composableBody`? (Not yet investigated)
2. Should the TCA fork also switch to PerceptionRegistrar, or can the bridge-level fix work with the existing bridge registrar?
3. What's the minimal change to skip-android-bridge that fixes the loop without breaking other Skip Fuse users?

</current_state>
