# PFW CasePaths Research

Generated: 2026-02-23
Skill source: `/Users/jacob/.claude/skills/pfw-case-paths`
Audit source: `.planning/PFW-AUDIT-RESULTS.md`
Findings addressed: H11, M2, M3, and all LOW items touching CasePaths (14 total)

---

## Canonical Patterns

All patterns below are drawn directly from the `pfw-case-paths` skill.

### 1. Applying `@CasePathable` to an enum

```swift
@CasePathable
enum Action {
    case increment
    case decrement
    case setText(String)
    case child(ChildAction)
}
```

- Apply to every enum that will be used with key-path syntax (`.is()`, `[case:]`, `store.receive(\.caseName)`).
- `@Reducer` enum cases synthesise their own `@CasePathable` automatically — do NOT add `@CasePathable` manually to a `@Reducer` enum.
- Nested enums that are NOT themselves `@Reducer` must get `@CasePathable` explicitly (e.g. `Delegate`, `Alert`, `ConfirmationDialog`, `View` sub-enums).

### 2. Case presence check — use `.is(\.caseName)`

```swift
// CORRECT
action.is(\.setText)

// WRONG — do not use if-case for boolean checks
if case .setText = action { ... }
```

### 3. Associated value extraction — use `[case:]` subscript

```swift
// CORRECT
let value = action[case: \.setText]   // String?

// WRONG — do not use if-case for extraction when [case:] is available
if case let .setText(v) = action { ... }
```

### 4. In-place mutation — use `.modify(\.caseName)`

```swift
var action = Action.setText("hello")
action.modify(\.setText) { $0 = "world" }
```

### 5. `AnyCasePath` for generic embed / extract

```swift
let path = AnyCasePath<Action, String>(\.setText)
path.extract(from: action)   // String?
path.embed("hello")          // Action
```

### 6. `fileprivate` instead of `private` for nested enums

```swift
// CORRECT — avoids "inaccessible due to 'private' protection level" compiler error
struct Feature {
    @CasePathable fileprivate enum Action { ... }
}

// WRONG
struct Feature {
    @CasePathable private enum Action { ... }
}
```

`@CasePathable` generates a nested `AllCasePaths` struct whose members reference the enum. Swift's access control rules prevent those generated members from compile when the enum is `private`. Use `fileprivate` as the narrowest safe level.

### 7. `allCasePaths` iteration

```swift
for caseKeyPath in Action.allCasePaths { ... }  // PartialCaseKeyPath<Action>
Action.allCasePaths[someAction]                  // PartialCaseKeyPath<Action> — current case
```

### 8. `@_spi(Reflection)` is fragile SPI — do not use

```swift
// WRONG
@_spi(Reflection) import CasePaths

// CORRECT — the public API surface is sufficient for all production use
import CasePaths
```

---

## Current State

### H11 / M2: Missing `@CasePathable` on top-level Action enums in fuse-app

None of the five top-level `Action` enums in `fuse-app/Sources/FuseApp/` carry `@CasePathable`. The `@Reducer` macro on the surrounding struct does NOT synthesise `@CasePathable` for the Action enum — that must be added explicitly.

| File | Type | Line | Status |
|------|------|------|--------|
| `examples/fuse-app/Sources/FuseApp/AppFeature.swift` | `AppFeature.Action` | 22 | Missing `@CasePathable` |
| `examples/fuse-app/Sources/FuseApp/ContactsFeature.swift` | `ContactsFeature.Action` | 25 | Missing `@CasePathable` |
| `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift` | `DatabaseFeature.Action` | 55 | Missing `@CasePathable` |
| `examples/fuse-app/Sources/FuseApp/SettingsFeature.swift` | `SettingsFeature.Action` | 20 | Missing `@CasePathable` |
| `examples/fuse-app/Sources/FuseApp/TodosFeature.swift` | `TodosFeature.Action` | 35 | Missing `@CasePathable` |

Already correct (have `@CasePathable` on nested sub-enums):

