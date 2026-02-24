# R7: Android Emulator Testing Research

**Created:** 2026-02-22
**Scope:** Skip test infrastructure, Robolectric vs emulator, deferred test automation, timeout/config, log verification

---

## Summary

Skip provides two distinct Android test execution paths: `skip test` (Robolectric on macOS, transpiled Kotlin) and `skip android test` (real emulator/device, native Swift). These serve fundamentally different purposes for Phase 7. Robolectric runs transpiled Kotlin tests locally -- fast but unable to exercise native Swift APIs like `withObservationTracking` or JNI bridge calls. `skip android test` runs native Swift code on a real Android emulator -- slower but capable of exercising the full observation bridge. Of the 5 deferred Phase 1 human tests, 2 can be fully automated via `skip android test` with diagnostics hooks, 1 is automatable via `skip android build`, and 2 require manual or semi-manual verification. Two emulators are already installed (`emulator-36-medium_phone`, `emulator-36-medium_phone_2`). No explicit timeout configuration exists in the generated Gradle files; Gradle's default 10-minute per-test timeout applies but can be overridden via `skip.yml` build blocks.

---

## Skip Test Infrastructure

### Two Test Commands

| Command | Runtime | Code Executed | Bridge Available | Speed |
|---------|---------|---------------|-----------------|-------|
| `skip test` | Robolectric (JVM on macOS) | Transpiled Kotlin | No (JNI unavailable) | Fast (~30s) |
| `skip android test` | Android emulator/device | Native Swift (`.so`) | Yes (full JNI) | Slow (~2-5min) |

### `skip test` (Robolectric)

Runs parity tests via `XCSkipTests.swift` -> `runGradleTests()`. This transpiles Swift XCTest cases to Kotlin JUnit and runs them on the JVM with Robolectric simulating the Android environment.

**Key limitation for this project:** `#if os(Android)` evaluates to **false** under Robolectric. The workaround is `#if os(Android) || ROBOLECTRIC`, but even with this, native Swift APIs (`withObservationTracking`, `ObservationRecording`, JNI exports) cannot be tested because Robolectric runs transpiled Kotlin, not compiled Swift.

**CLI options (from `skip test --help`):**
- `--filter <Test.testFun>` -- filter specific tests
- `--xunit <path>` / `--junit <path>` -- test report output
- `-c, --configuration <debug/release>` -- build configuration
- `-v, --verbose` -- verbose output
- `--summary-file <path>` -- output summary table

**Current status:** `skip test` passes 21/21 tests (Swift + Kotlin) as of Phase 2 resolution. Confirmed working after removing unused fork deps that broke Skip's sandbox.

### `skip android test` (Emulator)

Runs native Swift tests on a real Android emulator or device. The Swift code is compiled to `.so` shared libraries and deployed to the device.

**CLI options (from `skip android test --help`):**
- `--arch <arch>` -- target architecture (automatic, aarch64, x86_64, etc.)
- `--testing-library <library>` -- specific library to test (default: all)
- `--env <key=value>` -- environment variables for remote execution
- `--copy <file/folder>` -- additional files to deploy
- `--cleanup/--no-cleanup` -- cleanup test folders after running
- `--remote-folder <path>` -- remote folder on emulator for build upload
- `-c, --configuration <debug/release>` -- build configuration
- `--bridge/--no-bridge` -- enable SKIP_BRIDGE (default: on)

**Available emulators:** `emulator-36-medium_phone`, `emulator-36-medium_phone_2` (API 36).

### Gradle Test Infrastructure

The generated `build.gradle.kts` for FuseLibraryTests includes:

1. **Robolectric test support:** `testImplementation(testLibs.robolectric)` with `robolectric.logging=stdout` and `robolectric.graphicsMode=NATIVE`.
2. **Android instrumented test support:** `androidTestImplementation` dependencies for `androidx.test.core`, `rules`, `ext.junit`, and `SkipUnit`.
3. **Test runner:** `AndroidJUnitRunner` with analytics disabled.
4. **Bridge build integration:** `buildLocalSwiftPackage` task compiles Swift with `-DSKIP_BRIDGE -DROBOLECTRIC` flags for local Robolectric tests. `buildAndroidSwiftPackageDebug` compiles for Android with `-DSKIP_BRIDGE -DTARGET_OS_ANDROID`.
5. **JNI packaging:** `jniLibs.srcDir` + `keepDebugSymbols` + `pickFirsts` for `.so` files.

