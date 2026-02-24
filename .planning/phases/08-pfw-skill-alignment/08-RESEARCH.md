# Phase 8: PFW Skill Alignment - Reconciled Research

**Researched:** 2026-02-23
**Mode:** Ecosystem (implementation approach)
**Reconciled from:** 12 domain researchers + 3 concern scouts (15 parallel outputs)

---

## Standard Stack

All tools are already in the project. No new dependencies needed. The "stack" is the set of PFW canonical APIs that the audit found deviations from:

| Domain | Canonical Library | Already Wired | Confidence | Notes |
|--------|------------------|---------------|------------|-------|
| Testing framework | Swift Testing (`@Suite`/`@Test`) | Partial (13 files migrated, 14 remain XCTest) | HIGH | 184 test methods across 14 files must migrate |
| Test assertions | `CustomDump` (`expectNoDifference`, `expectDifference`) | Yes | HIGH | Replace `XCTAssertEqual` for struct/array; use `#expect` for scalars |
| Test dependencies | `DependenciesTestSupport` (`.dependencies` trait) | Yes | HIGH | Use `.dependencies {}` suite trait for database and shared state |
| TCA patterns | `ComposableArchitecture` | Yes | HIGH | Action naming, `@CasePathable`, Path un-nesting, dismiss pattern |
| Database queries | `StructuredQueries` (named functions) | Yes | HIGH | `.eq()`/`.gt()` not infix `==`/`>` |
| Database setup | `SQLiteData` (`defaultDatabase()`) | Yes | HIGH | Replace `DatabaseQueue(path:)` |
| Database observation | `SQLiteData` (`@FetchAll`/`@FetchOne`) | Yes | HIGH | Replace polling in DatabaseView |
| Case paths | `CasePaths` (`.is()`/`[case:]`) | Yes | HIGH | Replace `if case` pattern matching |
| Shared state | `Sharing` (`IdentifiedArrayOf`, `Observations`) | Yes | HIGH | Replace `[Todo]` with `IdentifiedArrayOf<Todo>` |
| Issue reporting | `IssueReporting` (`withErrorReporting`, `reportIssue`) | Yes | HIGH | Wrap Effect.run errors |
| Navigation | `SwiftNavigation` (`@Dependency(\.dismiss)`) | Yes | HIGH | Replace manual `state.path.popLast()` and `destination = nil` |
| Perception | `Perception` (`@Perceptible`/`@available`) | Yes | MEDIUM | Add availability annotations; project targets iOS 17+ |
| Identified collections | `IdentifiedCollections` (`IdentifiedArrayOf<T>`) | Yes | HIGH | O(1) ID-based access, type-safe |

---

## Architecture Patterns

### 1. Swift Testing `@Suite` Structure (pfw-testing canonical)

**Pattern:** Use `@Suite(.serialized)` on each test struct. For database suites, include `.dependencies` trait.

```swift
import ComposableArchitecture
import DependenciesTestSupport
import Testing

@Suite(.serialized)
@MainActor
struct CounterFeatureTests {
  @Test func increment() async {
    let store = TestStore(initialState: CounterFeature.State()) {
      CounterFeature()
    }
    await store.send(.view(.incrementButtonTapped)) {
      $0.count = 1
    }
  }
}

// Database suite:
@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct DatabaseTests {
  @Dependency(\.defaultDatabase) var database

  @Test func insertAndFetch() throws {
    // ...
  }
}
```

**Key rules:**
- `@MainActor` does NOT inherit through extensions or from base types -- annotate each `@Test` or nested `@Suite` directly.
- `.serialized` ensures TCA tests (which share MainActor) and database tests do not race.
- `.dependencies {}` trait replaces `withDependencies` setup in individual tests.
- `XCTExpectFailure` becomes `withKnownIssue { ... }`.
- `XCTestExpectation` + `wait(for:)` becomes `confirmation(expectedCount:)` or async patterns.
- Inverted expectations (must NOT fire) become `Task.sleep` + counter assertion.
- `setUp()` becomes `init()` on the struct; `addTeardownBlock` becomes `defer`.
- `XCTFail(...)` becomes `Issue.record(...)` (note: does NOT stop test execution; add `return` if needed).
- Infrastructure files (`XCSkipTests.swift`) using `XCGradleHarness` MUST remain XCTest.

### 2. TCA Action Naming Conventions (pfw-composable-architecture canonical)

**Pattern:** Action cases named literally after what the user does or data the effect returns.

```swift
enum Action {
  // User-initiated -- named after gesture/event
  case decrementButtonTapped  // not "decrement"
  case viewAppeared           // not "onAppear"
  case addButtonTapped        // not "addNoteTapped"

  // Effect responses -- named after data returned
  case factResponse(Result<String, any Error>)
  case timerTick
}
```

**Rules:**
- DO NOT conform `Action` to `Equatable`.
- DO NOT append `Reducer` suffix to type names.
- DO name view lifecycle actions `viewAppeared` (not `onAppear`).
- DO use `addButtonTapped` (not `addNoteTapped`) -- always `<noun>ButtonTapped`.

### 3. Path Feature Un-nesting (pfw-composable-architecture canonical)

**Pattern:** `@Reducer enum Path` must NOT be nested inside parent. Prefix with parent name.

```swift
// CORRECT
@Reducer enum ContactsFeaturePath {
  case detail(ContactDetailFeature)
}

@Reducer struct ContactsFeature {
  @ObservableState struct State {
    var path = StackState<ContactsFeaturePath.State>()
  }
  enum Action {
    case path(StackActionOf<ContactsFeaturePath>)
  }
  var body: some ReducerOf<Self> {
    Reduce { ... }
      .forEach(\.path, action: \.path) { ContactsFeaturePath.body }
  }
}

// WRONG -- nested inside parent
@Reducer struct ContactsFeature {
  @Reducer enum Path { ... }  // NO
}
```

### 4. `@CasePathable` on Action Enums (pfw-case-paths + pfw-composable-architecture)

**CONFLICT IDENTIFIED:** The pfw-case-paths researcher states `@Reducer struct` does NOT synthesise `@CasePathable` on Action and it must be added explicitly. The pfw-composable-architecture researcher states `@Reducer` on a struct DOES synthesise `@CasePathable` on Action automatically. The resolution: **`@Reducer` does synthesise case path infrastructure for scope routing, but adding explicit `@CasePathable` is safe, additive, and ensures key-path syntax (`\.caseName`) works for `store.receive(\.action)` and similar patterns.** Add `@CasePathable` explicitly for documentation clarity; there is no duplicate-conformance conflict for `@Reducer struct` types.

