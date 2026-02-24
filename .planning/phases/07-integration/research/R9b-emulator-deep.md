# R9b: Emulator Deep-Dive Research

**Date:** 2026-02-22
**Phase:** 07 — Integration
**Skip version:** 1.7.2

---

## 1. Skip Android Test Infrastructure

### `skip android --help` (full output)

```
OVERVIEW: Perform a native Android package command

USAGE: skip android <subcommand>

SUBCOMMANDS:
  build     Build the native project for Android
  run       Run the executable target Android device or emulator
  test      Test the native project on an Android device or emulator
  sdk       Manage installation of Swift Android SDK
  emulator  Manage Android emulators
  toolchain Manage installation of Swift Android Host Toolchain
```

### `skip android test --help` (full output)

```
OVERVIEW: Test the native project on an Android device or emulator

USAGE: skip android test [<options>] [<args> ...]

ARGUMENTS:
  <args>                  Command arguments

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

TOOLCHAIN OPTIONS:
  --swift-version <v>     Swift version
  --sdk <path>            Swift Android SDK path
  --ndk <path>            Android NDK path
  --toolchain <path>      Swift toolchain path
  --package-path <path>   Path to the package to run
  --scratch-path <.build> Custom scratch directory path
  -Xswiftc / -Xcc / -Xlinker / -Xcxx   Pass-through compiler flags
  -c, --configuration <debug>           Build configuration
  --arch <arch>           Architectures: automatic|current|default|all|aarch64|armv7|x86_64
  --android-api-level <level>           (default: 28)
  --swift-sdk-home <path>
  --bridge/--no-bridge    Enable SKIP_BRIDGE (default: --bridge)
  --aggregate/--no-aggregate            Bundle all libs into single .so (default: --no-aggregate)
  --prune/--no-prune      Prune non-dependent libs (default: --prune)

TEST-SPECIFIC OPTIONS:
  --cleanup/--no-cleanup  Cleanup test folders after running (default: --cleanup)
  --remote-folder <path>  Remote folder on emulator/device for build upload
  --testing-library <library>   Testing library name (default: all)
  --env <key=value>       Environment key/value pairs for remote execution
  --copy <file/folder>    Additional files or folders to copy to Android
```

### Key flags for test control

| Flag | Purpose | Notes |
|------|---------|-------|
| `--testing-library <name>` | Filter to a single library/module | default: `all` |
| `--env KEY=VALUE` | Pass env vars into the remote test process | Repeatable |
| `--remote-folder <path>` | Override where test artifacts are pushed on device | |
| `--copy <path>` | Copy extra files to Android before running | |
| `--no-cleanup` | Keep test folders after run (useful for debugging) | |
| `--arch aarch64` | Target architecture explicitly | emulator-5554 is arm64-v8a |
| `--android-api-level 36` | Match installed emulator API level | |
| `-v` / `--verbose` | Show exact adb/gradle commands executed | Critical for debugging |
| `--log-file <path>` | Capture all output to a file | |
| `-J` / `--json` | Machine-readable output | Useful for CI parsing |

### Test result format

- `skip android test` drives Gradle which drives **AndroidJUnitRunner** on-device
- Results are produced as **JUnit XML** by the Android test runner
- Location after a run (based on fuse-app precedent):
  ```
  .build/plugins/outputs/<target>/<Module>/destination/skipstone/<Module>/.build/<Module>/test-results/testDebugUnitTest/TEST-<package>.<TestClass>.xml
  ```
- The macOS-side `skip test` command also produces XUnit XML at:
  ```
  examples/fuse-library/.build/xcunit-<UUID>.xml          # XCTest/JUnit style
  examples/fuse-library/.build/xcunit-<UUID>-swift-testing.xml  # Swift Testing style
  ```

### Test filtering

- **`skip android test --testing-library FuseLibrary`** — runs only that module's instrumented tests
- There is **no per-test filter flag** in `skip android test` itself
- Fine-grained filtering requires passing Gradle arguments via `<args>` positional parameter:
  ```bash
  skip android test -- -Pandroid.testInstrumentationRunnerArguments.class=fuse.library.FuseLibraryTests#testObservationBridge
  ```
  This works because `testInstrumentationRunnerArguments` is already wired in `build.gradle.kts`.

### On-device vs Robolectric

Two distinct test execution paths exist:

