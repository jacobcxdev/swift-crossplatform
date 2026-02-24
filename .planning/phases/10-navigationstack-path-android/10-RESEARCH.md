# Phase 10: skip-fuse-ui Fork Integration & Cross-Fork Audit - Research

**Researched:** 2026-02-23
**Domain:** SPM dependency resolution, skip-fuse-ui fork audit, cross-fork verification, CLAUDE.md/Makefile updates
**Confidence:** HIGH (source-verified across all 19 forks)

## Summary

Phase 10 has been rescoped from its original narrow focus (NavigationStack path binding on Android, completed in plans 10-01/10-02) to a comprehensive integration and audit phase. The expanded scope covers four workstreams:

1. **SPM Dependency Identity Resolution** -- eliminate `swift package resolve` warnings caused by the same package being referenced as both a local path and remote URL across different forks
2. **skip-fuse-ui Fork Audit** -- systematic comparison of all skip-ui modifications against skip-fuse-ui to identify missing Fuse-mode counterparts
3. **Cross-Fork Guard Audit** -- verify correctness of `#if os(Android)`, `#if !os(Android)`, and `#if SKIP_BRIDGE` guards across TCA, swift-navigation, swift-sharing, and swift-perception
4. **CLAUDE.md & Makefile Updates** -- document new gotchas, environment variables, and add smart defaults to the Makefile

Phase 11 (Presentation Dismiss on Android) has been absorbed into this phase.

<phase_requirements>
## Phase Requirements

### Original Phase 10 (Completed)

| ID | Description | Status |
|----|-------------|--------|
| NAV-01 | `NavigationStack` with `$store.scope(state: \.path, action: \.path)` renders on Android | DONE (10-01) |
| NAV-02 | Path append pushes new destination onto stack on Android | DONE (10-01) |
| NAV-03 | Path removeLast pops top destination on Android | DONE (10-01) |
| TCA-32 | `StackState<Element>` initializes, appends, indexes by StackElementID on Android | DONE (pre-existing) |
| TCA-33 | `StackAction` routes through `forEach` on Android | DONE (pre-existing) |

### Expanded Phase 10 (New)

| ID | Description | Research Support |
|----|-------------|-----------------|
| SPM-01 | `swift package resolve` produces zero identity conflict warnings for fuse-app | Fork skip-android-bridge references to local paths in 3 packages |
| SPM-02 | `swift package resolve` produces zero identity conflict warnings for fuse-library | Same fix; verify fuse-library dependency graph is clean |
| AUDIT-01 | All skip-ui fork modifications have skip-fuse-ui counterparts where needed | Audit 2 modified skip-ui files + 148 `#if !SKIP_BRIDGE` files |
| AUDIT-02 | All `#if os(Android)` guards in TCA are correct for skip-fuse-ui layer | 28 guard locations identified in TCA |
| AUDIT-03 | All `#if os(Android)` guards in swift-navigation are correct | 10 guard locations identified |
| DISMISS-01 | `@Dependency(\.dismiss)` works on Android (absorbed Phase 11) | PresentationReducer wires dismiss on all platforms; Android fallback path exists |
| DOCS-01 | CLAUDE.md updated with new gotchas, env vars, Makefile commands | Per CONTEXT.md decisions |
| DOCS-02 | Makefile updated with smart defaults (both examples, both platforms) | Per CONTEXT.md decisions |

</phase_requirements>

## Standard Stack

