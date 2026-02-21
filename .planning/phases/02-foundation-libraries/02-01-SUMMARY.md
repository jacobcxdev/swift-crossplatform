---
phase: 02-foundation-libraries
plan: 01
status: complete
started: 2026-02-21
completed: 2026-02-21
---

# Plan 02-01 Summary: Fork Housekeeping & Dependency Graph Setup

## What Was Built

Standardized all fork branches to `dev/swift-crossplatform`, created 3 new GitHub forks (swift-case-paths, swift-identified-collections, xctest-dynamic-overlay), wired all 17 forks into fuse-library's Package.swift with local path overrides, and validated the expanded dependency graph compiles on both macOS and Android.

## Tasks Completed

| # | Task | Status |
|---|------|--------|
| 1 | Rename all fork branches to dev/swift-crossplatform | ✓ |
| 2 | Create 3 new forks and add as submodules | ✓ |
| 3 | Wire all forks into Package.swift + test targets | ✓ |
| 4 | Update fork count in documentation | ✓ |

## Key Files

### Created
- `forks/swift-case-paths/` — CasePaths fork submodule (tag 1.7.2)
- `forks/swift-identified-collections/` — IdentifiedCollections fork submodule (tag 1.1.1)
- `forks/xctest-dynamic-overlay/` — IssueReporting fork submodule (tag 1.9.0, directory name matches SPM package identity)
- `examples/fuse-library/Tests/CasePathsTests/CasePathsTests.swift` — placeholder
- `examples/fuse-library/Tests/IdentifiedCollectionsTests/IdentifiedCollectionsTests.swift` — placeholder
- `examples/fuse-library/Tests/CustomDumpTests/CustomDumpTests.swift` — placeholder
- `examples/fuse-library/Tests/IssueReportingTests/IssueReportingTests.swift` — placeholder

### Modified
- `.gitmodules` — 17 entries, all tracking `dev/swift-crossplatform`
- `examples/fuse-library/Package.swift` — 17 fork `.package(path:)` entries + 4 test targets
- `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift` — added `import Android` for pthread APIs
- `.planning/STATE.md` — Phase 2 in progress
- `.planning/ROADMAP.md` — Plan 02-01 marked complete
- `CLAUDE.md` — Fork count 14→17, branch names updated

## Deviations

1. **pthread import fix required:** Android build failed because `pthread_key_t`/`pthread_getspecific`/`pthread_setspecific` are not in scope without `import Android` (Android uses Bionic, not Glibc). Added `#if canImport(Android) / import Android` to Observation.swift. This was a pre-existing latent bug exposed by the expanded dependency graph triggering a fresh Android build.

2. **GitHub fork naming:** `pointfreeco/xctest-dynamic-overlay` was forked as `jacobcxdev/swift-issue-reporting` on GitHub (upstream renamed the repo). The submodule directory is correctly named `forks/xctest-dynamic-overlay` to match the SPM package identity `name: "xctest-dynamic-overlay"`.

## Self-Check

- [x] All 17 forks on dev/swift-crossplatform branches
- [x] .gitmodules has 17 entries with correct branch tracking
- [x] Package.swift has 17 .package(path:) entries
- [x] 4 per-library test targets created with placeholders
- [x] macOS build succeeds (swift build)
- [x] macOS tests pass (7/7 observation tests, no regressions)
- [x] Android build succeeds (make android-build)
- [x] Documentation updated (14→17 forks)
- [x] SPM-05 (local path overrides) complete

## Self-Check: PASSED
