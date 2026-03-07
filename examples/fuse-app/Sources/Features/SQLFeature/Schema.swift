// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import Dependencies
import Foundation
import SQLiteData
import StructuredQueries

@Table
public struct SQLItem: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name = ""
    public var date: Date = Date()
    public var sortOrder: Double?
}

extension SQLItem.Draft: Sendable {}

public final class StatementLog: @unchecked Sendable {
    private var _statements: [String] = []
    private let lock = NSLock()

    public var statements: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _statements
    }

    public func append(_ sql: String) {
        lock.lock()
        defer { lock.unlock() }
        _statements.append(sql)
    }
}

private enum StatementLogKey: DependencyKey {
    static let liveValue = StatementLog()
    static let testValue = StatementLog()
}

extension DependencyValues {
    public var statementLog: StatementLog {
        get { self[StatementLogKey.self] }
        set { self[StatementLogKey.self] = newValue }
    }
}

extension DependencyValues {
    public mutating func bootstrapDatabase() throws {
        let log = statementLog
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.trace { event in
                log.append(event.expandedDescription)
            }
        }
        let database = try SQLiteData.defaultDatabase(configuration: configuration)
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1") { db in
            try db.create(table: "sqlItems") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().defaults(to: "")
                t.column("date", .real).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "sqlItems") { t in
                t.add(column: "sortOrder", .real)
            }
        }
        try migrator.migrate(database)
        defaultDatabase = database
    }
}
