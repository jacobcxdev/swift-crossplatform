EXAMPLES ?= fuse-library fuse-app

ifdef EXAMPLE
# Single example override: EXAMPLE=fuse-app make build
TARGETS := $(EXAMPLE)
else
TARGETS := $(EXAMPLES)
endif

.PHONY: build test test-filter darwin-build darwin-test android-build android-test skip-verify clean status push-all pull-all diff-all branch-all

# Cross-platform build & test (Darwin + Android)
build: darwin-build android-build

test: darwin-test android-test

# Darwin-only
darwin-build:
	@for ex in $(TARGETS); do \
		echo "=== Building $$ex (Darwin) ===" && \
		cd examples/$$ex && swift build && cd ../.. || exit 1; \
	done

darwin-test:
	@for ex in $(TARGETS); do \
		echo "=== Testing $$ex (Darwin) ===" && \
		cd examples/$$ex && swift test && cd ../.. || exit 1; \
	done

test-filter:
	@test -n "$(FILTER)" || (echo "Usage: make test-filter FILTER=ObservationTests" && exit 1)
	cd examples/$(firstword $(TARGETS)) && swift test --filter $(FILTER)

# Android-only
android-build:
	@for ex in $(TARGETS); do \
		echo "=== Building $$ex (Android) ===" && \
		cd examples/$$ex && skip android build && cd ../.. || exit 1; \
	done

android-test:
	@for ex in $(TARGETS); do \
		echo "=== Testing $$ex (Android) ===" && \
		cd examples/$$ex && skip android test && cd ../.. || exit 1; \
	done

skip-verify:
	@for ex in $(TARGETS); do \
		echo "=== Skip verifying $$ex ===" && \
		cd examples/$$ex && skip verify --fix && cd ../.. || exit 1; \
	done

clean:
	@for ex in $(TARGETS); do \
		echo "=== Cleaning $$ex ===" && \
		cd examples/$$ex && swift package clean && rm -rf .build/plugins/outputs && cd ../.. || exit 1; \
	done

# Submodule management
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
