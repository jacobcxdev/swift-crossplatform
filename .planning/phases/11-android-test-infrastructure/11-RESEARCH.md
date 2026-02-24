# Phase 11: Android Test Infrastructure - Research

**Researched:** 2026-02-24
**Domain:** Skip test transpilation, skipstone plugin coverage, XCGradleHarness, Gradle/SPM local package symlink resolution
**Confidence:** HIGH (source-verified against actual codebase state and canonical Skip testing patterns)

## Summary

Phase 11 addresses the fundamental gap identified by the v1.0 milestone audit: no Android tests have ever executed for the example projects. Three blockers must be resolved in sequence:

1. **xctest-dynamic-overlay import guards** -- Already fixed in Phase 09-01. `IsTesting.swift` and `SwiftTesting.swift` (Internal) both have `#if os(Android) import Android #endif` guards. Success criterion 1 is already satisfied.

2. **Missing skipstone plugin on test targets** -- 5 of 7 test targets in fuse-library and 1 of 2 non-main test targets in fuse-app lack the `skipstone` plugin. Without it, Skip cannot transpile these Swift tests to Kotlin/JUnit. Adding the plugin will trigger compilation errors that must be resolved (missing Android imports, unavailable APIs, `#if !SKIP` guards on non-transpilable code).

3. **JUnit stubs vs. canonical XCGradleHarness** -- Both XCSkipTests.swift files write fake JUnit XML (`tests="0"`) instead of using Skip's canonical `XCGradleHarness`/`runGradleTests()` pattern. The root cause is that local fork path overrides (`../../forks/`) break Gradle's Swift dependency resolution through skipstone symlinks. This is the hardest problem in the phase -- solving it requires either fixing skipstone's local package resolution or restructuring how forks are consumed.

**Primary recommendation:** Fix in order: (1) confirm import guards already done, (2) add skipstone plugin to all test targets and resolve compilation errors, (3) investigate and fix the skipstone/Gradle local package symlink incompatibility so XCGradleHarness can replace the JUnit stubs.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-10 | Integration tests verify observation bridge prevents infinite recomposition on Android emulator | Requires skipstone on ObservationTests (already present) + XCGradleHarness restoration + actual Robolectric/emulator execution. ObservationBridgeTests.swift and StressTests.swift are `#if !SKIP` gated -- they test native Swift Observation which cannot transpile to Kotlin. Android observation testing may need separate Kotlin-native test approaches or emulator-only validation. |
| TEST-11 | Stress tests confirm stability under >1000 TCA state mutations/second on Android | StressTests.swift is `#if !SKIP` gated. TCA Store-based stress tests require native Swift runtime, not Kotlin transpilation. This requirement needs either: (a) an Android-native stress test via emulator with `ANDROID_SERIAL`, or (b) Robolectric tests exercising the Kotlin-transpiled TCA path. Current stress test achieves 229K mut/sec on macOS. |
| TEST-12 | A fuse-app example demonstrates full TCA app on both iOS and Android | Requires fuse-app's XCSkipTests to use real XCGradleHarness so FuseAppTests actually transpile and run. Also requires FuseAppIntegrationTests to have skipstone plugin. The fuse-app already has 6 features (Counter, Todos, Contacts, Database, Settings + root coordinator) that build on Android. |

</phase_requirements>

## Standard Stack

### Core

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| Skip (skipstone plugin) | `skip` package, v1.7.2+ | SPM build plugin that transpiles Swift to Kotlin and runs Gradle | Required for ALL targets that should produce Android artifacts |
| SkipTest (XCGradleHarness) | `skip` package, `SkipTest` product | XCTest harness that invokes Gradle to run transpiled JUnit tests | Canonical pattern per skip.dev -- every Skip test target needs this |
| Robolectric | Bundled via Skip's Gradle config | JVM-based Android runtime simulator | Enables Android tests without physical device or emulator |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `ANDROID_SERIAL` env var | Routes `runGradleTests()` to a specific device/emulator via `adb` | When testing on real hardware or emulator instead of Robolectric |
| `#if !SKIP` guard | Excludes non-transpilable Swift code from Kotlin generation | For code using native Swift Observation, dlopen, or other non-Kotlin-compatible APIs |
| `#if os(Android)` guard | Runtime platform detection | For code that should only execute on Android (not during Robolectric tests on macOS) |

