# PFW Testing Skill — Research

Generated: 2026-02-23
Source skill: `/Users/jacob/.claude/skills/pfw-testing/`
Audit input: `.planning/PFW-AUDIT-RESULTS.md` (H10, M4, M5, M8, and all testing LOW items)

---

## Canonical Patterns

### 1. Base Suite Pattern (H10)

Define ONE base suite per test bundle with shared traits:

```swift
@Suite(
  .serialized,
  .dependencies {
    // shared dependency overrides for all child suites
  }
)
struct BaseSuite {}
```

Extend the base suite with individual suites and tests so they inherit all traits:

```swift
extension BaseSuite {
  @Suite struct FeatureTests {
    @Test func testSomething() { ... }
  }
}

extension BaseSuite {
  @Suite struct ModelTests {
    @Test func testSomethingElse() { ... }
  }
}
```

Rules:
- `@Suite` and trait inheritance work for `@Test` functions and nested `@Suite` structs.
- `@MainActor` does NOT inherit through extensions — annotate individual `@Test` funcs directly.
- `.serialized` is the correct trait for test isolation (replaces XCTestCase's serial-by-default behavior).
- `.dependencies { ... }` is the Swift Testing trait that controls `@Dependency` values for the entire suite tree.

### 2. No Transitive Dependencies in Test Targets (M5)

A test target already receives all transitive dependencies from the target it tests. It MUST NOT re-list them:

```swift
// CORRECT — MyLibrary brings ComposableArchitecture transitively
.testTarget(
  name: "MyLibraryTests",
  dependencies: [
    "MyLibrary",
    .product(name: "CustomDump", package: "swift-custom-dump"),
    // DO NOT add ComposableArchitecture here — transitive from MyLibrary
  ]
)

// WRONG — explicit re-listing of a transitive dep
.testTarget(
  name: "MyLibraryTests",
  dependencies: [
    "MyLibrary",
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), // redundant
  ]
)
```

### 3. `.dependencies` Trait for Database Test Suites (M8)

When tests need a database, bootstrap it in the suite trait, not inline per test:

```swift
@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct DatabaseSuite {}
```

Do NOT construct `DatabaseQueue` inline per test method. All tests in the suite share the bootstrapped database through `@Dependency(\.defaultDatabase)`.

### 4. `expectNoDifference` Instead of `XCTAssertEqual` (M4)

For any struct, array, or model comparison use `expectNoDifference` from CustomDump:

```swift
// CORRECT
expectNoDifference(store.state.todos, expectedTodos)
expectNoDifference(items, [Item(id: 1, name: "alpha")])

// WRONG — use only for primitives if at all
XCTAssertEqual(store.state.todos, expectedTodos)
```

Rule: `XCTAssertEqual` is acceptable ONLY for primitive scalars (Int, Bool, String) in XCTest files that have not yet been migrated. In Swift Testing files use `#expect` for primitives and `expectNoDifference` for structured types.

### 5. Better Failures — Custom Dump Integration (M4)

Import `CustomDump` in test targets that compare models:

```swift
import CustomDump   // provides expectNoDifference, expectDifference, String(customDumping:)
```

`expectNoDifference` produces a diff on failure showing exactly which fields diverged, vs `XCTAssertEqual`'s opaque "not equal" message.

### 6. Dependencies in Tests (from pfw-dependencies)

- Use `.incrementing` for `uuid` in tests that need deterministic IDs.
- Use `.constant(date)` for `date` in tests that need a fixed timestamp.
- Pass dependency overrides through `withDependencies { ... }` (synchronous) or the `withDependencies` closure on `Store`/`TestStore`.
- Do NOT call `UUID()` or `Date()` directly in test setup — they are non-deterministic.

---

## Current State

### Test File Inventory

#### `examples/fuse-library/Tests/`

| File | Framework | Has `@Suite` | Has BaseSuite | Notes |
|------|-----------|-------------|---------------|-------|
| `TCATests/StoreReducerTests.swift` | XCTest | No | No | `final class StoreReducerTests: XCTestCase` |
| `TCATests/EffectTests.swift` | XCTest | No | No | `final class EffectTests: XCTestCase` |
| `TCATests/DependencyTests.swift` | XCTest | No | No | `final class DependencyTests: XCTestCase`; also imports `Dependencies`, `DependenciesMacros` (transitive) |
| `TCATests/TestStoreTests.swift` | XCTest + Testing | No | No | Imports `Testing` and `XCTest`, class is XCTestCase |
| `TCATests/TestStoreEdgeCaseTests.swift` | XCTest | No | No | `final class TestStoreEdgeCaseTests: XCTestCase` |
| `TCATests/ObservableStateTests.swift` | XCTest | No | No | `final class ObservableStateTests: XCTestCase` |
| `TCATests/BindingTests.swift` | (not read) | Unknown | No | — |
| `NavigationTests/UIPatternTests.swift` | Swift Testing | No | No | `@MainActor struct UIPatternTests` — uses `@Test` + `#expect` but no `@Suite` |
| `NavigationTests/NavigationTests.swift` | Swift Testing | No | No | `@MainActor struct NavigationTests` — uses `@Test` + `#expect` but no `@Suite` |
| `NavigationTests/NavigationStackTests.swift` | Swift Testing | No | No | `@MainActor struct NavigationStackTests` — uses `@Test` + `#expect` but no `@Suite` |
| `NavigationTests/PresentationTests.swift` | (not read) | Unknown | No | — |
| `DatabaseTests/StructuredQueriesTests.swift` | XCTest | No | No | `final class StructuredQueriesTests: XCTestCase`; inline `DatabaseQueue()` per test |
| `DatabaseTests/SQLiteDataTests.swift` | XCTest | No | No | `final class SQLiteDataTests: XCTestCase`; inline `DatabaseQueue()` per helper |
| `ObservationTests/` | (various) | Unknown | No | — |
| `SharingTests/` | (various) | Unknown | No | — |
| `FoundationTests/` | (various) | Unknown | No | — |

#### `examples/fuse-app/Tests/`

| File | Framework | Has `@Suite` | Has BaseSuite | Notes |
|------|-----------|-------------|---------------|-------|
| `FuseAppIntegrationTests/FuseAppIntegrationTests.swift` | XCTest | No | No | `import GRDB` (H6); 7 `final class` XCTestCase subclasses; inline `DatabaseQueue()` with `try!` |

### Transitive Dependency Violations (M5)

**`examples/fuse-library/Package.swift` — TCATests target:**
```swift
.testTarget(name: "TCATests", dependencies: [
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    .product(name: "Dependencies", package: "swift-dependencies"),        // TRANSITIVE from TCA
    .product(name: "DependenciesMacros", package: "swift-dependencies"),  // TRANSITIVE from TCA
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
])
```
`Dependencies` and `DependenciesMacros` are transitive from `ComposableArchitecture`. Only `DependenciesTestSupport` needs explicit listing (it is a test-only product not in TCA's public dependency graph).

**`examples/fuse-app/Package.swift` — FuseAppIntegrationTests target:**
```swift
.testTarget(name: "FuseAppIntegrationTests", dependencies: [
    "FuseApp",
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), // TRANSITIVE from FuseApp
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
    .product(name: "GRDB", package: "GRDB.swift"),                                      // TRANSITIVE from FuseApp
])
```
`FuseApp` links `ComposableArchitecture` and `GRDB` directly. `FuseAppIntegrationTests` should not re-list them.

### `Action: Equatable` violations (H3)

The following test reducers in fuse-library declare `Action: Equatable`, which violates the PFW rule:

- `TCATests/TestStoreTests.swift:38` — `TSFetchFeature.Action: Equatable`
- `TCATests/TestStoreTests.swift:110` — `TSMultiEffectFeature.Action: Equatable`
- `TCATests/TestStoreTests.swift:158` — `TSRunEffectFeature.Action: Equatable`
- `TCATests/TestStoreTests.swift:181` — `TSMergeEffectFeature.Action: Equatable`
- `TCATests/TestStoreTests.swift:210` — `TSConcatenateEffectFeature.Action: Equatable`
- `TCATests/TestStoreTests.swift:237` — `TSCancellableEffectFeature.Action: Equatable`
- `TCATests/TestStoreTests.swift:264` — `TSCancelEffectFeature.Action: Equatable`
- `TCATests/TestStoreEdgeCaseTests.swift:44` — `EdgeCaseCancelInFlightFeature.Action: Equatable`

(The audit reports additional instances in `EffectTests.swift`, `DependencyTests.swift`, `UIPatternTests.swift`. Those Action enums in the read files do NOT conform to Equatable — but the audit cites 18 total instances including unread files.)

### `XCTAssertEqual` on Structured Types (M4)

Sites using `XCTAssertEqual` on arrays, structs, or IdentifiedArrays (should be `expectNoDifference`):

- `StoreReducerTests.swift:340` — `XCTAssertEqual(store.withState(\.log), ["logged"])` (array)
- `StoreReducerTests.swift:267` — `XCTAssertEqual(store.withState(\.values), [1, 2])` (via EffectConcatenate)
- `EffectTests.swift:267` — `XCTAssertEqual(store.withState(\.values), [1, 2])` (array)
- `FuseAppIntegrationTests.swift:96` — `XCTAssertEqual(store.state.todos.count, 1)` (acceptable — scalar)
- `FuseAppIntegrationTests.swift:455` — `XCTAssertEqual(store.state.selectedTab, .counter)` (enum — borderline)
- `StructuredQueriesTests.swift:139,141` — `XCTAssertEqual(results[0], ItemSummary(...))` (struct)
- `SQLiteDataTests.swift:131-132` — `XCTAssertEqual(items[0].name, "alpha")` (string — acceptable)
- `TestStoreTests.swift:383` — `XCTAssertEqual(store.state.values, ["a", "b"])` (array)
- `TestStoreEdgeCaseTests.swift:153` — `XCTAssertEqual(store.state.result, "result-2")` (string — acceptable)

### Inline `DatabaseQueue` Construction (M8)

`StructuredQueriesTests.swift` — `makeDatabase()` at line 38 constructs `DatabaseQueue()` inline:
```swift
private func makeDatabase() throws -> DatabaseQueue {
    let dbQueue = try DatabaseQueue()
    ...
}
```
Every test method calls `makeDatabase()` independently. There is no `.dependencies` trait establishing a shared bootstrapped database.

`SQLiteDataTests.swift` — same pattern, `makeDatabase()` at line 36, `makeSeededDatabase()` at line 44.

`FuseAppIntegrationTests.swift` — `createMigratedDatabase()` at line 314 uses `try!`:
```swift
private func createMigratedDatabase() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try db.write { db in
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS note (...)")
    }
    return db
}
```
Tests at lines 333 and 348 call it with `try!`:
```swift
let db = try! createMigratedDatabase()
```

### `import GRDB` Violations (H6)

- `SQLiteDataTests.swift:3` — `import GRDB` (should be `import SQLiteData` only)
- `FuseAppIntegrationTests.swift:2` — `import GRDB` (should be removed; `SQLiteData` is the public API)

### `@_spi(Reflection) import CasePaths` (LOW)

- `DependencyTests.swift:1` — `@_spi(Reflection) import CasePaths` — fragile SPI import

### `#expect(Bool(true))` No-op Assertions (LOW)

- `NavigationStackTests.swift:182` — `#expect(Bool(true), "Modern NavigationStack(path:) API compiles successfully")` — this assertion always passes and adds no value.

### `try!` in Test Helpers (LOW)

- `FuseAppIntegrationTests.swift:333` — `let db = try! createMigratedDatabase()`
- `FuseAppIntegrationTests.swift:349` — `let db = try! createMigratedDatabase()`
- `FuseAppIntegrationTests.swift:350` — `try! await db.write { ... }`

### `if case` Instead of `.is(\.case)` (M3)

Pattern used in fuse-library tests where `.is(\.caseName)` should be preferred:

- `ObservableStateTests.swift:365-368` — `if case .featureA = store.withState(\.destination)` → use `store.withState(\.destination).is(\.featureA)`
- `ObservableStateTests.swift:373-376` — `if case .featureB = ...` same
- `StoreReducerTests.swift:316-319` — `if case let .loaded(counter) = state { return counter.count }` in `withState` closure — acceptable in production code but test assertion sites should use case paths
- `NavigationTests.swift:401-404` — `if case let .detail(state) = mutablePath` should use `mutablePath[case: \.detail]`

---

## Required Changes

### File: `examples/fuse-library/Package.swift`

**Change:** Remove `Dependencies` and `DependenciesMacros` from TCATests dependencies (both are transitive from `ComposableArchitecture`).

```swift
// BEFORE
.testTarget(name: "TCATests", dependencies: [
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "DependenciesMacros", package: "swift-dependencies"),
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
]),

// AFTER
.testTarget(name: "TCATests", dependencies: [
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
]),
```

**Verify:** `DependenciesTestSupport` is a test-only product. Confirm it is NOT transitively available from `ComposableArchitecture` before removing — if TCA does not re-export it publicly, keep it explicit.

### File: `examples/fuse-app/Package.swift`

**Change:** Remove `ComposableArchitecture` and `GRDB` from FuseAppIntegrationTests (both are direct dependencies of `FuseApp`).

```swift
// BEFORE
.testTarget(name: "FuseAppIntegrationTests", dependencies: [
    "FuseApp",
    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
    .product(name: "GRDB", package: "GRDB.swift"),
]),

// AFTER
.testTarget(name: "FuseAppIntegrationTests", dependencies: [
    "FuseApp",
    .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
]),
```

### File: `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift`

**Change 1:** Convert `final class StoreReducerTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`.

**Change 2:** Replace `XCTAssertEqual` on structured types with `expectNoDifference`.

Specific replacements:
- Line 340: `XCTAssertEqual(store.withState(\.log), ["logged"])` → `expectNoDifference(store.withState(\.log), ["logged"])`

**Change 3:** Remove `Action: Equatable` from `Combined.Action` (line 133) and any other Action enums in this file.

### File: `examples/fuse-library/Tests/TCATests/EffectTests.swift`

**Change 1:** Convert `final class EffectTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`.

**Change 2:** Replace array comparisons with `expectNoDifference`:
- Line 267: `XCTAssertEqual(store.withState(\.values), [1, 2])` → `expectNoDifference(store.withState(\.values), [1, 2])`

### File: `examples/fuse-library/Tests/TCATests/DependencyTests.swift`

**Change 1:** Remove `@_spi(Reflection) import CasePaths` (line 1) — use the public CasePaths API only.

**Change 2:** Remove `import Dependencies` and `import DependenciesMacros` — both are transitive from `ComposableArchitecture`. Keep only `import ComposableArchitecture`.

**Change 3:** Convert `final class DependencyTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`.

**Change 4:** `static let testValue` on `NumberClient` (line 504) — change to `static var testValue`.

### File: `examples/fuse-library/Tests/TCATests/TestStoreTests.swift`

**Change 1:** Remove `Action: Equatable` from all test reducers:
- `TSFetchFeature.Action` (line 38)
- `TSMultiEffectFeature.Action` (line 110)
- `TSRunEffectFeature.Action` (line 158)
- `TSMergeEffectFeature.Action` (line 181)
- `TSConcatenateEffectFeature.Action` (line 210)
- `TSCancellableEffectFeature.Action` (line 237)
- `TSCancelEffectFeature.Action` (line 264)

**Change 2:** Convert `final class TestStoreTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`. The file already imports `Testing` — complete the migration.

**Change 3:** Replace `XCTAssertEqual` on arrays:
- Line 383: `XCTAssertEqual(store.state.values, ["a", "b"])` → `expectNoDifference(store.state.values, ["a", "b"])`

### File: `examples/fuse-library/Tests/TCATests/TestStoreEdgeCaseTests.swift`

**Change 1:** Remove `Action: Equatable` from `EdgeCaseCancelInFlightFeature.Action` (line 44).

**Change 2:** Convert `final class TestStoreEdgeCaseTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`.

### File: `examples/fuse-library/Tests/TCATests/ObservableStateTests.swift`

**Change 1:** Convert `final class ObservableStateTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`.

**Change 2:** Replace `if case .featureA = ...` and `if case .featureB = ...` (lines 365, 373) with `.is(\.featureA)` / `.is(\.featureB)`.

**Change 3:** Replace `XCTFail(...)` → `Issue.record(...)` throughout.

### File: `examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift`

**Change:** Add `@Suite` wrapper around `@MainActor struct UIPatternTests`, extending `BaseSuite`. The struct already uses `@Test` and `#expect` — only the `@Suite` trait declaration is missing.

```swift
// BEFORE
@MainActor
struct UIPatternTests { ... }

// AFTER — add @Suite and extend BaseSuite
extension BaseSuite {
  @Suite @MainActor struct UIPatternTests { ... }
}
```

Note: `@MainActor` does not inherit from `BaseSuite` — the annotation stays on the nested struct.

### File: `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift`

**Change 1:** Same `@Suite` + `BaseSuite` extension pattern as UIPatternTests.

**Change 2:** Replace `if case let .detail(state) = mutablePath` (line 417) with `mutablePath[case: \.detail]` pattern.

### File: `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift`

**Change 1:** Same `@Suite` + `BaseSuite` extension pattern.

**Change 2:** Remove `#expect(Bool(true), "...")` no-op assertion (line 182).

### File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

**Change 1:** Convert `final class StructuredQueriesTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`.

**Change 2:** Add `.dependencies { try $0.bootstrapDatabase() }` to the suite trait. Remove the per-test `makeDatabase()` helper and instead inject database via `@Dependency(\.defaultDatabase)`.

**Change 3:** Replace `XCTAssertEqual` on struct instances with `expectNoDifference`:
- Lines 139, 141: `XCTAssertEqual(results[0], ItemSummary(...))` → `expectNoDifference(results[0], ItemSummary(...))`

**Change 4:** The `var id` on `Item` (line 10) and `Category` (line 18) are already declared as `let id` — these are CORRECT. No change needed here (audit finding H4 is not applicable to this file's current state as read — both use `let id`).

**Change 5:** Fix infix operators in `.where` closures (H5):
- Line 197: `$0.value > 10` → use named function: `$0.value.gt(10)`
- Line 443: `$0.value > 20` → `$0.value.gt(20)`
- Line 447: `$0.value == 999` → `$0.value.eq(999)`

**Change 6:** Fix `.asc()` calls where `order(by: \.field)` is the preferred form (M1):
- Lines 248, 301, 325, 341, 352, 362, 371 — replace `.order { $0.field.asc() }` with `.order(by: \.field)`
- For descending, `.desc()` stays.
- For collation cases (line 323), `.collate(.nocase).asc()` stays — the collation chain has no shorthand equivalent.

### File: `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift`

**Change 1:** Remove `import GRDB` (line 3). Use only `import SQLiteData`.

**Change 2:** Convert `final class SQLiteDataTests: XCTestCase` to Swift Testing `@Suite` extending `BaseSuite`.

**Change 3:** Add `.dependencies { try $0.bootstrapDatabase() }` to the suite trait. Remove per-test `makeDatabase()` and `makeSeededDatabase()` helpers and use `@Dependency(\.defaultDatabase)`.

**Change 4:** Remove `import Dependencies` and `import DependenciesTestSupport` if they become transitive after other changes. Keep only what is not transitively available.

### File: `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift`

**Change 1:** Remove `import GRDB` (line 2).

**Change 2:** Convert all 7 `final class ...Tests: XCTestCase` classes to Swift Testing `@Suite` structs extending `BaseSuite`.

**Change 3:** Replace `try!` with proper `throws` propagation:
- Line 333: `let db = try! createMigratedDatabase()` → use `.dependencies { try $0.bootstrapDatabase() }` and inject via `@Dependency(\.defaultDatabase)`
- Line 348: same

**Change 4:** Remove the `createMigratedDatabase()` helper entirely. Database setup belongs in the `BaseSuite` `.dependencies` trait.

**Change 5:** Replace `XCTAssertEqual` on structured types with `expectNoDifference`:
- Line 455: `XCTAssertEqual(store.state.selectedTab, .counter)` — borderline (enum, use `expectNoDifference`)
- Line 492: `XCTAssertEqual(store.state.counter.count, 1)` — scalar, acceptable to keep as `#expect`
- Line 509: `XCTAssertEqual(store.state.todos.todos.count, 1)` — scalar, acceptable

**Change 6:** Fix C1 (CRITICAL): Line 372 — change `.toggleCategory("work")` to `.categoryFilterChanged("work")`.

**Change 7:** Replace `XCTAssertEqual(store.state.todos.count, 1)` (line 96 in TodosFeatureTests) with `#expect(store.state.todos.count == 1)` after Swift Testing migration.

---

## Migration Gotchas

### 1. `@MainActor` Does Not Inherit Through BaseSuite

The skill documentation states: "Suites and traits do NOT inherit global actors (e.g. `@MainActor`) applied to the base suite."

If `BaseSuite` is annotated `@MainActor`, child suites do NOT automatically run on the main actor. Each `@Test` or nested `@Suite` that needs main-actor isolation must annotate itself:

```swift
// WRONG — @MainActor on BaseSuite does not propagate
@MainActor
@Suite(.serialized)
struct BaseSuite {}

extension BaseSuite {
  struct FeatureTests {
    @Test func testSomething() { ... } // NOT on main actor despite BaseSuite being @MainActor
  }
}

// CORRECT — annotate each test or suite that needs it
extension BaseSuite {
  @Suite struct FeatureTests {
    @Test @MainActor func testSomething() { ... }
  }
}
```

The existing Swift Testing files (`UIPatternTests`, `NavigationTests`, `NavigationStackTests`) all annotate the struct `@MainActor` directly. After wrapping in `BaseSuite` extension, move `@MainActor` to each `@Test` function or keep it on the nested struct — both are valid.

### 2. Swift Testing `@Test` vs XCTest `@MainActor func test...`

XCTest methods with `@MainActor func testFoo() async` work. Swift Testing `@Test @MainActor func testFoo() async` also works. They are NOT interchangeable:

- Swift Testing does not call XCTestCase-style `setUp`/`tearDown`. Init-based setup is used instead.
- XCTest's `XCTExpectFailure { }` maps to Swift Testing's `withKnownIssue { }`.
- XCTest's `XCTFail(...)` maps to Swift Testing's `Issue.record(...)`.
- XCTest's `XCTAssertNil` / `XCTAssertNotNil` map to `#expect(x == nil)` / `#expect(x != nil)`.
- XCTest's `XCTestExpectation` / `fulfill` / `wait(for:timeout:)` maps to Swift Testing's structured concurrency — use `async/await` directly.

`FuseAppIntegrationTests.swift` and all XCTest files that use `XCTestExpectation` must replace that pattern with `async` functions and `await`:

```swift
// WRONG after migration
let expectation = XCTestExpectation(description: "fires")
observation.start(..., onChange: { _ in expectation.fulfill() })
await fulfillment(of: [expectation], timeout: 5.0)

// CORRECT — use async stream or continuation
let values = AsyncStream { ... }
for await value in values { break }
```

### 3. `TestStore` Requires `@MainActor` in Swift Testing

`TestStore` is `@MainActor`-bound in TCA. In Swift Testing, `@Test` is NOT `@MainActor` by default. Failure to annotate will produce a compile error or runtime isolation violation:

```swift
// CORRECT
@Test @MainActor func testIncrement() async {
    let store = TestStore(...) { ... }
    await store.send(.increment) { $0.count = 1 }
}
```

All `TestStore` tests must have `@MainActor` on the `@Test` function.

### 4. `try!` in Test Setup Is Fatal on Failure

`FuseAppIntegrationTests.swift` uses `try!` in test setup (lines 333, 349). In Swift Testing, a fatal error in test setup terminates the entire process rather than failing a single test. Replace `try!` with proper `throws` propagation or structure setup in the `BaseSuite` `.dependencies` trait where errors are handled.

### 5. `Action: Equatable` Breaks `.receive(\.caseName)` Pattern

TestStore's `receive(_ actionKeyPath:)` method requires the action to conform to `CasePathable`, NOT `Equatable`. The `Action: Equatable` conformance is redundant and conflicts with PFW rules. Removing it will not break `receive` call sites — it may cause compile errors only if any test uses `==` to compare actions directly (which is an anti-pattern anyway).

### 6. Transitive Dependency Removal May Break the Build Temporarily

When removing `import Dependencies` and `import DependenciesMacros` from `DependencyTests.swift`, verify the import is not needed for any symbol that is NOT re-exported by `ComposableArchitecture`. Specifically:
- `@DependencyClient` — provided by `DependenciesMacros`. If TCA re-exports it, no explicit import needed.
- `withDependencies { }` — provided by `Dependencies`. TCA re-exports this.
- `DependenciesTestSupport` — test-only module. TCA does NOT re-export it. Keep explicit.

Do a test build after each Package.swift change to confirm the removal compiles.

### 7. `DatabaseQueue` in Tests Is GRDB-Specific

`StructuredQueriesTests.swift` and `SQLiteDataTests.swift` construct `DatabaseQueue()` directly — this requires `import GRDB`. After migrating to `.dependencies { try $0.bootstrapDatabase() }`, the tests access the database through `@Dependency(\.defaultDatabase)` which is typed as `SQLiteData.Database` (the `SQLiteData` abstraction). The `import GRDB` can then be removed.

If any test still needs `DatabaseMigrator` directly (as in `SQLiteDataTests.testDatabaseMigrator`), `DatabaseMigrator` is part of `SQLiteData`'s public surface — check if it is re-exported. If not, that single test may still need `import GRDB` or must be refactored to use `bootstrapDatabase`.

### 8. `@CasePathable` on Test Action Enums That Use `receive(\.caseName)`

`TestStore.receive` uses key-path syntax (`\.response`, `\.done`, etc.). This works only when the Action enum is `@CasePathable`. In the test files:
- `TSFetchFeature.Action` — has `@CasePathable` (line 37)
- `TSFinishFeature.Action` — has `@CasePathable` (line 83)
- Others that use `receive(\.caseName)` must have `@CasePathable` (added separately from `Equatable`)

Removing `Action: Equatable` should NOT also remove `@CasePathable`. They are independent.

### 9. No-op `#expect(Bool(true))` Is Harmless But Misleading

`NavigationStackTests.swift:182` — `#expect(Bool(true), "...")`. Removing it changes test intent but not behavior. Document the compile-time guarantee it was trying to express as a code comment instead.

### 10. `withKnownIssue` vs `XCTExpectFailure`

`TestStoreTests.swift:337` already uses `withKnownIssue { ... }` (Swift Testing API) inside a `final class ... XCTestCase` method. This works because `withKnownIssue` is available in both Swift Testing and XCTest contexts via `IssueReporting`. After full migration to Swift Testing, this call site stays unchanged.

---

## Ordering Dependencies

### Phase 8 must-do sequence for testing changes:

**Step 1 — Fix C1 (critical correctness, blocks all other test work):**
Fix `FuseAppIntegrationTests.swift:372` — `.toggleCategory("work")` → `.categoryFilterChanged("work")`.
This is a wrong action name that causes the test to silently no-op. Fix before any migration.

**Step 2 — Fix Package.swift transitive deps (M5, must precede import cleanup):**
1. `fuse-library/Package.swift` — remove `Dependencies`, `DependenciesMacros` from TCATests.
2. `fuse-app/Package.swift` — remove `ComposableArchitecture`, `GRDB` from FuseAppIntegrationTests.
Build after each change to verify compilation.

**Step 3 — Remove import violations (H6, M5, LOW SPI):**
After Package.swift is clean:
- Remove `import GRDB` from `SQLiteDataTests.swift` and `FuseAppIntegrationTests.swift`.
- Remove `import Dependencies`, `import DependenciesMacros` from `DependencyTests.swift`.
- Remove `@_spi(Reflection) import CasePaths` from `DependencyTests.swift`.

**Step 4 — Remove `Action: Equatable` (H3, independent, low risk):**
Remove `: Equatable` from all test Action enums listed above. Build to verify no `==` comparisons on actions remain.

**Step 5 — Add `BaseSuite` infrastructure per test bundle:**
Create a `BaseSuite.swift` file in each test bundle that defines the base suite. Each bundle has different dependency needs:
- `TCATests` — no database, add `.serialized`
- `DatabaseTests` — add `.dependencies { try $0.bootstrapDatabase() }`
- `NavigationTests` — add `.serialized`
- `FuseAppIntegrationTests` — add `.dependencies { try $0.bootstrapDatabase() }`

**Step 6 — Migrate XCTest classes to Swift Testing extensions of BaseSuite (H10):**
Migrate in this order (lowest risk first):
1. `StoreReducerTests.swift` — pure store tests, no async effects
2. `ObservableStateTests.swift` — pure store + observation
3. `TestStoreEdgeCaseTests.swift` — TestStore edge cases
4. `TestStoreTests.swift` — already partially migrated (imports Testing), complete it
5. `EffectTests.swift` — async effects with `Task.sleep`
6. `DependencyTests.swift` — dependency resolution
7. `StructuredQueriesTests.swift` — database (after bootstrapDatabase trait is in place)
8. `SQLiteDataTests.swift` — database + observation
9. `FuseAppIntegrationTests.swift` — most complex, last

**Step 7 — Replace `XCTAssertEqual` on structured types with `expectNoDifference` (M4):**
Do this as part of each file's migration in Step 6. Do not do it ahead of migration — changing assertion style while preserving XCTestCase is lower priority.

**Step 8 — Add `.dependencies` trait to database suites (M8):**
Only possible after Step 5 establishes BaseSuite and Step 6 migrates the database test files.

**Step 9 — Fix `.asc()` and infix operator violations (M1, H5):**
These are StructuredQueries-specific and independent of the testing migration. They can be done any time after Step 3 (imports are clean). Do them as part of `StructuredQueriesTests.swift` migration in Step 6.

**Step 10 — Remove no-op assertions and fix `if case` patterns (LOW, M3):**
Do these during the Swift Testing migration pass in Step 6 for each file.

### What BLOCKS what:

- **Step 1** (C1 fix) blocks nothing but must happen first — a wrong action name makes subsequent test results unreliable.
- **Step 2** (Package.swift) must come before **Step 3** (import removal) — removing imports without updating Package.swift may cause spurious "module not found" errors.
- **Step 5** (BaseSuite) must come before **Step 6** (file migration) — extensions of `BaseSuite` require `BaseSuite` to exist.
- **Step 8** (`.dependencies` database trait) must come after **Step 6** for database files — the `DatabaseQueue()` helpers cannot be removed until the suite-level bootstrap is in place.
- **Steps 7, 9, 10** are independent of each other and can be interleaved with Step 6.
