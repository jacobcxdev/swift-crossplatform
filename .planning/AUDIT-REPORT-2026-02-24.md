# Comprehensive Fuse-App Audit Report

**Date:** 2026-02-24
**Scope:** `examples/fuse-app/` — all 8 source files, 2 test files, Package.swift
**Skills applied:** PFW (TCA, Sharing, Dependencies, Navigation, Perception, SQLiteData, Testing, CustomDump, IdentifiedCollections, IssueReporting, SPM) + Axiom (SwiftUI Architecture, SwiftUI Performance, Navigation, Concurrency, Testing, Accessibility, Energy, Storage, Security)
**Workstreams:** 6 parallel agents (TCA Architecture, Data Layer, Navigation, Testing, Concurrency/Security, Accessibility)

## Summary

| Severity | Count |
|----------|-------|
| HIGH     | 7     |
| MEDIUM   | 16    |
| LOW      | 15    |
| **Total**| **38**|

## Previous Audit (2026-02-23) Status

| Finding | Status | Notes |
|---------|--------|-------|
| H6: `import GRDB` | FIXED | Uses `import SQLiteData` |
| H7: No @FetchAll/@FetchOne | PARTIAL | `DatabaseObservingView` exists but is unreferenced dead code (see M-5) |
| H8: `try!` in FuseApp.swift | FIXED | Uses `do/catch` with `reportIssue(error)` |
| H9: `static let` for DependencyKey | FIXED | Uses computed `static var` |
| H11: Missing @CasePathable | FIXED | All Action enums have `@CasePathable` |
| H12: savedTodos wrong type | FIXED | Uses `IdentifiedArrayOf<Todo>` |
| H13: Manual path.popLast() | FIXED | Uses `state.path.pop(from: stackID)` |

---

## HIGH Severity (7)

### H-1: `_printChanges()` not `#if DEBUG` guarded
- **File:** `FuseApp.swift:20`
- **Skills:** pfw-tca, axiom-energy, axiom-security
- **Description:** `._printChanges()` is applied unconditionally. In release builds this serialises and logs every state change (all 5 tabs), causing performance/energy drain and information disclosure (state values in os_log/logcat).
- **Fix:**
```swift
let store = Store(initialState: AppFeature.State()) {
    AppFeature()
    #if DEBUG
        ._printChanges()
    #endif
}
```

### H-2: `@Shared(.appearance)` in AppView bypasses TCA state
- **File:** `AppFeature.swift:65`
- **Skills:** pfw-sharing, pfw-tca
- **Description:** `AppView` declares `@Shared(.appearance) var appearance` and reads it directly in the view body. This bypasses TCA's state management — the Store has no visibility into this read, and the view re-renders outside of reducer actions.
- **Fix:** Add `@Shared(.appearance) var appearance: String` to `AppFeature.State` and read `store.appearance` in the view. Remove the standalone `@Shared` from `AppView`. Alternatively read `store.settings.appearance` since `SettingsFeature.State` already holds it.

### H-3: `savedTodos` is never written — always shows 0
- **File:** `TodosFeature.swift:11`, `SettingsFeature.swift:16,84`
- **Skills:** pfw-sharing
- **Description:** `TodosFeature.State.todos` is a local `IdentifiedArrayOf<Todo>` with no connection to `@Shared(.savedTodos)`. Settings displays `savedTodos.count` which is permanently 0. This is a visible functional bug.
- **Fix:** Either (A) add `@Shared(.savedTodos) var savedTodos` to `TodosFeature.State` and sync on every mutation with `state.$savedTodos.withLock { $0 = state.todos }`, or (B) remove the savedTodos display from SettingsView.

### H-4: `applicationSupportDirectory` not created before use (iOS)
- **File:** `SharedModels.swift:80`, `DatabaseFeature.swift:11`
- **Skills:** axiom-storage
- **Description:** iOS path uses bare `URL.applicationSupportDirectory` without creating the directory. The Android path correctly uses `FileManager.default.url(for:in:appropriateFor:create: true)`. On a fresh iOS install the directory may not exist, causing crashes or silent data loss.
- **Fix:** Use `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)` on iOS as well.

### H-5: Delete button no accessibility label (Todos)
- **File:** `TodosFeature.swift:164-170`
- **Skills:** axiom-accessibility
- **Description:** Trash icon button has no `.accessibilityLabel`. VoiceOver cannot identify which todo is being deleted.
- **Fix:** `.accessibilityLabel("Delete \(todo.title)")` + `.accessibilityHint("Presents a confirmation before deleting.")`

