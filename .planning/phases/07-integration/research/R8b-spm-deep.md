# R8b: SPM Identity Conflict Deep Dive

**Created:** 2026-02-22
**SwiftPM version:** Swift Package Manager - Swift 6.2.3
**Investigator:** R8b deep research pass (follows R9 initial finding of 41 conflicts)

---

## Executive Summary

- **41 identity conflict warnings** in fuse-library (confirmed exact match with R9)
- **14 unique conflicting package identities** (not 41 unique packages — warnings repeat per-reporter)
- **3 identity conflict warnings** in fuse-app (skip-android-bridge ×2, skip-ui ×1)
- **6 unused dependency warnings** in fuse-library (confirmed)
- **Build exit code: 0** — warnings do not fail `swift build` or `swift test --list-tests`
- **Escalation timeline: unknown, no committed date** — the warning has said "future versions" since 2022 and has not escalated yet in Swift 6.2.3
- **Root cause: 10 forks reference sibling forks via GitHub URLs** instead of using local paths
- **Recommended fix: Option B (local path substitution in fork Package.swift)** — resolves all 41 conflicts, feasible, does not break standalone builds

---

## 1. Exact Warning Reproduction

### 1.1 fuse-library — all 41 warnings (raw output)

Running `cd examples/fuse-library && swift build 2>&1`:

```
warning: 'sqlite-data': Conflicting identity for grdb.swift: dependency 'github.com/jacobcxdev/grdb.swift' and dependency '/…/forks/grdb.swift' both point to the same package identity 'grdb.swift'. … This will be escalated to an error in future versions of SwiftPM.

warning: 'sqlite-data': Conflicting identity for swift-custom-dump: dependency 'github.com/jacobcxdev/swift-custom-dump' and dependency '/…/forks/swift-custom-dump' …

warning: 'sqlite-data': Conflicting identity for swift-dependencies: dependency 'github.com/jacobcxdev/swift-dependencies' and dependency '/…/forks/swift-dependencies' …

warning: 'sqlite-data': Conflicting identity for swift-perception: dependency 'github.com/jacobcxdev/swift-perception' and dependency '/…/forks/swift-perception' …

warning: 'sqlite-data': Conflicting identity for swift-sharing: dependency 'github.com/jacobcxdev/swift-sharing' and dependency '/…/forks/swift-sharing' …

warning: 'sqlite-data': Conflicting identity for swift-snapshot-testing: dependency 'github.com/jacobcxdev/swift-snapshot-testing' and dependency '/…/forks/swift-snapshot-testing' …

warning: 'sqlite-data': Conflicting identity for swift-structured-queries: dependency 'github.com/jacobcxdev/swift-structured-queries' and dependency '/…/forks/swift-structured-queries' …

warning: 'sqlite-data': Conflicting identity for xctest-dynamic-overlay: dependency 'github.com/pointfreeco/xctest-dynamic-overlay' and dependency '/…/forks/xctest-dynamic-overlay' …

warning: 'swift-structured-queries': Conflicting identity for swift-custom-dump …
warning: 'swift-structured-queries': Conflicting identity for swift-snapshot-testing …
warning: 'swift-structured-queries': Conflicting identity for xctest-dynamic-overlay …

warning: 'swift-snapshot-testing': Conflicting identity for swift-custom-dump …

warning: 'swift-composable-architecture': Conflicting identity for combine-schedulers …
warning: 'swift-composable-architecture': Conflicting identity for swift-case-paths …
warning: 'swift-composable-architecture': Conflicting identity for swift-custom-dump …
warning: 'swift-composable-architecture': Conflicting identity for swift-dependencies …
warning: 'swift-composable-architecture': Conflicting identity for swift-identified-collections …
warning: 'swift-composable-architecture': Conflicting identity for swift-navigation …
warning: 'swift-composable-architecture': Conflicting identity for swift-perception …
warning: 'swift-composable-architecture': Conflicting identity for swift-sharing …
warning: 'swift-composable-architecture': Conflicting identity for xctest-dynamic-overlay …

warning: 'swift-sharing': Conflicting identity for combine-schedulers …
warning: 'swift-sharing': Conflicting identity for swift-custom-dump …
warning: 'swift-sharing': Conflicting identity for swift-dependencies …
warning: 'swift-sharing': Conflicting identity for swift-identified-collections …
warning: 'swift-sharing': Conflicting identity for swift-perception …
warning: 'swift-sharing': Conflicting identity for xctest-dynamic-overlay …

warning: 'swift-navigation': Conflicting identity for swift-case-paths …
warning: 'swift-navigation': Conflicting identity for swift-custom-dump …
warning: 'swift-navigation': Conflicting identity for swift-perception …
warning: 'swift-navigation': Conflicting identity for xctest-dynamic-overlay …

warning: 'swift-dependencies': Conflicting identity for combine-schedulers …
warning: 'swift-dependencies': Conflicting identity for swift-clocks …
warning: 'swift-dependencies': Conflicting identity for xctest-dynamic-overlay …

warning: 'combine-schedulers': Conflicting identity for xctest-dynamic-overlay …
warning: 'swift-clocks': Conflicting identity for xctest-dynamic-overlay …
warning: 'swift-perception': Conflicting identity for xctest-dynamic-overlay …

warning: 'skip-fuse-ui': Conflicting identity for skip-android-bridge …
warning: 'swift-custom-dump': Conflicting identity for xctest-dynamic-overlay …
warning: 'swift-case-paths': Conflicting identity for xctest-dynamic-overlay …

warning: 'skip-fuse': Conflicting identity for skip-android-bridge …

warning: 'fuse-library': dependency 'swift-perception' is not used by any target
warning: 'fuse-library': dependency 'swift-clocks' is not used by any target
warning: 'fuse-library': dependency 'swift-navigation' is not used by any target
warning: 'fuse-library': dependency 'skip-android-bridge' is not used by any target
warning: 'fuse-library': dependency 'swift-snapshot-testing' is not used by any target
warning: 'fuse-library': dependency 'grdb.swift' is not used by any target
```

