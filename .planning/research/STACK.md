# Technology Stack

**Project:** Swift Cross-Platform (Observation Bridge Fix + TCA Android)
**Researched:** 2026-02-20

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Skip Framework | 1.7.2+ | Cross-platform Swift-to-Android compilation (Fuse mode) | Only viable path for native Swift on Android with Compose UI integration. Already in use. Open-sourced Jan 2026. | HIGH |
| Swift Android SDK | 6.1 nightly (upgrade path to 6.3 official) | Native Swift compilation for Android | Official swift.org SDK. Skip currently uses preview builds; 6.3 will be the first "included by default" release. | HIGH |
| Android NDK | r27d | Cross-compilation toolchain for Android architectures | Required by Swift Android SDK. Provides headers and tools for aarch64/x86_64 targets. | HIGH |

### Observation & Reactivity Stack (The Critical Path)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Native `Observation` framework (`libswiftObservation.so`) | Ships with Swift SDK | `withObservationTracking` on Android | Ships with the Swift Android SDK. Native implementation is correct and performant. No need for Perception backport on Android -- use the real thing. | HIGH |
| `ObservationRecording` (custom, in skip-android-bridge fork) | dev/observation-tracking branch | Record-replay pattern bridging Swift Observation to Compose MutableState | Already implemented in the fork. Records `access()` calls during body eval, replays inside `withObservationTracking`, fires single `triggerSingleUpdate()` on onChange. This is THE fix for the infinite recomposition loop. | HIGH |
| `ViewObservation` (custom, in skip-ui fork) | dev/observation-tracking branch | JNI hook point calling `startRecording`/`stopAndObserve` around `Evaluate()` | Already implemented. Kotlin `object` with `external fun` declarations that bind to `@_cdecl` JNI exports in skip-android-bridge. Self-initializes on first `Evaluate()`. | HIGH |
| `BridgeObservationSupport` (existing in skip-android-bridge) | 0.6.1 base + fork additions | JNI calls to `MutableStateBacking.access()`/`update()` | Existing Skip infrastructure. Fork adds `triggerSingleUpdate()` for observation-driven (not mutation-driven) recomposition. | HIGH |
| `SkipAndroidBridge.Observation.ObservationRegistrar` | 0.6.1 base + fork | Dual-path registrar: native Observation + JNI bridge | Used by TCA's `ObservationStateRegistrar` on `#if os(Android)`. Intercepts `access()`/`withMutation()` to record during body eval and suppress direct bridge updates when observation tracking is enabled. | HIGH |
| `MutableStateBacking` (skip-model, Kotlin side) | Upstream (untouched) | Compose `MutableState<Int>` counter driving recomposition | Existing Skip infrastructure. Counter increment = Compose recomposition trigger. The fix ensures only ONE increment per observation cycle instead of per-mutation. Do NOT modify this. | HIGH |

### State Management

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| TCA (The Composable Architecture) | 1.x (fork: `flote/service-app` branch) | Application architecture | Core project requirement. Fork adds `#if os(Android)` conditional compilation for `ObservationStateRegistrar` and `Store` to use `SkipAndroidBridge.Observation.ObservationRegistrar` instead of `PerceptionRegistrar`. | HIGH |
| `@ObservableState` macro | TCA 1.x built-in | Generates observation code for TCA state types | Generates `_$id` (UUID-based identity tracking), `access()`, and `withMutation()` calls. High-frequency `_$willModify()` UUID regeneration is the root cause of infinite recomposition -- but the bridge fix handles this correctly. | HIGH |
| swift-perception | Fork (`flote/service-app`) | Observation backport for pre-iOS 17 | Used on non-Android, non-visionOS platforms. On Android, use native Observation instead (it ships with the SDK). TCA's `ObservableState` protocol conditionally conforms to `Perceptible` or `Observable` based on platform. | HIGH |

### Combine Compatibility

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| OpenCombine | 0.14.0+ | Combine API on Android | TCA 1.x depends on Combine for effect processing (`Effect<Action>` is a Combine publisher). OpenCombineShim conditionally re-exports real Combine on Apple platforms, OpenCombine elsewhere. Will become unnecessary with TCA 2.0. | HIGH |
| combine-schedulers | Fork (`flote/service-app`) | Test schedulers for Combine | Required by TCA 1.x for `TestStore`. Uses OpenCombineShim. | MEDIUM |

