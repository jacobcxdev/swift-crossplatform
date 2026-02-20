# Feature Landscape

**Domain:** Cross-platform Swift framework bridging Point-Free tools (TCA, swift-navigation, swift-dependencies, swift-sharing, GRDB) to Android via Skip Fuse mode
**Researched:** 2026-02-20

## Table Stakes

Features users expect. Missing = the framework is unusable for TCA apps on Android.

### Observation / Reactivity

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `withObservationTracking` bridge in view body | TCA's `@ObservableState` macro relies on Swift Observation for fine-grained reactivity. Without this, every state mutation triggers infinite recomposition loops on Android. | High | `ObservationRecording` record-replay pattern exists in skip-android-bridge but is not yet wired into skip-ui's `Evaluate()` JNI path. Fix must call `startRecording()` before body eval and `stopAndObserve()` after. |
| Single-increment-per-cycle recomposition | Compose's `MutableState` must increment once per observation cycle, not once per `withMutation` call. TCA's `_$id` UUID regeneration on every state assignment generates thousands of mutations per cycle. | High | `BridgeObservationSupport.triggerSingleUpdate()` exists but only fires when `ObservationRecording.isEnabled` is true. The `willSet` suppression in the registrar (`if !ObservationRecording.isEnabled`) is the key gate. |
| Nested view observation (stack-based recording) | Parent Fuse views contain child Fuse views. Each `Evaluate()` call must push/pop its own recording frame so observation subscriptions don't leak across view boundaries. | Medium | `ObservationRecording` already uses a thread-local stack (`FrameStack`) with `startRecording()`/`stopAndObserve()` per frame. Needs integration testing with real nested TCA views. |
| `@ObservableState` macro output compatibility | The `@ObservableState` macro generates `access()`, `withMutation()`, `willModify()`, `didModify()` calls. All must route through `ObservationStateRegistrar` correctly on Android. | Medium | Already implemented: `ObservationStateRegistrar` uses `SkipAndroidBridge.Observation.ObservationRegistrar` on Android (line 13). The `#if os(Android)` branch is in place. |
| `PerceptionRegistrar` bypass on Android | Android uses native `libswiftObservation.so` (ships with Swift Android SDK). The swift-perception backport is unnecessary and must not be used on Android. | Low | Already implemented: `#if !os(visionOS) && !os(Android)` gates PerceptionRegistrar usage. Android path uses `SkipAndroidBridge.Observation.ObservationRegistrar` directly. |

### State Management (TCA Store/Reducer)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `Store` initialization and scoping | `Store(initialState:reducer:)` and `store.scope(state:action:)` are the fundamental TCA API. Every TCA view receives a scoped store. | Low | Already compiles on Android. `Store.swift` imports `SkipAndroidBridge` on Android and uses the bridge registrar. |
| `Effect.run` / `Effect.send` / `Effect.merge` / `Effect.concatenate` | Effects are how TCA handles side effects. All effect combinators must work on Android. | Medium | `AndroidParityTests` verify `.merge`, `.concatenate`, `.run`, `.send`, and cancellation all work. OpenCombine provides the Combine layer on Android. |
| `Effect.cancel` (cancellation by ID) | Long-running effects must be cancellable. This is core TCA ergonomics. | Low | Verified working in `AndroidParityTests.testEffectCancellation()`. |
| `TestStore` on Android | TCA's `TestStore` is the primary testing tool. Must work on Android for parity tests. | Medium | Partially working. `#if !os(Android)` guards exist in `TestStore.swift` (4 locations) for `useMainSerialExecutor` (unavailable on Android). Android uses `effectDidSubscribe` stream instead. |
| `BindingReducer` / `@BindableAction` | Two-way bindings between SwiftUI controls and TCA state are fundamental to form-heavy apps. | Low | Already verified working in `AndroidParityTests.testBindingReducerMutatesState()`. |
| `IdentifiedArray` / `ForEachStore` | List-based UIs with per-item stores are the standard TCA pattern for collections. | Low | `ForEachStore` compiles and instantiates on Android per `TCASwiftUIParityTests.testForEachStoreInstantiation()`. |
| `@Presents` / `IfLetStore` (optional child state) | Modal presentation of child features via optional state is core TCA navigation. | Low | Compiles and instantiates on Android per `TCASwiftUIParityTests.testIfLetStoreInstantiation()`. |