### SPM Dependency Resolution

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| fuse-app Package.swift | `examples/fuse-app/Package.swift` | App-level dependency declarations with 6 local forks + skip remote | Entry point for SPM resolution; has unused deps to clean |
| fuse-library Package.swift | `examples/fuse-library/Package.swift` | Test-centric deps with 14 local forks + 2 remotes | Has skip-fuse as remote URL but fork exists locally |
| sqlite-data Package.swift | `forks/sqlite-data/Package.swift` | Android conditional deps use remote URLs for skip packages | Lines 50-52: skip-bridge, skip-android-bridge, swift-jni as remote |
| swift-composable-architecture Package.swift | `forks/swift-composable-architecture/Package.swift` | Android conditional deps use remote URLs for skip packages | Lines 40-43: skip-bridge, skip-android-bridge, swift-jni as remote; skip-fuse-ui as local |
| swift-navigation Package.swift | `forks/swift-navigation/Package.swift` | Android conditional deps | Needs verification for remote URL conflicts |
| swift-sharing Package.swift | `forks/swift-sharing/Package.swift` | Uses local paths for skip-fuse and skip-fuse-ui | Already correct pattern; reference for other forks |
| .gitmodules | `.gitmodules` | 19 submodules all on `dev/swift-crossplatform` branch | Source of truth for fork list |

### skip-fuse-ui Architecture

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| SwiftUI.swift (re-export) | `forks/skip-fuse-ui/Sources/SkipFuseUI/SwiftUI.swift` | `#if os(Android) @_exported import SkipSwiftUI` / `#else @_exported import SwiftUI` | Thin umbrella; SkipFuseUI = SkipSwiftUI on Android, SwiftUI on Apple |
| SkipSwiftUI sources | `forks/skip-fuse-ui/Sources/SkipSwiftUI/` | 135 files providing Swift-generic API wrappers conforming to `SkipUIBridging` | Two-tier bridge: SkipSwiftUI (Swift generics) -> skip-ui (Kotlin/Compose) |
| SkipUIBridging protocol | `forks/skip-fuse-ui/Sources/SkipSwiftUI/Fuse/SkipUI.swift` | Protocol with `Java_view` property for bridge boundary | Every SkipSwiftUI View conforms; converts to skip-ui's Kotlin types |
| Navigation.swift | `forks/skip-fuse-ui/Sources/SkipSwiftUI/Containers/Navigation.swift` | Generic `NavigationStack<Data, Root>` with SkipUIBridging | Unlike skip-ui (non-generic), skip-fuse-ui IS generic |
| ViewModifier.swift | `forks/skip-fuse-ui/Sources/SkipSwiftUI/View/ViewModifier.swift` | `ModifiedContent<Content, Modifier>` with constraints at type level | Fixed in earlier session (generic constraints moved from where clause) |
| Transaction.swift | `forks/skip-fuse-ui/Sources/SkipSwiftUI/Animation/Transaction.swift` | `withTransaction` marked `@available(*, unavailable)` with `fatalError()` | Critical: all animated navigation/dismiss must use non-animated paths |
| EnvironmentValues.swift | `forks/skip-fuse-ui/Sources/SkipSwiftUI/Environment/EnvironmentValues.swift` | DismissAction bridging at line 59-62 | Converts `SkipUI.DismissAction` to `SkipSwiftUI.DismissAction` |
| Presentation.swift | `forks/skip-fuse-ui/Sources/SkipSwiftUI/Layout/Presentation.swift` | Alert, confirmationDialog, fullScreenCover, sheet with SkipUIBridging | 478 lines covering all presentation modifiers |

### Cross-Fork Guard Locations

| Component | Location | Purpose | Guard Count |
|-----------|----------|---------|-------------|
| TCA observation guards | `forks/swift-composable-architecture/Sources/ComposableArchitecture/` | `#if !os(Android)` and `#if canImport(SwiftUI) && !os(Android)` | 28 locations |
| TCA Dismiss.swift | `forks/swift-composable-architecture/.../Dependencies/Dismiss.swift` | Two guards at lines 90 and 122 | 2 locations |
| swift-navigation guards | `forks/swift-navigation/Sources/` | `#if !os(Android)` platform exclusions | 10 locations |
| swift-sharing guards | `forks/swift-sharing/Sources/Sharing/` | Platform-conditional dependencies | Needs enumeration |
| swift-perception guards | `forks/swift-perception/Sources/Perception/` | Android observation model | Needs enumeration |

