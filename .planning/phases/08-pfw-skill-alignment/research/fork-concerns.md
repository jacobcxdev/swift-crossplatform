# Fork Concerns — Phase 8 PFW Skill Alignment

**Scouted:** 2026-02-23
**Scope:** Changes required in fork submodules to achieve PFW skill alignment

---

## Fork Changes Required

### 1. `forks/skip-android-bridge` — `DispatchSemaphore` → locking primitive

**File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift:269`

**Current code:**
```swift
private let lock = DispatchSemaphore(value: 1)
```

Used in `BridgeObservationSupport.triggerSingleUpdate()`, `Java_init(forKeyPath:)`.

**Pattern:** Acts as a mutex (value: 1), calling `lock.wait()` / `defer { lock.signal() }`. This is a semaphore-as-mutex anti-pattern. The PFW LOW finding flags this: `DispatchSemaphore` → prefer `os_unfair_lock`.

**Required change:** Replace with `os_unfair_lock` (or its Swift-friendly wrapper). The idiomatic Swift replacement is:

```swift
// import Darwin / os (already have 'import Android' on Android, which provides pthreads)
private var lockPrimitive = os_unfair_lock()

// at each call site:
os_unfair_lock_lock(&lockPrimitive)
defer { os_unfair_lock_unlock(&lockPrimitive) }
```

**Caveat:** `os_unfair_lock` is available on Darwin (macOS/iOS) and on Android via the Swift Android SDK's libc. The file is already guarded `#if SKIP_BRIDGE` and imports `Android` conditionally, so the primitive is available on both platforms. However, `os_unfair_lock` is not `Sendable` and requires the owning type to be a `class` (already the case — `BridgeObservationSupport` is `final class`). The property must be `var` (not `let`) because lock/unlock mutate it.

**Note on `@unchecked Sendable`:** `BridgeObservationSupport` is already `@unchecked Sendable`. Switching from `DispatchSemaphore` (which is itself a class reference type and reference-safe) to an `os_unfair_lock` value type embedded in a class is safe — the class reference is shared but the lock lives at a stable address inside the class, which is what `os_unfair_lock` requires.

---

### 2. `forks/skip-android-bridge` — `ObservationRegistrar` shadow type rename (M17)