### Navigation

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `NavigationStack` with `StackState`/`StackAction` | Stack-based navigation is the primary TCA navigation pattern. Push/pop screens driven by reducer state. | High | `NavigationStack+Observation.swift` has 4 `#if !os(Android)` blocks. The `NavigationStack.init(path:root:destination:)` extension is entirely guarded out on Android (line 150+). The `Binding.scope` variant works, but `ObservedObject.Wrapper` and `Perception.Bindable` variants are guarded. Skip-ui must provide a `NavigationStack` Compose equivalent. |
| Sheet / fullScreenCover presentation | Modal presentation via `.sheet(store:)` is used extensively in TCA apps. | Medium | `TCASwiftUIParityTests.testSheetPresentationModifier()` passes. The SwiftUI modifier compiles; whether Skip-ui renders it correctly on Compose is untested. |
| Alert / ConfirmationDialog | `AlertState` and `ConfirmationDialogState` are TCA's type-safe alert APIs. Both have `#if !os(Android)` guards for `tint` parameter handling. | Medium | Compilation verified in parity tests. The `#if !os(Android)` blocks in `Alert.swift` and `ConfirmationDialog.swift` gate `tint` color support (cosmetic, not functional). |
| Dismiss effect | Programmatic dismissal from reducers via `@Dependency(\.dismiss)`. | Low | Already verified in `AndroidParityTests.testDismissEffectInvokesClosureOnce()`. |

### Dependency Injection

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `@Dependency` property wrapper | Core DI mechanism. Every TCA reducer accesses dependencies this way. | Low | `swift-dependencies` has only 4 files with Android/SKIP_BRIDGE guards, all in non-critical paths (`AppEntryPoint.swift`, `Deprecations.swift`, `WithDependencies.swift`, `OpenURL.swift`). Core DI works. |
| `withDependencies` scoping | Overriding dependencies for child features and tests. | Low | `WithDependencies.swift` has a single Android guard. Core scoping mechanism works. |
| `DependencyKey` / `TestDependencyKey` | Defining and overriding dependencies. Standard protocol conformance. | Low | No Android-specific guards on the protocol definitions. Works as-is. |
| `@Dependency(\.openURL)` | URL opening is platform-specific. Must have Android implementation. | Medium | `OpenURL.swift` has an Android guard. Needs Android-specific implementation (Intent-based URL opening). |

### Persistence

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| GRDB SQLite database access | GRDB is the persistence layer for structured queries. Must read/write SQLite on Android. | Medium | GRDB.swift fork has zero `os(Android)` or `SKIP_BRIDGE` guards in Sources, suggesting it compiles without platform-specific changes. SQLite is available on Android natively. |
| `sqlite-data` fetch operations | `Fetch`, `FetchAll`, `FetchOne` are the query primitives from sqlite-data. | Low | 4 files have SKIP_BRIDGE guards, all in fetch-related code. The SwiftUI integration (`FetchKey+SwiftUI.swift`) has a guard. |
| `@Shared` state persistence | `swift-sharing`'s `@Shared` property wrapper for cross-feature state sharing. | Medium | 4 files have Android guards. `AppStorageKey.swift` includes `os(Android)` in its `#if canImport` check (line 1), so AppStorage-based sharing is intended to work. `Shared.swift` and `SharedReader.swift` have guards that need investigation. |
| `UserDefaults`-backed `@Shared(.appStorage(...))` | The most common persistence pattern for simple key-value state in TCA apps. | Medium | `AppStorageKey` explicitly includes `os(Android)` in its availability check. Foundation's `UserDefaults` must be available on Android (via swift-corelibs-foundation or Skip's Foundation shim). |