## Architecture Patterns

### Pattern 1: SPM Local Path Conversion

**What:** Convert remote URL references to local sibling paths (`../package-name`) in every fork's Package.swift where the referenced package is also a local fork.

**Why needed:** SwiftPM SE-0292 uses directory name as package identity for local paths but URL-derived identity for remote packages. When the same package appears as both, SPM emits identity conflict warnings and may resolve unpredictably.

**Current conflict map (traced from all 19 forks):**

| Package | Referenced As Remote URL By | Should Be Local Path |
|---------|---------------------------|---------------------|
| skip-android-bridge | sqlite-data (line 51), swift-composable-architecture (line 41) | `../skip-android-bridge` |
| skip-bridge | sqlite-data (line 50), swift-composable-architecture (line 40) | Stays remote -- NOT forked |
| swift-jni | sqlite-data (line 52), swift-composable-architecture (line 42) | Stays remote -- NOT forked |

**Key insight:** Only `skip-android-bridge` causes identity conflicts because it exists as both a local fork (in `forks/skip-android-bridge`) and is referenced via remote URL (`https://source.skip.tools/skip-android-bridge.git`) by some packages. `skip-bridge` and `swift-jni` are consistently remote across all forks and don't exist as local forks, so they cause no conflicts.

**Packages that stay remote (not forked, no conflicts):**
- `skip` (skip.git) -- build toolchain
- `skip-bridge` -- JNI bridge infrastructure
- `swift-jni` -- JNI Swift bindings
- `skip-model` -- model layer
- `skip-unit` -- unit testing
- `swift-collections` -- Apple standard library extension
- `swift-concurrency-extras` -- Point-Free concurrency utilities
- `swift-docc-plugin` -- documentation
- `swift-syntax` -- macro support
- `swift-tagged` -- tagged types
- `swift-macro-testing` -- macro test support
- `OpenCombine` -- Combine backport

**Packages already using local paths correctly:**
- All 17 forks in `.gitmodules` reference each other via `../package-name` where needed
- swift-sharing correctly uses `../skip-fuse`, `../skip-fuse-ui` local paths
- Exception: `fuse-library/Package.swift` references `skip-fuse` via remote URL but a local fork exists

**Dependency graph cycle assessment:** No cycles detected. The dependency graph is a DAG:
- Leaf packages: xctest-dynamic-overlay, swift-case-paths, combine-schedulers
- Mid-tier: swift-dependencies, swift-perception, swift-custom-dump
- Top-tier: swift-composable-architecture (depends on most others)
- UI tier: skip-fuse-ui -> skip-ui, skip-android-bridge

### Pattern 2: skip-fuse-ui Two-Tier Bridge

**What:** skip-fuse-ui provides Swift-generic wrappers (SkipSwiftUI module) that conform to `SkipUIBridging` protocol, bridging to skip-ui's non-generic Kotlin/Compose implementations via the `Java_view` property.

**Architecture:**
```
App Code (Swift)
    |
    v
SkipFuseUI (re-export umbrella)
    |
    v (on Android)
SkipSwiftUI (135 Swift files, generic APIs matching SwiftUI signatures)
    |
    v (via SkipUIBridging.Java_view)
skip-ui (Kotlin/Compose implementations)
    |
    v
Jetpack Compose
```

**Key properties:**
- SkipSwiftUI types are generic (e.g., `NavigationStack<Data, Root>`) matching SwiftUI's signatures
- skip-ui types are non-generic (e.g., `NavigationStack` with `Binding<[Any]>?` path)
- The bridge boundary is the `SkipUIBridging` protocol with its `Java_view` property
- Type erasure happens at the bridge boundary: generics -> `any View` / `Any`

**Implication for TCA:** TCA's `NavigationStack` extension (`where Data == StackState<State>.PathView`) compiles on Android because skip-fuse-ui's NavigationStack IS generic. The free-function adapter from plan 10-01 may be unnecessary if the extension can be unguarded. This needs investigation during the audit.