For `@Reducer enum` types (Destination, Path), `@CasePathable` IS auto-synthesised on both State and Action. DO NOT add it manually -- it will cause a duplicate conformance error.

Nested sub-enums (`Delegate`, `Alert`, `ConfirmationDialog`, `View`) always need explicit `@CasePathable`.

```swift
@Reducer struct MyFeature {
  @CasePathable  // explicit; safe with @Reducer
  enum Action {
    case buttonTapped
    case response(String)

    @CasePathable  // required on nested non-@Reducer enum
    enum Delegate { case deleteContact(Contact.ID) }
  }
}
```

### 5. Dismiss Pattern (pfw-composable-architecture + pfw-swift-navigation canonical)

**Pattern:** Use `@Dependency(\.dismiss)` in child feature, not `state.path.popLast()` in parent. For stack navigation, use `state.path.remove(id:)` when the parent must programmatically remove an element.

```swift
// CHILD feature self-dismisses
@Reducer struct ContactDetailFeature {
  @Dependency(\.dismiss) var dismiss
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .delegate(.deleteContact):
        return .run { _ in await dismiss() }
      }
    }
  }
}

// PARENT -- uses remove(id:) when it must pop explicitly
case .path(.element(let stackID, .detail(.delegate(.deleteContact(let contactID))))):
  state.contacts.remove(id: contactID)
  state.path.remove(id: stackID)  // NOT popLast()
  return .none
```

### 6. Presentation State Pattern (pfw-swift-navigation canonical)

**Pattern:** Use optional `@Presents` state for sheets/alerts, not boolean flags.

```swift
// CORRECT
@Presents var sheet: SheetContent.State?

// WRONG
var showSheet = false
```

For multiple presentations, consolidate into a single `@Reducer enum Destination` when they are mutually exclusive. Use `@ReducerCaseEphemeral` for `AlertState` and `ConfirmationDialogState` cases. Exception: if presentations can be shown simultaneously (e.g. `TodosFeature` alert + confirmation dialog), separate `@Presents` is acceptable.

**Dismissal:** Use `@Dependency(\.dismiss)` in child or `.send(.destination(.dismiss))` in parent. NEVER set `destination = nil` directly -- it bypasses PresentationReducer effect cancellation.

### 7. `CombineReducers` Usage (pfw-composable-architecture canonical)

**Pattern:** Only use `CombineReducers` when a modifier (`.ifLet`, `.forEach`) needs to be applied to the combined group.

```swift
// CORRECT -- modifier applied
var body: some ReducerOf<Self> {
  CombineReducers {
    ChildA()
    ChildB()
  }
  .ifLet(\.$child, action: \.child) { ... }
}

// WRONG -- no modifier needed; inline into single Reduce
var body: some ReducerOf<Self> {
  CombineReducers {  // unnecessary wrapper
    Reduce { ... }
    Reduce { ... }
  }
}
```

### 8. DependencyKey Computed Properties (pfw-dependencies canonical)

**Pattern:** Use `static var` computed properties, never `static let`.

```swift
// CORRECT
extension NumberFactClient: DependencyKey {
  static var liveValue: Self {
    Self(fetch: { number in "Fact for \(number)" })
  }
  static var testValue: Self { Self() }
  static var previewValue: Self {
    Self(fetch: { number in "Preview fact for \(number)" })
  }
}

// WRONG
static let liveValue = Self(...)
static let testValue = Self()
```

**Rationale:** Computed properties evaluate fresh each time, essential for dependency injection across live/test/preview contexts. `static let` captures at initialization time.

### 9. Uncontrolled UUID/Date in Model Defaults (pfw-dependencies + pfw-composable-architecture)

**Pattern:** Model types MUST NOT have `UUID()` or `Date()` / `.now` as default parameter values. The caller (always a reducer with `@Dependency`) supplies the values.

```swift
// WRONG
struct Todo {
  var id: UUID = UUID()
  var createdAt: Date = .now
}

// CORRECT
struct Todo {
  var id: UUID
  var createdAt: Date
}
// In reducer:
let newTodo = Todo(id: uuid(), createdAt: date.now)
```

### 10. Database Bootstrap Pattern (pfw-sqlite-data canonical)

**Pattern:** Use `SQLiteData.defaultDatabase()` (not `DatabaseQueue(path:)`), invoke in `@main` App struct `init()`.

```swift
extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("v1") { db in
      try #sql("""
        CREATE TABLE "note" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          "title" TEXT NOT NULL DEFAULT '',
          "body" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """)
        .execute(db)
    }
    try migrator.migrate(database)
    defaultDatabase = database
  }
}

// In @main entry point -- use try! ONLY here (unrecoverable at launch)
@main struct MyApp: App {
  init() {
    prepareDependencies {
      try! $0.bootstrapDatabase()
    }
  }
}
```

**Rules:**
- DO NOT call `DatabaseQueue(path:)` or construct paths manually.
- DO NOT invoke `bootstrapDatabase` in a View's `init()` -- only in `@main` App struct.
- DO assign `defaultDatabase = database` at the end.
- Use `try!` ONLY at the `@main` entry point. Everywhere else use `withErrorReporting`.

### 11. `@FetchAll` / `@FetchOne` for SwiftUI Views (pfw-sqlite-data canonical)

```swift
struct NotesView: View {
  @FetchAll(Note.order { $0.createdAt.desc() }) var notes
  @FetchOne(Note.count()) var noteCount = 0

  var body: some View {
    List(notes) { note in Text(note.title) }
  }
}
```

**Rules:**
- `@FetchAll` / `@FetchOne` are for SwiftUI views only.
- In `@Observable` models, add `@ObservationIgnored` before `@FetchAll`/`@FetchOne`.
- For dynamic queries, initialise with `.none` and load in `.task { await $notes.load(...) }`.
- Replaces the polling-via-reducer pattern (manual `database.read` on `viewAppeared`).

### 12. Query Syntax (pfw-structured-queries canonical)

**Named functions, not infix operators:**

```swift
// CORRECT
Item.where { $0.value.gt(10) && $0.isActive }
Item.where { $0.title.eq("test") }
Item.where { $0.name.is(nil) }  // for optionals

// WRONG
Item.where { $0.value > 10 && $0.isActive }
Item.where { $0.title == "test" }
```

