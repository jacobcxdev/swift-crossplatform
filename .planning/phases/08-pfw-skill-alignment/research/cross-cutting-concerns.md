# Cross-Cutting Concerns — Phase 8 PFW Skill Alignment

Prepared: 2026-02-23
Scope: All 191 audit findings across fuse-app sources, fuse-library tests, fuse-app integration tests, and fork code.

---

## Ordering Hazards

Changes that MUST happen before other changes, or the build breaks.

### OH-1: `@CasePathable` on Action enums BEFORE any `\.caseName` key-path usage

**Finding:** H11 / M2 require adding `@CasePathable` to top-level Action enums in fuse-app. Five features are missing it:
- `AppFeature.Action` (`AppFeature.swift:22`)
- `ContactsFeature.Action` (`ContactsFeature.swift:25`)
- `ContactDetailFeature.Action` (`ContactsFeature.swift:106`)
- `DatabaseFeature.Action` (`DatabaseFeature.swift:55`)
- `TodosFeature.Action` (`TodosFeature.swift:35`)

**Hazard:** M3 requires replacing `if case` patterns with `.is(\.caseName)` and `[case:]` subscripts in test files. Those replacements use `@CasePathable`-generated accessors on `Action` types. If you apply M3 first the test files will not compile because the key paths do not exist yet.

**Order required:** Add `@CasePathable` to all Action enums (H11) → then replace `if case` with `.is()` / `[case:]` (M3).

**Caveat:** `@Reducer` already synthesises case paths for actions used via `store.send(\.caseName)` in TestStore. Adding `@CasePathable` explicitly should not conflict, but verify there is no double-synthesis warning before proceeding with M3 callsites.

---

### OH-2: `IdentifiedArrayOf<Todo>` type change BEFORE any callsite migration

**Finding:** H12 requires changing `[Todo]` to `IdentifiedArrayOf<Todo>` in two places:
- `SharedModels.swift:64` — `FileStorageKey<[Todo]>` extension
- `SettingsFeature.swift:15` — `@Shared(.savedTodos) var savedTodos: [Todo]`

**Hazard:** The `FileStorageKey` type parameter is part of the `SharedKey` extension signature. Every callsite that reads `store.savedTodos` or passes `savedTodos` as `[Todo]` will break the moment the storage key changes type. The change in `SharedModels.swift` and `SettingsFeature.swift` must be a single atomic commit; they cannot be split across separate steps.

**Cascade:** `SettingsFeature.State` exposes `savedTodos` as a property accessed in `SettingsView` and `FuseAppIntegrationTests`. Those callsites use `.count` which works on both types, but any code constructing `[Todo]` literals and passing them as `savedTodos` will require an `IdentifiedArrayOf(uniqueElements:)` wrapper.

**Codable migration note:** `IdentifiedArrayOf` conforms to `Codable` and encodes as a JSON array, so existing `todos.json` files on disk (if any) will continue to decode correctly — no migration file needed.

---

### OH-3: Remove `import GRDB` from `FuseApp` target BEFORE removing `GRDB` from target dependencies

**Finding:** H6 requires removing `import GRDB` from:
- `DatabaseFeature.swift:3`
- `FuseAppIntegrationTests.swift:2`
- `FuseApp/Package.swift` — `GRDB` product listed in `FuseApp` target dependencies (line 46) and `FuseAppIntegrationTests` target dependencies (line 57)

**Hazard:** `DatabaseFeature.swift` uses `DatabaseQueue`, `DatabaseMigrator`, and `Database` types. These are re-exported by `SQLiteData` via `@_exported import GRDB`. Removing `import GRDB` will compile only if `SQLiteData`'s re-export covers all the symbols used. If any symbol is NOT re-exported, removing the import will break the build even though the Package.swift dependency is still present.

**Order required:**
1. Remove `import GRDB` from source files.
2. Verify build passes (`swift build`).
3. Only then remove `GRDB` from the Package.swift target dependency lists.

Reversing steps 2 and 3 will cause a build failure that cannot be diagnosed until you put the import back.

---

### OH-4: `Path` un-nesting BEFORE test file updates that reference the nested type

**Finding:** H1 requires moving `@Reducer enum Path` from inside `ContactsFeature` to file scope as `ContactsFeaturePath`. The same pattern applies to `NavigationTests.swift` and `NavigationStackTests.swift` in fuse-library.

