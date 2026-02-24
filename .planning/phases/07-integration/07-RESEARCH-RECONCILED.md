# Phase 7: Integration Testing & Documentation — Reconciled Research

**Created:** 2026-02-22
**Sources:** Initial 07-RESEARCH.md + 10 deep-dive agents (R1–R10)
**Mode:** Ecosystem research — HOW to implement, not WHETHER

---

## Corrections to Initial Research

| Item | Initial Claim | Corrected Finding | Source |
|------|--------------|-------------------|--------|
| Test count | "108 tests" (from STATE.md) | **226 test methods** across 20 targets (146 XCTest + 80 Swift Testing) | R6 |
| Memory measurement | `ProcessInfo.processInfo.physicalMemory` suggested | **Useless** — returns total system RAM. Use `mach_task_basic_info` (Darwin) / `/proc/self/status` VmRSS (Android) | R3 |
| Fork commit count | Rough estimates per fork | **162 total commits ahead** across all 17 forks. Heaviest: TCA (39), swift-navigation (27), swift-sharing (26), sqlite-data (16) | R5 |
| `skip test` for bridge | Implied viable for bridge testing | **Cannot test bridge** — Robolectric runs transpiled Kotlin, not native Swift. Only `skip android test` exercises JNI/observation bridge | R7 |
| Bridge failure mode | CLAUDE.md says "fatalError" | **Silent no-op** — `BridgeObservationSupport.Java_initPeer()` returns nil; closures stay null in Lite mode. Fuse mode calls `fatalError` only on `nativeEnable()` failure | R7 |
| XCTest.measure on Android | Not discussed | **Unavailable** — transpiled to JUnit which has no equivalent. Use `ContinuousClock` instead | R3 |
| GRDB upstream branch | Assumed `origin/main` | Uses **`origin/master`** (only fork that differs) | R5 |

---

## Unified Blocker Assessment

### P0 — Must resolve before Phase 7 execution

| # | Blocker | Impact | Mitigation | Source |
|---|---------|--------|------------|--------|
| B1 | **fuse-app missing TCA fork dependencies** | Cannot write any TCA code in fuse-app. Current Package.swift has only 2 fork deps; needs all 15+ | Add path dependencies matching fuse-library's set + product references to FuseApp target | R9 |
| B2 | **`@Shared(.fileStorage)` silently no-ops on Android** | File change monitoring disabled — `DispatchSource` replacement is compile-time stub only. External file changes invisible until manual read | Document as known limitation; test must assert write-then-read works even if change notification doesn't fire | R8 |
| B3 | **`@Shared(.appStorage)` subscription no-op on Android** | KVO-based UserDefaults subscription excluded. SharedPreferences changes invisible to app until next manual read | Same as B2 — test write/read path, document notification gap | R8 |
| B4 | **GRDB `link "sqlite3"` will fail on Android NDK** | Android NDK doesn't ship `libsqlite3.so` as linkable library. Linker will fail with `library not found for -lsqlite3` | Verify via `skip android sdk path`; if absent, GRDB fork needs `#if os(Android)` conditional bundling CSQLite or JNI path | R9 |
| B5 | **TestStore non-determinism on Android** | `useMainSerialExecutor` fully disabled. `effectDidSubscribe` AsyncStream fallback handles sync but timing characteristics differ — concurrent effect ordering may vary | Use `store.timeout = 5_000_000_000` for emulator; avoid assertions on concurrent effect ordering | R1, R8 |

### P1 — Should resolve during Phase 7

| # | Issue | Impact | Mitigation | Source |
|---|-------|--------|------------|--------|
| P1-1 | **41 SPM identity conflicts** (fuse-library) | Non-blocking today but SwiftPM will escalate to errors in future versions | Accept warnings; document risk; create standing TODO | R9 |
| P1-2 | **Makefile `android-test` undefined** | Declared in `.PHONY` but no rule body — `make android-test` silently succeeds doing nothing | Add rule body: `cd $(EXAMPLE_DIR) && skip test` | R9 |
| P1-3 | **GRDB/sqlite-data use `import Combine` without `OpenCombineShim`** | Will fail to compile on Android where Foundation Combine is unavailable | Needs conditional `#if canImport(Combine)` / `import OpenCombineShim` guard | R8 |
| P1-4 | **`swiftThreadingFatal` stub fragility** | Required for `libswiftObservation.so` to load until Swift 6.3 ([swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890)). If Swift runtime changes, stub must be updated | Monitor Swift 6.3 release; remove stub once upstream fix ships | R8 |
| P1-5 | **ObservationTrackingTests redundant** | 7 test methods are exact duplicates of ObservationTests | Remove target from Package.swift; delete `Tests/ObservationTrackingTests/` (226 → 219 unique tests) | R6 |
| P1-6 | **Missing `clean` Makefile target** | Combined `.build/` already 3.8 GB, will grow to ~8 GB. No way to reset for reproducible builds | Add `clean` target | R9 |

