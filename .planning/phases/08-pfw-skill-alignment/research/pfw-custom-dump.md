# CustomDump Canonical Patterns & Decision Boundary

**Date:** 2026-02-23
**Skill Source:** `/pfw-custom-dump`
**Audit Reference:** `.planning/PFW-AUDIT-RESULTS.md` — M4 (12 findings, 7+ XCTAssertEqual sites)

---

## Canonical Patterns

### Pattern 1: Static Equality Assertions with `expectNoDifference`

Use `expectNoDifference` when asserting that a computed state exactly matches an expected value after an action.

```swift
// CANONICAL: Swift Testing @Test macro + expectNoDifference
@Test func counterIncrement() {
  let store = TestStore(initialState: Counter.State()) {
    Counter()
  }
  await store.send(.increment) {
    $0.count = 1
  }
  // No separate assertion needed — TestStore mutation closure handles state transitions
}

// When separate assertion is required (outside TestStore):
@Test func verifyFinalState() {
  var model = Counter.State()
  model.count = 5

  expectNoDifference(model, Counter.State(count: 5))
}
```

**Best for:**
- Post-action state verification
- Struct/array equality checks where pretty-printed diff is valuable on failure
- Static expected-state scenarios (not mutation/side-effect tests)

**DO NOT:**
- Use with XCTest (`XCTAssertEqual`) — migrate to Swift Testing first
- Use for action/behavior tests that should verify state *changes* — use `expectDifference` instead

---

### Pattern 2: Mutation Assertions with `expectDifference`

Use `expectDifference` to assert that a specific set of mutations occurred when performing an action.

```swift
// CANONICAL: Assert state mutations caused by an action
@Test func incrementCounter() async {
  var counter = Counter.State()

  expectDifference(counter) {
    // Perform mutation
    counter.count += 1
  } changes: {
    // Describe ONLY the fields that changed
    \.count = 1
  }
}

// For nested/array mutations, be granular:
@Test func updateItemInList() async {
  var model = ItemList.State(items: [
    ItemFeature.State(id: UUID(), value: 0)
  ])
  let itemID = model.items[0].id

  expectDifference(model.items) {
    if let index = model.items.firstIndex(where: { $0.id == itemID }) {
      model.items[index].value += 1
    }
  } changes: {
    // Granular mutation: only the field that changed
    [0].value = 1
  }
}
```

**Best for:**
- Verifying state mutations caused by reducer actions
- Asserting that specific properties changed (and others did not)
- Sensitive to "too much logic" in changes closures

**DO NOT:**
- Recreate entire nested objects (bad: `\.items[0] = ItemFeature.State(...)`)
- Use aggregate transformations (bad: `\.items.map(\.value)`)
- Use comparison operators (`\.count += 1`) — reassign simple values (`\.count = 2`)

---

### Pattern 3: Insert/Remove for Complex Collections

When modifying arrays or dictionaries, use structural mutations instead of full reconstruction.

```swift
// CANONICAL: Use insert/remove for array mutations
@Test func addItemToList() {
  var model = ItemList.State(items: [
    ItemFeature.State(id: UUID(1), value: 0),
    ItemFeature.State(id: UUID(2), value: 10)
  ])
  let newItem = ItemFeature.State(id: UUID(3), value: 20)

  expectDifference(model.items) {
    model.items.append(newItem)
  } changes: {
    // Insert new element at the end
    .insert(ItemFeature.State(id: UUID(3), value: 20), at: 2)
  }
}

// For removals:
@Test func removeItemFromList() {
  var model = ItemList.State(items: [
    ItemFeature.State(id: UUID(1), value: 0),
    ItemFeature.State(id: UUID(2), value: 10)
  ])

  expectDifference(model.items) {
    model.items.remove(at: 1)
  } changes: {
    // Remove element at index
    .remove(at: 1)
  }
}
```

---

### Pattern 4: Pretty-Printing with `customDump`

Use `customDump` to inspect data structures in console output (debugging only, not assertions).

```swift
// CANONICAL: Pretty-print a value
customDump(model)

// To string:
let prettyString = String(customDumping: model)
```

---

### Pattern 5: Computing Diffs Programmatically

Use `diff` function to compute and print a difference between two values.

```swift
// CANONICAL: Compute and print difference
if let difference = diff(lhs, rhs) {
  print(difference)
}
```

---

## Decision Boundary

