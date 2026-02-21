EXAMPLE ?= fuse-library
EXAMPLE_DIR := examples/$(EXAMPLE)

.PHONY: build test android-build android-test skip-test skip-verify status push-all pull-all diff-all branch-all

# Build & Test (run against an example project, default: fuse-library)
build:
	cd $(EXAMPLE_DIR) && swift build

test:
	cd $(EXAMPLE_DIR) && swift test

test-filter:
	@test -n "$(FILTER)" || (echo "Usage: make test-filter FILTER=ObservationTests" && exit 1)
	cd $(EXAMPLE_DIR) && swift test --filter $(FILTER)

android-build:
	cd $(EXAMPLE_DIR) && skip android build

skip-test:
	cd $(EXAMPLE_DIR) && skip test

skip-verify:
	cd $(EXAMPLE_DIR) && skip verify --fix

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