| Path | How triggered | Runner | Requires emulator? |
|------|--------------|--------|--------------------|
| Robolectric (JVM) | `skip test` via `XCSkipTests.testSkipModule()` | JUnit4 + Robolectric 4.16 | No |
| On-device | `skip android test` | AndroidJUnitRunner (androidx.test) | Yes |
| On-device (env var) | Set `ANDROID_SERIAL=emulator-5554` before `swift test` | Same as above, triggered from XCTest | Yes |

The `XCSkipTests.swift` comment explicitly documents the `ANDROID_SERIAL` mechanism:
```swift
// Connected device or emulator tests can be run by setting the
// `ANDROID_SERIAL` environment variable to an `adb devices` ID
// in the scheme's Run settings.
```

---

## 2. Emulator State

### `skip devices` output

```
platform: android type: device id: emulator-5554
platform: ios type: device id: 52D7C895-6378-5423-BAB6-2ACC2D9C57A2
platform: ios type: device id: 739C6D60-377D-5DE3-9F07-E2BB83732DF4
platform: ios type: device id: D500AB8F-604C-55CA-A3C0-0C2F0BC07980
platform: ios type: device id: 72AB603B-AFB8-5F19-8123-99E85370302D
platform: ios type: device id: 7E317427-67A4-511B-94C8-4D4D97011E8D
platform: ios type: device id: 04E9384F-1C01-59F0-9144-6E614053470E
platform: ios type: device id: A82A635F-2A0D-50EC-BC51-30D28E4F0815
```

**Android emulator is already running and ADB-connected** (`emulator-5554`).

### `skip android emulator list` output

```
emulator-36-medium_phone
emulator-36-medium_phone_2
```

Two API-36 emulators installed. The running one (`emulator-5554`) is one of these.

### `adb devices -l` output

```
List of devices attached
emulator-5554   device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
```

### Emulator properties

| Property | Value |
|----------|-------|
| Model | `sdk_gphone64_arm64` |
| Android API level | 36 |
| Android version | 16 |
| CPU ABI | `arm64-v8a` |
| Status | Booted and ADB-connected |
| RAM available | ~2 GB free of 4 GB total (`MemAvailable: 2107260 kB`) |

### Host machine

| Property | Value |
|----------|-------|
| Chip | Apple M3 Max |
| RAM | 48 GB |
| Architecture | arm64 (Apple Silicon) |

### Swift Android SDK installed

```
swift-6.2.3-RELEASE_android
```

---

## 3. skip.yml Configuration

### Schema

`skip.yml` files live at `Sources/<Module>/Skip/skip.yml` and `Tests/<Module>Tests/Skip/skip.yml`. They configure Skip's transpilation and Gradle generation behavior.

### fuse-library source module (`Sources/FuseLibrary/Skip/skip.yml`)

```yaml
skip:
  mode: 'native'
  bridging: true
```

- `mode: native` — Fuse mode (native Swift compiled to .so via JNI)
- `bridging: true` — enables `SKIP_BRIDGE` / JNI bridge code generation

### fuse-library test module (`Tests/FuseLibraryTests/Skip/skip.yml`)

```yaml
# (empty — only commented-out template)
```

The test module inherits settings from the source module.

### skip-android-bridge (`Sources/SkipAndroidBridge/Skip/skip.yml`)

```yaml
skip:
  mode: 'native'
```

### Known skip.yml fields (from all observed files + docs)

```yaml
skip:
  mode: 'native'        # 'native' (Fuse/JNI) or 'transpile' (Lite/Kotlin codegen)
  bridging: true        # Enable JNI bridge wrapping

build:
  contents:
    - block: 'dependencies'
      contents:
        - 'implementation("com.example:library:1.0")'
    - block: 'android'
      contents:
        - 'defaultConfig { ... }'
```

The `build.contents` field lets you **inject arbitrary Gradle DSL blocks** into the generated `build.gradle.kts`. This is the extension point for:
- Adding Kotlin dependencies
- Customizing `testOptions`
- Setting per-test timeouts (via Gradle test task configuration)
- Passing environment variables via `systemProperties`

### Adding test configuration via skip.yml

To add custom Gradle test config without editing generated files:

```yaml
# Tests/FuseLibraryTests/Skip/skip.yml
build:
  contents:
    - block: 'android'
      contents:
        - |
          testOptions {
            unitTests {
              isIncludeAndroidResources = true
            }
            animationsDisabled = true
          }
    - block: 'tasks.withType<Test>().configureEach'
      contents:
        - 'timeout.set(Duration.ofMinutes(10))'
        - 'systemProperties["my.env.var"] = "value"'
```

**Warning:** Generated `build.gradle.kts` files are regenerated on each build. Only edits that flow through `skip.yml` are stable. Direct edits to `.build/plugins/outputs/*/build.gradle.kts` will be overwritten.

### Per-test timeout

No native per-test timeout in Skip. Options:
1. Gradle-level: add `timeout.set(Duration.ofSeconds(60))` to `tasks.withType<Test>().configureEach` via skip.yml injection
2. Swift-level: use `XCTestCase`'s default timeout or `Task { }.value` with `async` timeout

### Environment variables to emulator

Two mechanisms:
1. `skip android test --env KEY=VALUE` — passed to the remote test process at runtime
2. `skip.yml` `build.contents` injecting `systemProperties["KEY"] = "VALUE"` into Gradle test task

---

## 4. Gradle Test Configuration

### Generated Gradle project structure (FuseLibraryTests)

```
.build/plugins/outputs/fuse-library/FuseLibraryTests/destination/skipstone/
├── settings.gradle.kts      # root: includes all modules, sets bridgeModules
├── gradle.properties        # android.useAndroidX=true, org.gradle.jvmargs=-Xmx4g
├── FuseLibrary/
│   └── build.gradle.kts     # main library module config
├── SkipAndroidBridge -> (symlink)
├── SkipBridge -> (symlink)
├── SkipFoundation -> (symlink)
├── SkipLib -> (symlink)
└── SkipUnit -> (symlink)
```

The symlinks point to peer Gradle projects from other Skip packages — this is how the multi-module dependency graph is assembled without publishing to a Maven repository.

### `settings.gradle.kts` key configuration

```kotlin
rootProject.name = "fuse.library"
include(":FuseLibrary", ":SkipAndroidBridge", ":SkipBridge", ":SkipLib", ":SkipUnit", ":SkipFoundation")
gradle.extra["bridgeModules"] = listOf("FuseLibrary", "SkipAndroidBridge", "SkipBridge")
```

The `bridgeModules` list controls which modules trigger the `buildAndroidSwiftPackage` task (i.e., which ones compile Swift to .so via `skip android build`). `FuseLibrary` is first — it is the **root bridge module**.

### `build.gradle.kts` test runner configuration

```kotlin
defaultConfig {
    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    testInstrumentationRunnerArguments["disableAnalytics"] = "true"
}
```

- **Test runner:** `AndroidJUnitRunner` (JUnit4-compatible, used by Espresso and standard Android instrumented tests)
- **Not** JUnit5 — the `kotlin-test-junit` dependency confirms JUnit4

### Robolectric configuration (for `skip test` / JVM path)

```kotlin
tasks.withType<Test>().configureEach {
    systemProperties.put("robolectric.logging", "stdout")
    systemProperties.put("robolectric.graphicsMode", "NATIVE")
    testLogging { showStandardStreams = true }
    filter {
        isFailOnNoMatchingTests = false
        excludeTestsMatching("NonExistingExcludePattern")
    }
}
```

- Robolectric version: **4.16**
- Graphics mode: `NATIVE` (uses native graphics libs, not software renderer)
- `isFailOnNoMatchingTests = false` — won't fail if a filter matches nothing
- `showStandardStreams = true` — stdout/stderr from tests visible in Gradle output

### Android build task chain (when `isRootBridgeModule() == true`)

```
mergeDebugJniLibFolders
  └── buildAndroidSwiftPackageDebug
        └── skip android build ... --product FuseLibrary --arch automatic -Xswiftc -DSKIP_BRIDGE
```

The Swift build is embedded as a Gradle task dependency, so `./gradlew assembleDebug` or `./gradlew connectedAndroidTest` will automatically trigger `skip android build` for the root bridge module.

### Robolectric build task chain

```
test (Robolectric JUnit)
  └── buildLocalSwiftPackage
        └── swift build ... --product FuseLibrary -Xswiftc -DSKIP_BRIDGE -Xswiftc -DROBOLECTRIC
```

### JVM heap

`org.gradle.jvmargs=-Xmx4g` — Gradle daemon gets 4 GB heap.

