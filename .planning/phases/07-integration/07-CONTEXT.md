# Phase 7: Integration Testing & Documentation — Context

**Created:** 2026-02-22
**Phase goal:** A complete TCA app runs on both iOS and Android; all forks are documented with change rationale and upstream PR candidates
**Requirements:** TEST-01..TEST-12, DOC-01 (13 total)

## Decisions

### D1: Fuse-app is a comprehensive API showcase, not a minimal proof

The fuse-app must demonstrate **every non-deprecated, current, public API** of TCA and SQLiteData running on both platforms. This means every type of navigation, presentation, action, effect, dependency, persistence, and database interaction.

**Decision:** The app is a full reference architecture with a README. It must be navigable by a user, with features reachable through real navigation (not a hidden test harness). The scope is determined by exhaustive API surface coverage of all 17 forks.

### D2: Modular feature targets following TCA best practice

Features are self-contained SPM targets composed by Package.swift. Each feature is granular and modular, using components where possible, following TCA's composition patterns.

**Decision:**
- **Pure domain features** (reducers, models, shared logic) live in `examples/fuse-library/Sources/` — reusable across example apps.
- **App-specific composition/UI** (root app, tab coordinator, feature wiring) lives in `examples/fuse-app/Sources/`.
- Follow the `/pfw-composable-architecture` skill for canonical patterns.

### D3: Existing example templates preserved, tests reorganised

The `examples/*` directories were created with `skip create` and follow Skip's recommended template format. These templates are kept.

**Decision:**
- Skip template structure (project layout, configuration) is preserved.
- Code added by previous phases may be kept, refactored, or replaced on a case-by-case basis, guided by `/pfw-*` skills and application architecture.
- The existing 108 fuse-library tests are **reorganised to match the new modular feature structure** — moved into feature-aligned test targets for consistency.

### D4: Dual test focus — library isolation + app integration

**Decision:**
- **fuse-library tests** validate APIs in isolation (existing approach, reorganised into feature-aligned targets).
- **fuse-app tests** validate feature composition and integration — TestStore tests for each feature reducer, plus integration tests that exercise cross-feature flows.
- Both test suites must pass on macOS. App-level tests also validated on Android emulator.

### D5: README serves both evaluators and developers

**Decision:** The fuse-app README has two sections:
1. **Evaluator overview** — what works, what doesn't, platform differences, decision criteria for adoption.
2. **Developer guide** — how to structure a cross-platform TCA app, code pointers, "copy this pattern" guidance, and how to run on both platforms.

### D6: Android emulator tests — automate where possible, hybrid UI verification

**Decision:**
- **Automated:** Everything `skip test` can cover runs as automated test cases (data flow, state management, effect execution, compilation of all forks).
- **Manual:** UI rendering correctness (navigation renders, sheets present, alerts display) verified visually on emulator.
- **Hybrid:** Programmatic assertions for data flow (state → view update), visual verification for rendering correctness only.
- **Evidence bar:** Test logs only (`skip test` output showing pass/fail). No screenshots or video required.

### D7: Emulator tests run against both dedicated targets and fuse-app

**Decision:**
- **Dedicated test targets** for automated assertions (isolated, deterministic, fast).
- **fuse-app** for visual/manual verification (proves the real app works end-to-end).
- Both must pass for Phase 7 to be complete.

### D8: Deferred Phase 1 human tests — automate what's possible

The 5 deferred tests from Phase 1 (single recomposition, nested independence, ViewModifier observation, fatal error on bridge failure, 14-fork compilation):

**Decision:**
- **Automatable:** Recomposition count verification, nested view independence, fork compilation → write as `skip test` cases.
- **Manual:** Bridge failure fatal error (requires crashing the app intentionally), ViewModifier observation (may need UI hierarchy inspection) → document as manual verification steps with expected outcomes.

### D9: MainSerialExecutor fallback — comprehensive testing

The `effectDidSubscribe` AsyncStream fallback is the intended Android path (no `MainSerialExecutor` on Android).

**Decision:** Test all effect types (`Effect.run`, `.merge`, `.concatenate`, `.cancellable`, `.cancel`) to confirm the fallback handles each correctly on Android. This goes beyond a smoke test — each effect type gets its own assertion.

### D10: Stress tests — mixed workload on both platforms, two separate tests

**Decision:**
- **Test 1: Store/Reducer throughput** — Pure state management stress. Rapid-fire actions, concurrent effects, no view layer. Must complete without crash and with bounded memory.
- **Test 2: Observation pipeline under load** — Mutation → observation → view update trigger. Verifies coalescing under load. Must complete without crash and with bounded memory.
- **Both tests run on macOS first** (fast iteration), then validated on Android emulator.
- **Mixed workload shape:** Combination of rapid-fire actions, concurrent effects, and observation cycles simulating realistic heavy use.
- **Stability = no crashes + bounded memory** (no unbounded growth during the burst).

### D11: FORKS.md — structured sections with dependency graph and PR drafts