- `ContactsFeature.swift:88` — `Destination.Alert` has `@CasePathable`
- `ContactsFeature.swift:93` — `Destination.ConfirmationDialog` has `@CasePathable`
- `ContactsFeature.swift:112` — `Action.Delegate` (ContactDetailFeature) has `@CasePathable`
- `ContactsFeature.swift:194` — `Action.Delegate` (EditContactFeature) has `@CasePathable`
- `ContactsFeature.swift:235` — `Action.Delegate` (AddContactFeature) has `@CasePathable`
- `CounterFeature.swift:21` — `Action.View` has `@CasePathable`
- `TodosFeature.swift:29` — `State.Filter` has `@CasePathable`
- `TodosFeature.swift:44` — `Action.Alert` has `@CasePathable`
- `TodosFeature.swift:49` — `Action.ConfirmationDialog` has `@CasePathable`

Note: `CounterFeature.Action` itself is missing `@CasePathable` even though its nested `View` sub-enum has it. `CounterFeature.Action` is not listed in the fuse-app files but follows the same pattern — it needs `@CasePathable` on the outer enum.

### M3: `if case` used instead of `.is()` / `[case:]` subscript

All ten occurrences across fuse-library tests:

| File | Line | Current pattern | Required replacement |
|------|------|-----------------|----------------------|
| `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift` | 400 | `if case .child = store.state.destination {` | `.is(\.child)` check |
| `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift` | 417 | `if case let .detail(state) = mutablePath {` | `[case: \.detail]` subscript |
| `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift` | 429 | `if case let .detail(state) = path {` | `[case: \.detail]` subscript |
| `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift` | 455 | `if case .ignored = state {` | `.is(\.ignored)` check |
| `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift` | 93 | `if case let .detail(state) = store.state.path[id: ...]` | `[case: \.detail]` subscript |
| `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift` | 123 | `if case let .detail(state) = store.state.path[id: id]` | `[case: \.detail]` subscript |
| `examples/fuse-library/Tests/TCATests/ObservableStateTests.swift` | 365 | `if case .featureA = store.withState(\.destination) {` | `.is(\.featureA)` check |
| `examples/fuse-library/Tests/TCATests/ObservableStateTests.swift` | 373 | `if case .featureB = store.withState(\.destination) {` | `.is(\.featureB)` check |
| `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift` | 317 | `if case let .loaded(counter) = state { return counter.count }` | `state[case: \.loaded]?.count` |
| `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift` | 325 | `if case let .loaded(counter) = state { return counter.count }` | `state[case: \.loaded]?.count` |

### LOW: `@_spi(Reflection) import CasePaths`

| File | Line | Issue |
|------|------|-------|
| `examples/fuse-library/Tests/TCATests/DependencyTests.swift` | 1 | `@_spi(Reflection) import CasePaths` — fragile SPI import |

The `EnumMetadata` type used at lines 451–471 of `DependencyTests.swift` is accessed via `@_spi(Reflection)`. This SPI is not part of the public API contract and may break without notice. The test at line 448 (`testNavigationIDEnumMetadataTag`) exists to validate Android ABI behaviour for TCA's internal `NavigationID` mechanism. See ordering dependencies below for the correct resolution.

### LOW: `private` cancel-ID enums — no current instances

A search for `private enum CancelID` returned no matches. This LOW finding from the audit is a pre-emptive rule: if cancel-ID enums are added in the future, use `fileprivate` not `private`.

---

## Required Changes

### File 1: `examples/fuse-app/Sources/FuseApp/AppFeature.swift`

**Line 22** — Add `@CasePathable` to `AppFeature.Action`.

Before:
```swift
enum Action {
    case counter(CounterFeature.Action)
    case todos(TodosFeature.Action)
    case contacts(ContactsFeature.Action)
    case database(DatabaseFeature.Action)
    case settings(SettingsFeature.Action)
    case tabSelected(State.Tab)
}
```

After:
```swift
@CasePathable
enum Action {
    case counter(CounterFeature.Action)
    case todos(TodosFeature.Action)
    case contacts(ContactsFeature.Action)
    case database(DatabaseFeature.Action)
    case settings(SettingsFeature.Action)
    case tabSelected(State.Tab)
}
```

### File 2: `examples/fuse-app/Sources/FuseApp/ContactsFeature.swift`

