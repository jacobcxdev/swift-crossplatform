# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Prerequisites: Swift 6.2+, [Skip](https://skip.tools) (`brew install skiptools/skip/skip`), Xcode. Android builds also need Android SDK/NDK (`skip android sdk install`).

All build/test targets default to `fuse-library`. Override with `EXAMPLE=fuse-app`.

```bash
# From repo root (delegates to examples/fuse-library by default)
make build                         # swift build (macOS)
make test                          # swift test (macOS)
make test-filter FILTER=ObservationTests  # Run a single test suite
make android-build                 # skip android build
make skip-test                     # skip test (cross-platform parity)
make skip-verify                   # skip verify --fix

# Or run directly from an example directory
cd examples/fuse-app && swift build
cd examples/fuse-app && skip android build --configuration release --arch aarch64

# Skip toolchain
skip doctor --native               # Verify environment (native SDK)
skip checkup                       # Full system verification (builds sample)
skip devices                       # List available emulators/simulators

# Android debugging
adb logcat -s swift                # Stream Swift logs from device/emulator
skip android emulator launch --logcat '*:W'  # Launch emulator with filtered logs
```

## Submodule Management

17 fork submodules live in `forks/`. Use these from the repo root:

```bash
# After fresh clone
git submodule update --init --recursive

make status            # Git status for all submodules
make branch-all        # Show current branch per submodule
make pull-all          # Pull latest for each submodule's tracking branch
make push-all          # Push all submodule changes
make diff-all          # Show uncommitted changes across submodules
```

## Working with Forks

- All 17 forks track the `dev/swift-crossplatform` branch
- Example projects reference forks via local path: `.package(path: "../../forks/<name>")`
- All fork changes must gate behind `#if os(Android)` or `#if SKIP_BRIDGE` to preserve iOS behavior
- No iOS regressions — every fork must build and test cleanly on both platforms

**Typical workflow:** Edit code in `forks/<name>/`, then build/test from `examples/fuse-library/` (which resolves forks via local path dependencies). Commit within the fork submodule, then update the parent repo's submodule pointer.

## Key Files

The observation bridge fix spans 3 files across forks:

- `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` — `ObservationRecording` record-replay + JNI exports
- `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift` — `ViewObservation` hooks around `Evaluate()`
- `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift` — Android registrar path

**Skip reference docs** in `docs/skip/`: `modes.md` (Fuse vs Lite), `bridging.md` (JNI mechanics), `debugging.md` (adb/logcat), `testing.md` (parity tests).

**Example projects** (`EXAMPLE=` values): `fuse-library` (default, reusable library with observation tests), `fuse-app` (full app), `lite-app`/`lite-library` (Lite mode, not for TCA).

## Platform Conditionals

```swift
#if os(Android)    // Android-specific code paths
#if SKIP_BRIDGE    // Bridge-level observation wrappers (skip-android-bridge)
```

## Project Planning

Planning state lives in `.planning/`:

- `STATE.md` — current phase and progress
- `ROADMAP.md` — 7 phases with requirements and success criteria
- `REQUIREMENTS.md` — 184 atomic API-level specifications
- `PROJECT.md` — project context, decisions, constraints
- `config.json` — GSD workflow configuration
- `research/` — domain research documents
- `local/` — private context (gitignored)

## Gotchas

- **`swiftThreadingFatal` stub**: Required in skip-android-bridge for `libswiftObservation.so` to load on Android until Swift 6.3 ([swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890))
- **JNI naming**: Exports must match `Java_skip_ui_ViewObservation_<method>` exactly — package dots become underscores
- **Fuse mode only**: Lite mode's counter-based observation is fundamentally incompatible with TCA. Don't attempt Lite mode for TCA apps
- **No `swift-perception` on Android**: Use native `libswiftObservation.so` (ships with Swift Android SDK)