### Version catalog (from `settings.gradle.kts`)

| Component | Version |
|-----------|---------|
| JVM target | 17 |
| Android min SDK | 28 |
| Android compile SDK | 36 |
| Android Gradle Plugin | 8.13.0 |
| Kotlin | 2.3.0 |
| kotlinx.coroutines | 1.10.2 |
| androidx.test | 1.6.1 |
| androidx.test.ext.junit | 1.3.0 |
| Robolectric | 4.16 |

---

## 5. Log Capture and Diagnostics

### logcat during test execution

```bash
# Stream all Swift-tagged logs from running emulator
adb -s emulator-5554 logcat -s swift

# Capture to file during test run (run in background, kill after test)
adb -s emulator-5554 logcat -s swift > /tmp/swift-logcat.txt &
LOGCAT_PID=$!
skip android test --testing-library FuseLibrary
kill $LOGCAT_PID

# Broader capture: Swift + AndroidRuntime + system crashes
adb -s emulator-5554 logcat -s swift:V AndroidRuntime:E System.err:W > /tmp/test-logcat.txt
```

### logcat filter syntax

```
tag:priority  (e.g. swift:V = verbose, AndroidRuntime:E = errors only)
*:S           (silence all by default, then add specific tags)
```

`skip android emulator launch --logcat '*:W'` passes the filter to the emulator's built-in logcat capture.

### Crash/ANR detection

```bash
# Check for ANR traces after test
adb -s emulator-5554 shell ls /data/anr/ 2>/dev/null
adb -s emulator-5554 pull /data/anr/traces.txt /tmp/anr-traces.txt

# Check for crash tombstones
adb -s emulator-5554 shell ls /data/tombstones/ 2>/dev/null
```

### JNI library load verification

```bash
# Check if libswiftObservation.so and the bridge .so loaded
adb -s emulator-5554 logcat -d | grep -E "dlopen|libswift|JNI_OnLoad|nativeEnable"
```

### Test failure screenshots

AndroidJUnitRunner does **not** automatically capture screenshots on failure. Options:
1. Use `androidx.test.runner.screenshot.Screenshot.capture()` in test tearDown
2. Use `adb -s emulator-5554 shell screencap -p /sdcard/screen.png && adb pull /sdcard/screen.png` after failure detection
3. Espresso has screenshot-on-failure via `FailureHandler`

---

## 6. Android Build — Current State

### `.build/` directory timestamps (fuse-library)

```
Sun Feb 22 21:11:47 2026  .  (root)
Sun Feb 22 20:52:45 2026  debug.yaml
Sun Feb 22 20:52:45 2026  debug -> arm64-apple-macosx/debug (symlink)
Sun Feb 22 20:52:44 2026  plugin-tools.yaml
Sun Feb 22 20:52:42 2026  build.db
Sun Feb 22 18:34:05 2026  xcunit-7D4C8D9E-...-swift-testing.xml  (latest test run)
Sun Feb 22 18:34:05 2026  xcunit-7D4C8D9E-....xml
Sun Feb 22 18:11:46 2026  workspace-state.json
Sun Feb 22 13:53:13 2026  xcunit-7A39E833-... (earlier run)
Sun Feb 22 11:47:14 2026  arm64-apple-macosx/ (macOS Swift build)
```

**Key observation:** There is NO `Android/` or `aarch64-unknown-linux-android*/` directory in `.build/`. The last macOS build completed at 20:52 on 2026-02-22. **No Android build has been run yet** for fuse-library.

### Gradle plugin outputs (exist from plugin evaluation, not Android build)

The `.build/plugins/outputs/` Gradle KTS files exist because SPM evaluates the Skip Gradle plugin during `swift build`/`swift test` on macOS. This is **not** an Android build — it's the Gradle project generation step.

### Android build command (what `make android-build` runs)

```bash
cd examples/fuse-library && skip android build
```

This translates to roughly:
```bash
skip android build \
  --package-path <source> \
  --arch automatic \          # builds aarch64 for connected arm64 emulator
  --configuration debug \
  --bridge                    # SKIP_BRIDGE enabled
```