**Hazard:** `FuseAppIntegrationTests.swift:201` constructs `ContactDetailFeature.State` inside `state.path.append(.detail(...))`. It references `ContactsFeature.Path` implicitly through the `StackState<Path.State>` type. After the rename the type is `ContactsFeaturePath.State` — every existing test reference breaks.

**Cascade:** The `ContactsFeature.State` field `var path = StackState<Path.State>()` must be updated to `StackState<ContactsFeaturePath.State>()` at the same time as the enum is moved. The `ReducerOf<Self>` body `.forEach(\.path, action: \.path)` uses `Path` implicitly — it will also require updating.

**Order required:** Move the enum and update all references (State field, forEach, test callsites) in a single commit. Do not split.

---

### OH-5: `prepareDependencies` / `bootstrapDatabase` relocation BEFORE `import Dependencies` removal from `FuseApp.swift`

**Finding:** M10 requires moving `bootstrapDatabase()` from the `FuseAppRootView.init()` body to the `@main` App struct `init()`. The current code in `FuseApp.swift` uses `prepareDependencies { ... }` wrapper.

**Hazard:** `FuseApp.swift` currently imports `Dependencies` explicitly (line 5). Once `bootstrapDatabase` is moved to a different file (or the `@main` struct), the `import Dependencies` in `FuseApp.swift` may become unused. Removing it before the move will break the build; removing it after is safe.

**Order required:** Move bootstrap logic first, then clean up the import.

---

## Cascade Effects

Changes with wide blast radius touching many files simultaneously.

### CE-1: XCTest → Swift Testing migration (H10) — 17+ files, 314 XCT assertions

**Scope of change:**
- 17 `final class * : XCTestCase` declarations across both test bundles (grep confirmed count)
- 314 `XCTAssert*` call sites spanning all test targets
- Every file in: `TCATests/` (6 files), `SharingTests/` (3 files), `DatabaseTests/` (2 files), `ObservationTests/` (partially — `FuseLibraryTests.swift`, `ObservationTests.swift`), `FuseAppIntegrationTests/` (1 file with 8 classes)

**Files already on Swift Testing (do not migrate):**
- `NavigationTests/NavigationTests.swift` — struct with `@Test`
- `NavigationTests/NavigationStackTests.swift` — struct with `@Test`
- `NavigationTests/PresentationTests.swift` — struct with `@Test`
- `NavigationTests/UIPatternTests.swift` — struct with `@Test`
- `ObservationTests/ObservationBridgeTests.swift` — `@Suite` struct
- `ObservationTests/StressTests.swift` — `@Suite` struct
- `FoundationTests/CasePathsTests.swift`, `CustomDumpTests.swift`, `IdentifiedCollectionsTests.swift`, `IssueReportingTests.swift` — all free `@Test` functions

**Mixed file hazard:** `TCATests/DependencyTests.swift` has one remaining `XCTExpectFailure` call (line 364) while everything else in that class uses XCT assertions. When migrating this file, the `XCTExpectFailure` must become `withKnownIssue` (already the pattern used in `CustomDumpTests.swift` and `TestStoreTests.swift`).

**Package.swift impact:** `TCATests` target currently lists `DependenciesMacros` as an explicit dependency. After migration to Swift Testing, verify whether `DependenciesMacros` is genuinely imported in the test file or only transitively needed — M5 says to remove transitive deps, which may require coordinating the import-cleanup with the framework migration.

---

### CE-2: `Action: Equatable` removal (H3) — 7 files, affects `TestStore` exhaustivity

**Scope:** 11 `enum Action: Equatable` declarations across:
- `TestStoreTests.swift` (7 occurrences: lines 38, 109, 157, 182, 208, 236, 263)
- `TestStoreEdgeCaseTests.swift` (1 occurrence: line 42)
- `CasePathsTests.swift` (2 occurrences: lines 5, 13 — but these are standalone enums, not TCA Actions)
- `NavigationTests.swift` (1: line 182 — `AlertAction: Equatable`, not a top-level Action)

**Hazard:** `TestStore` uses case-path matching (via `store.receive(\.caseName)`) not equality for action matching. Removing `Equatable` from Actions is safe IF no test is using `XCTAssertEqual(action, ...)` directly. The grep shows no such direct equality comparisons on Actions, so removal is safe once you verify. However, `CasePathsTests.swift` enums (`Action: Equatable`, `ChildAction: Equatable`) are fixture types for CasePaths tests — NOT TCA Actions — and should retain `Equatable` because the tests use `#expect(path.extract(from: action) == "hello")`.

