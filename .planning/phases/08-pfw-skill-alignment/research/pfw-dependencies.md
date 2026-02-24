# PFW Dependencies Skill Alignment

**Phase:** 08-pfw-skill-alignment
**Date:** 2026-02-23
**Focus:** Canonical patterns for Swift Dependencies library usage across fuse-app and fuse-library

---

## Canonical Patterns

### Pattern 1: DependencyKey Conformance — Use `static var` Computed Properties

**Canonical (from skill):**

```swift
extension APIClientKey: DependencyKey {
  static var liveValue: any APIClient {
    LiveAPIClient()
  }
}
```

**Key requirement:** `liveValue` MUST be a `static var` computed property, NOT a `static let`.

**Rationale:** Computed properties allow lazy instantiation and ensure proper initialization order. `static let` evaluates at module load time and can cause issues with complex initialization logic.

**What it looks like when wrong:**
```swift
// WRONG - static let
extension NumberFactClient: DependencyKey {
    static let liveValue: Self {
        Self(fetch: { number in "The number \(number) is interesting!" })
    }
}
```

**Canonical (correct) for SharedModels.swift:**
```swift
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

### Pattern 2: Accessing Dependencies in Reducers

**Canonical (from skill and tests):**

```swift
@Reducer
struct MyFeature {
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date
    @Dependency(APIClient.self) var apiClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            // Use injected dependencies instead of calling Date(), UUID()
            state.id = uuid()
            state.createdAt = date()
            return .none
        }
    }
}
```

**Key requirements:**
- Use `@Dependency` property wrapper ALWAYS for system dependencies like `date`, `uuid`.
- For custom types conforming to `DependencyKey`, pass the type itself: `@Dependency(APIClient.self)`.
- NEVER call `Date()`, `UUID()`, or uncontrolled system APIs directly in reducers.

### Pattern 3: Dependency Overrides in Tests

**Canonical (from skill and DependencyTests.swift):**

```swift
@MainActor
func testDependencyResolution() async throws {
    let store = Store(
        initialState: MyFeature.State()
    ) {
        MyFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.date.now = Date(timeIntervalSince1970: 1_000_000)
        $0[CustomClient.self] = MockCustomClient()
    }

    store.send(.someAction)
    try await Task.sleep(for: .milliseconds(100))
    store.withState { state in
        XCTAssertEqual(state.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }
}
```

**Key requirements:**
- Use `Store(...) { reducer } withDependencies: { ... }` initializer for Store-level overrides.
- Use `withDependencies { ... } operation: { ... }` for scoped overrides in helper functions.
- Prefer `.incrementing` UUID generators for deterministic test results.
- Use fixed timestamps (`Date(timeIntervalSince1970:)`) for date testing.

### Pattern 4: DependencyClient Implementation

**Canonical (from skill and DependencyTests.swift):**

```swift
@DependencyClient
struct NumberClient: Sendable {
    var fetch: @Sendable (_ id: Int) -> Int = { _ in 0 }
}

extension NumberClient: TestDependencyKey {
    static var testValue: NumberClient {
        NumberClient()
    }
}

extension NumberClient: DependencyKey {
    static var liveValue: NumberClient {
        NumberClient(fetch: { id in
            // Live implementation
            id * 2
        })
    }
}
```

**Key requirements:**
- Use `@DependencyClient` macro for client interface definition.
- All properties MUST have `@Sendable` annotation on closures.
- Conform to `TestDependencyKey` first for modularized interface.
- Extend with `DependencyKey` for live/preview implementations.
- Set default values that create inert/noop implementations for unimplemented endpoints.
- `testValue` returns a no-op client (calls reportIssue if endpoint accessed).

### Pattern 5: Error Handling with `withErrorReporting`

**Canonical (from IssueReporting and FuseApp.swift):**

```swift
import IssueReporting

// In @main entry point or app initialization
@main
struct MyApp: App {
    init() {
        prepareDependencies {
            do {
                try $0.bootstrapDatabase()
            } catch {
                reportIssue(error, "Failed to bootstrap database")
            }
        }
    }
}

// Or in reducers for effect errors
var body: some ReducerOf<Self> {
    Reduce { state, action in
        switch action {
        case .saveData:
            return .run { send in
                if let result = await withErrorReporting("Failed to save") {
                    try await db.write { db in
                        try insertData(db)
                    }
                    await send(.saveSucceeded)
                } else {
                    // Error was reported, handle gracefully
                    await send(.saveFailed)
                }
            }
        default:
            return .none
        }
    }
}
```

**Key requirements:**
- NEVER use `try!` in production code (especially in app initialization or reducers).
- Use `withErrorReporting` to wrap throwing operations and automatically report errors.
- Always use `reportIssue(error, message)` when catching errors manually.
- For I/O errors in view layer or initialization, wrap in `do/catch` and call `reportIssue`.
- `withErrorReporting` returns `nil` on error, so check the optional result.

### Pattern 6: Dependency Propagation Through Effect Boundaries

**Canonical (from DependencyTests.swift, lines 405-420):**

```swift
@Reducer
struct MyFeature {
    struct State: Equatable {
        var id: UUID?
    }
    enum Action {
        case fetchID
        case gotID(UUID)
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .fetchID:
                // Capture the dependency value BEFORE the async boundary
                return .run { [uuid] send in
                    await send(.gotID(uuid()))
                }
            case let .gotID(id):
                state.id = id
                return .none
            }
        }
    }
}
```

**Key requirements:**
- Capture dependency values in `[...]` capture list before entering async closures.
- Dependencies are TaskLocal and do not cross async boundaries by default.
- Use explicit capture to preserve the specific dependency override across `await` points.
- For merged effects, capture independently in each branch.

### Pattern 7: TestDependencyKey for Modularized Interfaces

**Canonical (from skill):**

```swift
// In interface module (public)
public enum APIClientKey: TestDependencyKey {
    public static var testValue: any APIClient {
        MockAPIClient()
    }
}