### P2 — Track but non-blocking

| # | Issue | Source |
|---|-------|--------|
| P2-1 | 6 unused fuse-library dependencies (intentional for transitive resolution) | R9 |
| P2-2 | Stale fuse-app Android build (Feb 20, never tested with TCA) | R9 |
| P2-3 | `swift-concurrency-extras` not declared as direct dep in fuse-library | R9 |
| P2-4 | `ObservedObject` is thin shim on Android (no change observation) | R8 |
| P2-5 | `TextState` renders plain strings only on Android (all modifiers stripped) | R8 |
| P2-6 | 30+ SwiftUI binding/animation extensions excluded on Android | R8 |
| P2-7 | JNI `try!` force-unwraps in bridge code — crash on Java exception | R8 |

---

## Revised Standard Stack

### TestStore Infrastructure (TEST-01..TEST-09)

**No changes from initial research.** TCA's built-in `TestStore` with `effectDidSubscribe` fallback is the correct approach.

**New detail from R1:** 5 specific divergence points mapped in TestStore.swift (lines 477, 558, 654, 1006, 2580). The `effectDidSubscribe` mechanism works via two yield points:
1. `.none` effects: yields immediately (synchronous path)
2. `.publisher`/`.run` effects: yields after `Task.megaYield()` inside `receiveSubscription`

**Existing coverage:** AndroidParityTests.swift has 17 tests covering 6 core effect types. 4 gaps identified for Phase 7:
- Chained effects (effect that sends action that produces another effect)
- `cancelInFlight` with rapid re-sends
- Long-running effect + `finish()` timeout
- Non-exhaustive `receive` with `.off` exhaustivity

### Observation Bridge Testing (TEST-10)

**Revised approach from R2 + R7:**

The bridge spans 3 files, all behind `#if SKIP_BRIDGE` (not compilable on macOS). Testing strategy must be **two-tier**:

| Tier | Platform | What's Tested | How |
|------|----------|--------------|-----|
| Tier 1 (macOS) | `swift test` | Observation contract via `ObservationVerifier` | Already validated by 19 ObservationTests — property tracking, nesting, coalescing |
| Tier 2 (Android) | `skip android test` | Full JNI bridge + Compose recomposition | Use `diagnosticsEnabled`/`diagnosticsHandler` API for programmatic recomposition counting |

**Critical:** `skip test` (Robolectric) **cannot** test Tier 2. Must use `skip android test` with `--bridge` flag.

**Diagnostics API** (from R2):
```swift
ObservationRecording.diagnosticsEnabled = true
ObservationRecording.diagnosticsHandler = { closureCount, elapsed in
    // closureCount = number of replayed property accesses
    // elapsed = time for withObservationTracking replay
}
```

### Stress Testing (TEST-11)

**Revised from R3:**

Two tests per D10:

**Test A — Store throughput:**
- `Store.send()` is synchronous for `.none` reducers (~150ns per send)
- 5,000 iterations recommended (completes <5s on Android, surfaces linear growth)
- Use `ContinuousClock` for timing (NOT `XCTest.measure` — unavailable on Android)
- Memory: `mach_task_basic_info` (Darwin), `/proc/self/status` VmRSS (Android)
- Assert: bounded memory growth <50 MB over baseline

**Test B — Observation pipeline:**
- `withObservationTracking` fires 1:1 per mutation when resubscribed each cycle (no coalescing)
- Test rapid mutations with tracking subscription active
- Assert: no crashes, bounded memory, observation count matches mutation count

### Fuse-App Showcase (TEST-12)

**Significantly revised from R4 + R10:**

**Current state:** fuse-app is 100% Skip template (4 files, zero TCA code).

**Scope recommendation (R10):** Cap at 5-6 critical integration patterns rather than "every non-deprecated API" (D1). R10 estimates TEST-12 as "Very High" complexity — the single largest risk in Phase 7.

**Proposed modules (R4, trimmed by R10):**
1. **CounterFeature** — Store, send, state assertion, effect
2. **TodosFeature** — IdentifiedArray, forEach, child composition
3. **ContactsFeature** — NavigationStack, path-based routing, presentation
4. **SettingsFeature** — @Shared persistence, dependency injection
5. **TimerFeature** — Long-running effects, cancellation
6. **DatabaseFeature** — SQLiteData + StructuredQueries integration (hybrid: isolated tab + app-wide DI)
7. **AppFeature** — Tab coordinator composing all features