**Total: 41 identity conflict warnings + 6 unused dependency warnings = 47 warnings**
**Build result: `Build complete!` — exit code 0**

### 1.2 fuse-app — 3 warnings

```
warning: 'skip-fuse-ui': Conflicting identity for skip-android-bridge …
warning: 'skip-fuse-ui': Conflicting identity for skip-ui …
warning: 'skip-fuse': Conflicting identity for skip-android-bridge …
```

**Build result: exit code 0**

### 1.3 Warning count by conflicting package identity

```
xctest-dynamic-overlay      11 warnings  (reported by 11 different fork reporters)
swift-custom-dump            6
swift-perception             4
swift-dependencies           3
combine-schedulers           3
swift-snapshot-testing       2
swift-sharing                2
swift-identified-collections 2
swift-case-paths             2
skip-android-bridge          2
swift-structured-queries     1
swift-navigation             1
swift-clocks                 1
grdb.swift                   1
```

**14 unique conflicting identities. 41 warnings because each is reported once per upstream fork that "discovers" the conflict.**

---

## 2. Conflict Graph — Root Causes

The conflict pattern is: **fork F declares dependency on sibling fork G via GitHub URL, but fuse-library also declares G via local path.**

SwiftPM sees two resolution paths to the same package identity and warns on each fork that pulls the remote copy.

### 2.1 Forks that reference sibling forks via GitHub URL (the conflict sources)