### Test Filter Mechanism

`skip test --filter` maps to Gradle's test filter. However, the XCSkipTests comment notes: "it isn't currently possible to filter the tests to run." This refers to Robolectric parity tests specifically -- individual test method filtering within transpiled tests has limitations. For `skip android test`, the `--testing-library` flag allows targeting specific library tests.

---

## Robolectric vs Emulator

### What Robolectric Can Test

- Transpiled Kotlin logic (pure data transformations, state management)
- Skip framework APIs (SkipFoundation, SkipLib, SkipModel)
- TCA reducer logic (transpiled to Kotlin)
- Basic Android API simulation (SharedPreferences, file I/O)

### What Robolectric Cannot Test

- **Native Swift Observation APIs** -- `withObservationTracking`, `ObservationRegistrar.access/willSet/didSet`
- **JNI bridge calls** -- `Java_skip_ui_ViewObservation_nativeEnable/nativeStartRecording/nativeStopAndObserve`
- **ObservationRecording** -- entire record-replay mechanism (behind `#if SKIP_BRIDGE`, compiled as native Swift)
- **BridgeObservationSupport** -- JNI calls to `MutableStateBacking`
- **Compose recomposition** -- no Compose runtime in Robolectric
- **`libswiftObservation.so`** loading and the `swiftThreadingFatal` stub

### When to Use Each

| Scenario | Use |
|----------|-----|
| Rapid iteration on test logic | `skip test` (Robolectric) |
| Validating transpiled Kotlin parity | `skip test` |
| Bridge observation end-to-end | `skip android test` (emulator) |
| JNI function verification | `skip android test` (emulator) |
| Compose recomposition counting | Manual on emulator |
| Stress test on Android | `skip android test` (emulator) |
| CI/CD pipeline | Both (Robolectric first, emulator second) |

### `ROBOLECTRIC` Flag

The build system defines `-DROBOLECTRIC` when building for local Robolectric tests (see `buildLocalSwiftPackage` task in `build.gradle.kts`). Code can use `#if ROBOLECTRIC` or `#if os(Android) || ROBOLECTRIC` to include/exclude paths. However, since Robolectric runs transpiled Kotlin (not compiled Swift), the `#if ROBOLECTRIC` flag only affects the Swift compilation step for the local package build -- it does not make native Swift APIs available in transpiled test code.

---

## Deferred Test Automation

### Phase 1 Deferred Tests (from 01-VERIFICATION-CLAUDE.md)

#### 1. Single Recomposition Counting

**Original requirement:** Mutate 3 properties of an `@Observable` model in one action. Verify Compose recomposes the view once, not three times.

**Automation approach: AUTOMATABLE via `skip android test`**

The `ObservationRecording` class has built-in diagnostics:
```swift
// In Observation.swift (skip-android-bridge)
public static var diagnosticsEnabled = false
public static var diagnosticsHandler: ((Int, TimeInterval) -> Void)?
```

The `diagnosticsHandler` receives `(replayClosureCount, elapsedTime)` on every `stopAndObserve()` call. A test can:
1. Set `ObservationRecording.diagnosticsEnabled = true`
2. Set `diagnosticsHandler` to capture the replay count
3. Create a view body that accesses 3 properties of an `@Observable` model
4. Call `startRecording()` / body evaluation / `stopAndObserve()`
5. Assert the handler was called exactly once with `replayClosureCount == 3`

**Limitation:** This validates the Swift-side recording/replay mechanism. It does NOT validate that Compose actually recomposed once -- that requires a Compose test harness or visual inspection. However, the bridge architecture guarantees that a single `triggerSingleUpdate()` call produces exactly one Compose recomposition (one `MutableStateBacking.update(0)` call). The diagnostics test covers the Swift side; the Kotlin side is architecturally constrained to single recomposition.