### When to use `expectNoDifference` vs `#expect` vs `expectDifference`

| Assertion Type | Use Case | Example | XCTest Equivalent |
|----------------|----------|---------|------------------|
| **`expectNoDifference(lhs, rhs)`** | Static state equality after mutation (no verification of what changed) | Verify final state of counter after increment | `XCTAssertEqual` |
| **`#expect(condition)`** | Simple boolean conditions or non-structure types | `#expect(count > 0)`, `#expect(name == "test")` | `XCTAssert` |
| **`expectDifference(...) { action } changes: { mutations }`** | Assert specific state mutations caused by an action | Verify that `count` incremented by 1 but `name` stayed the same | `XCTAssertDifference` (legacy) |

### Decision Tree

```
Are you asserting state EQUALITY (no need to verify what changed)?
  └─ YES: Use expectNoDifference
  └─ NO: Are you asserting state MUTATIONS caused by an action?
         └─ YES: Use expectDifference
         └─ NO: Is it a simple boolean?
                └─ YES: Use #expect
                └─ NO: Use expectNoDifference (for struct/array equality)
```

### Concrete Examples from Codebase

**Current (WRONG):**
```swift
// examples/fuse-library/Tests/TCATests/StoreReducerTests.swift:276
XCTAssertEqual(store.withState(\.detail), Counter.State(count: 0))

// examples/fuse-library/Tests/TCATests/StoreReducerTests.swift:340
XCTAssertEqual(store.withState(\.log), ["logged"])

// examples/fuse-library/Tests/TCATests/EffectTests.swift:267
XCTAssertEqual(store.withState(\.values), [1, 2])
```

**Corrected (RIGHT):**
```swift
// These should become expectNoDifference (after Swift Testing migration)
expectNoDifference(store.withState(\.detail), Counter.State(count: 0))
expectNoDifference(store.withState(\.log), ["logged"])
expectNoDifference(store.withState(\.values), [1, 2])
```

---

## Current State

### File-by-File Analysis (M4 findings)

| File | Line | Pattern | Count | Issue |
|------|------|---------|-------|-------|
| `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift` | 276, 280, 340 | `XCTAssertEqual(store.withState(...), struct/array)` | 3 | Uses XCTest instead of expectNoDifference |
| `examples/fuse-library/Tests/TCATests/EffectTests.swift` | 267 | `XCTAssertEqual(store.withState(\.values), [1, 2])` | 1 | Array equality using XCTest |
| `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` | 96, 145, 146, 455–509 | `XCTAssertEqual(store.state.*, ...)` | 6+ | Struct/array/scalar equality assertions |

### Total M4 Violations: 12 (as per audit)

**Root cause:** All test files still use XCTest + `XCTAssertEqual` instead of Swift Testing + `expectNoDifference`.

---

## Required Changes

### Change 1: Add `import CustomDump` to Test Targets

**Files affected:**
- `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift`
- `examples/fuse-library/Tests/TCATests/EffectTests.swift`
- `examples/fuse-library/Tests/TCATests/TestStoreTests.swift` (if exists)
- `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift`

**Action:**
```swift
// Add to imports
import CustomDump
```

**Note:** `CustomDump` is already a dependency in `examples/fuse-library/Package.swift` (line 19, 51).

### Change 2: Migrate Test Targets to Swift Testing

**Wave 3 requirement (lowest urgency, largest volume):**

Convert XCTest files to Swift Testing `@Suite` pattern.

**Before:**
```swift
import XCTest

final class StoreReducerTests: XCTestCase {
  @MainActor
  func testScopeReducer() async {
    // ...
  }
}
```

**After:**
```swift
import Testing
import CustomDump

@Suite(.serialized)
struct StoreReducerTests {
  @Test
  @MainActor
  func testScopeReducer() async {
    // ...
  }
}
```

### Change 3: Replace `XCTAssertEqual` with `expectNoDifference`

**Specific replacements:**

```swift
// File: examples/fuse-library/Tests/TCATests/StoreReducerTests.swift
// Line 276: Change from
XCTAssertEqual(store.withState(\.detail), Counter.State(count: 0))
// To
expectNoDifference(store.withState(\.detail), Counter.State(count: 0))

// Line 280: Change from
XCTAssertEqual(store.withState(\.detail), Counter.State(count: 1))
// To
expectNoDifference(store.withState(\.detail), Counter.State(count: 1))

// Line 340: Change from
XCTAssertEqual(store.withState(\.log), ["logged"])
// To
expectNoDifference(store.withState(\.log), ["logged"])

// File: examples/fuse-library/Tests/TCATests/EffectTests.swift
// Line 267: Change from
XCTAssertEqual(store.withState(\.values), [1, 2])
// To
expectNoDifference(store.withState(\.values), [1, 2])
```