// In implementation module (internal or separate package)
extension APIClientKey: DependencyKey {
    public static var liveValue: any APIClient {
        LiveAPIClient()
    }
}
```

**Key requirements:**
- Use `TestDependencyKey` for interface definitions to separate API from implementation.
- Define `testValue` in the interface module (returns mock/noop).
- Extend with `DependencyKey` in the implementation module (adds `liveValue`).
- This allows testing without depending on live implementation details.

---

## Current State

### H8: `try!` in Production Code

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/FuseApp.swift:24-28`

```swift
init() {
    prepareDependencies {
        do {
            try $0.bootstrapDatabase()
        } catch {
            reportIssue(error)
        }
    }
}
```

**Status:** CORRECT as of current code (using `do/catch` + `reportIssue`). The audit result from PFW-AUDIT-RESULTS.md referenced line 24 with `try!` but the current code shows proper error handling. This appears to be already fixed.

### H9: `static let` vs `static var` on DependencyKey Values

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/SharedModels.swift:82-87`

```swift
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

**Status:** CORRECT. Already using `static var` computed properties.

### M6: Uncontrolled UUID()/Date() in Model Defaults

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/SharedModels.swift:16,31`

```swift
struct Todo: Equatable, Identifiable, Codable, Sendable {
    var id: UUID
    var title: String
    var isComplete: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String = "", isComplete: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}

struct Contact: Equatable, Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var email: String

    init(id: UUID = UUID(), name: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.email = email
    }
}
```

**Status:** REQUIRES FIX. Both `Todo` and `Contact` inits have uncontrolled `UUID()` and `.now` defaults. These bypass dependency injection.

**Current pattern (wrong):**
```swift
init(id: UUID = UUID(), createdAt: Date = .now) { ... }
```

**Test file reference:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-library/Tests/TCATests/DependencyTests.swift:10-11,22-23` also shows `static let` (WRONG) in test fixtures at lines 10-11 and 22-23, but the file review shows they're using `static var` correctly.

---

## Required Changes

### Change 1: Remove Default UUID()/Date() Parameters from Models

**File:** `examples/fuse-app/Sources/FuseApp/SharedModels.swift`

**Action:** Remove default parameter values that use uncontrolled system APIs. Require explicit injection via `@Dependency`.

**Current (lines 16, 31):**
```swift
init(id: UUID = UUID(), title: String = "", isComplete: Bool = false, createdAt: Date = .now) {
init(id: UUID = UUID(), name: String = "", email: String = "") {
```

**Required (new):**
```swift
init(id: UUID, title: String = "", isComplete: Bool = false, createdAt: Date) {
init(id: UUID, name: String = "", email: String = "") {
```

**Rationale:** Callers must explicitly provide `id` and `createdAt` by injecting via `@Dependency(\.uuid)` and `@Dependency(\.date.now)` in reducers, not in model defaults. This ensures all model creation is testable.

**Impact:** All creation sites for `Todo` and `Contact` must be updated to inject via dependencies.

