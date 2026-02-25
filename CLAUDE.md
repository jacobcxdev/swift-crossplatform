# CLAUDE.md

## Architecture

Cross-platform Swift framework targeting iOS (native) and Android (via [Skip](https://skip.tools) JNI bridging). Uses TCA (swift-composable-architecture) for state management with a custom observation bridge (`BridgeObservationRegistrar`) that replays `@Observable` access tracking across the Swift→Kotlin→JNI boundary. Forked Point-Free and Skip dependencies in `forks/` provide Android compatibility while preserving iOS behaviour.

## Build & Test

Prerequisites: Swift 6.2+, [Skip](https://skip.tools) (`brew install skiptools/skip/skip`), Xcode. Android builds also need Android SDK/NDK (`skip android sdk install`).

### Makefile (preferred)

Grammar: `make [platform] [action…] [target…]`
- **platform**: `ios` | `android` (default: both)
- **action**: `build` | `test` | `run` | `clean` (default: `build`)
- **target**: example name — `fuse-library` | `fuse-app` (default: all)
- `run` on Android: launches emulator if needed → `skip export` → `adb install` → launch → streams `logcat` (Ctrl+C to stop). Skips export if APK is up to date (timestamp-checks `Sources/`, `Package.swift`, `forks/`). iOS `run` prints Xcode guidance.
- `clean` is platform-agnostic (`.build` is shared) — `make clean ios` ≡ `make clean`

```bash
# Build
make                                       # build all examples, both platforms
make fuse-app                              # build fuse-app, both platforms
make ios fuse-app                          # build fuse-app for iOS only
make android build fuse-app                # build fuse-app for Android only

# Test
make test                                  # test all examples, both platforms
make ios test fuse-library                 # test fuse-library on iOS
make ios test fuse-library FILTER=Obs      # filtered iOS test
make android test fuse-app                 # test fuse-app on Android

# Run (Android only — iOS: use Xcode Cmd+R)
make android run fuse-app                  # export APK, install, launch, stream logs
make run fuse-app                          # iOS: Xcode hint; Android: full pipeline

# Combined actions
make clean build fuse-app                  # clean then build

# Standalone
make skip-verify                           # skip verify --fix all examples
make clean                                 # clean all examples
```

To run iOS, use Xcode (Cmd+R). To run Android from CLI, use `make android run <target>` — this auto-launches the emulator, exports an APK via `skip export`, installs it, launches the app, and streams `adb logcat -s swift` (Ctrl+C to stop). When running from Xcode, set `SKIP_ACTION` in the `.xcconfig` to control Android: `launch` (default, build + run both platforms), `build` (build Android but don't launch), or `none` (skip Android entirely for faster iteration).

### Direct commands (from example directory)

```bash
cd examples/fuse-app && swift build                # iOS/macOS
cd examples/fuse-app && swift test                 # iOS/macOS tests
cd examples/fuse-app && skip test                  # Darwin + Android/Robolectric parity
cd examples/fuse-app && skip android test          # Android device/emulator only
cd examples/fuse-app && skip android build --configuration release --arch aarch64
```

### Skip toolchain

```bash
skip doctor --native               # Verify environment (native SDK)
skip checkup                       # Full system verification (builds sample)
skip devices                       # List available emulators/simulators
```

### Android debugging

```bash
adb logcat -s swift                # Stream Swift logs from device/emulator
skip android emulator launch --logcat '*:W'  # Launch emulator with filtered logs
```

## Submodule Management

Fork submodules live in `forks/`. Use these from the repo root:

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

- All forks track the `dev/swift-crossplatform` branch
- Example projects reference forks via local path: `.package(path: "../../forks/<name>")`
- All fork changes must gate behind `#if os(Android)` or `#if SKIP_BRIDGE` to preserve iOS behavior
- No iOS regressions — every fork must build and test cleanly on both platforms

**Typical workflow:** Edit code in `forks/<name>/`, then build/test from `examples/fuse-library/` (which resolves forks via local path dependencies). Commit within the fork submodule, then update the parent repo's submodule pointer.

**Point-Free fork verification:** When writing tests or making changes to Point-Free forks, verify implementations against the corresponding `/pfw-*` skill (e.g. `/pfw-composable-architecture`, `/pfw-sharing`, `/pfw-case-paths`). These skills contain canonical API patterns and anti-pattern rules that tests must conform to.

## Platform Conditionals & Environment Variables

| Variable / Guard | Scope | Effect |
|------------------|-------|--------|
| `TARGET_OS_ANDROID` | SPM `Context.environment` | Enables Android-specific dependencies in Package.swift at resolution time |
| `SKIP_BRIDGE` | Swift compiler define | Gates bridge-level observation code in skip-android-bridge (`ObservationRecording`, JNI exports) |
| `#if os(Android)` | Swift conditional compilation | Standard platform check for Android-specific runtime code paths |
| `#if canImport(SwiftUI)` | Swift conditional compilation | False on Android -- SkipFuseUI re-exports SkipSwiftUI, not Apple's SwiftUI module |
| `#if SKIP` | Swift conditional compilation | True only in Skip-transpiled Kotlin context (e.g., `loadPeerLibrary`) |
| `FUSE_NAV_DEBUG` | Swift compiler define (opt-in) | Enables navigation debug logging in skip-ui, skip-fuse-ui, skip-android-bridge, TCA. Add `.define("FUSE_NAV_DEBUG")` to relevant Package.swift targets |
| `FUSE_TAB_DEBUG` | Swift compiler define (opt-in) | Enables tab debug logging in skip-ui. Add `.define("FUSE_TAB_DEBUG")` to SkipUI target in `forks/skip-ui/Package.swift` |

## Testing

- Use Swift Testing (preferred) or XCTest
- Run `skip test` (not just `swift test`) to catch platform divergence — it runs both Darwin and Android/Robolectric
- Filter with `make ios test fuse-library FILTER=Obs`

## Gotchas

- **`swiftThreadingFatal` stub**: Required in skip-android-bridge for `libswiftObservation.so` to load on Android until Swift 6.3 ([swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890))
- **JNI naming**: Exports must match `Java_skip_ui_ViewObservation_<method>` exactly — package dots become underscores
- **Fuse mode only**: Lite mode's counter-based observation is fundamentally incompatible with TCA. Don't attempt Lite mode for TCA apps
- **No `swift-perception` on Android**: Use native `libswiftObservation.so` (ships with Swift Android SDK)
- **`withAnimation` requires JNI context on Android**: `withAnimation` in skip-fuse-ui bridges to Java via JNI. In Robolectric test contexts where JNI is uninitialised, it guards with `isJNIInitialized` and skips animation bridge calls (executing the body directly). Animation is purely visual, so state mutations still apply correctly.
- **Android builds can pass when running fails**: `skip android build` succeeding does NOT mean the app works. Always verify with `skip android test` or emulator testing -- runtime JNI/bridge failures only surface at execution time.
- **Clean builds after dependency changes**: After modifying any fork's `Package.swift` or changing submodule pointers, run `swift package clean` or `make clean` before rebuilding. Incremental builds can use stale dependency artifacts.
- **skip-fuse-ui NavigationStack is generic**: Unlike skip-ui's non-generic `NavigationStack`, skip-fuse-ui provides `NavigationStack<Data, Root>` matching SwiftUI's generic signature. TCA extensions constrain `Data` to `StackState<State>.PathView` -- this compiles on Android via skip-fuse-ui.
- **SF Symbol mapping on Android**: skip-ui maps ~60 SF Symbol names to Material Design icons (core set only). Unmapped names display a warning triangle. Before using a new SF Symbol, check the mapping table in `forks/skip-ui/Sources/SkipUI/SkipUI/Components/Image.swift` (~line 431). To add a mapping, the target Material icon must exist in `material-icons-core` (verified by the resolver function at ~line 516). Build-verify after adding.
- **@Shared reactivity on Android**: `@Shared` properties are reactive on Android via the `BridgeObservationRegistrar` integration in swift-perception. If reactivity issues resurface, check that `PerceptionRegistrar` on Android is using `BridgeObservationRegistrar` (not stdlib `ObservationRegistrar`).