**Order by -- do NOT specify `asc()` unless customizing NULL sorting:**

```swift
// CORRECT
Item.order(by: \.title)          // ascending by default
Item.order { $0.title.desc() }   // descending explicit

// WRONG
Item.order { $0.title.asc() }   // unnecessary asc()
```

**Key-path vs closure scope rule:** Use key-path syntax (`order(by: \.field)`) before a join. After a join, use closure form (`order { items, categories in items.field }`).

**Prefer draft insert form for primary-keyed tables:**

```swift
// CORRECT
Item.insert {
  Item.Draft(name: "test", value: 42, isActive: true)
}

// ACCEPTABLE for non-primary-keyed tables only
Item.insert {
  ($0.name, $0.value, $0.isActive)
} values: {
  ("test", 42, true)
}
```

**Use `#sql` macro for migrations, not raw `db.execute(sql:)`:**

```swift
// CORRECT
migrator.registerMigration("v1") { db in
  try #sql("""
    CREATE TABLE "note" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
      "title" TEXT NOT NULL DEFAULT ''
    ) STRICT
    """)
    .execute(db)
}

// WRONG
migrator.registerMigration("v1") { db in
  try db.execute(sql: """
    CREATE TABLE note (...)
    """)
}
```

**DDL conventions:** Always use `STRICT` tables, quote all identifiers, use `NOT NULL` on non-nullable columns, remove `IF NOT EXISTS` from migrations (migrator tracks execution).

### 13. CasePaths Idioms (pfw-case-paths canonical)

**Pattern:** Use `.is()` for case checking, `[case:]` subscript for extraction, `.modify()` for in-place mutation. Replace `if case let`.

```swift
// CORRECT
#expect(state.destination.is(\.detail))
let detail = state.destination[case: \.detail]
state.modify(\.detail) { $0.title = "Updated" }

// WRONG
if case let .detail(value) = state.destination { ... }
```

**DO NOT use `private` with `@CasePathable` -- use `fileprivate`:**

```swift
// CORRECT
@CasePathable fileprivate enum CancelID { case timer }

// WRONG
@CasePathable private enum CancelID { case timer }
```

**DO NOT use `@_spi(Reflection) import CasePaths` in test files.** The public API is sufficient. The SPI import in TCA fork library files is acceptable (matches upstream).

### 14. Effect Error Handling (pfw-issue-reporting canonical)

**Pattern:** Use `do/catch` + `reportIssue(error)` or `withErrorReporting` in `Effect.run` closures. NEVER leave `try` unhandled.

```swift
// CORRECT -- do/catch
return .run { send in
  do {
    let notes = try await database.read { db in
      try Note.all.fetchAll(db)
    }
    await send(.notesLoaded(notes))
  } catch {
    reportIssue(error)
  }
}

// CORRECT -- withErrorReporting (when no specific recovery needed)
return .run { send in
  await withErrorReporting {
    let notes = try await database.read { db in
      try Note.all.fetchAll(db)
    }
    await send(.notesLoaded(notes))
  }
}

// WRONG -- unhandled errors in Effect.run
return .run { send in
  let notes = try await database.read { ... }  // throws silently
  await send(.notesLoaded(notes))
}
```

**Guard + reportIssue** for programmer errors (missing expected state):

```swift
guard let id = draft.id else {
  reportIssue("Draft ID should be non-nil.")
  return .none
}
```

### 15. Observation Patterns (pfw-sharing + pfw-perception canonical)

**`Observations {}` async sequence preferred over Combine:**

```swift
// CORRECT -- Observation framework
@Shared var currentUser: User?
let isLoggedInStream = Observations { currentUser != nil }

// DEPRECATED but acceptable
$currentUser.publisher.map { $0 != nil }
```

**`@Observable` requires availability annotations:**

```swift
// CORRECT
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@Observable class MyModel { ... }

// OR use Perception backport for cross-platform (especially Android)
@Perceptible class MyModel { ... }
```

**`ObservationRegistrar` shadow on Android (M17):** Rename `SkipAndroidBridge.Observation` namespace to `BridgeObservation` to avoid shadowing the `Observation` module.

### 16. `expectNoDifference` vs `#expect` Boundary (pfw-custom-dump canonical)

**Decision tree:**

| Assertion Type | Use Case | Tool |
|----------------|----------|------|
| Static struct/array equality | Verify final state | `expectNoDifference(lhs, rhs)` |
| Mutation assertions | Verify specific fields changed | `expectDifference(value) { action } changes: { mutations }` |
| Simple boolean/scalar | Quick checks | `#expect(condition)` |

```swift
// Use expectNoDifference for complex types
expectNoDifference(store.state.todos, expectedTodos)
expectNoDifference(store.state.contacts.count, 3)

// Use #expect for simple boolean/scalar
#expect(store.state.isLoading == false)
#expect(store.state.count == 5)
```

**Use `expectDifference` for mutation assertions:**

```swift
expectDifference(model.counters) {
  model.incrementButtonTapped(counter: model.counters[0])
} changes: {
  $0[0].count = 1
}
```

### 17. IdentifiedArrayOf for Identifiable Collections (pfw-identified-collections canonical)

All collections of `Identifiable` models in TCA `State` and `@Shared(.fileStorage)` keys MUST use `IdentifiedArrayOf<T>`.

```swift
// CORRECT
@Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []
var notes: IdentifiedArrayOf<Note> = []

// WRONG
@Shared(.savedTodos) var savedTodos: [Todo] = []
var notes: [Note] = []
```

**Benefits:** O(1) lookups (`todos[id: uuid]`), O(1) removal (`todos.remove(id: uuid)`), guaranteed uniqueness, Codable-compatible (same JSON wire format as plain array).

### 18. Import Hygiene (pfw-sqlite-data canonical)

```swift
// CORRECT
import SQLiteData  // re-exports GRDB, StructuredQueries, StructuredQueriesSQLite

// WRONG
import GRDB                    // implementation detail
import StructuredQueries       // re-exported by SQLiteData
import StructuredQueriesSQLite // re-exported by SQLiteData
```

---

## Don't Hand-Roll

