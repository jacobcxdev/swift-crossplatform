# PFW Composable Architecture — Phase 8 Research

Generated: 2026-02-23
Skill source: `/Users/jacob/.claude/skills/pfw-composable-architecture`
Audit source: `.planning/PFW-AUDIT-RESULTS.md` (28 findings)

---

## Canonical Patterns

These are the exact rules extracted from the `pfw-composable-architecture` skill. Each rule is stated as a DO or DO NOT to be applied mechanically.

### 1. Reducer declaration

```swift
@Reducer struct Counter {
  @ObservableState struct State { ... }
  enum Action { ... }
  var body: some Reducer<State, Action> {
    Reduce { state, action in ... }
  }
}
```

- **DO** use `@Reducer` macro on structs (or enums for destination/path).
- **DO NOT** append `Reducer` suffix to the type name.
- **DO NOT** use the legacy `reduce(into:action:)` method — use `body` + `Reduce`.

### 2. Action naming

- **DO** name action cases literally after what the user did: `incrementButtonTapped`, `addButtonTapped`, `deleteButtonTapped`, `sortButtonTapped`.
- **DO** name effect-response cases after the data returned: `factResponse`, `noteAdded`, `noteDeleted`, `notesLoaded`.
- **DO NOT** name cases after intent: `increment`, `decrement`, `fetch`.
- **DO** use `viewAppeared` (not `onAppear`) for the lifecycle action sent from `.task { store.send(.viewAppeared) }`.
- **DO** use `addButtonTapped` (not `addNoteTapped`) consistently — always `<noun>ButtonTapped`.

### 3. Action: Equatable

```swift
// WRONG
enum Action: Equatable { ... }

// CORRECT
enum Action { ... }
```

- **DO NOT** conform `Action` to `Equatable`. `@CasePathable` (synthesised by `@Reducer`) is the mechanism for pattern-matching actions in tests and `receive`; `Equatable` is not needed and conflicts with the macro.

### 4. @CasePathable on Action enums

```swift
// WRONG — top-level Action enum missing @CasePathable
@Reducer struct ContactsFeature {
  enum Action { ... }
}

// CORRECT — @Reducer synthesises @CasePathable automatically on the outer Action,
// but nested Delegate / Alert / ConfirmationDialog sub-enums need it explicitly
@Reducer struct ContactsFeature {
  enum Action {
    case delegate(Delegate)
    @CasePathable
    enum Delegate { case deleteContact(Contact.ID) }
  }
}
```

- **DO NOT** manually add `@CasePathable` to the top-level `Action` enum declared inside a `@Reducer` — `@Reducer` synthesises it automatically.
- **DO** add `@CasePathable` to every nested sub-enum (Delegate, Alert, ConfirmationDialog) because the macro only covers the direct `Action` type.
- **DO** use `\.caseName` key-path syntax (`store.receive(\.factResponse.success)`) which requires `@CasePathable` to be present.

### 5. Path feature un-nesting

```swift
// WRONG — Path nested inside parent
@Reducer struct ContactsFeature {
  @Reducer enum Path { case detail(ContactDetailFeature) }
}

// CORRECT — standalone top-level type, prefixed with parent name
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
```

- **DO NOT** nest `Path` (or `Destination`) enums inside parent reducers when they are `@Reducer` enums themselves (nesting creates ambiguous type paths and name-collision risk).
- **DO** use the `ParentNamePath` / `ParentNameDestination` prefix convention.
- The `Destination` pattern in `ContactDetailFeature` is acceptable as-is because it uses `@Reducer enum Destination` nested inside `ContactDetailFeature` — the rule specifically targets `Path`, which is used with `StackState`. Both `ContactsFeature.Destination` and `ContactDetailFeature.Destination` should be un-nested as `ContactsFeatureDestination` and `ContactDetailFeatureDestination` respectively to be fully consistent, but the audit finding H1 specifically calls out `Path`.

### 6. CombineReducers rule

```swift
// WRONG — CombineReducers with no modifier applied to it
var body: some Reducer<State, Action> {
  CombineReducers {
    Reduce { ... }
    Reduce { ... }
  }
  // nothing chained onto CombineReducers
}

// CORRECT option A — remove CombineReducers, keep bare Reduce
var body: some Reducer<State, Action> {
  Reduce { state, action in
    // first logic
    ...
    // second logic merged inline
    ...
  }
}

// CORRECT option B — apply a modifier
var body: some Reducer<State, Action> {
  CombineReducers {
    Scope(state: \.child1, action: \.child1) { Child1() }
    Scope(state: \.child2, action: \.child2) { Child2() }
  }
  .ifLet(\.$modal, action: \.modal) { Modal() }
}
```

- **DO NOT** use `CombineReducers` if no reducer modifier (`ifLet`, `forEach`, `ifCaseLet`, `_printChanges`, etc.) is chained onto it.
- **DO** inline multiple `Reduce` closures into a single `Reduce` when they share the same state/action domain and no modifier is needed.