### Change 4: Evaluate `#expect` for Simple Scalar Assertions

Some assertions in the codebase may be better served with `#expect` for scalar types:

```swift
// Current (acceptable but less pretty-printable):
XCTAssertEqual(store.state.count, 1)

// Better (simple boolean check):
#expect(store.state.count == 1)

// Or use expectNoDifference if comparing entire State struct:
expectNoDifference(store.state.count, 1)
```

---

## Ordering Dependencies

### 1. Swift Testing Migration (Blocking)

**Dependency chain:**
1. Create `@Suite` base infrastructure (H10 finding)
2. Convert test classes to `@Suite` structs
3. Replace `@Test` methods in place of `func test...()`
4. Only then import and use `CustomDump` APIs

**Timeline:** Phase 8, Wave 3

**Blocker:** Cannot use `expectNoDifference` in XCTest context. The macro requires Swift Testing.

### 2. CustomDump Import (Non-blocking)

Can be added immediately, but assertions won't convert until Swift Testing migration completes.

**Action:** Add `import CustomDump` to all test files in parallel with Swift Testing migration.

### 3. Assertion Replacement (Wave 3)

Replace assertions only **after** migration to Swift Testing:

1. Migrate to `@Suite` / `@Test`
2. Add `import CustomDump`
3. Replace `XCTAssertEqual(..., struct/array)` → `expectNoDifference(...)`
4. Replace `XCTAssertEqual(..., scalar)` → `#expect(... == ...)` or `expectNoDifference`
5. For behavioral tests: use `expectDifference` with granular change descriptors

### 4. Related Cleanup

**While migrating, also fix:**
- H3: Remove `Action: Equatable` from test reducers (conflicts with CustomDump reflection)
- M5: Remove transitive deps from test target Package.swift entries
- M3: Replace `if case` with `.is()` / `[case:]` subscript (CasePaths integration)

---

## Summary: Prescriptive Guidance

### DO

1. **Use `expectNoDifference` for struct/array equality** — provides pretty-printed diff on failure.
2. **Use `expectDifference` for mutation assertions** — verifies specific state changes without false positives.
3. **Use `#expect` for simple boolean conditions** — keeps tests readable.
4. **Add `import CustomDump`** to all test files that assert on structures or arrays.
5. **Migrate to Swift Testing** before using any CustomDump APIs (hard blocker).
6. **Keep mutation closures granular** — only specify fields that actually changed.

### DO NOT

1. **Do NOT use `XCTAssertEqual` for struct/array comparisons** — it lacks pretty-printing and is pre-Swift Testing.
2. **Do NOT use legacy `XCTAssertNoDifference` or `XCTAssertDifference`** — these are deprecated.
3. **Do NOT recreate entire nested objects** in `expectDifference` changes — use minimal mutations.
4. **Do NOT nest Path features inside parent reducers** — this breaks CustomDump reflection on Action enums.
5. **Do NOT conform Action enums to Equatable** — this interferes with CasePaths + CustomDump introspection.

---

## Related Findings

| Finding | Severity | Impact | Fix Priority |
|---------|----------|--------|--------------|
| H10: Missing `@Suite` base pattern | HIGH | Cannot use Swift Testing APIs | Wave 3, blocker |
| H3: Action: Equatable on test reducers | HIGH | Breaks CustomDump reflection | Wave 2 |
| H11: Missing `@CasePathable` on Actions | HIGH | Limits CustomDump output | Wave 2 |
| M3: `if case` instead of `.is()` / subscript | MEDIUM | Obsolete pattern when using CasePaths | Wave 3 |

---

## Next Steps

1. **Phase 8.0** — Migrate one test file to Swift Testing + CustomDump as proof-of-concept
2. **Phase 8.1** — Batch migrate remaining TCA test files
3. **Phase 8.2** — Migrate FuseApp integration tests
4. **Phase 8.3** — Verify all custom diff output and fix any CustomDumpRepresentable issues