**File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift:18`

**Current code:**
```swift
public struct Observation {
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public struct ObservationRegistrar: Sendable, Equatable, Hashable {
        ...
    }
    ...
}
```

The outer `struct Observation` creates a namespace that shadows the `Observation` module imported from `libswiftObservation.so`. Inside the file, `ObservationModule.ObservationRegistrarType()` is used as a type alias to access the real registrar (via a presumably local alias). Any call site that writes `Observation.ObservationRegistrar` is hitting this shadow type, not the real one.

**Audit finding M17:** "Rename namespace to avoid shadowing `Observation` module."

**Required change:** Rename the wrapper namespace from `Observation` to something that does not collide with the standard library module name. Candidates:
- `BridgeObservation` — clear provenance
- `AndroidObservation` — platform-scoped
- `SkipObservation` — matches Skip naming conventions

The internal type aliases (`ObservationModule.ObservationRegistrarType`, etc.) that currently compensate for the shadowing would then be simplified or removed.

**JNI impact:** The JNI `@_cdecl` exports (`Java_skip_ui_ViewObservation_*`) are free functions that do not reference the `Observation` struct by name. They call `ObservationRecording.*` static methods directly. No JNI binding changes are needed for this rename — see the JNI Binding Changes section for the full analysis.

---

### 3. `forks/swift-composable-architecture` — `@_spi(Reflection) import CasePaths`

**Files (7 total):**

| File | Uses |
|------|------|
| `Internal/NavigationID.swift` | `EnumMetadata(…).tag(of:)`, `EnumMetadata.project(_:)` |
| `Internal/EphemeralState.swift` | `EnumMetadata(…).tag(of:)`, `.associatedValueType(forTag:)` |
| `Internal/PresentationID.swift` | `EnumMetadata(…).tag(of:)`, `EnumMetadata.project(_:)` |
| `Reducer/Reducers/PresentationReducer.swift` | `EnumMetadata`, `.caseName(forTag:)`, `.tag(of:)` |
| `Reducer/Reducers/StackReducer.swift` | `EnumMetadata`, `.caseName(forTag:)`, `.tag(of:)` |
| `SwiftUI/NavigationDestination.swift` | `EnumMetadata(…).tag(of:)` |
| `SwiftUI/SwitchStore.swift` | `EnumMetadata(…).tag(of:)` |

**What `@_spi(Reflection)` actually provides:** The `EnumMetadata` struct and its members (`init(_:)`, `tag(of:)`, `associatedValueType(forTag:)`, `caseName(forTag:)`, `project(_:)`) plus `EnumTypeDescriptor` are all marked `@_spi(Reflection)` in `forks/swift-case-paths/Sources/CasePaths/EnumReflection.swift:195`. These are **not** public API — they are Swift reflection internals surfaced via an SPI group. The PFW LOW finding flags this as "fragile SPI."

**What removing the SPI import means:** All 7 files lose access to `EnumMetadata`. This type is used for runtime enum tag inspection — extracting which case is active, reading associated value types, and getting case names for debug logging. There is no public CasePaths API that exposes this information without `@_spi(Reflection)`.

**Realistic options:**
1. **Promote `EnumMetadata` to public in the CasePaths fork.** Since we own `forks/swift-case-paths`, we can change `@_spi(Reflection) public struct EnumMetadata` to just `public struct EnumMetadata`. This removes the SPI dependency without touching TCA's call sites. Risk: diverges further from upstream CasePaths.
2. **Keep SPI import in TCA fork only.** The audit LOW finding originated from `DependencyTests.swift` (a test file), not from the TCA fork's library code. The TCA fork's library usage of `@_spi(Reflection)` is already known to upstream pointfreeco — this is how the official TCA uses CasePaths internally. The test file usage is the spurious one.
3. **Remove from test file only.** `examples/fuse-library/Tests/TCATests/DependencyTests.swift:1` uses `@_spi(Reflection) import CasePaths` but (based on the file content seen) does not appear to use any SPI symbols directly — the import is likely a leftover. Removing it from the test file is safe and correct.

**Recommendation:** Remove `@_spi(Reflection) import CasePaths` from `DependencyTests.swift` (it is unused). Leave it in the TCA fork library files unchanged — removing it from those 7 files would require either promoting `EnumMetadata` to public or rewriting enum introspection without reflection, which is out of scope and would break navigation and presentation features.

---

### 4. `forks/swift-composable-architecture` — `private enum CancelID` → `fileprivate`

**Files (production source in Examples only):**

The grep results show that all `private enum CancelID` occurrences are in:
- `Examples/` subdirectory files (Todos, Search, CaseStudies, VoiceMemos)
- `Sources/ComposableArchitecture/TestStore.swift` — doc comment example only (line 142 is a code comment, not live code)

None of the `private enum CancelID` patterns appear in the main `Sources/ComposableArchitecture/` library production sources outside of doc comments. The audit LOW finding (`private cancel-ID enums → prefer fileprivate for CasePaths compatibility`) refers to **example code in the fork's own Examples directory** and to **user-land code in `examples/fuse-app/`**.

**Required change in fork:** No change needed in the TCA fork's library source. The Examples directory changes are illustrative only and don't affect the library or its compilation.

**Required change in user-land:** In `examples/fuse-app/Sources/FuseApp/` and any test files that define `private enum CancelID { ... }` inside a `@Reducer struct`, change `private` to `fileprivate`. This is an `examples/` change, not a `forks/` change.

---

### 5. `forks/skip-android-bridge` — `FlagBox` `@unchecked Sendable`

**Actual location:** `examples/fuse-library/Sources/FuseLibrary/ObservationVerifier.swift:277`

```swift
private final class FlagBox: @unchecked Sendable {
    var value = false
}
```

This is **not in a fork**. It is in the `examples/fuse-library/` library source. `FlagBox` is a test helper class that uses `@unchecked Sendable` because `withObservationTracking`'s `onChange` closure is `@Sendable` but the current Swift Observation implementation actually delivers `onChange` synchronously (before `willSet` returns), so no true cross-thread mutation occurs.

**The concern:** `@unchecked Sendable` suppresses compiler enforcement and relies on the undocumented synchronous-delivery behavior of `withObservationTracking`. If Apple changes delivery to be asynchronous (e.g., coalesced on the next run-loop tick), `FlagBox.value` could be read before `onChange` fires.

**Required change:** Either:
1. Add a comment documenting why `@unchecked Sendable` is safe here (the synchronous onChange contract), or
2. Replace `var value = false` with an `os_unfair_lock`-protected or `atomic` property.

Since `FlagBox` is a private test helper used only in synchronous verification methods that return `Bool` based on `flag.value`, option 1 (documentation) is lowest risk. The comment already partially exists at line 273-276.

---

### 6. `forks/xctest-dynamic-overlay` — No fork changes needed

Searched for `@_spi(Reflection)` in `forks/xctest-dynamic-overlay` — no matches found. No PFW alignment changes are required in this fork.

---

### 7. `forks/swift-perception` — No fork changes needed

Searched for `FlagBox`, `@unchecked Sendable`, `@_spi(Reflection)`, `DispatchSemaphore` in the perception fork — none of the targeted patterns appear there. The perception fork's `Locking.swift` uses `os_unfair_lock` already (it is the reference implementation). No changes required.

---

## Risk Assessment

| Change | Location | Risk | Rationale |
|--------|----------|------|-----------|
| `DispatchSemaphore` → `os_unfair_lock` | skip-android-bridge `Observation.swift` | **MEDIUM** | Correctness change in a JNI-facing concurrent lock path. The `os_unfair_lock` requires stable address (satisfied by being in a class). Must ensure `lockPrimitive` is `var`, not `let`. Needs Android runtime testing. |
| `ObservationRegistrar` namespace rename (M17) | skip-android-bridge `Observation.swift` | **LOW** | Pure rename of a wrapper `struct Observation` to `BridgeObservation`. No JNI exports reference it by name. Only affects callers of `Observation.ObservationRegistrar` — and the only caller is the file itself via internal aliases. |
| Remove `@_spi(Reflection)` from `DependencyTests.swift` | `examples/fuse-library/Tests/TCATests/` | **VERY LOW** | The import appears unused — no SPI symbols referenced in the file content. Removing it cannot break anything. |
| Leave `@_spi(Reflection)` in TCA fork library files | `forks/swift-composable-architecture` | **NO CHANGE** | These 7 files legitimately depend on `EnumMetadata` for navigation/presentation ID generation. Removing it requires either promoting `EnumMetadata` to public API in the CasePaths fork or abandoning enum reflection entirely. Both options are higher risk than leaving the SPI. |
| `FlagBox @unchecked Sendable` documentation | `examples/fuse-library/Sources/FuseLibrary/` | **VERY LOW** | Adding a comment or improving documentation. No behavior change. |
| `private enum CancelID` → `fileprivate` | `examples/fuse-app/` (user-land, not fork) | **VERY LOW** | Visibility change within a file. CasePaths case path generation needs `fileprivate` or wider access. No Android impact. |

---

## Android Impact

### `DispatchSemaphore` → `os_unfair_lock`

`DispatchSemaphore` is part of `libdispatch` (GCD), which is available on Android via the Swift Android SDK's bundled libdispatch. The replacement `os_unfair_lock` is a Darwin/POSIX primitive. On Android (Bionic libc), `os_unfair_lock` maps to a `pthread_mutex_t`-based implementation provided by the Swift Android SDK's compatibility layer.

Both are available at compile time when `import Android` is active. The change is Android-safe. Performance on Android may be marginally better with `os_unfair_lock` (avoids GCD overhead) but the difference is negligible for a low-contention lock.

The `Observation.swift` file is already gated `#if SKIP_BRIDGE` (entire file) and `#if os(Android)` (JNI exports section). The lock change affects the `BridgeObservationSupport` class which is used on both iOS and Android when `SKIP_BRIDGE` is active. No additional conditional compilation is needed.

