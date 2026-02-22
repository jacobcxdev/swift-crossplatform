import XCTest
import SQLiteData
import Dependencies
import DependenciesTestSupport
import StructuredQueries

// MARK: - @Table model (must be file-scope for macro expansion)

@Table
struct Item: Identifiable, Equatable, Sendable {
    @Column(primaryKey: true)
    var id: Int
    var name: String
    var value: Int
    var isActive: Bool
}

// MARK: - Test Suite

final class SQLiteDataTests: XCTestCase {

    // MARK: - Helpers

    private func setupSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE "items" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "name" TEXT NOT NULL DEFAULT '',
                "value" INTEGER NOT NULL DEFAULT 0,
                "isActive" BOOLEAN NOT NULL DEFAULT 1
            )
            """)
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
            try Item.insert {
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
                try db.execute(sql: """
                    CREATE TABLE "test" ("id" INTEGER PRIMARY KEY)
                    """)
            }
            let count = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM test")
            }
            XCTAssertEqual(count, 0)
        }

        // Test DatabaseQueue() in-memory fallback
        let inMemory = try DatabaseQueue()
        try inMemory.write { db in
            try db.execute(sql: """
                CREATE TABLE "test2" ("id" INTEGER PRIMARY KEY)
                """)
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
            try db.execute(sql: """
                CREATE TABLE "items" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    "name" TEXT NOT NULL DEFAULT '',
                    "value" INTEGER NOT NULL DEFAULT 0,
                    "isActive" BOOLEAN NOT NULL DEFAULT 1
                )
                """)
        }
        try migrator.migrate(dbQueue)

        // Verify table exists by inserting and reading
        try dbQueue.write { db in
            try Item.insert {
                Item.Draft(name: "migrated", value: 42, isActive: true)
            }.execute(db)
        }
        let items = try dbQueue.read { db in
            try Item.all.fetchAll(db)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "migrated")
    }

    // MARK: - SD-03: Sync read

    func testSyncRead() throws {
        let dbQueue = try makeSeededDatabase()

        let items = try dbQueue.read { db in
            try Item.all.order(by: \.id).fetchAll(db)
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
            try Item.insert {
                Item.Draft(name: "written", value: 99, isActive: true)
            }.execute(db)
        }

        // Verify data persists in subsequent read
        let items = try dbQueue.read { db in
            try Item.all.fetchAll(db)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "written")
        XCTAssertEqual(items[0].value, 99)
    }

    // MARK: - SD-05: Async read

    func testAsyncRead() async throws {
        let dbQueue = try makeSeededDatabase()

        let items = try await dbQueue.read { db in
            try Item.all.order(by: \.id).fetchAll(db)
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].name, "alpha")
    }

    // MARK: - SD-05: Async write

    func testAsyncWrite() async throws {
        let dbQueue = try makeDatabase()

        try await dbQueue.write { db in
            try Item.insert {
                Item.Draft(name: "async-written", value: 77, isActive: false)
            }.execute(db)
        }

        let items = try await dbQueue.read { db in
            try Item.all.fetchAll(db)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "async-written")
        XCTAssertEqual(items[0].value, 77)
    }

    // MARK: - SD-06: fetchAll

    func testFetchAll() throws {
        let dbQueue = try makeSeededDatabase()

        let allItems = try dbQueue.read { db in
            try Item.all.fetchAll(db)
        }
        XCTAssertEqual(allItems.count, 3)

        // Filtered fetchAll
        let activeItems = try dbQueue.read { db in
            try Item.where { $0.isActive }.fetchAll(db)
        }
        XCTAssertEqual(activeItems.count, 2)
        XCTAssertTrue(activeItems.allSatisfy { $0.isActive })
    }

    // MARK: - SD-07: fetchOne

    func testFetchOne() throws {
        let dbQueue = try makeSeededDatabase()

        // fetchOne returns first match
        let first = try dbQueue.read { db in
            try Item.find(1).fetchOne(db)
        }
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.name, "alpha")

        // fetchOne returns nil for no match
        let missing = try dbQueue.read { db in
            try Item.where { $0.name == "nonexistent" }.limit(1).fetchOne(db)
        }
        XCTAssertNil(missing)
    }

    // MARK: - SD-08: fetchCount

    func testFetchCount() throws {
        let dbQueue = try makeSeededDatabase()

        let totalCount = try dbQueue.read { db in
            try Item.all.fetchCount(db)
        }
        XCTAssertEqual(totalCount, 3)

        let activeCount = try dbQueue.read { db in
            try Item.where { $0.isActive }.fetchCount(db)
        }
        XCTAssertEqual(activeCount, 2)

        let inactiveCount = try dbQueue.read { db in
            try Item.where { !$0.isActive }.fetchCount(db)
        }
        XCTAssertEqual(inactiveCount, 1)
    }
}
