# PFW Sharing Skill — Canonical Patterns & Migration Guide

**Date:** 2026-02-23
**Phase:** 08 — PFW Skill Alignment
**Skills Referenced:** pfw-sharing, pfw-identified-collections, pfw-composable-architecture

---

## Canonical Patterns

This section documents the authoritative patterns from the `/pfw-sharing` skill.

### Pattern 1: FileStorage with Codable Values

**Use `@Shared(.fileStorage(url))` for persisting structured data:**

```swift
extension SharedKey where Self == FileStorageKey<Settings>.Default {
  static var appSettings: Self {
    Self[.fileStorage(.applicationSupportDirectory.appending(component: "settings.json")), default: Settings()]
  }
}

@Shared(.appSettings) var settings: Settings
```

**Rules:**
- Value type MUST conform to `Codable`
- Use `URL.applicationSupportDirectory` (not bundle/documents)
- Append component name matches the storage key semantically
- Default value is required and becomes the initial on-disk value

### Pattern 2: Observations Async Sequence (Preferred over Combine)

**Use `Observations { ... }` for reactive updates:**

```swift
@Shared var currentUser: User?

// Create async sequence
let isLoggedInAsyncSequence = Observations { currentUser != nil }

// Consume in task/loop
for await isLoggedIn in isLoggedInAsyncSequence {
  print("User logged in: \(isLoggedIn)")
}
```

**Key benefits:**
- Prefer Observation framework over Combine
- Async/await integration (no subscriptions, no cancellation boilerplate)
- Cleaner syntax for mutations: `$shared.wrappedValue = newValue`

### Pattern 3: Shared Optional Unwrapping

**Unwrap optional `@Shared` with type-safe access:**

```swift
@Shared var currentUser: User?

if let unwrappedSharedUser = Shared($currentUser) {
  // unwrappedSharedUser is Shared<User>, not optional
  print(unwrappedSharedUser.wrappedValue.name)
}
```

### Pattern 4: Shared Child Projection (Key-Path)

**Transform parent @Shared to child @Shared via key-path:**

```swift
@Shared var settings: Settings

let isReduceMotion: Shared<Bool> = $settings.isReduceMotionEnabled
$settings.isReduceMotionEnabled.wrappedValue = true  // Updates both child & parent
```

### Pattern 5: @ObservationIgnored + @Shared in Observable Models

**Mark `@Shared` with `@ObservationIgnored` to avoid double-observation:**

```swift
@Observable
class MyModel {
  @ObservationIgnored
  @Shared(.appStorage("theme")) var theme = "light"
}
```

**Rationale:** `@Shared` manages its own observation; `@Observable` registration would create redundant overhead.

### Pattern 6: AppStorage for User Preferences

**Use `@Shared(.appStorage(key))` for lightweight key-value pairs:**

```swift
extension SharedKey where Self == AppStorageKey<String>.Default {
  static var userName: Self { Self[.appStorage("userName"), default: "Guest"] }
}

@Shared(.userName) var userName: String
```

**Rules:**
- Keys must NOT contain `.` or `@` (invalid UserDefaults keys)
- Suitable for Bool, String, Int, URL, Data
- For complex types → use `fileStorage` instead

---

## Current State

### File 1: `SharedModels.swift` (Lines 64–68)

**Current:** `[Todo]` array with fileStorage

```swift
extension SharedKey where Self == FileStorageKey<[Todo]>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(URL.applicationSupportDirectory.appending(component: "todos.json")), default: []]
    }
}
```

**Problem (H12):** Arrays of Identifiable models should use `IdentifiedArrayOf<Todo>` for:
- O(1) lookups by `id` instead of O(n) linear search
- Guaranteed uniqueness by ID
- Automatic deduplication on append
- Better TCA reducer pattern for `.forEach` modifier

**Current Usage in State:**
- `SettingsFeature.swift:15` — `@Shared(.savedTodos) var savedTodos: [Todo] = []`
- Accessed as plain array; no ID-based operations

### File 2: `SettingsFeature.swift` (Line 15)

