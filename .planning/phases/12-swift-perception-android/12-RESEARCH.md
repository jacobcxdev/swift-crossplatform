# Phase 12: Swift Perception Android Port - Research

**Researched:** 2026-02-24
**Domain:** Swift Perception library Android compatibility / TCA observation infrastructure
**Confidence:** HIGH

## Summary

The swift-perception library is currently almost entirely gated out on Android via `#if canImport(SwiftUI) && !os(Android)` guards. This excludes `WithPerceptionTracking` (the SwiftUI view wrapper), `Perception.Bindable`, the `PerceptionRegistrar` perception-checking debug infrastructure, and the `Environment` extensions. However, the core non-SwiftUI types -- `Perceptible` protocol, `_PerceptionRegistrar`, `PerceptionTracking`, `_PerceptionLocals`, `Perceptions` async sequence, `_ThreadLocal`, `Locking`, and the macros -- already compile on Android with no changes needed.

The key insight is that TCA on Android already bypasses PerceptionRegistrar entirely: `Store._$observationRegistrar` uses `BridgeObservationRegistrar` (from skip-android-bridge), and `ObservationStateRegistrar.registrar` also uses `BridgeObservationRegistrar`. The `ObservableState` protocol conforms to `Observable` (not `Perceptible`) on Android. This means the perception infrastructure is not on the critical data path for TCA state observation on Android -- the bridge handles that directly via JNI.

What IS missing and needed:
1. **`Perceptible` protocol conformance on `Store`** -- currently gated `#if !os(visionOS) && !os(Android)` in Store+Observation.swift. TCA code that constrains on `Perceptible` (e.g., `ObservationStateRegistrar` methods with `Subject: Perceptible`) is entirely excluded on Android.
2. **`_PerceptionLocals` usage in TCA** -- used extensively for `skipPerceptionChecking` and `isInPerceptionTracking` in Core.swift, Store.swift, Store+Observation.swift, IdentifiedArray+Observation.swift, NavigationStack+Observation.swift. These already compile because `_PerceptionLocals` is not gated.
3. **`withPerceptionTracking` function** -- the free function in PerceptionTracking.swift is NOT gated (only the SwiftUI `WithPerceptionTracking` view is). It already compiles on Android.
4. **`ObservationStateRegistrar` Perceptible methods** -- the block at lines 131-206 of ObservationStateRegistrar.swift is gated `#if !os(visionOS) && !os(Android)`, excluding `access`, `mutate`, `willModify`, `didModify` overloads that take `Subject: Perceptible`.

