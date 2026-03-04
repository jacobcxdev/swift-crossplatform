# swift-crossplatform justfile
# Usage: just <recipe> [args...]
# Run `just` or `just --list` to see all available recipes.

# ── Variables ────────────────────────────────────────────────────
skip := justfile_directory() / "forks/skipstone/scripts/skip"
examples := "fuse-library fuse-app lite-library lite-app"
fuse_examples := "fuse-library fuse-app"
showcases := "skipapp-showcase skipapp-showcase-fuse"
export FILTER := ""

# ── Default ──────────────────────────────────────────────────────

# List all available recipes
default:
    @just --list

# ── Dispatch ───────────────────────────────────────────────────────

# Multi-action dispatch: just do [platform] [action…] [target…]
[doc("Dispatch: just do [ios|android] [build|test|run|clean] [target…] (e.g. just do clean android run fuse-app)")]
do +words="build":
    #!/usr/bin/env bash
    set -euo pipefail
    platform="" actions="" targets=""
    for w in {{ words }}; do
      case "$w" in
        ios|android) platform="$w" ;;
        build|test|run|clean) actions="$actions $w" ;;
        # Handle compound names: ios-build, android-run, etc.
        ios-*|android-*)
          platform="${w%%-*}"
          actions="$actions ${w#*-}"
          ;;
        *) targets="$targets $w" ;;
      esac
    done
    actions="${actions# }"; targets="${targets# }"
    [ -z "$actions" ] && actions="build"
    [ -z "$targets" ] && targets="{{ fuse_examples }}"
    [ -z "$platform" ] && platforms="ios android" || platforms="$platform"
    for action in $actions; do
      case "$action" in
        clean)
          for ex in $targets; do
            if [ -d "examples/$ex" ]; then
              echo "=== Cleaning $ex ==="
              (cd "examples/$ex" && swift package clean && rm -rf .build/plugins/outputs .build/DerivedData)
            fi
          done
          ;;
        build)
          for ex in $targets; do
            if [ -z "$platform" ]; then
              just build "$ex"
            else
              for p in $platforms; do
                case "$p" in
                  ios)     just ios-build "$ex" ;;
                  android) just android-build "$ex" ;;
                esac
              done
            fi
          done
          ;;
        test)
          for p in $platforms; do
            case "$p" in
              ios)     just ios-test $targets ;;
              android) just android-test $targets ;;
            esac
          done
          ;;
        run)
          for ex in $targets; do
            if [ -z "$platform" ]; then
              just run "$ex"
            else
              for p in $platforms; do
                case "$p" in
                  ios)     just ios-run "$ex" ;;
                  android) just android-run "$ex" ;;
                esac
              done
            fi
          done
          ;;
      esac
    done

# List available example targets
targets:
    @echo "Examples:  {{ examples }}"
    @echo "Fuse only: {{ fuse_examples }}"
    @echo "Showcases: {{ showcases }}"

# ── Build ────────────────────────────────────────────────────────

# Build example(s) for iOS via SPM (default: all examples)
ios-build *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    targets="{{ targets }}"
    targets="${targets:-{{ examples }}}"
    for ex in $targets; do
      echo "=== Building $ex (iOS) ==="
      (cd "examples/$ex" && swift build)
    done

# Build example(s) for Android using local skipstone (default: fuse examples)
android-build *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    targets="{{ targets }}"
    targets="${targets:-{{ fuse_examples }}}"
    for ex in $targets; do
      echo "=== Building $ex (Android) ==="
      (cd "examples/$ex" && "{{ skip }}" android build)
    done

# Build app for both platforms via xcodebuild (SKIP_ACTION=build triggers Android build phase)
build target:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    product_name=$(grep '^PRODUCT_NAME' "examples/{{ target }}/Skip.env" | sed 's/.*= *//')
    xcodeproj="examples/{{ target }}/Darwin/${product_name}.xcodeproj"
    scheme="${product_name} App"
    if [ ! -d "$xcodeproj" ]; then
      echo "Error: no Xcode project at $xcodeproj — build only works for app targets" >&2
      exit 1
    fi
    echo "=== Building {{ target }} (iOS + Android) ==="
    xcodebuild \
      -project "$xcodeproj" \
      -scheme "$scheme" \
      -destination 'generic/platform=iOS Simulator' \
      SKIP_ACTION=build \
      build 2>&1 | tail -5
    echo "=== {{ target }} built for both platforms ==="

