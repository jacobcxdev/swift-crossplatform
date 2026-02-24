# PFW IdentifiedCollections Skill Audit

**Phase:** 08 — PFW Skill Alignment
**Audit Date:** 2026-02-23
**Skill Source:** `/pfw-identified-collections` (Point-Free)
**Findings:** 4 total (1 HIGH, 2 MEDIUM, 1 LOW)

---

## Executive Summary

The H12 finding identifies a **critical type-safety regression** in the fuse-app's Settings feature:

- **Current state:** `@Shared(.savedTodos)` uses `[Todo]` (plain array)
- **Required state:** Must use `IdentifiedArrayOf<Todo>` for O(1) ID lookups
- **Impact:** Loss of performance guarantees and type-safe ID-based operations
- **Scope:** 2 locations (SharedModels.swift, SettingsFeature.swift)
- **Dependency:** Requires `IdentifiedCollections` library (already imported)

---

## Canonical Patterns

### Pattern 1: IdentifiedArrayOf Type Annotation

**Exact syntax required:**

```swift
import IdentifiedCollections

// Correct: Use IdentifiedArrayOf<T> where T: Identifiable
var todos: IdentifiedArrayOf<Todo> = []
var contacts: IdentifiedArrayOf<Contact> = []

// Incorrect: Plain array [Todo] loses O(1) lookup semantics
var todos: [Todo] = []  // DO NOT USE
```

**Why:** `IdentifiedArrayOf` is a typealias for `IdentifiedArray`, providing:
- **O(1) subscript lookup** by ID: `todos[id: someID]`
- **O(1) removal** by ID: `todos.remove(id: someID)`
- **Ordered iteration** with ID tracking: `for id in todos.ids { ... }`
- **Codable conformance** (automatic if element is Codable)

---

### Pattern 2: ID-Based Subscript Operations

**Correct operations on IdentifiedArrayOf:**

```swift
// 1. Read by ID (O(1))
let todo = todos[id: todoID]  // Optional<Todo>

// 2. Mutate by ID (O(1))
todos[id: todoID]?.title = "Updated"

// 3. Remove by ID, discarding result
todos[id: todoID] = nil

// 4. Remove by ID, capturing result
if let removed = todos.remove(id: todoID) {
    print("Deleted: \(removed.title)")
}

// 5. Iterate IDs (ordered set)
for id in todos.ids {
    print("ID: \(id)")
}

// 6. Append new element
todos.append(Todo(id: uuid(), title: "New"))

// 7. Filter (returns IdentifiedArrayOf<Todo>)
let completed = todos.filter { $0.isComplete }
```

**Incorrect operations:**

```swift
// DON'T: Manual find() — O(n) instead of O(1)
if let idx = todos.firstIndex(where: { $0.id == someID }) {
    todos[idx].title = "Updated"  // Anti-pattern
}

// DON'T: Manual filter then first — O(n)
let todo = todos.first { $0.id == someID }  // Anti-pattern

// DON'T: Treat as plain array
todos.append(contentsOf: moreTodos)  // Works but loses semantic intent
```

---

### Pattern 3: SharedKey Definition for IdentifiedArrayOf

**Correct SharedKey for file-persisted identifiable collections:**

```swift
import IdentifiedCollections
import Sharing

// In SharedModels.swift (or equivalent models file)

extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
    static var savedTodos: Self {
        Self[
            .fileStorage(
                URL.applicationSupportDirectory
                    .appending(component: "todos.json")
            ),
            default: []
        ]
    }
}

// In SettingsFeature.swift
@ObservableState
struct State: Equatable {
    @Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []
    // ...
}
```

**Why this pattern:**
- `FileStorageKey<IdentifiedArrayOf<Todo>>` declares the persisted type explicitly
- `.default: []` initializes as empty `IdentifiedArrayOf` (not plain array)
- Automatic Codable encoding/decoding (IdentifiedArrayOf conforms when element is Codable)

---

### Pattern 4: Filtering with Type Preservation

**IdentifiedArrayOf filtering returns IdentifiedArrayOf:**

```swift
// This works because filter on IdentifiedArrayOf returns IdentifiedArrayOf
let filtered: IdentifiedArrayOf<Todo> = todos.filter { !$0.isComplete }

// Can be used directly with [id:] subscript
let first = filtered[id: todoID]

// NOT required to convert back to IdentifiedArrayOf manually
```

**Why:** The library's generic `filter(_:)` preserves the `IdentifiedArrayOf` type.

---