**Primary recommendation:** Enable `Perceptible` conformance on `Store` for Android, and enable the `ObservationStateRegistrar` Perceptible methods on Android. The `WithPerceptionTracking` SwiftUI view should get an Android-specific implementation that delegates to the observation bridge rather than SwiftUI's `@State`-based change tracking. Perception checking (the debug warning system) should be disabled on Android since it depends on Darwin-specific `_dyld_image_count` / AttributeGraph introspection.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OBS-29 | `PerceptionRegistrar` facade delegates to `ObservationRegistrar` on Android (conditional compilation path) | TCA already uses `BridgeObservationRegistrar` on Android, not `PerceptionRegistrar`. The requirement is to ensure `PerceptionRegistrar` compiles and delegates correctly if used directly. The public `PerceptionRegistrar` type needs its Android path to delegate to native `ObservationRegistrar` (which it already does via `_PerceptionRegistrar` fallback when `#if canImport(Observation)` is true). Main work: remove the `!os(Android)` guards from PerceptionRegistrar.swift so it compiles on Android, with perception checking disabled. |
| OBS-30 | `withPerceptionTracking(_:onChange:)` delegates to `withObservationTracking` on Android | The free function `withPerceptionTracking` in PerceptionTracking.swift is already NOT gated -- it compiles on all platforms. On iOS 17+ it delegates to `withObservationTracking`. On Android (where `canImport(Observation)` is true and the runtime version check passes), this delegation should already work. Verification needed that the `#available` check passes on Android's Observation runtime. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| swift-perception (fork) | dev/swift-crossplatform branch | Perceptible protocol, PerceptionRegistrar, WithPerceptionTracking, _PerceptionLocals | Already forked; provides backward-compat observation layer TCA depends on |
| skip-android-bridge (fork) | dev/swift-crossplatform branch | BridgeObservationRegistrar, ObservationRecording, JNI bridge | Already provides the actual Android observation mechanism |
| swift-composable-architecture (fork) | dev/swift-crossplatform branch | Store, ObservationStateRegistrar, ObservableState | Consumer of perception APIs; needs guard changes |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Observation (system) | Swift 6.2 runtime | Native Observable/ObservationRegistrar on Android | Already available via libswiftObservation.so on Android SDK |
| IssueReporting (fork) | dev/swift-crossplatform branch | Runtime warning infrastructure | Used by PerceptionRegistrar.check() for perception warnings |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Porting full PerceptionRegistrar perception-checking to Android | Disabling perception-checking on Android | Perception checking uses Darwin-specific dyld/MachO/AttributeGraph introspection that has no Android equivalent. Since Android uses the bridge registrar (not PerceptionRegistrar) for actual state tracking, the debug checking adds no value. |
| Creating Android-native WithPerceptionTracking view | Making WithPerceptionTracking a no-op passthrough on Android | On Android with iOS 17+ equivalent runtime, WithPerceptionTracking should be a passthrough since native Observation handles tracking. The bridge handles recomposition separately. A no-op is correct. |

## Architecture Patterns

### Current Android Observation Architecture
```
TCA Store
  -> ObservationStateRegistrar (Android: uses BridgeObservationRegistrar)
    -> BridgeObservationRegistrar.access() records into ObservationRecording
    -> BridgeObservationRegistrar.willSet() suppressed during recording
    -> ObservationRecording.stopAndObserve() replays inside withObservationTracking
    -> onChange triggers MutableStateBacking.update(0) via JNI
    -> Compose recomposition fires
```

### Pattern 1: Guard Removal Strategy
**What:** Systematically remove `!os(Android)` from perception guards while preserving correctness
**When to use:** For every `#if canImport(SwiftUI) && !os(Android)` or `#if !os(visionOS) && !os(Android)` guard

The guards fall into 3 categories:
1. **Remove entirely** -- code that works on Android as-is (e.g., `Store: Perceptible` conformance, `ObservationStateRegistrar` Perceptible methods)
2. **Replace with Android-specific impl** -- code that needs SwiftUI types (e.g., `WithPerceptionTracking` View, `Bindable` property wrapper)
3. **Keep gated** -- code that is genuinely Darwin-only (e.g., MachO/dyld perception checking, AttributeGraph introspection)

### Pattern 2: WithPerceptionTracking on Android
**What:** Provide a minimal Android-compatible `WithPerceptionTracking` that acts as a transparent passthrough
**When to use:** When TCA or user code wraps view bodies in `WithPerceptionTracking { ... }`

