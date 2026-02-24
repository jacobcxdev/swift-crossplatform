# R10b: Cross-Cutting Deep Dive — What the Other 9 Researchers Missed

**Created:** 2026-02-22
**Role:** Paranoid reviewer — adversarial analysis of blind spots across R1-R10
**Method:** Codebase-wide grep/glob analysis across all 17 forks, both example projects, planning docs, and toolchain config

---

## 1. Swift 6 Strict Concurrency Compliance

### Finding: Silent concurrency mismatch between example projects and fork packages

**Severity: MEDIUM-HIGH**

Both example projects use `swift-tools-version: 6.1` with NO explicit `swiftLanguageModes` or `swiftSettings`:
- `examples/fuse-library/Package.swift` — tools-version 6.1, no swiftSettings
- `examples/fuse-app/Package.swift` — tools-version 6.1, no swiftSettings

With swift-tools-version 6.1, **Swift 6 language mode is the default**, meaning full strict concurrency checking is active for all targets in these packages.

Meanwhile, the fork packages are a patchwork:

| Concurrency Setting | Forks |
|---|---|
| Swift 6 mode (`swiftLanguageModes: [.v6]`) | xctest-dynamic-overlay, swift-dependencies, combine-schedulers, swift-structured-queries, sqlite-data |
| Swift 5 mode (`swiftLanguageModes: [.v5]`) | **swift-perception**, **swift-snapshot-testing** |
| StrictConcurrency experimental feature only | swift-clocks, swift-identified-collections, swift-case-paths, swift-navigation, swift-composable-architecture |
| No concurrency settings at all | skip-android-bridge, skip-ui, GRDB.swift (has .swiftLanguageMode(.v5) on some targets) |
| Swift 6.0 tools version (implicit Swift 6) | swift-custom-dump |

**Risk:** `swift-perception` and `swift-snapshot-testing` are PINNED to Swift 5 language mode. When imported into a Swift 6 project, their APIs may produce Sendable warnings or errors at the call site. TCA's `ComposableArchitectureMacros` target uses SwiftSyntax which does compile in the host (not target) toolchain — this is fine. But test targets importing `swift-perception` types that are not `Sendable` could produce unexpected concurrency diagnostics.

**What to check in Phase 7:**
- Run `swift build 2>&1 | grep -i "sendable\|concurrency\|warning"` on fuse-library and fuse-app to capture any Swift 6 warnings
- Particularly watch for warnings when test code creates `@Sendable` closures that capture non-Sendable types from Swift 5-mode packages

### Finding: TCA applies StrictConcurrency only to non-test targets

TCA's Package.swift (line 101-110):
```swift
#if compiler(>=6)
  for target in package.targets where target.type != .system && target.type != .test {
    target.swiftSettings = target.swiftSettings ?? []
    target.swiftSettings?.append(contentsOf: [
      .enableExperimentalFeature("StrictConcurrency"),
    ])
  }
#endif
```

This means `ComposableArchitectureTests` compiles WITHOUT strict concurrency. Phase 7 tests in fuse-library/fuse-app will compile WITH strict concurrency (Swift 6 default). Any test patterns copied from TCA's own tests may produce concurrency errors in the stricter context.

---

## 2. Skip Version Compatibility

### Finding: Skip 1.7.2 installed, packages pin `from: "1.7.2"`

Both example projects declare:
```swift
.package(url: "https://source.skip.tools/skip.git", from: "1.7.2")
```

`skip version` returns `1.7.2`. This is consistent.

**Risk:** No upper bound is declared. If Skip 1.8.x introduces breaking changes to the skipstone plugin or Fuse mode compilation, a `swift package resolve` could pull a breaking version. Package.resolved is gitignored (`.gitignore` line 16: `Package.resolved`), so resolved versions are not reproducible across machines.

