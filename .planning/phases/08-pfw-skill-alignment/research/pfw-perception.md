# PFW-Perception Skill Alignment — Phase 8 Research

Generated: 2026-02-23
Researcher: Claude Code Agent

---

## Executive Summary

This document captures the **canonical patterns** for the Point-Free `Perception` library and maps them against the current codebase state. Eight findings (H14, M17 from PFW audit) indicate:

1. **H14** — `@Observable` classes lack `@available` annotations (iOS 17+)
2. **M17** — `ObservationRegistrar` namespace shadows the `Observation` module on Android path

**Recommendation:** On iOS/macOS, use `@Observable` (iOS 17+, macOS 14+) with `@available` gates. On Android, delegate to `@Perceptible` via conditional imports, backed by `SkipAndroidBridge.Observation.ObservationRegistrar`.

---

## Canonical Patterns

### 1. `@Perceptible` vs `@Observable` — Backport Strategy

**From skill output:**
```
Observation vs. Perception
* `@Observable` -> `@Perceptible`
* `@ObservationIgnored` -> `@PerceptionIgnored`
* `Observations` -> `Perceptions`
* `withObservationTracking` -> `withPerceptionTracking`
```

**Macro Definition (from `/forks/swift-perception/Sources/Perception/Macros.swift:33-41`):**
```swift
@available(iOS, deprecated: 26, renamed: "Observable")
@available(macOS, deprecated: 26, renamed: "Observable")
@available(watchOS, deprecated: 26, renamed: "Observable")
@available(tvOS, deprecated: 26, renamed: "Observable")
@attached(member, names: named(_$perceptionRegistrar), named(access), named(withMutation), named(shouldNotifyObservers))
@attached(memberAttribute)
@attached(extension, conformances: Perceptible, Observable)
public macro Perceptible() =
  #externalMacro(module: "PerceptionMacros", type: "PerceptibleMacro")
```

**Pattern:** `@Perceptible` is a back-port that:
- Adds conformance to **both** `Perceptible` and `Observable` protocols
- Implements perception tracking via synthesized `_$perceptionRegistrar`
- Deprecated in future Swift versions (26+) in favor of native `@Observable`

### 2. `@available` Requirements for `@Observable`

**From Perception library (`/forks/swift-perception/Sources/PerceptionCore/Perceptible.swift:22-26`):**
```swift
@available(iOS, deprecated: 26, renamed: "Observable")
@available(macOS, deprecated: 26, renamed: "Observable")
@available(watchOS, deprecated: 26, renamed: "Observable")
@available(tvOS, deprecated: 26, renamed: "Observable")
public protocol Perceptible { }
```

**Requirement:** When using `@Observable` directly (not wrapped in `@Perceptible`), add platform availability:
```swift
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@Observable public class Counter {
    public var count: Int = 0
}
```

The availability must match iOS 17+, macOS 14+, watchOS 10+, tvOS 17+.

### 3. `WithPerceptionTracking` for SwiftUI Integration

**From skill output (Step 1: Use `WithPerceptionTracking`):**
```swift
var body: some View {
  WithPerceptionTracking {
    ...
  }
}
```

**And for closures accessing perceptible properties:**
```swift
ForEach(items) { item in
  WithPerceptionTracking {
    ...
  }
}
```

**Rules:**
- Wrap any view accessing perceptible properties in `WithPerceptionTracking`
- Wrap escaping view builder closures (ForEach, GeometryReader, etc.)
- **DO NOT** use outside of a view builder

### 4. `@Perception.Bindable` for Derived Bindings

**From skill output (Step 2):**
```swift
@State var model = MyPerceptibleModel()

var body: some View {
  @Perception.Bindable var model = model
  TextField("Title", text: $model.title)
}
```

**Pattern:** Use `@Perception.Bindable` instead of deriving directly from `@State` when working with perceptible models.

### 5. Android Path: `SkipAndroidBridge.Observation.ObservationRegistrar`

**From `/forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift:17-22`:**
```swift
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct ObservationRegistrar: Sendable, Equatable, Hashable {
    private let registrar = ObservationModule.ObservationRegistrarType()
    private let bridgeSupport = BridgeObservationSupport()

    public init() {
    }
```

