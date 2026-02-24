# PFW StructuredQueries — Research

Generated: 2026-02-23
Source: `/pfw-structured-queries` skill + audit findings H4, H5, M1, M16

---

## Canonical Patterns

### `let` vs `var` for `id`

Skill rule (schema-design.md): **DO prefer `let` for `id`**.

```swift
// CORRECT
@Table struct Reminder: Identifiable {
  let id: UUID
  var title = ""
}

// WRONG
@Table struct Item: Identifiable {
  var id: UUID    // <-- must be let
}
```

The `id` field represents a stable identity. It must never be mutated after creation, hence `let`.

### `@Column` annotation rules

Skill rule (schema-design.md): **DO NOT use `@Column("name")` when the column name string is identical to the property name**.

```swift
// CORRECT — name differs from column string
@Column("is_completed") var isCompleted = false

// CORRECT — marking primary key
@Column(primaryKey: true)
let id: Int

// WRONG — redundant, name matches property name exactly
@Column("itemCount") var itemCount: Int   // "itemCount" == property name

// WRONG — @Column(primaryKey:) not needed when field is named `id`
// @Table infers `id` as primary key automatically; @Column(primaryKey: true) is only
// needed when a different column is the PK, or to opt out with primaryKey: false
```

### Named predicate functions in `.where` closures

Skill rule (where.md): **DO NOT use infix operators for predicates. DO use named functions: `eq`, `neq`, `is`, `isNot`, `gt`, `gte`, `lt`, `lte`.**

```swift
// CORRECT
Item.where { $0.value.gt(10) }
Item.where { $0.name.eq("alpha") }
Item.where { $0.value.eq(999) }
Item.where { $0.categoryId.is(nil) }

// WRONG — infix operators are forbidden in .where closures
Item.where { $0.value > 10 }         // use .gt(10)
Item.where { $0.name == "alpha" }    // use .eq("alpha")
Item.where { $0.value == 999 }       // use .eq(999)
```

### `order(by:)` vs `.asc()`

Skill rule (order-by.md): **DO NOT specify `asc()` unless customizing NULL sorting.**

```swift
// CORRECT — simple ascending (the default)
Item.order(by: \.id)
Item.order(by: \.name)
// Key-path form only works before a join; after joins use closure form:
Item.order { $0.id }

// CORRECT — explicit direction only when needed
Item.order { $0.name.desc() }
Item.order { $0.title.asc(nulls: .last) }    // asc() justified: NULL customization
Item.order { $0.title.desc(nulls: .first) }

// WRONG — bare .asc() call with no NULL customization
Item.order { $0.name.asc() }    // drop .asc(), use order(by: \.name) or order { $0.name }
```

### Draft insert form for primary-keyed tables

Skill rule (inserts.md): **DO prefer drafts for primary-keyed tables. DO NOT use column-specifying form (`($0.name, $0.value)`) for primary-keyed tables.**

```swift
// CORRECT — draft form
Item.insert {
  Item.Draft(name: "newItem", value: 42, isActive: true)
}

// CORRECT — draft with optional id for upsert conflict
Item.upsert {
  Item.Draft(id: existingId, name: "updated", value: 100, isActive: false)
}

// WRONG — column-specifying form used where Draft should be used
Item.insert {
  ($0.name, $0.value, $0.isActive, $0.categoryId)
} values: {
  ("alpha", 5, true, Int?.some(1))
}
// Column-specifying form is valid only for non-primary-keyed tables
```

### Key-path syntax scope rule

Skill rule (query-building section): **ALWAYS use key-path syntax before a join. DO NOT use key-path syntax after a join.**

```swift
// CORRECT — key path before join
Item.order(by: \.id)
Item.where(\.isActive)

// CORRECT — closure form after join
Item
  .join(Category.all) { $0.categoryId.eq($1.id) }
  .order { items, categories in items.id }

// The closure parameter should be named after the pluralized table name
Item
  .join(Category.all) { items, categories in items.categoryId.eq(categories.id) }
```

---

## Current State

All violations are in:
- `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`
- `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift`

### H4: `var id` on `@Table` primary keys

File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

```swift
// Line 9-10: Item — WRONG, should be `let`
@Column(primaryKey: true)
let id: Int          // already let — CORRECT (H4 audit finding appears to be stale for Item)

// Line 18-19: Category — WRONG, should be `let`
@Column(primaryKey: true)
let id: Int          // already let — CORRECT (H4 audit finding appears to be stale for Category)
```