## Architecture Patterns

### Pattern 1: Canonical XCSkipTests.swift (XCGradleHarness)

**What:** Every Skip-enabled test target must have exactly one `XCSkipTests.swift` file conforming to `XCGradleHarness`.
**When to use:** Every test target that has the `skipstone` plugin.
**Source:** Verified from working examples: `forks/skip-android-bridge/Tests/*/XCSkipTests.swift`, `examples/lite-app/Tests/*/XCSkipTests.swift`

```swift
import Foundation
#if os(macOS) // Skip transpiled tests only run on macOS targets
import SkipTest

@available(macOS 13, macCatalyst 16, *)
final class XCSkipTests: XCTestCase, XCGradleHarness {
    public func testSkipModule() async throws {
        try await runGradleTests()
    }
}
#endif
```

**Key details:**
- `#if os(macOS)` guard -- Gradle only runs on macOS host (not on iOS sim or Android)
- `import SkipTest` -- provides `XCGradleHarness` protocol
- `runGradleTests()` -- invokes Gradle to compile transpiled Kotlin and execute JUnit tests
- Must be `async throws` -- Gradle execution is async
- The `SkipTest` product must be a dependency of the test target

### Pattern 2: Non-Transpilable Test Gating

**What:** Tests that use APIs not available in Skip's Kotlin transpilation must be wrapped in `#if !SKIP`.
**When to use:** Tests using native `withObservationTracking`, `dlopen`/`dlsym`, Combine, or any Apple-only framework.

```swift
#if !SKIP
import XCTest
import Observation

final class ObservationBridgeTests: XCTestCase {
    func testBridgeTracking() {
        // Uses native Swift Observation -- cannot transpile to Kotlin
    }
}
#endif
```

**Current `#if !SKIP` gated files in the project:**
- `examples/fuse-library/Tests/ObservationTests/ObservationBridgeTests.swift` (native Observation)
- `examples/fuse-library/Tests/ObservationTests/StressTests.swift` (native Observation + Store)

### Pattern 3: Test Target with skipstone Plugin

**What:** Every test target that should produce Android tests needs `skipstone` plugin + `SkipTest` dependency.
**When to use:** All test targets in Skip-enabled packages.

```swift
.testTarget(name: "MyTests", dependencies: [
    "MyLibrary",
    .product(name: "SkipTest", package: "skip"),
    // ... other deps
], plugins: [.plugin(name: "skipstone", package: "skip")])
```

### Anti-Patterns to Avoid

- **JUnit XML stubs instead of XCGradleHarness:** Writing fake JUnit results makes `skip test` silently report 0 tests as passing. This is the current state and must be fixed.
- **Adding skipstone without SkipTest dependency:** The skipstone plugin transpiles code but `XCGradleHarness`/`runGradleTests()` requires the `SkipTest` product to be available.
- **Assuming `#if !SKIP` tests run on Android:** They do not. `#if !SKIP` code is stripped during transpilation. Tests gated this way only run on macOS.
- **Mixing `#if !os(Android)` with Skip transpilation concerns:** Use `#if !SKIP` for transpilation exclusion. `#if os(Android)` is for runtime platform detection.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JUnit test results | Manual JUnit XML generation | `XCGradleHarness`/`runGradleTests()` | Skip handles all Gradle orchestration, test result collection, and parity reporting |
| Android test detection | Custom `isTesting` logic | `IssueReporting.isTesting` from xctest-dynamic-overlay fork | Already has `#if os(Android)` path with dlopen/dlsym + process args + env var detection |
| Test transpilation | Manual Kotlin test files | `skipstone` SPM plugin | Automatic Swift-to-Kotlin transpilation handles all the boilerplate |

**Key insight:** Skip's test infrastructure is designed as a closed system: `skipstone` transpiles, `XCGradleHarness` invokes Gradle, Gradle runs JUnit, results feed back to Xcode/`skip test`. Hand-rolling any part breaks the feedback loop.

