# PFW IssueReporting Skill — Canonical Patterns & Phase 8 Alignment

**Generated:** 2026-02-23
**Scope:** Phase 8, Wave 1 — Critical issue reporting fixes (H8, M15)

---

## Canonical Patterns

The `pfw-issue-reporting` skill defines **two primary patterns** for non-fatal error handling:

### Pattern 1: Guard + `reportIssue` for Programmer Error

**Use when:** A programmer error is detected (e.g., missing state that should always exist).
**Effect:** Reports issue to developer console, does NOT crash or dispatch an error action.

```swift
func saveButtonTapped() {
  guard let id = draft.id
  else {
    reportIssue("Draft ID should be non-nil.")
    return
  }
  // continue with save
}
```

**Key rule:** Report PROGRAMMER ERROR only, NOT user error.

---

### Pattern 2: `withErrorReporting` for Caught Errors

**Use when:** An I/O operation can fail (database, network, file system) and you want to catch and report the error without crashing.
**Effect:** Wraps thrown errors, reports them via `reportIssue(error)`, and returns `nil` or zero value on failure.

#### Synchronous

```swift
func saveButtonTapped() {
  do {
    try client.save()
  } catch {
    reportIssue(error)
  }
}
```

#### Asynchronous (no return value)

```swift
func refreshButtonTapped() async {
  await withErrorReporting {
    try await client.refresh()
  }
}
```

#### Asynchronous (with return value)

```swift
func fetchButtonTapped() async {
  let result: Int? = await withErrorReporting {
    try await client.fetch()
  }
}
```

**Key rule:** `withErrorReporting` automatically catches and reports errors. Use it when errors are **expected but non-fatal**.

---

## Current State

### H8: `try!` in FuseApp.swift (CRITICAL)

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/FuseApp.swift`

**Lines 23–30:**
```swift
public init() {
    prepareDependencies {
        do {
            try $0.bootstrapDatabase()    // ← Line 26
        } catch {
            reportIssue(error)             // ← Already correct! ✓
        }
    }
}
```

**Status:** Already fixed. The code correctly uses `do/catch` with `reportIssue(error)`. No change needed.

---

### M15: Unhandled Errors in `Effect.run` Closures (HIGH MEDIUM)

**File:** `/Users/jacob/Developer/src/github/jacobcxdev/swift-crossplatform/examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`

**Lines 74–83** (`.onAppear` action):
```swift
case .onAppear:
    state.isLoading = true
    return .run { send in
        let notes = try await database.read { db in
            try Note.all.order { $0.createdAt.desc() }.fetchAll(db)  // ← Line 76: No error handling
        }
        let count = try await database.read { db in
            try Note.all.fetchCount(db)  // ← Line 79: No error handling
        }
        await send(.notesLoaded(notes))
        await send(.noteCountLoaded(count))
    }
```

**Problem:** The `try` statements can throw, but there is NO `do/catch` wrapper. If an error occurs, the effect crashes silently.

---

**Lines 87–102** (`.addNoteTapped` action):
```swift
case .addNoteTapped:
    let now = date.now.timeIntervalSince1970
    return .run { send in
        let note = try await database.write { db in  // ← Line 88: No error handling
            try Note.insert { ... }.execute(db)
            let id = db.lastInsertedRowID
            return Note(...)
        }
        await send(.noteAdded(note))
    }
```

**Problem:** Same issue — `try` can throw but there is NO error handling wrapper.

---

**Lines 104–110** (`.deleteNote` action):
```swift
case let .deleteNote(id):
    return .run { send in
        try await database.write { db in  // ← Line 106: No error handling
            try Note.find(id).delete().execute(db)
        }
        await send(.noteDeleted(id))
    }
```

**Problem:** Same issue — `try` can throw but there is NO error handling wrapper.

---

## Required Changes

### Change 1: Wrap `.onAppear` Effect.run Closure in `do/catch`

**File:** `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`
**Lines:** 72–83

**From:**
```swift
case .onAppear:
    state.isLoading = true
    return .run { send in
        let notes = try await database.read { db in
            try Note.all.order { $0.createdAt.desc() }.fetchAll(db)
        }
        let count = try await database.read { db in
            try Note.all.fetchCount(db)
        }
        await send(.notesLoaded(notes))
        await send(.noteCountLoaded(count))
    }
```

**To:**
```swift
case .onAppear:
    state.isLoading = true
    return .run { send in
        do {
            let notes = try await database.read { db in
                try Note.all.order { $0.createdAt.desc() }.fetchAll(db)
            }
            let count = try await database.read { db in
                try Note.all.fetchCount(db)
            }
            await send(.notesLoaded(notes))
            await send(.noteCountLoaded(count))
        } catch {
            reportIssue(error)
        }
    }