### 7. Presentation pattern (@Presents)

```swift
// WRONG — legacy @PresentationState
@PresentationState var child: Child.State?

// CORRECT
@Presents var child: Child.State?
```

```swift
// WRONG — manual destination = nil
case .destination(.presented(.addContact(.delegate(.saveContact(let contact))))):
  state.contacts.append(contact)
  state.destination = nil  // skips PresentationReducer effect cancellation
  return .none

// CORRECT — use @Dependency(\.dismiss) in the child
// or document that there are no in-flight effects to cancel
```

```swift
// WRONG — Boolean flag for sheet
var showSheet = false

// CORRECT — optional state drives presentation
@Presents var sheet: SheetContent.State?
```

- **DO** use `@Presents` (not `@PresentationState`).
- **DO** use `.ifLet(\.$child, action: \.child)` (note the `$` sigil for `@Presents`).
- **DO** use `.sheet(item: $store.scope(state: \.child, action: \.child))` in views (not legacy `sheet(store:)`).
- **DO** use `@Dependency(\.dismiss)` in child features to self-dismiss instead of setting `destination = nil` in the parent.
- **DO NOT** use a Boolean flag to drive sheet presentation when the sheet has its own reducer state.

### 8. Destination enum pattern (single combined enum)

```swift
// WRONG — two separate @Presents
@Presents var alert: AlertState<Action.Alert>?
@Presents var confirmationDialog: ConfirmationDialogState<Action.ConfirmationDialog>?

// CORRECT — single @Reducer enum Destination covering all presentations
@Reducer enum ContactsFeatureDestination {
  @ReducerCaseEphemeral
  case alert(AlertState<AlertAction>)
  case addContact(AddContactFeature)
}
@Presents var destination: ContactsFeatureDestination.State?
```

- **DO** consolidate multiple presentation slots into a single `Destination` enum when the feature can only show one presentation at a time.
- **DO** use `@ReducerCaseEphemeral` for `AlertState` and `ConfirmationDialogState` cases inside `Destination`.
- Exception: `TodosFeature` uses two separate `@Presents` (`alert` and `confirmationDialog`) which can legitimately appear at the same time; this is a LOW finding and acceptable until Phase 8 specifically targets it.

### 9. @ViewAction

```swift
// Pattern: wrap all user-initiated actions under a View sub-enum
@Reducer struct CounterFeature {
  enum Action: ViewAction {
    case view(View)
    case factResponse(Result<String, Error>)

    @CasePathable
    enum View {
      case incrementButtonTapped
      case decrementButtonTapped
    }
  }
}

// In the view:
@ViewAction(for: CounterFeature.self)
struct CounterView: View {
  let store: StoreOf<CounterFeature>
  var body: some View {
    Button("+") { send(.incrementButtonTapped) }
  }
}
```

- **DO** use `@ViewAction` when a feature's `Action` has a `View` sub-enum conforming to `ViewAction`.
- **DO** annotate the `View` sub-enum with `@CasePathable`.
- **DO NOT** mix `@ViewAction` and direct `store.send(.view(...))` calls in the same view — the macro replaces `store.send` with the unqualified `send`.
- Features without a `View` sub-enum do not need `@ViewAction`.

### 10. Stack navigation (StackState / forEach)

```swift
var body: some ReducerOf<Self> {
  Reduce { ... }
    .forEach(\.path, action: \.path) {
      ParentNamePath.body
    }
}
```

```swift
// View
NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
  RootView()
} destination: { pathStore in
  switch pathStore.case {
  case let .detail(detailStore):
    DetailView(store: detailStore)
  }
}
```

- **DO** use `StackState` + `StackActionOf` + `.forEach` — never manage a plain `[State]` array for push navigation.
- **DO** use `NavigationStack(path: $store.scope(...))` — not the legacy `NavigationStackStore`.
- **DO** use `@Dependency(\.dismiss)` or `state.path.remove(id:)` (not `state.path.popLast()`) when removing from the stack inside a reducer action.

### 11. Dependencies

- **DO** declare `@Dependency` directly inside the `@Reducer` struct, not outside.
- **DO** use `static var liveValue` / `static var testValue` as computed properties on `DependencyKey` — not `static let`.
- **DO** use `@Dependency(\.uuid) var uuid` and call `uuid()` — not bare `UUID()`.
- **DO** use `@Dependency(\.date.now) var now` — not `Date()` or `Date.now`.
- **DO** use `Result` — not deprecated `TaskResult`.

### 12. Uncontrolled UUID / Date in model defaults

```swift
// WRONG
struct Todo {
  var id: UUID = UUID()
  var createdAt: Date = .now
}

// CORRECT — no defaults; caller injects via dependency
struct Todo {
  var id: UUID
  var createdAt: Date
}
// In reducer:
let newTodo = Todo(id: uuid(), createdAt: date.now)
```

- **DO NOT** put `UUID()` or `Date()` / `.now` as property defaults on model types.
- **DO** require the caller (always a reducer with a `@Dependency`) to supply the values.