## Common Pitfalls

### Pitfall 1: Skipstone Symlink Resolution with Local Fork Paths

**What goes wrong:** When `Package.swift` uses `../../forks/` relative paths for dependencies, the skipstone plugin creates symlinks in the Gradle project that point to these local paths. Gradle's Swift dependency resolution follows symlinks differently than SPM, causing `NO-SOURCE` for Kotlin compile tasks. No JUnit results directory is created, and `runGradleTests()` throws.
**Why it happens:** The skipstone plugin symlinks local SPM packages into the Gradle project tree. Gradle's dependency resolution follows a different path than SPM's when resolving transitive dependencies through these symlinks. With 19 local forks, the symlink chain becomes too deep/complex for Gradle to resolve.
**How to avoid:** This is the primary technical challenge of Phase 11. Possible approaches:
  1. **Fix skipstone's symlink resolution** -- Modify the skipstone plugin to handle local path overrides correctly. HIGH difficulty, requires Skip framework internals knowledge.
  2. **Use Gradle `includeBuild` or `composite builds`** -- Configure Gradle to resolve local forks directly instead of through SPM symlinks. MEDIUM difficulty but requires Gradle expertise.
  3. **Flatten the dependency graph for test targets** -- Reduce transitive dependency depth by consolidating test dependencies. LOW effectiveness, may not solve root cause.
  4. **Publish fork artifacts to local Maven repo** -- Use `./gradlew publishToMavenLocal` for each fork, then Gradle resolves from Maven instead of symlinks. MEDIUM difficulty, adds build step.
  5. **Accept Robolectric-only for complex targets, emulator for E2E** -- Use `XCGradleHarness` only for targets with simple dependency graphs; test complex scenarios via `skip android test` with emulator. PRAGMATIC fallback.
**Warning signs:** `runGradleTests()` throws with missing test-results directory; Gradle logs show `NO-SOURCE` for `compileDebugUnitTestKotlin`; symlink chain exceeds filesystem limits.

### Pitfall 2: Adding skipstone to Targets with Non-Transpilable Dependencies

**What goes wrong:** Adding `skipstone` plugin to a test target that imports frameworks not available in Skip's transpiler (e.g., Combine, XCTest internals, raw Swift Observation) causes Kotlin compilation errors.
**Why it happens:** The skipstone plugin transpiles ALL Swift files in the target (except those gated by `#if !SKIP`). If any file imports a module not available in the Kotlin world, transpilation fails.
**How to avoid:** Gate non-transpilable test files with `#if !SKIP`. Ensure all test files that should transpile only import modules that Skip can handle.
**Warning signs:** Kotlin compilation errors referencing unknown imports; `Unresolved reference` errors in generated Kotlin code.

### Pitfall 3: Test Target Missing SkipTest Dependency

**What goes wrong:** Adding `skipstone` plugin without also adding `SkipTest` as a dependency means the `XCSkipTests.swift` file cannot import `SkipTest` and conform to `XCGradleHarness`.
**Why it happens:** The `skipstone` plugin and `SkipTest` product are separate -- plugin handles transpilation, product provides the test harness.
**How to avoid:** Always add both together: `plugins: [.plugin(name: "skipstone")]` AND `.product(name: "SkipTest", package: "skip")` in dependencies.

### Pitfall 4: Observation Bridge Tests Cannot Transpile

**What goes wrong:** Tests that directly use `withObservationTracking` from Swift's native `Observation` module cannot be transpiled to Kotlin because Skip's Kotlin runtime does not expose the native observation API.
**Why it happens:** The observation bridge (`ObservationRecording`, JNI exports) is native Swift code that runs on Android via the Swift runtime. It is not Kotlin. Skip transpiles Swift to Kotlin, but observation internals stay in Swift-land.
**How to avoid:** Keep observation bridge tests gated with `#if !SKIP`. Verify observation behavior on Android via emulator testing (`ANDROID_SERIAL` + `skip android test`) or through higher-level TCA tests that exercise the bridge indirectly.

## Code Examples

### Current State: JUnit Stub (WRONG -- to be replaced)