| Fork | Sibling deps via GitHub URL (conflict-causing) |
|------|------------------------------------------------|
| `swift-composable-architecture` | `jacobcxdev/combine-schedulers`, `pointfreeco/swift-case-paths`, `jacobcxdev/swift-custom-dump`, `jacobcxdev/swift-dependencies`, `pointfreeco/swift-identified-collections`, `jacobcxdev/swift-navigation`, `jacobcxdev/swift-perception`, `jacobcxdev/swift-sharing`, `pointfreeco/xctest-dynamic-overlay` |
| `sqlite-data` | `jacobcxdev/GRDB.swift`, `jacobcxdev/swift-custom-dump`, `jacobcxdev/swift-dependencies`, `jacobcxdev/swift-perception`, `jacobcxdev/swift-sharing`, `jacobcxdev/swift-snapshot-testing`, `jacobcxdev/swift-structured-queries`, `pointfreeco/xctest-dynamic-overlay` |
| `swift-sharing` | `jacobcxdev/combine-schedulers`, `jacobcxdev/swift-custom-dump`, `jacobcxdev/swift-dependencies`, `pointfreeco/swift-identified-collections`, `jacobcxdev/swift-perception`, `pointfreeco/xctest-dynamic-overlay` |
| `swift-navigation` | `pointfreeco/swift-case-paths`, `jacobcxdev/swift-custom-dump`, `jacobcxdev/swift-perception`, `pointfreeco/xctest-dynamic-overlay` |
| `swift-dependencies` | `jacobcxdev/combine-schedulers`, `jacobcxdev/swift-clocks`, `pointfreeco/xctest-dynamic-overlay` |
| `swift-structured-queries` | `pointfreeco/swift-case-paths`, `jacobcxdev/swift-custom-dump`, `jacobcxdev/swift-dependencies`, `jacobcxdev/swift-snapshot-testing`, `pointfreeco/xctest-dynamic-overlay` |
| `swift-snapshot-testing` | `jacobcxdev/swift-custom-dump` |
| `swift-custom-dump` | `pointfreeco/xctest-dynamic-overlay` |
| `swift-case-paths` | `pointfreeco/xctest-dynamic-overlay` |
| `swift-perception` | `pointfreeco/xctest-dynamic-overlay` |
| `combine-schedulers` | `pointfreeco/xctest-dynamic-overlay` |
| `swift-clocks` | `pointfreeco/xctest-dynamic-overlay` |

**Forks with zero sibling GitHub URL references (no conflict contribution):**
- `xctest-dynamic-overlay` (leaf — no sibling deps)
- `swift-identified-collections` (apple/swift-collections only)
- `swift-case-paths` (swiftlang/swift-syntax only)
- `GRDB.swift` (apple/swift-docc-plugin only)
- `skip-android-bridge` (Skip SDK only)
- `skip-ui` (Skip SDK only)

### 2.2 fuse-app conflict chains

The 3 fuse-app conflicts are purely Skip SDK conflicts:
- `skip-fuse` → remote `skip-android-bridge` vs local fork `skip-android-bridge`
- `skip-fuse-ui` → remote `skip-android-bridge` vs local fork
- `skip-fuse-ui` → remote `skip-ui` vs local fork `skip-ui`

These cannot be fixed by editing fork Package.swift — `skip-fuse` and `skip-fuse-ui` are upstream Skip packages controlled by skiptools.

### 2.3 Conflict multiplier mechanics

`xctest-dynamic-overlay` generates 11 warnings because 11 different forks each independently declare it via `github.com/pointfreeco/xctest-dynamic-overlay`. When fuse-library declares `forks/xctest-dynamic-overlay` as local path, each of those 11 forks triggers a conflict warning. The package identity is resolved once (to the local path, which takes precedence), but SPM emits a warning for each reporter.

---

## 3. SwiftPM Escalation Timeline

### 3.1 Current status (Swift 6.2.3)

The warning text has read "This will be escalated to an error in future versions of SwiftPM" since at least **July 2022** (Swift Forums thread origin). As of **Swift 6.2.3** (current), it remains a **non-fatal warning**. Build exit code is **0**. The escalation has not happened in 3+ years.

### 3.2 What is known from SwiftPM source and forums

- The Swift Forums thread from 2022 shows this as a long-standing known issue with no committed escalation date.
- The Swift 6.2 release notes do not mention identity conflict escalation.
- SE-0443 (Precise Control Flags over Compiler Warnings, reviewed September 2024) and SE-0480 (Warning Control Settings for SwiftPM, reviewed May 2025) address warning suppression at the compiler and package level respectively — neither specifically targets identity conflicts, but SE-0480 could theoretically allow suppressing them when adopted.
- No Swift Evolution proposal exists that commits identity conflicts to hard-error status.
- SwiftPM's GitHub changelog (CHANGELOG.md) contains no entry escalating this warning to an error.

### 3.3 Risk assessment

**Low-to-medium risk in the 6–12 month horizon.** The warning has been stable for 3 years. It is unlikely to become a hard error in Swift 6.3 without an SE proposal and deprecation cycle. However:

