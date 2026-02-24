# R10: Phase 7 Scope & Risk Assessment

**Created:** 2026-02-22
**Purpose:** Identify scope, schedule, and execution risks before Phase 7 planning begins

## Summary

Phase 7 is the most heterogeneous phase in the project. It combines four distinct workstreams that have almost no code overlap: (1) TestStore validation on Android, (2) fuse-app rebuild as comprehensive TCA showcase, (3) stress/integration testing on emulator, and (4) fork documentation. The largest risk is **D1's scope** -- "demonstrate every non-deprecated, current, public API" across 17 forks is an open-ended commitment that could easily consume more time than Phases 3-6 combined. The second risk is **emulator dependency** -- several requirements (TEST-10, TEST-11, deferred Phase 1 human tests) require a running Android emulator, which introduces environment variability and longer iteration cycles compared to the macOS-only `swift test` loop used in all prior phases.

**Recommendation:** Split into 4-5 sub-plans with strict scope gates. Cap the fuse-app showcase at demonstrating requirements already validated in Phases 1-6, not attempting to enumerate the full public API surface of 17 forks.

## Requirement Complexity Assessment

| Req | Description | Complexity | Rationale |
|-----|-------------|------------|-----------|
| TEST-01 | TestStore init on Android | Low | Direct API call, well-understood from Phase 3-5 tests |
| TEST-02 | store.send with state assertion | Low | Core TestStore pattern, widely documented |
| TEST-03 | store.receive for effect actions | Low | Standard TestStore pattern |
| TEST-04 | Exhaustivity .on (default) | Low | Configuration flag test |
| TEST-05 | Exhaustivity .off | Low | Configuration flag test |
| TEST-06 | store.finish() waits for effects | Medium | Requires async effect lifecycle correctness |
| TEST-07 | skipReceivedActions | Low | Convenience API test |
| TEST-08 | Deterministic async without MainSerialExecutor | **High** | No MainSerialExecutor on Android; must validate effectDidSubscribe AsyncStream fallback across all effect types (run, merge, concatenate, cancellable, cancel). This is novel territory -- no prior phase tested this path comprehensively |
| TEST-09 | .dependencies test trait | Low | Standard dependency override pattern |
| TEST-10 | Integration: no infinite recomposition | **High** | Requires Android emulator, observation bridge exercised under real TCA workload, assertion on recomposition count. First emulator-dependent automated test in the project |
| TEST-11 | Stress: >1000 mutations/sec stability | **High** | Two separate tests (D10): Store throughput + observation pipeline. Requires memory boundedness measurement, potentially long-running. Emulator adds latency |
| TEST-12 | fuse-app full TCA showcase | **Very High** | D1 says "every non-deprecated, current, public API." The current fuse-app is a vanilla Skip template (3 files, no TCA, no reducers, no effects). Building a comprehensive TCA showcase from scratch requires: modular feature targets, Package.swift restructuring, reducers for each feature, navigation coordinator, persistence integration, database integration (D12), README (D5). This is an entire app build |
| DOC-01 | FORKS.md documentation | Medium | 17 forks to document. Mechanical (git commands extract metadata) but time-consuming. D11 adds draft PR descriptions and Mermaid dependency graph |

### Complexity Distribution
- Low: 7 requirements (TEST-01..05, TEST-07, TEST-09)
- Medium: 2 requirements (TEST-06, DOC-01)
- High: 3 requirements (TEST-08, TEST-10, TEST-11)
- Very High: 1 requirement (TEST-12)

## Dependency Order

```
Layer 0 (no dependencies):
  TEST-01..TEST-09  -- TestStore validation (macOS-first, then Android)
  DOC-01            -- Fork documentation (independent of all code work)

Layer 1 (depends on Layer 0):
  TEST-10           -- Integration test (needs TestStore working + emulator)
  TEST-11           -- Stress test (needs TestStore working + emulator)

Layer 2 (depends on Layers 0-1):
  TEST-12           -- fuse-app showcase (needs all other TEST-* to inform what to demonstrate)
```

**Critical observation:** TEST-12 logically comes last because the showcase app should demonstrate patterns that are already proven by TEST-01..TEST-11. Building the app first and then discovering TestStore doesn't work on Android would require rework.

**Parallel opportunity:** DOC-01 is entirely independent and can run in parallel with any other work.

## Scope Creep Risks

### Risk 1: D1 -- "Every non-deprecated, current, public API" (CRITICAL)

D1 states the fuse-app must demonstrate "every non-deprecated, current, public API of TCA and SQLiteData." This is the single largest risk in the phase.