```swift
// examples/fuse-library/Tests/ObservationTests/XCSkipTests.swift (CURRENT)
// Creates fake JUnit XML with tests="0" -- bypasses all Android testing
#if !os(Android)
final class XCSkipTests: XCTestCase {
    func testSkipModule() throws {
        let resultsDir = buildDir.appendingPathComponent("...")
        try FileManager.default.createDirectory(at: resultsDir, ...)
        let junitXML = """
            <testsuite tests="0" .../>
            """
        try junitXML.write(to: resultsDir.appendingPathComponent("TEST-...xml"), ...)
    }
}
#endif
```

### Target State: Canonical XCGradleHarness (CORRECT)

```swift
// examples/fuse-library/Tests/ObservationTests/XCSkipTests.swift (TARGET)
import Foundation
#if os(macOS)
import SkipTest

@available(macOS 13, macCatalyst 16, *)
final class XCSkipTests: XCTestCase, XCGradleHarness {
    public func testSkipModule() async throws {
        try await runGradleTests()
    }
}
#endif
```

### Test Target Configuration: Before and After

```swift
// BEFORE (fuse-library TCATests -- no skipstone, no SkipTest)
.testTarget(name: "TCATests", dependencies: [
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
]),

// AFTER (with skipstone and SkipTest)
.testTarget(name: "TCATests", dependencies: [
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
    .product(name: "SkipTest", package: "skip"),
], plugins: [.plugin(name: "skipstone", package: "skip")]),
```

## State of the Art

### Current Codebase State (as of 2026-02-24)

| Issue | Current State | Target State | Blocker Level |
|-------|---------------|--------------|---------------|
| xctest-dynamic-overlay imports | FIXED (Phase 09-01) | N/A -- already done | None |
| skipstone on ObservationTests | Present | N/A -- already done | None |
| skipstone on FuseAppTests | Present | N/A -- already done | None |
| skipstone on FoundationTests | **Missing** | Add plugin + SkipTest dep | Medium |
| skipstone on TCATests | **Missing** | Add plugin + SkipTest dep | Medium |
| skipstone on SharingTests | **Missing** | Add plugin + SkipTest dep | Medium |
| skipstone on NavigationTests | **Missing** | Add plugin + SkipTest dep | Medium |
| skipstone on DatabaseTests | **Missing** | Add plugin + SkipTest dep | Medium |
| skipstone on FuseAppIntegrationTests | **Missing** | Add plugin + SkipTest dep | Medium |
| XCSkipTests (fuse-library) | JUnit stub | XCGradleHarness | **High** (symlink issue) |
| XCSkipTests (fuse-app) | JUnit stub | XCGradleHarness | **High** (symlink issue) |
| Real Kotlin test execution | 0 tests | Non-zero test count | **High** (depends on above) |

### Skipstone Plugin Coverage Map

**fuse-library targets:**
| Target | Has skipstone | Has SkipTest | Has XCSkipTests | Transpiles |
|--------|--------------|-------------|-----------------|------------|
| FuseLibrary | YES | N/A (not test) | N/A | YES |
| ObservationTests | YES | YES | YES (stub) | YES |
| FoundationTests | **NO** | **NO** | **NO** | NO |
| TCATests | **NO** | **NO** | **NO** | NO |
| SharingTests | **NO** | **NO** | **NO** | NO |
| NavigationTests | **NO** | **NO** | **NO** | NO |
| DatabaseTests | **NO** | **NO** | **NO** | NO |

**fuse-app targets:**
| Target | Has skipstone | Has SkipTest | Has XCSkipTests | Transpiles |
|--------|--------------|-------------|-----------------|------------|
| FuseApp | YES | N/A (not test) | N/A | YES |
| FuseAppTests | YES | YES | YES (stub) | YES |
| FuseAppIntegrationTests | **NO** | **NO** | **NO** | NO |

## Open Questions