### Build & Bridging Infrastructure

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| skip-bridge | 0.16.4+ | Bidirectional Swift-to-JVM bridging | Core Skip infrastructure. Generates bridge code via `skipstone` build plugin. | HIGH |
| swift-jni | 0.3.1+ | Swift bindings for JNI | Low-level JNI call interface used by `BridgeObservationSupport` to call `MutableStateBacking` Java methods. | HIGH |
| swift-android-native | 1.4.1+ | Android native API bindings | Access to Android SDK APIs from Swift. | MEDIUM |
| skipstone (build plugin) | Ships with Skip | Code generation for bridge functions | Generates `Swift_composableBody` JNI functions, Kotlin `@Composable` wrappers. The `Evaluate()` function in skip-ui is what calls view body evaluation. | HIGH |

### Supporting Libraries

| Library | Version | Purpose | When to Use | Confidence |
|---------|---------|---------|-------------|------------|
| swift-dependencies | Fork (`flote/service-app`) | Dependency injection | Always -- TCA requires it for `@Dependency` macro | HIGH |
| swift-navigation | Fork (`flote/service-app`) | Type-safe navigation | When implementing navigation in TCA features | HIGH |
| swift-sharing | Fork (`flote/service-app`) | Shared state persistence | When features need shared/persisted state | MEDIUM |
| swift-clocks | Fork (`flote/service-app`) | Mockable clocks for testing | In tests that involve time-based effects | MEDIUM |
| GRDB.swift | Fork (`flote/service-app`) | SQLite database | When persistence layer is needed | MEDIUM |

## What NOT to Use

| Technology | Why Not | What to Use Instead |
|------------|---------|---------------------|
| swift-perception on Android | `libswiftObservation.so` ships with Swift Android SDK. Using Perception adds unnecessary indirection and the Perception backport is designed for pre-iOS 17, not for Android. | Native `Observation` framework via `ObservationModule` in skip-android-bridge |
| Skip Lite mode for TCA apps | Counter-based observation (`MutableStateBacking` integer increments per `withMutation()`) is fundamentally incompatible with TCA's high-frequency mutations. skip-model explicitly states it does not support `access(keyPath:)`/`withMutation(keyPath:)`. | Skip Fuse mode exclusively |
| App-level `Observing` wrapper | Breaks platform parity. The fix must be at the bridge level (skip-android-bridge + skip-ui) so ALL Fuse-mode views get correct observation, not just ones wrapped manually. | Bridge-level `ObservationRecording` + `ViewObservation` (already implemented in forks) |
| `PerceptionRegistrar` on Android | TCA's `ObservationStateRegistrar` correctly uses `SkipAndroidBridge.Observation.ObservationRegistrar` on Android, which wraps native `ObservationRegistrar` + JNI bridge support. Using `PerceptionRegistrar` would bypass the JNI bridge entirely. | `SkipAndroidBridge.Observation.ObservationRegistrar` |
| Direct Compose `mutableStateOf()` from Swift | Skip's architecture routes all state through `MutableStateBacking` via JNI. Going direct would bypass Skip's state management and break the view lifecycle. | `BridgeObservationSupport` JNI calls to `MutableStateBacking` |
| Waiting for TCA 2.0 | Sneak-peeked Feb 2026, no release date. Removes Combine dependency (good) but requires major migration. Current 1.x works with the observation bridge fix. | TCA 1.x with OpenCombine + observation bridge fix |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Observation on Android | Native `libswiftObservation.so` | swift-perception backport | Native ships with SDK, no extra dependency, full feature parity with iOS |
| Combine on Android | OpenCombine 0.14.0+ | AsyncSequence rewrites | TCA 1.x Effect system is Combine-based; rewriting to AsyncSequence would mean rewriting TCA itself |
| State bridge pattern | Record-replay (`ObservationRecording`) | Direct `withObservationTracking` wrapper in `Evaluate()` | Can't call `withObservationTracking` directly in `Evaluate()` because the Compose recomposition scope needs to own the subscription lifetime; record-replay separates recording (during body eval) from subscribing (after body eval) |
| Recomposition trigger | Single `MutableStateBacking.update(0)` per observation cycle | Per-keypath counter updates | Single trigger is sufficient because Compose recomposes the entire composable scope; per-keypath granularity adds JNI overhead with no benefit |
| Thread safety for recording | pthread TLS (thread-local storage) | Actor isolation | Compose can invoke `Evaluate()` on different threads concurrently; pthread TLS matches per-call-chain semantics without async overhead |