### 13. Error handling in Effect.run

```swift
// WRONG — error silently lost
case .fetch:
  return .run { send in
    let data = try await api.fetch()
    await send(.response(data))
  }

// CORRECT — explicit catch with reportIssue or dedicated error action
case .fetch:
  return .run { send in
    await send(.response(Result { try await api.fetch() }))
  }
// or:
case .fetch:
  return .run { send in
    let data = try await api.fetch()
    await send(.response(data))
  } catch: { error, send in
    await send(.fetchFailed(error))
  }
```

- **DO** handle errors explicitly in every `Effect.run` closure.
- **DO** use `reportIssue(error)` (from `IssueReporting`) when there is no meaningful user-visible recovery.

---

## Current State

Inventory of every TCA-related finding in the codebase, by file.

### `examples/fuse-app/Sources/FuseApp/ContactsFeature.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 13–15 | `@Reducer enum Path` nested inside `ContactsFeature` | H1 |
| 48 | `_ = state.path.popLast()` — bypasses TCA stack action mechanism | H13 |
| 25 | `enum Action { ... }` — missing `@CasePathable` (not synthesised by `@Reducer` on the outer enum due to the sub-enum nesting; but per skill: `@Reducer` on a struct does synthesise `@CasePathable` on `Action`) | H11 (MEDIUM — already synthesised by macro, see note below) |
| 56 | `state.destination = nil` — manual nil skips `PresentationReducer` effect cancellation | M12 |

**Note on H11 / @CasePathable in fuse-app features:** The `@Reducer` macro applied to a struct automatically synthesises `@CasePathable` on the `Action` enum declared inside it. The audit finding H11 ("missing `@CasePathable` from all top-level Action enums in fuse-app") refers to features that do NOT use `@Reducer` (e.g. AppFeature, ContactsFeature, etc. which all use `@Reducer`) — this is a false-positive for features that already have `@Reducer`. However, the finding is real for `ContactsFeature.Action` and `AppFeature.Action` if they are missing the `@CasePathable` attribute in source (the macro synthesises it at compile time but the source attribute is still best practice for documentation). Confirmed: none of the fuse-app Action enums carry an explicit `@CasePathable` annotation in source; they rely on `@Reducer` synthesis.

**Also in ContactsFeature.swift:**
- Line 8–10: `@Reducer enum Destination` also nested inside `ContactsFeature` — same un-nesting rule applies (LOW priority relative to Path)
- Line 83–98: `@Reducer enum Destination` nested inside `ContactDetailFeature` — same issue

### `examples/fuse-app/Sources/FuseApp/TodosFeature.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 13–14 | Two separate `@Presents var alert` and `@Presents var confirmationDialog` instead of single Destination enum | LOW |
| 36 | `enum Action { ... }` — no explicit `@CasePathable` in source (synthesised by `@Reducer`) | H11 (synthesised) |

TodosFeature uses two presentations simultaneously (alert for deletion, dialog for sorting) — these are legitimately independent and the single-Destination consolidation is a LOW priority item only if they are mutually exclusive. Current code allows both to be non-nil at the same time; consolidation requires logic changes. Defer to a separate phase.

### `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 55–64 | `enum Action` — `addNoteTapped` should be `addButtonTapped` (naming convention) | LOW |
| 72–110 | `Effect.run` closures without `catch:` block — errors silently lost | M15 |
| 58 | `case onAppear` — should be `case viewAppeared` | LOW |

### `examples/fuse-app/Sources/FuseApp/SettingsFeature.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 26 | `case onAppear` — should be `case viewAppeared` | LOW |

### `examples/fuse-app/Sources/FuseApp/SharedModels.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 16 | `init(id: UUID = UUID(), ...)` on `Todo` — uncontrolled UUID default | M6 |
| 16 | `init(..., createdAt: Date = .now)` on `Todo` — uncontrolled Date default | M6 |
| 31 | `init(id: UUID = UUID(), ...)` on `Contact` — uncontrolled UUID default | M6 |
| 82–87 | `static let liveValue`, `static let testValue`, `static let previewValue` — must be `static var` | H9 |
| 64 | `FileStorageKey<[Todo]>` — should use `IdentifiedArrayOf<Todo>` | H12 |

### `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 2 | `import GRDB` — must be removed | H6 |
| 96 | `XCTAssertEqual(store.state.todos.count, 1)` — should use `expectNoDifference` | M4 |
| 145–146 | `XCTAssertEqual(store.state.filteredTodos.count, 1)` / `.first?.title` — should use `expectNoDifference` | M4 |
| 314–316 | `createMigratedDatabase()` uses `db.execute(sql:)` — should use `#sql` macro | M7 |
| 332 | `try! createMigratedDatabase()` — `try!` in test helper | LOW |
| All test classes | `final class XFeatureTests: XCTestCase` — missing `@Suite(.serialized)` pattern | H10 |
| All test classes | No `.dependencies` trait | M8 |