| Problem | Use This | Not This |
|---------|----------|----------|
| Test suite structure | `@Suite`/`@Test` with `.dependencies` trait | XCTestCase subclasses |
| Database connection | `SQLiteData.defaultDatabase()` | `DatabaseQueue(path:)` |
| Database observation | `@FetchAll`/`@FetchOne` property wrappers | Manual polling with `viewAppeared` + `Effect.run` |
| SQL migrations | `#sql` macro + `.execute(db)` | Raw `db.execute(sql:)` |
| Equality assertions | `expectNoDifference` (structs/arrays), `#expect` (scalars) | `XCTAssertEqual` |
| Mutation assertions | `expectDifference { } changes: { }` | Manual before/after comparison |
| Feature dismissal | `@Dependency(\.dismiss)` or `state.path.remove(id:)` | `state.path.popLast()` or `state.destination = nil` |
| Error handling in effects | `do/catch` + `reportIssue(error)` or `withErrorReporting {}` | Bare `try` in Effect.run |
| Query predicates | Named `.eq()`/`.gt()` functions | Infix `==`/`>` operators |
| Ascending sort | `order(by: \.field)` (default ascending) | `.asc()` |
| Case checking | `.is(\.caseName)` / `[case:]` subscript | `if case let` |
| Database import | `import SQLiteData` | `import GRDB` or `import StructuredQueries` |
| Sheet state | `@Presents var sheet: Content.State?` | Boolean `showSheet` flag |
| Identifiable collections | `IdentifiedArrayOf<T>` | `[T]` for any `Identifiable` model |
| Known test failures | `withKnownIssue { ... }` | `XCTExpectFailure { ... }` |
| Async expectations | `confirmation(expectedCount:)` or structured concurrency | `XCTestExpectation` + `wait(for:)` |
| Test failure recording | `Issue.record("message")` | `XCTFail("message")` |
| DependencyKey values | `static var liveValue` (computed) | `static let liveValue` |
| UUID/Date in models | Inject via `@Dependency(\.uuid)` / `@Dependency(\.date)` | Default `UUID()` / `.now` parameters |

---

## Common Pitfalls

### P1: `@MainActor` does NOT inherit in Swift Testing
Marking a parent suite or base type `@MainActor` does NOT propagate to nested `@Suite` types or `@Test` functions. Each test that needs MainActor (all TCA `TestStore` tests) must declare it explicitly on the struct or individual test.

### P2: `@CasePathable` + `@Reducer` interaction
`@Reducer` on a struct synthesises case path infrastructure for State routing (scope), and provides enough for `store.send(\.action)` syntax. Adding explicit `@CasePathable` on Action is safe and recommended for documentation. For `@Reducer enum` types (Destination/Path), `@CasePathable` IS auto-synthesised on both State and Action -- DO NOT add manually.

### P3: `private` vs `fileprivate` for `@CasePathable`
`@CasePathable` generates a nested `AllCasePaths` struct. `private` prevents access. Always use `fileprivate`.

### P4: `static let` vs `static var` for DependencyKey
`static let` captures at initialization time. `static var` evaluates fresh -- essential for dependency injection.

### P5: Transitive dependencies in test targets
Test targets get all transitive dependencies from the target they test. Remove redundant explicit listings:
- Remove `ComposableArchitecture` and `GRDB` from `FuseAppIntegrationTests` (come through `FuseApp`).
- Remove `Dependencies` and `DependenciesMacros` from `TCATests` (come through `ComposableArchitecture`).
- Keep `DependenciesTestSupport` (test-only product, not transitively available).

### P6: `asc()` is redundant
StructuredQueries defaults to ascending order. `.asc()` is only needed with NULL customization (e.g., `.asc(nulls: .last)`). All 7 occurrences of bare `.asc()` must become `order(by: \.field)`.

### P7: Migration SQL should use `#sql` macro
The `#sql` macro provides compile-time SQL checking. Raw `db.execute(sql:)` has no such guarantees. Remove `IF NOT EXISTS` from migrations -- the migrator tracks execution. Add `STRICT` for type enforcement.

### P8: `withKnownIssue` replaces `XCTExpectFailure`
Swift Testing's equivalent of `XCTExpectFailure` is `withKnownIssue`. Supports async closures.

### P9: `Observations {}` vs Combine for shared state observation
The pfw-sharing skill explicitly states: "DO prefer Observation over Combine." `SharedObservationTests.swift` uses Combine exclusively and must migrate to `Observations {}` async sequence.

### P10: `import GRDB` and `import StructuredQueries*` leak implementation details
`SQLiteData` re-exports GRDB types and StructuredQueries types via `@_exported import`. App and test code should `import SQLiteData` only. Also remove `import StructuredQueries` and `import StructuredQueriesSQLite` from app source (same violation as `import GRDB`).

### P11: `DatabaseQueue(path:)` vs `SQLiteData.defaultDatabase()`
`defaultDatabase()` sets up WAL mode, multi-reader configuration, and production-quality settings. Raw `DatabaseQueue(path:)` misses these.

### P12: Uncontrolled `UUID()` and `Date()` in model defaults
`Todo` and `Contact` initializers have `id: UUID = UUID()` and `createdAt: Date = .now`. Remove defaults; require explicit injection via `@Dependency(\.uuid)` and `@Dependency(\.date)`.

### P13: Two separate `@Presents` instead of Destination enum
`TodosFeature` has separate `@Presents var alert` and `@Presents var confirmationDialog`. The PFW pattern uses a single `@Reducer enum Destination`. This is a LOW finding -- the current pattern works because both presentations can appear simultaneously.

### P14: `@_spi(Reflection) import CasePaths` is fragile in test files
Remove from `DependencyTests.swift` (unused). Leave in TCA fork library files (legitimate upstream pattern).

### P15: `@available` annotations for `@Observable`
All `@Observable` classes must have `@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)`. Alternatively use `@Perceptible` for cross-platform portability.

### P16: `ObservationRegistrar` namespace shadowing (M17)
`SkipAndroidBridge.Observation.ObservationRegistrar` shadows the `Observation` module. Rename wrapper namespace to `BridgeObservation` to resolve.

### P17: `DatabaseFeature.State.notes` uses `[Note]` not `IdentifiedArrayOf<Note>`
The audit's H12 flagged `[Todo]` but missed `[Note]` in `DatabaseFeature.State`. `Note` is `Identifiable` and should use `IdentifiedArrayOf<Note>` for consistency.

### P18: `bootstrapDatabase` invoked in View init, not `@main`
`FuseApp.swift` calls `prepareDependencies` inside `FuseAppRootView.init()` (a View). This must move to the `@main` App struct's `init()` or equivalent cross-platform entry point.

### P19: `XCTestExpectation` with `isInverted = true` has no Swift Testing equivalent
Replace with `AtomicCounter` + `Task.sleep` + `#expect(counter.value == 0)`. Pattern already proven in `ObservationBridgeTests.swift`.