# Build showcase apps for iOS (requires iOS SDK — these target iOS, not macOS)
showcase-build:
    #!/usr/bin/env bash
    set -euo pipefail
    SDK=$(xcrun --show-sdk-path --sdk iphonesimulator)
    for ex in {{ showcases }}; do
      if [ -d "examples/$ex" ]; then
        echo "=== Building $ex (iOS) ==="
        (cd "examples/$ex" && swift build --sdk "$SDK" --triple arm64-apple-ios17.0-simulator)
      fi
    done

# ── Run ──────────────────────────────────────────────────────────

# Run on iOS simulator via xcodebuild (builds + launches the app)
ios-run target:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    product_name=$(grep '^PRODUCT_NAME' "examples/{{ target }}/Skip.env" | sed 's/.*= *//')
    xcodeproj="examples/{{ target }}/Darwin/${product_name}.xcodeproj"
    scheme="${product_name} App"
    if [ ! -d "$xcodeproj" ]; then
      echo "Error: no Xcode project at $xcodeproj — ios-run only works for app targets" >&2
      exit 1
    fi
    # Find a booted iPhone simulator, or boot the first available one
    sim_id=$(xcrun simctl list devices booted -j | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    for runtime, devices in data.get('devices', {}).items():
        if 'iOS' not in runtime: continue
        for d in devices:
            if d.get('state') == 'Booted' and 'iPhone' in d.get('name', ''):
                print(d['udid']); sys.exit(0)
    " 2>/dev/null || true)
    if [ -z "$sim_id" ]; then
      echo "No booted iPhone simulator — booting one..."
      sim_id=$(xcrun simctl list devices available -j | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    for runtime, devices in sorted(data.get('devices', {}).items(), reverse=True):
        if 'iOS' not in runtime: continue
        for d in devices:
            if d.get('isAvailable') and 'iPhone' in d.get('name', ''):
                print(d['udid']); sys.exit(0)
    print('', end='')
    " 2>/dev/null || true)
      if [ -z "$sim_id" ]; then
        echo "Error: no available iPhone simulator found" >&2
        exit 1
      fi
      xcrun simctl boot "$sim_id"
      open -a Simulator
    fi
    sim_name=$(xcrun simctl list devices -j | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    for devices in data.get('devices', {}).values():
        for d in devices:
            if d['udid'] == '$sim_id':
                print(d['name']); sys.exit(0)
    " 2>/dev/null)
    echo "=== Building & running {{ target }} (iOS) on $sim_name ==="
    xcodebuild \
      -project "$xcodeproj" \
      -scheme "$scheme" \
      -destination "id=$sim_id" \
      SKIP_ACTION=none \
      build 2>&1 | tail -5
    # Install and launch
    app_path=$(find "$(xcodebuild -project "$xcodeproj" -scheme "$scheme" -destination "id=$sim_id" -showBuildSettings SKIP_ACTION=none 2>/dev/null \
      | grep '^\s*BUILT_PRODUCTS_DIR' | sed 's/.*= //')" -name "*.app" -maxdepth 1 2>/dev/null | head -1)
    if [ -z "$app_path" ]; then
      echo "Error: could not find built .app bundle" >&2
      exit 1
    fi
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist" 2>/dev/null)
    xcrun simctl install "$sim_id" "$app_path"
    echo "Launching $bundle_id..."
    xcrun simctl launch "$sim_id" "$bundle_id"
    echo "=== {{ target }} running on $sim_name ==="

# Run on both platforms (xcodebuild with SKIP_ACTION=launch builds + launches Android; simctl launches iOS)
run target:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    product_name=$(grep '^PRODUCT_NAME' "examples/{{ target }}/Skip.env" | sed 's/.*= *//')
    xcodeproj="examples/{{ target }}/Darwin/${product_name}.xcodeproj"
    scheme="${product_name} App"
    if [ ! -d "$xcodeproj" ]; then
      echo "Error: no Xcode project at $xcodeproj — run only works for app targets" >&2
      exit 1
    fi
    # Ensure Android emulator is running for SKIP_ACTION=launch
    if ! adb devices 2>/dev/null | grep -q 'emulator.*device$'; then
      echo "No Android emulator running — launching one..."
      skip android emulator launch &
      adb wait-for-device
    fi
    # Find a booted iPhone simulator, or boot the first available one
    sim_id=$(xcrun simctl list devices booted -j | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    for runtime, devices in data.get('devices', {}).items():
        if 'iOS' not in runtime: continue
        for d in devices:
            if d.get('state') == 'Booted' and 'iPhone' in d.get('name', ''):
                print(d['udid']); sys.exit(0)
    " 2>/dev/null || true)
    if [ -z "$sim_id" ]; then
      echo "No booted iPhone simulator — booting one..."
      sim_id=$(xcrun simctl list devices available -j | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    for runtime, devices in sorted(data.get('devices', {}).items(), reverse=True):
        if 'iOS' not in runtime: continue
        for d in devices:
            if d.get('isAvailable') and 'iPhone' in d.get('name', ''):
                print(d['udid']); sys.exit(0)
    print('', end='')
    " 2>/dev/null || true)
      if [ -z "$sim_id" ]; then
        echo "Error: no available iPhone simulator found" >&2
        exit 1
      fi
      xcrun simctl boot "$sim_id"
      open -a Simulator
    fi
    sim_name=$(xcrun simctl list devices -j | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    for devices in data.get('devices', {}).values():
        for d in devices:
            if d['udid'] == '$sim_id':
                print(d['name']); sys.exit(0)
    " 2>/dev/null)
    echo "=== Building & running {{ target }} on both platforms ($sim_name + Android) ==="
    xcodebuild \
      -project "$xcodeproj" \
      -scheme "$scheme" \
      -destination "id=$sim_id" \
      SKIP_ACTION=launch \
      build 2>&1 | tail -5
    # Install and launch on iOS
    app_path=$(find "$(xcodebuild -project "$xcodeproj" -scheme "$scheme" -destination "id=$sim_id" -showBuildSettings SKIP_ACTION=launch 2>/dev/null \
      | grep '^\s*BUILT_PRODUCTS_DIR' | sed 's/.*= //')" -name "*.app" -maxdepth 1 2>/dev/null | head -1)
    if [ -z "$app_path" ]; then
      echo "Error: could not find built .app bundle" >&2
      exit 1
    fi
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist" 2>/dev/null)
    xcrun simctl install "$sim_id" "$app_path"
    echo "Launching $bundle_id on iOS..."
    xcrun simctl launch "$sim_id" "$bundle_id"
    echo "=== {{ target }} running on $sim_name (iOS) + Android emulator ==="

# Run on Android (full pipeline: emulator → export → install → launch → logcat)
android-run target:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    # Ensure emulator is running
    if ! adb devices 2>/dev/null | grep -q 'emulator.*device$'; then
      echo "No emulator running — launching one..."
      skip android emulator launch &
      adb wait-for-device
    fi
    # Export APK
    export_dir="examples/{{ target }}/.build/export"
    apk=$(ls "$export_dir"/*-debug.apk 2>/dev/null | head -1 || true)
    if [ -z "$apk" ] || [ -n "$(find "examples/{{ target }}/Sources" "examples/{{ target }}/Package.swift" forks/ -newer "$apk" -name '*.swift' -print -quit 2>/dev/null)" ]; then
      echo "Source changed — rebuilding APK..."
      rm -rf "$export_dir"
      (cd "examples/{{ target }}" && "{{ skip }}" export --debug --android --no-ios -d .build/export)
      apk=$(ls "$export_dir"/*-debug.apk 2>/dev/null | head -1 || true)
      if [ -z "$apk" ]; then echo "Error: no APK found in $export_dir" >&2; exit 1; fi
    else
      echo "APK up to date — skipping export"
    fi
    # Find aapt
    sdk_home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
    if [ -z "$sdk_home" ]; then
      for candidate in "$HOME/Library/Android/sdk" /opt/homebrew/share/android-commandlinetools; do
        if [ -d "$candidate/build-tools" ]; then sdk_home="$candidate"; break; fi
      done
    fi
    aapt_bin=$(ls -d "$sdk_home/build-tools"/*/ 2>/dev/null | sort -V | tail -1 || true)
    aapt_bin="${aapt_bin}aapt"
    if [ ! -x "$aapt_bin" ]; then echo "Error: aapt not found — install Android SDK build-tools" >&2; exit 1; fi
    # Install and launch
    pkg=$($aapt_bin dump badging "$apk" | awk -F"'" '/^package:/{print $2}')
    activity=$($aapt_bin dump badging "$apk" | awk -F"'" '/launchable-activity/{print $2}')
    echo "Installing $apk..."
    adb install -r "$apk"
    adb shell am force-stop "$pkg" 2>/dev/null || true
    echo "Launching $pkg/$activity..."
    adb shell am start -n "$pkg/$activity"
    # Stream logs (unless NO_LOGCAT is set)
    if [ "${NO_LOGCAT:-}" = "1" ]; then
      echo "NO_LOGCAT=1 — skipping log streaming. App launched."
      exit 0
    fi
    pkill -f 'adb.*logcat' 2>/dev/null || true
    app_pid=""
    for i in $(seq 1 10); do
      sleep 1
      app_pid=$(adb shell pidof "$pkg" 2>/dev/null || true)
      if [ -n "$app_pid" ]; then break; fi
      echo "Waiting for app to start... (attempt $i)"
    done
    if [ -n "$app_pid" ]; then
      echo "=== Streaming logs (PID $app_pid, Ctrl+C to stop) ==="
      adb logcat --pid=$app_pid
    else
      echo "Warning: could not find PID for $pkg — falling back to tag filter" >&2
      echo "=== Streaming logs (tag: swift, Ctrl+C to stop) ==="
      adb logcat -s swift
    fi

# ── Test ─────────────────────────────────────────────────────────

# Test example(s) on iOS (default: all examples). Use FILTER=pattern to filter tests.
ios-test *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    targets="{{ targets }}"
    targets="${targets:-{{ examples }}}"
    filter_arg=""
    if [ -n "$FILTER" ]; then
      filter_arg="--filter $FILTER"
    fi
    for ex in $targets; do
      echo "=== Testing $ex (iOS) ==="
      (cd "examples/$ex" && swift test $filter_arg)
    done

# Test example(s) on Android (default: fuse examples)
android-test *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' INT TERM
    targets="{{ targets }}"
    targets="${targets:-{{ fuse_examples }}}"
    for ex in $targets; do
      echo "=== Testing $ex (Android) ==="
      (cd "examples/$ex" && "{{ skip }}" android test)
    done

# ── Clean ────────────────────────────────────────────────────────

# Clean build artifacts for all examples
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    for ex in {{ examples }} {{ showcases }}; do
      if [ -d "examples/$ex" ]; then
        echo "=== Cleaning $ex ==="
        (cd "examples/$ex" && swift package clean && rm -rf .build/plugins/outputs .build/DerivedData)
      fi
    done

# ── Setup & Diagnostics ─────────────────────────────────────────

# First-time setup: initialise all submodules recursively + configure SPM mirrors
init:
    git submodule update --init --recursive
    just setup-mirrors

# Configure SPM mirrors so transitive deps resolve forks/skip locally (eliminates identity warnings)
setup-mirrors:
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(cd "{{ justfile_directory() }}" && pwd)"
    skip_path="file://$root/forks/skip"
    skip_ui_path="file://$root/forks/skip-ui"
    for dir in examples/fuse-app examples/fuse-library examples/skipapp-showcase examples/skipapp-showcase-fuse; do
      if [ -d "$root/$dir" ]; then
        echo "=== Setting SPM mirrors for $dir ==="
        (cd "$root/$dir" && swift package config set-mirror \
          --original "https://source.skip.tools/skip.git" \
          --mirror "$skip_path")
        (cd "$root/$dir" && swift package config set-mirror \
          --original "https://source.skip.tools/skip-ui.git" \
          --mirror "$skip_ui_path")
      fi
    done

# Preflight checks — verify environment is ready to build
doctor:
    #!/usr/bin/env bash
    pass=0; fail=0
    check() {
      if eval "$2" >/dev/null 2>&1; then
        echo "✓ $1"; ((pass++))
      else
        echo "✗ $1 → $3"; ((fail++))
      fi
    }
    check "Swift ≥ 6.2" "swift --version 2>&1 | grep -qE '6\.[2-9]'" \
      "Install Swift 6.2+ from swift.org or update Xcode"
    check "Skip CLI" "skip version" \
      "Install: brew install skiptools/skip/skip"
    check "Xcode" "xcodebuild -version" \
      "Install Xcode from App Store"
    check "JDK ≥ 21" "java --version 2>&1 | head -1 | grep -qE '(2[1-9]|[3-9][0-9])'" \
      "Install: brew install openjdk"
    check "Android SDK" "test -d ${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/platforms || test -d /opt/homebrew/share/android-commandlinetools/platforms" \
      "Run: skip android sdk install"
    check "adb" "adb --version" \
      "Included in Android SDK platform-tools"
    check "Submodules initialised" "test $(git submodule status | grep -c '^-') -eq 0" \
      "Run: just init"
    check "Nested submodule (skipstone/skip)" "test -d forks/skipstone/skip/Sources/SkipDrive" \
      "Run: just init"
    check "SkipDriveExternal symlink" "test -L forks/skipstone/Sources/SkipDriveExternal && test -d forks/skipstone/Sources/SkipDriveExternal" \
      "Symlink broken — run: just init"
    check "Fork branches" "! just check-branches 2>&1 | grep -q 'detached'" \
      "Run: git checkout dev/swift-crossplatform in affected forks"
    check "Upstream purity (skip/skipstone)" "just check-upstream-purity" \
      "skip/skipstone Package.swift diverged from pinned upstream — see .planning/upstream-pins.md"
    check "SPM mirrors (skip identity)" \
      "test -f examples/fuse-app/.swiftpm/configuration/mirrors.json && \
       test -f examples/fuse-library/.swiftpm/configuration/mirrors.json && \
       test -f examples/skipapp-showcase-fuse/.swiftpm/configuration/mirrors.json" \
      "Run: just setup-mirrors"
    echo "---"
    echo "$pass passed, $fail failed"
    test $fail -eq 0

# ── Submodule Management ─────────────────────────────────────────

# Show git status for all submodules
status:
    @git submodule foreach --quiet 'echo "=== $name ===" && git status -sb'

# Show current branch for each direct fork (excludes nested submodules)
check-branches:
    #!/usr/bin/env bash
    for sub in forks/*/; do
      name=$(basename "$sub")
      branch=$(cd "$sub" && git branch --show-current 2>/dev/null)
      if [ -z "$branch" ]; then
        echo "$name: detached HEAD"
      else
        echo "$name: $branch"
      fi
    done

# Verify skip and skipstone Package.swift match pinned upstream commits
check-upstream-purity:
    #!/usr/bin/env bash
    set -euo pipefail
    SKIP_PIN=$(grep 'skip:' .planning/upstream-pins.md | awk '{print $2}')
    SKIPSTONE_PIN=$(grep 'skipstone:' .planning/upstream-pins.md | awk '{print $2}')
    (cd forks/skip && git diff --exit-code "$SKIP_PIN" -- Package.swift)
    (cd forks/skipstone && git diff --exit-code "$SKIPSTONE_PIN" -- Package.swift)

# Push all submodule changes to their remotes
push-all:
    git submodule foreach 'git push origin HEAD'

# Pull latest for each submodule's tracking branch
pull-all:
    git submodule foreach 'git pull origin $(git branch --show-current)'

# Show uncommitted changes across submodules (only shows dirty ones)
diff-all:
    @git submodule foreach --quiet 'changes=$(git diff --stat); if [ -n "$changes" ]; then echo "=== $name ===" && echo "$changes"; fi'

# Show current branch for all submodules (including nested)
branch-all:
    @git submodule foreach --quiet 'echo "$name: $(git branch --show-current)"'

# Run skip verify --fix on all examples
skip-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    for ex in {{ examples }}; do
      echo "=== skip verify $ex ==="
      (cd "examples/$ex" && skip verify --fix)
    done

# Fetch upstream changes for all forks (requires upstream remote configured)
sync-upstream:
    #!/usr/bin/env bash
    set -euo pipefail
    for sub in forks/*/; do
      name=$(basename "$sub")
      echo "=== $name ==="
      if (cd "$sub" && git remote get-url upstream &>/dev/null); then
        (cd "$sub" && git fetch upstream && echo "  Fetched upstream")
      else
        echo "  No upstream remote configured — skipping"
      fi
    done
    echo ""
    echo "Next steps:"
    echo "  1. cd forks/<name> && git merge upstream/main"
    echo "  2. Resolve conflicts (always take upstream for skip/skipstone Package.swift)"
    echo "  3. just check-upstream-purity"
    echo "  4. just ios-test && just android-build fuse-app"
