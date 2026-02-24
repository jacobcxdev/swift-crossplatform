# R8 — Cross-Platform Parity Gaps Audit

**Date:** 2026-02-22
**Scope:** All 17 fork submodules in `forks/`
**Goal:** Identify iOS/Android behavioral divergences, disabled functionality, crash risks, and missing API surface that Phase 7 integration testing must cover.

---

## Summary

A comprehensive scan of all fork source files reveals **36 `#if os(Android)` guards**, **42 `#if !os(Android)` exclusions**, and **2 `#if SKIP_BRIDGE` gates** across the codebase. The majority of `#if !os(Android)` blocks are intentional exclusions of SwiftUI-specific APIs that Android handles through SkipUI/Compose equivalents. However, several gaps represent **genuine behavioral divergences** that could cause silent data loss, missed UI updates, or test flakiness on Android.

**Critical findings (3):**
1. **File system monitoring is completely disabled** on Android (no-op `DispatchSource` replacement)
2. **AppStorage subscription is a no-op** on Android (no KVO support)
3. **`useMainSerialExecutor` is disabled** in TestStore on Android, affecting test determinism

**High-severity findings (5):**
4. Multiple SwiftUI `Binding` extensions excluded on Android (Popover, NavigationStack, legacy APIs)
5. `DynamicProperty.update()` excluded on Android for `Shared`, `SharedReader`, and `Fetch`
6. `ObservedObject` is a thin shim on Android (no actual change observation)
7. `TextState` rendering extensions entirely excluded on Android
8. `swiftThreadingFatal` stub required until Swift 6.3

---

## Disabled Functionality Map

### Completely disabled on Android (no-op / excluded)