### P20: `try!` in test setup is fatal in Swift Testing
`FuseAppIntegrationTests.swift` uses `try!` in test setup. In Swift Testing, a fatal error terminates the entire process. Replace with proper `throws` propagation or `.dependencies` trait.

---

## Code Examples

### Example 1: Full Swift Testing Migration (XCTest -> Swift Testing)

**Before (XCTest):**
```swift
import XCTest
import ComposableArchitecture

final class CounterFeatureTests: XCTestCase {
  @MainActor func testIncrement() async {
    let store = TestStore(initialState: CounterFeature.State()) {
      CounterFeature()
    }
    await store.send(.view(.incrementButtonTapped)) {
      $0.count = 1
    }
  }
}
```

**After (Swift Testing):**
```swift
import ComposableArchitecture
import Testing

@Suite(.serialized)
@MainActor
struct CounterFeatureTests {
  @Test func increment() async {
    let store = TestStore(initialState: CounterFeature.State()) {
      CounterFeature()
    }
    await store.send(.view(.incrementButtonTapped)) {
      $0.count = 1
    }
  }
}
```

### Example 2: `expectNoDifference` replacing `XCTAssertEqual`

**Before:**
```swift
XCTAssertEqual(store.state.todos.count, 1)
XCTAssertEqual(store.withState(\.log), ["logged"])
```

**After:**
```swift
#expect(store.state.todos.count == 1)  // scalar -> #expect
expectNoDifference(store.withState(\.log), ["logged"])  // array -> expectNoDifference
```

### Example 3: Named query functions replacing infix operators

**Before:**
```swift
Item.where { $0.value > 10 && $0.isActive }
Item.where { $0.name == "nonexistent" }
```

**After:**
```swift
Item.where { $0.value.gt(10) && $0.isActive }
Item.where { $0.name.eq("nonexistent") }
```

### Example 4: `order(by:)` replacing `.asc()`

**Before:**
```swift
Item.order { $0.name.asc() }
Item.order { $0.id.asc() }
```

**After:**
```swift
Item.order(by: \.name)
Item.order(by: \.id)
// After a join, use closure form without .asc():
.order { items, categories in items.id }
```

### Example 5: `import SQLiteData` replacing `import GRDB`

**Before:**
```swift
import GRDB
import SQLiteData
import StructuredQueries

private func createMigratedDatabase() throws -> DatabaseQueue {
  let db = try DatabaseQueue()
  try db.write { db in
    try db.execute(sql: "CREATE TABLE IF NOT EXISTS note (...)")
  }
  return db
}
```

**After:**
```swift
import SQLiteData

// Use bootstrapDatabase() with .dependencies trait
@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct DatabaseFeatureTests {
  @Dependency(\.defaultDatabase) var database
  // ...
}
```

### Example 6: Path un-nesting

**Before:**
```swift
@Reducer struct ContactsFeature {
  @Reducer enum Path {
    case detail(ContactDetailFeature)
  }
  @ObservableState struct State {
    var path = StackState<Path.State>()
  }
}
extension ContactsFeature.Path.State: Equatable {}
```

**After:**
```swift
@Reducer enum ContactsFeaturePath {
  case detail(ContactDetailFeature)
}

@Reducer struct ContactsFeature {
  @ObservableState struct State {
    var path = StackState<ContactsFeaturePath.State>()
  }
  enum Action {
    case path(StackActionOf<ContactsFeaturePath>)
  }
}
extension ContactsFeaturePath.State: Equatable {}
```

### Example 7: Effect.run error handling

**Before:**
```swift
case .onAppear:
  state.isLoading = true
  return .run { send in
    let notes = try await database.read { db in
      try Note.all.order { $0.createdAt.desc() }.fetchAll(db)
    }
    await send(.notesLoaded(notes))
  }
```

**After:**
```swift
case .viewAppeared:
  state.isLoading = true
  return .run { send in
    do {
      let notes = try await database.read { db in
        try Note.all.order { $0.createdAt.desc() }.fetchAll(db)
      }
      await send(.notesLoaded(notes))
    } catch {
      reportIssue(error)
    }
  }
```

### Example 8: `#sql` macro for migrations

**Before:**
```swift
migrator.registerMigration("v1") { db in
  try db.execute(sql: """
    CREATE TABLE IF NOT EXISTS note (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL DEFAULT ''
    )
    """)
}
```

**After:**
```swift
migrator.registerMigration("v1") { db in
  try #sql("""
    CREATE TABLE "note" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
      "title" TEXT NOT NULL DEFAULT ''
    ) STRICT
    """)
    .execute(db)
}
```

### Example 9: Dismiss dependency replacing popLast

**Before (parent handles pop):**
```swift
case .path(.element(_, .detail(.delegate(.deleteContact(let id))))):
  state.contacts.remove(id: id)
  _ = state.path.popLast()
  return .none
```

**After (parent uses remove(id:)):**
```swift
case .path(.element(let stackID, .detail(.delegate(.deleteContact(let contactID))))):
  state.contacts.remove(id: contactID)
  state.path.remove(id: stackID)
  return .none
```

### Example 10: `withKnownIssue` replacing `XCTExpectFailure`

**Before:**
```swift
func testDependencyClientUnimplementedReportsIssue() {
  let client = NumberClient()
  XCTExpectFailure {
    $0.compactDescription.contains("Unimplemented")
  }
  let result = client.fetch(42)
  XCTAssertEqual(result, 0)
}
```

**After:**
```swift
@Test func dependencyClientUnimplementedReportsIssue() {
  let client = NumberClient()
  withKnownIssue {
    _ = client.fetch(42)
  }
}
```

### Example 11: XCTestExpectation -> confirmation

**Before (Combine + expectation):**
```swift
let expectation = expectation(description: "publisher emits")
expectation.expectedFulfillmentCount = 3
let cancellable = $count.publisher.dropFirst().sink { value in
  received.append(value)
  expectation.fulfill()
}
wait(for: [expectation], timeout: 2.0)
```

**After (Observations async sequence):**
```swift
let task = Task {
  let sequence = Observations { count }
  for await value in sequence.prefix(4) {
    received.append(value)
  }
}
$count.withLock { $0 = 1 }
$count.withLock { $0 = 2 }
$count.withLock { $0 = 3 }
try? await task.value
expectNoDifference(received, [0, 1, 2, 3])
```