**Test location:** Must run via `skip android test` (needs `#if SKIP_BRIDGE` code and JNI runtime).

#### 2. Nested View Independence

**Original requirement:** Parent view body contains child Fuse views. Each view's observation should be independent (own stack frame).

**Automation approach: AUTOMATABLE via `skip android test`**

The `ObservationRecording` uses a thread-local stack (`FrameStack`). A test can:
1. Enable diagnostics
2. Simulate nested `startRecording()` calls (parent starts, child starts, child stops, parent stops)
3. Assert that each `stopAndObserve()` receives its own frame's replay closures
4. Verify the diagnostics handler fires twice (once per view), each with the correct closure count

This is a pure Swift-side test of the stack mechanism. It can be unit-tested on macOS if `SKIP_BRIDGE` is defined, but the full JNI integration (ViewObservation calling nativeStartRecording/nativeStopAndObserve) requires `skip android test`.

#### 3. ViewModifier Observation

**Original requirement:** ViewModifier's `Evaluate()` calls `startRecording()`/`stopAndObserve()` around body evaluation, same as View.

**Automation approach: SEMI-AUTOMATABLE**

The code in `ViewModifier.swift` (skip-ui fork) shows:
```swift
@Composable public func Evaluate(...) -> ... {
    ViewObservation.startRecording?()
    StateTracking.pushBody()
    // ... body evaluation ...
    StateTracking.popBody()
    ViewObservation.stopAndObserve?()
    return renderables
}
```

**What can be automated:** Verify that `ViewObservation.startRecording` and `stopAndObserve` are non-null (hooks are registered) at runtime via `skip android test`.

**What requires manual verification:** Verifying that a specific ViewModifier's body actually triggers the diagnostics handler requires a running Compose UI with a view hierarchy. This is a UI-level integration test, not a unit test. It could be automated with a Compose test harness (`composeTestRule`) but that infrastructure does not currently exist in the project.

**Recommendation:** Classify as "verified by architecture" -- the code path is identical to View.Evaluate(), which is tested in items 1-2. If ViewModifier.Evaluate() is called at all, it goes through the same recording mechanism.

#### 4. Fatal Error on Bridge Failure

**Original requirement:** If the JNI bridge fails to initialize, the app should crash with a clear error (not silently degrade).

**Automation approach: MANUAL ONLY**

Testing an intentional crash is inherently difficult to automate:
- XCTest has no built-in "expect this to crash" mechanism
- The fatal error occurs in `BridgeObservationSupport.Java_initPeer()` when JNI context is unavailable
- On Android, a crash would terminate the test runner process

**Manual verification procedure:**
1. Launch fuse-app on emulator
2. Temporarily modify `isJNIInitialized` to return `false` (or break JNI setup)
3. Trigger a view body evaluation that accesses an `@Observable` property
4. Observe: the app should crash (or the current behavior: `Java_initPeer()` returns `nil`, and `Java_access`/`Java_update` silently no-op via `guard isJNIInitialized` checks)

**Note:** Looking at the actual code, the current implementation does NOT `fatalError` on bridge failure. `BridgeObservationSupport.Java_initPeer()` returns `nil` when JNI is unavailable, and subsequent `Java_access`/`Java_update` calls silently return via guard checks. The `fatalError` behavior described in CLAUDE.md ("Bridge init/runtime JNI failures are fatal") may refer to a design intent that is not yet implemented, or to a different failure path. This should be clarified.

#### 5. 17-Fork Compilation

**Original requirement:** All 17 forks must compile for Android.

**Automation approach: AUTOMATABLE via `skip android build`**

```bash
cd examples/fuse-library && skip android build
```

This compiles all fork dependencies to `.so` libraries for Android. If any fork fails to compile, the build fails. This is a binary pass/fail check.

**Enhancement:** Also run `skip android test` to verify runtime linking (all `.so` libraries load correctly, no missing symbols like the `swiftThreadingFatal` issue).