| Fork | File | What is disabled | Impact |
|------|------|-----------------|--------|
| swift-sharing | `FileStorageKey.swift:347-360` | `DispatchSource` file monitoring | `@Shared(.fileStorage)` **will not detect external file changes** on Android. Polyfill provides compile-time stub only (`FileSystemEvent` OptionSet) with no-op subscription. |
| swift-sharing | `AppStorageKey.swift:457-461` | KVO-based UserDefaults subscription | `@Shared(.appStorage)` returns no-op subscription on Android. External changes to SharedPreferences are **invisible** to the app until next manual read. |
| swift-sharing | `AppStorageKey.swift:547` | `Observer` NSObject subclass (KVO) | Entire KVO observer class excluded; Android path relies on TCA's Compose recomposition. |
| swift-sharing | `SharedReader.swift:358` | `DynamicProperty.update()` | SwiftUI lifecycle hook excluded; Android relies on SkipUI Compose recomposition instead. |
| swift-sharing | `Shared.swift:497` | `DynamicProperty.update()` | Same as above for `Shared`. |
| sqlite-data | `Fetch.swift:168` | `DynamicProperty.update()` | Database fetch results won't auto-refresh via SwiftUI lifecycle on Android. |
| sqlite-data | `FetchOne.swift:905` | `DynamicProperty.update()` | Same for single-value fetches. |
| sqlite-data | `FetchAll.swift:402` | `DynamicProperty.update()` | Same for collection fetches. |
| swift-composable-architecture | `Popover.swift:4` | Entire `popover` modifier | No popover support on Android via TCA. |
| swift-composable-architecture | `Binding+Observation.swift:14,47,290,373` | `ObservedObject.Wrapper` binding extensions | Four binding extension blocks excluded; Android uses the `ObservedObject` shim instead. |
| swift-composable-architecture | `Binding.swift:303,340` | `Binding` animation extensions | `send(action, animation:)` excluded on Android. |
| swift-composable-architecture | `NavigationStack+Observation.swift:74,111` | Navigation stack observation helpers | Two blocks of navigation stack helpers excluded. |
| swift-composable-architecture | `Store+Observation.swift:197,317` | Store observation extensions | Two blocks of store-SwiftUI integration excluded. |
| swift-composable-architecture | `ViewAction.swift:31` | `ViewAction` conformance helpers | Excluded on Android. |
| swift-composable-architecture | `ViewStore.swift:251,365,632` | `send(action, animation:)`, `send(action, while:)`, `BindingLocal` | Animated sends, state-waiting sends, and binding local all excluded. |
| swift-composable-architecture | `TestStore.swift:477-480,558,654,1006` | `useMainSerialExecutor` | Test determinism mechanism fully disabled on Android. |
| swift-composable-architecture | `IfLetStore.swift:54,145,240` | Three `IfLetStore` overloads | Excluded on Android. |
| swift-composable-architecture | `NavigationStackStore.swift:104` | Navigation stack store helpers | Excluded on Android. |
| swift-composable-architecture | `ConfirmationDialog.swift:96` | Part of confirmation dialog modifier | Excluded on Android. |
| swift-composable-architecture | `Alert.swift:91` | Part of alert modifier | Excluded on Android. |
| swift-composable-architecture | `Exports.swift:14` | Re-export of perception module | Excluded on Android (uses native `libswiftObservation.so`). |
| swift-navigation | `TextState.swift:4-849` | `TextState` -> SwiftUI `Text` rendering | **Entire SwiftUI rendering pipeline** for TextState excluded on Android. Fallback `description` conformance provided at line 849. |
| swift-navigation | `ButtonState.swift:391` | `ButtonState` -> SwiftUI `Button` rendering | Excluded on Android; fallback description conformance provided. |
| swift-navigation | `Popover.swift:1-138` | Popover presentation modifier | Entire file excluded on Android. |
| swift-navigation | `Sheet.swift:1-112` | Sheet presentation modifier | Excluded on Android. |
| swift-navigation | `NavigationLink.swift:1-70` | NavigationLink helper | Excluded on Android. |
| swift-navigation | `Bind.swift:62-71,75-84` | `AccessibilityFocusState`, `AppStorage`, `FocusedBinding`, `FocusState` `_Bindable` conformances | Focus/accessibility state binding excluded on Android. |
| swift-perception | `WithPerceptionTracking.swift:127` | `AccessibilityRotorContent`, `Commands`, `ToolbarContent` conformances | Higher-order SwiftUI protocol conformances excluded on Android. |
| swift-clocks | `SwiftUI.swift:1` | SwiftUI clock animation extensions | Entire file excluded on Android. |
| swift-snapshot-testing | `AssertSnapshot.swift:372,525` | Xcode-specific snapshot behavior | Snapshot diffing/recording excluded on non-Apple platforms. |

---

## TODO/FIXME Audit

All TODO/FIXME/HACK comments mentioning Android or cross-platform concerns:

| File | Line | Comment | Risk |
|------|------|---------|------|
| skip-ui `Gradient.swift:227` | 227 | `TODO: We are not creating an elliptical gradient (which appears to be impossible in Android)` | **Visual parity gap** — elliptical gradients render differently. |
| skip-ui `Path.swift:429` | 429 | `TODO: Process for use in SkipUI` | Dead code / incomplete port. |
| skip-ui `VectorArithmetic.swift:4` | 4 | `TODO: Process for use in SkipUI` | Animation arithmetic missing on Android. |
| skip-ui `ScrollView.swift:497` | 497 | `TODO: Process for use in SkipUI` | ScrollView internals incomplete. |
| skip-ui `LayoutTests.swift:235` | 235 | `TODO: anti-aliasing on Android doesn't yet work` | Rendering quality difference. |
| skip-ui `LayoutTests.swift:562` | 562 | `TODO: Android HStack Color elements do not seem to expand to fill the space` | **Layout parity gap** — HStack fill behavior differs. |

---

## Fatal Error Points

### Android-specific crash risks