### Example 12: Draft insert form replacing column-specifying form

**Before:**
```swift
try Item.insert {
  ($0.name, $0.value, $0.isActive, $0.categoryId)
} values: {
  ("alpha", 5, true, Int?.some(1))
  ("beta", 15, true, Int?.some(1))
}.execute(db)
```

**After:**
```swift
try Item.insert {
  Item.Draft(name: "alpha", value: 5, isActive: true, categoryId: 1)
  Item.Draft(name: "beta", value: 15, isActive: true, categoryId: 1)
}.execute(db)
```

---

## Migration Strategy

### Wave Structure

Based on cross-cutting concern analysis, cascade effects, and build breakage windows, the following wave/batch execution order minimises broken builds and maximises parallelism.

#### Wave 0 -- Verification Baseline

Run `make test` and record exact passing count (expected: 121). This is the regression baseline.

#### Wave 1 -- Atomic Single-File Fixes (no cascade, lowest risk)

Each can be a standalone commit with a passing build:

1. **H5 + M1** -- Replace infix `==`/`>` with `.eq()`/`.gt()` and `.asc()` with `order(by:)` in `StructuredQueriesTests.swift` and `SQLiteDataTests.swift`
2. **H9** -- `static let testValue` -> `static var testValue` in `DependencyTests.swift:504`
3. **M15** -- Add `do/catch` + `reportIssue` to all `Effect.run` closures in `DatabaseFeature.swift`
4. **H14** -- Add `@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)` to `@Observable` classes

#### Wave 2 -- Structural Alignment (ordered within wave, some cascade)

Apply in listed order; do not parallelise within wave:

1. **H11** -- Add `@CasePathable` to all top-level Action enums in fuse-app (9 enums across 5 files). Must precede M3.
2. **M3** -- Replace `if case` with `.is()` / `[case:]` in 10 test callsites across 4 files. Depends on Wave 2.1.
3. **H1** -- Un-nest `@Reducer enum Path` from `ContactsFeature` -> `ContactsFeaturePath`, from `NavigationTests` -> `StackFeaturePath`, from `NavigationStackTests` -> `NavigationStackTestsPath`. Update all references atomically per file.
4. **H2** -- Merge dual `Reduce` closures in `Combined` / `StoreReducerTests.swift`; remove `CombineReducers`.
5. **H12** -- Change `[Todo]` to `IdentifiedArrayOf<Todo>` in `SharedModels.swift` + `SettingsFeature.swift` (single commit).
6. **P17** -- Change `[Note]` to `IdentifiedArrayOf<Note>` in `DatabaseFeature.State` + update action payloads.
7. **H13** -- Replace `state.path.popLast()` with `state.path.remove(id:)` in `ContactsFeature.swift`.
8. **M11** -- Replace boolean sheet state with `@Presents` optional in `UIPatternTests.swift:SheetToggleFeature`.
9. **M12** -- Replace manual `destination = nil` with child `dismiss()` pattern in `ContactsFeature.swift`.
10. **M6** -- Remove default `UUID()`/`Date()` from `Todo` and `Contact` init defaults; update all call sites.
11. **LOW** -- Rename `onAppear` -> `viewAppeared` and `addNoteTapped` -> `addButtonTapped` in 3 features + tests.

#### Wave 3 -- Database & Import Cleanup (ordered)

1. **H6 + P10** -- Remove `import GRDB`, `import StructuredQueriesSQLite`, `import StructuredQueries` from all app/test sources. Also remove `extension DatabaseQueue: @unchecked @retroactive Sendable {}`. Build-verify after each file.
2. **M5** -- Remove `GRDB` product from `FuseApp` target deps in Package.swift. Remove transitive deps from test targets (`ComposableArchitecture`/`GRDB` from `FuseAppIntegrationTests`; `Dependencies`/`DependenciesMacros` from `TCATests`).
3. **M9** -- Switch `DatabaseQueue(path:)` to `SQLiteData.defaultDatabase()` in `bootstrapDatabase`.
4. **M10** -- Move `bootstrapDatabase()` call to `@main` App struct `init()`.
5. **H7** -- Add `@FetchAll`/`@FetchOne` to `DatabaseView`; remove polling state from reducer.
6. **M7** -- Replace raw `db.execute(sql:)` with `#sql` macro in all migrations and test helpers.
7. **M8** -- Add `.dependencies { try $0.bootstrapDatabase() }` suite trait to database test suites; remove inline `makeDatabase()` / `createMigratedDatabase()` helpers.

#### Wave 4 -- Test Modernisation (largest volume, can parallelise across files)

Each file can be migrated independently, but within a file the conversion must be complete before building:

**Purely mechanical (do first):**
1. `SharedPersistenceTests.swift` -- 15 tests, `@MainActor`, no expectations
2. `StoreReducerTests.swift` -- 11 tests, one async
3. `ObservableStateTests.swift` -- 10 tests, `XCTFail` -> `Issue.record`
4. `BindingTests.swift` -- 7 tests
5. `StructuredQueriesTests.swift` -- 15 tests, all synchronous

**Async but straightforward:**
6. `EffectTests.swift` -- 8 tests; add `@Suite(.serialized)` if timing issues
7. `TestStoreEdgeCaseTests.swift` -- 4 tests
8. `TestStoreTests.swift` -- 13 tests (already hybrid)
9. `FuseLibraryTests.swift` + `ObservationTests.swift` -- 20 tests; `setUp` -> `init()`

**Complex:**
10. `DependencyTests.swift` -- 16 tests; `XCTExpectFailure` -> `withKnownIssue`; mixed actor
11. `FuseAppIntegrationTests.swift` -- 30 tests; 7 classes -> 7 `@Suite struct`

**Expectation rewrites (highest risk, do last):**
12. `SharedBindingTests.swift` -- 7 tests; inverted expectation rewrite
13. `SharedObservationTests.swift` -- 9 tests; Combine -> `Observations`
14. `SQLiteDataTests.swift` -- 14 tests; `ValueObservation` expectations

**Never migrate:** `XCSkipTests.swift` (both copies) -- `XCGradleHarness` requires XCTest.

#### Wave 5 -- Fork Code Cleanup

1. **M17** -- Rename `ObservationRegistrar` shadow type in `skip-android-bridge` -> `BridgeObservationRegistrar`; update TCA reference.
2. **LOW** -- Replace `DispatchSemaphore` with `os_unfair_lock` in `skip-android-bridge`.
3. **LOW** -- Document `FlagBox @unchecked Sendable` rationale in `ObservationVerifier.swift`.