**Order note:** Do not remove `Equatable` from `CasePathsTests.swift` fixture enums — H3 applies to TCA `Action` types only.

---

### CE-3: `savedTodos: [Todo]` → `IdentifiedArrayOf<Todo>` cascade through Settings feature

**Scope of change beyond H12:**
- `SharedModels.swift:64` — extension type signature
- `SettingsFeature.swift:15` — `@Shared` property declaration
- `SettingsView.swift` (embedded in `SettingsFeature.swift:96`) — `store.savedTodos.count` still works, no change needed
- `FuseAppIntegrationTests.swift` — no direct `savedTodos` manipulation found, so integration tests are unaffected
- Any Codable test that round-trips `savedTodos` through JSON — none found

The blast radius is smaller than it looks: only 2 source lines change. But the type system enforces the change atomically.

---

### CE-4: `onAppear` → `viewAppeared` rename (LOW) — affects 3 features + their test files

**Scope:** `onAppear` appears in:
- `ContactsFeature.swift`: `Action.onAppear` (line 30), reducer case (line 62), view `.task` (line 324)
- `SettingsFeature.swift`: `Action.onAppear` (line 26), reducer case (line 58), view `.task` (line 115)
- `DatabaseFeature.swift`: `Action.onAppear` (line 56), reducer case (line 72), view `.task` (line 205)
- `FuseAppIntegrationTests.swift`: `await store.send(.onAppear)` (line 186)

**Cascade:** Renaming `Action.onAppear` to `Action.viewAppeared` requires simultaneous updates to: (1) the `enum Action` case declaration, (2) the `switch action` handler, (3) the view's `.task { store.send(.viewAppeared) }` call, and (4) every test that sends `.onAppear`. All four locations must change atomically per feature, or the build will fail between steps.

---

### CE-5: `static let` → `static var` on DependencyKey (H9) — already partially fixed, but fork code also affected

**Scope:** The audit identified `static let liveValue`, `static let testValue`, `static let previewValue` in `SharedModels.swift:82-87`. The current source shows only `static var liveValue`, `static var testValue`, `static var previewValue` for `NumberFactClient` — these appear to already be `var` (not found by grep for `static let liveValue`). The grep for `static let testValue` found only one hit: `DependencyTests.swift:504` — the `NumberClient` fixture struct which uses `static let testValue = NumberClient()`. This fixture conforms to `TestDependencyKey`, not `DependencyKey`, but the same rule applies. Confirm whether this is in scope per H9.

---

## Build Breakage Windows

Periods during migration where the build will definitely be broken if changes are applied partially.

### BBW-1: Path un-nesting window

**Duration:** From the moment `@Reducer enum Path` is removed from `ContactsFeature` until all `StackState<Path.State>` references across `ContactsFeature.swift`, `AppFeature.swift`, and `FuseAppIntegrationTests.swift` are updated.

**Mitigation:** Make the move in a single editor pass with a project-wide rename, not file-by-file. Use LSP rename if available; otherwise use sed-equivalent before building.

---

### BBW-2: `import GRDB` removal window

**Duration:** From the moment `import GRDB` is removed from `DatabaseFeature.swift` until the compiler confirms all GRDB symbols are covered by `SQLiteData`'s re-export.

**Key unknown:** `DatabaseQueue: @unchecked @retroactive Sendable` conformance at `DatabaseFeature.swift:12` — this retroactive conformance requires the concrete `DatabaseQueue` type to be in scope. If `SQLiteData` re-exports `DatabaseQueue` (which it should, since it wraps GRDB), this will compile. If not, the conformance declaration will fail with "cannot find type 'DatabaseQueue'". Verify by removing the import in isolation before the Package.swift dep removal.

---

### BBW-3: Swift Testing migration window for each test class

**Duration:** During conversion of each `final class * : XCTestCase` to a `struct * { @Test func... }`. The intermediate state (partial conversion within a file) will fail to compile because `XCTestCase` methods and Swift Testing `@Test` functions have different signatures and cannot coexist in an ambiguous way within the same type.

**Mitigation:** Convert one test class at a time, building after each conversion. Do not batch multiple classes within a file into a single edit.

---

### BBW-4: `IdentifiedArrayOf<Todo>` storage key window