**Build order:** SharedModels → Counter → Todos → Settings → Timer → Contacts → Database → App

**Package.swift prerequisite (B1):** Must wire all 15+ fork path dependencies before any TCA code.

### Fork Documentation (DOC-01)

**From R5:**

- 162 total commits across 17 forks, 3 ecosystems (Point-Free 13, Skip 2, Database 2)
- GRDB is anomalous: 1 commit but 85 files changed (+13,871/-1,378) — monolithic Android patch
- `swift-custom-dump` is most depended-upon fork (7 dependents)
- 5 HIGH rebase risk forks: swift-sharing, swift-navigation, sqlite-data, TCA, GRDB

**Change classification:**
| Category | Count | Description |
|----------|-------|-------------|
| Upstreamable | 6 | Pure platform extensions, no fork-specific logic |
| Fork-only | 6 | Deep architectural changes for Android bridge |
| Conditional | 5 | `#if os(Android)` guards that could upstream with review |

**Deliverable:** `docs/FORKS.md` with per-fork table, Mermaid dependency graph (6 layers), upstream PR candidate list, rebase risk assessment.

---

## Architecture Patterns

### Test Organisation (from R6)

**No reorganisation needed.** 20 targets already align to feature areas. Key metrics:

| Metric | Value |
|--------|-------|
| Total test methods | 226 (146 XCTest + 80 Swift Testing) |
| Test targets | 20 (→ 19 after removing redundant ObservationTrackingTests) |
| Wall-clock time | ~25s (14s compilation + 11s execution) |
| Execution time (Swift Testing) | 0.13s for 80 tests |
| Slowest suite | EffectTests (1.56s — async effect scheduling) |

**Phase 7 tests go in fuse-app**, not fuse-library. This preserves the dual-test-focus: library isolation (existing 219) + app integration (new TEST-*).

### Android Test Execution (from R7)

Two paths serve different purposes:

| Path | Command | Use For |
|------|---------|---------|
| Robolectric | `skip test` | Kotlin transpilation parity, UI layout, non-bridge logic |
| Emulator | `skip android test` | Bridge testing, JNI, observation, native Swift on Android |

**Emulator config:** Two installed (`emulator-36-medium_phone`). No explicit timeout in Gradle; default 10-min per-test applies. Override via `skip.yml` if stress tests exceed.

**Deferred tests (from Phase 1):**
| Test | Automatable? | Method |
|------|-------------|--------|
| HT-1: App launches, recomposition stable | Yes | `skip android test` + diagnostics handler |
| HT-2: UI renders correctly | Manual | Visual inspection via screenshot |
| HT-3: Android build succeeds | Yes | `skip android build` exit code |
| HT-4: Compose recomposition not infinite | Yes | Diagnostics handler count assertion |
| HT-5: JNI bridge loads | Architecture-verified | `nativeEnable()` success = bridge loaded |

---

## Don't Hand-Roll

1. **TestStore** — use TCA's built-in, not custom test harness
2. **Observation tracking** — use `ObservationVerifier` (macOS) and diagnostics API (Android)
3. **Memory measurement** — use platform-specific APIs (`mach_task_basic_info` / `/proc/self/status`), NOT `ProcessInfo.processInfo.physicalMemory`
4. **Fork metadata extraction** — use `git log`, `git rev-list`, `git diff --stat` commands, not manual counting
5. **Test timing** — use `ContinuousClock`, not `XCTest.measure` (unavailable on Android)
6. **Dependency graph** — use `swift package show-dependencies --format json` + transform, not manual tracing
7. **Effect synchronisation on Android** — rely on `effectDidSubscribe` AsyncStream, don't build custom sync

---

## Common Pitfalls (Merged & Deduplicated)

| # | Pitfall | Severity | Source |
|---|---------|----------|--------|
| P1 | Using `skip test` to validate bridge/JNI functionality — Robolectric can't test native Swift | HIGH | R7 |
| P2 | Asserting concurrent effect ordering on Android — `effectDidSubscribe` doesn't guarantee order like `MainSerialExecutor` | HIGH | R1 |
| P3 | Using `ProcessInfo.processInfo.physicalMemory` for memory measurement — returns system total, not process RSS | HIGH | R3 |
| P4 | Using `XCTest.measure {}` in tests that must run on Android — unavailable in transpiled JUnit | MEDIUM | R3 |
| P5 | Assuming `@Shared(.fileStorage)` change notifications work on Android — they don't (silent no-op) | HIGH | R8 |
| P6 | Assuming `@Shared(.appStorage)` subscriptions work on Android — KVO excluded, changes invisible | HIGH | R8 |
| P7 | Testing >60s stress tests without Gradle timeout config — default 10-min is safe but CI runners may differ | LOW | R3, R7 |
| P8 | Referencing `ObservedObject` observation on Android — it's a thin shim with no change tracking | MEDIUM | R8 |
| P9 | Expecting `TextState` to render attributed strings on Android — plain text only, all modifiers stripped | LOW | R8 |
| P10 | Forgetting `store.timeout` increase for emulator tests — default may be too short for cold-start Android | MEDIUM | R1 |
| P11 | Building GRDB for Android without bundled SQLite — NDK doesn't ship `libsqlite3.so` | HIGH | R9 |
| P12 | Running `make android-test` expecting test execution — rule body is missing, silently no-ops | MEDIUM | R9 |