```

**Rationale:** Wrap all `try` statements in `do/catch`. Report errors via `reportIssue(error)`. This prevents silent crashes and makes errors visible to developers.

---

### Change 2: Wrap `.addNoteTapped` Effect.run Closure in `do/catch`

**File:** `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`
**Lines:** 85–102

**From:**
```swift
case .addNoteTapped:
    let now = date.now.timeIntervalSince1970
    return .run { send in
        let note = try await database.write { db in
            try Note.insert {
                Note.Draft(title: "New Note", body: "", category: "general", createdAt: now)
            }.execute(db)
            let id = db.lastInsertedRowID
            return Note(
                id: id,
                title: "New Note",
                body: "",
                category: "general",
                createdAt: now
            )
        }
        await send(.noteAdded(note))
    }
```

**To:**
```swift
case .addNoteTapped:
    let now = date.now.timeIntervalSince1970
    return .run { send in
        do {
            let note = try await database.write { db in
                try Note.insert {
                    Note.Draft(title: "New Note", body: "", category: "general", createdAt: now)
                }.execute(db)
                let id = db.lastInsertedRowID
                return Note(
                    id: id,
                    title: "New Note",
                    body: "",
                    category: "general",
                    createdAt: now
                )
            }
            await send(.noteAdded(note))
        } catch {
            reportIssue(error)
        }
    }
```

**Rationale:** Same as Change 1. Wrap all `try` statements in `do/catch` and report errors.

---

### Change 3: Wrap `.deleteNote` Effect.run Closure in `do/catch`

**File:** `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift`
**Lines:** 104–110

**From:**
```swift
case let .deleteNote(id):
    return .run { send in
        try await database.write { db in
            try Note.find(id).delete().execute(db)
        }
        await send(.noteDeleted(id))
    }
```

**To:**
```swift
case let .deleteNote(id):
    return .run { send in
        do {
            try await database.write { db in
                try Note.find(id).delete().execute(db)
            }
            await send(.noteDeleted(id))
        } catch {
            reportIssue(error)
        }
    }
```

**Rationale:** Same as Changes 1 and 2. Wrap all `try` statements in `do/catch` and report errors.

---

## Ordering Dependencies

### Dependency Chain

This fix has **NO dependencies** — it is **completely independent**.

- ✓ Does not depend on H6 (removing `import GRDB`) — we already import `IssueReporting`.
- ✓ Does not depend on M8 (adding `.dependencies` trait) — this is View/Reducer code, not test setup.
- ✓ Does not depend on M10 (moving `bootstrapDatabase()` call) — that is orthogonal; H8 is already correctly handled.

### Wave Placement

This fix belongs in **Wave 1 — Must Fix** (listed as H8 in audit).

### Prerequisites

- ✓ `IssueReporting` module is already imported in `DatabaseFeature.swift`.
- ✓ `IssueReporting` module is already imported in `FuseApp.swift`.
- ✓ Project already depends on `xctest-dynamic-overlay >= 1.0.0`.

No additional setup required.

---

## Verification Strategy

After applying the three changes:

1. **Build:** `swift build` should succeed.
2. **Run tests:** `swift test` should pass all existing tests.
3. **Manual test:** Trigger a database error (e.g., delete the database file while the app is running) and confirm that the error is reported via issue reporting console, not a crash.
4. **Code review:** Verify that all three closures now follow the `do/catch` + `reportIssue(error)` pattern.

---

## Anti-Patterns to Avoid

1. **Do NOT** use `try!` in any `Effect.run` closure — it will crash.
2. **Do NOT** use `try?` silently — errors are swallowed and developer won't know about failures.
3. **Do NOT** dispatch a separate `.error` action for expected I/O errors — use `reportIssue` instead.
4. **Do NOT** wrap `reportIssue` calls themselves in `try` — `reportIssue` does not throw.

---

## Summary

| Item | Current | Required | Priority |
|------|---------|----------|----------|
| H8: `FuseApp.swift` bootstrap | Already fixed ✓ | No change | — |
| M15: `.onAppear` Effect.run | Missing `do/catch` | Add wrapper + `reportIssue` | Wave 1 |
| M15: `.addNoteTapped` Effect.run | Missing `do/catch` | Add wrapper + `reportIssue` | Wave 1 |
| M15: `.deleteNote` Effect.run | Missing `do/catch` | Add wrapper + `reportIssue` | Wave 1 |

All three changes implement the **canonical `withErrorReporting` equivalent** for TCA `Effect.run` closures: catch errors and report them via `reportIssue` instead of crashing or silently swallowing failures.