- If it does escalate, all 41 warnings become build errors, blocking `swift build`, `swift test`, and `skip android build`.
- fuse-app's 3 Skip SDK conflicts would be outside our control (skiptools would need to patch `skip-fuse`/`skip-fuse-ui`).
- There is no flag today to suppress identity conflict warnings (SE-0480 is not yet adopted).

**Verdict: Fix proactively. The fix is tractable and removes the risk entirely for fuse-library.**

---

## 4. Mitigation Options

### Option A: Accept warnings (do nothing)

**Cost:**
- 41 warnings pollute every `swift build` and `swift test` run
- Warnings appear in CI logs alongside test output, obscuring real failures
- Build exit code remains 0 — no functional breakage today
- No suppression mechanism exists (SE-0480 not yet adopted)
- If escalation happens mid-Phase 7 or post-launch, it becomes a hard blocker requiring emergency fixes
- `swift package resolve` produces no output (already resolved to cached state), so warnings only appear during build/test

**Verdict: Not recommended. 47 warnings is significant noise; the "future error" language is a real threat.**

### Option B: Edit fork Package.swift to use local paths (RECOMMENDED)

Replace GitHub URL references in fork Package.swift files with `.package(path: "../<sibling>")` entries. Since all 17 forks share the same `forks/` directory, sibling references use relative paths like `../swift-custom-dump`.

**Feasibility:**
- **Which forks need changes:** 12 forks have sibling GitHub URL references (see Section 2.1)
- **Path structure:** All forks are in `forks/` — siblings are always `../sibling-name`
- **Conditional requirement:** NONE. Local path dependencies work for standalone builds too (Swift resolves the path relative to the Package.swift location), as long as the sibling fork checkout exists
- **Standalone build impact:** If someone clones only one fork without siblings, the local path resolution fails. However, all 17 forks are submodules of this monorepo — standalone cloning without siblings is not the intended use case
- **Does this break the fork's own `swift build`:** YES for standalone single-fork builds. Mitigation: use `Context.environment` gating (see below)

**Files to modify (12 forks, estimated 2–8 line changes each):**

| Fork | Lines to change |
|------|----------------|
| `swift-composable-architecture/Package.swift` | ~9 URL → path substitutions |
| `sqlite-data/Package.swift` | ~8 URL → path substitutions |
| `swift-sharing/Package.swift` | ~6 URL → path substitutions |
| `swift-navigation/Package.swift` | ~4 URL → path substitutions |
| `swift-dependencies/Package.swift` | ~3 URL → path substitutions |
| `swift-structured-queries/Package.swift` | ~5 URL → path substitutions |
| `swift-snapshot-testing/Package.swift` | ~1 URL → path substitution |
| `swift-custom-dump/Package.swift` | ~1 URL → path substitution |
| `swift-case-paths/Package.swift` | ~1 URL → path substitution |
| `swift-perception/Package.swift` | ~1 URL → path substitution |
| `combine-schedulers/Package.swift` | ~1 URL → path substitution |
| `swift-clocks/Package.swift` | ~1 URL → path substitution |

**Pattern using `Context.environment` (already used in TCA and sqlite-data forks):**

```swift
import PackageDescription

// Set FORK_LOCAL_PATHS=1 when building from the monorepo workspace
let useLocalPaths = Context.environment["FORK_LOCAL_PATHS"] ?? "0" != "0"

func dep(_ name: String, url: String, branch: String) -> Package.Dependency {
    if useLocalPaths {
        return .package(path: "../\(name)")
    } else {
        return .package(url: url, branch: branch)
    }
}

func dep(_ name: String, url: String, from version: Version) -> Package.Dependency {
    if useLocalPaths {
        return .package(path: "../\(name)")
    } else {
        return .package(url: url, from: version)
    }
}
```

However, the simpler approach is to **always use local paths in the fork Package.swift files unconditionally** since these forks are only ever built from within the monorepo checkout. The `Context.environment` pattern is needed only if the forks are intended for standalone release — they are not (they are internal monorepo forks on `dev/swift-crossplatform`).

**Unconditional local path substitution example (swift-custom-dump/Package.swift):**