### `ObservationRegistrar` namespace rename

`Observation.swift` is only compiled when `SKIP_BRIDGE` is defined. The rename affects no JNI-visible symbols (they are `@_cdecl` free functions, not methods on the struct). Android runtime behavior is unchanged. Kotlin/JVM-side code calls `ViewObservation.nativeEnable()` etc. via JNI — these symbol names come from the `@_cdecl` attributes, not from Swift type names.

### `@_spi(Reflection)` in TCA fork files

No Android impact from leaving these unchanged. The SPI symbols (`EnumMetadata`) are provided by the `swift-case-paths` fork which compiles to native Swift on Android. The reflection metadata approach works on Android as it does on iOS — Swift enum metadata is present in the binary regardless of platform.

### `private enum CancelID` → `fileprivate`

Pure Swift visibility change. No Android-specific impact. CasePaths macros generate the same code on Android as iOS.

---

## JNI Binding Changes

**Finding: No JNI binding changes are required for any of the planned fork changes.**

The JNI exports in `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` are:

```swift
@_cdecl("Java_skip_ui_ViewObservation_nativeEnable")
func _jni_nativeEnable(_ env: OpaquePointer?, _ thiz: OpaquePointer?)

@_cdecl("Java_skip_ui_ViewObservation_nativeStartRecording")
func _jni_nativeStartRecording(_ env: OpaquePointer?, _ thiz: OpaquePointer?)

@_cdecl("Java_skip_ui_ViewObservation_nativeStopAndObserve")
func _jni_nativeStopAndObserve(_ env: OpaquePointer?, _ thiz: OpaquePointer?)
```

These are top-level `@_cdecl` functions. Their mangled symbol names are determined entirely by the string literal in `@_cdecl(...)`, not by any Swift type or module name. The Kotlin-side `ViewObservation` object in `forks/skip-ui` declares matching `external fun` declarations with the exact same names.

