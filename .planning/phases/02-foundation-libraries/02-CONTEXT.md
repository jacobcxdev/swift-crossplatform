# Phase 2: Foundation Libraries - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Point-Free's utility libraries that TCA depends on work correctly on Android: CasePaths (enum routing), IdentifiedCollections (ID-indexed arrays), CustomDump (value dumping/diffing), and IssueReporting (runtime error surfacing). These are pure Swift logic libraries with no UI. Phase 2 also includes fork housekeeping (branch rename, new forks, wiring all forks into fuse-library).

**In scope:** CasePaths (CP-01..CP-08), IdentifiedCollections (IC-01..IC-06), CustomDump (CD-01..CD-05), IssueReporting (IR-01..IR-04), fork creation/rename, all-forks Package.swift wiring, SPM-05 completion.

**Out of scope:** TCA Store/reducer/effects (Phase 3), shared state (Phase 4), navigation (Phase 5), database (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Fork Housekeeping (Phase 2 Prerequisite)

- **Rename all fork branches to `dev/swift-crossplatform`.** Existing forks use `flote/service-app` (12 PF/GRDB forks) and `dev/observation-tracking` (2 Skip forks). All must be renamed to `dev/swift-crossplatform` for consistency. Update `.gitmodules` branch tracking accordingly. This is the first plan (02-01) before any library work begins.
- **Create 3 new forks.** CasePaths (`swift-case-paths`), IdentifiedCollections (`swift-identified-collections`), and IssueReporting (`xctest-dynamic-overlay`) are not currently forked. Fork each from upstream, branching off `main` at the latest release tag, then create the `dev/swift-crossplatform` branch. Add as submodules in `forks/`. **CRITICAL (DD-6): IssueReporting fork directory MUST be `xctest-dynamic-overlay`** (not `swift-issue-reporting`) — SPM uses directory name as package identity, and 10+ forks depend on `package: "xctest-dynamic-overlay"`.
- **Wire ALL forks into fuse-library Package.swift.** Every fork submodule (now 17+) gets a `.package(path: "../../forks/<name>")` entry. Follow the existing pattern used by other example projects for consistency. This completes SPM-05.
- **Update fork count references.** The "14 forks" number in STATE.md, ROADMAP.md, and CLAUDE.md must be updated to reflect the actual count after new forks are added.

### Test Strategy & Coverage

- **Full Android runtime validation.** Unlike Phase 1 which deferred Android runtime to Phase 7, Phase 2 requires tests to run on Android emulator. "Works on Android" means compiles AND executes correctly on device/emulator.
- **Per-library test targets.** Each library gets its own SPM test target in fuse-library: `CasePathsTests`, `IdentifiedCollectionsTests`, `CustomDumpTests`, `IssueReportingTests`. Better failure isolation and clearer attribution.
- **Upstream tests must pass on macOS.** Fork changes are gated on the upstream test suites continuing to pass on macOS. This catches regressions introduced by Android guards. Both upstream tests AND our fuse-library tests must pass.
- **Test-first for Mirror/reflection.** CustomDump relies heavily on `Mirror`. Run upstream tests on Android emulator first. Only add `#if os(Android)` fallbacks for specific paths that fail at runtime. Don't proactively guard what might already work.

### Fork Change Philosophy

- **Inline `#if` guards only.** When platform-specific changes are needed, use `#if os(Android)` or `#if canImport(Framework)` inline in the same file. No separate platform files (e.g., no `Dump+Android.swift`). Minimizes fork divergence and keeps diffs small for upstream PRs.
- **Gate non-essential APIs with documentation.** If a library feature doesn't work on Android and isn't required by TCA (e.g., CustomDump's XCTest assertion helpers), wrap it in `#if !os(Android)` (or appropriate `canImport` guard). Document every gated-out API in a tracking list — the long-term goal is 100% compatibility, so nothing should be silently dropped.
- **Same branch for all work.** All Phase 2 changes go on the `dev/swift-crossplatform` branch per fork. No per-library feature branches.

### CustomDump Apple Conformances

- **Gate with `#if canImport`.** CustomDump has conformance files for Apple-only frameworks (CoreImage, CoreMotion, GameKit, Photos, Speech, StoreKit, UIKit, SwiftUI, etc.). Use `#if canImport(CoreImage)` etc. to gate these. Check existing guards first — some files may already use `canImport`. Only add guards where missing.

### IssueReporting on Android

- **Production: print to logcat.** `reportIssue()` uses `print()` on Android, which routes to logcat. Visible via `adb logcat -s swift`. Matches existing Skip debugging pattern. No JNI bridge to `android.util.Log` needed.
- **Test context: Swift Testing.** In test context, `reportIssue()` causes test failure via `Issue.record()` / Swift Testing APIs. Target Swift Testing (`#expect`) as the primary test failure mechanism on Android.
- **Match upstream error detail level.** `withErrorReporting` includes whatever level of detail the upstream Apple implementation provides (error description, no extra stack traces). Match, don't exceed.
- **Match Apple severity behavior.** Warnings log, fatals crash — same as Apple platforms. Consistent cross-platform behavior, no Android-specific softening.

### Macro Compilation

- **Macros are host-side only.** Swift macros (`@CasePathable`, etc.) expand at compile time on the macOS host. Only the expanded Swift output needs to compile for Android. The macro plugin itself does not need Android changes.
- **swift-syntax is upstream (no fork).** swift-syntax resolves from the official SPM registry. No modifications needed.
- **Expanded output validation.** Phase 2 validates that `@CasePathable`-expanded code compiles and behaves correctly on Android. If expanded output uses unavailable APIs, the fix location (library shims vs macro plugin changes) will be decided after investigation.

### Dependency Notes

- **swift-collections (OrderedCollections) is upstream.** IdentifiedCollections depends on OrderedCollections from Apple's swift-collections. This is expected to work on Android without forking — it's a pure Swift Apple package.

</decisions>

<specifics>
## Specific Ideas

- CustomDump's `Internal/Mirror.swift` is the most likely file to need Android-specific changes — it wraps Mirror with custom children traversal logic.
- IssueReporting likely uses `os_log` or `OSLog` on Apple — these need `#if canImport(os)` guards with `print()` fallback for Android.
- CasePaths' `@CasePathable` macro generates `AllCasePaths` structs with `CaseKeyPath` properties. The generated code uses standard Swift — unlikely to need Android changes, but the macro expansion output should be inspected.
- IdentifiedCollections is a pure Swift data structure with no platform dependencies. Most likely to "just work" on Android with zero changes.
- The fork branch rename should update `.gitmodules` entries and verify `git submodule update` still works after the rename.

</specifics>

<deferred>
## Deferred Ideas

- **100% API compatibility tracking.** Every API gated out with `#if !os(Android)` must be tracked in a compatibility document for future work. This is a documentation deliverable, not a Phase 2 implementation task.
- **Android-native log integration.** Using `android.util.Log` via JNI for proper logcat priority/tag integration. Deferred — `print()` is sufficient for now.
- **Macro plugin Android compilation (SPM-04).** The requirement says macro targets should compile for Android. Phase 2 validates expanded output only. Full macro plugin cross-compilation is a future concern if the build system requires it.

</deferred>

---

*Phase: 02-foundation-libraries*
*Context gathered: 2026-02-21*