Re-reading the actual file: both `Item` (line 9-10) and `Category` (line 18-19) already use `let id`. The H4 finding in the audit may have been generated against an earlier version. However, `@Column(primaryKey: true)` on fields named `id` is redundant per schema-design.md — `@Table` infers `id` as primary key automatically.

File: `examples/fuse-app/Sources/FuseApp/SharedModels.swift`

```swift
// Line 42-43: Note model — CORRECT, uses let
@Column(primaryKey: true)
let id: Int64
```

Note models and `Todo`/`Contact` in SharedModels.swift use `var id: UUID` (lines 11, 27) but those are not `@Table`-annotated structs — they are plain `Identifiable` models. No fix required for those.

**Conclusion for H4:** Both `@Table` models in StructuredQueriesTests.swift already use `let id`. The `@Column(primaryKey: true)` annotation on a field named `id` is technically redundant but not harmful. No code change is required for H4 unless the `@Column(primaryKey: true)` redundancy is also being fixed.

### H5: Infix operators in `.where` closures

File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

```
Line 197: Item.where { $0.value > 10 && $0.isActive }
Line 443: Item.where { $0.value > 20 }          (inside testUpdateAndDelete)
Line 447: Item.where { $0.value == 999 }         (inside testUpdateAndDelete)
```

File: `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift`

```
Line 219: DataItem.where { $0.name == "nonexistent" }
```

### M1: `.asc()` without NULL customization (7 occurrences)

File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

```
Line 247: .order { $0.id.asc() }       (testJoinOperations, inner join)
Line 260: .order { $0.id.asc() }       (testJoinOperations, left join)
Line 301: .order { $0.name.asc() }     (testOrderBy, ascending name)
Line 325: .order { $0.name.asc() }     (testOrderBy, collation)  — NOTE: this is chained after .collate(.nocase), so it becomes .collate(.nocase).asc(); the collation is valid but .asc() itself has no NULL clause
Line 341: .order { $0.isActive.asc() } (testGroupByAggregation, countResults)
Line 354: .order { $0.isActive.asc() } (testGroupByAggregation, sumResults)
Line 364: .order { $0.isActive.asc() } (testGroupByAggregation, avgResults)
```

### M16: `@Column("itemCount")` redundant

File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

```swift
// Line 29-30: @Selection struct ItemSummary
@Selection
struct ItemSummary: Equatable {
  var isActive: Bool
  var itemCount: Int    // Line 30 — no @Column annotation present
}
```

Re-reading the actual file: line 29-30 shows `var itemCount: Int` with NO `@Column` annotation. The M16 finding references line 30, but that annotation does not exist in the current file. M16 is already resolved.

### Column-specifying insert form (LOW priority finding)

File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

```swift
// Lines 62-66: seedCategories — column-specifying form on non-primary-keyed insertion
try Category.insert {
  ($0.name)
} values: {
  "Tools"
  "Gadgets"
}.execute(db)

// Lines 70-78: seedItems — column-specifying form on primary-keyed table (Item)
try Item.insert {
  ($0.name, $0.value, $0.isActive, $0.categoryId)
} values: {
  ("alpha", 5, true, Int?.some(1))
  ...
}.execute(db)
```

The `seedItems` helper uses column-specifying form on `Item`, which is a primary-keyed table. The canonical form is `Item.Draft(...)`. The `seedCategories` helper uses column-specifying form on `Category`, which is also primary-keyed. Both should use the Draft form.

---

## Required Changes

### File: `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`

#### Change 1 — H5: Replace `>` with `.gt()` at line 197

```swift
// BEFORE
let results = try Item.where { $0.value > 10 && $0.isActive }

// AFTER
let results = try Item.where { $0.value.gt(10) && $0.isActive }
```

#### Change 2 — H5: Replace `>` and `==` with named functions at lines 443, 447

```swift
// BEFORE (line 443)
try Item.where { $0.value > 20 }
    .update { $0.value = 999 }
    .execute(db)

let highValue = try Item.where { $0.value == 999 }

// AFTER
try Item.where { $0.value.gt(20) }
    .update { $0.value = 999 }
    .execute(db)

let highValue = try Item.where { $0.value.eq(999) }
```

#### Change 3 — M1: Replace `.asc()` with `order(by:)` or bare closure at lines 247, 260

Lines 247 and 260 appear inside join chains (after `.join` and `.leftJoin`), so the closure form must be used (not key-path form). Drop `.asc()`:

```swift
// BEFORE (line 247 — inside join chain)
.order { $0.id.asc() }

// AFTER
.order { $0.id }

// BEFORE (line 260 — inside left join chain)
.order { $0.id.asc() }

// AFTER
.order { $0.id }
```