**Duration:** Approximately 2 lines. The `FileStorageKey<[Todo]>` extension and `@Shared(.savedTodos) var savedTodos: [Todo]` must both change to `IdentifiedArrayOf<Todo>` before the build can succeed. If only one is changed, the `SharedKey` type mismatch will cause a compiler error at the `SettingsFeature.State` declaration.

**Mitigation:** Edit `SharedModels.swift` and `SettingsFeature.swift` in the same commit or editor pass.

---

### BBW-5: `CombineReducers` removal (H2)

**Finding:** `StoreReducerTests.swift:134-151` defines a `Combined` reducer using `CombineReducers { Reduce { ... } Reduce { ... } }` without any `ifLet`/`forEach` modifier. The audit says to remove `CombineReducers` when no modifier is applied.

**Hazard:** Removing `CombineReducers` here means the two `Reduce` closures need to be merged into one, or `Scope` composition used. The test `testCombineReducers()` at line 334 validates the dual-reducer behaviour (count + log). The test logic itself is valid; the issue is the API pattern. If you simply delete `CombineReducers` and keep two `Reduce` closures without composition, the body will not type-check because `ReducerOf<Self>` requires a single `body`. The fix is to merge the two `Reduce` closures into one.

**Window:** From `CombineReducers { ... }` deletion until both `Reduce` closures are merged and the test updated.

---

## Missing from Audit

Items not explicitly called out in the PFW audit but observed in the source code that should be fixed for full PFW alignment.

### MA-1: `StructuredQueriesSQLite` imported directly in app source (not audited)

**Files:**
- `SharedModels.swift:6` — `import StructuredQueriesSQLite`
- `DatabaseFeature.swift:7` — `import StructuredQueriesSQLite`

**Issue:** The PFW audit flagged `import GRDB` (H6) as violating the "import only the public surface" rule, but did NOT flag `import StructuredQueriesSQLite`. The same principle applies: `SQLiteData` re-exports `StructuredQueriesSQLite` via `@_exported import`. App code importing `StructuredQueriesSQLite` directly bypasses the public API surface the same way `import GRDB` does.

**Risk if not fixed:** Phase 8 fixes H6 but leaves `StructuredQueriesSQLite` direct imports in place — inconsistent policy. If the fork ever moves StructuredQueries behind a different module boundary, the direct import breaks.

---

### MA-2: `DatabaseFeature.swift` imports `StructuredQueries` AND `StructuredQueriesSQLite` separately

**File:** `DatabaseFeature.swift:6-7`

`StructuredQueries` is the pure query layer; `StructuredQueriesSQLite` adds the SQLite execution layer. `SQLiteData` re-exports both. Importing either directly is the same violation as H6 (`import GRDB`). Both should be replaced with `import SQLiteData` alone.

---

### MA-3: `DatabaseFeature.State.notes` uses `[Note]` not `IdentifiedArrayOf<Note>`

**File:** `DatabaseFeature.swift:49` — `var notes: [Note] = []`

**Issue:** `Note` is `Identifiable` (it has `let id: Int64`). The audit's H12 calls out `[Todo]` for `@Shared(.fileStorage)`. The same `IdentifiedArrayOf` rule from `pfw-identified-collections` applies to any `Identifiable` collection held in TCA `State`. `notes` in `DatabaseFeature.State` is accessed via `state.notes.insert(note, at: 0)` and `state.notes.removeAll { $0.id == id }` — both of which have `IdentifiedArrayOf`-native equivalents (`append` and `remove(id:)`). The audit missed this instance.

**Cascade if fixed:** `DatabaseFeature.State` Equatable conformance is unaffected (IdentifiedArrayOf is Equatable). The `.notesLoaded([Note])` action payload would also need to change to `IdentifiedArrayOf<Note>` or be converted at the action boundary. `FuseAppIntegrationTests.swift` line 342 constructs `$0.notes = [Note(...)]` — that test line would need to become `IdentifiedArrayOf(uniqueElements: [Note(...)])`.

---

### MA-4: `XCTExpectFailure` in `DependencyTests.swift` uses XCTest-era API, not `withKnownIssue`

**File:** `fuse-library/Tests/TCATests/DependencyTests.swift:364`

```swift
XCTExpectFailure {
    $0.compactDescription.contains("Unimplemented")
}
```