**Line 25** — Add `@CasePathable` to `ContactsFeature.Action`.

Before:
```swift
enum Action {
    case addButtonTapped
    case path(StackActionOf<Path>)
    case destination(PresentationAction<Destination.Action>)
    case contactTapped(Contact)
    case onAppear
}
```

After:
```swift
@CasePathable
enum Action {
    case addButtonTapped
    case path(StackActionOf<Path>)
    case destination(PresentationAction<Destination.Action>)
    case contactTapped(Contact)
    case onAppear
}
```

No changes needed for `ContactDetailFeature.Action` (already has `@CasePathable` on its `Delegate` sub-enum), `EditContactFeature.Action`, or `AddContactFeature.Action` — but their top-level `Action` enums also lack `@CasePathable`. Audit finding H11 specifically names these five files' top-level feature Actions. Apply `@CasePathable` to the top-level `Action` enum in:

- `ContactDetailFeature` (line 106)
- `EditContactFeature` (line 188 — already has `BindableAction` conformance; add `@CasePathable` before `enum`)
- `AddContactFeature` (line 229 — same as EditContactFeature)

### File 3: `examples/fuse-app/Sources/FuseApp/CounterFeature.swift`

**Line 16** — Add `@CasePathable` to `CounterFeature.Action`.

Before:
```swift
enum Action: ViewAction {
    case view(View)
    case factResponse(Result<String, Error>)
    case incrementResponse
    ...
}
```

After:
```swift
@CasePathable
enum Action: ViewAction {
    case view(View)
    case factResponse(Result<String, Error>)
    case incrementResponse
    ...
}
```

### File 4: `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`

**Line 55** — Add `@CasePathable` to `DatabaseFeature.Action`.

Before:
```swift
enum Action {
    case onAppear
    case addNoteTapped
    case deleteNote(Int64)
    case categoryFilterChanged(String)
    case notesLoaded([Note])
    case noteCountLoaded(Int)
    case noteAdded(Note)
    case noteDeleted(Int64)
}
```

After:
```swift
@CasePathable
enum Action {
    case onAppear
    case addNoteTapped
    case deleteNote(Int64)
    case categoryFilterChanged(String)
    case notesLoaded([Note])
    case noteCountLoaded(Int)
    case noteAdded(Note)
    case noteDeleted(Int64)
}
```

### File 5: `examples/fuse-app/Sources/FuseApp/SettingsFeature.swift`

**Line 20** — Add `@CasePathable` to `SettingsFeature.Action`.

Before:
```swift
enum Action: BindableAction {
    case binding(BindingAction<State>)
    case userNameChanged(String)
    case appearanceChanged(String)
    case notificationsToggled(Bool)
    case resetButtonTapped
    case onAppear
}
```

After:
```swift
@CasePathable
enum Action: BindableAction {
    case binding(BindingAction<State>)
    case userNameChanged(String)
    case appearanceChanged(String)
    case notificationsToggled(Bool)
    case resetButtonTapped
    case onAppear
}
```

### File 6: `examples/fuse-app/Sources/FuseApp/TodosFeature.swift`

**Line 35** — Add `@CasePathable` to `TodosFeature.Action`.

Before:
```swift
enum Action {
    case addButtonTapped
    case toggleTodo(Todo.ID)
    case filterChanged(State.Filter)
    case deleteTapped(Todo.ID)
    case alert(PresentationAction<Alert>)
    case confirmationDialog(PresentationAction<ConfirmationDialog>)
    case sortButtonTapped
    ...
}
```

After:
```swift
@CasePathable
enum Action {
    case addButtonTapped
    case toggleTodo(Todo.ID)
    case filterChanged(State.Filter)
    case deleteTapped(Todo.ID)
    case alert(PresentationAction<Alert>)
    case confirmationDialog(PresentationAction<ConfirmationDialog>)
    case sortButtonTapped
    ...
}
```

### File 7: `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift`

**Lines 399–403** — Replace `if case .child` presence check with `.is()`:

Before:
```swift
if case .child = store.state.destination {
    // Destination is .child — correct
} else {
    Issue.record("Expected .child destination")
}
```

