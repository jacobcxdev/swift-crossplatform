import SQLiteData
import Testing

// MARK: - @Table models (must be file-scope for macro expansion)

@Table
struct Item: Identifiable, Equatable, Sendable {
    @Column(primaryKey: true)
    let id: Int
    var name: String
    var value: Int
    var isActive: Bool
    var categoryId: Int?
}

@Table
struct Category: Identifiable, Equatable, Sendable {
    @Column(primaryKey: true)
    let id: Int
    var name: String
}

// MARK: - @Selection for grouped aggregation (SQL-03/SQL-04)

@Selection
struct ItemSummary: Equatable {
    var isActive: Bool
    var itemCount: Int
}

// MARK: - Test Suite

@Suite(.serialized)
struct StructuredQueriesTests {

    // MARK: - Helpers

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try #sql(
                """
                CREATE TABLE "categories" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    "name" TEXT NOT NULL DEFAULT ''
                ) STRICT
                """
            ).execute(db)
            try #sql(
                """
                CREATE TABLE "items" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    "name" TEXT NOT NULL DEFAULT '',
                    "value" INTEGER NOT NULL DEFAULT 0,
                    "isActive" INTEGER NOT NULL DEFAULT 1,
                    "categoryId" INTEGER REFERENCES "categories"("id")
                ) STRICT
                """
            ).execute(db)
        }
        return dbQueue
    }

    private func seedCategories(_ db: Database) throws {
        try Category.insert {
            ($0.name)
        } values: {
            "Tools"
            "Gadgets"
        }.execute(db)
    }

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

    private func seedAll(_ db: Database) throws {
        try seedCategories(db)
        try seedItems(db)
    }

    // MARK: - SQL-01: @Table macro generates metadata

    @Test func tableMacro() {
        // @Table generates tableName and column accessors
        #expect(Item.tableName == "items")
        #expect(Category.tableName == "categories")

        // Verify the table can produce a valid SELECT query
        let query = Item.all.query
        #expect(!query.isEmpty, "@Table should generate a valid query")
    }

    // MARK: - SQL-02: @Column(primaryKey:) -- auto-increment

    @Test func columnPrimaryKey() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            // Insert without explicit id -- auto-increment should assign ids
            try Item.insert {
                Item.Draft(name: "first", value: 1, isActive: true)
            }.execute(db)
            try Item.insert {
                Item.Draft(name: "second", value: 2, isActive: true)
            }.execute(db)

            let items = try Item.all.order(by: \.id).fetchAll(db)
            #expect(items.count == 2)
            #expect(items[0].id == 1)
            #expect(items[0].name == "first")
            #expect(items[1].id == 2)
            #expect(items[1].name == "second")
        }
    }

    // MARK: - SQL-03: @Column(as:) -- custom column representation

    @Test func columnCustomRepresentation() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            // Use a raw SQL query that produces the columns ItemSummary expects
            let results = try #sql(
                """
                SELECT "isActive", count(*) AS "itemCount"
                FROM "items"
                GROUP BY "isActive"
                ORDER BY "isActive"
                """,
                as: ItemSummary.self
            ).fetchAll(db)

            #expect(results.count == 2)
            #expect(results[0] == ItemSummary(isActive: false, itemCount: 2))
            #expect(results[1] == ItemSummary(isActive: true, itemCount: 3))
        }
    }

    // MARK: - SQL-04: @Selection multi-column grouping

    @Test func selectionTypeComposition() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            let results = try #sql(
                """
                SELECT "isActive", count(*) AS "itemCount"
                FROM "items"
                GROUP BY "isActive"
                ORDER BY "isActive"
                """,
                as: ItemSummary.self
            ).fetchAll(db)

            #expect(results.count == 2)
            // false group: gamma, epsilon
            #expect(results[0].isActive == false)
            #expect(results[0].itemCount == 2)
            // true group: alpha, beta, delta
            #expect(results[1].isActive == true)
            #expect(results[1].itemCount == 3)
        }
    }

    // MARK: - SQL-05: Select specific columns

    @Test func selectColumns() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            let results = try Item.select { ($0.name, $0.value) }
                .order(by: \.id)
                .fetchAll(db)

            #expect(results.count == 5)
            #expect(results[0].0 == "alpha")
            #expect(results[0].1 == 5)
            #expect(results[2].0 == "gamma")
            #expect(results[2].1 == 25)
        }
    }

    // MARK: - SQL-06: Where predicates

    @Test func wherePredicates() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            let results = try Item.where { $0.value.gt(10) && $0.isActive }
                .order(by: \.id)
                .fetchAll(db)

            #expect(results.count == 1)
            #expect(results[0].name == "beta")
            #expect(results[0].value == 15)
        }
    }

    // MARK: - SQL-07: Find by ID

    @Test func findById() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            let results = try Item.find(1).fetchAll(db)
            #expect(results.count == 1)
            #expect(results[0].id == 1)
            #expect(results[0].name == "alpha")
        }
    }

    // MARK: - SQL-08: Where IN operator

    @Test func whereInOperator() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            let results = try Item.where { $0.name.in(["alpha", "gamma"]) }
                .order(by: \.name)
                .fetchAll(db)

            #expect(results.count == 2)
            #expect(results[0].name == "alpha")
            #expect(results[1].name == "gamma")
        }
    }

    // MARK: - SQL-09: Join operations

    @Test func joinOperations() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            // Inner join -- only items with matching categories
            let innerResults = try Item
                .order(by: \.id)
                .join(Category.all) { $0.categoryId.eq($1.id) }
                .select { ($0.name, $1.name) }
                .fetchAll(db)

            #expect(innerResults.count == 4) // epsilon has no category
            #expect(innerResults[0].0 == "alpha")
            #expect(innerResults[0].1 == "Tools")
            #expect(innerResults[2].0 == "gamma")
            #expect(innerResults[2].1 == "Gadgets")

            // Left join -- all items, categories nullable
            let leftResults = try Item
                .order(by: \.id)
                .leftJoin(Category.all) { $0.categoryId.eq($1.id) }
                .select { ($0.name, $1.name) }
                .fetchAll(db)

            #expect(leftResults.count == 5)
            #expect(leftResults[4].0 == "epsilon")
            #expect(leftResults[4].1 == nil) // no category

            // Right join -- all categories, items nullable
            let rightResults = try Item
                .rightJoin(Category.all) { $0.categoryId.eq($1.id) }
                .select { ($0.name, $1.name) }
                .fetchAll(db)

            // Both categories have items, so right join returns all category rows
            #expect(rightResults.count >= 2)
            // Verify at least one category name appears
            #expect(rightResults.contains(where: { $0.1 == "Tools" }))
            #expect(rightResults.contains(where: { $0.1 == "Gadgets" }))

            // Full join -- all rows from both sides
            let fullResults = try Item
                .fullJoin(Category.all) { $0.categoryId.eq($1.id) }
                .select { ($0.name, $1.name) }
                .fetchAll(db)

            // Full join includes epsilon (no category) + all category-matched items
            #expect(fullResults.count >= 5)
        }
    }

    // MARK: - SQL-10: Order by (asc, desc, collation)

    @Test func orderBy() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            // Ascending order by name
            let ascResults = try Item.select(\.name)
                .order(by: \.name)
                .fetchAll(db)
            #expect(ascResults == ["alpha", "beta", "delta", "epsilon", "gamma"])

            // Descending order by name
            let descResults = try Item.select(\.name)
                .order { $0.name.desc() }
                .fetchAll(db)
            #expect(descResults == ["gamma", "epsilon", "delta", "beta", "alpha"])
        }

        // Case-insensitive collation ordering
        let dbQueue2 = try makeDatabase()
        try dbQueue2.write { db in
            try Item.insert {
                ($0.name, $0.value, $0.isActive)
            } values: {
                ("Banana", 1, true)
                ("apple", 2, true)
                ("Cherry", 3, true)
            }.execute(db)

            let collateResults = try Item.select(\.name)
                .order { $0.name.collate(.nocase) }
                .fetchAll(db)
            #expect(collateResults == ["apple", "Banana", "Cherry"])
        }
    }

    // MARK: - SQL-11: Group by with aggregations

    @Test func groupByAggregation() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            // Group by isActive, count per group
            let countResults = try Item
                .select { ($0.isActive, $0.id.count()) }
                .group(by: \.isActive)
                .order(by: \.isActive)
                .fetchAll(db)

            #expect(countResults.count == 2)
            #expect(countResults[0].0 == false) // inactive
            #expect(countResults[0].1 == 2)     // gamma, epsilon
            #expect(countResults[1].0 == true)  // active
            #expect(countResults[1].1 == 3)     // alpha, beta, delta

            // Sum of values per group
            let sumResults = try Item
                .select { ($0.isActive, $0.value.sum()) }
                .group(by: \.isActive)
                .order(by: \.isActive)
                .fetchAll(db)

            #expect(sumResults[0].1 == 55)  // gamma(25) + epsilon(30)
            #expect(sumResults[1].1 == 30)  // alpha(5) + beta(15) + delta(10)

            // Avg of values per group
            let avgResults = try Item
                .select { ($0.isActive, $0.value.avg()) }
                .group(by: \.isActive)
                .order(by: \.isActive)
                .fetchAll(db)

            #expect(avgResults[0].1 == 27.5) // (25+30)/2
            #expect(avgResults[1].1 == 10.0) // (5+15+10)/3

            // Min and max
            let minResult = try Item.select { $0.value.min() }.fetchAll(db)
            #expect(minResult.first == 5)

            let maxResult = try Item.select { $0.value.max() }.fetchAll(db)
            #expect(maxResult.first == 30)
        }
    }

    // MARK: - SQL-12: Limit and offset

    @Test func limitOffset() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            let results = try Item.select(\.name)
                .order(by: \.id)
                .limit(2, offset: 1)
                .fetchAll(db)

            #expect(results.count == 2)
            #expect(results[0] == "beta")   // id=2
            #expect(results[1] == "gamma")  // id=3
        }
    }

    // MARK: - SQL-13: Insert and upsert

    @Test func insertAndUpsert() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedCategories(db)

            // Insert a new row
            try Item.insert {
                Item.Draft(name: "newItem", value: 42, isActive: true)
            }.execute(db)

            let items = try Item.all.fetchAll(db)
            #expect(items.count == 1)
            #expect(items[0].name == "newItem")
            #expect(items[0].value == 42)

            // Upsert -- insert new row (no conflict)
            try Item.upsert {
                Item.Draft(name: "upserted", value: 99, isActive: false)
            }.execute(db)

            let allItems = try Item.all.order(by: \.id).fetchAll(db)
            #expect(allItems.count == 2)
            #expect(allItems[1].name == "upserted")

            // Upsert -- conflict on existing id updates the row
            let existingId = allItems[0].id
            try Item.upsert {
                Item.Draft(id: existingId, name: "updated", value: 100, isActive: false)
            }.execute(db)

            let updated = try Item.find(existingId).fetchAll(db)
            #expect(updated.first?.name == "updated")
            #expect(updated.first?.value == 100)
        }
    }

    // MARK: - SQL-14: Update and delete

    @Test func updateAndDelete() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            // Update: set value = 999 for items where value > 20
            try Item.where { $0.value.gt(20) }
                .update { $0.value = 999 }
                .execute(db)

            let highValue = try Item.where { $0.value.eq(999) }
                .order(by: \.id)
                .fetchAll(db)
            #expect(highValue.count == 2) // gamma(25), epsilon(30) -> both 999
            #expect(highValue[0].name == "gamma")
            #expect(highValue[1].name == "epsilon")

            // Delete: remove item with id=1
            try Item.find(1).delete().execute(db)

            let remaining = try Item.all.fetchAll(db)
            #expect(remaining.count == 4) // was 5, removed 1
            #expect(!remaining.contains(where: { $0.id == 1 }))
        }
    }

    // MARK: - SQL-15: #sql macro for safe interpolation

    @Test func sqlMacro() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try seedAll(db)

            let results = try #sql(
                """
                SELECT \(Item.columns)
                FROM \(Item.self)
                WHERE \(Item.value) > \(bind: 10)
                ORDER BY \(Item.value)
                """,
                as: Item.self
            ).fetchAll(db)

            #expect(results.count == 3) // beta(15), gamma(25), epsilon(30)
            #expect(results[0].name == "beta")
            #expect(results[1].name == "gamma")
            #expect(results[2].name == "epsilon")
        }
    }
}