#### Wave 6 -- Assertion Modernisation (cleanup pass)

1. **M4** -- Replace remaining `XCTAssertEqual` on structured types with `expectNoDifference` (concurrent with Wave 4).
2. **M14** -- Replace Combine publishers with `Observations {}` async sequence in `SharedObservationTests`.

### Ordering Constraints (Strict)

| Step | Must Precede | Reason |
|------|-------------|--------|
| H11 (`@CasePathable` on Actions) | M3 (`if case` -> `.is()`) | Key-path syntax requires `@CasePathable` |
| H6 (remove `import GRDB` from files) | M5 (remove GRDB from Package.swift deps) | Build must pass before dep removal |
| H12 (SharedModels type change) | Any test using `savedTodos` | Type mismatch breaks build |
| H1 (Path un-nesting) | Test file updates referencing nested Path type | Type rename breaks references |
| M9 (defaultDatabase()) | M8 (.dependencies trait) | Tests need correct bootstrap |
| Wave 3 (database cleanup) | Wave 4 database file migration | Clean imports required first |
| Wave 2 structural fixes | Wave 4 test migration | Don't migrate tests on top of broken code |

### Build Breakage Windows

| Change | Duration | Mitigation |
|--------|----------|------------|
| H1 Path un-nesting | Until all State/forEach/test references updated | Single editor pass, atomic commit |
| H12 IdentifiedArrayOf | 2 lines (SharedModels + SettingsFeature) | Edit both in same commit |
| H6 import removal | Until compiler confirms re-exports cover all symbols | Build-verify before Package.swift change |
| Each test class migration | During conversion of class -> struct | Convert one class at a time |
| CombineReducers removal (H2) | Until Reduce closures are merged | Short window, single file |

---

## Fork Changes

### Changes Required

| Fork | File | Change | Priority | Risk |
|------|------|--------|----------|------|
| `skip-android-bridge` | `Observation.swift:18` | Rename `struct Observation` wrapper -> `BridgeObservation` to avoid shadowing `Observation` module | MEDIUM | LOW -- no JNI exports reference it |
| `skip-android-bridge` | `Observation.swift:269` | Replace `DispatchSemaphore(value: 1)` with `os_unfair_lock` | LOW | MEDIUM -- JNI-facing concurrent lock |
| `swift-composable-architecture` | `ObservationStateRegistrar.swift:13` | Update `SkipAndroidBridge.Observation.ObservationRegistrar()` -> `SkipAndroidBridge.BridgeObservation.BridgeObservationRegistrar()` | MEDIUM | LOW -- follows namespace rename |

### No Changes Required

| Fork | Reason |
|------|--------|
| `swift-composable-architecture` (7 files with `@_spi(Reflection)`) | Legitimate upstream pattern; matches official TCA |
| `xctest-dynamic-overlay` | No PFW alignment issues found |
| `swift-perception` | Already uses `os_unfair_lock`; no issues found |
| `swift-case-paths` | No changes needed (SPI promotion out of scope) |
| `swift-sharing` | No changes needed |

### JNI Impact

None of the planned fork changes affect JNI bindings. All JNI exports use `@_cdecl` free functions whose symbol names are determined by string literals, not Swift type names. The `ObservationRecording` class called by JNI functions is top-level, not nested in the renamed struct.

### Android Safety

- `os_unfair_lock` is available on Android via Swift Android SDK's compatibility layer.
- Namespace rename affects no JNI-visible symbols.
- `@_spi(Reflection)` symbols work identically on Android (Swift enum metadata present in binary).

### Upstream Compatibility

All planned fork changes **improve** upstreamability:
- `DispatchSemaphore`-as-mutex is a known anti-pattern
- Module name shadowing would be rejected in upstream PRs
- Removing unused SPI imports is clean code practice

---

## Conflicts Between Researchers

### Conflict 1: `@Reducer struct` and `@CasePathable` synthesis

**pfw-case-paths researcher:** States `@Reducer struct` does NOT synthesise `@CasePathable` on `Action`. Explicit annotation required.

**pfw-composable-architecture researcher:** States `@Reducer` on a struct DOES synthesise `@CasePathable` automatically on `Action`, and adding it manually is unnecessary.

**Resolution:** Both are partially correct. `@Reducer` synthesises enough case path infrastructure for `store.send(\.caseName)` and scope routing, but the explicit `@CasePathable` annotation is safe, additive, and ensures full key-path syntax works everywhere (including `store.receive(\.action)` in tests). **Recommendation: Add `@CasePathable` explicitly.** No duplicate-conformance error occurs on `@Reducer struct` types. However, DO NOT add to `@Reducer enum` types (Destination, Path) where it IS fully synthesised and would cause a duplicate.

### Conflict 2: M12 dismissal approach (`destination = nil` vs `.dismiss`)

**pfw-composable-architecture researcher:** Recommends using `state.path.remove(id:)` for stack pop, and documents that `destination = nil` is acceptable when child has no effects (with documentation).

**pfw-swift-navigation researcher:** Recommends using `.send(.destination(.dismiss))` to trigger PresentationReducer's effect cancellation pipeline.

**Resolution:** Both patterns are valid in different contexts. For stack navigation: use `state.path.remove(id:)` (preferred). For presentation dismissal: use `@Dependency(\.dismiss)` in child or `.send(.destination(.dismiss))` in parent. Manual `destination = nil` is acceptable ONLY when the child demonstrably has zero async effects, and must be documented. Default to the dismiss-based patterns.

---

## Scope & Impact Assessment

### Files Requiring Changes

**Source files (6):**
- `ContactsFeature.swift` -- Path un-nesting (H1), popLast->remove(id:) (H13), destination=nil->dismiss (M12), onAppear->viewAppeared (LOW), @CasePathable on Action (H11)
- `DatabaseFeature.swift` -- import cleanup (H6/P10), defaultDatabase() (M9), bootstrapDatabase location (M10), #sql migrations (M7), @FetchAll/@FetchOne (H7), Effect.run error handling (M15), naming (LOW), @CasePathable (H11), [Note]->IdentifiedArrayOf (P17)
- `SharedModels.swift` -- Remove UUID()/Date() defaults (M6), IdentifiedArrayOf<Todo> (H12)
- `TodosFeature.swift` -- @CasePathable on Action (H11)
- `AppFeature.swift` -- @CasePathable on Action (H11)
- `SettingsFeature.swift` -- @CasePathable on Action (H11), naming (LOW), IdentifiedArrayOf<Todo> type update