### H-6: Delete button no accessibility label (DatabaseView)
- **File:** `DatabaseFeature.swift:187-193`
- **Skills:** axiom-accessibility
- **Description:** Same pattern. Worse: deletion is immediate with no confirmation dialog.
- **Fix:** `.accessibilityLabel("Delete \(note.title)")` + `.accessibilityHint("Immediately deletes this note.")`

### H-7: Delete button no accessibility label (DatabaseObservingView)
- **File:** `DatabaseFeature.swift:258-264`
- **Skills:** axiom-accessibility
- **Description:** Identical to H-6 in the dead-code observing view.
- **Fix:** Same as H-6 (applies if view is kept).

---

## MEDIUM Severity (16)

### M-1: `filteredNotes` computed on View, not State
- **File:** `DatabaseFeature.swift:210-215`
- **Skills:** pfw-tca, axiom-swiftui-performance
- **Description:** `filteredNotes` is a computed property on the View struct, not on TCA State. Evaluated on every body recomputation. TCA observation tracking cannot skip body evaluation when only unrelated state changes. Compare with `TodosFeature.State.filteredTodos` which correctly lives on State.
- **Fix:** Move to `DatabaseFeature.State`:
```swift
var filteredNotes: IdentifiedArrayOf<Note> {
    if selectedCategory == "all" { return notes }
    return notes.filter { $0.category == selectedCategory }
}
```

### M-2: Flat `@Presents` in TodosFeature instead of Destination enum
- **File:** `TodosFeature.swift:13-14, 136-137`
- **Skills:** pfw-swift-navigation, pfw-tca
- **Description:** Two separate `@Presents` properties (`alert`, `confirmationDialog`) rather than a unified `@Reducer enum Destination`. Both can technically be non-nil simultaneously. ContactDetailFeature correctly uses a Destination enum.
- **Fix:** Introduce `@Reducer enum Destination` with `alert` and `confirmationDialog` cases. Use single `@Presents var destination`.

### M-3: `todoToDelete` side-channel state
- **File:** `TodosFeature.swift:15, 99-107`
- **Skills:** pfw-tca
- **Description:** `todoToDelete: Todo.ID?` is stored separately instead of encoding the ID into `AlertState`'s action type (e.g. `case confirmDeletion(Todo.ID)`). This creates temporal coupling between `deleteTapped` and alert confirmation.
- **Fix:** Change `Action.Alert` to `case confirmDeletion(Todo.ID)`, pass ID at call site, remove `todoToDelete` from State.

### M-4: Unused `@Dependency(\.dismiss)` in ContactDetailFeature
- **File:** `ContactsFeature.swift:121`
- **Skills:** pfw-dependencies
- **Description:** Declared but never called. Parent handles dismissal via `state.path.pop(from:)`. Dead dependency injection misleads readers.
- **Fix:** Remove `@Dependency(\.dismiss) var dismiss`.

### M-5: `DatabaseObservingView` is dead code
- **File:** `DatabaseFeature.swift:224-279`
- **Skills:** pfw-sqlite-data
- **Description:** Defined but never referenced anywhere. Adds maintenance burden.
- **Fix:** Remove, or add a comment explaining it's an intentional reference example.

### M-6: `debugInfo` is dead `@ObservationStateIgnored` field
- **File:** `SettingsFeature.swift:18`
- **Skills:** pfw-perception
- **Description:** Never read or written anywhere. Wasted memory.
- **Fix:** Delete line.

### M-7: `viewAppeared` action is a no-op in SettingsFeature
- **File:** `SettingsFeature.swift:27, 55-56, 103`
- **Skills:** pfw-tca
- **Description:** Declared, handled as `return .none`, sent on `.task`. Does nothing.
- **Fix:** Remove from Action enum, reducer, and view.

### M-8: `sessionActionCount` naming misleads — only incremented in Settings
- **File:** `SharedModels.swift:85`, `SettingsFeature.swift:35,40,45,52`
- **Skills:** pfw-sharing
- **Description:** Name implies app-wide scope but only Settings increments it.
- **Fix:** Rename to `settingsActionCount` or make it truly app-wide.

### M-9: `Note.createdAt` is Double, not Date
- **File:** `SharedModels.swift:46`
- **Skills:** pfw-sqlite-data
- **Description:** Requires manual `Date(timeIntervalSince1970:)` conversion in views. SQLiteData supports Date natively with REAL affinity.
- **Fix:** Change to `var createdAt: Date = Date(timeIntervalSince1970: 0)`. Remove manual conversions.

