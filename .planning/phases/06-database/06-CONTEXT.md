# Phase 6: Database & Queries — Context

**Created:** 2026-02-22
**Phase goal:** StructuredQueries type-safe query building and GRDB/SQLiteData work on Android with observation-driven view updates
**Requirements:** SQL-01..SQL-15, SD-01..SD-12 (27 total)

## Decisions

### D1: Fork state — all 3 forks exist

All three database forks are already in `forks/`:
- `GRDB.swift` — 8 files with Android conditionals
- `sqlite-data` — 6 files with Android conditionals, already adds skip-bridge/skip-android-bridge/swift-jni on Android
- `swift-structured-queries` — pure Swift, no Android-specific changes needed at Package level

**Decision:** Leverage existing fork work. Research must audit what's already done vs what's still needed before planning new changes.

### D2: Branch naming divergence

sqlite-data's Package.swift references `flote/service-app` branches on jacobcxdev forks, not `dev/swift-crossplatform`.

**Decision:** Research must determine whether `flote/service-app` and `dev/swift-crossplatform` are the same or divergent branches. If divergent, a branch alignment task is needed in Wave 1 before any code changes.

### D3: Macro compilation is a non-issue

`@Table`, `@Column`, `@Selection`, `@FetchAll`, `@FetchOne`, `@Fetch`, and `#sql()` are Swift macros (SwiftSyntax-based). Macro expansion is a preprocessor concern — it runs at compile time on the host, not at runtime on Android. Already validated in earlier phases (`@Observable`, `@CasePathable`, `@Reducer` all work).

**Decision:** Macros are not a risk item. Only flag if a macro's *expanded code* contains platform-specific APIs.

### D4: iOS/Android observation parity is required

`@FetchAll`/`@FetchOne` observation macros must trigger view updates on Android the same way they do on iOS. Whether this goes through GRDB's ValueObservation, Swift Observation, or the Phase 1 bridge — the end result must match.

**Decision:** Research must determine the observation mechanism and ensure it flows through Android's observation bridge. TCA-mediated observation is not an acceptable substitute if the iOS path works directly in SwiftUI views.

### D5: SQLite provider strategy — research decides

GRDB uses `.systemLibrary` for SQLite (expects system-provided `libsqlite3`). Options:
- GRDB links against Android system SQLite (if available via Swift Android SDK)
- GRDB is modified to use skip-sql's SQLite on Android
- GRDB vendors CSQLite with `#if os(Android)` conditional

**Decision:** Research evaluates all three approaches. Key constraint: if skip-sql is also in the dependency graph, there must not be duplicate SQLite symbols.

### D6: Database file location — research decides

iOS uses `Application Support` / `Documents`. Android uses `/data/data/<package>/databases/`. Skip may or may not translate `FileManager` paths.

**Decision:** Research investigates how Skip handles file paths (building on Phase 4's FileStorageKey Android enablement pattern). The `defaultDatabase()` path must resolve correctly on both platforms without app-level configuration.

### D7: Test strategy — match upstream patterns

StructuredQueries (query builder) and SQLiteData (database executor) may have different test approaches upstream.

**Decision:** Research checks Point-Free's upstream test patterns for both libraries and recommends matching patterns. Tests go in `examples/fuse-library/` following the established convention (new test targets in Package.swift).

## Research Items

These must be investigated before planning. Ordered by criticality.

### R1: SQLite C library on Android (Critical)

**Question:** How does GRDB's `.systemLibrary` SQLite dependency resolve on Android?
**Investigate:**
- Does the Swift Android SDK provide a system SQLite?
- Does skip-sql vendor SQLite, and if so, how?
- What does GRDB's existing Android work (8 files) already handle?
- Risk of duplicate SQLite symbols if both GRDB and skip-sql are in the dependency graph

### R2: Observation macro bridging (Critical)

**Question:** How do `@FetchAll`/`@FetchOne` trigger SwiftUI view updates, and does this path work on Android?
**Investigate:**
- Do they use GRDB's `ValueObservation` -> Combine/async publisher?
- Do they use Swift native `@Observable` / `withObservationTracking`?
- Does sqlite-data's existing Android code in `FetchAll.swift`, `FetchOne.swift`, `Fetch.swift` already bridge this?
- What does `FetchKey+SwiftUI.swift` do on Android?

### R3: GRDB concurrency model on Android (Important)

**Question:** Does GRDB's `DatabasePool`/`DatabaseQueue` serial queue work on Android?
**Investigate:**
- GRDB uses `DispatchQueueActor` (has Android conditional) — what's the fallback?
- Does `libdispatch` work on Android via the Swift SDK, or is there a custom executor?
- Are there deadlock risks with GRDB's queue + Swift concurrency on Android?

### R4: Prior Android work audit (Important)

**Question:** What Android enablement already exists in the GRDB and sqlite-data forks?
**Investigate:**
- Read all 8 GRDB files with Android conditionals
- Read all 6 sqlite-data files with Android conditionals
- Document what's done, what's stubbed, what's broken
- Identify remaining gaps between existing work and SD-01..SD-12 requirements

### R5: Database file location (Important)

**Question:** How does SQLiteData resolve database file paths on Android?
**Investigate:**
- How did Phase 4's `FileStorageKey` resolve paths on Android?
- Does Skip translate `FileManager.default.urls(for:in:)` to Android paths?
- Does sqlite-data's existing Android code handle path resolution?

### R6: Test patterns (Moderate)

**Question:** How does Point-Free test StructuredQueries and SQLiteData upstream?
**Investigate:**
- SQL string validation vs database execution for StructuredQueries
- In-memory vs on-disk SQLite for SQLiteData tests
- Test support libraries (`StructuredQueriesTestSupport`, `SQLiteDataTestSupport`)

### R7: Perception usage in sqlite-data (Moderate)

**Question:** Does sqlite-data's use of Perception work with the Android passthrough?
**Investigate:**
- What Perception APIs does sqlite-data use?
- Are they covered by the `PerceptionRegistrar` -> `ObservationRegistrar` passthrough?
- Any Perception features that bypass the bridge?

### R8: OpenCombine / async observation path (Moderate)

**Question:** Does GRDB's `ValueObservation` use Combine publishers on Android?
**Investigate:**
- Does GRDB conditionally use OpenCombine or async sequences on non-Apple platforms?
- If Combine-only, does the project already have an OpenCombine dependency?
- sqlite-data may use async observation instead — check which path

## Deferred Ideas

None — all discussion items are within Phase 6 scope.

## Constraints from Earlier Phases

- **Phase 1 bridge is the observation foundation.** Any database observation must ultimately trigger recomposition through the Phase 1 bridge on Android.
- **All fork changes gate behind `#if os(Android)` or `#if SKIP_BRIDGE`.** No iOS regressions.
- **fuse-library is the test host.** New test targets go in `examples/fuse-library/Package.swift`.
- **17 forks must all compile.** Adding database forks to fuse-library must not break existing compilation.
- **Macro expansion is host-side.** Only the expanded code runs on Android.
