# R9: Build & Packaging Concerns for Phase 7

## Summary

Phase 7 integration testing faces **three high-severity** and **four medium-severity** build/packaging risks. The most critical is the massive SPM identity conflict surface (41 warnings in fuse-library alone) which, per SwiftPM's own warning text, "will be escalated to an error in future versions of SwiftPM." The fuse-app Package.swift is missing nearly all TCA/Point-Free fork references needed for the Phase 7 TCA showcase rebuild. Build times are manageable today (12s incremental for fuse-library) but will grow significantly when fuse-app adds 12+ new dependencies.

**Risk Summary:**

| # | Risk | Severity | Mitigation Effort |
|---|------|----------|-------------------|
| 1 | SPM identity conflicts (41 warnings) | HIGH | Medium (fork Package.swift edits) |
| 2 | fuse-app missing TCA fork dependencies | HIGH | Low (Package.swift additions) |
| 3 | GRDBSQLite `link "sqlite3"` on Android | HIGH | Medium (conditional systemLibrary or NDK bundling) |
| 4 | 6 unused dependencies in fuse-library | MEDIUM | Low (comment out or wire to targets) |
| 5 | fuse-app Android build is stale | MEDIUM | Low (rebuild and verify) |
| 6 | .build directory bloat (3.8 GB combined) | MEDIUM | Low (clean before final test) |
| 7 | Makefile missing Phase 7 targets | LOW | Low (add new targets) |

## Package Resolution Analysis

### Resolution Timing

| Project | Resolution Time | Build Time (incremental) |
|---------|----------------|--------------------------|
| fuse-library | **14.1s** | 12.4s |
| fuse-app | **4.7s** | N/A (not built recently) |

fuse-library's 14s resolution is acceptable but notably 3x slower than fuse-app's 4.7s, entirely due to the 15 local path dependencies vs fuse-app's 2. When fuse-app gains the full TCA dependency set for Phase 7, expect its resolution time to approach 14-18s.

### Current Target Count

fuse-library currently has **22 targets** (1 library + 1 Skip test + 20 validation test targets). Phase 7 plans to add 5-8 new targets (TestStore integration, stress tests, emulator tests). At ~27-30 targets total, SPM resolution and build planning will remain within acceptable bounds -- the bottleneck is compilation parallelism, not manifest parsing.

### Dependency Graph Depth

The full dependency tree is 7 levels deep at maximum (fuse-library -> skip-fuse -> skip-android-bridge -> skip-bridge -> skip-foundation -> skip-lib -> skip-unit -> skip). No circular dependencies were detected -- all graphs are DAGs. However, the deep nesting means any version conflict in the Skip stack cascades through multiple paths.

## Dependency Conflict Risks

### CRITICAL: 41 SPM Identity Conflicts (fuse-library)

Every fork that is declared as a local path dependency at the root level also appears as a remote URL dependency inside other forks' Package.swift files. SwiftPM resolves this correctly today (local path wins), but emits 41 "Conflicting identity" warnings, with the explicit threat: **"This will be escalated to an error in future versions of SwiftPM."**

**Affected identity pairs (deduplicated by package):**

| Package Identity | Local Path Source | Remote URL Source(s) |
|-----------------|-------------------|----------------------|
| `grdb.swift` | `forks/GRDB.swift` | sqlite-data -> `github.com/jacobcxdev/grdb.swift` |
| `skip-android-bridge` | `forks/skip-android-bridge` | skip-fuse -> `source.skip.tools/skip-android-bridge` |
| `xctest-dynamic-overlay` | `forks/xctest-dynamic-overlay` | swift-case-paths, swift-custom-dump, etc. -> `github.com/pointfreeco/xctest-dynamic-overlay` |
| `swift-custom-dump` | `forks/swift-custom-dump` | swift-snapshot-testing -> `github.com/jacobcxdev/swift-custom-dump` |
| `swift-dependencies` | `forks/swift-dependencies` | swift-sharing, sqlite-data, TCA -> `github.com/jacobcxdev/swift-dependencies` |
| `swift-perception` | `forks/swift-perception` | swift-navigation, TCA -> `github.com/jacobcxdev/swift-perception` |
| `swift-sharing` | `forks/swift-sharing` | sqlite-data, TCA -> `github.com/jacobcxdev/swift-sharing` |
| `swift-snapshot-testing` | `forks/swift-snapshot-testing` | swift-structured-queries -> `github.com/jacobcxdev/swift-snapshot-testing` |
| `swift-structured-queries` | `forks/swift-structured-queries` | sqlite-data -> `github.com/jacobcxdev/swift-structured-queries` |
| `combine-schedulers` | `forks/combine-schedulers` | TCA, swift-dependencies -> `github.com/jacobcxdev/combine-schedulers` |
| `swift-case-paths` | `forks/swift-case-paths` | TCA, swift-navigation -> `github.com/pointfreeco/swift-case-paths` |
| `swift-identified-collections` | `forks/swift-identified-collections` | TCA, swift-sharing -> `github.com/pointfreeco/swift-identified-collections` |
| `swift-navigation` | `forks/swift-navigation` | TCA -> `github.com/jacobcxdev/swift-navigation` |
| `swift-clocks` | `forks/swift-clocks` | swift-dependencies -> `github.com/jacobcxdev/swift-clocks` |