**C1 (CRITICAL):** Line 372 — test sends `.categoryFilterChanged("work")` which IS the correct action name (the reducer at line 59 defines `case categoryFilterChanged(String)`). The audit note says C1 was `.toggleCategory` but the current file at line 372 already sends `.categoryFilterChanged("work")`. **C1 is already fixed** in the current file state.

### `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 9 | `enum Action { case increment, decrement }` — action names are intent-based, not event-based | LOW |
| 134–151 | `struct Combined` uses bare `CombineReducers { ... }` with no modifier applied | H2 |
| Various | None of the test `Action` enums conform to `Equatable` — this file is CLEAN for H3 |

**H2 detail:** `Combined` reducer (lines 128–152) uses:
```swift
var body: some ReducerOf<Self> {
  CombineReducers {
    Reduce { ... }  // counts
    Reduce { ... }  // logs
  }
}
```
No modifier (`.ifLet`, `.forEach`, `._printChanges`, etc.) is applied to the `CombineReducers` block. These two `Reduce` closures must be inlined into a single `Reduce`.

### `examples/fuse-library/Tests/TCATests/EffectTests.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 9 | `enum Action { case noop }` — intent-based name | LOW |
| All reducers | No `Action: Equatable` — CLEAN for H3 |
| 120 | `enum CancelID: Hashable { case timer }` — file-scope cancel ID enum; should be inside the reducer | LOW (fragile SPI note) |

### `examples/fuse-library/Tests/TCATests/DependencyTests.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 1 | `@_spi(Reflection) import CasePaths` — fragile SPI import | LOW |
| 9–11 | `static var liveValue: Int { 42 }` / `static var testValue: Int { 0 }` — these are already `var` computed properties, CLEAN for H9 |
| 501–504 | `static let testValue = NumberClient()` — `static let` on `TestDependencyKey` conformance | H9 variant |
| All reducers | No `Action: Equatable` — CLEAN for H3 |

### `examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 112–134 | `SheetToggleFeature` uses `var showSheet = false` (Boolean) instead of `@Presents var sheet: SheetContent.State?` | M11 |
| All reducers | No `Action: Equatable` — CLEAN for H3 |

### `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 16–18 | `@Reducer enum Path` nested inside `StackFeature` | H1 |
| All reducers | No `Action: Equatable` — CLEAN for H3 |

### `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift`

| Line | Finding | Audit ref |
|------|---------|-----------|
| 18–20 | `@Reducer enum Path` nested inside `AppFeature` | H1 |
| 182 | `#expect(Bool(true), ...)` — no-op assertion | LOW |
| All reducers | No `Action: Equatable` — CLEAN for H3 |

**H3 re-audit:** The audit listed H3 as affecting EffectTests, DependencyTests, StoreReducerTests, UIPatternTests, TestStoreEdgeCaseTests. Reading the actual files: NONE of the test reducers in the read files conform Action to Equatable. H3 appears to affect files NOT yet read, or the finding pre-dates recent edits. Confirmed clean in: EffectTests, DependencyTests, StoreReducerTests, UIPatternTests, NavigationTests, NavigationStackTests.

---

## Required Changes

Changes are listed file by file, in execution order within each file.

### Wave 1 — Blocking correctness (do these first)

#### `examples/fuse-app/Sources/FuseApp/SharedModels.swift`

**Change 1a — `static let` → `static var` on NumberFactClient (H9)**

```swift
// BEFORE (line 82–87)
extension NumberFactClient: DependencyKey {
    static let liveValue: Self = ...
    static let testValue: Self = ...
    static let previewValue: Self = ...
}

// AFTER
extension NumberFactClient: DependencyKey {
    static var liveValue: Self {
        Self(fetch: { number in "The number \(number) is interesting!" })
    }
    static var testValue: Self { Self() }
    static var previewValue: Self {
        Self(fetch: { number in "Preview fact for \(number)" })
    }
}
```

Note: The current file already uses computed `static var` for `liveValue` and property syntax for `testValue`/`previewValue`. Re-check the actual syntax — as read, lines 82–87 show:
```
static var liveValue: Self {
    Self(fetch: { number in "The number \(number) is interesting!" })
}
static var testValue: Self { Self() }
static var previewValue: Self { ... }
```
This is ALREADY compliant. H9 is clean in SharedModels.swift. The H9 finding in DependencyTests.swift line 501 (`static let testValue = NumberClient()`) is the remaining violation.

**Change 1b — Remove default UUID/Date from model inits (M6)**

```swift
// BEFORE
struct Todo: ... {
    init(id: UUID = UUID(), title: String = "", isComplete: Bool = false, createdAt: Date = .now) { ... }
}
struct Contact: ... {
    init(id: UUID = UUID(), name: String = "", email: String = "") { ... }
}

// AFTER
struct Todo: ... {
    init(id: UUID, title: String = "", isComplete: Bool = false, createdAt: Date) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}
struct Contact: ... {
    init(id: UUID, name: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.email = email
    }
}
```