Neither the `DispatchSemaphore` → `os_unfair_lock` change nor the `Observation` struct rename touches any of these export names. The `ObservationRecording` class (which the JNI functions call into) is also unaffected by the namespace rename — it is a top-level class, not nested inside `struct Observation`.

**The only scenario that would require JNI binding changes** is if the `ObservationRecording` class were renamed or moved, or if a new JNI-callable function were added. Neither is planned.

---

## Upstream Compatibility

### `DispatchSemaphore` → `os_unfair_lock` in skip-android-bridge

This change **improves** upstreamability. `DispatchSemaphore` used as a mutex is a known anti-pattern that upstream Skip would likely want to fix independently. Switching to `os_unfair_lock` is the idiomatic low-level synchronization primitive in Apple's own Swift concurrent code (e.g., swift-collections, swift-async-algorithms all use `os_unfair_lock` wrappers).

### `ObservationRegistrar` namespace rename

This change **improves** upstreamability. Shadowing the `Observation` module with a local `struct Observation` is a naming collision that makes the file confusing and would be rejected in a PR to upstream Skip. Renaming to `BridgeObservation` removes the ambiguity cleanly.

### Leaving `@_spi(Reflection)` in TCA fork library files

This change (no-op) **maintains** upstreamability at the current level. The upstream TCA repository uses the same `@_spi(Reflection) import CasePaths` pattern in the same 7 files. Our fork is already aligned with upstream on this point. Any future upstream removal of SPI usage (if pointfreeco promotes `EnumMetadata` to public) would flow in via a regular fork sync.

### Removing `@_spi(Reflection)` from `DependencyTests.swift`

This change **improves** upstreamability. A test file importing an SPI it does not use is a code smell. Removing it makes the test file cleaner and would be accepted by upstream.

### `private` → `fileprivate` for cancel-ID enums

This change **improves** upstreamability. The pfw-case-paths skill documents this as the canonical pattern. Upstream TCA examples and documentation use `fileprivate` (or no access modifier at all) for `CancelID` enums so that `@CasePathable`-generated accessors, which are synthesized at `internal` level, can reach them across file boundaries if needed.

---

## Testing Strategy

### For `DispatchSemaphore` → `os_unfair_lock`

1. **macOS unit test (existing):** Run `make test` from `examples/fuse-library/` — the `ObservationBridgeTests` suite exercises the bridge code paths that use the lock. If the lock is correctly replaced, all existing tests must continue to pass.
2. **Android integration test (required):** Run `make skip-test` or `skip android build` from `examples/fuse-library/` targeting an Android emulator. The `BridgeObservationSupport` JNI path only executes on Android. Verify that observation tracking still fires and that no crashes occur under concurrent access.
3. **Stress test (recommended):** The existing `ObservationVerifier.verifySequentialObservationCyclesResubscribe()` and `verifyNestedObservationCycles()` provide moderate concurrency coverage. No new stress test is strictly needed, but a rapid-fire mutation test (100+ sequential cycles) would expose lock ordering issues.

### For `ObservationRegistrar` namespace rename

1. **Compile verification:** `swift build` from `examples/fuse-library/` — the rename affects only `Observation.swift` internally. If any other file in the project references `Observation.ObservationRegistrar` by the old path, it will fail to compile immediately.
2. **Search for external references:** `grep -r "Observation\.ObservationRegistrar" forks/ examples/` before applying — confirm zero external callers.
3. **Android build:** `skip android build` to confirm the JNI exports still link correctly after the rename.

### For removing `@_spi(Reflection)` from `DependencyTests.swift`

1. **Compile verification only:** Remove the import line, then run `swift build` on the `TCATests` target. If no SPI symbols were used, it compiles cleanly. If any hidden SPI usage exists, the compiler will emit an error pointing at the exact symbol.
2. **Test run:** `make test-filter FILTER=DependencyTests` to confirm all tests still pass.

### For leaving TCA fork `@_spi(Reflection)` unchanged

No testing required — this is a no-op.

### For `FlagBox @unchecked Sendable` documentation

1. No behavioral change, no test needed. A documentation-only update.

### For `private` → `fileprivate` cancel-ID enums

1. **Compile verification:** `swift build` from the affected example directory.
2. **Test run:** `make test` to confirm no behavioral regression.
3. **CasePaths key-path access:** Write a test that uses `\.cancelID` case key-path syntax on the reducer's action — this is the scenario that `fileprivate` unblocks. Verify it compiles and produces the expected result.

### General regression baseline

Before any fork changes, record: `make test` passes 121 tests (91 fuse-library + 30 fuse-app). After each change, re-run and confirm the count is maintained or improved.