### Automation Summary

| Deferred Test | Automation Level | Tool | Notes |
|---------------|-----------------|------|-------|
| Single recomposition | Full | `skip android test` + diagnostics | Swift-side only; Compose side is architectural |
| Nested independence | Full | `skip android test` + diagnostics | Stack frame isolation test |
| ViewModifier observation | Verified by architecture | Code inspection | Same code path as View.Evaluate() |
| Fatal error on bridge failure | Manual only | Emulator + code modification | Current code silently no-ops, not fatalError |
| 17-fork compilation | Full | `skip android build` | Binary pass/fail |

---

## Timeout & Configuration

### Gradle Test Timeouts

The generated `build.gradle.kts` files contain **no explicit timeout configuration**. Gradle's defaults apply:

- **Per-test timeout:** None by default (tests run until completion or JVM kill)
- **Overall build timeout:** Controlled by Gradle daemon settings (default: no limit, but daemon times out after 3 hours of inactivity)

The `tasks.withType<Test>` block configures:
```kotlin
filter {
    isFailOnNoMatchingTests = false
    excludeTestsMatching("NonExistingExcludePattern")
}
```

No `timeout` property is set.

### Adding Timeout Configuration

Timeouts can be added via `skip.yml` build blocks for the test target:

```yaml
# Tests/FuseLibraryTests/Skip/skip.yml
build:
  contents:
    - block: 'tasks.withType<Test>'
      contents:
        - 'timeout.set(java.time.Duration.ofMinutes(10))'
```

Or per-test in Kotlin/JUnit:
```kotlin
@Test(timeout = 60000)  // 60 seconds
fun testStress() { ... }
```

### `skip android test` Timeouts

`skip android test` runs instrumented tests on the device via `adb shell am instrument`. The timeout is controlled by:
1. **AndroidJUnitRunner default:** No per-test timeout (runs until completion)
2. **ADB command timeout:** Configurable via `--env` flag: `skip android test --env timeout=300000`
3. **The `--cleanup` flag** (default: on) removes test artifacts after completion

### Stress Test Implications

For stress tests with >1000 iterations:
- **Robolectric (`skip test`):** Should complete quickly (pure computation on Mac JVM). No timeout concern.
- **Emulator (`skip android test`):** Depends on device speed. ARM emulation on x86_64 is slow. Recommendation: keep iteration counts at 500-1000 for emulator, 2000+ for macOS.
- **Memory measurement on Android:** `/proc/self/status` VmRSS parsing works but requires `#if os(Android)` guard. The `mach_task_basic_info` API is Darwin-only.

### Skip Test Configuration Files

| File | Purpose |
|------|---------|
| `Sources/FuseLibrary/Skip/skip.yml` | Module config: `mode: native`, `bridging: true` |
| `Tests/FuseLibraryTests/Skip/skip.yml` | Test module config (currently empty/default) |
| Generated `build.gradle.kts` | Full Gradle build config (ephemeral, regenerated) |
| `ANDROID_SERIAL` env var | Routes tests to specific emulator/device |

---

## Log Verification

### `adb logcat` Integration

`adb logcat` captures all Android system and app logs. Swift `print()` statements on Android output to the system log with the `swift` tag.

**Filtering for test output:**
```bash
adb logcat -s swift          # Only Swift print() output
adb logcat -s TestRunner     # AndroidJUnitRunner output
adb logcat '*:W'             # Warnings and above (all tags)
```

### Using Logs for Test Assertion Verification

**Approach 1: Diagnostics handler logging**
```swift
ObservationRecording.diagnosticsEnabled = true
ObservationRecording.diagnosticsHandler = { count, elapsed in
    print("[BRIDGE_DIAG] replayed=\(count) elapsed=\(elapsed)s")
}
```
Then verify via `adb logcat -s swift | grep BRIDGE_DIAG`.

**Approach 2: Structured log output from tests**
```swift
func testBridgeRecomposition() {
    // ... test logic ...
    print("[TEST_RESULT] testBridgeRecomposition: replayCount=\(count), expected=3")
}
```

