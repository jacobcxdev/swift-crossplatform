# Proactive Package Wiring Risks — Phase 6 Database Forks

**Created:** 2026-02-22
**Scope:** Package.swift integration of `GRDB.swift`, `swift-structured-queries`, `sqlite-data`, and `swift-snapshot-testing` into `examples/fuse-library/Package.swift`
**Method:** Static analysis of all four fork Package.swift files, fuse-library's Package.swift, both Package.resolved files (fuse-library and sqlite-data), and all relevant existing fork Package.swift files.

---

## Summary of Findings

| # | Severity | Finding |
|---|----------|---------|
| W1 | **BLOCKER** | sqlite-data references GRDB via remote URL `github.com/jacobcxdev/GRDB.swift`; fuse-library will add GRDB as a local path. SPM identity conflict. |
| W2 | **BLOCKER** | sqlite-data references swift-custom-dump, swift-dependencies, swift-perception, swift-sharing, and xctest-dynamic-overlay via remote URLs (`github.com/jacobcxdev/*` or `github.com/pointfreeco/*`); fuse-library already has all of these as local paths. URL identity mismatch for every one of them. |
| W3 | **BLOCKER** | swift-structured-queries references swift-case-paths via `github.com/pointfreeco/swift-case-paths`; fuse-library has swift-case-paths as a local path. URL identity conflict. |
| W4 | **BLOCKER** | sqlite-data references swift-structured-queries via `github.com/jacobcxdev/swift-structured-queries` (remote, branch); fuse-library will add swift-structured-queries as a local path. Same identity conflict pattern. |
| W5 | **WARNING** | swift-structured-queries uses `swift-dependencies` from `github.com/jacobcxdev/swift-dependencies` with `from: "1.8.1"` (version range), but fuse-library's swift-dependencies fork is a local path. URL mismatch — SPM will treat these as different packages and may duplicate the module. |
| W6 | **WARNING** | Two independent SQLite system libraries exist in the combined graph: GRDB's `GRDBSQLite` (`.systemLibrary`) and swift-structured-queries' `_StructuredQueriesSQLite3` (`.systemLibrary`). Both link `libsqlite3`. Duplicate symbol risk on Android where system SQLite availability is uncertain. |
| W7 | **WARNING** | `swift-snapshot-testing` fork references `swift-syntax` with range `"509.0.0"..<"603.0.0"`, while swift-structured-queries requires `"600.0.0"..<"603.0.0"`. These are compatible, but the resolved version must satisfy both. The fuse-library resolved file already pins `swift-syntax` at `602.0.0` — this is within both ranges and will work, but must be re-checked if swift-syntax is upgraded. |
| W8 | **WARNING** | sqlite-data's `TARGET_OS_ANDROID` environment-variable pattern for conditional dependencies may not fire during Skip's build. The pattern is `Context.environment["TARGET_OS_ANDROID"] ?? "0" != "0"` — identical to TCA's pattern which is known to work. Low risk but must be verified with a `skip android build` run. |
| W9 | **INFO** | swift-snapshot-testing is already a dependency in sqlite-data's own Package.resolved (version `1.18.9`, URL `github.com/flote-works/swift-snapshot-testing`). fuse-library/Package.swift has it commented out for Phase 6. The fork at `forks/swift-snapshot-testing` exists locally. When added as a local path, fuse-library owns the resolution — no remote pin conflict within fuse-library itself, but sqlite-data's transitive remote reference will cause the same URL identity collision as W1/W2. |
| W10 | **INFO** | `swift-tagged` and `swift-concurrency-extras` are net-new transitive dependencies entering the graph through sqlite-data and swift-structured-queries. Neither is a current local-path fork. SPM will fetch them from remote. No conflict today, but if they are ever forked to local paths, the same URL identity problem will recur. |
| W11 | **INFO** | `swift-structured-queries` declares a `StructuredQueriesCasePaths` trait that conditionally depends on `CasePaths`. The trait is not enabled by default (only auto-enabled in SPI doc builds). Fuse-library must NOT enable this trait unless it also has the swift-case-paths local path wired up correctly. Since it already is wired, this is safe — just a reminder to check trait propagation if the trait is ever activated. |
| W12 | **INFO** | Skip sandbox only resolves dependencies used by targets. Declaring a fork in `dependencies:` without any target using a product from it causes that fork to be ignored by the Skip transpiler. This is the current pattern for "transitive resolution" forks (swift-perception, etc.). Adding the database forks purely for dependency declaration is safe from a Skip perspective — but means the Skip build will not validate them. Actual Skip validation requires a test target that imports the product. |