### Pattern 3: Dismiss Mechanism on Android

**What:** TCA's `@Dependency(\.dismiss)` already has a working Android code path.

**Trace:**
1. `PresentationReducer.swift` (lines 607-610) wires `DismissEffect` on ALL platforms (no guard):
   ```swift
   .dependency(\.dismiss, DismissEffect { @MainActor in
       Task._cancel(id: PresentationDismissID(), navigationID: destinationNavigationIDPath)
   })
   ```
2. `Dismiss.swift` line 90: `#if canImport(SwiftUI) && !os(Android)` routes to animated dismiss on iOS
3. `Dismiss.swift` lines 98-119: Android fallback calls `dismiss()` directly (the closure from PresentationReducer)
4. `EnvironmentValues.swift` in skip-fuse-ui: DismissAction bridged from `SkipUI.DismissAction`

**Assessment:** Dismiss should work on Android. The existing `withKnownIssue` wrappers in tests may be masking success. The audit should verify dismiss works end-to-end and remove `withKnownIssue` if so.

### Pattern 4: withTransaction Unavailability

**What:** `withTransaction` is `@available(*, unavailable)` with `fatalError()` in skip-fuse-ui's Transaction.swift.

**Impact:**
- Any code path that calls `withTransaction` will crash at runtime on Android
- Dismiss.swift's `callAsFunction(animation:)` and `callAsFunction(transaction:)` methods at line 122+ use `withTransaction`
- These are guarded by `#if canImport(SwiftUI) && !os(Android)` so they're not reachable on Android
- Any NEW code must avoid `withTransaction` -- use plain `store.send()` for state mutations

**Assessment:** Currently safe. All `withTransaction` call sites are correctly guarded. The audit should verify no new unguarded paths exist.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SPM identity conflicts | Manual dependency pinning | Local sibling paths (`../package-name`) | SwiftPM resolves local paths by directory identity |
| Missing skip-fuse-ui wrapper | Copy-paste from skip-ui | Follow existing SkipSwiftUI pattern (struct + SkipUIBridging extension) | Maintains architectural consistency |
| Android observation | Custom observation system | skip-android-bridge's ObservationRecording + skip-ui's ViewObservation | Already working; Phase 1 solved this |
| Dismiss on Android | Custom dismiss handling | Existing DismissEffect fallback path in Dismiss.swift | PresentationReducer already wires it on all platforms |
| Build verification | Manual builds | Makefile targets (`make build`, `make android-build`, etc.) | Reproducible, documented commands |

## Common Pitfalls

### Pitfall 1: SPM Identity Conflict From Mixed Local/Remote References

**What goes wrong:** `swift package resolve` emits warnings like "dependency 'skip-android-bridge' has an identity conflict" when one fork uses `../skip-android-bridge` (local) and another uses `https://source.skip.tools/skip-android-bridge.git` (remote).
**Why it happens:** SwiftPM SE-0292 derives package identity differently for local paths (directory name) vs remote URLs (URL-derived). Same package, two identities = conflict.
**How to avoid:** Every reference to a forked package must use the local path form. Systematically audit ALL Package.swift files.
**Warning signs:** Yellow warnings during `swift package resolve` mentioning "identity" or "conflict".

### Pitfall 2: Forking a Package That Doesn't Need Forking

**What goes wrong:** Forking skip-bridge or swift-jni creates unnecessary maintenance burden and potential divergence.
**Why it happens:** Over-eager application of "fork anything that depends on a fork" rule.
**How to avoid:** Only fork if the package actually appears as BOTH local and remote in the dependency graph. skip-bridge and swift-jni are consistently remote everywhere -- no conflict, no fork needed.
**Warning signs:** Submodule with zero code changes on dev/swift-crossplatform branch.

### Pitfall 3: Assuming skip-fuse-ui Fork Has Our Changes