**Downstream impact:** Every call site that constructs `Todo(...)` or `Contact(...)` without explicit `id:` and `createdAt:` will fail to compile. Specifically:
- `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` lines 100, 137, 196, 251, 294, 352 — all construct `Todo` or `Contact` with positional args that currently rely on the defaults.
- `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift` — `ChildSheet` etc. have no `Todo`/`Contact` usage but check for transitive use.

Fix all call sites in the same commit as the model change. The `TodosFeature` reducer already injects via `@Dependency`; test helpers that use `Todo(id: UUID(), ...)` or `Contact(id: UUID(), ...)` must be updated to pass explicit values.

**Change 1c — FileStorageKey type (H12)**

```swift
// BEFORE
extension SharedKey where Self == FileStorageKey<[Todo]>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(...), default: []]
    }
}

// AFTER
extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(...), default: []]
    }
}
```

Also update `SettingsFeature.State`:
```swift
// BEFORE
@Shared(.savedTodos) var savedTodos: [Todo] = []

// AFTER
@Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []
```

#### `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift`

**Change 2a — Remove `import GRDB` (H6)**

```swift
// BEFORE line 2
import GRDB

// AFTER — remove entirely
```

**Change 2b — Replace `try!` with `throws` propagation (LOW, but needed for H8 wave)**

```swift
// BEFORE line 332
let db = try! createMigratedDatabase()

// AFTER
let db = try createMigratedDatabase()
// and mark the test function with throws:
@MainActor func testAddNote() async throws { ... }
```

### Wave 2 — Structural alignment

#### `examples/fuse-app/Sources/FuseApp/ContactsFeature.swift`

**Change 3a — Un-nest `Path` from `ContactsFeature` (H1)**

Move `Path` to file scope, rename to `ContactsFeaturePath`:

```swift
// BEFORE (lines 13–15, inside ContactsFeature)
@Reducer
enum Path {
    case detail(ContactDetailFeature)
}

// AFTER — at file scope, before ContactsFeature declaration
@Reducer
enum ContactsFeaturePath {
    case detail(ContactDetailFeature)
}
```

Update all references within `ContactsFeature`:
```swift
// State
var path = StackState<ContactsFeaturePath.State>()

// Action
case path(StackActionOf<ContactsFeaturePath>)

// body
.forEach(\.path, action: \.path) { ContactsFeaturePath.body }
```

Update the view's `destination:` closure:
```swift
// was: switch store.case { case let .detail(s): ... }
// remains the same pattern, but the type is now ContactsFeaturePath
```

Update the `Equatable` extension at the bottom:
```swift
// BEFORE
extension ContactsFeature.Path.State: Equatable {}

// AFTER
extension ContactsFeaturePath.State: Equatable {}
```

Update integration tests in `FuseAppIntegrationTests.swift`:
```swift
// BEFORE line 201
$0.path.append(.detail(ContactDetailFeature.State(contact: contact)))

// AFTER — same: .detail(...) still works because the enum case name is unchanged
$0.path.append(ContactsFeaturePath.State.detail(ContactDetailFeature.State(contact: contact)))
// OR if StackState infers the type: unchanged syntax works fine
```

**Change 3b — Fix `state.path.popLast()` → `state.path.remove(id:)` or child dismiss (H13)**

```swift
// BEFORE (line 48)
case .path(.element(_, .detail(.delegate(.deleteContact(let id))))):
    state.contacts.remove(id: id)
    _ = state.path.popLast()
    return .none

// AFTER — option A: remove by id (preferred when we know which element to remove)
case .path(.element(let elementID, .detail(.delegate(.deleteContact(let contactID))))):
    state.contacts.remove(id: contactID)
    state.path.remove(id: elementID)
    return .none

// AFTER — option B: let child call @Dependency(\.dismiss) (preferred TCA idiom)
// Add to ContactDetailFeature body: when deleteContact delegate fires, child calls dismiss()
// Parent only handles the delegate:
case .path(.element(_, .detail(.delegate(.deleteContact(let id))))):
    state.contacts.remove(id: id)
    return .none
// (stack item is removed automatically by the child's dismiss())
```

Use option A (remove by id) since we cannot add dismiss to path-pushed children without further refactor, and the path element ID is available in the pattern match.

**Change 3c — Fix `state.destination = nil` bypasses effect cancellation (M12)**

```swift
// BEFORE (line 56 in ContactsFeature)
case .destination(.presented(.addContact(.delegate(.saveContact(let contact))))):
    state.contacts.append(contact)
    state.destination = nil   // <-- problematic
    return .none

// AFTER — add @Dependency(\.dismiss) to AddContactFeature and call it after delegate
// AddContactFeature.saveButtonTapped:
case .saveButtonTapped:
    let contact = Contact(id: uuid(), name: state.name, email: state.email)
    return .run { send in
        await send(.delegate(.saveContact(contact)))
        await dismiss()   // child dismisses itself
    }

// Then in ContactsFeature, remove the manual nil:
case .destination(.presented(.addContact(.delegate(.saveContact(let contact))))):
    state.contacts.append(contact)
    // NO state.destination = nil — child's dismiss() handles it
    return .none
```