---

## Detailed Analysis

### W1 + W2 + W3 + W4 — The URL Identity Problem (BLOCKER)

This is the central risk for Phase 6 package wiring. SPM identifies packages by their source URL (for remote) or by their path (for local). When fuse-library declares:

```swift
.package(path: "../../forks/swift-case-paths")
```

...and swift-structured-queries (resolved transitively through fuse-library) declares:

```swift
.package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.0.0")
```

SPM sees these as **two different packages** with the same module name. This produces either a "multiple products named X" error or silently picks one resolution, potentially building the wrong version.

**The same conflict exists for every shared dependency:**

| Package | fuse-library uses | Database fork uses |
|---------|------------------|--------------------|
| `GRDB.swift` | (will be) local path | `github.com/jacobcxdev/GRDB.swift` (sqlite-data) |
| `swift-custom-dump` | local path `../../forks/swift-custom-dump` | `github.com/jacobcxdev/swift-custom-dump` (sqlite-data, swift-structured-queries, swift-snapshot-testing) |
| `swift-dependencies` | local path `../../forks/swift-dependencies` | `github.com/jacobcxdev/swift-dependencies` (sqlite-data, swift-structured-queries) |
| `swift-perception` | local path `../../forks/swift-perception` | `github.com/jacobcxdev/swift-perception` (sqlite-data) |
| `swift-sharing` | local path `../../forks/swift-sharing` | `github.com/jacobcxdev/swift-sharing` (sqlite-data) |
| `xctest-dynamic-overlay` | local path `../../forks/xctest-dynamic-overlay` | `github.com/pointfreeco/xctest-dynamic-overlay` (sqlite-data, swift-structured-queries) |
| `swift-case-paths` | local path `../../forks/swift-case-paths` | `github.com/pointfreeco/swift-case-paths` (swift-structured-queries, swift-composable-architecture—already wired) |
| `swift-structured-queries` | (will be) local path | `github.com/jacobcxdev/swift-structured-queries` (sqlite-data) |
| `swift-snapshot-testing` | (will be) local path | `github.com/jacobcxdev/swift-snapshot-testing` (sqlite-data, swift-structured-queries) |

**SPM's resolution rule for local paths overriding remote references:** When a package graph contains both a local path reference and a remote URL reference for a package with the same `name` field in its Package.swift, SPM *will* use the local path and suppress the remote — **but only if the package name strings match exactly**. This is the `useLocalPackage` behavior Skip and TCA already rely on.

**Critical verification needed:** All the database fork Package.swift files use remote URLs pointing to `github.com/jacobcxdev/*`. Their `name` fields in Package.swift must match the names declared in the local fork Package.swift files for SPM's local-override to work. Mismatches in the `name:` field (e.g., if the remote repo's Package.swift has `name: "GRDB"` but the local fork also has `name: "GRDB"`) are what make override safe. The identity resolution is by `name`, not by URL.

**Confirmed safe cases (names match):**
- `GRDB.swift` local fork: `name: "GRDB"` — sqlite-data references it as `package: "GRDB.swift"` using identity `grdb.swift`. **Mismatch risk here**: the local path package has `name: "GRDB"` but the remote URL has path component `GRDB.swift`. SPM derives identity from the last URL path component lowercased: `grdb.swift`. The local path's identity is `grdb.swift` (from the directory name `GRDB.swift`). These should match — but this needs a `swift package resolve` to confirm.

**The real solution:** Each database fork's Package.swift, when it references a package that fuse-library also provides via local path, needs to be patched so that fuse-library can override via `useLocalPackage` in Skip's dependency management. This was already done for TCA, swift-sharing, etc. — but was **not yet done** for GRDB, swift-structured-queries, and the database forks themselves.

In practice, this means sqlite-data's Package.swift references to `github.com/jacobcxdev/GRDB.swift`, `github.com/jacobcxdev/swift-structured-queries`, etc. must be replaceable by fuse-library's local path declarations. Whether this happens automatically (SPM name-based override) or requires editing sqlite-data's Package.swift to use local paths must be tested.

---

### W5 — swift-dependencies Version Range vs Local Path

swift-structured-queries declares:
```swift
.package(url: "https://github.com/jacobcxdev/swift-dependencies", from: "1.8.1")
```

