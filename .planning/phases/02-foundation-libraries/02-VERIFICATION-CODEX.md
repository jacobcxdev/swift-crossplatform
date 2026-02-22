---
phase: 02-foundation-libraries
verified: 2026-02-21T23:50:00Z
verifier: Codex
status: partial
verdict: 5/8 fully verified, 3/8 partial
---

# Phase 2 Verification (Codex)

## Verdict
Phase 2 is **partially verified**.

What is verified:
1. Android dependency graph compiles with all 17 fork path dependencies (`make android-build` passed).
2. Phase 2 targeted test suites exist and pass on macOS (including CasePaths, IdentifiedCollections, CustomDump, IssueReporting).
3. IssueReporting Android fork delta is minimal and Android-guarded.
4. EnumMetadata smoke coverage and `expectNoDifference`/`expectDifference` coverage are present and passing on macOS.

What is not fully verified:
1. Android runtime behavior for success criteria 1-4 is still inferred from macOS tests + Android build, not executed as Android tests.
2. “All upstream tests pass on macOS” is true for 3/4 libraries by default; `swift-case-paths` needs `OMIT_MACRO_TESTS=1` in this environment due `SwiftCompilerPlugin` module availability.
3. Required command `swift test` in `examples/fuse-library` fails due `XCSkipTests` path (Skip/Gradle bridge), though Phase 2 suites themselves pass.

## Commands Run
1. `cd examples/fuse-library && swift test` (failed overall; Phase 2 suites passed, `XCSkipTests` failed)
2. `cd examples/fuse-library && swift test --skip XCSkipTests` (passed)
3. `make android-build` (passed)
4. `cd forks/xctest-dynamic-overlay && swift test` (passed)
5. `cd forks/swift-identified-collections && swift test` (passed)
6. `cd forks/swift-custom-dump && swift test` (passed)
7. `cd forks/swift-case-paths && swift test` (fails on `CasePathsMacrosTests` missing `SwiftCompilerPlugin`)
8. `cd forks/swift-case-paths && OMIT_MACRO_TESTS=1 swift test` (passed)

## Success Criteria Check
| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `@CasePathable` enum matching works on Android | PARTIAL | Coverage exists in `examples/fuse-library/Tests/CasePathsTests/CasePathsTests.swift:33`, `examples/fuse-library/Tests/CasePathsTests/CasePathsTests.swift:41`, `examples/fuse-library/Tests/CasePathsTests/CasePathsTests.swift:68`; Android runtime tests not executed. |
| 2 | `IdentifiedArrayOf` init/O(1) id indexing/removal on Android | PARTIAL | Coverage exists in `examples/fuse-library/Tests/IdentifiedCollectionsTests/IdentifiedCollectionsTests.swift:11`, `examples/fuse-library/Tests/IdentifiedCollectionsTests/IdentifiedCollectionsTests.swift:21`, `examples/fuse-library/Tests/IdentifiedCollectionsTests/IdentifiedCollectionsTests.swift:32`, `examples/fuse-library/Tests/IdentifiedCollectionsTests/IdentifiedCollectionsTests.swift:44`; Android runtime tests not executed. |
| 3 | `customDump` and `diff` output correct on Android | PARTIAL | Coverage exists in `examples/fuse-library/Tests/CustomDumpTests/CustomDumpTests.swift:16`, `examples/fuse-library/Tests/CustomDumpTests/CustomDumpTests.swift:60`; Android runtime tests not executed. |
| 4 | `reportIssue` and `withErrorReporting` surface runtime errors on Android | PARTIAL | Coverage exists in `examples/fuse-library/Tests/IssueReportingTests/IssueReportingTests.swift:5`, `examples/fuse-library/Tests/IssueReportingTests/IssueReportingTests.swift:22`, `examples/fuse-library/Tests/IssueReportingTests/IssueReportingTests.swift:32`; Android runtime tests not executed. |
| 5 | EnumMetadata ABI pointer arithmetic works | VERIFIED | Smoke test present and passing in `examples/fuse-library/Tests/CasePathsTests/CasePathsTests.swift:108`. |
| 6 | `expectNoDifference` / `expectDifference` work via `reportIssue` | VERIFIED | Tests present and passing in `examples/fuse-library/Tests/CustomDumpTests/CustomDumpTests.swift:91` and `examples/fuse-library/Tests/CustomDumpTests/CustomDumpTests.swift:100` with known-issue capture. |
| 7 | All upstream macOS tests pass for all libraries | PARTIAL | Pass by default for `xctest-dynamic-overlay`, `swift-identified-collections`, `swift-custom-dump`; `swift-case-paths` fails default run on macro test toolchain module and passes with `OMIT_MACRO_TESTS=1`. |
| 8 | Android build succeeds with full 17-fork graph | VERIFIED | `make android-build` passed; `examples/fuse-library/Package.swift` contains 17 `.package(path:)` entries at lines 16-33. |