After:
```swift
#expect(store.state.destination.is(\.child), "Expected .child destination")
```

**Lines 416–420** — Replace `if case let .detail(state)` extraction in `.modify` test with `[case:]` subscript:

Before:
```swift
var mutablePath = path
mutablePath.modify(\.detail) { $0.title = "Updated" }
if case let .detail(state) = mutablePath {
    #expect(state.title == "Updated")
} else {
    Issue.record("Expected .detail case after modify")
}
```

After:
```swift
var mutablePath = path
mutablePath.modify(\.detail) { $0.title = "Updated" }
if let state = mutablePath[case: \.detail] {
    #expect(state.title == "Updated")
} else {
    Issue.record("Expected .detail case after modify")
}
```

**Lines 428–432** — Replace `if case let .detail(state)` extraction in subscript-set test:

Before:
```swift
path[case: \.detail] = DetailRow.State(id: UUID(0), title: "Set")
if case let .detail(state) = path {
    #expect(state.title == "Set")
} else {
    Issue.record("Expected .detail case after subscript set")
}
```

After:
```swift
path[case: \.detail] = DetailRow.State(id: UUID(0), title: "Set")
if let state = path[case: \.detail] {
    #expect(state.title == "Set")
} else {
    Issue.record("Expected .detail case after subscript set")
}
```

**Lines 454–458** — Replace `if case .ignored` presence check:

Before:
```swift
if case .ignored = state {
    // Pass — case is constructible
} else {
    Issue.record("Expected .ignored case")
}
```

After:
```swift
#expect(state.is(\.ignored), "Expected .ignored case")
```

### File 8: `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift`

**Lines 92–96** — Replace `if case let .detail(state)` in `testNavigationStackPop`:

Before:
```swift
if case let .detail(state) = store.state.path[id: store.state.path.ids.last!] {
    #expect(state.title == "B")
} else {
    Issue.record("Expected .detail case for remaining top item")
}
```

After:
```swift
if let state = store.state.path[id: store.state.path.ids.last!]?[case: \.detail] {
    #expect(state.title == "B")
} else {
    Issue.record("Expected .detail case for remaining top item")
}
```

**Lines 122–126** — Replace `if case let .detail(state)` in `testNavigationStackChildMutation`:

Before:
```swift
if case let .detail(state) = store.state.path[id: id] {
    #expect(state.title == "Mutated")
} else {
    Issue.record("Expected .detail case after mutation")
}
```

After:
```swift
if let state = store.state.path[id: id]?[case: \.detail] {
    #expect(state.title == "Mutated")
} else {
    Issue.record("Expected .detail case after mutation")
}
```

### File 9: `examples/fuse-library/Tests/TCATests/ObservableStateTests.swift`

**Lines 364–368** — Replace `if case .featureA` check:

Before:
```swift
if case .featureA = store.withState(\.destination) {
    // success
} else {
    XCTFail("Expected .featureA case")
}
```

After:
```swift
XCTAssertTrue(
    store.withState(\.destination).is(\.featureA),
    "Expected .featureA case"
)
```

**Lines 372–376** — Replace `if case .featureB` check:

Before:
```swift
if case .featureB = store.withState(\.destination) {
    // success
} else {
    XCTFail("Expected .featureB case after switching")
}
```

After:
```swift
XCTAssertTrue(
    store.withState(\.destination).is(\.featureB),
    "Expected .featureB case after switching"
)
```

Note: `DestinationFeature.State` is produced by `@Reducer enum DestinationFeature` at line 138. Because `@Reducer` synthesises `@CasePathable` on the generated `State` enum automatically, `.is()` and `[case:]` work here without any manual annotation.

### File 10: `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift`

**Lines 315–319** and **323–327** — Replace both `if case let .loaded(counter)` extractions in `testIfCaseLetReducer`. These occur inside `store.withState { }` closures that return `Int?`:

Before (lines 316–318):
```swift
let count: Int? = store.withState { state -> Int? in
    if case let .loaded(counter) = state { return counter.count }
    return nil
}
```