| File | Line | Trigger | Severity |
|------|------|---------|----------|
| skip-android-bridge `SkipAndroidBridgeSamples.swift:63` | 63 | `fatalError("cannot import AndroidNative")` — fires if `AndroidNative` is unavailable | Low (sample code only) |
| skip-android-bridge `Observation.swift:316` | 316 | `swiftThreadingFatal` stub — called if `libswiftObservation.so` references the missing threading symbol | **HIGH** — crash on Android launch if Swift <6.3 and stub is stripped in release mode. The `print()` call inside is specifically to prevent stripping. |
| skip-android-bridge `Observation.swift:240` | 240 | `try!` in `Java_initPeer()` JNI class creation | **MEDIUM** — JNI failure would crash. Guarded by `isJNIInitialized` check but `try!` inside `jniContext` could still fail. |
| skip-android-bridge `Observation.swift:253` | 253 | `try!` in `Java_access()` | Same as above. |
| skip-android-bridge `Observation.swift:265` | 265 | `try!` in `Java_update()` | Same as above. |
| skip-android-bridge `ProcessInfo.swift:8` | 8 | `try!` in `ProcessInfo.androidContext` | **MEDIUM** — JNI call failure during bootstrap would crash. |
| skip-android-bridge `AndroidBridgeBootstrap.swift:125` | 125 | `try!` in `FileManager.default.url(for: .applicationSupportDirectory, ...)` | **MEDIUM** — would crash if Android file system paths are misconfigured. |

### Observation bridge `assertionFailure`

| File | Line | Condition |
|------|------|-----------|
| skip-android-bridge `Observation.swift:150` | 150 | `assertionFailure("ObservationRecording: replay closures recorded but no trigger")` — fires if recording happens without a trigger closure (programming error). Debug-only. |

---

## Stubbed/No-op APIs

| API | Fork | Behavior on Android | iOS Behavior |
|-----|------|---------------------|-------------|
| `DispatchSource.FileSystemEvent` | swift-sharing | Compile-time polyfill OptionSet, no actual monitoring | Real file system event monitoring via `DispatchSource.makeFileSystemObjectSource` |
| `FileStorage.fileSystemSource` | swift-sharing | Returns `SharedSubscription {}` (no-op) | Monitors file descriptor for write/delete/rename events |
| `AppStorageKey.subscribe()` | swift-sharing | Returns `SharedSubscription {}` (no-op) | KVO observation on UserDefaults, or NotificationCenter fallback |
| `DynamicProperty.update()` | swift-sharing, sqlite-data | Excluded (not compiled) | Called by SwiftUI lifecycle to trigger subscription setup |
| `ObservedObject` (TCA shim) | swift-composable-architecture | Thin wrapper: stores `wrappedValue`, provides `Binding` via `projectedValue`, but **does not observe changes** | SwiftUI's real `@ObservedObject` triggers view updates on `objectWillChange` |
| `useMainSerialExecutor` | swift-composable-architecture | Always false / excluded | Serializes async work to main thread for deterministic testing |
| `TextState` SwiftUI rendering | swift-navigation | `description`-based string output only | Full attributed text rendering with fonts, colors, modifiers |

---

## Foundation Availability Risks

| API | Usage Location | Android Status |
|-----|---------------|----------------|
| `ProcessInfo.processInfo` | Multiple forks (IsTesting, Logger, dependencies) | **Available** via Swift Android SDK + Skip bridge extension for `.androidContext` |
| `FileManager.default` | swift-sharing, skip-android-bridge | **Available** but paths require bootstrap via `AndroidBridgeBootstrap.bootstrapFileManagerProperties()`. Must set `XDG_DATA_HOME` / `XDG_CACHE_HOME` env vars. |
| `UserDefaults.standard` | skip-android-bridge, swift-sharing | **Available** via Skip's SharedPreferences bridge, but **no KVO support** |
| `NotificationCenter.default` | swift-sharing (AppStorage fallback) | **Available** via Swift Android SDK, but `UserDefaults.didChangeNotification` may not fire reliably |
| `URLSession` | swift-dependencies | **Available** via Swift Android SDK but untested in this project's context |
| `Data(contentsOf:)` / `Data.write(to:)` | swift-sharing (FileStorage) | **Available** on Android |
| `Bundle.main` | skip-android-bridge | **Custom bridge** via `AndroidBundle.swift` — maps to Android asset system |
| `dlopen` / `dlsym` | xctest-dynamic-overlay (IsTesting) | **Available** on Android — used for XCTest symbol detection |