## Verification Task Results
1. Read all summary files and cross-check claims with code: **Completed**.
2. Check `examples/fuse-library/Tests` coverage: **Completed** (all 4 Phase 2 suites exist and are substantive).
3. Verify `forks/xctest-dynamic-overlay` changes are minimal and Android-guarded: **Completed**.
4. Run `cd examples/fuse-library && swift test`: **Completed, command failed** (details below).
5. Run `make android-build`: **Completed, passed**.
6. Check gaps between success criteria and evidence: **Completed**.
7. Check `examples/fuse-library/Package.swift` has 17 fork path entries: **Completed (17 found)**.

## Key Findings

### 1. Required `swift test` command does not pass end-to-end in `examples/fuse-library`
- `swift test` fails on `XCSkipTests.testSkipModule` due Skip Gradle path.
- During that path, a compile error appears in `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift:111`:
  - `if let ptr = ptr` where `ptr` is non-optional in this build context.
- `swift test --skip XCSkipTests` passes and confirms all 34 targeted Phase 2 tests pass with expected known issues.

### 2. Upstream no-regression claim is environment-sensitive for `swift-case-paths`
- Default `swift test` in `forks/swift-case-paths` fails:
  - `Tests/CasePathsMacrosTests/CasePathableMacroTests.swift:2` missing required module `SwiftCompilerPlugin`.
- Running with `OMIT_MACRO_TESTS=1` passes all non-macro upstream tests.
- Therefore criterion 7 is **partial**, not unconditional.

### 3. Android runtime verification remains the largest evidence gap
- Android build is green, but runtime assertions for criteria 1-4 were not executed on Android test runtime in this verification pass.
- Current evidence is strong for compile-time compatibility and macOS behavior, but still inferential for Android runtime semantics.

## Fork Delta Review: `xctest-dynamic-overlay`
Minimal and appropriately guarded.

1. Commit delta from upstream `1.9.0` is a single fork commit (`2952bba`) touching only 2 files.
2. `forks/xctest-dynamic-overlay/Sources/IssueReporting/IsTesting.swift:30` adds Android-specific detection via `#if os(Android)`.
3. `forks/xctest-dynamic-overlay/Sources/IssueReporting/Internal/SwiftTesting.swift:641` expands ELF path to `#if os(Linux) || os(Android)`.
4. Working tree is clean in `forks/xctest-dynamic-overlay`.

## Plan Summary Consistency Notes
Most claims are directionally correct. A few are stale/inexact against current tree state:

1. `02-01-SUMMARY.md` labels per-library test files as placeholders, but they are now fully implemented.
2. `02-02-SUMMARY.md` and `02-03-SUMMARY.md` upstream test counts do not match current command outputs in this environment.
3. `02-03-SUMMARY.md` says zero fork changes needed for CasePaths/CustomDump; this is true for code deltas, but default upstream CasePaths macro test execution is still toolchain-environment dependent.

## Final Assessment
Phase 2 foundation work is in strong shape and Android compile validation is successful, but strict goal achievement is **not fully closed** without Android runtime test execution and a clean default macOS upstream test story for `swift-case-paths` macro tests.