**Test files (14 files requiring Swift Testing migration):**
- `FuseAppIntegrationTests.swift` -- XCTest->Swift Testing, import GRDB removal, expectNoDifference, .dependencies trait, try! removal
- `StructuredQueriesTests.swift` -- XCTest->Swift Testing, .eq()/.gt(), order(by:), draft form
- `SQLiteDataTests.swift` -- XCTest->Swift Testing, import GRDB removal, .eq(), .dependencies trait, ValueObservation expectations
- `EffectTests.swift` -- XCTest->Swift Testing
- `DependencyTests.swift` -- XCTest->Swift Testing, @_spi removal, static let->var, withKnownIssue
- `StoreReducerTests.swift` -- XCTest->Swift Testing, CombineReducers removal, if case->is()
- `TestStoreTests.swift` -- Complete hybrid migration (already imports Testing)
- `TestStoreEdgeCaseTests.swift` -- XCTest->Swift Testing
- `ObservableStateTests.swift` -- XCTest->Swift Testing, if case->is()
- `BindingTests.swift` -- XCTest->Swift Testing
- `SharedObservationTests.swift` -- XCTest->Swift Testing, Combine->Observations
- `SharedBindingTests.swift` -- XCTest->Swift Testing, inverted expectation rewrite
- `SharedPersistenceTests.swift` -- XCTest->Swift Testing
- `FuseLibraryTests.swift` + `ObservationTests.swift` -- XCTest->Swift Testing, setUp->init(), @available guard

**Package.swift files (2):**
- `fuse-library/Package.swift` -- Remove transitive deps from TCATests
- `fuse-app/Package.swift` -- Remove transitive deps and GRDB from FuseAppIntegrationTests and FuseApp

**Fork files (2-3):**
- `skip-android-bridge/.../Observation.swift` -- Rename namespace, DispatchSemaphore->os_unfair_lock
- `swift-composable-architecture/.../ObservationStateRegistrar.swift` -- Update renamed type reference

**Already correct (no changes needed):**
- C1 (.toggleCategory -> .categoryFilterChanged) -- ALREADY FIXED
- H3 (Action: Equatable) -- ALREADY CLEAN in all read files
- H4 (var id -> let id on @Table) -- ALREADY CORRECT
- H8 (try! in FuseApp.swift) -- ALREADY FIXED (uses do/catch + reportIssue)
- H9 (static let -> static var in SharedModels) -- ALREADY CORRECT
- M16 (@Column("itemCount") redundant) -- ALREADY RESOLVED

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Swift Testing migration breaks test count | LOW | HIGH | Run `make test` after each file; count must stay >= 121 |
| Path un-nesting breaks Equatable extensions | LOW | MEDIUM | Update all references atomically in single commit |
| `SQLiteData.defaultDatabase()` unavailable in test context | LOW | HIGH | Use `.dependencies { try $0.bootstrapDatabase() }` trait |
| `@CasePathable` + `@Reducer` macro conflict | VERY LOW | HIGH | Safe on structs; DO NOT add on `@Reducer enum` types |
| `IdentifiedArrayOf<Todo>` Codable migration | VERY LOW | LOW | Same JSON wire format as `[Todo]` |
| `#sql` macro doesn't support all DDL forms | LOW | MEDIUM | Verify CREATE TABLE works; fall back with documentation if needed |
| Inverted expectation rewrite fails | MEDIUM | MEDIUM | Proven pattern in ObservationBridgeTests.swift |
| `os_unfair_lock` on Android | LOW | HIGH | Available via Swift Android SDK; needs emulator testing |
| XCTestExpectation -> confirmation timing | MEDIUM | MEDIUM | Add `.timeLimit` trait; test with `.serialized` |

---

## Research Confidence

| Domain | Confidence | Source | Researcher Agreement |
|--------|-----------|--------|---------------------|
| Swift Testing patterns | HIGH | pfw-testing skill (canonical) | Full agreement |
| TCA action naming | HIGH | pfw-composable-architecture skill (canonical) | Full agreement |
| Path un-nesting | HIGH | pfw-composable-architecture skill (canonical) | Full agreement |
| Query named functions | HIGH | pfw-structured-queries skill + where.md + order-by.md | Full agreement |
| Database bootstrap | HIGH | pfw-sqlite-data skill + testing.md + migrations.md | Full agreement |
| `expectNoDifference` boundary | HIGH | pfw-custom-dump skill (canonical) | Full agreement |
| `@CasePathable` on Actions | HIGH | pfw-case-paths + pfw-composable-architecture (reconciled conflict) | Resolved -- add explicitly |
| Dismiss pattern | HIGH | pfw-composable-architecture + pfw-swift-navigation (reconciled) | Resolved -- prefer dismiss API |
| `Observations {}` pattern | HIGH | pfw-sharing skill (canonical) | Full agreement |
| Error handling in effects | HIGH | pfw-issue-reporting skill (canonical) | Full agreement |
| `#sql` for DDL migrations | HIGH | pfw-sqlite-data migrations.md (canonical) | Full agreement |
| `@Perceptible` vs `@Observable` | MEDIUM | pfw-perception skill -- project targets iOS 17+ so `@available` may suffice | Full agreement |
| IdentifiedArrayOf | HIGH | pfw-identified-collections + pfw-sharing (canonical) | Full agreement |
| Fork changes (M17, lock) | MEDIUM | fork-concerns scout -- Android testing needed | N/A (single scout) |
| Migration ordering | HIGH | cross-cutting-concerns + test-migration-risks scouts | Full agreement |
| XCTestExpectation migration | MEDIUM | test-migration-risks scout -- confirmation API semantics differ subtly | N/A (single scout) |

---

*Phase: 08-pfw-skill-alignment*
*Research reconciled: 2026-02-23*
*Sources: 12 PFW domain skills + 3 concern scouts, plus reference docs for structured-queries (where.md, order-by.md, inserts.md, safe-sql-strings.md) and sqlite-data (testing.md, migrations.md)*
*Researchers: pfw-testing, pfw-composable-architecture, pfw-sqlite-data, pfw-structured-queries, pfw-case-paths, pfw-custom-dump, pfw-dependencies, pfw-perception, pfw-swift-navigation, pfw-issue-reporting, pfw-sharing, pfw-identified-collections, cross-cutting-concerns, fork-concerns, test-migration-risks*