**Recommendation:** Consider committing Package.resolved for the example projects, or pinning to an exact range (`"1.7.2"..<"1.8.0"`). This is especially important for Phase 7 where reproducibility matters for TEST-10 and TEST-11 (emulator tests).

---

## 3. Macro Compilation on Android

### Finding: Macros are safe — compile on host, not target

TCA's `.macro(name: "ComposableArchitectureMacros")` target depends on SwiftSyntax and SwiftCompilerPlugin. Swift macros are expanded at **compile time on the host machine** (macOS), not at runtime on Android. The expanded code (not the macro plugin itself) is what runs on Android.

**Verified:** The project already uses `@Reducer`, `@ObservableState`, `@Presents`, `@ViewAction`, `@CasePathable`, `@DependencyClient`, and `@Table` macros extensively in tests (100+ usages found across example test targets). All compile on macOS. The expanded output is pure Swift that should cross-compile to Android without issues.

**No macro-related `#if` guards found** — the macros expand identically regardless of platform. Platform-specific behavior is in the expanded code's runtime paths, not the macro expansion itself.

**Residual risk:** SPM-04 (`macro targets with SwiftSyntax dependencies compile for Android macro expansion`) is a requirement. This is technically satisfied by the host-compilation model, but should be explicitly documented that "compile for Android" means "macro expansion happens on macOS, expanded code compiles for Android."

---

## 4. Testing Framework Compatibility

### Finding: Mixed XCTest + Swift Testing — potential Android divergence

The project uses both frameworks:
- **146 XCTest methods** across 13 targets (StoreReducerTests, EffectTests, BindingTests, ObservableStateTests, SharedPersistenceTests, SharedBindingTests, SharedObservationTests, StructuredQueriesTests, SQLiteDataTests, ObservationTrackingTests, DependencyTests, FuseLibraryTests, FuseAppViewModelTests)
- **80 Swift Testing `@Test` methods** across 7 targets (CasePathsTests, CustomDumpTests, IdentifiedCollectionsTests, IssueReportingTests, NavigationTests, NavigationStackTests, PresentationTests, UIPatternTests)

**Risk: Swift Testing on Android via `skip test`/`skip android test`**

Swift Testing (`import Testing`, `@Test`) is relatively new (introduced in Swift 5.10/6.0). The reconciled research (R7) distinguishes between:
- `skip test` (Robolectric, transpiled Kotlin) — runs JUnit, which is the transpilation target for XCTest. Swift Testing's `@Test` attributes may or may not be correctly transpiled.
- `skip android test` (emulator, native Swift) — should support both XCTest and Swift Testing since it runs native Swift.

**Nobody investigated whether Skip's skipstone plugin correctly transpiles Swift Testing `@Test` attributes to JUnit equivalents.** XCTest has a well-established mapping to JUnit via Skip, but Swift Testing is newer and may not be supported.

**What to verify:** Before writing any Phase 7 tests, confirm which test framework to use. If `skip test` doesn't support `@Test`, all Phase 7 tests must use XCTest.

### Finding: Mixed frameworks in same file

Some test files import BOTH frameworks:
- `UIPatternTests.swift` — `import XCTest` + `import Testing` + `@MainActor struct UIPatternTests` with `@Test` methods
- This coexistence works on macOS but may confuse Skip's transpiler.

---

## 5. Xcode Project Files

### Finding: No Xcode projects at root level — fork-only

No `.xcodeproj` or `.xcworkspace` files exist at the repository root or in example projects. The project is pure SPM.

Fork-level `.xcodeproj` files exist (GRDB.swift has many, swift-dependencies, swift-sharing, etc.) but these are upstream artifacts, not used by this project.

**No risk here.** The SPM-only approach is clean.

---

## 6. Documentation Gaps

### Finding: README.md is stale — multiple factual errors