**Decision:**
- **Location:** `docs/FORKS.md` (alongside existing Skip reference docs).
- **Format:** Each fork gets its own H2 section with subsections: upstream version, key changes, rationale, upstream PR candidates.
- **Upstream PR assessment:** Every commit/change tagged as upstreamable (generic improvement), fork-only (Android-specific), or conditional (upstreamable if upstream accepts Android). For upstreamable changes, include a **draft PR description** explaining the change to upstream maintainers.
- **Dependency graph:** Mermaid diagram showing fork → fork relationships, rendered in GitHub markdown.

### D12: Database integration in showcase — research decides approach

Whether the fuse-app demonstrates database features (StructuredQueries/GRDB) alongside TCA persistence, as separate concerns, or integrated, is a tradeoff that requires analysis of the API surface and user experience.

**Decision:** Research phase analyses the tradeoffs of:
1. Both comprehensive integration and isolation (separate tabs/sections).
2. Just integration (database as persistence backend for TCA features).
3. Just isolation (database demo separate from TCA features).

The research recommendation, informed by exhaustive API coverage requirements, determines the final structure.

## Research Items

These must be investigated before planning. Ordered by criticality.

### R1: Full public API surface audit (Critical)

**Question:** What is the complete non-deprecated public API surface of TCA, SQLiteData, StructuredQueries, and every other fork that the showcase must demonstrate?
**Investigate:**
- Enumerate every non-deprecated public type, method, and property across all 17 forks
- Cross-reference against REQUIREMENTS.md to identify coverage gaps
- Group APIs by feature area to inform modular target structure
- Identify APIs that are platform-gated (iOS-only vs cross-platform)

### R2: Existing fuse-app and fuse-library state (Critical)

**Question:** What already exists in both example projects, and what's the delta to reach comprehensive coverage?
**Investigate:**
- Current fuse-app structure, features, and Package.swift targets
- Current fuse-library test targets and what they cover
- What can be kept, what needs refactoring, what's missing
- How the Skip template structure constrains or enables the modular target approach

### R3: Database integration tradeoffs (Important)

**Question:** What's the most effective way to demonstrate database features alongside TCA?
**Investigate:**
- API surface of SQLiteData and StructuredQueries that must be covered
- Whether database observation (@FetchAll/@FetchOne) composes naturally with TCA features
- Whether isolation or integration better demonstrates the full API surface
- Tradeoffs for user navigability of the showcase app

### R4: Android emulator test infrastructure (Important)

**Question:** What `skip test` infrastructure exists and what's needed for the deferred test items?
**Investigate:**
- Current `skip test` capabilities and limitations for assertion-based testing
- How to test recomposition count programmatically on Android
- How to validate observation bridge behaviour in automated tests
- What the MainSerialExecutor fallback test suite looks like for all effect types

### R5: Stress test design patterns (Moderate)

**Question:** How should the two stress tests (Store throughput + observation pipeline) be structured?
**Investigate:**
- TCA's own upstream stress/performance test patterns
- How to measure memory boundedness in a Swift test
- Appropriate mutation counts and concurrent effect loads
- Whether `skip test` supports long-running stress tests on Android

### R6: Fork metadata extraction (Moderate)

**Question:** How to efficiently extract per-fork documentation data?
**Investigate:**
- Git commands to determine upstream version, commits ahead, branch divergence
- Automated extraction of files changed, lines added/removed per fork
- How to classify changes (upstreamable vs fork-only vs conditional)
- Dependency relationships between the 17 forks for Mermaid graph generation

### R7: Test reorganisation strategy (Moderate)

**Question:** How should the existing 108 tests be reorganised into feature-aligned targets?
**Investigate:**
- Current test target structure and what each test validates
- Natural groupings that align with the modular feature target structure
- Whether any tests become redundant once app-level integration tests exist
- Impact on Package.swift complexity and build times

## Deferred Ideas

None — all discussion items are within Phase 7 scope.

## Constraints from Earlier Phases

- **Phase 1 bridge is the observation foundation.** All observation on Android flows through the bridge. Stress tests and integration tests must exercise this path.
- **All fork changes gate behind `#if os(Android)` or `#if SKIP_BRIDGE`.** No iOS regressions.
- **17 forks must all compile.** Adding new feature targets must not break existing compilation.
- **Macro expansion is host-side.** Only the expanded code runs on Android.
- **`skip test` passes 21/21** as of Phase 2. New tests must not regress this.
- **108 existing tests across Phases 1-6.** These are reorganised, not discarded.
- **Pending todos from STATE.md** are incorporated into this phase's requirements (deferred Phase 1 human tests, MainSerialExecutor validation, dismiss/openSettings validation, Android UI rendering validation, database observation wrapper testing, Android build verification).
- **SQLite not in Android sysroot.** The Swift Android SDK does not provide libsqlite3. Database tests on Android require explicit SQLite provisioning (resolved in Phase 6 fork work, must be validated in integration).
