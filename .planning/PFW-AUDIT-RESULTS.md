# PFW Skill Audit Results

Generated: 2026-02-23

## Cross-Skill Summary

| Skill | CRITICAL | HIGH | MEDIUM | LOW | Total |
|-------|----------|------|--------|-----|-------|
| pfw-composable-architecture | 1 | 4 | 12 | 11 | 28 |
| pfw-structured-queries | 0 | 3 | 8 | 5 | 16 |
| pfw-sqlite-data | 0 | 7 | 7 | 5 | 19 |
| pfw-sharing | 0 | 0 | 2 | 3 | 5 |
| pfw-dependencies | 0 | 2 | 4 | 3 | 9 |
| pfw-testing | 0 | 15 | 27 | 22 | 64 |
| pfw-case-paths | 0 | 2 | 7 | 5 | 14 |
| pfw-identified-collections | 0 | 1 | 2 | 1 | 4 |
| pfw-swift-navigation | 0 | 1 | 3 | 2 | 6 |
| pfw-custom-dump | 0 | 0 | 7 | 5 | 12 |
| pfw-perception | 0 | 1 | 3 | 4 | 8 |
| pfw-issue-reporting | 0 | 1 | 2 | 3 | 6 |
| **TOTALS** | **1** | **37** | **84** | **69** | **191** |

---

## CRITICAL (1)

### C1: Test sends non-existent action `.toggleCategory`
- **File:** `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift:372`
- **Issue:** Sends `.toggleCategory("work")` but reducer defines `.categoryFilterChanged(String)`
- **Skills:** TCA, Dependencies, IssueReporting
- **Fix:** Change to `.categoryFilterChanged("work")`

---

## HIGH (deduplicated to ~10 unique findings)

### H1: `Path` nested inside parent features
- **Files:** `ContactsFeature.swift:13-15`, `NavigationTests.swift:16-18`, `NavigationStackTests.swift:18-20`
- **Rule:** DO NOT nest Path feature inside parent — prefix with parent name (e.g. `ContactsFeaturePath`)
- **Skill:** TCA

### H2: `CombineReducers` without modifier
- **File:** `StoreReducerTests.swift:134-151`
- **Rule:** DO NOT use CombineReducers if no modifier (ifLet, forEach) is applied
- **Skill:** TCA

### H3: `Action: Equatable` on ~18 test reducers
- **Files:** EffectTests.swift (7), DependencyTests.swift (4), StoreReducerTests.swift (3), UIPatternTests.swift (4), TestStoreEdgeCaseTests.swift (1)
- **Rule:** DO NOT conform Action to Equatable
- **Skill:** TCA

### H4: `var id` on `@Table` primary keys
- **Files:** `StructuredQueriesTests.swift:10` (Item), `StructuredQueriesTests.swift:18` (Category)
- **Rule:** DO prefer `let` for `id` on primary-keyed tables
- **Skill:** StructuredQueries

### H5: Infix `==`/`>` operators in `.where` closures
- **Files:** `SQLiteDataTests.swift:219`, `StructuredQueriesTests.swift:198,444,448`
- **Rule:** Use named functions: `.eq()`, `.gt()`, not Swift infix operators
- **Skill:** StructuredQueries

### H6: `import GRDB` in app/test code
- **Files:** `DatabaseFeature.swift:3`, `FuseAppIntegrationTests.swift:2`, `SQLiteDataTests.swift:3`
- **Rule:** `import SQLiteData` always — GRDB is internal implementation detail
- **Skill:** SQLiteData

### H7: No `@FetchAll`/`@FetchOne` observation in DatabaseView
- **File:** `DatabaseFeature.swift:72-83`
- **Issue:** Polls once on appear, notes go stale. Should use `@FetchAll` / `@FetchOne` property wrappers
- **Skill:** SQLiteData

### H8: `try!` in production code
- **File:** `FuseApp.swift:24` — `try! $0.bootstrapDatabase()`
- **Rule:** Use `withErrorReporting` for I/O errors, not fatalError/try!
- **Skills:** Dependencies, IssueReporting

### H9: `static let` for DependencyKey values
- **Files:** `SharedModels.swift:82-87` (NumberFactClient), `DependencyTests.swift:10-11,22-23`
- **Rule:** Use `static var` computed properties, not `static let`
- **Skill:** Dependencies