## Differentiators

Features that set this framework apart from KMP/Flutter/React Native approaches. Not expected, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Single Swift codebase for iOS + Android** | Write TCA reducers, views, and tests once. No Kotlin/Java layer. No bridging code. Competitive advantage over KMP which requires separate UI layers. | N/A (project-level) | This is the core value proposition. Skip Fuse compiles Swift natively for Android via NDK. |
| **TCA's exhaustive testing on Android** | `TestStore` with exhaustive assertion checking runs on both platforms. No other cross-platform framework offers this level of test ergonomics for state management. | Medium | Partially working. `TestStore` compiles with Android-specific synchronization (`effectDidSubscribe` instead of `useMainSerialExecutor`). |
| **Compile-time navigation safety** | TCA's `StackState`/`StackAction` with `@Reducer enum Path` gives compile-time exhaustive handling of navigation destinations. No runtime crashes from unhandled routes. | Low (once observation works) | Already compiles. Depends on observation bridge fix for runtime correctness. |
| **Shared dependency graph across platforms** | `@Dependency` lets you swap live/test/preview implementations. Same dependency graph on both platforms with platform-specific live implementations where needed. | Low | Core DI already works cross-platform. Only platform-specific dependencies (like `openURL`) need separate implementations. |
| **GRDB cross-platform persistence** | Same SQLite queries, same migration system, same `@Observable` database observation on both platforms. No Core Data / Room split. | Medium | GRDB compiles without Android guards. sqlite-data has minimal guards. Actual runtime behavior on Android needs validation. |
| **Snapshot testing on Android** | `swift-snapshot-testing` fork exists. If working, enables visual regression testing of Android Compose rendering. | High | Fork exists but no Android parity tests found. Snapshot testing requires rendering infrastructure that may not exist on Android. |
| **Upstream contribution path** | Changes proven in forks can flow back to Skip and Point-Free. Community benefits from this work. | Low (effort) | Skip team (Marc) and Point-Free (Stephen) are both supportive. Fork-first approach endorsed. |

## Anti-Features

Features to explicitly NOT build. Building these would waste effort or create maintenance burden.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Skip Lite mode TCA support** | Lite mode's counter-based `MutableStateBacking` observation is fundamentally incompatible with TCA's high-frequency `withMutation` calls. skip-model explicitly documents: "Skip does not support calls to the generated `access(keyPath:)` and `withMutation(keyPath:_:)` functions." | Use Fuse mode exclusively. Lite mode is for simple apps without complex observation. |
| **App-level observation wrappers** | An `Observing` view wrapper was tried and rejected. It creates a second observation layer that conflicts with the bridge and requires every TCA view to opt in. | Fix at the bridge level (skip-android-bridge / skip-ui). Platform parity means views should not need wrapper boilerplate. |
| **Custom Combine replacement** | Building a full Combine replacement for Android would be massive scope. OpenCombine already exists and works. | Continue using OpenCombine for TCA 1.x. TCA 2.0 drops the Combine dependency entirely, making this a temporary solution. |
| **TCA 2.0 support (now)** | TCA 2.0 is in preview but not stable. Targeting both 1.x and 2.0 doubles the maintenance surface. Stephen Celis says 2.0 preview is "very soon" but that is not "now." | Target TCA 1.x exclusively. Plan migration to 2.0 as a separate effort once 2.0 is released and stable. TCA 2.0 will simplify things (no Combine dependency, simplified observation). |
| **KMP interop layer** | This is a Swift-first framework. Adding Kotlin Multiplatform interop creates a second abstraction that conflicts with Skip's approach. | If users need KMP, they should use KMP directly, not this framework. |
| **UIKit navigation support on Android** | TCA's `UIKitNavigation` module (`NavigationStackController`, `Push`, `Dismiss`) is iOS-only. Porting UIKit navigation semantics to Compose would be enormous effort with no users. | Only support SwiftUI-based navigation patterns. The `#if !os(Android)` guards on `UIBindable`, `Perception.Bindable`, and `ObservedObject.Wrapper` scope variants are correct. |
| **Animation parity** | `Effect.send(_:animation:)` wraps in `withTransaction` on iOS, which is unavailable on Android. Achieving animation parity is a Skip-ui concern, not this framework's. | Accept that `animation:` parameter is unavailable on Android. TCA apps should use Skip-ui's Compose animation system for Android-specific animations. |
| **Production app in this repo** | This repo produces framework-level tools. Building an app here mixes concerns and makes the repo harder to maintain. | Example apps (`fuse-app`, `fuse-library`) demonstrate features. Production apps should depend on this framework as a package. |

