# Phase 8: PFW Skill Alignment - Context

**Gathered:** 2026-02-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Align all app code, test code, and fork code with Point-Free canonical API patterns as documented in `/pfw-*` skills. The PFW audit identified 191 findings across 12 skills — some were partially addressed in a prior session (C1, H3, H4, H8, H9, M16). This phase addresses ALL remaining findings with zero exceptions. PFW skills are canonical instructions; deviation reduces upstreamability.

**Scope includes:** fuse-app source, fuse-library tests, fuse-app integration tests, AND fork code we maintain.

</domain>

<decisions>
## Implementation Decisions

### Guiding principle
- PFW skills are canonical — NO deviations, NO skipping
- Every finding from the 191-item audit gets addressed
- If following a skill breaks something, that reveals a bug to fix, not a reason to skip
- Prior session's "intentionally skipped" rationale is overridden — all findings are in scope

### Previously-skipped findings (all now in scope)
- **H1 (nested Path):** Un-nest `@Reducer enum Path` from parent features. Create `ContactsFeaturePath` etc. at file scope per PFW skill
- **H6 (import GRDB):** Replace all `import GRDB` with `import SQLiteData`. If types aren't re-exported, fix the fork's re-exports
- **H11 (@CasePathable):** Add `@CasePathable` to all Action enums. If `@Reducer` already generates case paths, verify no conflict — but follow the skill
- **H12 (IdentifiedArrayOf):** Switch `[Todo]` to `IdentifiedArrayOf<Todo>` for `@Shared(.fileStorage)`. Handle any Codable migration needed
- **H13 (popLast):** Replace `state.path.popLast()` with canonical dismiss pattern from pfw-swift-navigation
- **H14 (@available):** Add `@available` annotations or use `@Perceptible` as pfw-perception skill prescribes
- **M5 (transitive deps):** Remove transitive deps from Package.swift test targets. If imports break, stop importing those modules directly

### Test framework migration
- **Full migration:** ALL 15+ XCTestCase files migrate to Swift Testing `@Suite`/`@Test` pattern — both fuse-library and fuse-app
- **XCTExpectFailure:** Claude's discretion on equivalent (likely `withKnownIssue`)
- **Template pattern:** Claude's discretion — check pfw-testing skill for canonical structure (UIPatternTests.swift is a candidate reference)
- **TestStore + async:** No concerns — proceed with Swift Testing async model

### Database API conventions
- **H5 + M1 (query syntax):** Replace all infix `==`/`>` with `.eq()`/`.gt()`. Replace all `.asc()` with `order(by: \.field)`. No exceptions
- **H7 (@FetchAll):** Full refactor of DatabaseFeature views — replace polling with `@FetchAll`/`@FetchOne` property wrappers
- **M7 (#sql macro):** Use `#sql` macro everywhere possible, including migrations. Document if DDL genuinely can't use it
- **M9 (defaultDatabase):** Switch to `SQLiteData.defaultDatabase()` for proper WAL mode / multi-reader setup
- **M10 (bootstrap location):** Move `bootstrapDatabase` to `@main` App struct's `init()` per pfw-sqlite-data

### Assertion & idiom modernisation
- **M4 (expectNoDifference):** Claude's discretion — check pfw-custom-dump for when to use `expectNoDifference` vs `#expect`
- **M3 (CasePaths idioms):** Replace all `if case` with `.is()` / `[case:]` subscript per pfw-case-paths
- **M15 (Effect errors):** Claude's discretion — check pfw-issue-reporting and pfw-composable-architecture for canonical error handling pattern in Effect.run
- **ALL LOW items:** Every LOW finding gets fixed. No exceptions. Full PFW alignment

### Remaining MEDIUMs (all in scope, follow PFW exactly)
- **H2:** Remove `CombineReducers` when no modifier is applied
- **M6:** Remove default `UUID()`/`Date()` from models, require `@Dependency` injection
- **M8:** Add `.dependencies { try $0.bootstrapDatabase() }` trait to database test suites
- **M11:** Replace boolean sheet state with optional `@Presents` state
- **M12:** Replace manual `destination = nil` with `@Dependency(\.dismiss)` pattern
- **M14:** Replace Combine-only observation tests with `Observations { ... }` async sequence

### Platform-specific items (in scope)
- **M13 (Android NavigationStack):** Fix or document StackState being silently unused on Android. Either implement path binding or explicitly document the gap with a TODO
- **M17 (ObservationRegistrar shadow):** Rename shadow type in skip-android-bridge to avoid module name collision. Update JNI bindings as needed

### Fork code (in scope)
- Fork infrastructure changes are in scope alongside app/test code
- `DispatchSemaphore` → `os_unfair_lock` in bridge code
- `FlagBox` `@unchecked Sendable` — address the undocumented implementation detail
- `@_spi(Reflection) import CasePaths` — remove fragile SPI usage
- `private` cancel-ID enums → `fileprivate` for CasePaths compatibility

### Claude's Discretion
- Test file structure template (check pfw-testing for canonical pattern)
- `XCTExpectFailure` → `withKnownIssue` or alternative (check pfw-testing)
- `expectNoDifference` vs `#expect` decision boundary (check pfw-custom-dump)
- Effect.run error handling pattern: `reportIssue` vs dedicated error actions (check pfw-issue-reporting + pfw-composable-architecture)

</decisions>

<specifics>
## Specific Ideas

- "We should not be skipping anything; PFW skills are canonical instructions and best practices directly from pointfreeco. Deviation reduces upstreamability."
- Prior session applied 7 fixes (C1, H3, H4, H8, H9, M16, UIPatternTests receive calls) — these are done and should not be reverted
- Each PFW skill (`/pfw-*`) must be consulted before implementing its findings to get the exact canonical pattern — don't guess from audit descriptions alone
- 121 tests currently pass (91 fuse-library + 30 fuse-app) — maintain or improve this count

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-pfw-skill-alignment*
*Context gathered: 2026-02-23*
