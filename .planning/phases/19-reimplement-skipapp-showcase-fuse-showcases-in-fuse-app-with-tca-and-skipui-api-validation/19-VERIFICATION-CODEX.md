# Phase 19 Plan Verification (Codex)

## Inputs Reviewed
- `.planning/ROADMAP.md` (Phase 19 goal, requirements SHOWCASE-01...SHOWCASE-11, success criteria)
- `.planning/phases/19-reimplement-skipapp-showcase-fuse-showcases-in-fuse-app-with-tca-and-skipui-api-validation/19-CONTEXT.md`
- `.planning/phases/19-reimplement-skipapp-showcase-fuse-showcases-in-fuse-app-with-tca-and-skipui-api-validation/19-RESEARCH.md`
- `CLAUDE.md`
- All 12 plan files:
  - `19-01-PLAN.md` ... `19-12-PLAN.md`

## Dimension Checks

### 1) Requirement Coverage
Status: PASS

Coverage map:
- SHOWCASE-01 -> 19-01
- SHOWCASE-02 -> 19-02
- SHOWCASE-03 -> 19-03
- SHOWCASE-04 -> 19-04
- SHOWCASE-05 -> 19-04
- SHOWCASE-06 -> 19-05, 19-06
- SHOWCASE-07 -> 19-07
- SHOWCASE-08 -> 19-08, 19-09
- SHOWCASE-09 -> 19-10, 19-11
- SHOWCASE-10 -> 19-12
- SHOWCASE-11 -> 19-12

All SHOWCASE requirements are covered by at least one plan.

### 2) Task Completeness
Status: PASS

Every task block in all 12 plans contains all required sections:
- `<files>`
- `<action>`
- `<verify>`
- `<done>`

### 3) Dependency Correctness
Status: PASS

- No dependency cycles detected.
- Wave ordering is consistent:
  - Wave 1: 19-01, 19-02
  - Wave 2: 19-03...19-11 depend only on earlier wave plans
  - Wave 3: 19-12 depends on Wave 2 outputs
- All referenced dependency plans exist.

### 4) Key Links
Status: PASS

Required wiring chain is explicitly planned:
- `TestHarnessFeature -> ShowcaseFeature` in 19-03 (`Scope(state: \\.showcase, action: \\.showcase)`)
- `ShowcaseFeature -> PlaygroundTypes` in 19-02 (`PlaygroundType` used in state/actions)
- `ShowcasePath -> playground files` in 19-12 (switch routing to all 84 playground views)

### 5) Scope Sanity (>10 files in one task)
Status: FAIL

Two tasks exceed the >10 file sanity threshold:
- 19-04 Task 1: 11 files
- 19-10 Task 1: 11 files

### 6) Verification Derivation (must_haves should be user-observable)
Status: FAIL

Many `must_haves.truths` entries are implementation/internal assertions, not user-observable outcomes.
Examples:
- 19-02: "ShowcasePath reducer enum provides navigation destination routing"
- 19-04: "Each stub compiles independently"
- 19-11: "SQLPlayground creates its own in-memory database (no shared state)"

### 7) Context Compliance (locked decisions)
Status: PARTIAL / FAIL

Honored:
- 84-playground port scope is fully distributed across plans.
- Two-tab architecture (Showcase + Control) is explicitly planned.
- TCA NavigationStack/path model is explicitly planned.
- Phase 18.1 files/tests deletion is explicitly planned.
- ScenarioEngine/debug toolbar retention is explicitly planned.

Not explicitly planned (locked decisions gap):
- "Delete all existing scenarios (ForEachNS, peer survival)" is not directly mapped to a concrete file/task touching scenario registry/scenario definitions.
- "Broken playgrounds tracked via UAT document" is not mapped to a concrete file/task/output.

## ISSUES FOUND

1. **SCOPE-01 (Scope Sanity)**
- Dimension: 5
- Evidence: 19-04 Task 1 and 19-10 Task 1 each modify 11 files.
- Risk: Oversized tasks increase execution/review risk and reduce checkpoint quality.
- Fix: Split each into two smaller tasks (<=10 files per task), preserving same requirements.

2. **VERIFY-01 (Must-Have Derivation Quality)**
- Dimension: 6
- Evidence: Multiple `must_haves.truths` are internal implementation claims rather than user-observable behavior.
- Risk: Plan verification can pass without proving phase outcomes visible to users/UAT.
- Fix: Rewrite must-haves as observable outcomes (navigation behavior, searchable UX behavior, rendered playground outcomes, scenario control behavior), keep internal details in task actions.

3. **CONTEXT-01 (Locked Scenario/UAT Decisions Not Fully Mapped)**
- Dimension: 7
- Evidence: No explicit plan task/file for removing legacy scenarios or creating/updating a UAT tracking artifact for broken playgrounds.
- Risk: Locked decisions may be partially implemented by assumption, not by explicit executable tasks.
- Fix: Add explicit task(s) to:
  - remove existing scenario definitions (ForEachNS/peer survival) from registry/source,
  - create or update a Phase 19 UAT tracking document for broken playground follow-up.