---

## Conditional Compilation Landscape (from R8)

| Guard | Count | Purpose |
|-------|-------|---------|
| `#if os(Android)` | 36 | Android-specific code paths |
| `#if !os(Android)` | 42 | iOS/macOS-only exclusions |
| `#if SKIP_BRIDGE` | 2 | Bridge-level observation (skip-android-bridge only) |
| `#if canImport(SwiftUI) && !os(Android)` | 8 | SwiftUI property wrappers/extensions |

Total: **88 conditional compilation guards** across all forks.

---

## Plan Structure Recommendation (from R10)

| Plan | Scope | Est. Time | Dependencies |
|------|-------|-----------|-------------|
| **07-01** | TestStore validation (TEST-01..TEST-09) | ~10 min | None |
| **07-02** | Android emulator integration (TEST-10, TEST-11, deferred HT-*) | ~25 min | 07-01 |
| **07-03** | Fuse-app showcase rebuild (TEST-12) | ~30 min | 07-01 (TestStore patterns inform showcase) |
| **07-04** | Fork documentation (DOC-01) | ~15 min | None (parallel with 07-01..03) |

**Critical path:** 07-01 → 07-02 → 07-03 ≈ 65 min. 07-04 runs in parallel.

**Key risk:** TEST-12/D1 scope. Cap showcase at demonstrating requirements already validated in Phases 1-6, not attempting exhaustive API enumeration of 17 forks.

---

## Cross-Cutting Findings

### Design Documentation Mismatch (R7)
CLAUDE.md states bridge failures cause `fatalError`. Actual behaviour:
- **Fuse mode:** `nativeEnable()` failure → `fatalError` (correct for load-bearing bridge)
- **Lite mode:** closures stay `nil`, optional chaining makes bridge a harmless no-op

**Action:** Update CLAUDE.md to clarify the dual behaviour.

### Test Count Correction (R6)
All project state documents referencing "108 tests" should be updated to **226 test methods** (or 219 after removing redundant ObservationTrackingTests).

### Build Performance Baseline (R9)
| Metric | fuse-library | fuse-app |
|--------|-------------|----------|
| `swift package resolve` | 14.1s | 4.7s |
| Incremental build | 12.4s | N/A (stale) |
| `.build/` size | 2.7 GB | 1.1 GB |

**Post-Phase 7 projection:** Combined ~8 GB. First fuse-app clean build with TCA: 60-120s. First Android transpilation: 5-15 min.

---

## Research File Index

| File | Lines | Domain | Key Finding |
|------|-------|--------|-------------|
| R1-teststore-android.md | 294 | TestStore | 5 divergence points, effectDidSubscribe sound, 4 coverage gaps |
| R2-observation-bridge.md | 330 | Bridge | #if SKIP_BRIDGE gate, diagnostics API, two-tier test strategy |
| R3-stress-testing.md | 389 | Stress | Store.send() synchronous, 5k iterations, ContinuousClock not measure |
| R4-fuse-app-showcase.md | 536 | Showcase | 8 feature modules, 184/184 req coverage map, build order |
| R5-fork-documentation.md | 587 | Forks | 162 commits, 3 ecosystems, 5 HIGH rebase risk, Mermaid graph |
| R6-test-reorganisation.md | 240 | Tests | 226 methods, ObservationTrackingTests redundant, no reorg needed |
| R7-android-emulator.md | 387 | Emulator | skip test ≠ bridge test, design doc mismatch, 3/5 HT automatable |
| R8-parity-gaps.md | 227 | Parity | 88 guards, 3 P0 (Shared no-ops + TestStore), 5 P1 |
| R9-build-packaging.md | 232 | Build | 41 SPM conflicts, missing fuse-app deps, sqlite3 linker risk |
| R10-scope-risks.md | 193 | Scope | TEST-12 is highest risk, 4-plan split, ~65-75 min critical path |

---

*Reconciliation completed: 2026-02-22*
*Data sources: 10 parallel research agents, initial 07-RESEARCH.md, cross-referenced against codebase*