### H10: All XCTest files lack `@Suite` base suite pattern
- **Files:** 15+ XCTestCase files across both test bundles
- **Rule:** Define `@Suite(.serialized, .dependencies { ... }) struct BaseSuite {}` and extend
- **Skill:** Testing

### H11: `@CasePathable` missing from all top-level Action enums in fuse-app
- **Files:** AppFeature, ContactsFeature, ContactDetailFeature, DatabaseFeature, SettingsFeature
- **Rule:** Action enums must have `@CasePathable` for `\.caseName` key-path syntax
- **Skill:** CasePaths

### H12: `[Todo]` used for `@Shared(.fileStorage)` instead of `IdentifiedArrayOf<Todo>`
- **File:** `SharedModels.swift:64`, `SettingsFeature.swift:15`
- **Rule:** Identifiable collections should use IdentifiedArrayOf
- **Skill:** IdentifiedCollections

### H13: Manual `state.path.popLast()` bypasses TCA stack action mechanism
- **File:** `ContactsFeature.swift:48`
- **Rule:** Use `state.path.remove(id:)` or `@Dependency(\.dismiss)`
- **Skill:** SwiftNavigation

### H14: Missing `@available` on `@Observable` class declarations
- **Files:** `ObservationModels.swift:7,17,24,30`, `ViewModel.swift:9`, various test files
- **Rule:** `@Observable` requires iOS 17+ — needs availability annotation or use `@Perceptible`
- **Skill:** Perception

---

## MEDIUM (top themes, deduplicated)

### M1: `asc()` without NULL customization (7 occurrences)
- **File:** `StructuredQueriesTests.swift:248,261,302,325,342,355,365`
- **Fix:** Use `order(by: \.field)` for ascending, not `.asc()`
- **Skill:** StructuredQueries

### M2: Missing `@CasePathable` on Action enums (5 fuse-app features)
- **Fix:** Add `@CasePathable` to all Action enum declarations
- **Skill:** CasePaths

### M3: `if case` instead of `.is(\.case)` / `[case:]` subscript (6+ test sites)
- **Files:** ObservableStateTests, NavigationTests, NavigationStackTests, StoreReducerTests
- **Fix:** Use `.is(\.caseName)` for case checks, `[case:]` subscript for extraction
- **Skill:** CasePaths

### M4: `XCTAssertEqual` instead of `expectNoDifference` (7+ sites)
- **Files:** StoreReducerTests, EffectTests, TestStoreTests, FuseAppIntegrationTests
- **Fix:** Replace with `expectNoDifference` for struct/array comparisons
- **Skill:** CustomDump

### M5: Transitive deps in test targets (4)
- **Files:** fuse-library/Package.swift (Dependencies, DependenciesMacros in TCATests), fuse-app/Package.swift (ComposableArchitecture, GRDB in FuseAppIntegrationTests)
- **Fix:** Remove transitively-available deps from test target dependency lists
- **Skill:** Testing

### M6: Uncontrolled `UUID()`/`Date()` in model defaults (4)
- **Files:** `SharedModels.swift:16,31` (Todo, Contact init defaults)
- **Fix:** Remove default values, require explicit injection via `@Dependency`
- **Skills:** Dependencies, TCA

### M7: Raw `db.execute(sql:)` instead of `#sql` macro (3+)
- **Files:** DatabaseFeature.swift migration, FuseAppIntegrationTests, StructuredQueriesTests setup
- **Fix:** Use `#sql("""...""").execute(db)` for compile-time SQL checking
- **Skill:** SQLiteData

### M8: No `.dependencies` trait in test suites (10+)
- **Issue:** Tests bypass `bootstrapDatabase()` pattern, use inline DatabaseQueue construction
- **Fix:** Use `.dependencies { try $0.bootstrapDatabase() }` suite trait
- **Skill:** SQLiteData, Testing

### M9: `DatabaseQueue(path:)` instead of `SQLiteData.defaultDatabase()`
- **File:** `DatabaseFeature.swift:21`
- **Fix:** Use `SQLiteData.defaultDatabase()` for proper WAL mode/multi-reader setup
- **Skill:** SQLiteData