**What goes wrong:** Building with skip-fuse-ui fork expecting the ModifiedContent fix or other changes, but they're not committed.
**Why it happens:** `git diff main..dev/swift-crossplatform` in skip-fuse-ui shows zero changes -- the fork branch has no divergence from upstream main. Prior session fixes may exist only in working directory.
**How to avoid:** Check `git status` in skip-fuse-ui fork before building. Commit any uncommitted changes. Verify with `git log --oneline main..dev/swift-crossplatform`.
**Warning signs:** Build failures that were previously fixed. ModifiedContent protocol conformance errors.

### Pitfall 4: Partial Package.swift Conversion

**What goes wrong:** Converting some forks' Package.swift to local paths but not all creates a mixed state where new conflicts appear.
**Why it happens:** Dependency graph is transitive. If A depends on B (local) and B depends on C (remote), but A also depends on C (local), the conflict propagates.
**How to avoid:** Per CONTEXT.md decision: SPM changes must be atomic -- convert ALL Package.swift files in one plan. One commit per fork submodule, parent repo updates all submodule pointers in a single commit.
**Warning signs:** Build works for fuse-library but fails for fuse-app (or vice versa) after partial conversion.

### Pitfall 5: JVM Type Erasure in NavigationStack Destination Matching

**What goes wrong:** `navigationDestination(for: StackState<State>.Component.self)` registers a destination type, but at JVM runtime `type(of: value)` may return an erased type, causing destination lookup to fail (blank screen on push).
**Why it happens:** JVM erases generic type parameters. `StackState<PathA.State>.Component` and `StackState<PathB.State>.Component` may be identical types at runtime.
**How to avoid:** skip-fuse-ui's Navigation.swift uses `String(describing: type(of: value))` for destination keys, which may preserve enough type info. Test with Android emulator. If lookup fails, use `destinationKeyTransformer` parameter.
**Warning signs:** Push navigation shows blank screen. Navigator logs show no matching destination.

## Code Examples

### SPM Local Path Fix (sqlite-data)

**Before:**
```swift
// forks/sqlite-data/Package.swift lines 50-52
+ (android ? [
    .package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
    .package(url: "https://source.skip.tools/skip-android-bridge.git", "0.6.1"..<"2.0.0"),
    .package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
] : []),
```

**After:**
```swift
+ (android ? [
    .package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
    .package(path: "../skip-android-bridge"),  // local fork
    .package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
] : []),
```

### SPM Local Path Fix (swift-composable-architecture)

**Before:**
```swift
// forks/swift-composable-architecture/Package.swift lines 39-44
+ (android ? [
    .package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
    .package(url: "https://source.skip.tools/skip-android-bridge.git", "0.6.1"..<"2.0.0"),
    .package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
    .package(path: "../skip-fuse-ui"),
] : []),
```

**After:**
```swift
+ (android ? [
    .package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
    .package(path: "../skip-android-bridge"),  // local fork
    .package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
    .package(path: "../skip-fuse-ui"),
] : []),
```

### SkipSwiftUI Wrapper Pattern (for gap fills)

```swift
// Pattern for adding missing skip-fuse-ui counterparts
// File: forks/skip-fuse-ui/Sources/SkipSwiftUI/SomeFeature/NewWrapper.swift

import SkipUI

public struct SomeNewView<Content: View>: View, SkipUIBridging {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    #if !os(Android)
    public var body: some View {
        content  // On Apple, delegate to SwiftUI
    }
    #else
    public var body: some View {
        fatalError("Use Java_view on Android")
    }
    #endif
}

#if os(Android)
extension SomeNewView: SkipUIBridging {
    public var Java_view: any SkipUI.View {
        return SkipUI.SomeNewView(content.Java_viewOrEmpty)
    }
}
#endif
```

### Makefile Smart Defaults