## Current State

### Location 1: `SharedModels.swift:64-67`

**Current (incorrect):**

```swift
extension SharedKey where Self == FileStorageKey<[Todo]>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(URL.applicationSupportDirectory.appending(component: "todos.json")), default: []]
    }
}
```

**Issues:**
- `FileStorageKey<[Todo]>` declares plain array type
- `.default: []` is ambiguous (plain array, not IdentifiedArrayOf)
- Loss of O(1) ID-based operations
- Type mismatch when consuming via @Shared

---

### Location 2: `SettingsFeature.swift:15`

**Current (incorrect):**

```swift
@ObservableState
struct State: Equatable {
    @Shared(.savedTodos) var savedTodos: [Todo] = []
    // ...
}
```

**Issues:**
- `[Todo]` type annotation conflicts with intended IdentifiedArray semantics
- Default `[]` is plain array, not IdentifiedArrayOf
- View code (line 96) only reads `.count`, masking the real problem
- Incompatible with TodosFeature's `IdentifiedArrayOf<Todo>` pattern

---

### Location 3: `TodosFeature.swift:11` (Correct Reference)

**Current state (correct):**

```swift
@ObservableState
struct State: Equatable {
    var todos: IdentifiedArrayOf<Todo> = []
    // ...
}
```

**Why this is correct:**
- In-memory state uses `IdentifiedArrayOf<Todo>`
- All mutations use `[id:]` subscript (line 74, 99)
- Filter preserves IdentifiedArrayOf type (line 20)
- Sort modifies in-place (lines 120, 124, 128)

---

## Required Changes

### Change 1: Update SharedKey Definition

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/SharedModels.swift`

**Line:** 64

**From:**

```swift
extension SharedKey where Self == FileStorageKey<[Todo]>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(URL.applicationSupportDirectory.appending(component: "todos.json")), default: []]
    }
}
```

**To:**

```swift
extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(URL.applicationSupportDirectory.appending(component: "todos.json")), default: []]
    }
}
```

**Rationale:** Declares the correct persisted type as `IdentifiedArrayOf<Todo>` instead of plain `[Todo]`.

---

### Change 2: Update SettingsFeature State Type

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/SettingsFeature.swift`

**Line:** 15

**From:**

```swift
        @Shared(.savedTodos) var savedTodos: [Todo] = []
```

**To:**

```swift
        @Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []
```

**Rationale:** Matches the SharedKey definition and aligns with TodosFeature conventions.

---

### Verification: Type Consistency

After changes, verify:

1. **SharedModels.swift** exports:
   ```swift
   FileStorageKey<IdentifiedArrayOf<Todo>>.Default
   ```

2. **SettingsFeature.swift** consumes:
   ```swift
   @Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo>
   ```

3. **TodosFeature.swift** uses (unchanged):
   ```swift
   var todos: IdentifiedArrayOf<Todo>
   ```

4. **View code** (SettingsView, line 96) continues to compile:
   ```swift
   Text("\(store.savedTodos.count)")
   ```
   ✓ No changes needed — `count` exists on IdentifiedArrayOf

---

## Testing Strategy

### Test 1: Verify Type Alignment

**Location:** Create in `examples/fuse-library/Tests/FoundationTests/IdentifiedCollectionsTests.swift` (append)

```swift
// IC-07: Shared persistence respects IdentifiedArrayOf type
@Test func sharedPersistenceType() async throws {
    @Shared(.savedTodos) var todos: IdentifiedArrayOf<Todo> = []

    // Should compile without conversion
    #expect(todos.count == 0)

    // Should support O(1) operations
    todos.append(Todo(id: UUID(), title: "Test"))
    #expect(todos[id: todos.ids.first!] != nil)
}
```

---

### Test 2: Verify Serialization

Add to existing IdentifiedCollectionsTests or new DatabaseTests:

```swift
@Test func fileStorageSerializesIdentifiedArrayOf() throws {
    let todos: IdentifiedArrayOf<Todo> = [
        Todo(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "A"),
        Todo(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "B"),
    ]

    let data = try JSONEncoder().encode(todos)
    let decoded = try JSONDecoder().decode(IdentifiedArrayOf<Todo>.self, from: data)

    #expect(decoded.count == 2)
    #expect(decoded[id: todos.ids.first!] != nil)
}
```

---

## Ordering Dependencies

### Dependency Chain