Similarly for `ContactDetailFeature` line 165 (`state.destination = nil` after edit save):
```swift
// BEFORE
case .destination(.presented(.editSheet(.delegate(.save(let contact))))):
    state.contact = contact
    state.destination = nil
    return .none

// AFTER — EditContactFeature already has @Dependency(\.dismiss); saveButtonTapped
// should call dismiss after sending the delegate.
// In EditContactFeature:
case .saveButtonTapped:
    return .run { [contact = state.contact] send in
        await send(.delegate(.save(contact)))
        await dismiss()
    }
// In ContactDetailFeature — remove nil assignment:
case .destination(.presented(.editSheet(.delegate(.save(let contact))))):
    state.contact = contact
    return .none
```

#### `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift`

**Change 4a — Remove bare `CombineReducers` from `Combined` reducer (H2)**

```swift
// BEFORE (lines 134–151)
@Reducer
struct Combined {
    struct State: Equatable {
        var count = 0
        var log: [String] = []
    }
    enum Action { case increment }
    var body: some ReducerOf<Self> {
        CombineReducers {
            Reduce { state, action in
                switch action {
                case .increment: state.count += 1; return .none
                }
            }
            Reduce { state, action in
                switch action {
                case .increment: state.log.append("logged"); return .none
                }
            }
        }
    }
}

// AFTER — inline into single Reduce
@Reducer
struct Combined {
    struct State: Equatable {
        var count = 0
        var log: [String] = []
    }
    enum Action { case increment }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.count += 1
                state.log.append("logged")
                return .none
            }
        }
    }
}
```

The test `testCombineReducers` must continue to pass — the observable behaviour (both `count` and `log` updated on `.increment`) is preserved.

#### `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift`

**Change 5a — Un-nest `Path` from `StackFeature` (H1)**

```swift
// BEFORE (lines 16–18, inside StackFeature)
@Reducer
enum Path {
    case detail(DetailRow)
}

// AFTER — file scope before StackFeature
@Reducer
enum StackFeaturePath {
    case detail(DetailRow)
}
```

Update all references: `StackState<StackFeaturePath.State>`, `StackActionOf<StackFeaturePath>`, `.forEach(\.path, action: \.path) { StackFeaturePath.body }`.

#### `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift`

**Change 6a — Un-nest `Path` from `AppFeature` (H1)**

Note: This test file defines its own local `AppFeature` (different from the fuse-app `AppFeature`). Rename the path enum to avoid ambiguity:

```swift
// BEFORE (lines 18–20, inside AppFeature in NavigationStackTests.swift)
@Reducer
enum Path {
    case detail(DetailFeature)
}

// AFTER
@Reducer
enum NavigationStackTestsPath {
    case detail(DetailFeature)
}
```

Update all references in the file: `StackState<NavigationStackTestsPath.State>`, `StackActionOf<NavigationStackTestsPath>`.

#### `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`

**Change 7a — Action naming: `onAppear` → `viewAppeared`, `addNoteTapped` → `addButtonTapped` (LOW)**

```swift
// BEFORE
enum Action {
    case onAppear
    case addNoteTapped
    ...
}

// AFTER
enum Action {
    case viewAppeared
    case addButtonTapped
    ...
}
```

Update reducer body and view call sites:
- `DatabaseView` line 205: `.task { store.send(.viewAppeared) }`
- `DatabaseView` line 200: `store.send(.addButtonTapped)`
- Integration tests: `store.send(.addButtonTapped)`, `await store.receive(\.noteAdded)`

**Change 7b — Add error handling to Effect.run closures (M15)**

```swift
// BEFORE — onAppear effect (lines 73–83)
return .run { send in
    let notes = try await database.read { db in
        try Note.all.order { $0.createdAt.desc() }.fetchAll(db)
    }
    ...
}

// AFTER
return .run { send in
    let notes = try await database.read { db in
        try Note.all.order { $0.createdAt.desc() }.fetchAll(db)
    }
    let count = try await database.read { db in
        try Note.all.fetchCount(db)
    }
    await send(.notesLoaded(notes))
    await send(.noteCountLoaded(count))
} catch: { error, send in
    reportIssue(error)
}
```

Apply the same `catch:` block to `addButtonTapped` and `deleteNote` effects.

#### `examples/fuse-app/Sources/FuseApp/SettingsFeature.swift`

**Change 8a — Action naming: `onAppear` → `viewAppeared` (LOW)**

```swift
// BEFORE line 26
case onAppear

// AFTER
case viewAppeared
```

Update view: line 115 `.task { store.send(.viewAppeared) }`.

#### `examples/fuse-library/Tests/TCATests/DependencyTests.swift`