The test class `DependencyTests` is `final class DependencyTests: XCTestCase` — scheduled for H10 migration to Swift Testing. `XCTExpectFailure` does not exist in Swift Testing; the equivalent is `withKnownIssue`. The audit noted this as a "Claude's discretion" item, but the code already uses `withKnownIssue` in `TestStoreTests.swift` and `CustomDumpTests.swift`. The pattern is already established; this is a mechanical substitution.

**Migration detail:** The `XCTExpectFailure` block here checks `$0.compactDescription.contains("Unimplemented")`. In `withKnownIssue` the equivalent is:
```swift
withKnownIssue("Unimplemented") {
    let result = client.fetch(42)
    #expect(result == 0)
}
```

---

### MA-5: `DatabaseFeature.Action.addNoteTapped` violates PFW naming convention

**File:** `DatabaseFeature.swift:57` — `case addNoteTapped`

**Issue:** The LOW findings note that `addNoteTapped` is inconsistent with the `addButtonTapped` pattern used in `ContactsFeature`, `TodosFeature`, and `CounterFeature`. The audit does call this out as LOW, but the integration tests at `FuseAppIntegrationTests.swift:340` send `.addNoteTapped` directly — renaming requires simultaneous test update.

---

### MA-6: `SettingsFeature.State` has `@ObservationStateIgnored var debugInfo` with no usage

**File:** `SettingsFeature.swift:17` — `@ObservationStateIgnored var debugInfo: String = ""`

**Issue:** `debugInfo` is declared but never set or read anywhere in the codebase (no grep hits for `debugInfo`). Dead state fields inflate the `State` struct's memory footprint and muddy `Equatable` comparisons. This was not mentioned in the audit. It should either be removed or documented with a `// TODO: populate in debug builds` comment.

---

### MA-7: `DatabaseFeature` does not participate in `@Shared` state at all — `notes` is ephemeral

**File:** `DatabaseFeature.swift:49` — `var notes: [Note] = []`

**Issue:** The database notes are fetched on `onAppear` and held in ephemeral `State`. When the app backgrounds and returns, `onAppear` re-fires and reloads. This is the `M9` / `M10` polling pattern the audit identified. What the audit did NOT call out is that there is also no persistence of the current filter selection (`selectedCategory: String = "all"`) — it resets on every appear. Whether this is intentional or a bug is unclear, but it is a missing-audit item for the `pfw-sharing` skill (store per-session filter in `@Shared(.inMemory(...))`).

---

### MA-8: `FuseApp` target depends on `GRDB` product in Package.swift but also on `SQLiteData`

**File:** `examples/fuse-app/Package.swift:46` — `GRDB` listed in `FuseApp` target dependencies alongside `SQLiteData`

**Issue:** After removing `import GRDB` from all source files (H6), the `GRDB` product should also be removed from the `FuseApp` target dependency list in Package.swift. The audit called out the import change but not the Package.swift dep list change for the `FuseApp` target itself (only the `FuseAppIntegrationTests` target was mentioned for M5). Both target entries need cleaning.

---

### MA-9: `@_spi(Reflection) import CasePaths` still present in `DependencyTests.swift`

**File:** `fuse-library/Tests/TCATests/DependencyTests.swift:1`

The LOW findings note this as fragile SPI. The import is used for `EnumMetadata(TestAction.self)` in the `testNavigationIDEnumMetadataTag` test. The canonical fix is to move that test to `FoundationTests/CasePathsTests.swift` where `@_spi(Reflection)` is already imported (line 1 of that file), removing the SPI import from `DependencyTests.swift` entirely.

---

### MA-10: `private cancel-ID enum CancelID` in `EffectTests.swift` — should be `fileprivate`

**File:** `fuse-library/Tests/TCATests/EffectTests.swift:120` — `enum CancelID: Hashable { case timer }`

The LOW findings say `private` cancel-ID enums should be `fileprivate` for CasePaths compatibility. This enum is file-scope with no access modifier (implicitly `internal`), which is actually fine. However `CancellableFeature` and `CancelInFlightFeature` both use `CancelID.timer` and are in the same file — the risk here is if a macro tries to generate case paths for `CancelID`. Since `CancelID` is not `@CasePathable`, this is lower risk but worth confirming during the migration.

---

## Recommended Wave Structure

Batch changes to minimise the number of build-broken commits and maximise parallelism.

### Wave 0 — Verification baseline (before any changes)