#### Change 4 — M1: Replace `.asc()` with `order(by:)` at line 301

Line 301 is on `Item.select(\.name)` with no join, so key-path form is valid:

```swift
// BEFORE
let ascResults = try Item.select(\.name)
    .order { $0.name.asc() }
    .fetchAll(db)

// AFTER
let ascResults = try Item.select(\.name)
    .order(by: \.name)
    .fetchAll(db)
```

#### Change 5 — M1: Replace `.collate(.nocase).asc()` with `.collate(.nocase)` at line 324-325

NULL customization is absent; `.asc()` must be dropped. The collation itself stays:

```swift
// BEFORE
let collateResults = try Item.select(\.name)
    .order { $0.name.collate(.nocase).asc() }
    .fetchAll(db)

// AFTER
let collateResults = try Item.select(\.name)
    .order { $0.name.collate(.nocase) }
    .fetchAll(db)
```

#### Change 6 — M1: Replace `.asc()` with bare expression at lines 341, 354, 364

These are inside group aggregation queries with no join, but the closure form is already in use (not key-path). Drop `.asc()`:

```swift
// BEFORE (3 occurrences)
.order { $0.isActive.asc() }

// AFTER
.order { $0.isActive }
// OR if the non-join key-path form is preferred:
.order(by: \.isActive)
// Use .order(by: \.isActive) since there is no join in those queries.
```

#### Change 7 — LOW: Replace column-specifying insert with Draft form in `seedItems`

```swift
// BEFORE
private func seedItems(_ db: Database) throws {
    try Item.insert {
        ($0.name, $0.value, $0.isActive, $0.categoryId)
    } values: {
        ("alpha", 5, true, Int?.some(1))
        ("beta", 15, true, Int?.some(1))
        ("gamma", 25, false, Int?.some(2))
        ("delta", 10, true, Int?.some(2))
        ("epsilon", 30, false, Int?.none)
    }.execute(db)
}

// AFTER
private func seedItems(_ db: Database) throws {
    try Item.insert {
        Item.Draft(name: "alpha", value: 5, isActive: true, categoryId: 1)
        Item.Draft(name: "beta", value: 15, isActive: true, categoryId: 1)
        Item.Draft(name: "gamma", value: 25, isActive: false, categoryId: 2)
        Item.Draft(name: "delta", value: 10, isActive: true, categoryId: 2)
        Item.Draft(name: "epsilon", value: 30, isActive: false)
    }.execute(db)
}
```

#### Change 8 — LOW: Replace column-specifying insert with Draft form in `seedCategories`

```swift
// BEFORE
private func seedCategories(_ db: Database) throws {
    try Category.insert {
        ($0.name)
    } values: {
        "Tools"
        "Gadgets"
    }.execute(db)
}

// AFTER
private func seedCategories(_ db: Database) throws {
    try Category.insert {
        Category.Draft(name: "Tools")
        Category.Draft(name: "Gadgets")
    }.execute(db)
}
```

#### Change 9 — LOW: Remove redundant `@Column(primaryKey: true)` from `id` fields

`@Table` infers `id` as primary key automatically. The annotation is harmless but redundant:

```swift
// BEFORE — Item (line 9-10)
@Column(primaryKey: true)
let id: Int

// AFTER
let id: Int

// BEFORE — Category (line 18-19)
@Column(primaryKey: true)
let id: Int

// AFTER
let id: Int
```

Only apply this if the team is aligning to zero-noise schema design. It is not a named audit finding; treat as optional cleanup.

### File: `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift`

#### Change 10 — H5: Replace `==` with `.eq()` at line 219

```swift
// BEFORE
try DataItem.where { $0.name == "nonexistent" }.limit(1).fetchOne(db)

// AFTER
try DataItem.where { $0.name.eq("nonexistent") }.limit(1).fetchOne(db)
```

### Files with no StructuredQueries API violations

- `examples/fuse-app/Sources/FuseApp/SharedModels.swift` — `Note` model uses `@Column(primaryKey: true)` and `let id: Int64`, which is correct.
- `examples/fuse-app/Sources/FuseApp/DatabaseFeature.swift` — Uses `Note.Draft(...)` form correctly. No ordering or predicate violations.

---

## Query API Reference

### Predicates (use in `.where` closures)