**Current:** Plain array declaration and mutation

```swift
@Shared(.savedTodos) var savedTodos: [Todo] = []
```

**Consumer in Reducer (Lines 36–49):** Mutates via `withLock` but no indexed access by ID.

### File 3: `SharedObservationTests.swift` (Lines 1–166)

**Current:** All tests use Combine `.publisher` + `.sink` pattern

Examples:
- Line 23: `$count.publisher.dropFirst().sink { ... }`
- Line 45: `$count.publisher.dropFirst().sink { ... }`
- Line 103: `$count.publisher.dropFirst().prefix(3).sink(...)`

**Problem (M14):** Preference stated in audit: "Prefer Observations framework over Combine"

**Pattern used:**
```swift
let cancellable = $count.publisher
    .dropFirst()
    .sink { value in
        received.append(value)
        expectation.fulfill()
    }
```

**Missing:** No tests for `Observations { ... }` async sequence, which is the canonical modern pattern.

### File 4: `TodosFeature.swift` (Lines 11, 17)

**Current State:** Uses `IdentifiedArrayOf<Todo>` correctly in reducer state

```swift
@ObservableState
struct State: Equatable {
    var todos: IdentifiedArrayOf<Todo> = []

    var filteredTodos: IdentifiedArrayOf<Todo> {
        todos.filter { !$0.isComplete || $0.isComplete }
    }
}
```

**Good:** This is the canonical pattern. **NOT BROKEN.**

### File 5: `ContactsFeature.swift` (Line 20)

**Current State:** Uses `IdentifiedArrayOf<Contact>` correctly

```swift
@ObservableState
struct State: Equatable {
    var contacts: IdentifiedArrayOf<Contact> = []
    // ...
}
```

**Good:** This is also correct. **NOT BROKEN.**

---

## Required Changes

### Change 1: Migrate `[Todo]` → `IdentifiedArrayOf<Todo>` in FileStorage Key

**File:** `/examples/fuse-app/Sources/FuseApp/SharedModels.swift:64–68`

**Action:** Replace array type with `IdentifiedArrayOf<Todo>`

```swift
extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(URL.applicationSupportDirectory.appending(component: "todos.json")), default: []]
    }
}
```

**Reason:** Identifiable collections with fileStorage MUST use `IdentifiedArrayOf` for O(1) ID-based access and guaranteed uniqueness.

**Impact:** No downstream breakage — `IdentifiedArrayOf<Todo>` is collection-compatible with array APIs (`.count`, `.append()`, `.first`, iteration).

---

### Change 2: Add @CasePathable to Action Enum (H11 — Deferred)

**File:** `SettingsFeature.swift:20`

```swift
enum Action: BindableAction, @CasePathable {
    case binding(BindingAction<State>)
    case userNameChanged(String)
    case appearanceChanged(String)
    case notificationsToggled(Bool)
    case resetButtonTapped
    case onAppear
}
```

**Reason:** Required for TCA-16 pattern `.is(\.caseName)` key-path syntax in other parts of the codebase.

**Timing:** Include in Wave 2 of fixes (after H12, before M14).

---

### Change 3: Migrate SharedObservationTests from Combine → Observations

**File:** `/examples/fuse-library/Tests/SharingTests/SharedObservationTests.swift:1–166`

**Strategy:** Replace each test's Combine `.publisher.sink` with `Observations { ... }` async sequence.

#### Example Transformation

**Before (Combine):**
```swift
@MainActor func testSharedPublisher() {
    @Shared(.inMemory("pubTest")) var count = 0
    var received: [Int] = []
    let expectation = expectation(description: "publisher emits")
    expectation.expectedFulfillmentCount = 1

    let cancellable = $count.publisher
        .dropFirst()
        .sink { value in
            received.append(value)
            expectation.fulfill()
        }

    $count.withLock { $0 = 42 }

    wait(for: [expectation], timeout: 2.0)
    XCTAssertTrue(received.contains(42))
    _ = cancellable
}
```