The Gradle `buildAndroidSwiftPackageDebug` task runs:
```bash
skip android build \
  -d "<build>/jni-libs" \
  --package-path "<source>" \
  --configuration debug \
  --product FuseLibrary \
  --scratch-path "<build>/swift" \
  --arch automatic \
  -Xcc -fPIC \
  -Xswiftc -DSKIP_BRIDGE \
  -Xswiftc -DTARGET_OS_ANDROID \
  -Xswiftc -Xfrontend -Xswiftc -no-clang-module-breadcrumbs \
  -Xswiftc -Xfrontend -Xswiftc -module-cache-path \
  -Xswiftc -Xfrontend -Xswiftc "<build>/swift/module-cache/FuseLibrary"
```

### Expected build time

No prior Android build to measure from. Based on project complexity (6 modules, Swift 6.2, SKIP_BRIDGE):
- **Cold build (no cache):** 15–40 minutes (downloading SDK toolchain, compiling all deps)
- **Incremental build (module cache warm):** 3–8 minutes
- **Gradle Kotlin compilation only (Swift cached):** 1–3 minutes

### `make android-test` status

`android-test` appears in the Makefile's `.PHONY` declaration but **has no recipe**. It is a stub — the target exists in intent but is not implemented. Running `make android-test` would produce:
```
make: Nothing to be done for 'android-test'.
```

The correct command to run on-device tests is:
```bash
cd examples/fuse-library && skip android test
```
or with the ANDROID_SERIAL environment approach through XCTest:
```bash
cd examples/fuse-library && ANDROID_SERIAL=emulator-5554 swift test --filter XCSkipTests
```

---

## 7. Deferred Human Test Automation Feasibility

### HT-1: App Launches, Recomposition Stable

**Current status:** Deferred (requires UI + visual inspection)

**Automation approach:**
```bash
# Build and install the app APK
skip android build --configuration debug
adb -s emulator-5554 install -r path/to/app.apk

# Launch the app
adb -s emulator-5554 shell am start -n "fuse.app/.MainActivity"

# Wait for launch and check for crashes/ANRs
sleep 5
adb -s emulator-5554 shell pidof fuse.app  # non-empty = app running
adb -s emulator-5554 logcat -d -s swift | grep -c "recompos"  # count recompositions
```

**Recomposition stability check:** The diagnostics handler in TCA's `ObservableStateRegistrar` emits log messages when recomposition is detected. These are captured via `adb logcat -s swift`. A threshold check (e.g., fewer than 3 recompositions in 5 seconds with no user interaction) would distinguish stable from infinite-loop.

**Automatable:** Partially. Launch + crash detection is fully automatable. Recomposition count requires knowing the exact log tag/message TCA emits.

### HT-2: UI Renders Correctly

**Current status:** Deferred (visual assertion)

**Automation approaches:**
1. **Screenshot comparison:**
   ```bash
   adb -s emulator-5554 shell screencap -p /sdcard/screen.png
   adb pull /sdcard/screen.png /tmp/screen.png
   # Compare against golden image with ImageMagick or custom tool
   compare -metric MAE golden.png screen.png diff.png
   ```
2. **UI Automator (on-device):** Write an `androidTest` that uses `UiDevice.findObject()` to assert specific UI elements exist. This requires writing Kotlin instrumented tests.
3. **Espresso:** Same as UI Automator but more idiomatic for Android.

**Automatable:** Yes, with investment. Screenshot comparison is brittle (pixel-exact). UI Automator content descriptions are robust but require adding `contentDescription` attributes to Compose views.

**Recommendation:** Out of scope for Phase 7. Defer to a future UI testing phase.

### HT-3: Android Build Succeeds (Exit Code)

**Current status:** Flagged as automatable in R7.

**Automation:** Fully automatable. `skip android build` exits 0 on success, non-zero on failure.

```bash
cd examples/fuse-library && skip android build
BUILD_EXIT=$?
if [ $BUILD_EXIT -eq 0 ]; then
  echo "PASS: Android build succeeded"
else
  echo "FAIL: Android build failed with exit code $BUILD_EXIT"
fi
```

This is already achievable with `make android-build` plus exit code checking. The Makefile target just needs a test harness around it.

### HT-4: Recomposition Is Not Infinite

**Current status:** Deferred (requires runtime observation)

**Automation approach:**
The recomposition diagnostic in `ObservationStateRegistrar.swift` (Android path) calls through to a handler. The key question is what log output it produces.