| Operation | Named function | FORBIDDEN infix |
|-----------|----------------|-----------------|
| equals | `.eq(value)` | `==` |
| not equals | `.neq(value)` | `!=` |
| greater than | `.gt(value)` | `>` |
| greater or equal | `.gte(value)` | `>=` |
| less than | `.lt(value)` | `<` |
| less or equal | `.lte(value)` | `<=` |
| is NULL | `.is(nil)` | `== nil` |
| is NOT NULL | `.isNot(nil)` | `!= nil` |
| contained in | `.in(collection)` | n/a |
| not contained in | `.notIn(collection)` | n/a |
| boolean true | key-path `.where(\.isActive)` or `$0.isActive` | n/a |
| boolean false | `.where { !$0.isActive }` | n/a |

### Ordering

| Intent | Correct form | Forbidden form |
|--------|-------------|----------------|
| Ascending (default) | `order(by: \.field)` or `order { $0.field }` | `order { $0.field.asc() }` |
| Descending | `order { $0.field.desc() }` | n/a |
| Ascending with NULL last | `order { $0.field.asc(nulls: .last) }` | n/a |
| Descending with NULL first | `order { $0.field.desc(nulls: .first) }` | n/a |
| With collation, ascending | `order { $0.field.collate(.nocase) }` | `order { $0.field.collate(.nocase).asc() }` |
| With collation, descending | `order { $0.field.collate(.nocase).desc() }` | n/a |
| Key-path (before join) | `order(by: \.field)` | Use after a join |
| Closure (after join) | `order { items, categories in items.field }` | Key-path form |

### Inserts

| Table type | Correct form | Wrong form |
|------------|-------------|------------|
| Primary-keyed | `Table.insert { Table.Draft(...) }` | Column-specifying `($0.col1, $0.col2) values: {...}` |
| Non-primary-keyed | `Table.insert { ($0.col1) } values: { ... }` | `.Draft` |
| Upsert with ID | `Table.upsert { Table.Draft(id: existingId, ...) }` | n/a |

### Schema `@Column` annotation

| Case | Use `@Column`? |
|------|---------------|
| Custom column name (differs from property) | Yes: `@Column("snake_case_name")` |
| Primary key on non-`id` field | Yes: `@Column(primaryKey: true)` |
| Opt out of primary key on `id` | Yes: `@Column(primaryKey: false)` |
| Column name equals property name exactly | No: remove the annotation |
| Field named `id` as primary key | No: `@Table` infers this automatically |

### `id` mutability

| Case | Declaration |
|------|-------------|
| All `@Table` primary key `id` fields | `let id: Type` |
| All other mutable columns | `var columnName: Type` |

---

## Ordering Dependencies

Apply changes in this sequence to avoid breaking the test suite mid-edit:

### Step 1 — Predicate changes (H5, independent, no structural impact)

Apply Changes 1, 2, 10. These are pure substitutions within existing `.where` closures. They compile independently and do not affect seeding or ordering logic.

```
StructuredQueriesTests.swift: lines 197, 443, 447
SQLiteDataTests.swift: line 219
```

### Step 2 — Order changes (M1, independent of Step 1)

Apply Changes 3, 4, 5, 6. These are inside query chains that do not depend on predicate changes. Verify test output is identical (ordering semantics are preserved — ascending is the SQL default, and `order(by: \.field)` produces the same SQL as `order { $0.field.asc() }`).

```
StructuredQueriesTests.swift: lines 247, 260, 301, 324-325, 341, 354, 364
```

Step 2 must be done **after** Step 1 is verified to compile, but Steps 1 and 2 have no data dependency on each other — they can be done in a single pass as long as the file compiles after both are applied.

### Step 3 — Draft insert refactor (LOW priority, depends on knowing `Item.Draft` initializer shape)

Apply Changes 7 and 8. These require knowing `categoryId` is optional (`Int?`) and that `Item.Draft` accepts `categoryId: Int?` as a trailing optional parameter. The `Draft` type is synthesised by the `@Table` macro, so confirm the parameter labels by checking macro expansion or the test model definition before applying.

Do Step 3 only after Steps 1-2 pass `swift test`.

### Step 4 — Annotation cleanup (OPTIONAL, zero-risk)

Apply Change 9 (remove redundant `@Column(primaryKey: true)`) only if the team explicitly chooses zero-noise schema alignment. This is not a named audit finding and does not affect runtime behavior.

### No cross-file dependencies

Changes to `StructuredQueriesTests.swift` and `SQLiteDataTests.swift` are independent of each other. They can be applied in parallel.

Changes to `SharedModels.swift` and `DatabaseFeature.swift` are not required (no violations found in current state).