| Claim in README | Actual State | Severity |
|---|---|---|
| "14 git submodules" (line 19) | **17 git submodules** (3 added: swift-case-paths, swift-identified-collections, xctest-dynamic-overlay) | HIGH |
| "12 Point-Free/GRDB forks track `flote/service-app` branch" (line 48) | All 17 track **`dev/swift-crossplatform`** branch | HIGH |
| "2 Skip forks track `dev/observation-tracking`" (line 48) | Skip forks also track **`dev/swift-crossplatform`** | HIGH |
| Fork table lists 14 entries | Missing 3: swift-case-paths, swift-identified-collections, xctest-dynamic-overlay | MEDIUM |
| "Known Issues" section lists NavigationStack as "fully guarded out" | STATE.md says this was **RESOLVED in Phase 5** | MEDIUM |
| Repository structure shows `forks/` with 14 entries | Should be 17 | LOW |

**Recommendation:** README.md needs a full refresh as part of DOC-01 or as a parallel task. The branch name error (`flote/service-app`) is particularly dangerous — it would mislead any new contributor.

### Finding: `docs/skip/` has 13 reference docs

```
app-development.md  bridging.md  c-development.md  debugging.md
dependencies.md  development-topics.md  gradle.md  modes.md
platform-customization.md  porting.md  skip-cli.md  swift-support.md
testing.md
```

These are Skip framework reference docs, not project-specific documentation. There is NO project-level documentation beyond README.md and CLAUDE.md. The DOC-01 requirement (FORKS.md) would be the first project-specific doc.

---

## 7. CI/CD Infrastructure

### Finding: ZERO CI at the repository level

There is no `.github/workflows/` directory at the repository root. The individual forks have CI workflows (inherited from upstream), but the parent repository has no automated testing pipeline.

**Impact on Phase 7:**
- No automated way to validate that all 17 forks compile together
- No automated way to run `swift test` or `skip test` on push
- TEST-10 (emulator integration) and TEST-11 (stress tests) have no automated execution path
- A new contributor has no way to know if their changes broke something without manually running `make test`

**Makefile gaps:**
- `android-test` is declared in `.PHONY` (line 4) but has NO rule body — `make android-test` is a silent no-op (confirmed by R9)
- No `clean` target (confirmed by R9)
- No `test-all` target that runs both `swift test` and `skip test`
- No `lint` or `format` target

This is a v2/REL-03 concern but worth documenting now as Phase 7 technical debt.

---

## 8. Dependency Version Pinning

### Finding: Package.resolved is gitignored — builds are NOT reproducible

`.gitignore` line 16: `Package.resolved`

This means:
- Each developer (or CI runner) resolves dependencies independently
- Skip, skip-fuse, skip-fuse-ui, swift-jni, and all transitive deps can resolve to different versions
- A `swift package update` on one machine could produce a different dependency graph than another

Local path dependencies (forks) are pinned by submodule commit, which IS tracked by git. But remote dependencies (`skip.git from: "1.7.2"`, `skip-fuse.git from: "1.0.0"`, `skip-fuse-ui.git from: "1.0.0"`) are semver ranges — unbounded above.

**Risk during Phase 7:** If Skip releases 1.8.0 during Phase 7 execution, `swift package resolve` on a clean build could pull a breaking version mid-phase.

### Finding: Submodule pointers are commit-pinned but branch-tracking

`.gitmodules` sets `branch = dev/swift-crossplatform` for all 17 forks. The actual submodule pointer is a specific commit SHA. However:
- `make pull-all` pulls latest from tracking branch for each fork
- If someone runs `make pull-all` during Phase 7, all fork pointers move
- No locking mechanism exists

**Mitigation:** Don't run `make pull-all` during Phase 7 execution. Document this in the plan.

---

## 9. Phase 7 Requirement Ambiguities

### Finding: Several requirements have ambiguous "on Android" scope

**TEST-08: "Deterministic async effect execution (alternative to `useMainSerialExecutor`) works on Android"**