### Change 2: Verify All DependencyKey Conformances Use `static var`

**File:** `examples/fuse-library/Tests/TCATests/DependencyTests.swift`

**Status:** ALREADY CORRECT. Lines 9-11 and 22-24 use `static var`:
```swift
private struct TestCounterKey: DependencyKey {
    static var liveValue: Int { 42 }
    static var testValue: Int { 0 }
}
```

**Action:** No changes needed. Continue this pattern for all new DependencyKey conformances.

### Change 3: Ensure withErrorReporting Wraps All I/O Operations

**File:** `examples/fuse-app/Sources/FuseApp/FuseApp.swift` (line 24-28) — ALREADY CORRECT

**Status:** Already uses proper `do/catch` + `reportIssue` pattern.

**Scanning scope:** Search all reducers and initialization code for `try!` — report any found as violations.

**Required pattern:**
```swift
do {
    try operation()
} catch {
    reportIssue(error, "Description of what was attempted")
}
```

Or for async:
```swift
let result = await withErrorReporting("Description") {
    try await operation()
}
guard result != nil else { return .none }
```

---

## Ordering Dependencies

### Dependency Graph for Phase 8 Alignment

```
H9: static var (DependencyKey)
  └─ M6: Remove default UUID()/Date() in models
      └─ Requires: Update all creation sites to inject via @Dependency
          └─ Depends on: Reducer changes to accept injected values
              └─ Depends on: Feature reducer refactoring (Phase 7)

H8: withErrorReporting for I/O errors
  ├─ Already implemented in FuseApp.swift
  └─ Audit for remaining try! in codebase
      └─ Depends on: No other phase work

M6 Implementation Order:
  1. Scan all Todo/Contact creation sites
  2. Update inits to remove defaults
  3. Update reducers to inject via @Dependency(\.uuid) and @Dependency(\.date)
  4. Verify tests still pass with injected dependencies
```

### Relationship to Other Skill Changes

| Skill | Dependency | Notes |
|-------|-----------|-------|
| pfw-composable-architecture | Blocks M6 | Need reducer Action/State updates for dependency parameters |
| pfw-testing | Complements H9 | Testing trait `.dependencies { ... }` pairs with DependencyKey patterns |
| pfw-issue-reporting | Enables H8 | `withErrorReporting` and `reportIssue` are IssueReporting exports |
| pfw-identified-collections | Blocked by M6 | Todo uses [Todo] instead of IdentifiedArrayOf<Todo> |
| pfw-custom-dump | Orthogonal | No dependency ordering |

---

## Implementation Checklist

### For Phase 8 Execution

- [ ] **H9 Verification:** Audit all DependencyKey conformances in codebase. Confirm all use `static var`.
- [ ] **M6 Step 1:** Identify all Todo/Contact creation sites across features and tests.
- [ ] **M6 Step 2:** Remove `id: UUID = UUID()` and `createdAt: Date = .now` defaults from `SharedModels.swift`.
- [ ] **M6 Step 3:** Update each feature reducer that creates Todo/Contact to inject via `@Dependency(\.uuid)` and `@Dependency(\.date)`.
- [ ] **M6 Step 4:** Update test fixtures to pass explicit values or override via `withDependencies { ... }`.
- [ ] **H8 Verification:** `grep -r "try!"` across `examples/` to confirm only test helpers use forced try (acceptable). Production code must use `withErrorReporting` or `do/catch` + `reportIssue`.
- [ ] **Integration Test:** Run full test suite to verify dependency injection doesn't break Store initialization or effect resolution.

### For Verification

- [ ] All new DependencyKey conformances use `static var`, not `static let`.
- [ ] No `UUID()` or `Date()` calls in model defaults.
- [ ] No `try!` in production code (FuseApp, Features, DatabaseFeature).
- [ ] All effect error handling uses `withErrorReporting` or explicit `reportIssue`.

---

## References

- **Point-Free Dependencies Skill:** `/Users/jacob/.claude/skills/pfw-dependencies`
- **Audit Results:** `.planning/PFW-AUDIT-RESULTS.md` (H8, H9, M6)
- **Test Fixtures:** `examples/fuse-library/Tests/TCATests/DependencyTests.swift`
- **IssueReporting API:** `forks/xctest-dynamic-overlay/Sources/IssueReporting/ErrorReporting.swift`
- **Current Implementation:** `examples/fuse-app/Sources/FuseApp/SharedModels.swift` and `FuseApp.swift`
