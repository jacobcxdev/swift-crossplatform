# CLAUDE.md

## Quick Start (Bootstrap)

```bash
git clone --recursive https://github.com/jacobcxdev/swift-crossplatform.git
cd swift-crossplatform
just setup-toolchain      # install custom Swift 6.2.4 toolchain + Android SDK
just doctor               # verify environment
just ios-build fuse-app   # build for iOS
just android-run fuse-app # full Android pipeline
```

Prerequisites: Swift 6.2+, Xcode, [Skip](https://skip.tools) (`brew install skiptools/skip/skip`), [Just](https://github.com/casey/just) (`brew install just`), `gh` CLI (for toolchain download). Android builds also need JDK 21+, Android SDK/NDK (`skip android sdk install`).

## Architecture

Cross-platform Swift framework targeting iOS (native) and Android (via [Skip](https://skip.tools) JNI bridging). Uses TCA (swift-composable-architecture) for state management with a custom observation bridge (`BridgeObservationRegistrar`) that replays `@Observable` access tracking across the Swift→Kotlin→JNI boundary. Forked Point-Free and Skip dependencies in `forks/` provide Android compatibility while preserving iOS behaviour.

### Repository Layout

```
swift-crossplatform/
├── forks/                    # 23 git submodule forks (Point-Free + Skip)
│   ├── skip/                 # Skip SPM plugin (upstream-identical Package.swift)
│   ├── skipstone/            # Skip transpiler (upstream-identical Package.swift)
│   │   └── skip/             # Nested upstream submodule (SkipDriveExternal symlink target)
│   ├── skip-ui/              # Skip UI framework fork
│   ├── skip-fuse-ui/         # Skip Fuse UI framework fork
│   ├── swift-composable-architecture/  # TCA fork with Android gating
│   └── ...                   # Other Point-Free + Skip library forks
├── examples/
│   ├── fuse-app/             # Full TCA app (Fuse mode) — primary test target
│   ├── fuse-library/         # Library with comprehensive test coverage
│   ├── lite-app/             # Lite mode app (upstream remote deps, no TCA)
│   ├── lite-library/         # Lite mode library (upstream remote deps)
│   ├── skipapp-showcase/     # Upstream Lite showcase (submodule, validation only)
│   └── skipapp-showcase-fuse/# Upstream Fuse showcase (submodule, validation only)
├── justfile                  # Build orchestration (run `just` to see all recipes)
└── .planning/                # Plans, patches, upstream pins
```

## Build & Test (justfile)

Run `just` or `just --list` to see all available recipes.

```bash
# Build (both platforms via xcodebuild — app targets only)
just build fuse-app                    # build for iOS + Android (SKIP_ACTION=build)

# Build (single platform via SPM / Skip CLI)
just ios-build                         # build all examples for iOS (swift build)
just ios-build fuse-app                # build fuse-app for iOS
just android-build fuse-app            # build fuse-app for Android (uses local skipstone)

# Run
just run fuse-app                      # build + launch on iOS simulator + Android emulator
just ios-run fuse-app                  # build + launch on iOS simulator only
just android-run fuse-app              # emulator → export APK → install → launch → logcat

# Test
just ios-test                          # test all examples on iOS
just ios-test fuse-library             # test fuse-library on iOS
just android-test fuse-app             # test fuse-app on Android

# Clean
just clean                             # clean all examples

# Setup & Diagnostics
just init                              # git submodule update --init --recursive
just doctor                            # preflight checks (11 checks)
just status                            # git status across all submodules
just check-branches                    # verify fork branches
just check-upstream-purity             # verify skip/skipstone match upstream
```

The `build`, `ios-run`, and `run` recipes require an Xcode project (`Darwin/<ProductName>.xcodeproj`), so they only work for app targets (e.g. `fuse-app`, `lite-app`). Library targets use `ios-build`/`android-build` instead.

### Direct commands (from example directory)

```bash
cd examples/fuse-app && swift build         # iOS/macOS
cd examples/fuse-app && swift test          # iOS/macOS tests
cd examples/fuse-app && skip test           # Darwin + Android/Robolectric parity
cd examples/fuse-app && skip android test   # Android device/emulator only
```

### Skip toolchain

```bash
skip doctor --native               # Verify environment (native SDK)
skip checkup                       # Full system verification (builds sample)
skip devices                       # List available emulators/simulators
```

### Android builds with local skipstone

Android builds use the locally-built skipstone transpiler via `forks/skipstone/scripts/skip`. This ensures our transpiler fixes (e.g. compose view identity gap) are active. The justfile handles this automatically. To verify the local build is being used:

```bash
cd forks/skipstone && ./scripts/skip version
# Output: Skip version X.Y.Z (debug)  ← "(debug)" = local source build
# Compare: skip version → Skip version X.Y.Z  ← Homebrew binary (no suffix)
```

### Xcode integration

`SKIP_ACTION` controls the Android build phase in xcodebuild (used by both Xcode and justfile):
- `launch` — build + run both platforms (`just run`, Xcode Cmd+R default)
- `build` — build Android but don't launch (`just build`)
- `none` — skip Android entirely (`just ios-run`, or set in `.xcconfig` for faster Xcode iteration)

The justfile's `build`/`ios-run`/`run` recipes pass `SKIP_ACTION` to xcodebuild directly. When using Xcode manually (Cmd+R), `SKIP_ACTION` is read from `Darwin/<ProductName>.xcconfig`.

### Android debugging

```bash
adb logcat --pid=$(adb shell pidof <pkg>)    # Stream all logs from app process
skip android emulator launch --logcat '*:W'  # Launch emulator with filtered logs
```

Log tags: `fuse.app.FuseApp`, `SkipFoundation`, `skip.android.bridge/AndroidBridge`, `skip.ui.SkipUI`.

## Submodule Management

Fork submodules live in `forks/`. All forks track the `dev/swift-crossplatform` branch.

```bash
just init              # initialise all submodules (including nested skipstone/skip)
just status            # git status for all submodules
just check-branches    # show current branch per direct fork
just diff-all          # show uncommitted changes across submodules
just push-all          # push all submodule changes
just pull-all          # pull latest for each submodule
```

**Important:** `forks/skipstone/skip/` is a **nested upstream submodule** (not our fork). It provides the `SkipDriveExternal` symlink target. Use `just init` (which runs `--recursive`) to populate it.

## Working with Forks

- All forks track the `dev/swift-crossplatform` branch
- Example projects reference forks via local path: `.package(path: "../../forks/<name>")`
- All fork changes must gate behind `#if os(Android)` or `#if SKIP_BRIDGE` to preserve iOS behaviour
- No iOS regressions — every fork must build and test cleanly on both platforms

**Typical workflow:** Edit code in `forks/<name>/`, then build/test from `examples/fuse-library/` (which resolves forks via local path dependencies). Commit within the fork submodule, then update the parent repo's submodule pointer.

**Point-Free fork verification:** When writing tests or making changes to Point-Free forks, verify implementations against the corresponding `/pfw-*` skill (e.g. `/pfw-composable-architecture`, `/pfw-sharing`, `/pfw-case-paths`). These skills contain canonical API patterns and anti-pattern rules that tests must conform to.

### Fork Change Policy

- `#if os(Android)` / `#if SKIP_BRIDGE` gated code: **ACCEPTABLE** — consider upstreaming
- Local path deps in Package.swift: **ACCEPTABLE** — enables standalone fork builds
- Android-conditional deps in Package.swift: **ACCEPTABLE** — gated by `TARGET_OS_ANDROID`
- Workarounds for build issues (flag injection, platform hacks): **NEVER** — investigate root cause
- Feature enhancements (transpiler fixes, UI improvements): **ACCEPTABLE** — strongly consider upstreaming
- **skip and skipstone Package.swift must remain byte-identical to upstream** — verified by `just check-upstream-purity`

### Fork Inventory

| Fork | Category | Changes | Description |
|------|----------|---------|-------------|
| skip | skiptools-tool | None (upstream-identical) | SPM plugin, downloads binary or builds from skipstone |
| skipstone | skiptools-tool | Transpiler only | Compose view identity gap fix (StatementTypes, BridgeToKotlinVisitor) |
| skip-android-bridge | skiptools-lib | Local paths + nav debug | Observation bridge, JNI exports |
| skip-fuse-ui | skiptools-lib | Local paths + UI fixes | Animation, Navigation, Accessibility |
| skip-ui | skiptools-lib | UI improvements | Image mapping, List, Navigation, TabView debug |
| swift-composable-architecture | pointfreeco | Local paths + Android gating | Store, Animation, NavigationStack, IfLetStore |
| swift-perception | pointfreeco | Android bridge | BridgeObservationRegistrar integration |
| swift-navigation | pointfreeco | Feature work | TextState, ButtonState enhancements |
| swift-structured-queries | pointfreeco | Android gating | Test infra conditional compilation |
| sqlite-data | pointfreeco | Android gating | Test infra conditional compilation |
| GRDB.swift | other | Symlink fix | Removed recursive symlink in Tests/ |

Forks with no changes: skip-fuse, swift-identified-collections, swift-custom-dump, swift-concurrency-extras, xctest-dynamic-overlay, swift-snapshot-testing.

### Upstream Sync Workflow

```bash
just sync-upstream     # fetch upstream for all forks
# Then per fork:
cd forks/<name>
git merge upstream/main
# Resolve conflicts (Package.swift local paths are the common conflict point)
just check-upstream-purity   # verify skip/skipstone still match upstream
just ios-test && just android-build fuse-app   # regression check
```

### Upstream PR Workflow

1. `cd forks/<name> && git checkout -b pr/<feature> upstream/main`
2. Cherry-pick relevant commits from `dev/swift-crossplatform`
3. Ensure changes are gated with `#if os(Android)` / `#if SKIP_BRIDGE`
4. Open PR against upstream repo

### External App Consumption

A private app consuming these forks:

- **CI/release:** `.package(url: "https://github.com/jacobcxdev/<fork>.git", branch: "dev/swift-crossplatform")`
- **Local dev:** Xcode workspace containing the private app + swift-crossplatform repo (SPM auto-resolves local checkouts), or `.package(path: "../swift-crossplatform/forks/<fork>")` overrides

## Toolchain Versions

| Tool | Minimum | Notes |
|------|---------|-------|
| Swift | 6.2+ | Apple Swift via Xcode |
| Xcode | 16+ | |
| Skip CLI | 1.7+ | `brew install skiptools/skip/skip` |
| Just | any | `brew install just` |
| JDK | 21+ | For Android builds |
| Android SDK | API 36 | `skip android sdk install` |
| Custom toolchain | 6.2.4 | `just setup-toolchain` (installs toolchain + Android SDK) |

## Platform Conditionals & Environment Variables

| Variable / Guard | Scope | Effect |
|------------------|-------|--------|
| `TARGET_OS_ANDROID` | SPM `Context.environment` | Enables Android-specific dependencies in Package.swift at resolution time |
| `SKIP_BRIDGE` | Swift compiler define | Gates bridge-level observation code in skip-android-bridge (`ObservationRecording`, JNI exports) |
| `#if os(Android)` | Swift conditional compilation | Standard platform check for Android-specific runtime code paths |
| `#if canImport(SwiftUI)` | Swift conditional compilation | False on Android — SkipFuseUI re-exports SkipSwiftUI, not Apple's SwiftUI module |
| `#if SKIP` | Swift conditional compilation | True only in Skip-transpiled Kotlin context (e.g., `loadPeerLibrary`) |
| `FUSE_NAV_DEBUG` | Swift compiler define (opt-in) | Enables navigation debug logging. Add `.define("FUSE_NAV_DEBUG")` to relevant Package.swift targets |
| `FUSE_TAB_DEBUG` | Swift compiler define (opt-in) | Enables tab debug logging. Add `.define("FUSE_TAB_DEBUG")` to SkipUI target |
| `SKIPLOCAL` | Environment variable | When set, skip's Package.swift resolves skipstone as local source dependency instead of downloading binary. Not normally needed — justfile uses `scripts/skip` mechanism instead |

## Testing

- Use Swift Testing (preferred) or XCTest
- Run `skip test` (not just `swift test`) to catch platform divergence — it runs both Darwin and Android/Robolectric
- Filter: `just ios-test fuse-library` or `cd examples/fuse-library && swift test --filter Obs`

## Skipstone Transpiler Design Principles

When generating Kotlin bridge code in `KotlinBridgeToKotlinVisitor`:

- **Lean on Compose primitives** — express intent through `remember`, `remember(key)`, `RememberObserver`, etc. rather than reimplementing their logic manually. If Compose has a built-in mechanism for what you need (lifecycle callbacks, key-based cache invalidation), use it.
- **Peer remembering uses one pattern with one variable** — `SwiftPeerHandle` wraps retain/release into a `RememberObserver`; the only difference between view types is the `remember` key: absent for views with no constructor params (never invalidate), present with `Swift_inputsHash` for mixed views (invalidate when inputs change).
- **`Swift_inputsHash` runs on the Swift side** — constructor params don't need to be bridged to Kotlin for hashing. Both bridgable Kotlin members and unbridged Swift-only properties (tracked via `uninitializedStructProperty(name)`) are accessible through the peer pointer.

## SPM Mirror Configuration

Non-forked transitive dependencies (`skip-model`, `skip-bridge`, `skip-foundation`, etc.) reference `source.skip.tools/skip.git` and `source.skip.tools/skip-ui.git` via remote URLs, which conflict with our local `forks/skip` and `forks/skip-ui` path dependencies. SPM mirrors redirect the remote URLs to the local forks, eliminating identity warnings that would otherwise become errors in future SPM versions. This is especially important for showcase apps (`skipapp-showcase`, `skipapp-showcase-fuse`) whose Package.swift files mix local fork paths with remote dependencies that transitively depend on `skip` and `skip-ui`.

- `just init` sets up mirrors automatically (calls `just setup-mirrors`)
- `just doctor` verifies mirrors are configured
- `just setup-mirrors` can be run independently to (re)configure mirrors for all example dirs (fuse-app, fuse-library, skipapp-showcase, skipapp-showcase-fuse)
- Mirror config lives in `examples/*/.swiftpm/configuration/mirrors.json` (gitignored — must be set up per-clone)

## Gotchas

- **`swiftThreadingFatal` stub**: Required in skip-android-bridge for `libswiftObservation.so` to load on Android until Swift 6.3 ([swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890))
- **JNI naming**: Exports must match `Java_skip_ui_ViewObservation_<method>` exactly — package dots become underscores
- **Fuse mode only**: Lite mode's counter-based observation is fundamentally incompatible with TCA. Don't attempt Lite mode for TCA apps
- **No `swift-perception` on Android**: Use native `libswiftObservation.so` (ships with Swift Android SDK)
- **`withAnimation` requires JNI context on Android**: In Robolectric test contexts where JNI is uninitialised, it guards with `isJNIInitialized` and skips animation bridge calls. Animation is purely visual, so state mutations still apply correctly.
- **Android builds can pass when running fails**: `skip android build` succeeding does NOT mean the app works. Always verify with `skip android test` or emulator testing — runtime JNI/bridge failures only surface at execution time.
- **Clean builds after dependency changes**: After modifying any fork's `Package.swift` or changing submodule pointers, run `just clean` before rebuilding. Incremental builds can use stale dependency artifacts.
- **skip-fuse-ui NavigationStack is generic**: Unlike skip-ui's non-generic `NavigationStack`, skip-fuse-ui provides `NavigationStack<Data, Root>` matching SwiftUI's generic signature. TCA extensions constrain `Data` to `StackState<State>.PathView`.
- **SF Symbol mapping on Android**: skip-ui maps ~60 SF Symbol names to Material Design icons. Unmapped names display a warning triangle. Check the mapping table in `forks/skip-ui/Sources/SkipUI/SkipUI/Components/Image.swift` (~line 431).
- **@Shared reactivity on Android**: `@Shared` properties are reactive on Android via `BridgeObservationRegistrar` integration in swift-perception. If reactivity issues resurface, check that `PerceptionRegistrar` on Android is using `BridgeObservationRegistrar`.
- **Nested submodule must be initialised**: `forks/skipstone/skip/` is a nested submodule. If `SkipDriveExternal` symlink is broken, run `just init` (which uses `--recursive`).
- **`just android-run` streams logcat indefinitely**: The recipe tails `adb logcat` after launching the app — it will never "complete". Do not treat it as a finite task or poll for completion. The build/install/launch phase finishes when logcat output starts streaming; the command itself runs until manually interrupted (Ctrl+C).
- **Skip.env files**: `examples/*/Skip.env` contains app metadata (bundle ID, version) shared between iOS (xcconfig) and Android (Gradle). These are standard upstream configuration — do not modify as part of infrastructure work.