---

## Combine Dependencies

Combine is **not available** on Android. The project handles this via **OpenCombineShim**:

| Fork | Approach |
|------|----------|
| combine-schedulers | `#if canImport(Combine)` / `#elseif canImport(OpenCombineShim)` pattern throughout. All scheduler types compile against OpenCombine on Android. |
| swift-composable-architecture | `import OpenCombineShim` (Store.swift line 1). `@_exported import CombineSchedulers` in Exports. |
| swift-sharing | `import CombineSchedulers` in FileStorageKey. `import Combine` guarded by platform in SharedPublisher, PassthroughRelay, Reference. |
| GRDB.swift | Direct `import Combine` in multiple files (ValueObservation, DatabaseReader/Writer, migration). **Risk:** These files likely need OpenCombineShim guards if used on Android. |
| sqlite-data | `import Combine` in Fetch, FetchAll, FetchOne, FetchKey. **Risk:** Same as GRDB — may need OpenCombineShim for Android compilation. |
| swift-perception | `import Combine` in test file only (PerceptionCheckingTests). Low risk. |
| swift-dependencies | `import Combine` in test file only (NotificationCenterTests). `@_exported import CombineSchedulers` in Exports. |

### OpenCombine Known Limitations
- `Publishers.MergeMany` not available in OpenCombine (noted in `combine-schedulers/Tests/TimerTests.swift:84`)
- `RunLoop` scheduler references in combine-schedulers may behave differently on Android where `RunLoop` semantics differ

---

## Threading Assumptions

### `DispatchQueue.main` usage (production code, not tests)

| Fork | File | Usage | Risk |
|------|------|-------|------|
| skip-android-bridge | `Observation.swift:161` | `DispatchQueue.main.async` in `stopAndObserve()` onChange handler | **Low** — intentional; triggers Compose recomposition from main thread |
| swift-sharing | `FileStorageKey.swift:349-350` | `DispatchQueue.main.async/asyncAfter` for file storage scheduling | **Low** — same pattern on both platforms |
| swift-composable-architecture | Multiple files | `@MainActor` annotations throughout | **Medium** — `@MainActor` semantics should be equivalent, but Android's main thread is the Looper thread, not a traditional Cocoa run loop |

### `DispatchSemaphore` usage (production code)

| Fork | File | Usage | Risk |
|------|------|-------|------|
| skip-android-bridge | `Observation.swift:269` | `DispatchSemaphore(value: 1)` as mutex in `BridgeObservationSupport` | **Medium** — blocking semaphore on Android main thread could cause ANR if JNI calls are slow |
| GRDB.swift | `Pool.swift:63` | `DispatchSemaphore` for connection pool | **Low** — used on background database threads |

### `@MainActor` annotations

Over 100 `@MainActor` annotations across the fork tree. Android's main thread is the Android Looper thread. Swift's `@MainActor` should map correctly via libdispatch's Android integration, but the guarantee is less battle-tested than on Apple platforms.

### `useMainSerialExecutor` disabled on Android

The `TestStore` property `useMainSerialExecutor` is completely excluded on Android via `#if !os(Android)`. This means:
- **Tests may be non-deterministic** on Android due to uncontrolled async interleaving
- The `Task.yield()` call gated behind this flag (line 1007) is also excluded
- `originalUseMainSerialExecutor` save/restore in `deinit` is excluded