### M10: `bootstrapDatabase` invoked in view init, not `@main` entry point
- **File:** `FuseApp.swift:22-26`
- **Fix:** Move to `@main` App struct's `init()`
- **Skill:** SQLiteData

### M11: Boolean sheet state instead of optional state
- **File:** `UIPatternTests.swift:115` (SheetToggleFeature)
- **Fix:** Use `@Presents var sheet: SheetContent.State?`
- **Skill:** SwiftNavigation

### M12: Manual `destination = nil` skips PresentationReducer effect cancellation
- **Files:** `ContactsFeature.swift:56,165`
- **Fix:** Use `@Dependency(\.dismiss)` in child, or document side-effect-free constraint
- **Skill:** SwiftNavigation

### M13: Android path omits `NavigationStack(path:)` — StackState silently unused
- **File:** `ContactsFeature.swift:268-278`
- **Fix:** Implement path binding on Android or remove StackState for Android
- **Skill:** SwiftNavigation

### M14: Observation tests use Combine exclusively, never `Observations { ... }` async sequence
- **File:** `SharedObservationTests.swift`
- **Rule:** Prefer Observations framework over Combine
- **Skill:** Sharing

### M15: Unhandled errors in `Effect.run` closures
- **File:** `DatabaseFeature.swift:74,87,105`
- **Fix:** Add `do/catch` with `reportIssue(error)` or dedicated error action
- **Skill:** IssueReporting

### M16: `@Column("itemCount")` redundant — name matches property
- **File:** `StructuredQueriesTests.swift:30`
- **Fix:** Remove `@Column("itemCount")`, keep just `var itemCount: Int`
- **Skill:** StructuredQueries

### M17: `ObservationRegistrar` shadow type in skip-android-bridge
- **File:** `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift:18`
- **Fix:** Rename namespace to avoid shadowing `Observation` module
- **Skill:** Perception

---

## LOW (top themes, abbreviated)

- `onAppear` naming → prefer `viewAppeared` (TCA convention, 3 files)
- `addNoteTapped` inconsistent with `addButtonTapped` pattern (TCA, 1 file)
- Two separate `@Presents` instead of single Destination enum (TodosFeature)
- Draft insert form preferred over column-specifying form (4 test sites)
- `print()` in stress tests → prefer `customDump` for structured output
- `try!` in test helpers → use `throws` propagation
- `try?` silently drops cancellation in ObservationBridgeTests
- `DispatchSemaphore` in bridge code → prefer `os_unfair_lock`
- `FlagBox` `@unchecked Sendable` relies on undocumented implementation detail
- `#expect(Bool(true))` no-op assertions in NavigationStackTests, PresentationTests
- Missing test coverage for `append(contentsOf:)` / `sort` on IdentifiedArray
- `appearance` shared key uses empty string sentinel without semantic type
- `@_spi(Reflection) import CasePaths` in DependencyTests — fragile SPI
- `private` cancel-ID enums → prefer `fileprivate` for CasePaths compatibility

---

## Recommended Fix Priorities

### Wave 1 — Must fix (CRITICAL + blocking HIGH)
1. Fix `.toggleCategory` → `.categoryFilterChanged` in integration test (C1)
2. Add `withErrorReporting` to `try!` in FuseApp.swift (H8)
3. Remove `import GRDB` from app and test sources (H6)

### Wave 2 — Structural alignment
4. `var id` → `let id` on remaining `@Table` models (H4)
5. `static let` → `static var` on DependencyKey conformances (H9)
6. Un-nest `Path` features from parent reducers (H1)
7. Remove `Action: Equatable` from all test reducers (H3)
8. Replace infix operators with `.eq()`/`.gt()` in `.where` closures (H5)
9. Replace `asc()` with `order(by: \.field)` in 7 locations (M1)
10. Add `@CasePathable` to fuse-app Action enums (H11)

### Wave 3 — Test modernisation (largest volume, lowest urgency)
11. Migrate XCTest files to Swift Testing `@Suite` pattern (H10)
12. Replace `XCTAssertEqual` with `expectNoDifference` for struct/array comparisons (M4)
13. Add `.dependencies { try $0.bootstrapDatabase() }` trait to database test suites (M8)
14. Remove transitive deps from test target Package.swift entries (M5)
15. Replace `if case` with `.is()` / `[case:]` subscript in test assertions (M3)