```makefile
# Smart defaults: both examples, both platforms
EXAMPLES ?= fuse-library fuse-app

.PHONY: build
build: $(foreach ex,$(EXAMPLES),build-$(ex))

build-%:
    cd examples/$* && swift build

.PHONY: test
test: $(foreach ex,$(EXAMPLES),test-$(ex))

test-%:
    cd examples/$* && swift test

.PHONY: android-build
android-build: $(foreach ex,$(EXAMPLES),android-build-$(ex))

android-build-%:
    cd examples/$* && skip android build --configuration release --arch aarch64
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Remote URLs for all skip packages | Local paths for forked packages | This phase | Eliminates SPM identity conflicts |
| skip-fuse-ui unforked (upstream only) | Forked with `dev/swift-crossplatform` branch | Pre-phase 10 | Enables customization for TCA compatibility |
| NavigationStack platform split | Unified code path via adapter | Plans 10-01/10-02 | Single `NavigationStack(path:root:destination:)` call |
| Phase 11 separate (Presentation Dismiss) | Absorbed into Phase 10 audit | Phase rescope | Comprehensive audit covers all gaps |
| Single EXAMPLE= target | Smart defaults covering both examples | This phase | `make build` tests everything |

## Open Questions

### 1. How Many skip-fuse-ui Counterparts Are Actually Missing?

**What we know:** skip-ui has 148 files with `#if !SKIP_BRIDGE` guards and only 2 files modified in our fork. skip-fuse-ui has 135 SkipSwiftUI source files from upstream.
**What's unclear:** How many of the 148 guarded skip-ui files expose APIs that TCA/Point-Free tools need but skip-fuse-ui doesn't wrap. The audit must produce a formal gap report.
**Recommendation:** Systematic file-by-file comparison during the gap audit plan. Focus on APIs actually used by fuse-app and fuse-library imports first.

### 2. Is the Plan 10-01 Free-Function Adapter Still Needed?

**What we know:** The adapter was created because skip-ui's NavigationStack is non-generic. But skip-fuse-ui's NavigationStack IS generic (`NavigationStack<Data, Root>`). TCA's extension adds constraints on the generic Data parameter.
**What's unclear:** Whether TCA's `extension NavigationStack where Data == StackState<State>.PathView` can compile against skip-fuse-ui's generic NavigationStack on Android. If yes, the free-function adapter is redundant.
**Recommendation:** Test during the audit. If the extension compiles, the adapter can be simplified or removed. If not (due to type erasure at the SkipUIBridging boundary), the adapter remains necessary.

### 3. Are There Additional Packages That Need Local Path Conversion?

**What we know:** Traced the full dependency graph and identified skip-android-bridge as the only package causing identity conflicts. swift-navigation also has android conditional deps that need checking.
**What's unclear:** Whether swift-navigation, swift-perception, or any other fork has remote URLs for skip-android-bridge.
**Recommendation:** The SPM resolution plan must grep ALL Package.swift files for `skip-android-bridge` URL references and convert them.

### 4. Does the skip-fuse-ui Fork Have Uncommitted Changes?

**What we know:** `git diff main..dev/swift-crossplatform` shows zero changes in the skip-fuse-ui fork. The ModifiedContent fix from a prior session may be uncommitted.
**What's unclear:** Whether `git status` in the skip-fuse-ui working directory shows unstaged changes.
**Recommendation:** First action in the SPM plan should be to check and commit any uncommitted skip-fuse-ui changes.

### 5. JVM Type Erasure Risk for navigationDestination(for:)

**What we know:** skip-fuse-ui uses `String(describing: type(of: value))` for destination key matching. TCA uses `StackState<State>.Component` as the destination type.
**What's unclear:** Whether `String(describing:)` preserves enough type information on JVM to distinguish `StackState<PathA.State>.Component` from `StackState<PathB.State>.Component`.
**Recommendation:** Must be investigated and resolved BEFORE gap fixes. If erasure is a problem, the solution is to use a custom `destinationKeyTransformer` or embed type identity in Component's description.

## SPM Dependency Graph