On Android, `WithPerceptionTracking` should:
- Accept a `@ViewBuilder` content closure (using SkipFuseUI's View protocol)
- Return the content directly (passthrough)
- Optionally set `_PerceptionLocals.isInPerceptionTracking = true` in DEBUG builds
- NOT attempt SwiftUI `@State`-based observation (the bridge handles this)

```swift
#if os(Android)
import SkipFuseUI

public struct WithPerceptionTracking<Content: View>: View {
    let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        #if DEBUG
        _PerceptionLocals.$isInPerceptionTracking.withValue(true) {
            content()
        }
        #else
        content()
        #endif
    }
}
#endif
```

### Pattern 3: PerceptionRegistrar Android Delegation
**What:** Enable PerceptionRegistrar on Android, delegating to native ObservationRegistrar
**When to use:** When any code path uses PerceptionRegistrar directly (rather than BridgeObservationRegistrar)

On Android:
- `PerceptionRegistrar.init()` creates native `ObservationRegistrar` (already happens via `_PerceptionRegistrar` when `canImport(Observation)` is true and `#available` passes)
- `access/willSet/didSet/withMutation` delegate to native registrar
- Perception checking (`check()`) is disabled (no-op)
- The `_isPerceptionCheckingEnabled` flag and `perceptionChecks` cache are excluded

### Anti-Patterns to Avoid
- **Do not port the AttributeGraph/MachO perception checking to Android.** The `isSwiftUI()` method introspects `_dyld_image_count` and `mach_header` which are Darwin-only. On Android, the observation bridge handles tracking, making these checks meaningless.
- **Do not make Perception.Bindable available on Android.** It depends on SwiftUI's `@ObservedObject` and `ObservableObject` protocol. On Android, TCA uses `$store.property` bindings through the Store's own bridge-based subscript, not through Perception.Bindable.
- **Do not change the BridgeObservationRegistrar path.** TCA's Store and ObservationStateRegistrar correctly use BridgeObservationRegistrar on Android. The perception port should NOT redirect these to PerceptionRegistrar -- the bridge is the correct path for JNI-based Compose recomposition.
- **Do not remove the `#if !os(visionOS) && !os(Android)` guards from ObservationStateRegistrar without understanding the implications.** These gates enable the Perceptible-constrained overloads. On Android, the Observable-constrained overloads (from `#if canImport(Observation)`) are the ones used by BridgeObservationRegistrar. Enabling Perceptible overloads provides the API surface TCA macros may generate, but must not conflict with the Observable overloads.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-local storage on Android | Custom TLS implementation | `_ThreadLocal` already handles Bionic via `pthread_getspecific/pthread_setspecific` | swift-perception already supports `canImport(Bionic)` in ThreadLocal.swift |
| Locking on Android | Custom lock | `Lock` in Locking.swift already handles `canImport(Bionic)` | Uses `pthread_mutex_t` on Android, `os_unfair_lock` on Darwin |
| Observation beta detection | Android-specific check | `isObservationBeta` already returns `false` on non-iOS/tvOS/watchOS | The function's `#else return false` handles Android |
| Perception tracking (non-SwiftUI) | Custom tracking system | `withPerceptionTracking` free function | Already compiles on all platforms, delegates to `withObservationTracking` when available |

**Key insight:** Most of swift-perception's core infrastructure already compiles on Android. The work is almost entirely about removing guards and providing minimal SwiftUI-type substitutes, not about porting complex logic.

## Common Pitfalls

### Pitfall 1: Conflicting Overload Resolution
**What goes wrong:** Enabling both `Perceptible`-constrained and `Observable`-constrained overloads on Android causes ambiguity because on Android, types conform to `Observable` (through BridgeObservationRegistrar) but may also conform to `Perceptible`.
**Why it happens:** `@_disfavoredOverload` is used on Perceptible methods to prefer Observable ones on iOS 17+. On Android, if a type conforms to both, the compiler must resolve which overload to call.
**How to avoid:** Ensure `@_disfavoredOverload` is preserved on all Perceptible-constrained methods. Test that Store (which conforms to both Observable and Perceptible on Android) correctly resolves to the Observable/Bridge path.
**Warning signs:** Ambiguous method call compiler errors; wrong registrar being called at runtime.

### Pitfall 2: canImport(SwiftUI) is False on Android
**What goes wrong:** Code guarded with `#if canImport(SwiftUI)` is excluded on Android because SkipFuseUI provides `SkipSwiftUI`, not Apple's `SwiftUI` module.
**Why it happens:** The Android SDK does not ship Apple's SwiftUI framework. Skip provides its own UI layer.
**How to avoid:** Use `#if canImport(SwiftUI) || os(Android)` for code that needs both platforms, or use separate `#if os(Android)` blocks with SkipFuseUI imports.
**Warning signs:** "Missing module 'SwiftUI'" errors on Android builds.

### Pitfall 3: @available Checks on Android
**What goes wrong:** `#available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)` checks may not behave as expected on Android -- the `*` wildcard covers Android, so the check always passes.
**Why it happens:** Android is not listed as a named platform in `@available`, so it falls through to the wildcard.
**How to avoid:** This is actually desirable -- on Android with Swift 6.2+, the Observation framework is available, so `#available(*, *)` correctly indicates availability. No special handling needed.
**Warning signs:** None expected -- this is correct behavior.

### Pitfall 4: DEBUG-only _PerceptionLocals.isInPerceptionTracking
**What goes wrong:** `_PerceptionLocals.isInPerceptionTracking` is only defined in `#if DEBUG` builds. Code that references it outside DEBUG guards will fail in release builds.
**Why it happens:** The property is deliberately DEBUG-only to avoid runtime overhead in production.
**How to avoid:** Always gate `isInPerceptionTracking` access with `#if DEBUG`. The existing TCA code already does this correctly (e.g., `#if DEBUG && !os(visionOS)` in Store+Observation.swift).
**Warning signs:** Release build failures referencing `isInPerceptionTracking`.

### Pitfall 5: WithPerceptionTracking Content Type Constraints
**What goes wrong:** The Darwin `WithPerceptionTracking` has conformances to `View`, `ToolbarContent`, `Scene`, `Commands`, `TableContent`, `ChartContent`, etc. Porting all of these to Android is impractical.
**Why it happens:** SwiftUI has many content protocols. SkipFuseUI only provides `View`.
**How to avoid:** On Android, only provide `WithPerceptionTracking: View` conformance. Other content types (Scene, ToolbarContent, etc.) are not relevant on Android.
**Warning signs:** Compilation errors from code trying to use WithPerceptionTracking in non-View contexts on Android.

## Code Examples

### Example 1: PerceptionRegistrar Android Path (Proposed)
```swift
// In PerceptionRegistrar.swift -- remove !os(Android) from outer guard
#if canImport(SwiftUI) && !os(Android)
  import SwiftUI
#elseif os(Android)
  // No SwiftUI import needed -- PerceptionRegistrar delegates to
  // _PerceptionRegistrar which delegates to ObservationRegistrar
#endif

public struct PerceptionRegistrar: Sendable {
  private let rawValue: any Sendable
  #if DEBUG
    public let _isPerceptionCheckingEnabled: Bool
  #endif
  // Remove: #if DEBUG && canImport(SwiftUI) && !os(Android)
  // perceptionChecks only needed on Darwin for AttributeGraph detection

  public init(isPerceptionCheckingEnabled: Bool = true) {
    #if DEBUG
      _isPerceptionCheckingEnabled = isPerceptionCheckingEnabled
    #endif
    #if canImport(Observation)
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *), !isObservationBeta {
        rawValue = ObservationRegistrar()
        return
      }
    #endif
    rawValue = _PerceptionRegistrar()
  }

  // access/willSet/didSet/withMutation -- remove !os(Android) from guards
  // Perception checking (check() method) stays Darwin-only
}
```

### Example 2: Store Perceptible Conformance (Proposed)
```swift
// In Store+Observation.swift -- change the guard
#if !os(visionOS)
  extension Store: Perceptible {}
#endif
// Remove os(Android) exclusion -- Store can conform to Perceptible on Android
// even though it uses BridgeObservationRegistrar for actual observation
```

### Example 3: ObservationStateRegistrar Perceptible Methods (Proposed)
```swift
// In ObservationStateRegistrar.swift -- change the guard
#if !os(visionOS)
  extension ObservationStateRegistrar {
    @_disfavoredOverload
    @inlinable
    public func access<Subject: Perceptible, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>
    ) {
      self.registrar.access(subject, keyPath: keyPath)
    }
    // ... other Perceptible-constrained methods
  }
#endif
// On Android, self.registrar is BridgeObservationRegistrar which takes
// Subject: Observable. Since Perceptible != Observable, the call goes
// through the _disfavoredOverload path to _PerceptionRegistrar.
// This is fine -- these overloads exist for API completeness.
```

### Example 4: WithPerceptionTracking Android Implementation
```swift
#if os(Android)
import SkipFuseUI

public struct WithPerceptionTracking<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
    }
}
#endif
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| swift-perception excluded on Android ("no backport needed") | Recognized TCA depends on Perceptible conformances | v1.0 audit (2026-02-24) | Phase 12 created to close SWIFT-PERCEPTION-EXCLUDED gap |
| ObservableState conforms to Observable on Android | Will additionally conform to Perceptible (via protocol inheritance or direct) | This phase | Enables TCA binding/scoping that constrains on Perceptible |
| No WithPerceptionTracking on Android | Passthrough implementation using SkipFuseUI View | This phase | User code wrapping bodies in WithPerceptionTracking compiles on Android |

**Deprecated/outdated:**
- The "Out of Scope" entry in REQUIREMENTS.md stating "Swift Perception backport on Android: no backport needed" was rescoped to Phase 12

## Open Questions

1. **Overload resolution with dual conformance**
   - What we know: On Android, Store conforms to `Observable` (via `@ObservableState` macro). Adding `Perceptible` conformance means Store is both. `@_disfavoredOverload` on Perceptible methods should cause Observable methods to be preferred.
   - What's unclear: Whether the Swift compiler on Android correctly resolves `@_disfavoredOverload` in all TCA usage sites, or if there are edge cases.
   - Recommendation: Test compilation thoroughly. If ambiguity arises, keep Perceptible overloads gated and instead make `ObservableState: Perceptible` on Android (so the conformance propagates from the protocol, not from direct Store extension).

2. **PerceptionRegistrar on Android: needed by anything?**
   - What we know: TCA's Store uses BridgeObservationRegistrar on Android. ObservationStateRegistrar uses BridgeObservationRegistrar. Direct PerceptionRegistrar usage on Android is likely zero in TCA.
   - What's unclear: Whether any user-level code (not in TCA) might use `@Perceptible` models directly on Android and expect PerceptionRegistrar to work.
   - Recommendation: Enable PerceptionRegistrar on Android for API completeness (delegates to ObservationRegistrar via existing codepath), but don't invest in porting the perception-checking debug features.

3. **Perception.Bindable on Android**
   - What we know: Requires `@ObservedObject`, `ObservableObject` (SwiftUI types not available on Android). TCA uses `$store.property` bindings through its own Store subscripts, not Perception.Bindable.
   - What's unclear: Whether any TCA binding helpers explicitly reference `Perception.Bindable`.
   - Recommendation: Keep `Perception.Bindable` gated out on Android. If TCA has references, gate those too or provide Android-specific alternatives.

## Sources

### Primary (HIGH confidence)
- Direct source code analysis of `forks/swift-perception/Sources/` -- all 21 .swift files read
- Direct source code analysis of `forks/swift-composable-architecture/Sources/ComposableArchitecture/` -- Store.swift, Core.swift, Store+Observation.swift, ObservableState.swift, ObservationStateRegistrar.swift, Exports.swift
- Direct source code analysis of `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` -- BridgeObservationRegistrar implementation
- Direct source code analysis of `forks/swift-navigation/Sources/SwiftNavigation/` -- UIBindable.swift, Observe.swift, UIBinding.swift usage of Perceptible
- v1.0-MILESTONE-AUDIT.md -- SWIFT-PERCEPTION-EXCLUDED gap identification
- REQUIREMENTS.md -- OBS-29, OBS-30 requirement definitions

### Secondary (MEDIUM confidence)
- PROJECT STATE.md decisions about PerceptionRegistrar as thin passthrough on Android
- CLAUDE.md gotchas about canImport(SwiftUI) being false on Android

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all code is in the forked repo, directly inspectable
- Architecture: HIGH - the guard structure and delegation patterns are clear from source analysis
- Pitfalls: HIGH - based on direct analysis of platform-conditional compilation patterns already in the codebase

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (stable -- swift-perception fork is under our control)