---

## Severity Assessment

### P0 — Must address before Phase 7 integration tests

1. **`@Shared(.fileStorage)` silent no-op on Android** — File storage changes from external processes (or even the same app after backgrounding) will never trigger subscriber updates. Integration tests MUST verify this limitation is documented and that apps use alternative mechanisms (e.g., manual re-read on foreground).

2. **`@Shared(.appStorage)` subscription no-op on Android** — Same issue for SharedPreferences. TCA's Compose recomposition handles in-app changes, but cross-process changes (e.g., Settings app, other Android components) are invisible.

3. **TestStore non-determinism on Android** — `useMainSerialExecutor = false` means all `TestStore` tests may have race conditions. Integration tests should validate that existing parity tests pass reliably under this constraint, or document which tests are flaky.

### P1 — Should address in Phase 7

4. **`ObservedObject` shim does not observe** — The Android `ObservedObject` shim provides bindings but does NOT trigger view updates when the wrapped object changes. Any code using `@ObservedObject store` (legacy TCA pattern) will silently break on Android. Verify that all TCA code paths use the modern `@Bindable` / `@State` patterns instead.

5. **GRDB.swift and sqlite-data Combine imports** — These forks use `import Combine` without OpenCombineShim guards. If any Combine-dependent code paths are exercised on Android (e.g., `ValueObservation` publisher, `DatabaseRegionObservation` publisher), they will fail to compile or crash at runtime. Verify which GRDB Combine APIs are actually used.

6. **`swiftThreadingFatal` stub fragility** — The `print()` call inside the stub is specifically to prevent the linker from stripping it in release builds. This is a workaround that will break silently if the linker becomes more aggressive. Gated by `!swift(>=6.3)` so it auto-removes, but until then it's a launch-crash risk.

7. **JNI `try!` calls in BridgeObservationSupport** — Three `try!` force-unwraps in JNI calls (lines 240, 253, 265) that would crash if JNI context is unavailable or class loading fails. Should at minimum have error logging before crash.

### P2 — Track for future phases

8. **TextState rendering gap** — `TextState` on Android produces plain string output via `description` instead of rich attributed text. This is a known visual parity gap but affects UX, not functionality.

9. **Elliptical gradient rendering** — SkipUI cannot produce elliptical gradients on Android (linear/radial only). Visual parity gap.

10. **HStack fill behavior** — Android HStack Color elements do not expand to fill available space, producing different layouts than iOS.

11. **OpenCombine `Publishers.MergeMany` gap** — If any code path relies on `Publishers.MergeMany`, it will fail on Android via OpenCombine.

12. **`RunLoop` scheduler semantics** — `RunLoop`-based schedulers in combine-schedulers may behave differently on Android where there is no Cocoa run loop. The `DispatchQueue`-based schedulers should be preferred.

13. **`AccessibilityFocusState`, `FocusState` excluded** — Focus management APIs are not available on Android through TCA/swift-navigation. Apps using focus-based navigation will need platform-specific alternatives.

---

## Guard Count Summary

| Pattern | Count | Primary locations |
|---------|-------|-------------------|
| `#if os(Android)` | 36 | skip-android-bridge (17), swift-sharing (4), swift-composable-architecture (3), swift-navigation (4), xctest-dynamic-overlay (1), swift-snapshot-testing (2), skip-ui README (5) |
| `#if !os(Android)` | 42 | swift-composable-architecture (22), swift-navigation (9), swift-sharing (3), sqlite-data (3), swift-perception (1), swift-snapshot-testing (2), swift-clocks (1), skip-ui README (1) |
| `#if SKIP_BRIDGE` | 2 | skip-android-bridge (Observation.swift, ObservationModule.swift) |
| `#if canImport(SwiftUI) && !os(Android)` | 8 | swift-navigation (6), swift-composable-architecture (2) |

**Total conditional compilation guards affecting Android behavior: ~88**