### Full Transitive Map

```
fuse-app
  -> skip (remote)
  -> skip-fuse-ui (local fork)
  -> skip-android-bridge (local fork)
  -> skip-ui (local fork)
  -> swift-composable-architecture (local fork)
  -> swift-dependencies (local fork)
  -> sqlite-data (local fork)

fuse-library
  -> skip (remote)
  -> skip-fuse (remote URL -- should be local fork path)
  -> skip-fuse-ui (local fork)
  -> skip-android-bridge (local fork)
  -> skip-ui (local fork)
  -> swift-composable-architecture (local fork)
  -> swift-dependencies (local fork)
  -> sqlite-data (local fork)
  -> swift-navigation (local fork)
  -> swift-sharing (local fork)
  -> swift-perception (local fork)
  -> swift-case-paths (local fork)
  -> swift-custom-dump (local fork)
  -> swift-identified-collections (local fork)
  -> xctest-dynamic-overlay (local fork)
  -> combine-schedulers (local fork)
  -> GRDB.swift (local fork)
  -> swift-structured-queries (local fork)
  -> swift-snapshot-testing (local fork)
  -> swift-clocks (local fork)

sqlite-data (CONFLICT)
  -> skip-bridge (remote) -- OK, not forked
  -> skip-android-bridge (REMOTE URL -- MUST convert to local path)
  -> swift-jni (remote) -- OK, not forked
  -> GRDB.swift (local fork)
  -> swift-concurrency-extras (remote) -- OK, not forked
  -> swift-custom-dump (local fork)
  -> swift-dependencies (local fork)
  -> swift-perception (local fork)
  -> swift-sharing (local fork)
  -> swift-snapshot-testing (local fork)
  -> swift-structured-queries (local fork)
  -> swift-tagged (remote) -- OK, not forked
  -> swift-collections (remote) -- OK, not forked
  -> xctest-dynamic-overlay (local fork)

swift-composable-architecture (CONFLICT)
  -> skip-bridge (remote) -- OK, not forked
  -> skip-android-bridge (REMOTE URL -- MUST convert to local path)
  -> swift-jni (remote) -- OK, not forked
  -> skip-fuse-ui (local fork)
  -> combine-schedulers (local fork)
  -> swift-case-paths (local fork)
  -> swift-concurrency-extras (remote) -- OK, not forked
  -> swift-custom-dump (local fork)
  -> swift-dependencies (local fork)
  -> swift-identified-collections (local fork)
  -> swift-navigation (local fork)
  -> swift-perception (local fork)
  -> swift-sharing (local fork)
  -> xctest-dynamic-overlay (local fork)
  -> OpenCombine (remote) -- OK, not forked
  -> swift-collections (remote) -- OK, not forked
  -> swift-syntax (remote) -- OK, not forked
```

### Conflict Resolution Summary

| Action | Package | Forks Affected | Change |
|--------|---------|----------------|--------|
| Convert to local path | skip-android-bridge | sqlite-data, swift-composable-architecture, (check swift-navigation) | URL -> `../skip-android-bridge` |
| Convert to local path | skip-fuse | fuse-library | URL -> `../../forks/skip-fuse` |
| Remove unused deps | fuse-app | fuse-app | Remove swift-dependencies, skip-android-bridge, skip-ui if unused by targets |
| Keep remote | skip-bridge, swift-jni, skip, skip-model | All | Not forked, no conflicts |
| Verify | swift-navigation, swift-perception, swift-sharing | Each fork | Grep for any remaining remote URLs referencing forked packages |

## Guard Audit Summary

### TCA Guards (`#if !os(Android)` and `#if canImport(SwiftUI) && !os(Android)`)

28 locations across ComposableArchitecture sources. Key categories:

| Category | Files | Assessment |
|----------|-------|------------|
| SwiftUI import guards | Multiple | Correct -- `import SwiftUI` not available on Android, use SkipFuseUI |
| ObservedObject.Wrapper (deprecated) | NavigationStack+Observation.swift:74 | Keep guarded -- deprecated API |
| Perception.Bindable | NavigationStack+Observation.swift:111 | Keep guarded -- type doesn't exist on Android |
| NavigationStack extension | NavigationStack+Observation.swift:150 | **INVESTIGATE** -- may work with skip-fuse-ui's generic NavigationStack |
| withTransaction/animation guards | Dismiss.swift:90, :122 | Correct -- withTransaction is fatalError on Android |
| UIKit-specific code | Various | Correct -- UIKit not available on Android |

### swift-navigation Guards

10 locations. Key categories:

| Category | Assessment |
|----------|------------|
| SwiftUI import guards | Correct |
| UIKit navigation | Correct -- UIKit not available |
| Combine-specific | Needs review -- OpenCombine may be available |

## Dismiss Analysis

### Full Chain Trace

```
User code: store.send(.destination(.dismiss))
    |
    v
PresentationReducer._presentChild() [all platforms]
    - Sets DismissEffect { Task._cancel(id: PresentationDismissID(), ...) }
    |
    v
@Dependency(\.dismiss) in child reducer
    |
    v
DismissEffect.callAsFunction() [Dismiss.swift]
    |
    +-- iOS: callAsFunction(animation: nil) -> withTransaction -> dismiss()
    |
    +-- Android: dismiss() directly [line 98-119]
        |
        v
    PresentationReducer-provided closure
        |
        v
    Task._cancel(id: PresentationDismissID())
```

**Assessment:** The mechanism is complete on Android. The `dismiss()` closure is set by PresentationReducer on all platforms. The Android path skips animation (correct, since `withTransaction` is unavailable) and calls the closure directly. This should work.

**Verification needed:** Run dismiss tests on Android without `withKnownIssue`. If they pass, dismiss was never actually broken -- the `withKnownIssue` wrapper was overly cautious.

## Sources

### Primary (HIGH confidence)
- Direct source analysis of all 19 fork Package.swift files for SPM dependency graph
- Direct source analysis of skip-fuse-ui's 135 SkipSwiftUI source files (structure and patterns)
- Direct source analysis of NavigationStack+Observation.swift (589 lines, all guards verified)
- Direct source analysis of Dismiss.swift (183 lines, full chain traced)
- Direct source analysis of PresentationReducer.swift (dismiss wiring at lines 607-610)
- Direct source analysis of skip-fuse-ui Navigation.swift (597 lines, generic NavigationStack confirmed)
- Direct source analysis of skip-fuse-ui Transaction.swift (withTransaction unavailability confirmed)
- Direct source analysis of skip-fuse-ui EnvironmentValues.swift (DismissAction bridging confirmed)
- .gitmodules showing all 19 submodules with branch tracking

### Secondary (MEDIUM confidence)
- Phase 10 CONTEXT.md decisions (locked by user, govern all planning)
- Prior plans 10-01 and 10-02 (completed, provide baseline)
- Phase 10 verification report (4/5 truths verified, Android runtime pending)
- skip.dev documentation (NavigationStack: High support, DismissAction: Full support)

### Tertiary (LOW confidence)
- JVM generic type erasure behavior for `type(of:)` / `String(describing:)` -- needs runtime verification
- skip-fuse-ui fork uncommitted changes status -- needs `git status` check
- Exact count of missing skip-fuse-ui counterparts -- needs systematic audit

## Metadata

**Confidence breakdown:**
- SPM dependency graph: HIGH -- every Package.swift traced, conflicts identified
- skip-fuse-ui architecture: HIGH -- 135 source files examined, bridging pattern understood
- Dismiss mechanism: HIGH -- full chain traced from user code through PresentationReducer to Android fallback
- Guard audit: MEDIUM -- locations enumerated but correctness assessment pending per-guard analysis
- Gap count: LOW -- needs systematic audit to produce gap report

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (stable -- fork code under project control)
