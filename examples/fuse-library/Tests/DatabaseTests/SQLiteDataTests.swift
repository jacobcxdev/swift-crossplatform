import XCTest
import SQLiteData
import DependenciesTestSupport

// MARK: - @Table model (must be file-scope for macro expansion)

@Table("items")
struct DataItem: Identifiable, Equatable, Sendable {
    @Column(primaryKey: true)
    let id: Int
    var name: String
    var value: Int
    var isActive: Bool
}

// MARK: - Test Suite

// TODO: Wave 4 — Migrate to Swift Testing @Suite with .dependencies { try $0.bootstrapDatabase() } trait
// This will replace the manual makeDatabase()/setupSchema() helpers with consistent bootstrap.
final class SQLiteDataTests: XCTestCase {

    // MARK: - Helpers

    private func setupSchema(_ db: Database) throws {
        try #sql(
            """
            CREATE TABLE "items" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "name" TEXT NOT NULL DEFAULT '',
                "value" INTEGER NOT NULL DEFAULT 0,
                "isActive" INTEGER NOT NULL DEFAULT 1
            ) STRICT
            """
        ).execute(db)
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try setupSchema(db)
        }
        return dbQueue
    }

    private func makeSeededDatabase() throws -> DatabaseQueue {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try DataItem.insert {
                ($0.name, $0.value, $0.isActive)
            } values: {
                ("alpha", 5, true)
                ("beta", 15, true)
                ("gamma", 25, false)
            }.execute(db)
        }
        return dbQueue
    }

    // MARK: - SD-01: Database initialization

    func testDatabaseInit() throws {
        // Test defaultDatabase() via withDependencies
        let testDB = try DatabaseQueue()
        try withDependencies {
            $0.defaultDatabase = testDB
        } operation: {
            @Dependency(\.defaultDatabase) var database
            // Verify the database is usable
            try database.write { db in
                try #sql(
                    """
                    CREATE TABLE "test" ("id" INTEGER PRIMARY KEY NOT NULL) STRICT
                    """
                ).execute(db)
            }
            let count = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM test")
            }
            XCTAssertEqual(count, 0)
        }

        // Test DatabaseQueue() in-memory fallback
        let inMemory = try DatabaseQueue()
        try inMemory.write { db in
            try #sql(
                """
                CREATE TABLE "test2" ("id" INTEGER PRIMARY KEY NOT NULL) STRICT
                """
            ).execute(db)
        }
        let count2 = try inMemory.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM test2")
        }
        XCTAssertEqual(count2, 0)
    }

    // MARK: - SD-02: DatabaseMigrator

    func testDatabaseMigrator() throws {
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try #sql(
                """
                CREATE TABLE "items" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    "name" TEXT NOT NULL DEFAULT '',
                    "value" INTEGER NOT NULL DEFAULT 0,
                    "isActive" INTEGER NOT NULL DEFAULT 1
                ) STRICT
                """
            ).execute(db)
        }
        try migrator.migrate(dbQueue)

        // Verify table exists by inserting and reading
        try dbQueue.write { db in
            try DataItem.insert {
                DataItem.Draft(name: "migrated", value: 42, isActive: true)
            }.execute(db)
        }
        let items = try dbQueue.read { db in
            try DataItem.all.fetchAll(db)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "migrated")
    }

    // MARK: - SD-03: Sync read

    func testSyncRead() throws {
        let dbQueue = try makeSeededDatabase()

        let items = try dbQueue.read { db in
            try DataItem.all.order(by: \.id).fetchAll(db)
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].name, "alpha")
        XCTAssertEqual(items[1].name, "beta")
        XCTAssertEqual(items[2].name, "gamma")
    }

    // MARK: - SD-04: Sync write

    func testSyncWrite() throws {
        let dbQueue = try makeDatabase()

        try dbQueue.write { db in
            try DataItem.insert {
                DataItem.Draft(name: "written", value: 99, isActive: true)
            }.execute(db)
        }

        // Verify data persists in subsequent read
        let items = try dbQueue.read { db in
            try DataItem.all.fetchAll(db)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "written")
        XCTAssertEqual(items[0].value, 99)
    }

    // MARK: - SD-05: Async read

    func testAsyncRead() async throws {
        let dbQueue = try makeSeededDatabase()

        let items = try await dbQueue.read { db in
            try DataItem.all.order(by: \.id).fetchAll(db)
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].name, "alpha")
    }

    // MARK: - SD-05: Async write

    func testAsyncWrite() async throws {
        let dbQueue = try makeDatabase()

        try await dbQueue.write { db in
            try DataItem.insert {
                DataItem.Draft(name: "async-written", value: 77, isActive: false)
            }.execute(db)
        }

        let items = try await dbQueue.read { db in
            try DataItem.all.fetchAll(db)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "async-written")
        XCTAssertEqual(items[0].value, 77)
    }

    // MARK: - SD-06: fetchAll

    func testFetchAll() throws {
        let dbQueue = try makeSeededDatabase()

        let allItems = try dbQueue.read { db in
            try DataItem.all.fetchAll(db)
        }
        XCTAssertEqual(allItems.count, 3)

        // Filtered fetchAll
        let activeItems = try dbQueue.read { db in
            try DataItem.where { $0.isActive }.fetchAll(db)
        }
        XCTAssertEqual(activeItems.count, 2)
        XCTAssertTrue(activeItems.allSatisfy { $0.isActive })
    }

    // MARK: - SD-07: fetchOne

    func testFetchOne() throws {
        let dbQueue = try makeSeededDatabase()

        // fetchOne returns first match
        let first = try dbQueue.read { db in
            try DataItem.find(1).fetchOne(db)
        }
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.name, "alpha")

        // fetchOne returns nil for no match
        let missing = try dbQueue.read { db in
            try DataItem.where { $0.name.eq("nonexistent") }.limit(1).fetchOne(db)
        }
        XCTAssertNil(missing)
    }

    // MARK: - SD-08: fetchCount

    func testFetchCount() throws {
        let dbQueue = try makeSeededDatabase()

        let totalCount = try dbQueue.read { db in
            try DataItem.all.fetchCount(db)
        }
        XCTAssertEqual(totalCount, 3)

        let activeCount = try dbQueue.read { db in
            try DataItem.where { $0.isActive }.fetchCount(db)
        }
        XCTAssertEqual(activeCount, 2)

        let inactiveCount = try dbQueue.read { db in
            try DataItem.where { !$0.isActive }.fetchCount(db)
        }
        XCTAssertEqual(inactiveCount, 1)
    }

    // MARK: - SD-09: @FetchAll observation via ValueObservation

    @MainActor
    func testFetchAllObservation() async throws {
        let dbQueue = try makeDatabase()

        let observation = ValueObservation.tracking { db in
            try DataItem.all.order(by: \.id).fetchAll(db)
        }

        let expectation = XCTestExpectation(description: "observation triggers on insert")
        var observedValues: [[DataItem]] = []

        let cancellable = observation.start(in: dbQueue, onError: { _ in }, onChange: { items in
            observedValues.append(items)
            if observedValues.count >= 2 {
                expectation.fulfill()
            }
        })

        // Initial value should be empty array
        try await Task.sleep(for: .milliseconds(100))

        // Mutate database — should trigger onChange
        try await dbQueue.write { db in
            try DataItem.insert {
                DataItem.Draft(name: "observed", value: 42, isActive: true)
            }.execute(db)
        }

        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()

        XCTAssertGreaterThanOrEqual(observedValues.count, 2)
        XCTAssertEqual(observedValues.first?.count, 0) // initial empty
        XCTAssertEqual(observedValues.last?.count, 1)  // after insert
        XCTAssertEqual(observedValues.last?.first?.name, "observed")
    }

    // MARK: - SD-10: @FetchOne observation via ValueObservation

    @MainActor
    func testFetchOneObservation() async throws {
        let dbQueue = try makeDatabase()

        let observation = ValueObservation.tracking { db in
            try DataItem.all.limit(1).fetchOne(db)
        }

        let expectation = XCTestExpectation(description: "observation triggers for single row")
        var observedValues: [DataItem?] = []

        let cancellable = observation.start(in: dbQueue, onError: { _ in }, onChange: { item in
            observedValues.append(item)
            if observedValues.count >= 2 {
                expectation.fulfill()
            }
        })

        try await Task.sleep(for: .milliseconds(100))

        // Insert a row — should trigger onChange
        try await dbQueue.write { db in
            try DataItem.insert {
                DataItem.Draft(name: "single", value: 10, isActive: true)
            }.execute(db)
        }

        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()

        XCTAssertGreaterThanOrEqual(observedValues.count, 2)
        XCTAssertNil(observedValues.first!) // initial: no rows
        XCTAssertEqual(observedValues.last??.name, "single")
    }

    // MARK: - SD-11: @Fetch composite observation via ValueObservation

    @MainActor
    func testFetchCompositeObservation() async throws {
        let dbQueue = try makeDatabase()

        // Composite observation: fetch count + filtered items in single tracking block
        let observation = ValueObservation.tracking { db -> (Int, [DataItem]) in
            let count = try DataItem.all.fetchCount(db)
            let activeItems = try DataItem.where { $0.isActive }.order(by: \.id).fetchAll(db)
            return (count, activeItems)
        }

        let expectation = XCTestExpectation(description: "composite observation triggers")
        var observedValues: [(Int, [DataItem])] = []

        let cancellable = observation.start(in: dbQueue, onError: { _ in }, onChange: { value in
            observedValues.append(value)
            if observedValues.count >= 2 {
                expectation.fulfill()
            }
        })

        try await Task.sleep(for: .milliseconds(100))

        // Insert mixed active/inactive rows
        try await dbQueue.write { db in
            try DataItem.insert {
                ($0.name, $0.value, $0.isActive)
            } values: {
                ("active1", 1, true)
                ("inactive1", 2, false)
                ("active2", 3, true)
            }.execute(db)
        }

        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()

        XCTAssertGreaterThanOrEqual(observedValues.count, 2)
        // Initial: count=0, activeItems=[]
        XCTAssertEqual(observedValues.first?.0, 0)
        XCTAssertEqual(observedValues.first?.1.count, 0)
        // After insert: count=3, activeItems=2
        XCTAssertEqual(observedValues.last?.0, 3)
        XCTAssertEqual(observedValues.last?.1.count, 2)
        XCTAssertEqual(observedValues.last?.1.first?.name, "active1")
    }

    // MARK: - SD-12: @Dependency(\.defaultDatabase) injection

    func testDefaultDatabaseDependency() throws {
        let testDB = try makeDatabase()

        try withDependencies {
            $0.defaultDatabase = testDB
        } operation: {
            @Dependency(\.defaultDatabase) var database

            // Write through dependency-injected database
            try database.write { db in
                try DataItem.insert {
                    DataItem.Draft(name: "injected", value: 55, isActive: true)
                }.execute(db)
            }

            // Read through dependency-injected database
            let count = try database.read { db in
                try DataItem.all.fetchCount(db)
            }
            XCTAssertEqual(count, 1)

            let items = try database.read { db in
                try DataItem.all.fetchAll(db)
            }
            XCTAssertEqual(items.first?.name, "injected")
        }
    }
}