**Quantification of the problem:**
- TCA alone has ~35 requirements covering Store, reducers, effects, scoping, bindings, navigation, presentation, testing APIs
- SQLiteData/StructuredQueries has ~27 requirements (SQL-01..SQL-15, SD-01..SD-12)
- Additional forks: CasePaths (8 APIs), IdentifiedCollections (6), CustomDump (5), IssueReporting (4), Sharing (14), Navigation (16), UI patterns (8)
- Total: demonstrating all of these in a navigable app would require roughly **10-15 feature modules**, **20-30 views**, and **10-15 reducers**

**Comparison to prior velocity:** Previous phases averaged 6.5 minutes per plan and produced test files, not application features. Building a full modular TCA app with navigation, persistence, database, and a README is fundamentally different work -- it's application architecture, not unit test authoring.

**Recommendation:** Redefine TEST-12 scope. The showcase should demonstrate the **critical integration patterns** (store+reducer+effects, navigation stack, sheet presentation, shared state, database persistence), not exhaustively exercise every API. The 108 existing tests already provide exhaustive API coverage. The app proves the integration story, not individual API correctness.

### Risk 2: D3 -- Test reorganisation (MODERATE)

D3 says existing 108 tests are "reorganised to match the new modular feature structure." Reorganising 22 test files across 18 test targets in Package.swift is a non-trivial refactor that risks breaking the existing green test suite. If reorganisation causes regressions, debugging takes time away from new work.

**Recommendation:** Skip reorganisation entirely. The existing test structure is already well-organized by concern (BindingTests, NavigationTests, etc.). Reorganising adds risk with no functional benefit. If reorganisation is desired, defer it to a post-Phase-7 polish pass.

### Risk 3: D12 -- Database integration approach (MODERATE)

D12 defers the database integration approach to research. This is an open design question that could expand scope significantly if the answer is "comprehensive integration" (database as TCA persistence backend requires custom SharedKey implementations, migration management, observation bridging).

**Recommendation:** Choose isolation. A separate database demo tab in the showcase app is simpler, proves the APIs work, and avoids coupling database and TCA complexity in a single feature.

### Risk 4: R1 -- Full API surface audit (LOW-MODERATE)

R1 asks for an exhaustive enumeration of every public type/method/property across 17 forks. This is research that could take significant time and may not provide actionable output if the showcase scope is capped.

**Recommendation:** Skip R1 if TEST-12 scope is capped. The existing REQUIREMENTS.md already has 184 requirements that serve as the API coverage checklist.

### Risk 5: Emulator environment variability (MODERATE)

All prior phases used `swift test` on macOS exclusively. Phase 7 introduces `skip test` on Android emulator for the first time since Phase 2 (which only ran existing template tests). New tests (TEST-10, TEST-11) must work in the emulator environment, which has different timing characteristics, memory constraints, and potential JNI threading issues.

## Phase Split Recommendation

**Yes, split into sub-plans.** The natural boundaries are clear:

### Plan 07-01: TestStore Validation (TEST-01..TEST-09)
- **Scope:** Write TestStore tests in fuse-library, validate on macOS
- **Estimated duration:** 7-10 min (similar to Phase 3 plans)
- **Risk:** Low -- follows established test-authoring pattern from Phases 3-6
- **Output:** ~9 new test functions in a TestStoreTests target

### Plan 07-02: Android Emulator Integration (TEST-10, TEST-11, deferred Phase 1 items)
- **Scope:** Write integration and stress tests, validate on Android emulator via `skip test`
- **Estimated duration:** 15-25 min (emulator startup + iteration adds overhead)
- **Risk:** High -- first emulator-dependent automated tests; recomposition counting may require Skip-specific APIs; stress test timing is environment-sensitive
- **Output:** Integration test target, stress test target, deferred item resolution
- **Includes:** MainSerialExecutor fallback validation (TEST-08 may need to move here if it requires Android runtime)

### Plan 07-03: Fuse-App Showcase (TEST-12)
- **Scope:** Rebuild fuse-app with TCA architecture -- SCOPED to critical integration patterns, not exhaustive API coverage
- **Estimated duration:** 20-30 min (app architecture + multiple feature modules + Package.swift restructuring)
- **Risk:** High -- largest single deliverable, but manageable if scope is capped
- **Output:** Modular TCA app with 4-6 feature areas, running on both platforms

### Plan 07-04: Fork Documentation (DOC-01)
- **Scope:** Generate FORKS.md with per-fork metadata, dependency graph, upstream PR candidates
- **Estimated duration:** 10-15 min (largely mechanical git metadata extraction + writing)
- **Risk:** Low -- no code changes, no compilation
- **Output:** `docs/FORKS.md` with 17 fork sections + Mermaid dependency graph