This is a version range requirement, not a branch reference. The local fork at `forks/swift-dependencies` is on branch `flote/service-app`. If SPM does not apply the local override for `swift-dependencies` (because the name or URL doesn't match), it will fetch a released version `>= 1.8.1` from remote — potentially fetching a version that diverges from the fork's branch modifications. This could cause API mismatches at build time for any forked API surface.

---

### W6 — Dual SQLite System Libraries

`GRDB.swift/Package.swift` declares:
```swift
.systemLibrary(name: "GRDBSQLite", providers: [.apt(["libsqlite3-dev"])])
```

`swift-structured-queries/Package.swift` appends at runtime:
```swift
.systemLibrary(name: "_StructuredQueriesSQLite3", providers: [.apt(["libsqlite3-dev"])])
```

Both link against the system `libsqlite3`. On macOS and iOS, there is exactly one system SQLite — no symbol conflicts. On Android, the situation is different:

1. The Swift Android SDK may or may not provide `libsqlite3.so` in the sysroot.
2. If skip-sql is in the dependency graph (brought in transitively via skip-fuse or skip-foundation), it may vendor its own SQLite, creating three providers of `sqlite3_*` symbols.
3. Even if both `GRDBSQLite` and `_StructuredQueriesSQLite3` link the same system `libsqlite3.so`, having two `.systemLibrary` targets for the same underlying library is unusual and may cause issues with the Skip transpiler or the Android linker's deduplication.

**Recommendation:** Before Phase 6 planning, determine whether the Swift Android SDK sysroot includes `libsqlite3`. If it does not, both system library targets will fail to link on Android. This is R1 (SQLite C library on Android) in `06-CONTEXT.md` — flag this as a concrete manifestation of that risk.

---

### W7 — swift-syntax Version Range Compatibility

| Fork | swift-syntax requirement |
|------|--------------------------|
| `swift-snapshot-testing` | `"509.0.0"..<"603.0.0"` |
| `swift-structured-queries` | `"600.0.0"..<"603.0.0"` |
| `swift-case-paths` (existing) | `"509.0.0"..<"603.0.0"` |
| `swift-dependencies` (existing) | `"509.0.0"..<"603.0.0"` |
| `swift-perception` (existing) | `"509.0.0"..<"603.0.0"` |
| `swift-composable-architecture` (existing) | `"509.0.0"..<"603.0.0"` |
| Current fuse-library pin | `602.0.0` ✓ |

All ranges include `602.0.0`. The current pin is compatible with all forks. No conflict today. However, if `swift-structured-queries` is updated to require `603.0.0+` before the others are updated, this will become a hard conflict.

---

### W8 — Android Detection Pattern in sqlite-data

sqlite-data uses:
```swift
let android = Context.environment["TARGET_OS_ANDROID"] ?? "0" != "0"
```

This is identical to the pattern in `swift-composable-architecture/Package.swift` (line 6) which is known to work for the existing TCA-based Android build. Low risk. However, `sqlite-data` conditionally adds three new remote packages when `android == true`:

```swift
.package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
.package(url: "https://source.skip.tools/skip-android-bridge.git", "0.6.1"..<"2.0.0"),
.package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
```

These are already in fuse-library's resolved graph (via skip-android-bridge local fork). The local fork's `skip-android-bridge` is at path `../../forks/skip-android-bridge`. The remote URL `https://source.skip.tools/skip-android-bridge.git` is a different identity. Same URL-vs-local-path identity problem as W1/W2 — applies only during Android builds.

---

### W9 — swift-snapshot-testing Already in sqlite-data's Resolved Graph

sqlite-data's `Package.resolved` pins `swift-snapshot-testing` at version `1.18.9` from `github.com/flote-works/swift-snapshot-testing`. The local fork at `forks/swift-snapshot-testing/Package.swift` uses `name: "swift-snapshot-testing"`. The identity derived from the URL `flote-works/swift-snapshot-testing` is `swift-snapshot-testing`.

When fuse-library adds `swift-snapshot-testing` as a local path, the local path identity (from directory name `swift-snapshot-testing`) is also `swift-snapshot-testing`. SPM's local path override should work here — but requires the local path override mechanism to fire before sqlite-data's remote resolution. This is the same mechanism as all other forks.

**Key question:** Does fuse-library need to explicitly declare `swift-snapshot-testing` as a local path dependency even if no fuse-library target directly uses it, purely to ensure the local version wins over sqlite-data's remote pin? The answer is yes — this is the "transitive resolution via useLocalPackage" pattern already used for swift-perception, swift-clocks, etc.

---

### W10 — Net-New Transitive Dependencies

These packages enter the graph for the first time via the database forks and have no existing local-path override:

| Package | Source | Constraint |
|---------|--------|------------|
| `swift-tagged` | sqlite-data (optional, `SQLiteDataTagged` trait), swift-structured-queries (optional trait) | `from: "0.10.0"` — not forked |
| `swift-concurrency-extras` | sqlite-data | `from: "1.0.0"` — already in fuse-library resolved at `1.3.2` via TCA transitive dep |
| `swift-macro-testing` | swift-structured-queries (test only), swift-perception (test only) | already in fuse-library resolved via existing forks |
| `swift-collections` | sqlite-data, TCA (already present) | already pinned at `1.3.0` — compatible with `from: "1.0.0"` |

`swift-concurrency-extras` is already in fuse-library's Package.resolved at version `1.3.2`. sqlite-data requires `from: "1.0.0"` — satisfied. No conflict.

`swift-collections` is already pinned at `1.3.0`. sqlite-data requires `from: "1.0.0"`, TCA requires `from: "1.1.0"` — both satisfied. No conflict.

`swift-tagged` is genuinely new and unforked. It is only needed when the `SQLiteDataTagged` trait is enabled. If fuse-library does not enable that trait, `swift-tagged` never enters the build graph at all. **Recommendation:** Do not enable `SQLiteDataTagged` in Phase 6 tests to avoid pulling in an unaudited transitive dependency.

---

### W11 — StructuredQueriesCasePaths Trait and Local swift-case-paths

swift-structured-queries declares a `StructuredQueriesCasePaths` trait that conditionally includes `CasePaths` from `github.com/pointfreeco/swift-case-paths`. This trait is **not enabled by default**. If fuse-library ever enables this trait (to test enum table support), it must be aware that:

1. The local-path override for swift-case-paths must be active (it already is in fuse-library).
2. The URL `github.com/pointfreeco/swift-case-paths` in swift-structured-queries must resolve to the local fork, not the remote.
3. The local fork's `name: "swift-case-paths"` matches the identity — override should work.

No action needed for Phase 6 unless enum table support is explicitly tested.

---

### W12 — Skip Sandbox and Unused Dependencies

The comment in fuse-library/Package.swift already documents this pattern:

```swift
// Remaining forks (wired for transitive resolution — Skip sandbox compatible via useLocalPackage)
.package(path: "../../forks/swift-perception"),
```

These packages have no fuse-library target that directly imports their products. They are declared purely so SPM's local-path override fires before any transitive remote resolution. The Skip sandbox ignores them (they produce no skip-transpiled output). This is correct and intentional.

The same pattern must be applied to all four database forks:
- `../../forks/GRDB.swift` — needed so local path wins over sqlite-data's remote reference
- `../../forks/swift-structured-queries` — needed so local path wins over sqlite-data's remote reference
- `../../forks/sqlite-data` — needed for actual test targets to import `SQLiteData`
- `../../forks/swift-snapshot-testing` — needed so local path wins over sqlite-data's remote reference

All four must be added to `dependencies:` in fuse-library/Package.swift. The first three listed above can be declared without any target importing them (pure transitive override), until test targets are added. sqlite-data needs at least one test target to be useful.

---

## Action Items for Phase 6 Planning

These are ordered by priority and should be captured in the Phase 6 plan:

1. **[P0 MUST-DO before coding]** Run `swift package resolve` from `examples/fuse-library/` with all four forks added as local paths and no target changes. Verify SPM accepts the graph without duplicate identity errors. This is the ground-truth test for W1–W4.

2. **[P0]** If SPM rejects the graph due to URL identity conflicts, patch the database fork Package.swift files to use local path references (same pattern as TCA/swift-sharing already do for their inter-fork dependencies). Specifically, sqlite-data's Package.swift needs its remote `jacobcxdev/GRDB.swift`, `jacobcxdev/swift-structured-queries`, `jacobcxdev/swift-perception`, `jacobcxdev/swift-sharing`, `jacobcxdev/swift-dependencies`, `jacobcxdev/swift-custom-dump`, `jacobcxdev/swift-snapshot-testing` references replaced with relative local paths when building from the fuse-library context. This is not straightforward because sqlite-data's Package.swift must also work standalone (for its own tests). The standard Skip solution is to use `useLocalPackage` at the Skip build level, not in Package.swift itself.

3. **[P1]** Investigate whether the Swift Android SDK sysroot provides `libsqlite3.so`. If not, both `GRDBSQLite` and `_StructuredQueriesSQLite3` will fail to link on Android, and at least one must be patched to vendor or redirect to an available SQLite. This is R1 from `06-CONTEXT.md`.

4. **[P1]** Do not enable `SQLiteDataTagged` trait in Phase 6. This keeps `swift-tagged` out of the dependency graph.

5. **[P2]** Add fuse-library test targets for SQLiteData tests (which will pull in `InlineSnapshotTesting` from swift-snapshot-testing). Confirm that `InlineSnapshotTesting` works on macOS before adding Android coverage — it modifies source files via `SwiftSyntax` during tests, which may behave differently in the Skip test runner.

6. **[P2]** Verify `swift-syntax 602.0.0` compatibility with swift-structured-queries' macro targets. The range `"600.0.0"..<"603.0.0"` is satisfied, but macro compilation against a specific swift-syntax version can be sensitive to minor ABI differences.

---

## Dependency Graph (Phase 6 addition to fuse-library)

```
fuse-library/Package.swift
  ├── [existing] swift-composable-architecture (local path)
  │     └── [remote] swift-case-paths (pointfreeco) ← overridden by local path
  ├── [existing] swift-case-paths (local path) ← wins
  ├── [existing] swift-dependencies (local path) ← wins
  ├── [existing] swift-custom-dump (local path) ← wins
  ├── [existing] swift-perception (local path) ← wins
  ├── [existing] swift-sharing (local path) ← wins
  ├── [existing] xctest-dynamic-overlay (local path) ← wins
  │
  ├── [new] GRDB.swift (local path)
  │     └── GRDBSQLite (.systemLibrary → libsqlite3) ← W6
  │
  ├── [new] swift-structured-queries (local path)
  │     ├── [remote] swift-case-paths (pointfreeco) ← must be overridden by local path ← W3
  │     ├── [remote] xctest-dynamic-overlay (pointfreeco) ← overridden by local path
  │     ├── [remote] swift-custom-dump (jacobcxdev) ← overridden by local path
  │     ├── [remote] swift-dependencies (jacobcxdev) ← overridden by local path ← W5
  │     ├── [remote] swift-syntax (swiftlang) 600..<603 ← compatible ← W7
  │     └── _StructuredQueriesSQLite3 (.systemLibrary → libsqlite3) ← W6
  │
  ├── [new] sqlite-data (local path)
  │     ├── [remote] GRDB.swift (jacobcxdev) ← must be overridden by local path ← W1
  │     ├── [remote] swift-structured-queries (jacobcxdev) ← must be overridden ← W4
  │     ├── [remote] swift-custom-dump (jacobcxdev) ← overridden by local path ← W2
  │     ├── [remote] swift-dependencies (jacobcxdev) ← overridden by local path ← W2
  │     ├── [remote] swift-perception (jacobcxdev) ← overridden by local path ← W2
  │     ├── [remote] swift-sharing (jacobcxdev) ← overridden by local path ← W2
  │     ├── [remote] xctest-dynamic-overlay (pointfreeco) ← overridden by local path ← W2
  │     ├── [remote] swift-snapshot-testing (jacobcxdev) ← must be overridden ← W2
  │     ├── [remote] swift-concurrency-extras (pointfreeco) ← already in graph ✓
  │     ├── [remote] swift-collections (apple) ← already in graph at 1.3.0 ✓
  │     └── [Android only] skip-bridge, skip-android-bridge, swift-jni ← overridden by local path ← W8
  │
  └── [new] swift-snapshot-testing (local path)
        ├── [remote] swift-custom-dump (jacobcxdev) ← overridden by local path
        └── [remote] swift-syntax (swiftlang) 509..<603 ← compatible ← W7
```

---

## Files Examined

- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-library/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-library/Package.resolved`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/sqlite-data/Package.resolved`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/GRDB.swift/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-structured-queries/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-snapshot-testing/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-composable-architecture/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-sharing/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-dependencies/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-perception/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/swift-case-paths/Package.swift`
- `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/forks/xctest-dynamic-overlay/Package.swift`