**Approach 3: `skip android emulator launch --logcat`**
The `--logcat <filter>` flag on `skip android emulator launch` streams filtered logs directly:
```bash
skip android emulator launch --logcat 'swift:D'
```

### Limitations

- `adb logcat` is a passive stream -- it requires a separate terminal or background process
- Log assertions are informal (grep-based), not structured test assertions
- For formal test assertions, use XCTest assertions within `skip android test` -- these produce JUnit XML reports via `--junit <folder>` or `--xunit <path>`
- `skip test --junit <folder>` generates structured test reports that can be parsed programmatically

### Recommended Log Strategy for Phase 7

1. **Primary:** Use XCTest assertions in `skip android test` for formal pass/fail
2. **Secondary:** Enable `ObservationRecording.diagnosticsHandler` with structured logging for bridge behavior
3. **Debugging:** Use `adb logcat -s swift` in a separate terminal during manual emulator testing
4. **CI artifacts:** Generate JUnit XML reports via `skip test --junit reports/` for automated pipeline integration

---

## Recommendations

### R1: Use `skip android test` for Bridge Verification, Not `skip test`

The observation bridge (`ObservationRecording`, JNI exports, `BridgeObservationSupport`) is native Swift code behind `#if SKIP_BRIDGE`. Robolectric runs transpiled Kotlin and cannot exercise this code. All bridge-specific tests must use `skip android test` with a running emulator.

### R2: Automate 3 of 5 Deferred Tests

- **Single recomposition:** Write a native Swift test using `ObservationRecording.diagnosticsHandler` assertions. Run via `skip android test`.
- **Nested independence:** Write a stack frame isolation test using `startRecording()`/`stopAndObserve()` nesting. Run via `skip android test`.
- **17-fork compilation:** Run `skip android build` as a pass/fail gate.

### R3: Accept 2 Tests as Architecture-Verified or Manual

- **ViewModifier observation:** Same code path as View.Evaluate(). Architecture-verified. Document the equivalence.
- **Fatal error on bridge failure:** Requires manual verification. Document the expected behavior and the actual current behavior (silent no-op, not fatalError). Consider whether the design intent should be implemented.

### R4: Add Timeout Configuration for Stress Tests

Add to `Tests/FuseLibraryTests/Skip/skip.yml`:
```yaml
build:
  contents:
    - block: 'tasks.withType<Test>'
      contents:
        - 'timeout.set(java.time.Duration.ofMinutes(10))'
```

Keep stress test iteration counts reasonable for emulator (500-1000 iterations).

### R5: Generate Test Reports

Use `skip test --junit reports/` and `skip android test` JUnit output for CI artifact collection. These provide structured pass/fail data beyond console output.

### R6: Clarify Bridge Failure Behavior

The current `BridgeObservationSupport` silently no-ops when JNI is unavailable (returns from guard checks). The project's design documentation states "Bridge init/runtime JNI failures are fatal (fatalError)". Either:
1. Implement the fatalError behavior as designed, or
2. Update the design documentation to reflect the silent degradation approach

This should be resolved before the "fatal error on bridge failure" manual test.

### R7: Emulator Launch Strategy

Two emulators are available (`emulator-36-medium_phone`, `emulator-36-medium_phone_2`). For Phase 7:
1. Launch one emulator: `skip android emulator launch --name emulator-36-medium_phone --background`
2. Verify it's running: `adb devices`
3. Run tests: `skip android test` (auto-detects connected device)
4. For parallel testing, launch both emulators and use `ANDROID_SERIAL` to target specific ones

---

*Research completed: 2026-02-22*
*Sources: skip test --help, skip android test --help, skip android emulator --help/list, Observation.swift (skip-android-bridge), View.swift/ViewModifier.swift (skip-ui), XCSkipTests.swift, build.gradle.kts (generated), docs/skip/testing.md, docs/skip/gradle.md, 01-VERIFICATION-CLAUDE.md, STATE.md pending todos*