### Optional Plan 07-05: Test Reorganisation (D3, if pursued)
- **Scope:** Reorganise existing 108 tests into feature-aligned targets
- **Estimated duration:** 10-15 min
- **Risk:** Moderate -- refactoring working tests
- **Recommendation:** DEFER. Not worth the risk for Phase 7 completion.

## Estimated Plan Count

**4 plans** (dropping the optional reorganisation plan).

Comparison to prior phases:
| Phase | Plans | Complexity Profile |
|-------|-------|--------------------|
| 3 - TCA Core | 2 | Uniform (test authoring) |
| 4 - TCA State & Bindings | 3 | Uniform (test authoring) |
| 5 - Navigation | 3 | Mixed (fork changes + tests) |
| 6 - Database | 2 | Mixed (fork wiring + tests) |
| **7 - Integration** | **4** | **Heterogeneous (tests + app build + emulator + docs)** |

4 plans is reasonable given the heterogeneity. The prior phases with 2-3 plans each had homogeneous work (all test authoring). Phase 7 has four distinct workstreams that benefit from separate plans with separate verification criteria.

## Critical Path

```
07-01 (TestStore)  ──────────────────> 07-02 (Emulator Integration) ──> 07-03 (Showcase App)
                                                                              │
DOC-01 (07-04) runs in parallel ─────────────────────────────────────────────>│
                                                                              v
                                                                        Phase Complete
```

**Critical path duration estimate:** 07-01 (10min) + 07-02 (25min) + 07-03 (30min) = ~65 minutes on the critical path. 07-04 runs in parallel and should finish within 15 minutes.

**Total estimated phase duration:** ~65-75 minutes (compared to ~96 minutes for Phases 3-6 combined).

This makes Phase 7 roughly 40-45% of the total project execution time, which is consistent with it being the integration/capstone phase. However, this estimate assumes TEST-12 scope is capped. With the full D1 scope ("every public API"), the estimate could easily double to 120-150 minutes.

## Recommendations

### 1. Cap TEST-12 scope immediately (CRITICAL)
Redefine D1 from "every non-deprecated, current, public API" to "critical integration patterns that prove cross-platform viability." The 108 existing tests provide exhaustive API-level coverage. The showcase app proves the integration story. Suggested feature areas for the capped scope:
- Counter feature (Store + Reducer + Effect basics)
- Todo list feature (IdentifiedArray + ForEach scoping)
- Navigation feature (stack + sheet + alert)
- Settings feature (Shared state persistence)
- Database feature (StructuredQueries + GRDB, isolated tab)
- This covers TCA core, state management, navigation, persistence, and database -- the five pillars of the project

### 2. Front-load TestStore validation (07-01)
TEST-01..TEST-09 are the lowest-risk, highest-confidence items. Getting them green early provides a foundation for the harder integration work.

### 3. Treat emulator work as a separate risk zone (07-02)
Emulator-dependent tests (TEST-10, TEST-11, deferred items) have fundamentally different iteration dynamics than macOS `swift test`. Isolating them in their own plan prevents emulator issues from blocking other work.

### 4. Skip test reorganisation (D3)
The existing 22-file, 18-target test structure is already well-organized by concern. Reorganising into "feature-aligned" targets adds risk (breaking green tests) with no functional benefit. The current structure IS feature-aligned -- BindingTests test bindings, NavigationTests test navigation, etc.

### 5. Run DOC-01 in parallel
Fork documentation is entirely independent of code work. It can be executed as a parallel plan at any point during the phase.

### 6. Resolve D12 (database integration) with "isolation" before planning starts
Avoid the research overhead of R3. Choose the isolation approach (separate database demo tab) and move on. This is the simpler path that still demonstrates every database API.

### 7. Skip R1 (full API surface audit)
REQUIREMENTS.md already has 184 requirements. A separate audit of every public type/method/property across 17 forks would produce a massive document that doesn't change the planning. The requirements are the API surface.

### 8. Budget for emulator environment setup
No prior phase has run automated tests on the Android emulator. Budget 5-10 minutes in 07-02 for environment verification (`skip doctor`, emulator launch, baseline `skip test` pass) before writing new emulator-dependent tests.

---
*Assessment created: 2026-02-22*
*Inputs: REQUIREMENTS.md, STATE.md, 07-CONTEXT.md, ROADMAP.md, existing fuse-app/fuse-library structure*
