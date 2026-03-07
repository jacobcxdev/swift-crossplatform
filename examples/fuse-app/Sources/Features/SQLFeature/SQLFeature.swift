// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import Foundation
import SkipFuse

private let logger = Logger(subsystem: "dev.jacobcx.fuseApp", category: "SQLFeature")

@Reducer
public struct SQLFeature {
    @ObservableState
    public struct State: Equatable {
        public var items: IdentifiedArrayOf<SQLItem> = []
        public var statements: [String] = []
        @Presents public var editor: SQLItemEditorFeature.State?

        public init() {
            logger.debug("SQLFeature.State.init")
        }

        public var lastActionSQL: String? {
            statements.last { sql in
                !sql.hasPrefix("PRAGMA ") && !sql.hasPrefix("SELECT ")
            }
        }
    }

    public enum Action {
        case task
        case createItemTapped
        case deleteItems(offsets: [Int])
        case moveItems(from: [Int], to: Int)
        case itemTapped(SQLItem)
        case editor(PresentationAction<SQLItemEditorFeature.Action>)
        case itemsLoaded(IdentifiedArrayOf<SQLItem>)
        case statementsUpdated([String])
    }

    @Dependency(\.sqlClient) var sqlClient
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                logger.debug("reducer: .task")
                return .run { [sqlClient] send in
                    logger.debug("reducer: .task effect: fetching items")
                    let items = try await sqlClient.fetchAll()
                    logger.debug("reducer: .task effect: loaded \(items.count) items")
                    for item in items.prefix(3) {
                        logger.debug("reducer: .task effect: sample item id=\(item.id) name=\(item.name)")
                    }
                    let identified = IdentifiedArrayOf(uniqueElements: items)
                    logger.debug("reducer: .task effect: IdentifiedArrayOf count=\(identified.count)")
                    await send(.itemsLoaded(identified))
                    logger.debug("reducer: .task effect: sent .itemsLoaded")
                    let statements = await sqlClient.fetchStatements()
                    logger.debug("reducer: .task effect: fetched \(statements.count) statements")
                    await send(.statementsUpdated(statements))
                    logger.debug("reducer: .task effect: sent .statementsUpdated")
                } catch: { error, _ in
                    logger.error("reducer: .task effect FAILED: \(error)")
                }

            case .createItemTapped:
                let currentCount = state.items.count
                logger.debug("reducer: .createItemTapped, current items.count=\(currentCount)")
                let maxSort = state.items.compactMap(\.sortOrder).max() ?? 0.0
                let draft = SQLItem.Draft(name: "", date: date.now, sortOrder: maxSort + 100.0)
                return .run { [sqlClient, draft] send in
                    logger.debug("reducer: .createItemTapped effect: inserting")
                    try await sqlClient.insert(draft)
                    logger.debug("reducer: .createItemTapped effect: inserted, fetching")
                    let items = try await sqlClient.fetchAll()
                    logger.debug("reducer: .createItemTapped effect: fetched \(items.count) items")
                    await send(.itemsLoaded(IdentifiedArrayOf(uniqueElements: items)))
                    let statements = await sqlClient.fetchStatements()
                    await send(.statementsUpdated(statements))
                    logger.debug("reducer: .createItemTapped effect: done")
                } catch: { error, _ in
                    logger.error("reducer: .createItemTapped effect FAILED: \(error)")
                }

            case .deleteItems(let offsets):
                logger.debug("reducer: .deleteItems offsets=\(offsets)")
                let ids = offsets.map { state.items[$0].id }
                return .run { [sqlClient, ids] send in
                    try await sqlClient.delete(ids)
                    let items = try await sqlClient.fetchAll()
                    await send(.itemsLoaded(IdentifiedArrayOf(uniqueElements: items)))
                    let statements = await sqlClient.fetchStatements()
                    await send(.statementsUpdated(statements))
                } catch: { error, _ in
                    logger.error("reducer: .deleteItems effect FAILED: \(error)")
                }

            case .moveItems(let from, let to):
                logger.debug("reducer: .moveItems from=\(from) to=\(to)")
                let items = state.items
                return .run { [sqlClient, items] send in
                    for index in from {
                        var item = items[index]
                        let orderOffset = 100.0
                        let nextOrder = to == items.count
                            ? 0.0 : items[to].sortOrder ?? 0.0
                        let prevOrder = to == 0
                            ? 0.0 : items[to - 1].sortOrder ?? 0.0
                        item.sortOrder = to == 0
                            ? (nextOrder + orderOffset)
                            : to == items.count
                                ? (prevOrder - orderOffset)
                                : (nextOrder + ((prevOrder - nextOrder) / 2.0))
                        try await sqlClient.update(item)
                    }
                    let updatedItems = try await sqlClient.fetchAll()
                    await send(.itemsLoaded(IdentifiedArrayOf(uniqueElements: updatedItems)))
                    let statements = await sqlClient.fetchStatements()
                    await send(.statementsUpdated(statements))
                } catch: { error, _ in
                    logger.error("reducer: .moveItems effect FAILED: \(error)")
                }

            case .itemTapped(let item):
                logger.debug("reducer: .itemTapped id=\(item.id)")
                state.editor = SQLItemEditorFeature.State(item: item)
                return .none

            case .editor(.dismiss):
                logger.debug("reducer: .editor(.dismiss)")
                return .run { [sqlClient] send in
                    let items = try await sqlClient.fetchAll()
                    await send(.itemsLoaded(IdentifiedArrayOf(uniqueElements: items)))
                    let statements = await sqlClient.fetchStatements()
                    await send(.statementsUpdated(statements))
                } catch: { error, _ in
                    logger.error("reducer: .editor(.dismiss) effect FAILED: \(error)")
                }

            case .editor:
                return .none

            case .itemsLoaded(let items):
                let prevCount = state.items.count
                logger.debug("reducer: .itemsLoaded count=\(items.count), prev count=\(prevCount)")
                state.items = items
                let newCount = state.items.count
                logger.debug("reducer: .itemsLoaded state.items.count now=\(newCount)")
                return .none

            case .statementsUpdated(let statements):
                logger.debug("reducer: .statementsUpdated count=\(statements.count)")
                state.statements = statements
                return .none
            }
        }
        .ifLet(\.$editor, action: \.editor) {
            SQLItemEditorFeature()
        }
    }
}