### M-10: `import CustomDump` unused — no `expectNoDifference` calls
- **File:** `FuseAppIntegrationTests.swift:3`
- **Skills:** pfw-custom-dump
- **Description:** Imported but never used. PFW recommends `expectNoDifference` for richer diffs.
- **Fix:** Remove import or replace `#expect(a == b)` with `expectNoDifference(a, b)`.

### M-11: Sort actions have zero test coverage
- **File:** `FuseAppIntegrationTests.swift:154`
- **Skills:** pfw-testing
- **Description:** `sortConfirmationDialog` only checks dialog appears. The 3 sort cases (`sortByTitle/sortByDate/sortByStatus`) that mutate todos are never tested.
- **Fix:** Add 3 tests with pre-populated unsorted todos, asserting correct order after each sort action.

### M-12: Test migration SQL duplicates production SQL
- **File:** `FuseAppIntegrationTests.swift:326`
- **Skills:** pfw-testing
- **Description:** `createMigratedDatabase()` copies DDL verbatim from `bootstrapDatabase()`. Schema drift causes confusing failures.
- **Fix:** Extract migration to shared function or call `bootstrapDatabase()` from tests.

### M-13: No standalone tests for AddContactFeature
- **File:** Tests (missing)
- **Skills:** pfw-testing
- **Description:** Binding changes, cancel dismiss, and save-with-empty-name are untested. The reducer allows saving an empty-name contact.
- **Fix:** Add `AddContactFeatureTests` with binding, cancel, and empty-name tests.

### M-14: TodoRowView toggle lacks accessibility label/trait
- **File:** `TodosFeature.swift:205-209`
- **Skills:** axiom-accessibility
- **Description:** Toggle button renders only SF Symbol with no label or `.accessibilityAddTraits(.isToggle)`.
- **Fix:** `.accessibilityLabel(todo.isComplete ? "Mark \(todo.title) incomplete" : "Mark \(todo.title) complete")` + `.accessibilityAddTraits(.isToggle)`

### M-15: Counter +/- buttons lack explicit accessibility labels
- **File:** `CounterFeature.swift:104, 109`
- **Skills:** axiom-accessibility
- **Description:** `Button("-")` and `Button("+")` — VoiceOver reads "hyphen"/"plus sign" inconsistently.
- **Fix:** `.accessibilityLabel("Decrement")` and `.accessibilityLabel("Increment")`

### M-16: HStack label/value rows not grouped for VoiceOver
- **File:** `ContactsFeature.swift:327-328`, `SettingsFeature.swift:84-85`, `CounterFeature.swift:130-135`
- **Skills:** axiom-accessibility
- **Description:** `HStack { Text("Label"); Spacer(); Text(value) }` produces two VoiceOver focus targets.
- **Fix:** `.accessibilityElement(children: .combine)` on each HStack.

---

## LOW Severity (15)

### L-1: `isLoading` stuck forever on database error
- **File:** `DatabaseFeature.swift:65-80`
- **Skills:** pfw-tca
- **Description:** On `.viewAppeared` failure, `isLoading` stays true. Infinite spinner.
- **Fix:** Send a failure action or `send(.notesLoaded([]))` in catch block.

### L-2: Reducer ordering comment needed
- **File:** `ContactsFeature.swift:49-52`
- **Skills:** pfw-tca
- **Description:** Parent pops path before `.forEach` runs — subtle ordering. Worth a comment.
- **Fix:** Add comment explaining intentional ordering.

### L-3: Manual Equatable on macro-generated types may be redundant
- **File:** `ContactsFeature.swift:404-406`
- **Skills:** pfw-tca
- **Description:** `extension ... : Equatable {}` on @Reducer enum generated State types. May be redundant if macro synthesises them.
- **Fix:** Test removal; if build passes, delete.

### L-4: NumberFactClient liveValue is hardcoded stub
- **File:** `SharedModels.swift:97`
- **Skills:** axiom-networking
- **Description:** Returns `"The number \(number) is interesting!"` — no actual API call. Fine for demo but naming implies network.
- **Fix:** Add doc comment clarifying stub.

### L-5: `DependenciesTestSupport` unused in Package.swift
- **File:** `Package.swift:42`
- **Skills:** pfw-spm
- **Description:** Listed as test dependency but never imported.
- **Fix:** Remove from dependencies.

