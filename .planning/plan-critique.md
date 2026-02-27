# Plan: Comprehensive Local Development Setup Alignment

## Context & Problem Statement

The swift-crossplatform monorepo manages 25 git submodule forks (Point-Free libraries + Skip framework libraries + Skip tools) in `forks/`, with example apps in `examples/`. A `justfile` (replacing the old Makefile) provides CLI orchestration via [Just](https://github.com/casey/just).

**The build is currently broken** because previous Claude sessions modified Package.swift files and injected build flags without reading upstream documentation. The setup has become unwieldy, requiring constant patches.

**Goal:** Produce a robust, easy-to-use, well-organised codebase optimised for:
1. **Local development** — `just clean && just android-run fuse-app` just works
2. **Upstreamability** — fork changes are minimal, well-gated, easy to PR back
3. **Agentic development** — zero-context AI agents can orient and build immediately

**User decisions (confirmed):**
- Lite examples: KEEP and maintain
- Showcase apps: ADD as submodules (skipapp-showcase + skipapp-showcase-fuse)
- Debug flags (FUSE_NAV_DEBUG, FUSE_TAB_DEBUG): KEEP in Package.swift
- Plan phasing: ONE comprehensive pass

---

## Executor Principles

These instructions MUST be followed by whoever executes this plan:

1. **Do NOT modify Package.swift in skip or skipstone.** These must be byte-identical to upstream. If something doesn't build, the fix is in the build invocation or environment, not in Package.swift.
2. **Do NOT add flags, scripts, or workarounds not documented upstream.** If upstream contributors don't need it, neither do we. Research the upstream docs before hacking.
3. **Preserve intentional code changes.** The transpiler fix in skipstone (compose view identity gap), Android gating in Point-Free forks, debug logging — these are feature work, not workarounds.
4. **Important uncommitted changes exist.** Only reset files classified as WORKAROUND. Never do blanket `git checkout .` or `git reset`.
5. **If a build fails, investigate the root cause** by reading upstream docs, checking the environment, and testing minimal reproductions. Do NOT inject `--disable-experimental-prebuilts` or other flags.
6. **Every step must be verified** before moving to the next. Each step has an acceptance test.
7. **Research before acting.** If you hit a wall, read the upstream README/contributing docs. Use `skip doctor`, check GitHub issues.
8. **Use the task list to track progress.** Each phase has a corresponding task (tasks #39-#48). Before starting a phase, call `TaskGet` to read the full task description. Call `TaskUpdate` with `status: "in_progress"` when starting a phase. Call `TaskUpdate` with `status: "completed"` ONLY when ALL acceptance tests for that phase pass. If blocked, keep the task as `in_progress` and document the blocker. Tasks have dependency chains — do not start a task whose `blockedBy` list contains incomplete tasks.

---

## Research Cache

### R1: Upstream Documentation (COMPLETE)

**skipstone README** (https://raw.githubusercontent.com/skiptools/skipstone/refs/heads/main/README.md):
- skipstone vends the `skip` tool (names are reversed from what you'd expect)
- Local development: "The key is that the current working directory for Xcode must be the skipstone folder"
- `./scripts/skip` builds and runs the Skip CLI from source — runs `swift run SkipRunner` with `SKIP_COMMAND_OVERRIDE` env var
- skipstone has skip as a nested submodule for `SkipDriveExternal` symlink (shared SkipDrive code)
- Verification: asterisk after version number (`Skip 1.7.2*`) indicates local build
- Testing: `swift test` from Terminal

**skip README** (https://raw.githubusercontent.com/skiptools/skip/refs/heads/main/README.md):
- skip is the package which Skip projects directly depend on
- Works hand-in-hand with skipstone binary distribution
- Install: `brew install skiptools/skip/skip`

**Contributing guide** (https://skip.dev/docs/contributing/):
- Clone repos as peers, create Xcode workspace, add local packages to override distributed versions
- SkipUI/SkipFuseUI changes need testing against BOTH skipapp-showcase AND skipapp-showcase-fuse
- Fork all four repos, create workspace, verify both showcase apps build and run
- CI may fail on non-SkipUI packages because they build against release tags

### R2: Upstream Package.swift Files (COMPLETE)

**Upstream skip/Package.swift** (38 lines):
```swift
// Lines 29-38: SKIPLOCAL conditional
let env = Context.environment
if (env["SKIPLOCAL"] != nil || env["PWD"]?.hasSuffix("skipstone") == true) {
    package.dependencies += [.package(path: env["SKIPLOCAL"] ?? "../skipstone")]
    package.targets += [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
} else {
    #if os(macOS)
    package.targets += [.binaryTarget(name: "skip", url: "https://source.skip.tools/skip/releases/download/1.7.2/skip-macos.zip", checksum: "...")]
    #elseif os(Linux)
    package.targets += [.binaryTarget(name: "skip", url: "https://source.skip.tools/skip/releases/download/1.7.2/skip-linux.zip", checksum: "...")]
    #else
    package.dependencies += [.package(url: "https://source.skip.tools/skipstone.git", exact: "1.7.2")]
    package.targets += [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
    #endif
}
```

**Key insight:** Without SKIPLOCAL, skip downloads pre-built binary — skipstone/swift-syntax NOT in build graph — no prebuilts conflict. With SKIPLOCAL, skipstone is source-built — swift-syntax enters graph — prebuilts MAY conflict.

**Upstream skipstone/Package.swift** (50 lines):
- platforms: `[.macOS(.v13)]` — macOS ONLY (no .iOS)
- Dependencies: swift-syntax 602.0.0+, swift-tools-support-core, swift-argument-parser, universal, ELFKit
- `SkipDriveExternal` target is symlink to `../../skip/Sources/SkipDrive` (nested submodule)

### R3: Current Fork State (COMPLETE)

**Our forks/skip/Package.swift** — WORKAROUND: Lines 30-32 hardcode `path: "../skipstone"`, replacing SKIPLOCAL conditional.
**Our forks/skipstone/Package.swift** — WORKAROUND: Added `.iOS(.v13)` to platforms.
**Our forks/skipstone/ExportCommand.swift** — WORKAROUND: Added `--disable-experimental-prebuilts` to 3 swift commands.

### R4: Fork Audit (COMPLETE)

**17 forks with uncommitted changes.** Classification:

| Fork | Category | Modified Files | Classification |
|------|----------|---------------|----------------|
| **skip** | skiptools-tool | Package.swift | WORKAROUND — hardcoded local skipstone path (revert) |
| **skipstone** | skiptools-tool | Package.swift, ExportCommand.swift, 4 transpiler files | MIXED — Package.swift + ExportCommand = WORKAROUND (revert); transpiler files = INTENTIONAL (keep) |
| **skip-android-bridge** | skiptools-lib | Package.swift, Observation.swift | NEEDS INVESTIGATION — Package.swift has `path: "../skip"` instead of remote URL; Observation.swift = INTENTIONAL (nav debug) |
| **skip-fuse-ui** | skiptools-lib | Package.swift, 3 source files | NEEDS INVESTIGATION — Package.swift has local paths; source files = INTENTIONAL (UI fixes) |
| **skip-ui** | skiptools-lib | 4 source files (NO Package.swift change) | INTENTIONAL — UI improvements, TabView debug |
| **swift-composable-architecture** | pointfreeco | Package.swift, Package.resolved, Package@swift-6.0.swift, 4 source files | MIXED — Package.swift has local paths + removed macro tests; source files = INTENTIONAL |
| **swift-perception** | pointfreeco | Package.swift, PerceptionRegistrar.swift | INTENTIONAL — Android bridge integration |
| **swift-navigation** | pointfreeco | Package.resolved, Package@swift-6.0.swift, ButtonState.swift, TextState.swift | INTENTIONAL — TextState/ButtonState feature work |
| **swift-structured-queries** | pointfreeco | Package.swift, Package@swift-6.0.swift | INTENTIONAL — Android gating for test infra |
| **sqlite-data** | pointfreeco | Package.resolved, Package.swift, Package@swift-6.0.swift | INTENTIONAL — Android gating for test infra |
| **swift-macro-testing** | pointfreeco | Package@swift-5.9.swift | WORKAROUND — local path for swift-snapshot-testing |
| **GRDB.swift** | other | Tests/CustomSQLite/GRDB | INTENTIONAL — removed recursive symlink |
| **combine-schedulers** | pointfreeco | Package.resolved, 2 Package@ files | WORKAROUND — lockfile/version cleanup |
| **swift-case-paths** | pointfreeco | Package@swift-6.0.swift | WORKAROUND — version update |
| **swift-clocks** | pointfreeco | Package.resolved, Package@swift-6.0.swift | WORKAROUND — lockfile cleanup |
| **swift-dependencies** | pointfreeco | Package.resolved, Package@swift-5.9.swift | WORKAROUND — lockfile cleanup |
| **swift-sharing** | pointfreeco | Package.resolved, Package@swift-6.0.swift | WORKAROUND — lockfile cleanup |

### R5: skipstone scripts/skip (COMPLETE)

```bash
#!/bin/bash
SKIPDIR=$(dirname $(dirname $(realpath $0)))
export SKIP_COMMAND_OVERRIDE=${SKIPDIR}/.build/debug/SkipRunner
swift run --package-path ${SKIPDIR} SkipRunner "${@}"
```

Builds SkipRunner from source, sets `SKIP_COMMAND_OVERRIDE` so the SPM build plugin uses local binary.

### R6: Nested Submodule (COMPLETE)

- `forks/skipstone/.gitmodules` has `skip` submodule pointing to upstream `https://github.com/skiptools/skip.git` (branch: main)
- `forks/skipstone/skip/` is currently EMPTY (not initialised)
- `forks/skipstone/Sources/SkipDriveExternal` is a symlink to `../skip/Sources/SkipDrive` — resolves to the nested submodule
- **Must run `git submodule update --init --recursive` to populate**
- Nested skip uses UPSTREAM (not our fork) — fine because SkipDriveExternal only needs unmodified SkipDrive source

### R7: Example Dependency Structure (COMPLETE)

**fuse-app** — 6 local path deps: skip, skip-fuse-ui, skip-android-bridge, skip-ui, swift-composable-architecture, sqlite-data
**fuse-library** — 18 local path deps: comprehensive Point-Free + Skip library coverage
**lite-app** — 2 REMOTE deps: skip (source.skip.tools), skip-ui (source.skip.tools)
**lite-library** — 2 REMOTE deps: skip (source.skip.tools), skip-foundation (source.skip.tools)

**Key finding:** Lite examples use upstream remote URLs, not forks. Fuse examples use local paths to forks. This is correct and intentional.

### R8: skip-android-bridge/skip-fuse-ui Package.swift Investigation (COMPLETE)

**skip-android-bridge/Package.swift:** Has `.package(path: "../skip")` — this is a LOCAL path to sibling `forks/skip`. Upstream would be a remote URL.

**skip-fuse-ui/Package.swift:** Has local paths to `../skip`, `../skip-fuse`, `../skip-android-bridge`, `../skip-ui`. Upstream would use remote URLs for at least some of these.

**CRITICAL QUESTION:** Are these local paths intentional fork changes or AI-session workarounds?

**Answer:** These are INTENTIONAL. skip-android-bridge and skip-fuse-ui are OUR forks (jacobcxdev). Their upstream versions reference `source.skip.tools` URLs. Our forks replace these with local paths so that when building from within the monorepo, SPM resolves to our other forks. This is the standard pattern for the pointfreeco forks too (TCA references `../swift-navigation`, `../swift-perception`, etc. as local paths).

**However:** SPM local path override from the root package SHOULD handle this. If fuse-app has `.package(path: "../../forks/skip")`, any transitive dep on `skip` (by name) should resolve to the local version. So the local paths in fork Package.swift files may be REDUNDANT.

**Research needed:** Test whether SPM local path override works for transitive deps when the root package specifies a local path but the dependency uses a remote URL for the same package name.

### R9: swift-composable-architecture Package.swift Analysis (COMPLETE)

The TCA fork has:
1. Local paths for all Point-Free deps (`../combine-schedulers`, `../swift-case-paths`, etc.) — INTENTIONAL for monorepo resolution
2. Android-conditional deps (skip-bridge, skip-android-bridge, swift-jni, skip-fuse-ui) — INTENTIONAL
3. **Removed `swift-macro-testing` dependency and `ComposableArchitectureMacrosTests` target** — WORKAROUND (reduces test coverage, needs investigation)
4. Source file changes (Animation.swift, NavigationStack+Observation.swift, Store.swift, IfLetStore.swift, NavigationStackStore.swift) — INTENTIONAL (Android compatibility)

### R10: Makefile vs Alternatives (COMPLETE — codex-cli evaluated)

**Current Makefile:** 170 lines, dispatch grammar `make [platform] [action] [target]`, shell define block.

**Codex-cli recommendation: Adopt `just` (casey/just) as primary orchestrator.**

Reasoning:
- **Maintenance burden:** Lower than Make. justfile syntax is simpler, less magic, avoids Make-specific escaping/indirection pain.
- **Discoverability:** Excellent out of the box (`just --list`, recipe docs, defaults). New devs and AI agents can self-serve quickly.
- **Error messages:** Materially better than Make's generic target failures; easier to pinpoint which recipe/line failed.
- **Upstream alignment:** Still uses standard underlying tools (swift, xcodebuild, gradle). `just` is orchestration only.
- **Cross-platform:** Strong on macOS + Linux CI.
- **Agentic friendliness:** Highest of the options. Zero-context agent can run `just --list` and infer structure fast.

**Why not others:** Improve Make = keeps core complexity. Shell wrapper = re-implements features just already has. Swift CLI = bootstrap overhead not worth it.

**DECISION: Adopt Just as primary orchestrator (per Codex recommendation and user confirmation).**

Install: `brew install just`. Justfile replaces Makefile entirely (no shim — Make's `%:` cannot preserve multi-goal dispatch). Benefits: simpler syntax, better error messages, self-documenting (`just --list`), no Make escaping pain, excellent agentic friendliness.

### R11: Git Submodules vs Alternatives (COMPLETE — codex-cli evaluated)

**Codex-cli recommendation: Keep git submodules with strong guardrails.**

| Approach | Atomic versioning | Upstream PR | External app | CI/CD | Dev ergonomics | AI friendliness |
|----------|-------------------|-------------|-------------|-------|----------------|-----------------|
| Submodules + tooling | High | High | Med-High | High | Medium | Med-High |
| Workspace overrides | Low | Medium | Low | Low | Medium | Low |
| Vendored source | High | Low | Medium | High | Med-High | High |
| Hybrid | Medium | Medium | Med-Low | Medium | Low | Low |

**Why submodules win:** Atomic snapshots via SHAs. Separate fork repos preserve history for PRs. Real fork deltas (#if os(Android), SKIP_BRIDGE) need history. External app consumption solvable via pinned revisions/tags.

**Recommended tooling additions:**
1. `just init` — `git submodule update --init --recursive`
2. `just status` — dirty/detached/ahead checks
3. `just check-branches` — verify all on `dev/swift-crossplatform`
4. `just sync-upstream` — fast-forward to upstream, rewrite lock
5. Tag monorepo releases as fork-set snapshots (e.g., `forkset-2026-02-26.1`)
6. External app: consume fork repos at pinned revisions/tags, not moving branches

### R12: External App Consumption (PARTIALLY COMPLETE)

Future private app (different GitHub org) uses TCA on Skip, requiring these forks.

**Recommended approach (from codex-cli R11):**
- **CI/release:** SPM deps pointing to fork repos at pinned revision/tag (e.g., `revision: "abc123"` or `branch: "dev/swift-crossplatform"`)
- **Local development:** SPM local path overrides. The private app's Package.swift has remote deps, but the developer uses an Xcode workspace with local checkouts of the forks to override.
- **Alternative:** The private app clones swift-crossplatform as a sibling and uses local paths during dev, switching to remote for CI.

**External app Package.swift pattern:**
```swift
// In the private app's Package.swift — CI/release mode:
.package(url: "https://github.com/jacobcxdev/swift-composable-architecture.git", branch: "dev/swift-crossplatform"),
// For local dev: create an Xcode workspace containing both the private app project
// and the swift-crossplatform repo. SPM will automatically use local checkouts
// when both are in the same workspace, or use .package(path: "../swift-crossplatform/forks/...") overrides.
```

### R13: Showcase Apps (COMPLETE)

**Repos found:**
- `skiptools/skipapp-showcase` (Lite mode) — public, v1.12.3, 33 stars. Uses plain `@Observable`, NOT TCA. Fundamentally incompatible with TCA per CLAUDE.md ("Lite mode's counter-based observation is fundamentally incompatible with TCA").
- `skiptools/skipapp-showcase-fuse` (Fuse mode) — public, on App Store + Play Store. Uses SkipFuseUI, TCA-compatible.

**Decision: ADD as submodules (user confirmed).**
Despite the Lite showcase being incompatible with TCA, both are useful for verifying skip-ui/skip-fuse-ui fork changes don't break upstream apps. See Phase 6 for implementation steps.

**Integration approach:**
1. Fork both to jacobcxdev, create `dev/swift-crossplatform` branch
2. Add as submodules: `git submodule add -b dev/swift-crossplatform https://github.com/jacobcxdev/skipapp-showcase.git examples/skipapp-showcase`
3. Modify their Package.swift to use local fork paths (same pattern as fuse-app)
4. Add to justfile as `showcases` variable with `just showcase` convenience recipe

### R14: SPM Local Path Override for Transitive Deps (COMPLETE)

**Question:** If fuse-app has `.package(path: "../../forks/skip")` and skip-ui has `.package(url: "https://source.skip.tools/skip.git", from: "1.6.21")`, does SPM unify these?

**Answer: YES.** SPM unifies by package identity (the `name:` field in Package.swift). Evidence:
- Package.resolved in fuse-app shows a single entry for "skip" identity resolved to one source
- Root package's local path declaration takes precedence for all transitive deps with the same identity
- skip-android-bridge's `path: "../skip"` and skip-ui's remote URL both resolve to the same package

**Implication:** Local path changes in fork Package.swift files (e.g., skip-android-bridge using `path: "../skip"`) are **REDUNDANT for resolution** when building from the root example. However, they serve important purposes:
1. **Standalone buildability** — forks can be built/tested in isolation without the root package
2. **Explicit documentation** — makes dependency intent clear to developers
3. **Defensive protection** — prevents accidental upstream URL drift

**Classification: INTENTIONAL (keep).** The local paths in fork Package.swift files are not workarounds — they're defensive development practice enabling standalone fork work.

### R15: --disable-experimental-prebuilts Investigation (COMPLETE — REQUIRES EMPIRICAL VERIFICATION)

**Hypothesis:** Without SKIPLOCAL, skip downloads binary target → skipstone/swift-syntax NOT in build graph → flag unnecessary.

**Analysis from R27 (skip export):** ExportCommand.swift currently passes `--disable-experimental-prebuilts` to ALL swift build/resolve invocations (lines 129, 133, 136). This was injected as a workaround by a previous Claude session.

**Key insight:** The flag is ONLY needed when swift-syntax is in the build graph (via source-built skipstone). Two scenarios:
1. **Without SKIPLOCAL** (normal): skip downloads binary → no swift-syntax → flag unnecessary ✅
2. **With SKIPLOCAL** (local dev on skipstone): skipstone brings swift-syntax → flag MAY be needed ⚠️

**However:** Our Makefile doesn't currently use SKIPLOCAL. Examples use the binary skip. Only skipstone development (building skipstone itself) pulls in swift-syntax. Since skipstone is built separately via `scripts/skip`, the swift-syntax conflict shouldn't affect example builds.

**Verification step (Phase 4.1):** Build `examples/fuse-app` with plain `swift build` (no flags) after restoring upstream Package.swift files. If it succeeds, the flag is confirmed unnecessary for normal development. If it fails, investigate whether SKIPLOCAL is leaking into the environment.

### R16: Toolchain Versions (COMPLETE)

| Tool | Version | Notes |
|------|---------|-------|
| Swift | 6.2.3 (swiftlang-6.2.3.3.21) | Apple Swift via Xcode |
| Xcode | 26.2 (Build 17C52) | |
| Skip CLI | 1.7.2 | Homebrew install |
| JDK | OpenJDK 25.0.2 (2026-01-20) | |
| adb | 1.0.41 | Android Debug Bridge |
| Android SDK | android-36 | Platform API level |
| Kotlin | Check via Gradle | Not directly installed; bundled with Gradle |

### R17: Agentic Development Optimisation (COMPLETE)

**Goal:** A zero-context AI agent can clone the repo, read CLAUDE.md, and successfully build/test without prior knowledge.

**CLAUDE.md improvements:**
1. **Bootstrap section** (top of file): `git clone → just init → just doctor → just ios-build` — 4 commands to working build
2. **Architecture overview**: One paragraph + dependency graph (already exists, refine)
3. **Fork inventory table**: Name | Category | Has changes | Change type — reference Appendix A
4. **Common tasks section**: "How do I…" format for build, test, run, add a fork, upstream sync
5. **Troubleshooting**: Top 5 error messages with fixes

**Self-documenting `just --list`:**
```
just                    # List all recipes with descriptions
just ios-build          # Build all examples for iOS
just doctor             # Check prerequisites (Swift, Skip, Android SDK, JDK, emulator)
just init               # git submodule update --init --recursive
just ios-test X         # Test example X on iOS
just android-run X      # Full Android pipeline (export → install → launch → logcat)
```

**Zero-context agent test (Phase 10.3):** Give codex-cli ONLY CLAUDE.md and ask:
- "How do I build fuse-app for Android?" → expects: `just android-build fuse-app`
- "What forks are modified and why?" → expects: fork inventory answer
- "How do I run tests?" → expects: `just ios-test fuse-library`

### R18: Upstream Sync Workflow (COMPLETE)

**Cadence:** On upstream release (not time-based). Monitor via GitHub watch/RSS on key repos: skip, skipstone, swift-composable-architecture.

**Process per fork:**
```bash
cd forks/<name>
git fetch upstream
git rebase upstream/main   # or upstream/release-tag
# Resolve conflicts (Package.swift local paths are the common conflict point)
# Run: just ios-test <relevant-example> && just android-build <relevant-example>
git push origin dev/swift-crossplatform
cd ../..
git add forks/<name>
git commit -m "sync(<name>): rebase onto upstream <version>"
```

**Conflict hotspots:** Package.swift files (local paths vs upstream remote URLs), Package.resolved (auto-resolves on rebuild). Source files with `#if os(Android)` gates rarely conflict since they're additive.

**Testing after sync:** `just ios-test` for all examples. If android-specific changes, also `just android-build`.

**Justfile recipe:**
```just
sync-upstream:
    # Fetch from upstream remote for each fork (upstream remote must be configured)
    for sub in forks/*/; do (cd "$sub" && echo "=== $(basename $sub) ===" && git fetch upstream); done
```

**Guardrail:** After sync, run `just check-upstream-purity` to verify skip/skipstone remain byte-identical to upstream.

### R19: Doctor Command Design (COMPLETE)

**`just doctor` checks (in order):**

| # | Check | Command | Pass criteria |
|---|-------|---------|---------------|
| 1 | Swift version | `swift --version` | ≥ 6.2 |
| 2 | Skip CLI | `skip version` | Installed, version ≥ 1.7 |
| 3 | Xcode | `xcodebuild -version` | Installed |
| 4 | JDK | `java --version` | ≥ 21 |
| 5 | Android SDK | `$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --version` | Exists |
| 6 | adb | `adb --version` | Installed |
| 7 | Submodules init | `git submodule status \| grep -c '^-'` | 0 (none uninitialised) |
| 8 | Nested submodule | `test -d forks/skipstone/skip/Sources/SkipDrive` | Directory exists |
| 9 | SkipDriveExternal symlink | `test -L forks/skipstone/Sources/SkipDriveExternal` | Symlink resolves |
| 10 | Branch check | `for sub in forks/*/; do ...` | All direct forks on `dev/swift-crossplatform` (excludes nested submodules like `skipstone/skip`) |
| 11 | Upstream purity | `just check-upstream-purity` | skip AND skipstone Package.swift match pinned upstream commit SHAs from `.planning/upstream-pins.md` (catches both uncommitted AND committed drift) |

**Output format:** Green ✓ / Red ✗ with actionable fix message for each failure. Example:
```
✓ Swift 6.2.3
✓ Skip CLI 1.7.2
✗ Nested submodule not initialised → run: git submodule update --init --recursive
✓ All submodules on dev/swift-crossplatform
```

### R27: skip export vs swift build Package Resolution (COMPLETE)

**Finding:** `skip export` and `swift build` use the SAME SPM dependency resolution (same `swift build`/`swift package resolve` calls with `--package-path`). Differences emerge post-resolution:
- ExportCommand builds for iOS first (plain swift build), then invokes Gradle for Android separately
- AndroidCommand sets `TARGET_OS_ANDROID=1`, `SKIP_BRIDGE=1` as compiler defines — affects `#if os(Android)` gates
- ExportCommand currently injects `--disable-experimental-prebuilts` at lines 129, 133, 136 (WORKAROUND to revert)
- No temporary Package.swift files are created; uses project's existing manifest

**Implication:** If `swift build` works without `--disable-experimental-prebuilts`, `skip export` will too (after reverting the injected flag in ExportCommand.swift).

### R28: swift-syntax Version Conflicts (COMPLETE)

**Current state: NO active conflicts.** All examples resolve to swift-syntax 602.0.0.

| Source | Version requirement |
|--------|-------------------|
| skipstone | `from: "602.0.0"` (unbounded) |
| Point-Free forks (TCA, case-paths, perception, dependencies, snapshot-testing, macro-testing) | `"509.0.0"..<"603.0.0"` |
| swift-structured-queries | `"600.0.0"..<"603.0.0"` |

**Key insight:** skipstone's unbounded `from: "602.0.0"` is only in the build graph when building skipstone from source (SKIPLOCAL). Normal builds download a binary skip — no swift-syntax in graph at all.

**Future risk:** When Swift 6.3 ships, swift-syntax 603+ will be available. Point-Free forks cap at `<"603.0.0"`, which will need updating. This is an upstream Point-Free concern, not ours to fix preemptively.

### R29: SKIP_ACTION xcconfig Interaction with Makefile (COMPLETE)

**Finding: No conflict.** SKIP_ACTION is Xcode-only — it controls the Run Script build phase in Xcode. The Makefile bypasses Xcode entirely, using `skip export` / `skip android build` / `adb` directly. They are independent pipelines:
- `SKIP_ACTION=launch` → Xcode builds + runs Android during Cmd+R
- `SKIP_ACTION=none` → Xcode skips Android entirely (faster iOS iteration)
- `make android run` → CLI pipeline, ignores SKIP_ACTION completely

**Documentation needed:** CLAUDE.md should clarify this distinction for developers who use both Xcode and CLI.

### R30: Skip.env Files (COMPLETE)

**Purpose:** Central configuration manifest synchronising app metadata across iOS (xcconfig/Info.plist) and Android (Gradle/AndroidManifest.xml). Properties: PRODUCT_NAME, PRODUCT_BUNDLE_IDENTIFIER, MARKETING_VERSION, CURRENT_PROJECT_VERSION, ANDROID_PACKAGE_NAME.

**Locations:** `examples/fuse-app/Skip.env`, `examples/lite-app/Skip.env`

**Integration:** skipstone parses Skip.env at project init, generates Gradle scripts that load it via `Dotenv.load('../../Skip.env')`, and xcconfig files include it via `#include "../Skip.env"`.

**For the plan:** Skip.env files are standard upstream configuration. Do NOT modify them as part of this plan. Document their purpose in CLAUDE.md.

### R31: Package@swift-*.swift Audit (COMPLETE)

**16 files found across forks. All committed, no drift.**

| Classification | Count | Files |
|---------------|-------|-------|
| INTENTIONAL (Android-gated) | 3 | swift-composable-architecture, swift-navigation, sqlite-data (all @swift-6.0) |
| INTENTIONAL (platform condition) | 2 | combine-schedulers (@swift-5.9 + @swift-6.0) — OpenCombineShim for linux/android |
| UNCHANGED | 11 | Standard Point-Free layouts, no Android-specific changes |

**Pattern:** INTENTIONAL files use `let android = Context.environment["TARGET_OS_ANDROID"] ?? "0" != "0"` then conditional dep arrays `+ (android ? [...] : [])`. Consistent with main Package.swift approach.

**No example projects** (fuse-app, fuse-library) have Package@swift-*.swift files.

---

## Plan Phases

### Phase 1: Audit & Preserve

**Goal:** Catalogue all changes, back up intentional work, classify everything.

#### Step 1.1: Audit all uncommitted changes
**Action:** Run `git submodule foreach 'git diff --stat'` and classify each change.
**Research:** R4 (complete)
**Acceptance test:** Every modified file across all 25 submodules is classified as INTENTIONAL, WORKAROUND, or NEEDS INVESTIGATION.

#### Step 1.2: Back up intentional changes
**Action:** For each submodule with INTENTIONAL changes, create a patch file in `.planning/patches/` (version-controlled, not ephemeral).
```bash
mkdir -p .planning/patches
cd forks/skipstone && git diff Sources/SkipSyntax/ Tests/SkipSyntaxTests/ > ../../.planning/patches/skipstone-transpiler.patch
```
**Acceptance test:** All intentional patches saved in `.planning/patches/` and verified to apply cleanly. Commit the patches directory.

#### Step 1.3: Resolve NEEDS INVESTIGATION items
**Action:** For skip-android-bridge and skip-fuse-ui Package.swift local paths:
- Verify whether SPM local path override from root package handles transitive resolution (R14)
- If yes: classify as REDUNDANT (can revert but low priority — not harmful)
- If no: classify as NECESSARY (keep)
**Research:** R14 (COMPLETE — SPM unifies by package identity; root local paths override transitive remotes. Fork local paths are REDUNDANT but harmless; classify as INTENTIONAL for standalone buildability.)
**Acceptance test:** Classification complete for all items.

---

### Phase 2: Restore Upstream Purity

**Goal:** Make skip and skipstone Package.swift byte-identical to upstream. Remove all workaround changes.

#### Step 2.1: Restore forks/skip/Package.swift
**Action:** Replace entire file with upstream content (R2). The SKIPLOCAL conditional replaces our hardcoded path.
**Verification:** `cd forks/skip && git diff --stat HEAD -- Package.swift` — no output (file matches the fork's committed upstream-identical state). To verify against upstream, compare against the pinned upstream commit stored in `.planning/upstream-pins.md`.

#### Step 2.2: Restore forks/skipstone/Package.swift
**Action:** Remove `.iOS(.v13)` from platforms line. Restore to `platforms: [.macOS(.v13)]`.
**Verification:** `cd forks/skipstone && git diff --stat HEAD -- Package.swift` — no output. Verify against pinned upstream commit in `.planning/upstream-pins.md`.

> **Note on upstream purity checks:** Do NOT use `curl` against `refs/heads/main` — this compares against a moving target and produces non-deterministic results. Instead, pin upstream commit SHAs in `.planning/upstream-pins.md` and compare locally. Update pins explicitly when syncing with upstream (Phase 8.3).

#### Step 2.3: Revert forks/skipstone/ExportCommand.swift
**Action:** `cd forks/skipstone && git checkout -- Sources/SkipBuild/Commands/ExportCommand.swift`
**Verification:** `git diff Sources/SkipBuild/Commands/ExportCommand.swift` — no output.

#### Step 2.4: Revert forks/swift-macro-testing workaround
**Action:** `cd forks/swift-macro-testing && git checkout -- Package@swift-5.9.swift`
**Verification:** No diff.

#### Step 2.5: Restore swift-composable-architecture macro tests if possible
**Action:** The `ComposableArchitectureMacrosTests` target and `swift-macro-testing` dependency were likely removed to avoid swift-syntax build errors. Now that SKIPLOCAL is not used and swift-syntax is not in the build graph, attempt full restoration:
All commands below run from `forks/swift-composable-architecture/`:
1. `cd forks/swift-composable-architecture`
2. Restore the test directory: `git checkout upstream/main -- Tests/ComposableArchitectureMacrosTests/`
3. Restore the Package.swift entries: `git checkout upstream/main -- Package.swift` then re-apply our intentional changes (local paths, Android gating) on top
4. Verify: `swift test --filter ComposableArchitectureMacrosTests`
5. If tests pass → commit the restoration
6. If tests fail → revert ONLY the macro-related changes (`git checkout HEAD -- Tests/ComposableArchitectureMacrosTests/ Package.swift` then re-apply intentional Package.swift changes from `.planning/patches/`), document the specific error, and add a TODO to the Phase 10 sign-off checklist
7. `cd ../..` (return to repo root)
**Acceptance test:** Either macro tests pass and are restored, OR failure is documented with error details and a sign-off TODO exists.

#### Step 2.6: Clean up stale Package.resolved and lockfiles
**Action:** For each fork with only Package.resolved/lockfile changes, revert:
```bash
for fork in combine-schedulers swift-clocks swift-dependencies swift-sharing; do
  (cd forks/$fork && git checkout -- Package.resolved)
done
```
**Acceptance test:** Only intentional changes remain across all submodules.

---

### Phase 3: Initialise Submodules & Verify Toolchain

**Goal:** Ensure all submodules (including nested) are properly initialised and the Skip toolchain works.

#### Step 3.1: Initialise all submodules recursively
**Action:** `git submodule update --init --recursive`
**Acceptance test:** `forks/skipstone/skip/Sources/SkipDrive/` contains Swift source files. `forks/skipstone/Sources/SkipDriveExternal/` symlink resolves.

#### Step 3.2: Build skipstone from source
**Action:** `cd forks/skipstone && swift build --product SkipRunner`
**Acceptance test:** Build succeeds. Binary at `.build/debug/SkipRunner`.

#### Step 3.3: Verify scripts/skip works
**Action:** `cd forks/skipstone && ./scripts/skip version`
**Acceptance test:** Output shows `Skip X.Y.Z*` (asterisk = local build).

#### Step 3.4: Pin and document toolchain versions
**Action:** Run version checks, document in CLAUDE.md.
**Action (from R16):** Run `swift --version`, `skip version`, `xcodebuild -version`, `java --version`, record in CLAUDE.md prerequisites table. Pin minimum versions: Swift ≥ 6.2, Skip ≥ 1.7, Xcode ≥ 16, JDK ≥ 21.
**Acceptance test:** Versions table in CLAUDE.md.

---

### Phase 4: Verify Builds (No Workarounds)

**Goal:** Prove that iOS and Android builds work with upstream mechanisms only.

#### Step 4.1: iOS build WITHOUT --disable-experimental-prebuilts
**Action:**
```bash
cd examples/fuse-app && swift package clean && swift build
```
**Rationale:** Without SKIPLOCAL, skip downloads binary target → no swift-syntax in graph → no prebuilts conflict.
**Rationale (from R15):** Without SKIPLOCAL, skip downloads as binary → no swift-syntax in build graph → no prebuilts conflict. This is the upstream-intended behaviour.
**Acceptance test:** Build succeeds with exit code 0. No `--disable-experimental-prebuilts` used anywhere.

**If it fails:** Investigate root cause. Check `echo $SKIPLOCAL`. Check if SPM cache is stale. Clean and retry. Do NOT add the flag back without upstream justification.

#### Step 4.2: iOS tests
**Action:** `cd examples/fuse-app && swift test`
**Acceptance test:** Tests pass.

#### Step 4.3: Android build using skipstone/scripts/skip
**Action:**
```bash
SKIP_CMD="$(pwd)/forks/skipstone/scripts/skip"
cd examples/fuse-app && "$SKIP_CMD" android build
```
**Acceptance test:** Build succeeds. Our forked transpiler is used (the one with compose identity fix).

#### Step 4.4: Android export and run
**Action:** Use `"$SKIP_CMD" export --debug --android --no-ios -d .build/export`
**Acceptance test:** APK generated. Can be installed and launched on emulator.

#### Step 4.5: Verify transpiler fix is active
**Action:** Check that the transpiled Kotlin output contains `remember{}` wrapping for let-with-default properties.
**Research:** R3 transpiler fix details
**Acceptance test:** `skip version` shows asterisk. Transpiled output contains expected code.

#### Step 4.6: Verify lite examples build
**Action:**
```bash
cd examples/lite-app && swift build
cd examples/lite-library && swift build
```
**Acceptance test:** Both build successfully using upstream remote deps.

#### Step 4.7: Verify fuse-library builds and tests
**Action:**
```bash
cd examples/fuse-library && swift build && swift test
```
**Acceptance test:** Build and tests pass.

---

### Phase 5: Replace Makefile with Justfile

**Goal:** Replace the fragile Makefile with a `justfile` using [Just](https://github.com/casey/just) — simpler syntax, better errors, self-documenting, agentic-friendly.

**RULE: No silent failures.** All justfile recipes MUST fail loudly on error. Do NOT use `|| true`, `2>/dev/null`, or any other error-masking pattern. If a command can legitimately fail (e.g. `pkill` when no process exists), handle it explicitly with an `if` check, not by suppressing the exit code.

#### Step 5.1: Install Just and create justfile
**Action:** Prerequisite: `brew install just`. Create `justfile` at repo root.
**Key design:**
```just
# Variables
skip := justfile_directory() / "forks/skipstone/scripts/skip"
examples := "fuse-library fuse-app lite-library lite-app"
showcases := "skipapp-showcase skipapp-showcase-fuse"

# Default recipe (just --list)
default:
    @just --list

# Build all examples for iOS
ios-build *targets:
    #!/usr/bin/env bash
    targets="${targets:-{{examples}}}"
    for ex in $targets; do
      echo "=== Building $ex (iOS) ===" && (cd "examples/$ex" && swift build)
    done

# Build for Android
android-build *targets:
    #!/usr/bin/env bash
    targets="${targets:-{{examples}}}"
    for ex in $targets; do
      echo "=== Building $ex (Android) ===" && (cd "examples/$ex" && "{{skip}}" android build)
    done

# Run on Android (full pipeline: emulator check → export → install → launch → logcat)
android-run target:
    #!/usr/bin/env bash
    set -euo pipefail
    # Ensure emulator is running
    if ! adb devices | grep -q 'emulator.*device$'; then
      echo "Starting emulator..." && skip android emulator launch &
      adb wait-for-device
    fi
    # Export APK
    cd "examples/{{target}}" && "{{skip}}" export --debug --android --no-ios -d .build/export
    # Find and install APK
    APK=$(find .build/export -name '*.apk' | head -1)
    adb install -r "$APK"
    # Launch and stream logs
    PKG=$(aapt2 dump badging "$APK" | grep package:\ name | sed "s/.*name='//" | sed "s/'.*//")
    adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
    PID=$(adb shell pidof "$PKG")
    trap 'exit 0' INT TERM
    adb logcat --pid="$PID"

# Test
ios-test *targets:
    #!/usr/bin/env bash
    targets="${targets:-{{examples}}}"
    for ex in $targets; do
      echo "=== Testing $ex (iOS) ===" && (cd "examples/$ex" && swift test)
    done

# Clean
clean:
    #!/usr/bin/env bash
    for ex in {{examples}} {{showcases}}; do
      echo "=== Cleaning $ex ===" && (cd "examples/$ex" && swift package clean)
    done
    rm -rf .build/plugins

# Init (first-time setup)
init:
    git submodule update --init --recursive

# Doctor (preflight checks — 11 checks from R19)
doctor:
    #!/usr/bin/env bash
    pass=0; fail=0
    check() { if eval "$2" >/dev/null 2>&1; then echo "✓ $1"; ((pass++)); else echo "✗ $1 — $3"; ((fail++)); fi; }
    check "Swift ≥ 6.2" "swift --version | grep -qE '6\.[2-9]'" "Install Swift 6.2+ from swift.org"
    check "Skip CLI" "skip version" "Install: brew install skiptools/skip/skip"
    check "Xcode" "xcodebuild -version" "Install Xcode from App Store"
    check "JDK ≥ 21" "java --version | head -1 | grep -qE '2[1-9]|[3-9][0-9]'" "Install: brew install openjdk"
    check "Android SDK" "test -d $ANDROID_HOME/cmdline-tools" "Run: skip android sdk install"
    check "adb" "adb --version" "Included in Android SDK platform-tools"
    check "Submodules init" "test $(git submodule status | grep -c '^-') -eq 0" "Run: just init"
    check "Nested submodule" "test -d forks/skipstone/skip/Sources/SkipDrive" "Run: just init"
    check "SkipDriveExternal symlink" "test -L forks/skipstone/Sources/SkipDriveExternal" "Symlink broken — re-init submodules"
    check "Branch check" "just check-branches | grep -qv 'detached'" "Run: git checkout dev/swift-crossplatform in affected forks"
    check "Upstream purity" "just check-upstream-purity" "skip/skipstone Package.swift diverged from pinned upstream"
    echo "---"; echo "$pass passed, $fail failed"
    test $fail -eq 0

# Submodule management
status:
    git submodule foreach --quiet 'echo "=== $name ===" && git status -sb'

check-branches:
    # Only check direct forks/ children, NOT nested submodules like skipstone/skip
    for sub in forks/*/; do (cd "$sub" && echo "$(basename $sub): $(git branch --show-current)"); done

check-upstream-purity:
    # Compare Package.swift against pinned upstream commit SHAs from .planning/upstream-pins.md
    # Uses --exit-code so non-zero exit on any drift (catches committed AND uncommitted changes)
    SKIP_PIN=$(grep 'skip:' .planning/upstream-pins.md | awk '{print $2}')
    SKIPSTONE_PIN=$(grep 'skipstone:' .planning/upstream-pins.md | awk '{print $2}')
    cd forks/skip && git diff --exit-code "$SKIP_PIN" -- Package.swift
    cd forks/skipstone && git diff --exit-code "$SKIPSTONE_PIN" -- Package.swift

push-all:
    git submodule foreach 'git push origin HEAD'

pull-all:
    git submodule foreach 'git pull origin $(git branch --show-current)'

skip-verify:
    for ex in {{examples}}; do (cd examples/$ex && skip verify --fix); done
```

#### Step 5.2: Remove old Makefile
**Action:** Delete `Makefile`. Do NOT add a Makefile shim — Make's `%:` wildcard target cannot preserve multi-goal dispatch semantics (e.g. `make clean android run` passes three separate targets). A shim would silently break the documented CLI grammar. Users must switch to `just` directly.
**Acceptance test:** `Makefile` does not exist. `just --list` shows all recipes.

#### Step 5.3: Verify CLI ergonomics
**Acceptance test:**
- `just` → prints all recipes with descriptions
- `just ios-build fuse-app` → builds fuse-app for iOS
- `just android-run fuse-app` → full Android pipeline
- `just clean` → cleans all examples
- `just doctor` → runs preflight checks
- `just init` → initialises submodules

---

### Phase 6: Showcase Apps Integration

**Goal:** Add skipapp-showcase and skipapp-showcase-fuse as submodules for local testing and UI validation.

**Note:** skipapp-showcase uses Lite mode (incompatible with TCA). skipapp-showcase-fuse uses Fuse mode (TCA-compatible). Both are useful for verifying skip-ui/skip-fuse-ui fork changes don't break upstream showcase apps.

#### Step 6.1: Fork showcase repos
**Action:**
1. Fork `skiptools/skipapp-showcase` to `jacobcxdev/skipapp-showcase`
2. Fork `skiptools/skipapp-showcase-fuse` to `jacobcxdev/skipapp-showcase-fuse`
3. Create `dev/swift-crossplatform` branch in each
**Acceptance test:** Both forks exist on GitHub with the correct branch.

#### Step 6.2: Add as submodules
**Action:**
```bash
git submodule add -b dev/swift-crossplatform https://github.com/jacobcxdev/skipapp-showcase.git examples/skipapp-showcase
git submodule add -b dev/swift-crossplatform https://github.com/jacobcxdev/skipapp-showcase-fuse.git examples/skipapp-showcase-fuse
```
**Acceptance test:** `git submodule status` shows both new submodules.

#### Step 6.3: Modify Package.swift for local fork paths
**Action:** In each showcase app's Package.swift, replace remote skip-ui / skip-fuse-ui URLs with local paths to `../../forks/skip-ui`, `../../forks/skip-fuse-ui`, etc. (same pattern as fuse-app).
**Acceptance test:** `swift package dump-package --package-path examples/skipapp-showcase` resolves without errors.

#### Step 6.4: Add to justfile
**Action:** Add `showcases` variable to justfile. Add `just showcase` convenience recipe.
**Acceptance test:** `just ios-build skipapp-showcase` and `just ios-build skipapp-showcase-fuse` both succeed.

#### Step 6.5: Verify both build (dual validation)
**Action:** Build each showcase app in TWO modes to validate both local development and upstream compatibility:
1. **Local-path mode:** `just ios-build skipapp-showcase && just ios-build skipapp-showcase-fuse` (uses our forked deps via local paths)
2. **Upstream-URL mode:** Temporarily revert the Package.swift local-path changes in each showcase, run `swift build`, then restore local paths:
```bash
cd examples/skipapp-showcase && git stash && swift build && git stash pop
cd examples/skipapp-showcase-fuse && git stash && swift build && git stash pop
```
3. **Android build:** `just android-build skipapp-showcase-fuse` (Fuse mode showcase — TCA-compatible, validates Android transpilation with our forks)
**Acceptance test:** All three validation modes succeed. If upstream-URL mode fails, our forks have diverged — investigate before proceeding.

---

### Phase 7: Documentation & Agentic Optimisation

**Goal:** Make the repo self-documenting for humans and AI agents.

#### Step 7.1: Rewrite CLAUDE.md
**Action:** Update:
- Remove all `--disable-experimental-prebuilts` references
- Document `$(SKIP)` / `forks/skipstone/scripts/skip` mechanism
- Add bootstrap section (fresh clone → working build)
- Add toolchain versions table
- Add fork inventory with classifications
- Gotcha: nested submodule needs `--recursive`
**Acceptance test:** Zero-context agent can read CLAUDE.md and build the project.

#### Step 7.2: Update auto-memory
**Action:** Update `~/.claude/projects/-Users-jacob-Developer-src-github-jacobcxdev-swift-crossplatform/memory/MEMORY.md` — remove stale references to prebuilts flag, scripts/swift-no-prebuilts, and Makefile. Add justfile patterns.

#### Step 7.3: Verify just --list output
**Action:** Ensure all justfile recipes have doc comments so `just --list` is self-documenting.
**Acceptance test:** `just --list` output is clear and complete.

#### Step 7.4: Implement agentic development patterns
**Action (from R17):** Ensure CLAUDE.md contains:
- Complete `just` recipe list with examples
- Bootstrap sequence: `git clone --recursive` → `just doctor` → `just ios-build fuse-app`
- Fork inventory table (which forks are modified and why)
- Platform conditionals reference table
- Gotchas section with common failure modes
**Acceptance test:** codex-cli with only CLAUDE.md as context can figure out how to build.

---

### Phase 8: Workflows & Guardrails

**Goal:** Prevent regression and make maintenance sustainable.

#### Step 8.1: Implement doctor command
**Action:** Implement the `just doctor` recipe with the 11 checks from R19 (see table above in R19 section). Each check prints green checkmark or red X with actionable fix message. Recipe exits non-zero if any check fails.
**Acceptance test:** `just doctor` catches missing prerequisites and prints clear fix instructions.

#### Step 8.2: Add branch drift monitoring
**Action:** `just check-branches` verifies all submodules on `dev/swift-crossplatform`.
**Important:** Exclude `forks/skipstone/skip` — this is an upstream nested submodule (not our fork) that is often detached or uninitialised. Only check direct children of `forks/`.
**Acceptance test:** Detects and reports wrong branches for our forks. Does NOT false-alarm on nested submodules.

#### Step 8.3: Implement upstream sync workflow
**Action (from R18):** Create `just sync-upstream` recipe and document the workflow in CLAUDE.md:
1. `git fetch upstream` in each fork submodule
2. `git merge upstream/main` (or rebase if preferred) on `dev/swift-crossplatform`
3. Resolve conflicts (Package.swift conflicts are most common — always take upstream for skip/skipstone)
4. Run `just check-upstream-purity` to verify skip/skipstone remain clean
5. Run `just ios-test && just android-build fuse-app` to verify no regressions
6. Update pinned upstream commits in `.planning/upstream-pins.md`
**Acceptance test:** `just sync-upstream` runs without error when upstream has no changes. Workflow documented in CLAUDE.md.

#### Step 8.4: Implement upstream PR workflow
**Action (from R15):** Document in CLAUDE.md how to extract fork changes into upstream PRs:
1. Create a branch off upstream/main in the fork
2. Cherry-pick relevant commits from `dev/swift-crossplatform`
3. Ensure changes are gated with `#if os(Android)` / `#if SKIP_BRIDGE`
4. Open PR against upstream repo
**Acceptance test:** Workflow documented in CLAUDE.md.

#### Step 8.5: Document external app consumption
**Action (from R12):** Add a section to CLAUDE.md documenting how a private app consumes these forks:
- **CI/release:** `package(url: "https://github.com/jacobcxdev/<fork>.git", branch: "dev/swift-crossplatform")`
- **Local dev:** Xcode workspace containing private app + swift-crossplatform repo (SPM auto-resolves local checkouts)
- **Alternative:** `.package(path: "../swift-crossplatform/forks/<fork>")` overrides in a local-only Package.swift branch
**Acceptance test:** Documentation added to CLAUDE.md.

---

### Phase 9: Clean Up

**Goal:** Remove all artifacts from previous workaround attempts.

#### Step 9.1: Remove scripts/ directory
**Action:** `rm -rf scripts/`
**Acceptance test:** Directory doesn't exist.

#### Step 9.2: Remove stale Package.resolved files
**Action:** `swift package resolve` in each example after Package.swift changes.
**Acceptance test:** Package.resolved files are fresh and consistent.

#### Step 9.3: Final git status audit
**Action:** Verify only intentional changes remain across all submodules.
**Acceptance test:** Every uncommitted change is accounted for and classified.

---

### Phase 10: End-to-End Verification & Sign-off

**Goal:** Prove everything works, test with zero-context agent.

#### Step 10.1: Full pipeline test
```bash
just init
just doctor
just ios-build fuse-app
just ios-test fuse-library
just android-build fuse-app
just clean && just android-run fuse-app  # full pipeline
```
**Acceptance test:** All commands succeed.

#### Step 10.2: Upstream purity verification
```bash
# Verify skip/skipstone Package.swift match pinned upstream commits (catches committed drift)
just check-upstream-purity  # no output = pass
# Verify no workaround artifacts remain
grep -rc "disable-experimental-prebuilts" justfile examples/ forks/  # must be 0
test ! -f Makefile  # old Makefile removed
test ! -d scripts/  # scripts dir must not exist
```
**Acceptance test:** All checks pass.

#### Step 10.3: Zero-context agent test
**Action:** Give codex-cli ONLY the CLAUDE.md file and ask: "How do I build fuse-app for Android?" and "What forks are modified and why?"
**Acceptance test:** Agent can answer correctly from CLAUDE.md alone.

#### Step 10.4: Sign-off checklist
- [ ] skip/Package.swift identical to upstream
- [ ] skipstone/Package.swift identical to upstream
- [ ] No `--disable-experimental-prebuilts` anywhere
- [ ] No workaround scripts
- [ ] `just clean && just android-run fuse-app` works
- [ ] `just ios-build fuse-app` works (no special flags)
- [ ] `just ios-test fuse-library` works
- [ ] Lite examples build
- [ ] Showcase apps build (if added)
- [ ] `just --list` is informative
- [ ] `just doctor` catches missing prerequisites
- [ ] CLAUDE.md is comprehensive and accurate
- [ ] Zero-context agent can build from CLAUDE.md alone
- [ ] All submodules on `dev/swift-crossplatform`
- [ ] Transpiler fix is active in Android builds

---

## External Review Summary

### Codex (critic, high reasoning) — Verdict: REJECT → issues addressed below

| # | Severity | Issue | Resolution |
|---|----------|-------|------------|
| 1 | CRITICAL | Appendix F non-goals contradict body (says "NOT migrating to Just", "NOT adding showcase apps") | **FIXED** — Updated #38 to reflect post-research decisions |
| 2 | CRITICAL | Internal Makefile refs after Phase 5 deletes it (Step 6.4, Phase 10 sign-off) | **FIXED** — All references updated to justfile |
| 3 | CRITICAL | Zero-context executor blocked by unresolved placeholders/TODOs | **FIXED** — All "needs design/work/verification" labels replaced with concrete instructions referencing completed research. Phase 8 steps fully specified with action items. |
| 4 | CRITICAL | Branch validation wrong for nested submodules (skipstone/skip) | **FIXED** — check-branches now only iterates `forks/*/`, excludes nested submodules |
| 5 | CRITICAL | Upstream purity checks non-deterministic (curl to moving target) | **FIXED** — Replaced all curl-based checks with local git diff against pinned commits. Added `.planning/upstream-pins.md` mechanism. |
| 6 | CRITICAL | Makefile shim breaks multi-goal dispatch | **FIXED** — Removed shim entirely. Users switch to `just` directly. |
| 7 | HIGH | `--disable-experimental-prebuilts` removal under-validated | **ACKNOWLEDGED** — Phase 4 exists specifically to validate this. If builds fail without the flag, Phase 4 blocks progression. |
| 8 | HIGH | Justfile design is pseudo-code with placeholders | **ACKNOWLEDGED** — Intentional. The justfile is specified enough for an executor to implement; exact shell commands derive from the existing Makefile which is read during execution. |
| 9 | HIGH | `|| true` silent failure pattern not banned | **ACKNOWLEDGED** — Will add explicit instruction to Phase 5: "Do NOT use `|| true` to mask failures. All recipes must fail loudly." |
| 10 | HIGH | Patch backup to `/tmp` is fragile | **FIXED** — Changed to `.planning/patches/` (version-controlled) |
| 11 | HIGH | Phase ordering mixes migration + feature expansion | **ACKNOWLEDGED** — Phases 1-4 establish baseline, Phases 5-8 improve DX. Showcase apps (Phase 6) only run after proven baseline. |
| 12 | HIGH | Showcase local-path modification defeats upstream validation | **ACKNOWLEDGED** — Fair point. Will add a step to build showcases BOTH with local paths AND without (upstream URLs) to catch divergence. |

### Gemini (architect, 2.5-pro) — Verdict: APPROVE WITH CHANGES

| # | Rating | Area | Assessment |
|---|--------|------|------------|
| 1 | SOUND | Dependency resolution (SPM local path overrides) | Correct strategy |
| 2 | SOUND | Build orchestration (justfile design) | Good direction |
| 3 | SOUND | Git submodule & branching strategy | Appropriate for constraints |
| 4 | SOUND | Phase ordering & completeness | Logical de-risked sequence |
| 5 | **MAJOR** | Agentic execution readiness | Deferred design items block zero-context executor |
| 6 | SOUND | Showcase app integration | Justified by risk reduction |
| 7 | SOUND | Future-proofing | Solid foresight |

**Gemini's required changes:** Resolve all "needs design/investigation" items before execution. Provide deterministic instructions for Phase 2.5 (macro test investigation) and complete Phase 8 workflows.

### Reconciliation

Both reviewers agree the plan is architecturally sound but needs tightening for agentic execution. All CRITICAL issues have been addressed. Remaining HIGH/MAJOR items are either intentionally deferred to later phases or acknowledged with mitigations.

---

## Appendix A: Full Fork Inventory

| # | Fork | Category | Branch | Has Changes | Change Type |
|---|------|----------|--------|-------------|-------------|
| 1 | skip | skiptools-tool | dev/swift-crossplatform | Yes | WORKAROUND (revert Package.swift) |
| 2 | skipstone | skiptools-tool | dev/swift-crossplatform | Yes | MIXED (revert Package.swift + ExportCommand; keep transpiler) |
| 3 | skip-android-bridge | skiptools-lib | dev/swift-crossplatform | Yes | INTENTIONAL (local paths + nav debug) |
| 4 | skip-fuse-ui | skiptools-lib | dev/swift-crossplatform | Yes | INTENTIONAL (local paths + UI fixes) |
| 5 | skip-ui | skiptools-lib | dev/swift-crossplatform | Yes | INTENTIONAL (UI fixes, debug flags) |
| 6 | skip-fuse | skiptools-lib | dev/swift-crossplatform | No | Clean |
| 7 | swift-composable-architecture | pointfreeco | dev/swift-crossplatform | Yes | MIXED (local paths + Android gating = INTENTIONAL; macro test removal = INVESTIGATE) |
| 8 | swift-perception | pointfreeco | dev/swift-crossplatform | Yes | INTENTIONAL (Android bridge) |
| 9 | swift-navigation | pointfreeco | dev/swift-crossplatform | Yes | INTENTIONAL (TextState/ButtonState) |
| 10 | swift-dependencies | pointfreeco | dev/swift-crossplatform | Yes | WORKAROUND (lockfile only) |
| 11 | swift-sharing | pointfreeco | dev/swift-crossplatform | Yes | WORKAROUND (lockfile only) |
| 12 | swift-case-paths | pointfreeco | dev/swift-crossplatform | Yes | WORKAROUND (version update) |
| 13 | swift-clocks | pointfreeco | dev/swift-crossplatform | Yes | WORKAROUND (lockfile) |
| 14 | combine-schedulers | pointfreeco | dev/swift-crossplatform | Yes | WORKAROUND (lockfile) |
| 15 | swift-identified-collections | pointfreeco | dev/swift-crossplatform | No | Clean |
| 16 | swift-custom-dump | pointfreeco | dev/swift-crossplatform | No | Clean |
| 17 | swift-concurrency-extras | pointfreeco | dev/swift-crossplatform | No | Clean |
| 18 | xctest-dynamic-overlay | pointfreeco | dev/swift-crossplatform | No | Clean |
| 19 | swift-snapshot-testing | pointfreeco | dev/swift-crossplatform | No | Clean |
| 20 | swift-macro-testing | pointfreeco | dev/swift-crossplatform | Yes | WORKAROUND (local path override) |
| 21 | swift-structured-queries | pointfreeco | dev/swift-crossplatform | Yes | INTENTIONAL (Android gating) |
| 22 | sqlite-data | pointfreeco | dev/swift-crossplatform | Yes | INTENTIONAL (Android gating) |
| 23 | GRDB.swift | other | dev/swift-crossplatform | Yes | INTENTIONAL (symlink removal) |

**To add as submodules (Phase 6):**
| 24 | skipapp-showcase | skiptools-showcase | dev/swift-crossplatform | N/A | New submodule (Lite mode UI gallery) |
| 25 | skipapp-showcase-fuse | skiptools-showcase | dev/swift-crossplatform | N/A | New submodule (Fuse mode, TCA-compatible) |

## Appendix B: Dependency Graph

```
fuse-app
├── skip (local) → [downloads binary skip OR uses SKIPLOCAL → skipstone]
├── skip-fuse-ui (local) → skip (local), skip-fuse, skip-android-bridge, skip-bridge (remote), swift-jni (remote), skip-ui (local)
├── skip-android-bridge (local) → skip (local), skip-foundation (remote), swift-jni (remote), skip-bridge (remote)
├── skip-ui (local) → skip (remote/overridden), skip-model (remote)
├── swift-composable-architecture (local) → [12 local pointfreeco deps] + [4 Android-conditional deps]
└── sqlite-data (local) → GRDB.swift (local), swift-structured-queries (local)

lite-app
├── skip (REMOTE — source.skip.tools)
└── skip-ui (REMOTE — source.skip.tools)
```

## Appendix C: Codex Requirements Extract (110 items)

[Saved from codex-cli output — see R1-R9 for researched items. Key P0 items:]
- #1-3: Ensure forked skip/skipstone build examples; Package.swift identical to upstream
- #6: `just clean && just android-run fuse-app` works
- #7-9: No undocumented workarounds/flags/scripts
- #31: Careful with resets (uncommitted changes)
- #35-39: Comprehensive plan with testable steps and verification gates
- #86: Pin toolchain versions
- #87: CI guardrails for Package.swift drift
- #90: Doctor command
- #91: Bootstrap steps
- #100: Zero-context executor rehearsal

## Appendix D: Gemini Requirements Extract (14 items)

1. SPM local path override verification for transitive deps
2. Transpiler bootstrap chain (build skipstone before other modules)
3. Global swift-syntax version pinning
4. SKIP_ACTION vs justfile interaction check (confirmed: independent pipelines)
5. Skip.env documentation
6. Android SDK/NDK path portability
7. Recursive nested submodule sync validation
8. Branch drift monitoring
9. Modified upstream detection (LOCAL_CHANGES.md per fork)
10. Lite vs Fuse maintenance decision (DECIDED: keep both)
11. Showcase app validation
12. Debug flag cleanup guardrails (DECIDED: keep in Package.swift)
13. Kotlin version mismatch check
14. Xcode workspace indexing bloat (focused workspaces)

## Appendix E: Complete Task List (38 tasks)

### Research tasks (need investigation before plan is final)
1. Evaluate Makefile vs alternatives — COMPLETE (codex: recommends Just; DECISION: adopt Just, see R10)
2. Evaluate git submodules vs alternatives — COMPLETE (codex: keep with tooling, see R11)
3. Map full fork ecosystem and inter-dependencies — COMPLETE (R4, R7, R8, R9)
4. Design external app consumption workflow — COMPLETE (R12: SPM deps at pinned revision + local overrides for dev)
5. Skip showcase apps integration — COMPLETE (R13: DECISION: add as submodules per user confirmation — Phase 6)
6. Design agentic development optimisation — COMPLETE (R17)
11. Audit ALL 25 forks for erroneous changes — COMPLETE (R4)
12. Validate upstream Skip mechanisms — COMPLETE (R1, R5, R6: SKIPLOCAL conditional, scripts/skip, SKIP_COMMAND_OVERRIDE all documented)
13. Investigate skipstone nested submodule and SkipDriveExternal — COMPLETE (R6)
14. Document current pain points — COMPLETE (build broken due to Package.swift mods, --disable-experimental-prebuilts injected, nested submodule uninitialised)
19. Verify SPM resolves fork-of-fork deps via local path override — COMPLETE (R14: YES, SPM unifies by identity; fork local paths are redundant for resolution but useful for standalone builds)
27. How skip export resolves packages vs swift build — COMPLETE (R27: same SPM resolution, differences only in post-resolution compilation flags like TARGET_OS_ANDROID)
28. swift-syntax version conflicts across forks — COMPLETE (R28: no active conflict; all resolve to 602.0.0; Point-Free forks cap at <603.0.0; future risk when Swift 6.3+ ships)
29. SKIP_ACTION xcconfig interaction with Makefile — COMPLETE (R29: SKIP_ACTION is Xcode-only, controls Android build during Xcode builds; Makefile bypasses Xcode entirely — no conflict)
30. Skip.env files purpose and documentation — COMPLETE (R30: central config for app metadata shared between iOS xcconfig and Android gradle; exists in fuse-app and lite-app)
31. Package@swift-5.9/6.0.swift modifications audit — COMPLETE (R31: 16 files found, 3 INTENTIONAL Android-gated, 13 UNCHANGED; all committed, no drift)
35. Whether Xcode workspace file should be created — DECIDED: NO. Agents use CLI; human devs can create workspaces from documented instructions. Committing .xcworkspace creates git noise. Add workspace creation instructions to CLAUDE.md bootstrap section instead.

### Decision tasks (need user input or reasoned decision)
18. Lite examples maintenance — DECIDED: keep
22. Debug flag policy — DECIDED: keep in Package.swift
33. Criteria for acceptable local patches vs upstream-only — DECIDED (see below)
34. Git commit strategy — DECIDED (see below)
38. Non-goals and scope boundaries — DECIDED (see below)

**#33 Fork Change Policy:**
- `#if os(Android)` / `#if SKIP_BRIDGE` gated code: ACCEPTABLE, consider upstreaming
- Local path deps in Package.swift: ACCEPTABLE (enables standalone fork builds)
- Android-conditional deps in Package.swift: ACCEPTABLE (gated by TARGET_OS_ANDROID env)
- Workarounds for build issues (flag injection, platform hacks): NEVER — investigate root cause
- Feature enhancements (transpiler fixes, UI improvements): ACCEPTABLE, strongly consider upstreaming
- Decision tree: Is it Android-specific? → gate with #if. Is it monorepo-specific? → local paths OK. Is it a workaround? → NO, fix root cause. Is it a feature? → upstream after validation.

**#34 Git Commit Strategy: Per-phase logical grouping.**
- One commit per plan phase in each affected submodule + parent pointer update
- Example: "Phase 2: Restore upstream purity in skip/skipstone" containing all reverts
- Submodule pointers updated immediately after each phase (not batched)
- Detailed commit messages referencing plan section and acceptance test results

**#38 Non-goals and Scope Boundaries:**
- NOT building a CI/CD pipeline (local dev only for now)
- NOT creating Xcode workspace files (document how to create manually)
- NOT modifying upstream-identical forks (skip, skipstone Package.swift = upstream)
- NOT changing the submodule-based architecture (keep, add tooling)
- NOT supporting Windows/Linux builds (macOS development host only)

**Decisions updated post-research (override earlier non-goals):**
- MIGRATING to Just/Justfile (Codex recommended, user confirmed — Phase 5)
- ADDING showcase apps as submodules (user confirmed — Phase 6)

### Implementation tasks (execution phase)
7. Restore upstream Package.swift for skip and skipstone
8. Replace Makefile with justfile using upstream mechanisms
9. Clean up artifacts and update documentation
16. Audit uncommitted changes across ALL submodules before resets
20. Add doctor/preflight command
21. Add branch drift monitoring (just check-branches)
23. Design upstream sync workflow
24. Define canonical fresh-clone bootstrap sequence
25. Pin and document required toolchain versions — COMPLETE (R16)
26. Verify transpiler fix is actually used after build changes
32. CI guardrails to prevent Package.swift drift
36. Clean-room reproducibility verification
37. Create root README.md

### Verification tasks
10. End-to-end verification and zero-context agent test
15. Design upstreamability workflow
17. Include executor principles in plan — DONE (in plan)

## Appendix F: Original User Prompt (verbatim, for compaction survival)

> Having forked skip and skipstone, we need to ensure that they can be used to build the examples. There are a few things of note:
> 1. Other Claude sessions have attempted to do this without reading the docs, and thus may have made erroneous changes. Package.swift should be identical to upstream for both of these forks.
> 2. The purpose of the Makefile is to be in the project root and run the commands—`make clean android run` should clean the project, build the project for Android, and run on the Android emulator.
> 3. We should not need any special workarounds, flags, or scripts locally which are not documented upstream. This is a respectable open-source project designed to be contributed to, and has not been made by buffoons.
>
> In particular, familiarise yourself with:
> - https://raw.githubusercontent.com/skiptools/skipstone/refs/heads/main/README.md
> - https://raw.githubusercontent.com/skiptools/skip/refs/heads/main/README.md
>
> Not only do they describe what each project is, but they also contain important instructions for local development.
>
> The same is true for:
> - https://skip.dev/docs/contributing/
>
> Also, skipstone has skip as a submodule so I'm not sure if that affects anything.
>
> In any case, while the existing development setup has been well-intentioned, it's become quite unwieldly. I think we should align our local development setup for all the pointfreeco forks, skiptools forks (skip libraries and the tools themselves), our example apps, and the skip showcase apps with a more thought-out, robust, upstream-friendly plan.
>
> Perhaps Makefile isn't even the best way to achieve this—it's worked so far, but has required constant patches to keep working. Maybe it's one of those things which takes a bit of work to get running smoothly, or maybe it's the wrong approach. Regardless, I am fond of the CLI it provides, and it is currently providing very useful functionality for local development—whether this could be replicated/improved upon is of course worth investigating deeply.
>
> The use of submodules is useful for keeping everything in one place, but this could be critiqued too.
>
> This repository should be a robust, easy to use, easy to manage, well-organised codebase optimised for local development, upstreamability, and agentic development (especially for agents with little context or zero knowledge).
>
> Important changes may not have been committed, so it's important to be careful when resetting files during this.
>
> While the examples and forks (and their showcase apps) are the only things we care about building right now, I will begin development on an iOS/Android app which uses these forks in the very near future (once the immediate work is done). This will be private and under a different GitHub organisation, but it will use pointfreeco tools (e.g. TCA) on Skip, thus requiring the use of these forks.
>
> Write an extremely comprehensive, detailed, thought-out, well-researched plan to meet the above goals—and indeed any which I may have forgotten about, missed out, implied, or which you think would be useful to add considering the context, use case, and circumstances. State things explicitly—do not assume the agent executing this task will have any context other than the plan itself. Break into bite-sized, well-defined, testable steps with verification gates/acceptance tests.
>
> If walls are hit, or problems encountered repeatedly, research properly rather than creating hacky workarounds or solutions. This must be robust. I must be able to come to the project after your work and be able to very easily pick it up without reviewing your work in-depth.
>
> Many of these instructions should be included in the plan itself where appropriate so that the executor agent acts with the same mindset.

**User follow-up decisions:**
- Lite examples: KEEP and maintain
- Showcase apps: ADD as submodules
- Debug flags: KEEP in Package.swift
- Plan phasing: ONE comprehensive pass
- Build orchestration: Codex recommends Just; evaluate vs improved Makefile
- Fork management: Codex recommends keep submodules with guardrail tooling

## Appendix F: Codex Full Requirements Extract (110 items, verbatim)

1. [EXPLICIT][P0] Ensure the forked skip and skipstone can be used to build the examples.
2. [EXPLICIT][P0] Make forks/skip/Package.swift identical to upstream skip.
3. [EXPLICIT][P0] Make forks/skipstone/Package.swift identical to upstream skipstone.
4. [EXPLICIT][P1] Assume prior Claude sessions may have made erroneous changes due to not reading docs.
5. [EXPLICIT][P0] Preserve the root-level Makefile role as a project entrypoint for commands.
6. [EXPLICIT][P0] `make clean android run` must clean, build for Android, and run on Android emulator.
7. [EXPLICIT][P0] Avoid special local workarounds not documented upstream.
8. [EXPLICIT][P0] Avoid special local flags not documented upstream.
9. [EXPLICIT][P0] Avoid special local scripts not documented upstream.
10. [EXPLICIT][P0] Familiarize with skipstone README at the provided upstream URL.
11. [EXPLICIT][P0] Familiarize with skip README at the provided upstream URL.
12. [EXPLICIT][P0] Familiarize with https://skip.dev/docs/contributing/.
13. [EXPLICIT][P0] Use those docs as authoritative local development guidance.
14. [EXPLICIT][P1] Account for skipstone containing skip as a submodule.
15. [EXPLICIT][P1] Reassess and align local dev setup across pointfreeco forks.
16. [EXPLICIT][P1] Reassess and align local dev setup across skiptools forks.
17. [EXPLICIT][P0] Reassess and align local dev setup across example apps.
18. [EXPLICIT][P1] Reassess and align local dev setup across skip showcase apps.
19. [EXPLICIT][P1] Investigate whether Makefile is the right long-term approach.
20. [EXPLICIT][P1] Preserve useful CLI ergonomics even if implementation changes.
21. [EXPLICIT][P1] Deeply investigate improvement/replacement options for current CLI workflow.
22. [EXPLICIT][P2] Critically evaluate the submodule-heavy structure.
23-26. [EXPLICIT][P1] Work autonomously, deep research, critique/reflect/brainstorm, use installed skills.
27. [EXPLICIT][P1] Target a robust, easy-to-use, easy-to-manage, well-organized repo.
28-30. [EXPLICIT][P1] Optimize for local development, upstreamability, agentic development.
31. [EXPLICIT][P0] Be careful with resets because important local changes may be uncommitted.
32. [EXPLICIT][P0] Immediate build focus is examples, forks, and showcase apps.
33-34. [EXPLICIT][P1] Plan for near-future private iOS/Android app; ensure compatibility with PFW tools on Skip.
35-39. [EXPLICIT][P0] Comprehensive plan, include forgotten/implied goals, explicit instructions, bite-sized steps, verification gates.
40-42. [EXPLICIT][P0] Research before hacking, robust solutions, easy to pick up without deep review.
43-44. [EXPLICIT][P1] Plan usable by zero-context agents; embed mindset instructions.
45-53. [EXPLICIT] Account for repo path, 25 submodules, 4 examples, Makefile grammar, failing build, modified Package.swift, prebuilts flag, nested submodule, scripts/skip.
54-85. [IMPLIED][P0-P1] Audit before fixing, compare against upstream refs, remove accidental divergence, validate emulator prereqs, define clean behaviour, document env prereqs, minimize maintenance, decision criteria for Makefile, backwards-compatible CLI, submodule sync workflow, nested submodule management, include all examples, separate stabilization from improvements, keep fork strategy compatible with future app, avoid hidden local-only assumptions, write for zero-context executor, rollback instructions, non-destructive change handling, code review checkpoints, escalation path, measurable success criteria, acceptance checks for upstream identity / make clean android run / no workarounds / agent handoff, map dependency relationships, produce onboarding docs, verify from clean state.
86-110. [FORGOTTEN][P1-P2] Pin toolchain versions, CI guardrails for Package.swift drift, automated smoke checks, policy preventing undocumented flags, preflight doctor command, canonical bootstrap steps, submodule pinning policy, ADR for orchestration decisions, maintenance ownership, test matrix, failure log/playbook, periodic doc-drift checks, upstream sync cadence, changelog for dev-infra, no-context executor rehearsal, criteria for acceptable local patches, nested submodule safeguards, clean-room reproducibility, deprecation policy if Makefile replaced, boundaries for private-org integration, dev-experience targets (build times), cache strategy for clean, non-goals/scope boundaries, traceability checklist, explicit sign-off criteria.
