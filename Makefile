SHELL := /bin/bash
# ── Configuration ─────────────────────────────────────────────────
EXAMPLES := fuse-library fuse-app
FILTER ?=

# ── Dispatch grammar ──────────────────────────────────────────────
# make [platform] [action…] [target…]
#   platform : ios | android                   (default: both)
#   action   : build | test | run | clean        (default: build)
#   target   : example name                    (default: all examples)
#
# Examples:
#   make                                       build all, both platforms
#   make clean                                 clean all examples
#
#   Note: clean is platform-agnostic (.build is shared), so
#         'make clean ios' and 'make clean' behave identically.
#   make ios test fuse-library                 test fuse-library on iOS
#   make android build fuse-app                build fuse-app for Android
#   make ios test fuse-library FILTER=Obs      filtered iOS test
#   make android run fuse-app                  export APK, install, launch
#
# Run:
#   android: skip export → adb install → launch → logcat (Ctrl+C to stop)
#            skips export if APK is up to date (timestamps Sources/ + forks/)
#   ios:     use Xcode (Cmd+R) — prints guidance instead
#
# To run from Xcode, set SKIP_ACTION in .xcconfig:
#   launch (default) = build + run both platforms
#   build  = build Android but don't launch
#   none   = skip Android entirely for faster iteration

# ── Dispatch routing ──────────────────────────────────────────────
_DISPATCH_WORDS := ios android build test run clean $(EXAMPLES)
_FIRST := $(firstword $(MAKECMDGOALS))

ifneq ($(filter $(_FIRST),$(_DISPATCH_WORDS)),)

.PHONY: _do_dispatch $(MAKECMDGOALS)
_do_dispatch:
	@$(_dispatch)
$(_FIRST): _do_dispatch ;
ifneq ($(word 2,$(MAKECMDGOALS)),)
$(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS)): ;
endif

endif # dispatch guard

# ── Default goal (bare `make`) ────────────────────────────────────
.DEFAULT_GOAL := _default
.PHONY: _default
_default:
	@$(MAKE) --no-print-directory build

# ── Dispatch implementation ───────────────────────────────────────
define _dispatch
set -e; \
platform=""; actions=""; targets=""; \
for w in $(MAKECMDGOALS); do \
  case "$$w" in \
    ios|android) platform="$$w" ;; \
    build|test|run|clean) actions="$$actions $$w" ;; \
    *) targets="$$targets $$w" ;; \
  esac; \
done; \
actions=$${actions# }; targets=$${targets# }; \
[ -z "$$actions" ] && actions="build"; \
\
[ -z "$$targets" ] && targets="$(EXAMPLES)"; \
[ -z "$$platform" ] && platforms="ios android" || platforms="$$platform"; \
for action in $$actions; do \
  for ex in $$targets; do \
    case "$$action" in \
      clean) \
        echo "=== Cleaning $$ex ==="; \
        (cd "examples/$$ex" && swift package clean; rm -rf .build/plugins/outputs .build/DerivedData) ;; \
      build) \
        for p in $$platforms; do \
          case "$$p" in \
            ios) echo "=== Building $$ex (iOS) ===" && (cd "examples/$$ex" && swift build) ;; \
            android) echo "=== Building $$ex (Android) ===" && (cd "examples/$$ex" && skip android build) ;; \
          esac; \
        done ;; \
      test) \
        for p in $$platforms; do \
          case "$$p" in \
            ios) echo "=== Testing $$ex (iOS) ===" && (cd "examples/$$ex" && swift test $(if $(FILTER),--filter $(FILTER))) ;; \
            android) echo "=== Testing $$ex (Android) ===" && (cd "examples/$$ex" && skip android test) ;; \
          esac; \
        done ;; \
      run) \
        for p in $$platforms; do \
          case "$$p" in \
            ios) \
              echo "=== Running $$ex (iOS) ==="; \
              echo "Use Xcode to run iOS apps (Cmd+R), or:"; \
              echo "  open examples/$$ex" ;; \
            android) \
              echo "=== Running $$ex (Android) ==="; \
              if ! adb devices 2>/dev/null | grep -q 'emulator.*device$$'; then \
                echo "No emulator running — launching one..."; \
                skip android emulator launch & \
                adb wait-for-device; \
              fi; \
              export_dir="examples/$$ex/.build/export"; \
              apk=$$(ls "$$export_dir"/*-debug.apk 2>/dev/null | head -1); \
              if [ -z "$$apk" ] || [ -n "$$(find "examples/$$ex/Sources" "examples/$$ex/Package.swift" forks/ -newer "$$apk" -name '*.swift' -print -quit 2>/dev/null)" ]; then \
                echo "Source changed — rebuilding APK..."; \
                rm -rf "$$export_dir"; \
                (cd "examples/$$ex" && skip export --debug --android --no-ios -d .build/export) || true; \
                apk=$$(ls "$$export_dir"/*-debug.apk 2>/dev/null | head -1); \
                if [ -z "$$apk" ]; then echo "Error: no APK found in $$export_dir" >&2; exit 1; fi; \
              else \
                echo "APK up to date — skipping export"; \
              fi && \
              aapt_bin=$$(ls -d "$$HOME/Library/Android/sdk/build-tools"/*/ 2>/dev/null | sort -V | tail -1)aapt && \
              if [ ! -x "$$aapt_bin" ]; then echo "Error: aapt not found — install Android SDK build-tools" >&2; exit 1; fi && \
              pkg=$$($$aapt_bin dump badging "$$apk" | awk -F"'" '/^package:/{print $$2}') && \
              activity=$$($$aapt_bin dump badging "$$apk" | awk -F"'" '/launchable-activity/{print $$2}') && \
              echo "Installing $$apk..." && adb install -r "$$apk" && \
              adb shell am force-stop "$$pkg" 2>/dev/null; \
              echo "Launching $$pkg/$$activity..." && adb shell am start -n "$$pkg/$$activity" && \
              pkill -f 'adb.*logcat' 2>/dev/null; \
              echo "=== Streaming logs (Ctrl+C to stop) ===" && (trap 'exit 0' INT TERM; adb logcat -s swift) ;; \
          esac; \
        done ;; \
    esac; \
  done; \
done
endef

# ── Standalone targets ────────────────────────────────────────────
.PHONY: skip-verify status push-all pull-all diff-all branch-all

skip-verify:
	@for ex in $(EXAMPLES); do \
		echo "=== skip verify $$ex ===" && \
		(cd examples/$$ex && skip verify --fix) || exit 1; \
	done

status:
	@git submodule foreach --quiet 'echo "=== $$name ===" && git status -sb'

push-all:
	@git submodule foreach 'git push origin HEAD'

pull-all:
	@git submodule foreach 'git pull origin $$(git branch --show-current)'

diff-all:
	@git submodule foreach --quiet 'changes=$$(git diff --stat); if [ -n "$$changes" ]; then echo "=== $$name ===" && echo "$$changes"; fi'

branch-all:
	@git submodule foreach --quiet 'echo "$$name: $$(git branch --show-current)"'