### L-6: No standalone tests for EditContactFeature
- **File:** Tests (missing)
- **Skills:** pfw-testing
- **Description:** Binding and cancel paths untested in isolation.
- **Fix:** Add `EditContactFeatureTests`.

### L-7: TabBindingTests use live Store instead of TestStore
- **File:** `TabBindingTests.swift:17`
- **Skills:** pfw-testing
- **Description:** Synchronous assertions fragile if `tabSelected` gains effects.
- **Fix:** Convert to TestStore pattern.

### L-8: `deleteConfirmation` test doesn't assert contact ID
- **File:** `FuseAppIntegrationTests.swift:298`
- **Skills:** pfw-testing
- **Description:** `await store.receive(\.delegate.deleteContact)` ignores the associated value.
- **Fix:** Assert the received ID matches `contact.id`.

### L-9: No snapshot tests
- **File:** Tests (missing)
- **Skills:** pfw-snapshot-testing
- **Description:** UI showcase app with no visual regression tests.
- **Fix:** Add snapshot tests for key views.

### L-10: `eraseDatabaseOnSchemaChange` reachable outside simulator
- **File:** `DatabaseFeature.swift:14-16`
- **Skills:** axiom-storage
- **Description:** `#if DEBUG` doesn't exclude TestFlight builds. Could silently drop data.
- **Fix:** Gate with `#if DEBUG && targetEnvironment(simulator)`.

### L-11: No email validation in AddContact/EditContact
- **File:** `ContactsFeature.swift:253-256, 394-397`
- **Skills:** axiom-security
- **Description:** Save button only checks name.isEmpty. Malformed emails accepted.
- **Fix:** Add lightweight email validation.

### L-12: `viewAppeared` re-seeds contacts after all deleted
- **File:** `ContactsFeature.swift:64-72`
- **Skills:** axiom-concurrency
- **Description:** `onAppear` fires on re-appear after popping stack. Deleting all contacts then returning re-seeds them.
- **Fix:** Use `.task` (fires once) or a `hasSeeded: Bool` flag.

### L-13: Store created as `let` property, not `@State`
- **File:** `FuseApp.swift:18-21`
- **Skills:** axiom-swiftui-architecture
- **Description:** SwiftUI may recreate struct views; `let store` allocates a new Store each time. `init` runs `prepareDependencies` + `bootstrapDatabase` on main thread.
- **Fix:** Use `@State private var store = Store(...)` and move bootstrap to `.task`.

### L-14: Contact row decorative icon not hidden from VoiceOver
- **File:** `ContactsFeature.swift:294`
- **Skills:** axiom-accessibility
- **Description:** `person.circle.fill` image included in VoiceOver synthesis.
- **Fix:** `.accessibilityHidden(true)` on the Image.

### L-15: "Reset to Defaults" button lacks accessibilityHint
- **File:** `SettingsFeature.swift:89-91`
- **Skills:** axiom-accessibility
- **Description:** Destructive action with no pre-activation warning for VoiceOver users.
- **Fix:** `.accessibilityHint("Resets username, appearance, and notification preferences.")"`

---

## Coverage Matrix

| Feature | @Reducer | @ObservableState | @CasePathable | ViewAction | Tests | A11y |
|---------|----------|------------------|---------------|------------|-------|------|
| AppFeature | OK | OK | OK | N/A | OK | M-16 |
| CounterFeature | OK | OK | OK | OK | OK | M-15 |
| TodosFeature | OK | OK | OK | No (M-2) | Partial (M-11) | H-5, M-14 |
| ContactsFeature | OK | OK | OK | No | Partial (M-13) | M-16, L-14 |
| DatabaseFeature | OK | OK | OK | No | OK | H-6, H-7 |
| SettingsFeature | OK | OK | OK | No | OK | L-15, M-16 |

## Recommended Fix Priority

1. **H-1** `_printChanges()` guard — 1 line change, high impact
2. **H-3** savedTodos sync — functional bug visible to users
3. **H-4** applicationSupportDirectory creation — potential crash
4. **H-2** @Shared in view — TCA pattern violation
5. **H-5/H-6** Accessibility labels — VoiceOver unusable for delete actions
6. **M-1 through M-3** TCA pattern fixes — correctness guarantees
7. **M-6/M-7** Dead code removal — cleanup
8. **M-10 through M-13** Test improvements — coverage gaps
9. Remaining LOW findings