```bash
# Capture logcat during a brief interaction window
adb -s emulator-5554 logcat -c  # clear buffer
adb -s emulator-5554 shell am start -n "fuse.app/.MainActivity"
sleep 10  # let app stabilize
adb -s emulator-5554 logcat -d -s swift > /tmp/recomp-log.txt

# Check for infinite recomposition indicators
RECOMP_COUNT=$(grep -c "recomposit\|observation.*trigger\|state.*changed" /tmp/recomp-log.txt)
MAX_ACCEPTABLE=5
if [ "$RECOMP_COUNT" -le "$MAX_ACCEPTABLE" ]; then
  echo "PASS: recomposition count $RECOMP_COUNT <= $MAX_ACCEPTABLE"
else
  echo "FAIL: recomposition count $RECOMP_COUNT exceeds threshold"
fi
```

**Automatable:** Yes, once the exact log tag/message from `ObservationStateRegistrar`'s Android path is known. Need to inspect `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift` Android branch.

### HT-5: JNI Bridge Loads (nativeEnable() Success)

**Current status:** Flagged as automatable via test assertion in R7.

**Automation approach 1 — unit test assertion:**
```swift
// In FuseLibraryTests, on Android path:
#if os(Android)
func testJNIBridgeLoads() {
    // nativeEnable() is called during module init; if we reach here, it succeeded
    XCTAssertTrue(isAndroid)
    // Verify SkipAndroidBridge is active
    XCTAssertNotNil(/* bridge handle or observable object */)
}
#endif
```

**Automation approach 2 — logcat:**
```bash
adb -s emulator-5554 logcat -d | grep -E "JNI_OnLoad|nativeEnable|libFuseLibrary|dlopen.*swift"
# Successful load produces: JNI_OnLoad or similar from libswiftObservation.so
```

**Automation approach 3 — `skip android test`:**
The instrumented tests run on-device via `skip android test`. If the .so files don't load, all tests fail with `UnsatisfiedLinkError`. A successful test run is itself proof of JNI bridge loading. This is the cleanest automation path.

**Automatable:** Yes. Running `skip android test --testing-library FuseLibrary` and checking for zero errors constitutes an HT-5 pass.

---

## 8. CI Considerations

### Headless emulator

```bash
skip android emulator launch --headless --background
```

The `--headless` flag runs the emulator without a GUI window — essential for CI. The `--background` flag daemonizes it. Combined:
```bash
skip android emulator launch \
  --name emulator-36-medium_phone \
  --headless \
  --background \
  --logcat '*:W'
```

Wait for boot:
```bash
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell while [ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null)" != "1" ]; do sleep 2; done
```

### Cold-start time

No measured baseline yet for this setup (M3 Max, API 36, arm64-v8a). General reference:
- **Apple Silicon (M1/M2/M3) + API 34+ arm64 emulator:** 30–90 seconds to boot
- **Apple Silicon + API 36 arm64:** likely 45–75 seconds (newer API = more services)
- **Subsequent launches (warm AVD):** 20–40 seconds

The currently running emulator (`emulator-5554`) is already booted, so for interactive development no cold-start cost applies.

### Memory requirements

| Component | Requirement |
|-----------|-------------|
| Android emulator (API 36, arm64) | 2–4 GB RAM |
| Gradle daemon (`-Xmx4g`) | 4 GB |
| Swift compiler (Android cross-compile) | 2–4 GB |
| macOS + Xcode overhead | 4–8 GB |
| **Total recommended** | **16–24 GB** |

The 48 GB M3 Max is **more than sufficient**. The emulator itself shows 4 GB total RAM, 2 GB available.

### Disk requirements

- Android SDK + NDK + API 36 system image: ~15–20 GB
- Swift Android SDK (swift-6.2.3): ~2–3 GB
- Gradle cache (all deps): ~2–4 GB
- Build artifacts (.build/): ~5–10 GB per example

### Apple Silicon compatibility

**No known issues.** The emulator is `arm64-v8a` which runs natively on Apple Silicon — no x86 translation layer needed. The Swift Android SDK targets `aarch64-unknown-linux-android`, matching the emulator's ABI. This setup is fully native end-to-end.

Known historical issues (pre-2023) with x86_64 emulator images on Apple Silicon are **not applicable** here since API 36 arm64 images are used.

### CI emulator startup script