This is ambiguous. What counts as "works"? The reconciled research (R1) says `effectDidSubscribe` AsyncStream is the intended Android path. But "deterministic" and "AsyncStream" are somewhat at odds — AsyncStream provides ordering guarantees for sequential effects but not for concurrent effects. The requirement should clarify: deterministic for SEQUENTIAL effects, best-effort for concurrent.

**TEST-10: "Integration tests verify observation bridge prevents infinite recomposition on Android emulator"**

This requires an Android emulator. The reconciled research (R7) says `skip android test` is needed, not `skip test`. But can this be run in CI? There are no CI runners. Is this a one-time manual verification?

**TEST-11: "Stress tests confirm stability under >1000 TCA state mutations/second on Android"**

"On Android" is ambiguous — is this macOS Swift tests simulating Android patterns, or actual emulator execution? The stress test (R3) uses `Store.send()` which is synchronous, so it should work on macOS. But "on Android" implies emulator execution, which is slower and may not achieve 1000 mutations/second.

**TEST-12: "A fuse-app example demonstrates full TCA app"**

The word "demonstrates" is ambiguous. Does it mean:
- Compiles and runs (minimum)
- Has tests that pass (medium)
- Has visual UI that a human can interact with (maximum)

R10 recommended capping at 5-6 features. R4 proposed 7 modules + AppFeature. The reconciled research recommends 7 modules. This is the LARGEST requirement by far.

### Finding: Traceability table inconsistency

In REQUIREMENTS.md, the traceability table (lines 306-492) shows ALL Phase 1 and Phase 2 requirements as "Pending" status, but ROADMAP.md shows Phase 1 and 2 as "Executed" (Phase 1) or having completion dates. This is a documentation maintenance issue — the traceability table was never updated after execution.

Specifically:
- OBS-01 through OBS-30: Listed as "Pending" but Phase 1 is "Executed"
- SPM-01 through SPM-06: Listed as "Pending" but Phase 1 is "Executed"
- CP-01 through CP-08: Listed as "Pending" but Phase 2 is "Executed"
- CD-01 through CD-05: Listed as "Pending" but Phase 2 is "Executed"

Meanwhile, IC-01..IC-06, IR-01..IR-04, TCA-01..TCA-16, DEP-01..DEP-12, SQL-01..SQL-15 are correctly marked "Complete." This suggests Phases 1-2 were executed before the traceability update convention was established.

Similarly, SD-01..SD-12 are marked "Pending" in the traceability table but STATE.md says "SD-01..SD-12" were covered by Phase 6 tests.

### Finding: CP-07 is unchecked but potentially satisfied

CP-07: "`@Reducer enum` pattern -- enum reducers synthesize `body` and `scope` on Android" is unchecked in REQUIREMENTS.md but the existing tests use `@Reducer enum` patterns:
- `NavigationTests.swift` line 174: `@Reducer enum` for `Destination`
- `ObservableStateTests.swift` line 137: `@Reducer enum` for `DestinationFeature`
- Phase 4 decision: "@Reducer enum DestinationFeature needs parent wrapper with .ifLet for enum case switching"

This was likely tested but not checked off.

---

## 10. Things That Could Go Wrong During Execution

### A. Network Dependencies During Build

**First build of fuse-app with TCA deps will trigger massive SPM resolution.**

When B1 (missing fuse-app fork dependencies) is resolved, the first `swift build` will:
1. Resolve ~20+ packages (all local forks + remote deps like Skip, skip-fuse-ui, swift-syntax)
2. Download SwiftSyntax (large) for macro compilation
3. Build all macro plugins
4. Build all 17 fork packages

Estimated first-build time: 60-120s (macOS, from R9). First Android transpilation: 5-15 min. If network is flaky, SPM resolution can hang or fail partway through.

**Mitigation:** Do a full `swift package resolve` and `swift build` before starting any coding work.

### B. Disk Space