## Version Pinning Strategy

```
Fork dependencies (flote/service-app branch):
  swift-composable-architecture  -> jacobcxdev fork, flote/service-app
  swift-perception               -> jacobcxdev fork, flote/service-app
  swift-navigation               -> jacobcxdev fork, flote/service-app
  swift-sharing                  -> jacobcxdev fork, flote/service-app
  swift-dependencies             -> jacobcxdev fork, flote/service-app
  swift-clocks                   -> jacobcxdev fork, flote/service-app
  combine-schedulers             -> jacobcxdev fork, flote/service-app
  swift-custom-dump              -> jacobcxdev fork (if modified)
  swift-snapshot-testing         -> jacobcxdev fork, flote/service-app
  swift-structured-queries       -> jacobcxdev fork, flote/service-app
  GRDB.swift                     -> jacobcxdev fork, flote/service-app
  sqlite-data                    -> jacobcxdev fork, flote/service-app

Skip framework forks (dev/observation-tracking branch):
  skip-android-bridge            -> jacobcxdev fork, dev/observation-tracking
  skip-ui                        -> jacobcxdev fork, dev/observation-tracking

Upstream (unmodified):
  skip                           -> source.skip.tools, 1.7.2+
  skip-fuse-ui                   -> source.skip.tools, 1.0.0+
  skip-bridge                    -> source.skip.tools, 0.16.4+
  swift-jni                      -> source.skip.tools, 0.3.1+
  swift-android-native           -> source.skip.tools, 1.4.1+
  OpenCombine                    -> github.com/OpenCombine, 0.14.0+
```

## Key Technical Details

### The `swiftThreadingFatal` Workaround

The skip-android-bridge fork includes a `@_cdecl("_ZN5swift9threading5fatalEPKcz")` stub to work around a missing symbol in `libswiftObservation.so`. This is tracked at [swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890) and should be fixed in Swift 6.3. Until then, this stub is required for `libswiftObservation.so` to load on Android.

**Confidence:** HIGH -- the crash without this stub is documented in the fork code and the upstream fix PR is linked.

### JNI Naming Convention

The JNI exports use the standard naming convention: `Java_<package>_<class>_<method>` where dots become underscores. `ViewObservation` lives in `skip.ui`, so exports are `Java_skip_ui_ViewObservation_<method>`. This naming must match exactly or the `external fun` declarations in Kotlin will fail to bind.

### Compilation Targets

The Swift Android SDK targets:
- `aarch64-unknown-linux-android28` (ARM64 devices/emulators)
- `x86_64-unknown-linux-android28` (x86_64 emulators)

Both must be built and included in the APK.

## Sources

- [Swift SDK for Android -- Getting Started (swift.org)](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html) -- NDK r27d requirement, compilation targets
- [Announcing the Swift SDK for Android (swift.org)](https://www.swift.org/blog/nightly-swift-sdk-for-android/) -- Official SDK nightly releases, 6.3 timeline
- [Skip Official SDK Announcement (skip.dev)](https://skip.dev/blog/official-swift-sdk-for-android/) -- Skip's integration plan with official SDK
- [Skip Modes Documentation (skip.dev)](https://skip.dev/docs/modes/) -- Fuse vs Lite mode details
- [Skip now fully open source (InfoQ)](https://www.infoq.com/news/2026/01/swift-skip-open-sourced/) -- Skip open-sourced Jan 2026
- [Point-Free 2025 Year-in-Review](https://www.pointfree.co/blog/posts/196-2025-year-in-review) -- TCA 2.0 preview, planned simplifications
- [TCA 2.0 Sneak Peek (pointfree.co)](https://www.pointfree.co/blog/posts/200-the-point-free-way-tca-2-0-sneak-peek-a-giveaway-q-a-and-more) -- Feb 2026 live event
- [skip-android-bridge repository (GitHub)](https://github.com/skiptools/skip-android-bridge) -- v0.6.1 latest upstream
- [OpenCombine (GitHub)](https://github.com/OpenCombine/OpenCombine) -- v0.14.0+ cross-platform Combine
- [swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890) -- Fix for `_ZN5swift9threading5fatalEPKcz` missing symbol
- Project codebase: `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` -- Fork implementation (142 lines added)
- Project codebase: `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` -- Fork implementation (23 lines added)
- Project codebase: `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift` -- TCA Android registrar wiring

---

*Stack research: 2026-02-20*
