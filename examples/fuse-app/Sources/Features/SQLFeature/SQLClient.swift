// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import Dependencies
import DependenciesMacros
import Foundation
import SkipFuse

private let logger = Logger(subsystem: "dev.jacobcx.fuseApp", category: "SQLClient")

@DependencyClient
public struct SQLClient: Sendable {
    public var fetchAll: @Sendable () async throws -> [SQLItem] = { [] }
    public var insert: @Sendable (_ draft: SQLItem.Draft) async throws -> Void
    public var update: @Sendable (_ item: SQLItem) async throws -> Void
    public var delete: @Sendable (_ ids: [Int64]) async throws -> Void
    public var batchTogglePin: @Sendable (
        _ toPin: [Int64], _ toUnpin: [Int64], _ date: Date
    ) async throws -> Void
    public var fetchStatements: @Sendable () async -> [String] = { [] }
}

extension SQLClient: DependencyKey {
    public static var liveValue: Self {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.statementLog) var statementLog
        logger.debug("SQLClient.liveValue: creating client")
        return Self(
            fetchAll: {
                logger.debug("SQLClient.fetchAll: starting")
                let result = try await database.read { db in
                    try SQLItem
                        .order { $0.sortOrder.desc() }
                        .fetchAll(db)
                }
                logger.debug("SQLClient.fetchAll: returned \(result.count) items")
                return result
            },
            insert: { draft in
                logger.debug("SQLClient.insert: starting")
                try await database.write { db in
                    try SQLItem.insert { draft }.execute(db)
                }
                logger.debug("SQLClient.insert: done")
            },
            update: { item in
                logger.debug("SQLClient.update: id=\(item.id)")
                try await database.write { db in
                    try SQLItem.upsert { item }.execute(db)
                }
                logger.debug("SQLClient.update: done")
            },
            delete: { ids in
                logger.debug("SQLClient.delete: ids=\(ids)")
                try await database.write { db in
                    try SQLItem.find(ids).delete().execute(db)
                }
                logger.debug("SQLClient.delete: done")
            },
            batchTogglePin: { toPin, toUnpin, date in
                logger.debug("SQLClient.batchTogglePin: pin=\(toPin) unpin=\(toUnpin)")
                try await database.write { db in
                    if !toPin.isEmpty {
                        try SQLItem.find(toPin).update { $0.pinnedAt = date }.execute(db)
                    }
                    if !toUnpin.isEmpty {
                        try SQLItem.find(toUnpin).update { $0.pinnedAt = nil }.execute(db)
                    }
                }
                logger.debug("SQLClient.batchTogglePin: done")
            },
            fetchStatements: {
                let stmts = statementLog.statements
                logger.debug("SQLClient.fetchStatements: \(stmts.count) statements")
                return stmts
            }
        )
    }
}

extension DependencyValues {
    public var sqlClient: SQLClient {
        get { self[SQLClient.self] }
        set { self[SQLClient.self] = newValue }
    }
}