**After (Observations):**
```swift
@MainActor func testSharedPublisher() async {
    @Shared(.inMemory("pubTest")) var count = 0
    var received: [Int] = []

    let task = Task {
        let sequence = Observations { count }
        for await value in sequence {
            received.append(value)
            if value == 42 { break }
        }
    }

    $count.withLock { $0 = 42 }

    try? await task.value
    XCTAssertTrue(received.contains(42))
}
```

**Detailed Changes for All Tests:**

1. **testSharedPublisher** (line 17)
   - Remove Combine import
   - Convert to async test
   - Use `Observations { count }` for observation sequence
   - Replace `.sink` with `for await value in` loop
   - Remove expectation fulfillment ceremony

2. **testSharedPublisherMultipleValues** (line 39)
   - Same pattern
   - Use `.prefix(3)` or manual break condition
   - Collect values in loop

3. **testPublisherValuesAsyncSequence** (line 97)
   - Simplify: async sequence IS the native pattern
   - Remove `.publisher`, `.dropFirst()`, `.prefix(3)` adapters
   - Direct `for await` collection

4. **testPublisherAndObservationBothWork** (line 122)
   - Merge into single async loop
   - Demonstrate that Observations is the ONE pattern needed

5. **Keep synchronous tests** (lines 63–68, 81–93, 147–165)
   - `testMultipleSharedSameKeySynchronize`
   - `testConcurrentSharedMutations`
   - `testBidirectionalSync`
   - These don't require Combine; no changes needed

**Reason:** The Observations async sequence is the canonical modern pattern. Combine tests are maintenance burden without demonstrating any value Observations doesn't provide.

---

### Change 4: Add Observations Tests for Common Patterns

**File:** `/examples/fuse-library/Tests/SharingTests/SharedObservationTests.swift` — append new tests

```swift
// MARK: SHR-11 — Observations with transformation

@MainActor func testObservationsWithTransformation() async {
    @Shared(.inMemory("transform")) var count = 0
    var isEven: [Bool] = []

    let task = Task {
        let sequence = Observations { count % 2 == 0 }
        for await even in sequence.prefix(3) {
            isEven.append(even)
        }
    }

    $count.withLock { $0 = 1 }  // odd
    $count.withLock { $0 = 2 }  // even
    $count.withLock { $0 = 3 }  // odd

    try? await task.value
    XCTAssertEqual(isEven, [true, false, true])
}

// MARK: SHR-14 — Shared child observation

@MainActor func testSharedChildObservation() async {
    @Shared(.inMemory("parent")) var parent = ObsParent()
    let childShared: Shared<String> = $parent.child
    var childValues: [String] = []

    let task = Task {
        let sequence = Observations { childShared.wrappedValue }
        for await value in sequence.prefix(3) {
            childValues.append(value)
        }
    }

    childShared.wrappedValue = "updated1"
    childShared.wrappedValue = "updated2"

    try? await task.value
    XCTAssertEqual(childValues, ["initial", "updated1", "updated2"])
}
```

**Reason:** Demonstrate that Observations handles all Combine use cases + more clearly.

---

## Codable Migration

When migrating `[Todo]` → `IdentifiedArrayOf<Todo>`:

### What Stays the Same

- **FileStorage URL path:** Still `"todos.json"` on disk
- **Codable conformance:** `IdentifiedArrayOf<Todo>` is `Codable` if `Todo: Codable` ✓
- **Setter/getter API:** Both types support `.append()`, `.count`, iteration

### What Changes

#### On-Disk Format

**Before `[Todo]`:**
```json
[
  { "id": "uuid1", "title": "Task 1", ... },
  { "id": "uuid2", "title": "Task 2", ... }
]
```

**After `IdentifiedArrayOf<Todo>`:**
```json
[
  { "id": "uuid1", "title": "Task 1", ... },
  { "id": "uuid2", "title": "Task 2", ... }
]
```

**Result:** Identical on disk. `IdentifiedArrayOf` wraps an array at the JSON level; the wire format doesn't change.

#### Runtime Guarantees