After:
```swift
let count: Int? = store.withState { state -> Int? in
    state[case: \.loaded]?.count
}
```

Apply the same replacement at lines 324–326.

### File 11: `examples/fuse-library/Tests/TCATests/DependencyTests.swift`

**Line 1** — Remove `@_spi(Reflection)` qualifier from the CasePaths import.

Before:
```swift
@_spi(Reflection) import CasePaths
```

After:
```swift
import CasePaths
```

The `EnumMetadata` type used in `testNavigationIDEnumMetadataTag` (line 451) is accessed via the SPI. If removing `@_spi(Reflection)` causes `EnumMetadata` to be unavailable, the correct resolution is to remove or rewrite `testNavigationIDEnumMetadataTag` to use only the public `@CasePathable` API (`.is()`, `[case:]`, `allCasePaths`). The test's stated purpose — validating Android ABI smoke-test for TCA's internal `NavigationID` — does not require `EnumMetadata` directly; it is testing internal TCA behaviour that TCA itself covers in its own test suite.

---

## `@CasePathable` + `@Reducer` Interaction

### Rule 1: `@Reducer` struct — Action enum needs explicit `@CasePathable`

`@Reducer` applied to a `struct` does NOT synthesise `@CasePathable` for the nested `Action` enum. You must add it manually:

```swift
@Reducer
struct MyFeature {
    @CasePathable          // <-- required; @Reducer does NOT add this
    enum Action {
        case doThing
        case child(ChildFeature.Action)
    }
}
```

Without `@CasePathable`, key-path syntax (`store.receive(\.doThing)`, `action.is(\.doThing)`) will not compile.

### Rule 2: `@Reducer` enum — `@CasePathable` is synthesised automatically

`@Reducer` applied to an `enum` (the `Destination`/`Path` pattern) DOES synthesise `@CasePathable` on both the generated `State` and `Action` enums. Do NOT add `@CasePathable` manually — it will produce a duplicate conformance warning/error.

```swift
@Reducer                   // synthesises @CasePathable on State and Action automatically
enum Destination {
    case sheet(SheetFeature)
    case alert(AlertState<Alert>)
}
```

This is why `store.state.destination.is(\.sheet)` compiles without any explicit annotation on `Destination`.

### Rule 3: Nested non-`@Reducer` enums always need explicit `@CasePathable`

Sub-enums that are not themselves annotated with `@Reducer` must get `@CasePathable` explicitly:

```swift
@Reducer
struct MyFeature {
    @CasePathable
    enum Action {
        case alert(PresentationAction<Alert>)

        @CasePathable          // <-- must be explicit on this nested enum
        enum Alert {
            case confirmDeletion
        }
    }
}
```

### Rule 4: `fileprivate` vs `private` when `@CasePathable` is applied

The `@CasePathable` macro generates a nested `AllCasePaths` struct. Swift's access control requires that `AllCasePaths`'s members be at least as visible as the enum itself. If the enum is `private`, the generated members cannot reference it — this produces:

> 'MyEnum' is inaccessible due to 'private' protection level

Fix: use `fileprivate` as the narrowest access level when the enum is defined inside another type.

```swift
struct Feature {
    @CasePathable fileprivate enum Action { ... }  // correct
}
```

In this codebase, none of the current Action enums in fuse-app are declared `private` — they are implicitly `internal`. This rule applies when you add new cancel-ID enums or helper enums nested inside a struct/class.

### Rule 5: `BindableAction` and `ViewAction` conformances compose with `@CasePathable`

Adding `@CasePathable` to an enum that already conforms to `BindableAction` or `ViewAction` is safe and correct:

```swift
@CasePathable
enum Action: BindableAction {
    case binding(BindingAction<State>)
    case userNameChanged(String)
}
```

```swift
@CasePathable
enum Action: ViewAction {
    case view(View)
    case factResponse(Result<String, Error>)
}
```

Neither `BindableAction` nor `ViewAction` conflict with `CasePathable`. The `BindingReducer()` and `@ViewAction` infrastructure in TCA uses `@CasePathable` internally, so adding it explicitly is always correct here.

---

## Ordering Dependencies

Perform changes in this exact order. Each step's output is a prerequisite for the next.