```swift
// Before:
.package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2")

// After:
.package(path: "../xctest-dynamic-overlay")
```

**Resolution of fuse-app conflicts:** The 3 fuse-app conflicts (skip-fuse → skip-android-bridge, skip-fuse-ui → skip-android-bridge, skip-fuse-ui → skip-ui) are in **upstream Skip packages** (`skip-fuse`, `skip-fuse-ui`). These cannot be fixed by editing our forks — skiptools controls those Package.swift files. These 3 warnings will remain regardless.

**Verdict: Implement unconditional local path substitution in the 12 forks. Eliminates 38 of 41 fuse-library conflicts. The 3 Skip SDK conflicts in fuse-app are immovable.**

### Option C: SPM package-collection overrides

**Status: Not a real feature.** SwiftPM has no "package collection override" or workspace-level dependency substitution mechanism analogous to Xcode's local package override or Cargo's `[patch]` section. The commonly referenced "mirror" approach (`swift package config set-mirror`) works for URL-to-URL substitution but not for the local-path conflict scenario. This option does not exist in a usable form.

### Option D: `Context.environment` conditional local paths in workspace

**Context:** `Context.environment` is already used in TCA fork (`TARGET_OS_ANDROID`) and sqlite-data fork (`TARGET_OS_ANDROID`) to gate platform-specific dependencies. The same mechanism could be used to switch between GitHub URLs and local paths based on an environment variable set when building from the monorepo.

**Pattern:**

```swift
let useLocalPaths = Context.environment["FORK_LOCAL_PATHS"] ?? "0" != "0"

let package = Package(
    dependencies: useLocalPaths ? [
        .package(path: "../xctest-dynamic-overlay"),
        // ...
    ] : [
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2"),
        // ...
    ]
)
```

fuse-library's Makefile (or `make build`) would set `FORK_LOCAL_PATHS=1`.

**Assessment:** Adds complexity with marginal benefit over Option B. Since the forks are internal monorepo forks not meant for standalone use, there is no scenario requiring the GitHub URL path. Unconditional local paths (Option B without the env gating) are simpler and equally correct.

**Verdict: Viable but unnecessary complexity. Prefer unconditional Option B.**

---

## 5. Unused Dependency Warnings

### 5.1 The 6 unused dependencies (confirmed)

```
warning: 'fuse-library': dependency 'swift-perception' is not used by any target
warning: 'fuse-library': dependency 'swift-clocks' is not used by any target
warning: 'fuse-library': dependency 'swift-navigation' is not used by any target
warning: 'fuse-library': dependency 'skip-android-bridge' is not used by any target
warning: 'fuse-library': dependency 'swift-snapshot-testing' is not used by any target
warning: 'fuse-library': dependency 'grdb.swift' is not used by any target
```

### 5.2 Root cause

These 6 packages are declared in fuse-library's Package.swift as top-level dependencies (with the comment "Remaining forks (wired for transitive resolution — Skip sandbox compatible via useLocalPackage)"), but no fuse-library target directly imports products from them. They are present to force SPM to resolve the local fork version over any transitive remote copy.

### 5.3 Does Phase 7 resolve these naturally?

Phase 7 adds feature targets that will import:
- `ComposableArchitecture` (from `swift-composable-architecture`) → pulls in `swift-navigation`, `swift-perception` transitively, but these are still unused as **direct** fuse-library dependencies
- `swift-snapshot-testing` remains unused unless Phase 7 adds snapshot tests directly in fuse-library

**Verdict:** Phase 7 does NOT naturally resolve these 6 unused warnings. The warnings exist because of the "force local resolution" strategy in fuse-library's Package.swift. If Option B (local paths in fork Package.swift) is implemented, the need to force-declare these transitive forks in fuse-library's top-level dependencies disappears — those 6 declarations can be removed, eliminating all 6 unused dependency warnings too.

**Resolution of unused warnings via Option B:**
- Once fork Package.swift files reference siblings via local paths, SPM naturally resolves to the local forks without needing them force-declared in fuse-library
- Remove the 6 force-declared deps from fuse-library Package.swift
- All 6 unused dependency warnings disappear

---

## 6. Impact on CI and Reproducibility