Run `make test` and record the exact passing count (expected: 247 total from Phase 7). This is the regression baseline for all subsequent waves.

---

### Wave 1 — Atomic single-file fixes (no cascade, lowest risk)

Apply these independently; each can be a standalone commit with a passing build:

1. **H4** — `var id` → `let id` on `@Table` models (already done per context, verify)
2. **H5 + M1** — Replace infix `==`/`>` with `.eq()`/`.gt()` and `asc()` with `order(by:)` in `StructuredQueriesTests.swift` and `SQLiteDataTests.swift`
3. **M16** — Remove redundant `@Column("itemCount")` annotation (already done per context, verify)
4. **H8** — `try!` → `withErrorReporting` (already done per context, verify `FuseApp.swift`)
5. **H9** — `static let` → `static var` on DependencyKey values (verify current state; grep found only one remaining `static let testValue` in `DependencyTests.swift:504`)
6. **MA-6** — Remove unused `debugInfo` from `SettingsFeature.State`
7. **MA-7** — Decide: add `@Shared(.inMemory)` for `selectedCategory` or document as intentional

---

### Wave 2 — Structural alignment (ordered, some cascade)

Apply in the order listed within this wave; do not parallelise within the wave:

1. **H11 + M2** — Add `@CasePathable` to all five top-level Action enums in fuse-app (must precede M3)
2. **M3** — Replace `if case` with `.is()` / `[case:]` in test files (depends on Wave 2 step 1)
3. **H1** — Un-nest `@Reducer enum Path` from `ContactsFeature` → `ContactsFeaturePath`, update all references atomically (State field, forEach, test callsites) — **single commit**
4. **H2** — Merge dual `Reduce` closures in `Combined` / `StoreReducerTests.swift`; remove `CombineReducers`
5. **H12** — Change `[Todo]` to `IdentifiedArrayOf<Todo>` in `SharedModels.swift` + `SettingsFeature.swift` — **single commit**
6. **MA-3** — Change `[Note]` to `IdentifiedArrayOf<Note>` in `DatabaseFeature.State` + update action payloads and integration tests — **single commit**
7. **H13** — Replace `state.path.popLast()` with canonical dismiss pattern in `ContactsFeature.swift:48`
8. **M11** — Replace boolean sheet state with `@Presents` optional in `UIPatternTests.swift:SheetToggleFeature`
9. **M12** — Replace manual `destination = nil` with `@Dependency(\.dismiss)` in `ContactsFeature.swift:56,165`
10. **H14** — Add `@available(iOS 17, macOS 14, *)` annotations to all `@Observable` declarations (or switch to `@Perceptible` per pfw-perception)
11. **M6** — Remove default `UUID()`/`Date()` from `Todo` and `Contact` init defaults; require explicit injection

---

### Wave 3 — Database & import cleanup (ordered)

1. **H6 + MA-1 + MA-2** — Remove `import GRDB`, `import StructuredQueriesSQLite`, `import StructuredQueries` from all app/test sources; verify build passes with `import SQLiteData` only — **build verification required after each file**
2. **MA-8** — Remove `GRDB` product from `FuseApp` target dependencies in `Package.swift` (after Wave 3 step 1 confirms no remaining GRDB direct imports)
3. **M5** — Remove transitive deps from `FuseAppIntegrationTests` target (`ComposableArchitecture`, `GRDB`) and from `TCATests` target (`Dependencies`, `DependenciesMacros`) in their respective Package.swift files
4. **M9** — Switch `DatabaseQueue(path:)` to `SQLiteData.defaultDatabase()`
5. **M10 + OH-5** — Move `bootstrapDatabase()` call to `@main` App struct `init()`, then clean up `FuseApp.swift` imports
6. **H7** — Refactor `DatabaseView` to use `@FetchAll`/`@FetchOne` property wrappers (largest single change in this wave)
7. **M7** — Replace raw `db.execute(sql:)` with `#sql` macro in migration and test helpers
8. **M8** — Add `.dependencies { try $0.bootstrapDatabase() }` suite trait to database test suites
9. **M13** — Fix or explicitly document `NavigationStack` Android path binding gap in `ContactsFeature.swift`

---

### Wave 4 — Test modernisation (largest volume, can parallelise across test targets)

Each test file can be migrated independently, but within a file the conversion must be complete before the build will succeed:

**Priority order (most assertions first):**
1. `StructuredQueriesTests.swift` (73 XCT assertions) — convert `StructuredQueriesTests` class
2. `SQLiteDataTests.swift` (36 XCT assertions) — convert `SQLiteDataTests` class
3. `ObservationTests.swift` (33 XCT assertions) — convert `ObservationTests` class
4. `ObservableStateTests.swift` (29 XCT assertions) — convert `ObservableStateTests` class
5. `StoreReducerTests.swift` (20 XCT assertions) — convert `StoreReducerTests` class
6. `DependencyTests.swift` (31 XCT assertions + 1 `XCTExpectFailure`) — migrate + fix MA-4, MA-9
7. `SharedObservationTests.swift` (11 XCT assertions) — convert + fix M14 (Combine → `Observations`)
8. `SharedBindingTests.swift` (11 XCT assertions) — convert
9. `SharedPersistenceTests.swift` (20 XCT assertions) — convert
10. `EffectTests.swift` (11 XCT assertions) — convert
11. `TestStoreEdgeCaseTests.swift` (1 XCT assertion) — convert (smallest, easiest)
12. `TestStoreTests.swift` (6 XCT assertions + existing `withKnownIssue`) — convert
13. `BindingTests.swift` (18 XCT assertions) — convert
14. `FuseAppIntegrationTests.swift` (8 XCT assertions across 8 classes) — convert, add `@Suite`
15. Add `expectNoDifference` (M4) to struct/array comparisons during or after the XCT → `#expect` pass

**H10 `@Suite` base pattern note:** The pfw-testing skill prescribes a `@Suite(.serialized, .dependencies { ... }) struct BaseSuite {}` pattern. Verify whether a base suite struct is needed or if per-file `@Suite` attributes on each test struct suffice. UIPatternTests.swift (already migrated) uses a plain `@MainActor struct UIPatternTests` without `@Suite` — this is the de facto template used in this project. Follow the same pattern for consistency unless the pfw-testing skill prescribes otherwise.

---

### Wave 5 — Fork code cleanup (independent of app/test changes)

1. **M17** — Rename `ObservationRegistrar` shadow type in `skip-android-bridge`
2. **LOW: DispatchSemaphore** — Replace with `os_unfair_lock` in bridge code
3. **LOW: FlagBox `@unchecked Sendable`** — Address the undocumented implementation detail
4. **LOW: `private` cancel-ID enums** — Change to `fileprivate` where CasePaths compatibility is needed

---

### Wave 6 — Assertion modernisation pass (cleanup)

1. **M4** — Replace remaining `XCTAssertEqual` with `expectNoDifference` for struct/array comparisons (can be done alongside Wave 4 or after)
2. **LOW: `onAppear` → `viewAppeared`** — Rename across 3 features + integration tests (CE-4)
3. **LOW: `addNoteTapped` → `addButtonTapped`** — Rename in `DatabaseFeature` + integration tests (MA-5)
4. **LOW: `appearance` shared key empty-string sentinel** — Evaluate whether a semantic type (`enum Appearance`) is preferable
5. **LOW: Two separate `@Presents`** — Consolidate into single `Destination` enum in `TodosFeature`
6. **M14** — Replace Combine-only tests in `SharedObservationTests` with `Observations { ... }` async sequence
7. **M15** — Add `do/catch` with `reportIssue(error)` to unhandled errors in `Effect.run` closures (`DatabaseFeature.swift:74,87,105`)

---

## Summary Risk Table

| Finding | Files Affected | Cascade Risk | Build Breakage Window |
|---------|---------------|-------------|----------------------|
| H1 (Path unnest) | 3–5 | High | Yes — multi-file atomic |
| H11 + M3 (CasePathable) | 6+ | Medium | No if ordered correctly |
| H12 (IdentifiedArrayOf Todo) | 2 | Low | Yes — must be atomic |
| MA-3 (IdentifiedArrayOf Note) | 3 | Medium | Yes — must be atomic |
| H6 + MA-1/2 (import cleanup) | 5 | Medium | Yes — verify before dep removal |
| H10 (XCTest → Swift Testing) | 17 files | High | Yes — per-file breakage window |
| H2 (CombineReducers) | 1 | Low | Short |
| M6 (UUID/Date defaults) | 2 + all callers | Medium | Depends on callers |
| H13 (popLast) | 1 | Low | No |
| MA-4 (XCTExpectFailure) | 1 | Low | No |
| MA-9 (@_spi move) | 2 | Low | No |