**Bridge Mechanics:**
- `ObservationRegistrar` wraps native Android `ObservationModule.ObservationRegistrarType`
- `BridgeObservationSupport` handles JNI calls to Kotlin side
- Record-replay pattern: `ObservationRecording` captures access calls during body eval, replays in `withObservationTracking`

**JNI Naming Convention (line 286-287):**
```swift
// ViewObservation is in package skip.ui, so: Java_skip_ui_ViewObservation_<method>
```

---

## Current State

### H14 Finding: Missing `@available` on `@Observable` Classes

**Files with violations:**
- `/examples/fuse-library/Sources/FuseLibrary/ObservationModels.swift:7,17,24,30`
  - `@Observable public class Counter` (line 7)
  - `@Observable public class Parent` (line 17)
  - `@Observable public class Child` (line 24)
  - `@Observable public class MultiTracker` (line 30)

- `/examples/lite-app/Sources/LiteApp/ViewModel.swift:9`
  - `@Observable public class ViewModel` (line 9)

**Current code (ObservationModels.swift:7-14):**
```swift
@Observable public class Counter {
    public var count: Int = 0
    @ObservationIgnored public var ignoredValue: Int = 0
    public var label: String = ""

    public var doubleCount: Int { count * 2 }

    public init() {}
}
```

**Issue:** No `@available` guard means compilation fails on iOS < 17, macOS < 14.

### M17 Finding: `ObservationRegistrar` Namespace Shadowing

**File:** `/forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift:18`
```swift
public struct ObservationRegistrar: Sendable, Equatable, Hashable {
```

**Context:** Within module `Observation` (line 16):
```swift
public struct Observation {
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public struct ObservationRegistrar: Sendable, Equatable, Hashable {
```

**Issue:** Nested under `Observation` struct, but imports from `ObservationModule` can shadow the outer protocol. Accessed in TCA as:
```swift
// forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift:13
let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
```

**Problem:** If code imports both `Observation` module and `SkipAndroidBridge.Observation`, name collision risk.

### TCA Integration Pattern

**From `/forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift:1-20`:**
```swift
#if os(Android)
import SkipAndroidBridge
#endif

public struct ObservationStateRegistrar: Sendable {
  public private(set) var id = ObservableStateID()
  #if !os(visionOS) && !os(Android)
    @usableFromInline
    let registrar = PerceptionRegistrar()
  #elseif os(Android)
    @usableFromInline
    let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
  #else
    @usableFromInline
    let registrar = Observation.ObservationRegistrar()
  #endif
  public init() {}
```

**Pattern:**
- Non-Android, non-visionOS: Use `PerceptionRegistrar()` from Perception library
- visionOS (iOS 17+ native): Use native `Observation.ObservationRegistrar()`
- Android: Use bridged `SkipAndroidBridge.Observation.ObservationRegistrar()`

---

## Required Changes

### Change 1: Add `@available` to `@Observable` in ObservationModels.swift

**File:** `/examples/fuse-library/Sources/FuseLibrary/ObservationModels.swift`

**Before (lines 7, 17, 24, 30):**
```swift
@Observable public class Counter {
```

**After:**
```swift
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@Observable public class Counter {
```

**Apply to all four classes:**
1. `Counter` (line 7)
2. `Parent` (line 17)
3. `Child` (line 24)
4. `MultiTracker` (line 30)

### Change 2: Add `@available` to `@Observable` in ViewModel.swift

**File:** `/examples/lite-app/Sources/LiteApp/ViewModel.swift`

**Before (line 9):**
```swift
@Observable public class ViewModel {
```

**After:**
```swift
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@Observable public class ViewModel {
```

### Change 3: Rename `ObservationRegistrar` to `BridgeObservationRegistrar` in skip-android-bridge

**File:** `/forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`

**Before (line 18):**
```swift
public struct Observation {
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public struct ObservationRegistrar: Sendable, Equatable, Hashable {
```

**After:**
```swift
public struct Observation {
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public struct BridgeObservationRegistrar: Sendable, Equatable, Hashable {
```

**Rationale:** Avoids shadow collision with native `Observation.ObservationRegistrar`. The "Bridge" prefix clarifies intent.

### Change 4: Update TCA reference to renamed type

**File:** `/forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift`

**Before (line 13):**
```swift
    let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
```

**After:**
```swift
    let registrar = SkipAndroidBridge.Observation.BridgeObservationRegistrar()
```

