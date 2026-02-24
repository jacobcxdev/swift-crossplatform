# Phase 14: Android Verification & Requirements Reset - Research

**Researched:** 2026-02-24
**Domain:** Android test execution, requirements traceability, cross-platform verification
**Confidence:** HIGH

## Summary

Phase 14 is a verification and documentation phase, not an implementation phase. The goal is to run the full Android test suite via `skip android test`, map passing/failing tests to the 159 pending requirements (the phase description says "169" but actual count is 159), update the traceability table in REQUIREMENTS.md with evidence-backed statuses, and document known limitations for requirements that cannot pass.

The critical insight from research is that **27 of 35 test files are gated with `#if !SKIP`**, meaning they are invisible to the Android/Kotlin transpiler. The 253 Android tests reported by Phase 11 come from only a small subset of non-gated files (ObservationTests.swift, FuseLibraryTests.swift, and fuse-app integration tests). This means most requirement-specific unit tests (TCA, Navigation, Sharing, Foundation, Database) have **never been transpiled or executed on Android**. Phase 14 must determine requirement status through a combination of:

1. Direct Android test evidence (tests that actually run on Android)
2. Indirect evidence (Android tests exercise the code path even if not testing the specific API)
3. Code-level verification (the requirement's API compiles and is wired correctly for Android, with macOS test coverage proving correctness)
4. Known limitation documentation (requirements that genuinely cannot pass on Android)

**Primary recommendation:** Run `make android-test`, capture full test output, then systematically map each of the 159 pending requirements to evidence categories (direct test, indirect evidence, code verification, or known limitation). Update REQUIREMENTS.md traceability table with evidence-backed statuses.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `skip android test` | Skip 1.7+ | Android emulator test execution | Canonical Android test pipeline; runs Kotlin-transpiled tests on connected emulator |
| `make android-test` | Makefile | Iterates both examples | Runs `skip android test` for fuse-library and fuse-app |
| `make darwin-test` | Makefile | macOS test baseline | Runs `swift test` for both examples; establishes passing baseline |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `adb logcat -s swift` | Stream Swift logs from emulator | Debug runtime failures during Android test execution |
| `skip android emulator launch` | Launch emulator | When no emulator is running |
| `skip devices` | List available emulators | Verify emulator availability before testing |

### Not Applicable
| Instead of | Why Not |
|------------|---------|
| `skip test` (Robolectric) | Blocked by skipstone symlink issue with local fork paths; `skip android test` is the canonical pipeline |
| New test framework setup | Existing XCTest + Swift Testing infrastructure is sufficient |
| Context7 / WebSearch | This is a project-internal verification phase, not a technology research phase |

## Architecture Patterns

### Verification Decision Tree

For each of the 159 pending requirements, apply this decision tree:

```
1. Does a test exist that exercises this API on Android?
   YES → Run it, check result → DIRECT EVIDENCE
   NO  → Continue to 2

2. Is the API exercised indirectly by Android tests?
   (e.g., TCA Store init is tested by observation tests that create stores)
   YES → Document indirect evidence → INDIRECT EVIDENCE
   NO  → Continue to 3

3. Does the code compile for Android AND pass on macOS?
   YES → Code verification (architecture-level confidence) → CODE VERIFIED
   NO  → Continue to 4

4. Is there a known platform limitation?
   YES → Document as KNOWN LIMITATION with rationale
   NO  → Flag as UNVERIFIED (needs investigation)
```

### Evidence Categories for Requirements

| Category | Traceability Status | Checkbox | Criteria |
|----------|-------------------|----------|----------|
| DIRECT | Complete | `[x]` | Android test directly exercises the API and passes |
| INDIRECT | Complete | `[x]` | Android test exercises the code path; macOS test proves API correctness |
| CODE_VERIFIED | Complete | `[x]` | Compiles on Android; macOS tests pass; no Android-specific runtime concern |
| KNOWN_LIMITATION | Known Limitation | `[ ]` | Cannot work on Android; documented with rationale |
| UNVERIFIED | Pending | `[ ]` | Insufficient evidence; needs further investigation |

### Recommended Project Structure

```
.planning/phases/14-android-verification/
├── 14-RESEARCH.md              # This file
├── 14-01-PLAN.md               # Run Android tests, capture output
├── 14-02-PLAN.md               # Map requirements to evidence, update REQUIREMENTS.md
├── 14-03-PLAN.md               # Re-audit and final documentation
├── android-test-output.md       # Captured test results (artifact)
└── requirement-evidence-map.md  # Per-requirement evidence (artifact)
```

### Pattern: Test Evidence Capture

```bash
# Step 1: Verify emulator is available
skip devices

# Step 2: Run Android tests and capture full output
cd examples/fuse-library && skip android test 2>&1 | tee /tmp/fuse-library-android.log
cd examples/fuse-app && skip android test 2>&1 | tee /tmp/fuse-app-android.log

# Step 3: Run Darwin tests for baseline comparison
cd examples/fuse-library && swift test 2>&1 | tee /tmp/fuse-library-darwin.log
cd examples/fuse-app && swift test 2>&1 | tee /tmp/fuse-app-darwin.log
```

### Pattern: Requirement-to-Test Mapping

For each requirement, the planner should create a mapping entry:

```markdown
| REQ-ID | Test File | Test Name | Platform | Evidence Type | Status |
|--------|-----------|-----------|----------|---------------|--------|
| OBS-01 | ObservationTests.swift | testVerifyBasicTracking | Android | DIRECT | Pass |
| TCA-01 | StoreReducerTests.swift | testStoreInit | macOS-only (#if !SKIP) | CODE_VERIFIED | Pass |
```

### Anti-Patterns to Avoid

- **Marking requirements Complete without evidence:** Every `[x]` must have a documented evidence type and source.
- **Re-running macOS tests as "Android verification":** macOS test passes do not constitute Android evidence by themselves.
- **Ignoring `#if !SKIP` gating:** 27 test files are gated out -- do not assume these run on Android.
- **Treating 253 Android tests as covering all requirements:** The 253 tests cover a narrow subset (observation bridge + fuse-app features). Most requirement-specific tests are `#if !SKIP` gated.
- **Attempting to remove `#if !SKIP` guards:** These guards exist because the test files use Swift Testing macros, XCTest APIs, or TCA test infrastructure that cannot be transpiled by skipstone. Removing them would cause Kotlin compilation failures. This is an infrastructure limitation, not a Phase 14 fix.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Android test execution | Custom test runner | `skip android test` | Skip's canonical pipeline handles JNI, Gradle, and emulator orchestration |
| Test output parsing | Manual log grep | Structured JUnit XML from Gradle | Skip generates JUnit results automatically |
| Requirement traceability | New tracking system | Update existing REQUIREMENTS.md table | The table structure is already defined; just update statuses |
| Audit validation | Manual checklist | `/gsd:audit-milestone` workflow | Automated milestone audit catches gaps systematically |

**Key insight:** Phase 14 is not about building anything new. It is about executing existing tests, analyzing results, and updating documentation. The tooling already exists.

## Common Pitfalls

### Pitfall 1: Conflating "compiles on Android" with "works on Android"
**What goes wrong:** A requirement is marked Complete because the code compiles via `skip android build`, but runtime behavior was never tested.
**Why it happens:** The v1.0 audit found exactly this pattern across phases 1-7.
**How to avoid:** Require explicit evidence type (DIRECT/INDIRECT/CODE_VERIFIED) for every requirement. CODE_VERIFIED is acceptable only when there is no Android-specific runtime concern (e.g., pure data structure operations).
**Warning signs:** Requirements marked Complete with no test name or evidence source.

### Pitfall 2: Assuming all 253 Android tests map to requirements
**What goes wrong:** The planner assumes the 253 tests provide broad requirement coverage, when in reality they are concentrated in ObservationTests and fuse-app integration tests.
**Why it happens:** The test count is impressive but the coverage is narrow.
**How to avoid:** Map each test to specific requirements. Many requirements (especially TCA, DEP, SHR, SQL, SD) have no direct Android test coverage because their test files are `#if !SKIP` gated.
**Warning signs:** Large requirement groups marked DIRECT with only one or two source tests.

### Pitfall 3: Incorrect pending count
**What goes wrong:** The phase description states "169 pending requirements" but actual count is 159 Pending (25 Complete, 184 total).
**Why it happens:** The count was likely estimated during roadmap creation and not verified against current REQUIREMENTS.md state.
**How to avoid:** Always count from the source of truth (REQUIREMENTS.md traceability table). The correct number is **159 Pending**.
**Warning signs:** Plans that reference "169" instead of "159".

### Pitfall 4: Trying to un-gate `#if !SKIP` test files
**What goes wrong:** Someone removes `#if !SKIP` guards hoping to get tests transpiled to Kotlin, causing Kotlin compilation failures.
**Why it happens:** The tests use Swift Testing macros (`@Test`, `@Suite`), `withKnownIssue`, `@_spi(Reflection)`, Combine publishers, and other APIs that skipstone cannot transpile.
**How to avoid:** Accept that these tests are macOS-only. For Android evidence, rely on the non-gated observation/integration tests plus code-level verification.
**Warning signs:** Kotlin compilation errors after removing guards.

### Pitfall 5: Not running Android tests before updating requirements
**What goes wrong:** Requirements are marked based on assumptions rather than actual test execution.
**Why it happens:** Android emulator setup is non-trivial and test execution takes time.
**How to avoid:** The first plan MUST execute `make android-test` and capture full output BEFORE any requirement status updates.
**Warning signs:** REQUIREMENTS.md updated without android-test-output.md artifact.

### Pitfall 6: Missing known limitation documentation
**What goes wrong:** Requirements that genuinely cannot pass on Android are left as Pending without explanation.
**Why it happens:** The requirement descriptions say "on Android" but some APIs are architecturally unavailable (e.g., SD-09/SD-10/SD-11 @FetchAll/@FetchOne need SwiftUI DynamicProperty).
**How to avoid:** Document each known limitation with: (a) what specifically doesn't work, (b) why (architectural reason), (c) workaround if any, (d) whether it's fixable in principle.
**Warning signs:** Requirements stuck at Pending with no investigation notes.

## Code Examples

### Requirement Evidence Table Entry (for REQUIREMENTS.md update)

```markdown
## Traceability

| Requirement | Phase | Status | Evidence |
|-------------|-------|--------|----------|
| OBS-01 | Phase 1 | Complete | DIRECT: ObservationTests.testVerifyBasicTracking passes on Android emulator |
| TCA-01 | Phase 3 | Complete | CODE_VERIFIED: Store.init compiles on Android; StoreReducerTests.testStoreInit passes on macOS |
| SD-09 | Phase 6 | Known Limitation | @FetchAll requires SwiftUI DynamicProperty.update() (unavailable on Android) |
```

### Known Limitations Section (for REQUIREMENTS.md)

```markdown
## Known Limitations (Android)

| Requirement | Limitation | Rationale | Workaround |
|-------------|-----------|-----------|------------|
| SD-09 | @FetchAll macro unavailable | Requires SwiftUI DynamicProperty runtime | Use ValueObservation.start() directly |
| SD-10 | @FetchOne macro unavailable | Same as SD-09 | Use ValueObservation.start() directly |
| SD-11 | @Fetch with FetchKeyRequest unavailable | Same as SD-09 | Use ValueObservation.start() directly |
| DEP-05 | previewValue unused on Android | No preview context on Android | Preview context never active; liveValue used |
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| JUnit XML stubs (fake tests) | XCGradleHarness with XCTSkip | Phase 11 (2026-02-24) | Android tests actually execute; stubs replaced |
| All 184 requirements marked Complete | 159 Pending + 25 Complete | Phase 9 audit reset (2026-02-23) | Honest traceability reflects actual evidence |
| `skip test` for Android | `skip android test` for Android | Phase 11 decision | Robolectric blocked by symlink issue; emulator pipeline canonical |

## Open Questions

1. **Emulator availability during plan execution**
   - What we know: `skip android test` requires a running Android emulator or connected device
   - What's unclear: Whether the executor session will have emulator access
   - Recommendation: Plan must include emulator launch step; if unavailable, fall back to `skip android build` + code-level verification only, and flag reduced confidence

2. **Evidence threshold for CODE_VERIFIED status**
   - What we know: Many requirements test pure Swift APIs that work identically on all platforms
   - What's unclear: Where to draw the line between "obviously platform-independent" and "needs Android runtime proof"
   - Recommendation: CODE_VERIFIED is acceptable for: pure data structures (IC, CP), query building (SQL), custom dump/diff (CD), and any API that has no JNI/bridge/UI dependency. Require DIRECT or INDIRECT evidence for: observation (OBS), UI presentation (NAV sheet/alert/dialog), shared state persistence (SHR appStorage/fileStorage), and database observation macros (SD-09..11).

3. **withKnownIssue-wrapped tests**
   - What we know: Several tests use `withKnownIssue` for Android timing issues (dismiss JNI pipeline, async effect timing)
   - What's unclear: Whether these should count as "passing" or "known limitation"
   - Recommendation: Tests that pass with `withKnownIssue` where `isIntermittent: true` should be marked Complete (the API works, timing is flaky). Tests with non-intermittent `withKnownIssue` should be documented as Known Limitation.

4. **Exact pending count discrepancy**
   - What we know: Phase description says "169 pending", actual count is **159 Pending** (25 Complete)
   - What's unclear: Whether the discrepancy was from a different point in time or a counting error
   - Recommendation: Use 159 as the authoritative count from current REQUIREMENTS.md

## Requirement-to-Evidence Pre-Analysis

### Requirements with likely DIRECT Android test evidence (from non-gated tests)

The following requirements map to tests in `ObservationTests.swift` (not `#if !SKIP` gated) which run on Android:

| Requirement | Android Test | Test Method |
|-------------|-------------|-------------|
| OBS-01 | ObservationTests | testVerifyBasicTracking |
| OBS-05 | ObservationTests | testVerifyNestedTracking |
| OBS-08 | ObservationTests | testVerifyBasicTracking (access recorded) |
| OBS-09 | ObservationTests | testVerifyBasicTracking (willSet fires) |
| OBS-11 | ObservationTests | testVerifyBasicTracking (uses withObservationTracking) |
| OBS-12 | ObservationTests | testObservablePropertyReadWrite (@Observable class) |
| OBS-13 | ObservationTests | testObservablePropertyReadWrite (property read) |
| OBS-14 | ObservationTests | testVerifyBasicTracking (single update) |
| OBS-15 | ObservationTests | testVerifyBulkMutationCoalescing |
| OBS-17 | ObservationTests | testObservationIgnoredProperty, testVerifyIgnoredProperty |
| OBS-22 | ObservationTests | testVerifyMultiPropertySingleOnChange |

Fuse-app integration tests (also not `#if !SKIP` gated, 30 Android tests):

| Requirement | Android Test | Feature Exercised |
|-------------|-------------|-------------------|
| TCA-01..TCA-04 | FuseAppIntegrationTests | Counter, Todos, Contacts features create/scope stores |
| TCA-11 | FuseAppIntegrationTests | Effect.run in async todo/contact operations |
| NAV-01..NAV-03 | FuseAppIntegrationTests | Contacts NavigationStack push/pop |
| TEST-12 | FuseAppIntegrationTests | Full app exercises all features |

### Requirements likely CODE_VERIFIED (pure Swift, no Android runtime concern)

| Category | Requirements | Rationale |
|----------|-------------|-----------|
| CasePaths | CP-01..CP-08 | Pure Swift enum introspection; no JNI/bridge dependency |
| IdentifiedCollections | IC-01..IC-06 | Pure Swift data structures; no platform dependency |
| CustomDump | CD-01..CD-05 | Pure Swift value dumping/diffing; no platform dependency |
| StructuredQueries | SQL-01..SQL-15 | Query building is pure Swift; SQL generation has no platform dependency |
| Effects (pure) | TCA-10, TCA-12..TCA-16 | Effect combinators are pure Swift async; no bridge dependency |
| Reducers (pure) | TCA-05, TCA-06, TCA-07, TCA-08, TCA-09 | Reducer composition is pure Swift |

### Requirements likely KNOWN LIMITATION

| Requirement | Limitation | Source |
|-------------|-----------|--------|
| SD-09 | @FetchAll requires SwiftUI DynamicProperty | Phase 6 Codex verifier, STATE.md |
| SD-10 | @FetchOne requires SwiftUI DynamicProperty | Phase 6 Codex verifier, STATE.md |
| SD-11 | @Fetch with FetchKeyRequest requires SwiftUI DynamicProperty | Phase 6 Codex verifier, STATE.md |
| DEP-05 | previewValue unused (no preview context on Android) | STATE.md pending todo |
| SHR-09 | Observations {} async sequence -- needs verification | STATE.md: Combine publishers used instead |
| SHR-10 | $shared.publisher (Combine) -- may need OpenCombine on Android | Needs verification |
| NAV-16 | iOS 26+ API compatibility -- not testable on Android | Platform-specific |

### Requirements needing careful assessment

| Requirement | Concern |
|-------------|---------|
| OBS-02..OBS-04, OBS-06, OBS-07, OBS-10 | Bridge internals; may need indirect evidence from observation tests |
| OBS-18..OBS-20 | @Observable + sheet/binding patterns; partially tested by fuse-app |
| OBS-21..OBS-28 | JNI bridge exports; verified by bridge init success but no direct unit test |
| TCA-26 | Dismiss dependency; known P2 timing issue (withKnownIssue wrapped) |
| IR-01..IR-04 | Issue reporting; withKnownIssue tests exist but test the reporting mechanism itself |
| TEST-01..TEST-09 | TestStore API; tests are #if !SKIP gated; need code-level verification |

<phase_requirements>
## Phase Requirements

**Actual count: 159 Pending requirements** (phase description says 169 -- discrepancy noted)

| Category | IDs | Count | Likely Evidence Type |
|----------|-----|-------|---------------------|
| OBS | OBS-01..OBS-28 | 28 | Mix: DIRECT (observation tests), INDIRECT (bridge init proves JNI exports), CODE_VERIFIED |
| CP | CP-01..CP-08 | 8 | CODE_VERIFIED (pure Swift) |
| IC | IC-01..IC-06 | 6 | CODE_VERIFIED (pure Swift) |
| CD | CD-01..CD-05 | 5 | CODE_VERIFIED (pure Swift) |
| IR | IR-01..IR-04 | 4 | INDIRECT (IssueReporting compiles/runs on Android via xctest-dynamic-overlay fix) |
| TCA | TCA-01..TCA-24, TCA-26..TCA-30, TCA-32..TCA-35 | 31 | Mix: INDIRECT (fuse-app exercises stores/effects), CODE_VERIFIED (pure reducer/effect combinators) |
| DEP | DEP-01..DEP-12 | 12 | CODE_VERIFIED (dependency resolution is pure Swift); DEP-05 KNOWN LIMITATION |
| SHR | SHR-01..SHR-14 | 14 | Mix: CODE_VERIFIED (in-memory), needs assessment (file/appStorage persistence on Android) |
| NAV | NAV-01..NAV-04, NAV-06, NAV-09..NAV-16 | 12 | Mix: INDIRECT (fuse-app navigation), CODE_VERIFIED (AlertState/ConfirmationDialogState data layer) |
| SQL | SQL-01..SQL-15 | 15 | CODE_VERIFIED (pure Swift query building) |
| SD | SD-01..SD-12 | 12 | Mix: CODE_VERIFIED (database lifecycle), KNOWN LIMITATION (SD-09..SD-11 DynamicProperty) |
| TEST | TEST-01..TEST-09 | 9 | CODE_VERIFIED (TestStore API is pure Swift; tests pass on macOS) |
| **Total** | | **159** | |
</phase_requirements>

## Sources

### Primary (HIGH confidence)
- REQUIREMENTS.md traceability table (159 Pending, 25 Complete counted directly)
- Phase 11 verification reports (Claude + Gemini: 253 Android tests confirmed)
- `#if !SKIP` grep results: 27 of 35 test files gated (cannot run on Android)
- STATE.md accumulated decisions and pending todos
- v1.0-MILESTONE-AUDIT.md (6 critical gaps, 5 now resolved by Phases 11-13)

### Secondary (MEDIUM confidence)
- ObservationTests.swift code review: 18 test methods, none `#if !SKIP` gated
- FuseAppIntegrationTests.swift: 30 tests, with `#if !SKIP` gating
- Fuse-app Package.swift: skipstone on all test targets confirmed
- Phase 6/7 Codex verifier notes on SD-09..SD-11 DynamicProperty limitation

### Tertiary (LOW confidence)
- Exact mapping of 253 Android tests to requirements (needs actual test execution output to confirm)
- SHR-09/SHR-10 Combine/OpenCombine behavior on Android (needs runtime verification)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - `skip android test` is well-documented and proven in Phase 11
- Architecture: HIGH - verification decision tree and evidence categories are straightforward
- Pitfalls: HIGH - drawn directly from v1.0 audit findings and accumulated project decisions
- Requirement mapping: MEDIUM - pre-analysis is based on code review, needs actual test output confirmation

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (stable; no external dependencies changing)
