SHELL := /bin/bash
# ── Configuration ─────────────────────────────────────────────────
EXAMPLES := fuse-library fuse-app
SIMULATOR ?= iPhone 17 Pro
FILTER ?=

# ── Dispatch grammar ──────────────────────────────────────────────
# make [platform] [action…] [target…]
#   platform : ios | android | xc              (default: both)
#   action   : build | test | run | clean      (default: build)
#   target   : example name                    (default: all examples)
#   For xc  : target = <project> [<scheme…>]    (scheme words are joined)
#             xc clean only needs <project>; xc build/run need <project> <scheme>
#
# Examples:
#   make                                       build all, both platforms
#   make clean                                 clean all examples
#
#   Note: clean is platform-agnostic (.build is shared), so
#         'make clean ios' and 'make clean' behave identically.
#   make ios test fuse-library                 test fuse-library on iOS
#   make android build fuse-app                build fuse-app for Android
#   make android test run fuse-app             test + run fuse-app on Android
#   make test run fuse-app                     test + run on both platforms
#   make run fuse-app                          run fuse-app on both platforms
#   make xc build fuse-app FuseApp App         xcodebuild specific scheme
#   make xc run fuse-app FuseApp App           xcodebuild + simulator launch

# ── Dispatch routing ──────────────────────────────────────────────
_DISPATCH_WORDS := ios android xc build test run clean $(EXAMPLES)
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
    ios|android|xc) platform="$$w" ;; \
    build|test|run|clean) actions="$$actions $$w" ;; \
    *) targets="$$targets $$w" ;; \
  esac; \
done; \
actions=$${actions# }; targets=$${targets# }; \
[ -z "$$actions" ] && actions="build"; \
\
if [ "$$platform" = "xc" ]; then \
  proj=$$(echo "$$targets" | awk '{print $$1}'); \
  scheme=$$(echo "$$targets" | awk '{$$1=""; print}' | xargs); \
  [ -z "$$proj" ] && echo "Error: xc requires at least <project>" >&2 && exit 1; \
  ws="examples/$$proj/Project.xcworkspace"; \
  dd="examples/$$proj/.build/DerivedData"; \
  for action in $$actions; do \
    case "$$action" in \
      clean) \
        echo "=== Cleaning $$proj (including DerivedData) ==="; \
        (cd "examples/$$proj" && swift package clean && rm -rf .build/plugins/outputs .build/DerivedData) ;; \
      build) \
        [ -z "$$scheme" ] && echo "Error: xc build requires <project> <scheme>" >&2 && exit 1; \
        echo "=== xcodebuild $$proj / $$scheme ==="; \
        xcodebuild -workspace "$$ws" -scheme "$$scheme" \
          -destination "platform=iOS Simulator,name=$(SIMULATOR)" \
          -derivedDataPath "$$dd" build ;; \
      run) \
        [ -z "$$scheme" ] && echo "Error: xc run requires <project> <scheme>" >&2 && exit 1; \
        echo "=== xcodebuild + launch $$proj / $$scheme ==="; \
        : "xcodebuild uses a different toolchain than swift build / skip android build," ; \
        : "so stale SPM artifacts cause build failures — clean first." ; \
        (cd "examples/$$proj" && swift package clean && rm -rf .build/plugins/outputs); \
        xcodebuild -workspace "$$ws" -scheme "$$scheme" \
          -destination "platform=iOS Simulator,name=$(SIMULATOR)" \
          -derivedDataPath "$$dd" clean build; \
        xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true; \
        open -a Simulator; \
        app=$$(find "$$dd" -path "*/Debug-iphonesimulator/*.app" -maxdepth 6 | head -1); \
        xcrun simctl install booted "$$app"; \
        bid=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$$app/Info.plist"); \
        xcrun simctl launch booted "$$bid" ;; \
      test) \
        echo "Error: use 'ios test' or 'android test' instead of 'xc test'" >&2 && exit 1 ;; \
    esac; \
  done; \
else \
  [ -z "$$targets" ] && targets="$(EXAMPLES)"; \
  [ -z "$$platform" ] && platforms="ios android" || platforms="$$platform"; \
  for action in $$actions; do \
    for ex in $$targets; do \
      case "$$action" in \
        clean) \
          echo "=== Cleaning $$ex ==="; \
          (cd "examples/$$ex" && swift package clean && rm -rf .build/plugins/outputs) ;; \
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
                echo "=== Running $$ex (iOS Simulator) ==="; \
                ws="examples/$$ex/Project.xcworkspace"; \
                if [ ! -d "$$ws" ]; then echo "Error: no xcworkspace for $$ex — use 'xc run' with explicit scheme" >&2 && exit 1; fi; \
                schemes=$$(xcodebuild -workspace "$$ws" -list 2>/dev/null | sed -n '/Schemes:/,/^$$/p' | tail -n +2); \
                scheme=$$(echo "$$schemes" | grep -m1 'App' | xargs); \
                [ -z "$$scheme" ] && scheme=$$(echo "$$schemes" | head -1 | xargs); \
                [ -z "$$scheme" ] && echo "Error: no scheme found for $$ex" >&2 && exit 1; \
                dd="examples/$$ex/.build/DerivedData"; \
                : "xcodebuild uses a different toolchain than swift build / skip android build," ; \
                : "so stale SPM artifacts cause build failures — clean first." ; \
                (cd "examples/$$ex" && swift package clean && rm -rf .build/plugins/outputs); \
                xcodebuild -workspace "$$ws" -scheme "$$scheme" \
                  -destination "platform=iOS Simulator,name=$(SIMULATOR)" \
                  -derivedDataPath "$$dd" clean build; \
                xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true; \
                open -a Simulator; \
                app=$$(find "$$dd" -path "*/Debug-iphonesimulator/*.app" -maxdepth 6 | head -1); \
                xcrun simctl install booted "$$app"; \
                bid=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$$app/Info.plist"); \
                xcrun simctl launch booted "$$bid" ;; \
              android) \
                echo "=== Running $$ex (Android) ==="; \
                (cd "examples/$$ex" && skip android run) ;; \
            esac; \
          done ;; \
      esac; \
    done; \
  done; \
fi
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