```
08-PFW-Skill-Alignment
├─ H12 IdentifiedCollections (this document)
│  └─ INDEPENDENT — No blocking dependencies
│     (Can proceed immediately after SharedModels + SettingsFeature changes)
├─ H11 @CasePathable on Action enums
│  └─ pfw-case-paths (separate phase)
├─ H9 static var vs static let on DependencyKey
│  └─ pfw-dependencies (separate phase)
└─ H6 Remove GRDB imports
   └─ pfw-sqlite-data (separate phase)
```

### Why H12 is Independent

- **No cross-feature mutations:** SettingsFeature only reads `savedTodos.count`
- **TodosFeature unaffected:** Already uses `IdentifiedArrayOf<Todo>`
- **Sharing library unchanged:** Only type annotation changes in user code
- **No effect order constraints:** Can merge before/after other HIGH fixes

### Implementation Order (Recommended)

**Wave 1 — CRITICAL + H6, H8 (must fix):**
1. Fix C1: `.toggleCategory` → `.categoryFilterChanged`
2. Fix H8: Add `withErrorReporting` to `try!` in FuseApp.swift
3. Fix H6: Remove `import GRDB` from app and test sources

**Wave 2 — Structural alignment (sequential, can batch):**
4. **→ Fix H12: Update SharedModels + SettingsFeature (THIS CHANGE)**
5. Fix H4: `var id` → `let id` on @Table models
6. Fix H9: `static let` → `static var` on DependencyKey
7. Fix H1: Un-nest Path features
8. Continue with H3, H5, etc.

---

## Gotchas & Edge Cases

### Gotcha 1: Default Value Syntax

**Incorrect:**

```swift
// Ambiguous — compiler may infer [Todo] not IdentifiedArrayOf<Todo>
@Shared(.savedTodos) var savedTodos = []
```

**Correct:**

```swift
// Explicit type annotation required
@Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []
```

**Why:** Swift's type inference cannot distinguish plain array from IdentifiedArrayOf without a type hint.

---

### Gotcha 2: Mixing Codable Conformance

**Correct:**

```swift
struct Todo: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String
    // ...
}

// FileStorageKey<IdentifiedArrayOf<Todo>> — automatic Codable
```

**Incorrect:**

```swift
// If Todo doesn't conform to Codable, this fails at runtime
@Shared(.fileStorage(url)) var todos: IdentifiedArrayOf<NonCodableTodo>
```

**Verification:** Ensure `Todo` has `Codable` conformance (✓ already present in codebase).

---

### Gotcha 3: Conversion from Plain Array

**If you need to convert from existing plain array storage:**

```swift
// DO NOT do this manually:
let todos: IdentifiedArrayOf<Todo> = IdentifiedArrayOf(uniqueElements: plainArray)

// INSTEAD: Update the SharedKey definition at the source
// The persisted format (JSON) is unchanged; only the type annotation updates
```

**Why:** IdentifiedArrayOf's Codable automatically handles the conversion.

---

## Impact Analysis

### Code Breakage: NONE

- `savedTodos.count` works on both `[Todo]` and `IdentifiedArrayOf<Todo>` ✓
- No view code accesses `savedTodos` by index (`[n]`)
- No enumeration over `savedTodos` in current code
- Existing JSON serialization format unchanged (array of Todo objects)

### Performance Impact: POSITIVE

- **Before:** O(n) lookup via `.count` only (no ID-based ops possible)
- **After:** O(1) if view later adds ID-based operations
- **Today:** Neutral (view only reads `.count`)

### Cross-Platform: NO CHANGE

- FileStorage serialization format identical (JSON array)
- Skip bridge has no special handling for IdentifiedArrayOf
- Android/iOS behavior unchanged

---

## Summary

| Item | Value |
|------|-------|
| **Audit ID** | H12 |
| **Severity** | HIGH |
| **Type** | Type-safety regression |
| **Files affected** | 2 |
| **Lines to change** | 2 |
| **Breaking changes** | 0 |
| **Ordering blocker** | None (independent) |
| **Canonical source** | pfw-identified-collections skill |
| **Test coverage** | 6 existing tests (IdentifiedCollectionsTests) + recommendations for 2 new |

---

## References

- **Skill:** `/pfw-identified-collections` — Point-Free IdentifiedCollections skill
- **Library:** [IdentifiedCollections](https://github.com/pointfreeco/swift-identified-collections) v1.0.0+
- **Related audit findings:** H1, H4, H6, H9, H11 (structurally related, sequentially independent)
- **Documentation:** Library README + API interface at `references/interface/IdentifiedCollections.swiftinterface`