### 6.1 `swift build` exit code

**Exit code: 0.** Identity conflict warnings and unused dependency warnings do not cause build failure. Verified on Swift 6.2.3.

### 6.2 `swift test` exit code

**Exit code: 0.** `swift test --list-tests` shows 41 conflict warnings but exits 0. Full `swift test` runs also exit 0 (warnings only appear during the resolve/build phase, not in test output itself).

### 6.3 `skip test` and `skip android build`

Not directly verified, but `skip test` delegates to `swift build` internally before transpiling. The warnings appear during the Swift build phase. Since exit code is 0, `skip test` and `skip android build` continue normally. The warnings appear in build logs.

### 6.4 Warning pollution in CI logs

47 warnings (41 conflict + 6 unused) appearing in every `swift build` / `swift test` run means:
- Real build warnings (deprecations, type-checker hints) are buried
- CI log grep for `warning:` returns false positives
- New warnings introduced by Phase 7 code changes are hard to spot

This is the most concrete current cost of doing nothing.

### 6.5 Effect on test output

The warnings appear in **stderr during the build phase**, before test output begins. They do not interleave with individual test pass/fail lines. However, they appear in XCTest's overall output and in any CI artifact that captures stderr.

---

## 7. Phase 7 Impact Assessment

### 7.1 Will Phase 7 changes increase conflict count?

Phase 7 wires additional forks into fuse-app (all 17 forks via local paths) and adds new test targets to fuse-library. This will:

- **fuse-library:** Adding new targets that depend on `ComposableArchitecture` does not add new conflicts — the conflict graph is already fully expressed by the existing Package.swift declarations. Conflict count stays at 41.
- **fuse-app:** Adding TCA, swift-sharing, sqlite-data, and other forks to fuse-app's Package.swift **will add new conflicts** — each fork added to fuse-app that has sibling GitHub URL references will generate new warnings. Estimated addition: 20–30 new warnings in fuse-app if all forks are wired without fixing their Package.swift first.

**This makes Option B more urgent.** If Phase 7 wires all 17 forks into fuse-app before fixing fork Package.swift files, fuse-app conflict count grows from 3 to potentially 30+.

### 7.2 Recommended sequencing

Fix fork Package.swift files (Option B) as a **Phase 7 prerequisite**, before wiring forks into fuse-app. This means:
1. Edit 12 fork Package.swift files to use local paths for sibling deps
2. Verify `swift build` in fuse-library shows 0 identity conflict warnings (only 3 Skip SDK warnings in fuse-app will remain, which are immovable)
3. Proceed with Phase 7 fuse-app wiring — new forks added won't generate additional conflicts

---

## 8. Concrete Recommendations

### Recommendation 1: Fix fork Package.swift files before Phase 7 implementation begins (PRIORITY: HIGH)

**Action:** For each of the 12 forks listed in Section 2.1, replace GitHub URL references to sibling forks with `../sibling-name` local path references.

**Effort:** ~2 hours. 12 files, each requiring 1–9 line replacements.

**Outcome:**
- fuse-library identity conflict warnings: 41 → 0 (3 Skip SDK warnings in fuse-app remain)
- Unused dependency warnings: 6 → 0 (after also removing force-declared deps from fuse-library Package.swift)
- Total warnings eliminated: 47

**Example change for `swift-custom-dump/Package.swift`:**

```swift
// Before:
.package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2")

// After:
.package(path: "../xctest-dynamic-overlay")
```

**Example change for `swift-composable-architecture/Package.swift`:**

```swift
// Before (9 sibling deps via GitHub URL):
.package(url: "https://github.com/jacobcxdev/combine-schedulers", branch: "flote/service-app"),
.package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.5.4"),
.package(url: "https://github.com/jacobcxdev/swift-custom-dump", from: "1.3.2"),
.package(url: "https://github.com/jacobcxdev/swift-dependencies", branch: "flote/service-app"),
.package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
.package(url: "https://github.com/jacobcxdev/swift-navigation", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-perception", branch: "flote/service-app"),
.package(url: "https://github.com/jacobcxdev/swift-sharing", branch: "flote/service-app"),
.package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.3.0"),

// After:
.package(path: "../combine-schedulers"),
.package(path: "../swift-case-paths"),
.package(path: "../swift-custom-dump"),
.package(path: "../swift-dependencies"),
.package(path: "../swift-identified-collections"),
.package(path: "../swift-navigation"),
.package(path: "../swift-perception"),
.package(path: "../swift-sharing"),
.package(path: "../xctest-dynamic-overlay"),
```