**Root cause:** The fork Package.swift files still reference other forks via their GitHub remote URLs (e.g., `https://github.com/jacobcxdev/swift-dependencies`), while the root Package.swift declares them as local path dependencies. SPM sees these as two different sources for the same identity.

**Mitigation options (ordered by preference):**
1. **Accept warnings for now** -- they are non-blocking today and this is a fork-heavy dev environment. Monitor SwiftPM release notes for when the escalation happens.
2. **Edit fork Package.swift files** to use local path references when resolved from within this workspace. This is fragile and breaks standalone fork builds.
3. **Use SPM package-collection overrides** (not yet available as a stable feature).

**Recommendation:** Option 1. The warnings are cosmetic for now. Document the risk in Phase 7 plans and create a standing TODO to address before SwiftPM escalates to errors.

### fuse-app Identity Conflicts (3 warnings)

fuse-app has 3 identity conflicts, all involving `skip-android-bridge` and `skip-ui` being declared both as local paths and pulled transitively via `skip-fuse-ui`. Same root cause, same mitigation.

### fuse-library Unused Dependencies (6 warnings)

These dependencies are declared but not consumed by any target:

1. `grdb.swift` -- present for transitive resolution only; SQLiteData test targets use `sqlite-data` which depends on GRDB internally
2. `skip-android-bridge` -- wired for transitive resolution (Skip sandbox compatibility)
3. `swift-clocks` -- transitive dep of swift-dependencies
4. `swift-navigation` -- transitive dep of TCA
5. `swift-perception` -- transitive dep of TCA
6. `swift-snapshot-testing` -- transitive dep of swift-structured-queries

These are intentionally present (comment in Package.swift says "wired for transitive resolution -- Skip sandbox compatible via useLocalPackage"). However, if Phase 7 adds targets that directly import any of these (e.g., a SnapshotTesting integration target), the warnings will resolve naturally.

## Android Build Status

### fuse-app: Stale Android Build

The fuse-app `.build/Android/` directory exists with contents dated **Feb 20**, suggesting a prior android build succeeded. However:

- The fuse-app currently uses `SkipFuseUI`, `SkipUI`, and `SkipAndroidBridge` -- a minimal set
- Phase 7 will add `ComposableArchitecture`, `Dependencies`, `Sharing`, `SQLiteData`, and potentially more
- **No evidence of a recent `skip android build` from fuse-app with the TCA dependency set**
- The fuse-app's current sources (`FuseApp.swift`, `ViewModel.swift`, `ContentView.swift`) are still the Skip template -- no TCA code has been added yet

**Risk:** The first `skip android build` after adding TCA dependencies will be the real test. Skip's Gradle plugin must transpile/bridge all new Swift modules. This is where most Android-specific linker and bridge failures will surface.

### fuse-library: Skip Sandbox Constraint

Per project decision log, Skip's sandbox only resolves dependencies used by targets. The 6 unused deps listed above are kept for transitive resolution but may cause issues during `skip test` if Skip tries to resolve them. Phase 6 already confirmed `skip test` passes 21/21, but adding more targets will change the resolution surface.

## Linker Concerns

### HIGH: GRDBSQLite System Library on Android

GRDB uses a `.systemLibrary` target (`GRDBSQLite`) with a module map that declares `link "sqlite3"`. This expects `libsqlite3` to be available as a system library.

**Module map contents:**
```
module GRDBSQLite [system] {
    header "shim.h"
    link "sqlite3"
    export *
}
```