| Property | `[Todo]` | `IdentifiedArrayOf<Todo>` |
|----------|----------|--------------------------|
| Duplicate IDs allowed | Yes (O(n) search) | No (duplicate breaks invariant) |
| Append performance | O(1) | O(1) |
| Lookup by ID | O(n) linear scan | O(1) hash table |
| `.forEach` modifier | ❌ Breaks | ✅ Natural |
| Ordering preserved | Yes | Yes |

#### Migration in Code

**Current (Broken Pattern):**
```swift
@Shared(.savedTodos) var savedTodos: [Todo] = []

// In view/reducer:
savedTodos.append(newTodo)  // O(n) on next lookup
let existing = savedTodos.first { $0.id == targetID }  // O(n) every time
```

**Fixed (Canonical):**
```swift
@Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []

// In view/reducer:
savedTodos.append(newTodo)  // O(1) by ID hashing
if let existing = savedTodos[id: targetID] {  // O(1)
  existing.isComplete = true
}
```

#### No Breaking Change for Consumers

```swift
// Both types support:
for todo in savedTodos { ... }  // iteration
savedTodos.count               // length
savedTodos.first               // first element
savedTodos.filter { ... }      // filtering
```

**Only improvements:**
- `savedTodos[id: uuid]` — new O(1) access
- `savedTodos.remove(id: uuid)` — new O(1) removal
- Automatic deduplication on assignment/merge

---

## Ordering Dependencies

### 1. Must Complete First (Wave 1 — Not blocking this work)

- **C1:** Fix `.toggleCategory` action in integration tests
- **H8:** Replace `try!` with `withErrorReporting`
- **H6:** Remove `import GRDB`

### 2. **H12 Shared+IdentifiedArrayOf Migration (This Phase)**

**Depends on:**
- IdentifiedCollections library (already imported in SharedModels.swift)
- FileStorage strategy (already in SharedKey extension)

**Blocks:**
- Any reducer using `forEach` on todos (already using `IdentifiedArrayOf` in TodosFeature — no change)
- Any Combine→Observations migration in observation tests (M14)

**Critical:** H12 must complete before M14, because M14 tests need to demonstrate modern patterns on the fixed state.

### 3. Must Complete After H12 (Wave 2)

- **M14:** Replace Combine publishers with Observations async sequence
- **H11:** Add `@CasePathable` to Action enums

**Reason:** M14 tests will showcase Observations on the corrected `IdentifiedArrayOf<Todo>` state.

### 4. Test Modernisation (Wave 3 — Parallel)

- H10, M4, M5, M8 — Swift Testing migration, dependency cleanup
- Can proceed in parallel with H12 + M14

---

## Implementation Checklist

- [ ] **Step 1:** Change `FileStorageKey<[Todo]>` → `FileStorageKey<IdentifiedArrayOf<Todo>>` in SharedModels.swift:64
- [ ] **Step 2:** Verify no import additions needed (IdentifiedCollections already imported)
- [ ] **Step 3:** Run `make test` to confirm no consumer breakage
- [ ] **Step 4:** (Wave 2) Remove Combine import from SharedObservationTests.swift
- [ ] **Step 5:** (Wave 2) Migrate 6 Combine tests to Observations async sequence
- [ ] **Step 6:** (Wave 2) Add 2 new Observations tests (transformation, child observation)
- [ ] **Step 7:** (Wave 2) Add `@CasePathable` to SettingsFeature.Action
- [ ] **Step 8:** Run full test suite to verify all three changes work together
- [ ] **Step 9:** Commit with message: "fix(sharing): align H12 + M14 + H11 with pfw-sharing patterns"

---

## Success Criteria

1. ✅ `@Shared(.savedTodos)` accepts `IdentifiedArrayOf<Todo>` type without warnings
2. ✅ All tests pass after H12 migration (no consumer breakage)
3. ✅ M14 tests use only `Observations { ... }` async sequence, zero Combine
4. ✅ `SettingsFeature.Action` has `@CasePathable` annotation
5. ✅ All Wave 1 audit findings (C1, H8, H6) remain fixed
6. ✅ FileStorage on-disk format unchanged (backwards compatible)