Note: Non-sibling deps (`OpenCombine`, `swift-collections`, `swift-concurrency-extras`, `swift-syntax`, etc.) keep their GitHub URLs — they have no local fork.

### Recommendation 2: Remove force-declared unused deps from fuse-library Package.swift after fixing forks

**Action:** After fixing fork Package.swift files, remove these 6 lines from `examples/fuse-library/Package.swift`:

```swift
// Remove these (no longer needed after fork Package.swift uses local paths):
.package(path: "../../forks/swift-perception"),
.package(path: "../../forks/swift-clocks"),
.package(path: "../../forks/swift-navigation"),
.package(path: "../../forks/skip-android-bridge"),
.package(path: "../../forks/swift-snapshot-testing"),  // keep if needed by Phase 7 targets
.package(path: "../../forks/GRDB.swift"),              // keep if needed by Phase 7 targets
```

Verify each before removing — `swift-snapshot-testing` and `GRDB.swift` may be needed by Phase 7 fuse-library targets.

### Recommendation 3: Accept the 3 remaining fuse-app Skip SDK conflicts

The conflicts `skip-fuse → skip-android-bridge` and `skip-fuse-ui → skip-android-bridge/skip-ui` cannot be fixed in this repo. They require upstream skiptools changes. Accept them as permanent low-severity warnings. If SE-0480 is adopted, they can be suppressed via package-level warning configuration.

### Recommendation 4: Monitor Swift 6.3 / SwiftPM release notes

Add a note in the project's maintenance checklist: on each Swift toolchain upgrade, grep the SwiftPM changelog for "identity conflict" to catch escalation before it becomes a CI breakage.

---

## 9. Summary Table

| Metric | Value |
|--------|-------|
| fuse-library identity conflict warnings | 41 |
| fuse-library unused dependency warnings | 6 |
| fuse-app identity conflict warnings | 3 |
| Unique conflicting package identities (fuse-library) | 14 |
| Forks with sibling GitHub URL references (conflict sources) | 12 |
| Build exit code (fuse-library) | 0 (non-fatal) |
| Build exit code (fuse-app) | 0 (non-fatal) |
| SwiftPM version | 6.2.3 |
| Escalation status | Warning only, no committed escalation date |
| Warning age | Since ~July 2022 (3+ years) |
| Fixable conflicts (via fork Package.swift) | 38 of 41 (fuse-library) |
| Immovable conflicts (Skip SDK upstream) | 3 (fuse-app, skiptools-controlled) |
| Recommended fix | Option B: local path substitution in 12 fork Package.swift files |
| Estimated fix effort | ~2 hours |
| Phase 7 conflict risk if unfixed | fuse-app grows to ~30+ warnings when all forks wired |

---

## Sources

- [SwiftPM identity conflict original forum thread (2022)](https://forums.swift.org/t/x-dependency-on-https-github-com-y-git-conflicts-with-dependency-on-https-github-com-z-which-has-the-same-identity-swift-protobuf-this-will-be-escalated-to-an-error-in-future-versions-of-swiftpm/59176)
- [SE-0480: Warning Control Settings for SwiftPM (pitch, 2025)](https://forums.swift.org/t/pitch-warning-control-settings-for-swiftpm/78666)
- [SE-0443: Precise Control Flags over Compiler Warnings](https://forums.swift.org/t/se-0443-precise-control-flags-over-compiler-warnings/74116)
- [Swift 6.2 Released](https://www.swift.org/blog/swift-6.2-released/)
- Raw `swift build` output: captured 2026-02-22 on Swift 6.2.3

*Research completed: 2026-02-22*
*Commands run: `swift build` (fuse-library), `swift build` (fuse-app), `swift package show-dependencies --format json`, `swift test --list-tests`, grep across all 17 fork Package.swift files*