## Feature Dependencies

```
Observation Bridge Fix (skip-android-bridge + skip-ui)
  |
  +-> TCA Store renders correctly on Android
  |     |
  |     +-> NavigationStack works (state-driven push/pop)
  |     +-> Sheet/Alert/Dialog presentation works
  |     +-> ForEachStore renders lists correctly
  |     +-> BindingReducer two-way bindings work
  |     |
  |     +-> Example TCA app runs on Android (validation)
  |           |
  |           +-> Android integration test suite
  |           +-> Fork change documentation (FORKS.md)
  |           +-> Stable fork releases (tagged versions)
  |           +-> Upstream PR candidates identified
  |
  +-> TestStore works on Android (observation-dependent assertions)
        |
        +-> Android parity test coverage expanded
        +-> CI running tests on Android emulator

Dependency Injection (swift-dependencies) -- INDEPENDENT
  |
  +-> Platform-specific dependency implementations (openURL, etc.)

Persistence (GRDB + sqlite-data + swift-sharing) -- INDEPENDENT (after compilation)
  |
  +-> Runtime validation on Android
  +-> @Shared(.appStorage) on Android
  +-> Database observation via GRDB on Android
```

## MVP Recommendation

**The entire MVP is the observation bridge fix.** Without it, nothing else matters -- TCA apps enter infinite recomposition loops and are unusable on Android.

Prioritize:
1. **Observation bridge fix** (skip-android-bridge `ObservationRecording` wired into skip-ui's `Evaluate()` JNI path) -- this unblocks everything
2. **Validate core TCA patterns** (Store scoping, effects, bindings) -- verify the parity tests pass on a real Android emulator after the bridge fix
3. **NavigationStack on Android** -- the `#if !os(Android)` guard on `NavigationStack.init(path:root:destination:)` must be resolved; either Skip-ui supports the SwiftUI `NavigationStack` API or a Compose-native alternative is needed
4. **Integration test suite** -- observation stability tests, recomposition count tests, high-frequency mutation stress tests
5. **Example TCA app demonstrating all patterns** -- counter, list, navigation, persistence

Defer:
- **GRDB runtime validation**: Compiles already; runtime validation is lower risk and can come after core observation works
- **Snapshot testing on Android**: High complexity, unclear if rendering infrastructure exists
- **@Shared(.appStorage) on Android**: UserDefaults availability on Android needs investigation but is not blocking TCA apps
- **Upstream PRs**: Explicitly out of scope per project constraints; prove the fix first
- **TCA 2.0 migration**: Wait for stable release

## Sources

- Project context: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/.planning/PROJECT.md`
- Codebase concerns: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/.planning/codebase/CONCERNS.md`
- Current test state: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/.planning/codebase/TESTING.md`
- Observation bridge source: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`
- TCA ObservationStateRegistrar: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift`
- TCA AndroidParityTests: `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-composable-architecture/Tests/ComposableArchitectureTests/AndroidParityTests.swift`
- [Skip Fuse documentation](https://skip.tools/docs/modules/skip-fuse/)
- [Skip Lite and Fuse Modes](https://skip.dev/docs/modes/)
- [skip-ui GitHub](https://github.com/skiptools/skip-ui)
- [TCA GitHub](https://github.com/pointfreeco/swift-composable-architecture)
- [Skip open source announcement (Jan 2026)](https://www.infoq.com/news/2026/01/swift-skip-open-sourced/)