### Step 1 — fuse-app Action enums (prerequisite for nothing, blocks Step 2)

Add `@CasePathable` to the six top-level Action enums in fuse-app:

1. `AppFeature.Action` (`AppFeature.swift:22`)
2. `ContactsFeature.Action` (`ContactsFeature.swift:25`)
3. `ContactDetailFeature.Action` (`ContactsFeature.swift:106`)
4. `EditContactFeature.Action` (`ContactsFeature.swift:188`)
5. `AddContactFeature.Action` (`ContactsFeature.swift:229`)
6. `CounterFeature.Action` (`CounterFeature.swift:16`)
7. `DatabaseFeature.Action` (`DatabaseFeature.swift:55`)
8. `SettingsFeature.Action` (`SettingsFeature.swift:20`)
9. `TodosFeature.Action` (`TodosFeature.swift:35`)

Build after this step: `cd examples/fuse-app && swift build`. Expect zero new errors — the annotation is purely additive.

### Step 2 — fuse-library test `if case` replacements (depends on Step 1 for `@Reducer` enum types, independent for `@CasePathable` enums)

The `if case` replacements in NavigationTests and NavigationStackTests use `@Reducer enum Path` and `@Reducer enum Destination` types, which already have `@CasePathable` synthesised. These can be done independently of Step 1, but do them after to avoid split commits.

Order within Step 2 (no internal dependencies — do all at once):

1. `NavigationTests.swift` lines 400, 417, 429, 455
2. `NavigationStackTests.swift` lines 93, 123
3. `ObservableStateTests.swift` lines 365, 373

Build + test: `make test-filter FILTER=NavigationTests` and `make test-filter FILTER=ObservableStateTests`.

### Step 3 — `StoreReducerTests.swift` `if case` replacements (depends on `EnumFeature.State` having `@CasePathable`)

`EnumFeature` is defined in `StoreReducerTests.swift` as:

```swift
@Reducer
enum EnumFeature {
    case loading
    case loaded(Counter.State)
}
```

This is a `@Reducer enum`, so its `State` already has `@CasePathable` synthesised. The `[case: \.loaded]` subscript will work immediately. No prerequisite other than Step 2 being complete for logical ordering.

Build + test: `make test-filter FILTER=StoreReducerTests`.

### Step 4 — `DependencyTests.swift` SPI removal (independent, do last)

Remove `@_spi(Reflection)` from line 1. Check if `EnumMetadata` is still available under the public import. If the compiler reports `EnumMetadata` as unresolved:

- Remove the entire `testNavigationIDEnumMetadataTag` test function (lines 448–473).
- Remove the file-scope `@CasePathable enum TestAction` (lines 507–511) only if it was solely used by that test.
- Replace with a comment: `// EnumMetadata ABI tested via CasePaths.allCasePaths in CasePathsTests.swift`.

Build + test: `make test-filter FILTER=DependencyTests`.

### Step 5 — Verify fuse-app integration tests still pass

The integration tests in `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` use key-path receive syntax (`await store.receive(\.factResponse.success)`, `await store.receive(\.noteAdded)`) which requires `@CasePathable` on the Action enums. After Step 1 those will now have proper macro support. Run:

```bash
cd examples/fuse-app && swift test
```

Expect all existing tests to pass. The Step 1 additions are additive — no existing code breaks.

### Do NOT do

- Do not add `@CasePathable` to `@Reducer enum` types (`Destination`, `Path`) — it is already synthesised and will cause a duplicate conformance error.
- Do not use `private` on any enum that receives `@CasePathable` — use `fileprivate` or `internal`.
- Do not keep `@_spi(Reflection) import CasePaths` anywhere in production or test code.
- Do not use `if case` for boolean presence checks where `.is()` is available.
- Do not use `if case let` for extraction where `[case:]` subscript is available and the value is used immediately (e.g. as a function argument or in an `#expect`).

The one exception: `if case let .x(value) = subject { ... }` is acceptable inside a `switch` statement body, because that is the standard Swift pattern-matching form. The prohibition targets stand-alone `if case` expressions used purely to check or extract when the CasePaths API exists.