1. **Can skipstone's symlink resolution be fixed for local fork paths?**
   - What we know: The skipstone plugin creates symlinks from the Gradle project to SPM package locations. With local `../../forks/` paths, Gradle cannot resolve dependencies through the symlink chain. All Kotlin compile tasks report `NO-SOURCE`.
   - What's unclear: Whether this is a fundamental limitation of skipstone or a configuration issue. The Skip team may have a solution or workaround for projects with many local dependencies.
   - Recommendation: Investigate skipstone's symlink creation logic (in the `skip` package itself). If not fixable, fall back to approach 4 (local Maven repo) or approach 5 (emulator testing for complex targets).
   - **Confidence:** MEDIUM -- the root cause is documented but no solution has been attempted.

2. **Which test files will fail transpilation when skipstone is added?**
   - What we know: Files using Combine (`#if canImport(Combine)`), Darwin-specific APIs, or native Observation will fail. Several test files already use `#if !SKIP` guards, but the 5 new test targets (FoundationTests, TCATests, SharingTests, NavigationTests, DatabaseTests) have not been audited for transpilability.
   - What's unclear: The exact set of files that need `#if !SKIP` gates. Each test target may have different compatibility issues.
   - Recommendation: Add skipstone to each target one at a time, fix transpilation errors by adding `#if !SKIP` guards, then move to the next target. This is an iterative debugging process.
   - **Confidence:** HIGH -- the process is well-understood even if the specific errors are not yet known.

3. **How will TEST-10 and TEST-11 be verified on Android?**
   - What we know: ObservationBridgeTests and StressTests are `#if !SKIP` gated because they use native Swift `withObservationTracking`. They cannot be transpiled to Kotlin.
   - What's unclear: Whether these can be verified through Robolectric at all, or if they require a real Android emulator with `ANDROID_SERIAL`.
   - Recommendation: For TEST-10, rely on higher-level TCA tests that exercise the observation bridge indirectly (e.g., sending actions and asserting state changes through a Store). For TEST-11, create a Kotlin-side stress test or verify via emulator. Accept that some observation tests are macOS-only by design (the bridge code runs as native Swift on Android, not as transpiled Kotlin).
   - **Confidence:** MEDIUM -- the testing strategy for native bridge code on Android is genuinely ambiguous.

4. **What is the expected non-zero Kotlin test count?**
   - What we know: Many tests use `#if !SKIP` guards and will not transpile. The actual Kotlin test count depends on how many tests are transpilation-compatible.
   - What's unclear: The final count. It could be as few as 5-10 per target if most tests need `#if !SKIP`, or 50+ if TCA tests transpile cleanly.
   - Recommendation: Any non-zero count satisfies the success criterion. Focus on getting the infrastructure working first; optimize test count later.
   - **Confidence:** HIGH -- the success criterion says "non-zero", not a specific number.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: Direct inspection of all files mentioned in this research
- `forks/skip-android-bridge/Tests/*/XCSkipTests.swift` -- canonical XCGradleHarness pattern (working example)
- `examples/lite-app/Tests/*/XCSkipTests.swift` -- canonical XCGradleHarness pattern (working example)
- `examples/fuse-library/Package.swift` -- current skipstone coverage
- `examples/fuse-app/Package.swift` -- current skipstone coverage
- `forks/xctest-dynamic-overlay/Sources/IssueReporting/IsTesting.swift` -- confirmed import guards present
- `forks/xctest-dynamic-overlay/Sources/IssueReporting/Internal/SwiftTesting.swift` -- confirmed import guards present

### Secondary (MEDIUM confidence)
- skip.dev/docs/testing/ -- confirms XCTest-to-JUnit transpilation, Robolectric testing, `ANDROID_SERIAL` for device testing
- `.planning/phases/10-navigationstack-path-android/10-07-PLAN.md` -- documents root cause of skipstone symlink incompatibility

### Tertiary (LOW confidence)
- Skipstone plugin internals -- not directly inspected; behavior inferred from error symptoms and documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Skip testing patterns are well-documented and working in other targets
- Architecture: HIGH -- the patterns are established; the challenge is making them work with local forks
- Pitfalls: HIGH -- the skipstone symlink issue is thoroughly documented from Phase 10 investigation
- Open questions: MEDIUM -- the symlink fix feasibility and Android observation testing strategy are genuinely uncertain

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (stable -- Skip testing infrastructure does not change rapidly)