### Change 5: Verify no other references exist

**Search for all usages of `SkipAndroidBridge.Observation.ObservationRegistrar`:**
```bash
grep -r "SkipAndroidBridge\.Observation\.ObservationRegistrar" --include="*.swift"
```

Update any remaining references to use `BridgeObservationRegistrar`.

---

## Cross-Platform Implications

### iOS/macOS Path

**Behavior:** `@Observable` classes on iOS 17+/macOS 14+ use native `libswiftObservation.so` observation runtime.

**Requirements:**
- All `@Observable` classes must have `@available(iOS 17, macOS 14, ...)` annotation
- No additional SwiftUI wrapping needed — native observation works directly
- Target: iOS 13+, macOS 10.15+ codebases need `@available` guards to prevent compilation errors on older OS versions

### Android Path

**Behavior:** `@Observable` on Android delegates to `SkipAndroidBridge.Observation.BridgeObservationRegistrar()`, which:
1. Records observation accesses during Compose view body evaluation (`ObservationRecording`)
2. Replays accesses inside `withObservationTracking` to establish proper subscriptions
3. Calls JNI methods to notify Kotlin side of state changes

**Requirements:**
- Bridge support enabled at app startup: `ObservationRecording.isEnabled = true`
- JNI exports (`Java_skip_ui_ViewObservation_*` functions) must be compiled into `libswiftObservation.so`
- Workaround for Swift < 6.3: `swiftThreadingFatal()` stub prevents linker crash (line 315-319)

**SwiftUI Integration:**
- Use `WithPerceptionTracking` to wrap view bodies
- Use `@Perception.Bindable` for state bindings
- Pattern ensures observation subscriptions fire Compose recomposition via JNI

### Test Implications

**Files using `@Observable` in tests:**
- `/examples/fuse-library/Tests/ObservationTests/ObservationTests.swift`
- `/examples/fuse-library/Tests/ObservationTests/ObservationBridgeTests.swift`

**Action:** Ensure tests that instantiate `@Observable` models also add `@available` guards if targeting iOS < 17.

---

## Ordering Dependencies

### Phase 1: Availability Annotations (NO DEPENDENCIES)

- Add `@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)` to all `@Observable` classes
- **Files affected:**
  - `examples/fuse-library/Sources/FuseLibrary/ObservationModels.swift` (4 classes)
  - `examples/lite-app/Sources/LiteApp/ViewModel.swift` (1 class)
- **Verification:** `swift build` succeeds for macOS/iOS targets

### Phase 2: Rename to Avoid Shadowing (DEPENDS ON: Phase 1)

- Rename `Observation.ObservationRegistrar` → `Observation.BridgeObservationRegistrar`
- Update TCA reference in `ObservationStateRegistrar.swift`
- **Files affected:**
  - `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`
  - `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift`
- **Verification:** Android build succeeds (`skip android build`)

### Phase 3: Integration Tests (DEPENDS ON: Phase 2)

- Run full test suite to confirm observation bridge still functions:
  - `make test` (macOS)
  - `make skip-test` (cross-platform parity)
  - `examples/fuse-library/Tests/ObservationTests/ObservationBridgeTests.swift`
- **Success:** All observation tests pass, no JNI crashes

### Phase 4: Documentation & Cleanup (DEPENDS ON: Phase 3)

- Update CLAUDE.md if necessary to reflect canonical patterns
- Verify no orphaned `ObservationRegistrar` references remain
- Document Swift 6.3 removal of `swiftThreadingFatal()` workaround

---

## Summary of Fixes

| Finding | File | Line | Issue | Fix | Priority |
|---------|------|------|-------|-----|----------|
| H14 | `ObservationModels.swift` | 7, 17, 24, 30 | Missing `@available` on `@Observable` | Add `@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)` | P0 |
| H14 | `ViewModel.swift` | 9 | Missing `@available` on `@Observable` | Add `@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)` | P0 |
| M17 | `Observation.swift` | 18 | `ObservationRegistrar` shadows module name | Rename to `BridgeObservationRegistrar` | P1 |
| M17 | `ObservationStateRegistrar.swift` | 13 | References old `ObservationRegistrar` name | Update to `BridgeObservationRegistrar` | P1 |

**Wave:** All changes align with Phase 8 PFW skill alignment. No test rewrites needed for H14/M17.