R9 projects ~8 GB combined `.build/` directories. But this doesn't account for:
- Android Gradle cache (`~/.gradle/caches/`)
- Android emulator images
- SwiftSyntax build artifacts (macro compilation)
- Skip's transpiled Kotlin output

Realistic total: **10-15 GB** if both macOS and Android builds are active.

### C. Emulator Flakiness

R7 identifies two installed emulators (`emulator-36-medium_phone`). Emulator-based tests are inherently flaky:
- Cold start time: 30-90 seconds
- JNI initialization race conditions
- Gradle daemon memory leaks on repeated runs
- ADB connection drops

Phase 7 tests (TEST-10, TEST-11) depend on emulator stability. No retry logic exists.

### D. Fork Submodule Pointer Drift

The 17 submodules are commit-pinned but there is no branch protection on `dev/swift-crossplatform` branches. If someone pushes to a fork's branch during Phase 7:
- `make pull-all` would move all pointers
- Subsequent `swift build` could pick up untested changes
- No way to detect this automatically

### E. Reconciled Research Correction: P1-3 (Combine in GRDB/sqlite-data)

The reconciled research flags "GRDB/sqlite-data use `import Combine` without `OpenCombineShim`" as P1-3. **This is partially incorrect:**

- GRDB Sources has **zero** Combine imports
- sqlite-data's Combine imports are ALL guarded behind `#if canImport(Combine)`:
  - `Fetch.swift` line 3-5: `#if canImport(Combine) / import Combine / #endif`
  - `FetchOne.swift` line 3-5: same guard
  - `FetchAll.swift` line 3-5: same guard
  - `FetchKey.swift` line 7-9: same guard

On Android, `canImport(Combine)` evaluates to `false`, so these imports are excluded. The Combine-dependent code paths (publishers, etc.) are also gated. **P1-3 is a non-issue** for compilation, though it does mean Combine-based observation features (publisher subscriptions) are unavailable on Android — which aligns with the existing `@Shared` notification limitations documented in B2/B3.

### F. OpenCombineShim Dependency Chain

TCA depends on `OpenCombineShim` which conditionally imports either `Combine` (Apple platforms) or `OpenCombine` (other platforms). On Android, this resolves to OpenCombine. The `combine-schedulers` fork also uses OpenCombine.

**Risk:** OpenCombine is a third-party reimplementation of Apple's Combine framework. It may have subtle behavioral differences that surface under TCA's effect system on Android. TCA 2.0 is expected to eliminate the Combine dependency entirely (TCA2-02 in v2 requirements). Until then, OpenCombine is load-bearing infrastructure for Effects on Android.

### G. `@MainActor` Test Isolation

Many existing tests use `@MainActor` annotation:
- All SharedPersistenceTests methods
- All SharedObservationTests methods
- UIPatternTests struct
- SharedBindingTests

On macOS, `@MainActor` test methods run on the main thread. On Android via `skip android test`, the main actor may map differently. TCA's TestStore sets `useMainSerialExecutor = true` which forces all async work onto the main serial executor — but this is disabled on Android.

**Risk:** Phase 7 tests that are `@MainActor` annotated and also use TestStore may behave differently on Android. The `effectDidSubscribe` fallback handles synchronization for effect delivery, but `@MainActor` isolation guarantees may differ.

### H. ROADMAP Inconsistency: Phase 1 & 2 Status

The ROADMAP shows Phase 1 as "Executed" (not "Complete") and Phase 2 as "Executed" (not "Complete"). Phases 3-6 are "Complete". This suggests Phase 1 and 2 may have incomplete verification or outstanding items. STATE.md's "Pending Todos" includes "Android runtime verification (Phase 7): 5 human tests deferred" which originated from Phase 1.

This means Phase 7 is carrying deferred work from Phase 1, not just its own TEST-* requirements. The 5 deferred human tests (single recomposition, nested independence, ViewModifier observation, fatal error on bridge failure, full 14-fork compilation) add to Phase 7's actual scope.