```bash
#!/bin/bash
# ci-android-test.sh

# 1. Launch emulator headless in background
skip android emulator launch \
  --name emulator-36-medium_phone \
  --headless \
  --background

# 2. Wait for ADB connection
adb wait-for-device

# 3. Wait for full boot
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; do
  sleep 3
done

# 4. Disable animations (reduces flakiness)
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

# 5. Run tests
export ANDROID_SERIAL=$(adb devices | grep emulator | awk '{print $1}')
cd examples/fuse-library
skip android test \
  --testing-library FuseLibraryTests \
  --log-file /tmp/android-test.log \
  -v

TEST_EXIT=$?

# 6. Capture logcat artifact
adb logcat -d -s swift > /tmp/swift-logcat.txt

exit $TEST_EXIT
```

### Known CI gotchas

1. **Local fork path overrides break Gradle Swift build:** The fuse-app test XML showed:
   ```
   Gradle tests skipped: local fork path overrides incompatible with Gradle Swift build
   ```
   This means when `Package.swift` uses local path dependencies (`forks/`), the Gradle-embedded `skip android build` step cannot resolve them from the Gradle working directory. **This is the critical blocker for `skip android test`** — it will hit the same issue as fuse-app did. Workaround: set `SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1` and pre-build the .so files separately, then supply them.

2. **`SKIP_BRIDGE_ROBOLECTRIC_BUILD_DISABLED=1`:** Set this env var to skip the `buildLocalSwiftPackage` Gradle task if Swift is already built.

3. **`SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1`:** Set this to skip the `buildAndroidSwiftPackage` Gradle task when .so files are pre-built.

4. **Gradle daemon persistence:** First run after reboot starts a fresh daemon (slow). Subsequent runs reuse it.

5. **`ANDROID_SERIAL` env var:** Must be set when multiple devices are connected (e.g., both a real device and emulator). ADB will fail if ambiguous. Set `export ANDROID_SERIAL=emulator-5554` before any `adb` or `skip android test` invocation.

---

## 9. Makefile Gap: `android-test` Has No Recipe

**Current Makefile state:**

```makefile
.PHONY: build test android-build android-test skip-test skip-verify ...

android-build:
    cd $(EXAMPLE_DIR) && skip android build

# android-test: MISSING RECIPE
```

`android-test` is declared phony but has no implementation. Adding it:

```makefile
android-test:
    cd $(EXAMPLE_DIR) && skip android test
```

Or with full CI-appropriate options:

```makefile
android-test:
    cd $(EXAMPLE_DIR) && skip android test \
        --testing-library FuseLibraryTests \
        -v \
        --log-file .build/android-test.log
```

---

## 10. Summary of Automation Feasibility

| Test | Automatable? | Method | Blocker |
|------|-------------|--------|---------|
| HT-1 (app launches) | Partially | `adb am start` + pidof + logcat | Need log tag for recomposition |
| HT-2 (UI renders) | With effort | Screenshot comparison or UI Automator | Significant test authoring required |
| HT-3 (build succeeds) | Yes | `skip android build` exit code | Local fork path override issue |
| HT-4 (no infinite recompose) | Yes | logcat threshold check | Need exact log tag from ObservationStateRegistrar |
| HT-5 (JNI bridge loads) | Yes | `skip android test` passes | Same fork path override issue as HT-3 |

### Critical blocker for all on-device tests

The local fork path override incompatibility (seen in fuse-app's skipped Gradle tests) will affect fuse-library as well. The Gradle-embedded Swift build step (`buildAndroidSwiftPackageDebug`) runs `skip android build --package-path <src/main/swift>` from the Gradle project directory, but the local forks are referenced from `Package.swift` using relative paths like `../../forks/<name>`. These relative paths are resolved at SPM level but are not visible from inside the Gradle build tree.

**Workaround sequence:**
1. Run `skip android build` manually from the fuse-library directory first (SPM resolves forks correctly)
2. Set `SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1` before running `skip android test` (skips the embedded Swift build step, uses pre-built .so files)
3. The .so files land in the Gradle module's `build/jni-libs/` directory and get picked up by the AAR packaging step

```bash
# Step 1: Build Swift for Android (resolves forks via SPM)
cd examples/fuse-library
skip android build --arch aarch64 --configuration debug

# Step 2: Run instrumented tests without re-triggering Swift build
SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 skip android test \
  --testing-library FuseLibraryTests \
  -v
```