**Risks on Android:**
1. Android NDK does not ship `libsqlite3.so` as a linkable library in the sysroot. The Android framework has SQLite, but it is accessed via Java APIs, not C linkage.
2. Skip's Swift-on-Android toolchain may or may not bundle a SQLite library. If not, the linker will fail with `ld: library not found for -lsqlite3`.
3. The GRDB fork may need a conditional target that bundles SQLite source (like GRDB's `CSQLite` target used in CocoaPods) or links against a pre-built Android `.so`.

**Mitigation:** Before Phase 7 Android builds, verify:
```bash
# Check if Skip's Android SDK includes sqlite3
find $(skip android sdk path) -name "libsqlite3*" -o -name "sqlite3.h"
```
If absent, the GRDB fork needs a `#if os(Android)` conditional that either bundles `CSQLite` or links against Android's SQLite via JNI.

### LOW: Duplicate Symbol Risk

With 17 forks all potentially defining similar types (e.g., multiple modules defining `@_exported import` re-exports), there is a theoretical risk of duplicate symbols at link time. However:
- SPM's identity resolution ensures only one version of each package is linked
- The local path overrides guarantee the fork version wins
- No duplicate symbol errors have been observed in Phases 1-6

### LOW: swift-concurrency-extras Not Declared in fuse-library

`swift-concurrency-extras` is not declared as a direct dependency in fuse-library's Package.swift, yet it is used by `sqlite-data` and `swift-composable-architecture` transitively. This is fine for current usage but may cause issues if Phase 7 adds a test target that directly imports `ConcurrencyExtras`.

## Build Time Impact

### Current Baseline

| Operation | Time |
|-----------|------|
| `swift package resolve` (fuse-library) | 14.1s |
| `swift package resolve` (fuse-app) | 4.7s |
| `swift build` (fuse-library, incremental) | 12.4s |
| `.build/` size (fuse-library) | 2.7 GB |
| `.build/` size (fuse-app) | 1.1 GB |

### Projected Impact of Phase 7

Adding 5-8 new targets to fuse-library:
- **Resolution time:** Negligible increase (targets don't add resolution work, only dependencies do)
- **Build time (clean):** Each new test target adds ~2-5s of compilation. Estimate +10-30s for 5-8 targets.
- **Build time (incremental):** Minimal impact -- only changed targets recompile
- **.build/ size:** Each target adds ~50-150 MB of build artifacts. Estimate fuse-library grows to ~3.5-4.0 GB.

Adding TCA dependencies to fuse-app:
- **Resolution time:** Expect ~14-18s (matching fuse-library with similar dependency count)
- **Build time (clean):** First build with TCA will be significant -- ComposableArchitecture alone has ~100 source files. Estimate 60-120s for clean build.
- **Android build time:** Skip transpilation of TCA is the major unknown. The Gradle build for a full TCA app with all forks has never been attempted. Budget 5-15 minutes for first Android build.

### Disk Space Concern

Combined `.build/` directories already consume 3.8 GB. After Phase 7:
- fuse-library: ~4.0 GB
- fuse-app: ~3.0-4.0 GB (with full TCA)
- Total: ~7-8 GB

**Recommendation:** Add `make clean` target and document the disk space requirement.

## Makefile Updates Needed

### Current Targets (all work)

`build`, `test`, `test-filter`, `android-build`, `skip-test`, `skip-verify`, `status`, `push-all`, `pull-all`, `diff-all`, `branch-all`

### Missing Targets for Phase 7

1. **`clean`** -- Delete `.build/` directories. Critical for reproducible CI builds.
   ```makefile
   clean:
   	cd $(EXAMPLE_DIR) && swift package clean
   ```

2. **`test-all`** -- Run all test targets (not just the default). Currently `make test` runs all tests, but Phase 7 may need selective execution.

3. **`android-test`** -- Listed in `.PHONY` but not defined. Should be:
   ```makefile
   android-test:
   	cd $(EXAMPLE_DIR) && skip test
   ```

4. **`build-app` / `test-app`** -- Convenience aliases for `EXAMPLE=fuse-app make build/test`. Phase 7's fuse-app rebuild will need frequent use.

5. **`verify-all`** -- Run `skip verify --fix` on both example projects sequentially.

### Existing Issue: `android-test` in .PHONY but Undefined

Line 4 of the Makefile declares `android-test` as a phony target, but no rule is defined for it. Running `make android-test` will silently succeed (doing nothing) rather than failing explicitly. This should be fixed before Phase 7.

## Recommendations

### Before Phase 7 Execution

1. **[P0] Wire fuse-app Package.swift for TCA.** Add all 15 fork path dependencies (matching fuse-library's set) plus `ComposableArchitecture`, `Dependencies`, `Sharing`, `SQLiteData` product references to the FuseApp target. Without this, no TCA code can be written in fuse-app.

2. **[P0] Verify SQLite availability on Android.** Run `skip android sdk path` and search for `libsqlite3`. If absent, the GRDB fork needs an Android-specific SQLite bundling strategy before any database features work in the fuse-app on Android.

3. **[P1] Fix `android-test` Makefile target.** Add the missing rule body to prevent silent no-ops during validation.

4. **[P1] Add `clean` Makefile target.** Essential for reproducible builds during integration testing.

5. **[P1] Run `skip android build` from fuse-app** after wiring TCA dependencies. This will be the first real integration test and will likely surface new issues.

### During Phase 7 Execution

6. **[P2] Monitor SPM identity conflict warnings.** Currently 41 warnings for fuse-library, 3 for fuse-app. These will increase as fuse-app gains more fork dependencies. Track SwiftPM release notes for the warning-to-error escalation timeline.

7. **[P2] Budget disk space.** Phase 7 will push combined `.build/` to ~8 GB. Ensure CI runners (if any) have adequate storage.

8. **[P2] Consider `swift-concurrency-extras` as explicit dependency** if any Phase 7 test target imports it directly.

### Post Phase 7

9. **[P3] Evaluate fork Package.swift harmonization.** Long-term, each fork's Package.swift could use conditional local-path references (via `Context.environment`) to eliminate identity conflicts. This is a substantial effort and should only be pursued if SwiftPM escalates warnings to errors.