**Change 9a — `static let testValue` → `static var testValue` on `NumberClient` (H9)**

```swift
// BEFORE (line 504)
static let testValue = NumberClient()

// AFTER
static var testValue: Self { Self() }
```

#### `examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift`

**Change 10a — Replace Boolean sheet state with optional state (M11)**

```swift
// BEFORE
@Reducer
struct SheetToggleFeature {
    @ObservableState
    struct State: Equatable {
        var showSheet = false
        var sheetCount = 0
    }
    enum Action {
        case toggleSheet
        case incrementInSheet
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleSheet:
                state.showSheet.toggle()
                return .none
            case .incrementInSheet:
                state.sheetCount += 1
                return .none
            }
        }
    }
}

// AFTER
@Reducer
struct SheetContent {
    @ObservableState
    struct State: Equatable {
        var count = 0
    }
    enum Action {
        case incrementButtonTapped
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .incrementButtonTapped:
                state.count += 1
                return .none
            }
        }
    }
}

@Reducer
struct SheetToggleFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var sheet: SheetContent.State?
    }
    enum Action {
        case sheet(PresentationAction<SheetContent.Action>)
        case showSheetButtonTapped
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showSheetButtonTapped:
                state.sheet = SheetContent.State()
                return .none
            case .sheet:
                return .none
            }
        }
        .ifLet(\.$sheet, action: \.sheet) {
            SheetContent()
        }
    }
}
```

Update tests accordingly: `testSheetIsPresentedToggle`, `testSheetContentInteraction`.

---

## Interaction with Other Skills

### pfw-case-paths

- **H11 / @CasePathable synthesis:** `@Reducer` on a struct synthesises `@CasePathable` on `Action`. The fuse-app features are all `@Reducer struct`, so `@CasePathable` IS synthesised. No source change needed for the outer `Action` types. The explicit `@CasePathable` attribute on nested sub-enums (`Delegate`, `Alert`, `ConfirmationDialog`) is correct and must be kept.
- **M3 (if case → .is()):** Tests using `if case let .detail(state) = ...` should become `path.is(\.detail)` and `path[case: \.detail]`. This is a case-paths change that depends on `@CasePathable` being present. After TCA changes confirm the enums have synthesis, implement the `pfw-case-paths` M3 fixes.
- **Ordering:** TCA structural changes (Path un-nesting, Action changes) must land first. Then case-paths API changes can be applied as a second pass.

### pfw-swift-navigation

- **H13 (popLast):** The fix described above (`state.path.remove(id:)`) aligns directly with the `pfw-swift-navigation` canonical pattern. This is a TCA + SwiftNavigation joint fix.
- **M11 (Boolean sheet):** The `@Presents` optional-state pattern for sheet is a TCA presentation pattern, not a SwiftNavigation-specific change. Fix it in the TCA wave.
- **M12 (manual destination nil):** The fix requires adding `@Dependency(\.dismiss)` to child features (`AddContactFeature`, `EditContactFeature`). Both already have `@Dependency(\.dismiss) var dismiss` declared but do not call `dismiss()` after sending the delegate. The fix is in the child's `saveButtonTapped` case.
- **M13 (Android NavigationStack missing):** This is a SwiftNavigation + Skip-specific issue. It does not affect TCA logic. Defer to `pfw-swift-navigation` wave.

### pfw-testing

- **H3 (Action: Equatable):** All test reducers are currently clean. No changes needed.
- **H10 (@Suite pattern):** Requires migrating `XCTestCase` classes to Swift Testing `@Suite`. This is a large mechanical change (64 findings across the testing skill). Do NOT mix with TCA structural changes. TCA wave first, then testing modernisation in a dedicated wave.
- **M4 (XCTAssertEqual → expectNoDifference):** Can be done in parallel with H10 migration, but should happen after TCA fixes so the test expectations are stable.
- **M8 (.dependencies trait):** Requires database infrastructure changes (pfw-sqlite-data skill). Defer until database wave.

### pfw-dependencies

- **H9 (static let → static var):** Only `NumberClient.testValue` in DependencyTests remains. SharedModels is clean.
- **M6 (UUID/Date defaults):** Removing defaults from `Todo` and `Contact` inits is a TCA + Dependencies joint fix. The dependencies skill requires the reducer to supply values via `@Dependency`; the TCA skill requires the model not to embed uncontrolled randomness. Fix in TCA wave.

### pfw-sharing

- **H12 (IdentifiedArrayOf):** The `@Shared(.fileStorage)` key type change from `[Todo]` to `IdentifiedArrayOf<Todo>` is a Sharing skill change that also requires updating `SettingsFeature.State`. This is safe to include in TCA wave since it does not touch reducer logic.

### pfw-sqlite-data / pfw-structured-queries