### I. swiftThreadingFatal Stub Longevity

The `swiftThreadingFatal` stub is documented as "required until Swift 6.3" (CLAUDE.md, STATE.md). Swift 6.2 is the minimum requirement for this project. If Swift 6.3 is released during or shortly after Phase 7, the stub becomes dead code that should be removed. But there is no automated check for this — it requires monitoring [swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890).

**Risk:** If the stub is NOT removed after Swift 6.3, it remains as unnecessary symbol pollution. If Swift 6.3 changes the symbol's signature, the stub could cause linker conflicts.

### J. No Lockfile for Gradle Dependencies

Android builds via Skip use Gradle. The Gradle wrapper and dependency versions are controlled by Skip's generated build files. There is no `gradle.lock` file committed. Gradle dependency resolution is also non-reproducible across machines.

---

## Summary: Top 10 Missed Risks by Priority

| # | Risk | Severity | Source Section |
|---|------|----------|----------------|
| 1 | **README.md has wrong branch name, wrong fork count, stale known issues** — would mislead any contributor | HIGH | 6 |
| 2 | **Package.resolved gitignored** — remote dep versions (Skip, skip-fuse) not reproducible; mid-phase breakage possible | HIGH | 8 |
| 3 | **Swift Testing `@Test` transpilation via Skip untested** — may not work with `skip test` (Robolectric/JUnit mapping) | HIGH | 4 |
| 4 | **Swift 5 ↔ Swift 6 language mode mismatch** — swift-perception and swift-snapshot-testing pinned to v5 in Swift 6 consumer projects | MEDIUM-HIGH | 1 |
| 5 | **TCA test strict concurrency gap** — TCA's own tests skip StrictConcurrency but Phase 7 tests will have it enabled | MEDIUM | 1 |
| 6 | **REQUIREMENTS.md traceability table stale** — Phases 1-2 and SD requirements show "Pending" despite being executed/tested | MEDIUM | 9 |
| 7 | **Reconciled P1-3 is wrong** — sqlite-data Combine imports are properly `#if canImport(Combine)` guarded; not an Android compilation risk | MEDIUM (false positive) | 10E |
| 8 | **No CI at repository level** — no automated way to catch regressions across 17 forks | MEDIUM | 7 |
| 9 | **Phase 7 carries 5 deferred Phase 1 human tests** — actual scope is TEST-01..TEST-12 + DOC-01 + 5 HT deferred items | MEDIUM | 10H |
| 10 | **Disk space underestimated** — 8 GB projection doesn't include Gradle cache, emulator images; realistic ~10-15 GB | LOW-MEDIUM | 10B |

---

## Actionable Recommendations for Phase 7 Planning

1. **Before coding:** Refresh README.md with correct fork count (17), correct branch name (`dev/swift-crossplatform`), correct fork table, and remove resolved known issues
2. **Before coding:** Run `swift build 2>&1 | grep -c warning` on both example projects to baseline Swift 6 concurrency warnings
3. **Before writing tests:** Verify `skip test` handles `@Test` attributes. If not, use XCTest exclusively for tests that must run on Android
4. **During planning:** Account for the 5 deferred Phase 1 human tests in Phase 7 scope
5. **During planning:** Update REQUIREMENTS.md traceability table for Phases 1-2 and SD-* items
6. **During execution:** Do NOT run `make pull-all` — freeze all submodule pointers for the duration of Phase 7
7. **During execution:** Run `swift package resolve` and a clean build before starting any test writing
8. **Post-execution:** Consider committing Package.resolved for reproducibility
9. **Dismiss P1-3:** sqlite-data's Combine imports are correctly guarded — this is not a blocker

---

*Deep dive completed: 2026-02-22*
*Analysis method: Codebase-wide pattern search across all forks, example projects, and planning documents*
*Files examined: 280+ across the repository*