- **H6 (import GRDB):** Remove from integration test file. Simple one-line change.
- **M7 (#sql macro), M8 (.dependencies trait), M9 (defaultDatabase), M10 (bootstrapDatabase location):** These are database-layer changes. Do NOT mix with TCA wave.

### pfw-issue-reporting

- **H8 (try! in FuseApp.swift):** The current `FuseApp.swift` already uses `reportIssue(error)` inside a `do/catch` — H8 is already fixed in the current file.
- **M15 (unhandled errors in Effect.run):** Fix in TCA wave as part of DatabaseFeature changes.

---

## Ordering Dependencies

### Strict prerequisite chain

```
1. SharedModels.swift changes (M6 model defaults, H9 static var, H12 IdentifiedArrayOf)
        |
        v
2. All call-site updates for removed Todo/Contact init defaults
   (FuseAppIntegrationTests.swift, any other test helpers)
        |
        v
3. ContactsFeature.swift structural changes (H1 Path un-nesting, H13 popLast, M12 destination nil)
        |
        v
4. DatabaseFeature.swift changes (naming, M15 error handling)
        |
        v
5. SettingsFeature.swift changes (naming)
        |
        v
6. FuseAppIntegrationTests.swift cleanup (H6 import GRDB, M4 XCTAssertEqual, try!)
        |
        v
7. TCATests/StoreReducerTests.swift (H2 CombineReducers)
        |
        v
8. NavigationTests/NavigationTests.swift (H1 StackFeature Path)
        |
        v
9. NavigationTests/NavigationStackTests.swift (H1 AppFeature Path)
        |
        v
10. NavigationTests/UIPatternTests.swift (M11 Boolean sheet)
        |
        v
11. TCATests/DependencyTests.swift (H9 NumberClient static let)
```

### Can be done in parallel (no dependencies between them)

- Steps 7, 8, 9, 10, 11 are independent of each other and can be batched in a single commit after steps 1–6.
- Step 3 (ContactsFeature) and steps 4–5 (Database/Settings naming) are independent of each other.

### Must NOT be done before

- Do NOT run `pfw-testing` wave (H10 @Suite, M4 expectNoDifference) until all TCA structural changes are committed and tests pass — test migration on top of broken tests compounds failures.
- Do NOT run `pfw-sqlite-data` wave until `import GRDB` is removed (H6) and DatabaseFeature error handling (M15) is in place — the database skill changes assume a clean import surface.
- Do NOT add `@CasePathable` explicitly to top-level `Action` enums inside `@Reducer struct` types — the macro synthesises it and adding it manually may cause a compiler error about duplicate conformance.

### Validation gates

After each step, run:
```bash
cd /Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform && make test EXAMPLE=fuse-app
make test EXAMPLE=fuse-library
```

If the path un-nesting (step 3) breaks the `StackFeature` test in `NavigationTests`, check that `StackFeaturePath.body` is correctly referenced in `.forEach`.

After step 10 (SheetToggleFeature rewrite), verify `UIPatternTests` still compiles and all 8 UI pattern tests pass.

---

## Summary Table

| Finding | File | Change type | Wave |
|---------|------|-------------|------|
| C1 — .toggleCategory | FuseAppIntegrationTests.swift | ALREADY FIXED | — |
| H1 — Path nested | ContactsFeature.swift:13 | Move Path to file scope as ContactsFeaturePath | 2 |
| H1 — Path nested | NavigationTests.swift:16 | Move Path to file scope as StackFeaturePath | 2 |
| H1 — Path nested | NavigationStackTests.swift:18 | Move Path to file scope as NavigationStackTestsPath | 2 |
| H2 — bare CombineReducers | StoreReducerTests.swift:134 | Inline into single Reduce | 2 |
| H3 — Action: Equatable | (all files) | ALREADY CLEAN | — |
| H6 — import GRDB | FuseAppIntegrationTests.swift:2 | Remove import | 1 |
| H8 — try! in FuseApp | FuseApp.swift:24 | ALREADY FIXED | — |
| H9 — static let | DependencyTests.swift:504 | Change to static var computed | 2 |
| H11 — @CasePathable on Action | fuse-app features | Synthesised by @Reducer; no source change | — |
| H12 — [Todo] in fileStorage | SharedModels.swift:64 | Change to IdentifiedArrayOf<Todo> | 1 |
| H13 — popLast | ContactsFeature.swift:48 | Change to path.remove(id:) | 2 |
| LOW — onAppear naming | DatabaseFeature.swift:58, SettingsFeature.swift:26 | Rename to viewAppeared | 2 |
| LOW — addNoteTapped | DatabaseFeature.swift:57 | Rename to addButtonTapped | 2 |
| M6 — UUID/Date defaults | SharedModels.swift:16,31 | Remove init defaults | 1 |
| M11 — Boolean sheet | UIPatternTests.swift:115 | Replace with @Presents optional | 2 |
| M12 — destination = nil | ContactsFeature.swift:56, ContactDetailFeature.swift:165 | Use child dismiss() | 2 |
| M15 — unhandled errors | DatabaseFeature.swift:73,87,105 | Add catch: blocks | 2 |
