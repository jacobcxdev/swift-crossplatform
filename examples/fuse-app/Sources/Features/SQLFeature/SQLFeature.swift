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
        public var isEditing = false
        public var selection: Set<SQLItem.ID> = []
        @Presents public var editor: SQLItemEditorFeature.State?

        public init() {
            logger.debug("SQLFeature.State.init")
        }

        public var pinnedItems: [SQLItem] {
            items.elements.filter(\.isPinned)
        }

        public var unpinnedItems: [SQLItem] {
            items.elements.filter { !$0.isPinned }
        }

        public var lastActionSQL: String? {
            statements.last { sql in
                // GRDB .profile trace prepends "X.XXXs " (e.g. "0.001s INSERT...")
                // Strip the timing prefix before checking SQL keyword prefixes.
                let body: Substring
                if let sIdx = sql.firstIndex(of: "s"),
                   sIdx > sql.startIndex,
                   sql[sql.startIndex..<sIdx].allSatisfy({ $0.isNumber || $0 == "." }),
                   let start = sql.index(sIdx, offsetBy: 2, limitedBy: sql.endIndex) {
                    body = sql[start...]
                } else {
                    body = sql[...]
                }
                return !body.hasPrefix("PRAGMA ")
                    && !body.hasPrefix("SELECT ")
                    && !body.hasPrefix("BEGIN ")
                    && !body.hasPrefix("COMMIT")
                    && !body.hasPrefix("ROLLBACK")
            }
        }
    }

    public enum Action {
        case task
        case createItemTapped
        case deleteItem(id: SQLItem.ID)
        case togglePinned(id: SQLItem.ID)
        case moveItems(from: [Int], to: Int)
        case itemTapped(SQLItem)
        case editButtonTapped
        case selectionChanged(Set<SQLItem.ID>)
        case deleteSelectedTapped
        case pinSelectedTapped
        case editor(PresentationAction<SQLItemEditorFeature.Action>)
        case itemsLoaded(IdentifiedArrayOf<SQLItem>)
        case statementsUpdated([String])
    }

    @Dependency(\.sqlClient) var sqlClient
    @Dependency(\.date) var date

    public init() {}

    private static func alphabeticLabel(for index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var result = ""
        var n = index
        repeat {
            result = String(alphabet[n % 26]) + result
            n = n / 26 - 1
        } while n >= 0
        return "Item \(result)"
    }

    private static func refresh(
        sqlClient: SQLClient,
        send: Send<Action>,
        animated: Bool = false
    ) async throws {
        let items = try await sqlClient.fetchAll()
        if animated {
            await send(.itemsLoaded(IdentifiedArrayOf(uniqueElements: items)), animation: .default)
        } else {
            await send(.itemsLoaded(IdentifiedArrayOf(uniqueElements: items)))
        }
        let statements = await sqlClient.fetchStatements()
        await send(.statementsUpdated(statements))
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                logger.debug("reducer: .task")
                return .run { [sqlClient] send in
                    try await Self.refresh(sqlClient: sqlClient, send: send)
                } catch: { error, _ in
                    logger.error("reducer: .task effect FAILED: \(error)")
                }

            case .createItemTapped:
                let currentCount = state.items.count
                logger.debug("reducer: .createItemTapped, current items.count=\(currentCount)")
                let existingNames = Set(state.items.map(\.name))
                var index = currentCount
                var name = Self.alphabeticLabel(for: index)
                while existingNames.contains(name) {
                    index += 1
                    name = Self.alphabeticLabel(for: index)
                }
                let maxSort = state.items.compactMap(\.sortOrder).max() ?? 0.0
                let draft = SQLItem.Draft(name: name, date: date.now, sortOrder: maxSort + 100.0)
                return .run { [sqlClient, draft] send in
                    try await sqlClient.insert(draft)
                    try await Self.refresh(sqlClient: sqlClient, send: send, animated: true)
                } catch: { error, _ in
                    logger.error("reducer: .createItemTapped effect FAILED: \(error)")
                }

            case .deleteItem(let id):
                logger.debug("reducer: .deleteItem id=\(id)")
                return .run { [sqlClient] send in
                    try await sqlClient.delete([id])
                    try await Self.refresh(sqlClient: sqlClient, send: send, animated: true)
                } catch: { error, _ in
                    logger.error("reducer: .deleteItem effect FAILED: \(error)")
                }

            case .togglePinned(let id):
                logger.debug("reducer: .togglePinned id=\(id)")
                guard var item = state.items[id: id] else { return .none }
                item.pinnedAt = item.pinnedAt == nil ? date.now : nil
                return .run { [sqlClient, item] send in
                    try await sqlClient.update(item)
                    try await Self.refresh(sqlClient: sqlClient, send: send, animated: true)
                } catch: { error, _ in
                    logger.error("reducer: .togglePinned effect FAILED: \(error)")
                }

            case .moveItems(let from, let to):
                logger.debug("reducer: .moveItems from=\(from) to=\(to)")
                guard from.count == 1, let sourceIndex = from.first else {
                    logger.warning("reducer: .moveItems ignoring multi-item move")
                    return .none
                }
                let items = state.unpinnedItems
                guard sourceIndex < items.count else { return .none }
                var item = items[sourceIndex]
                let orderOffset = 100.0
                let nextOrder = to == items.count ? 0.0 : items[to].sortOrder ?? 0.0
                let prevOrder = to == 0 ? 0.0 : items[to - 1].sortOrder ?? 0.0
                item.sortOrder = to == 0
                    ? (nextOrder + orderOffset)
                    : to == items.count
                        ? (prevOrder - orderOffset)
                        : (nextOrder + ((prevOrder - nextOrder) / 2.0))
                return .run { [sqlClient, item] send in
                    try await sqlClient.update(item)
                    try await Self.refresh(sqlClient: sqlClient, send: send)
                } catch: { error, _ in
                    logger.error("reducer: .moveItems effect FAILED: \(error)")
                }

            case .editButtonTapped:
                state.isEditing.toggle()
                if !state.isEditing {
                    state.selection = []
                }
                return .none

            case .selectionChanged(let selection):
                logger.debug("reducer: .selectionChanged count=\(selection.count) ids=\(selection)")
                state.selection = selection
                return .none

            case .deleteSelectedTapped:
                let ids = Array(state.selection)
                state.selection = []
                state.isEditing = false
                return .run { [sqlClient, ids] send in
                    try await sqlClient.delete(ids)
                    try await Self.refresh(sqlClient: sqlClient, send: send, animated: true)
                } catch: { error, _ in
                    logger.error("reducer: .deleteSelectedTapped effect FAILED: \(error)")
                }

            case .pinSelectedTapped:
                let selectedItems = state.selection.compactMap { state.items[id: $0] }
                let now = date.now
                state.selection = []
                state.isEditing = false
                let toPin = selectedItems.filter { !$0.isPinned }.map(\.id)
                let toUnpin = selectedItems.filter(\.isPinned).map(\.id)
                return .run { [sqlClient] send in
                    try await sqlClient.batchTogglePin(toPin, toUnpin, now)
                    try await Self.refresh(sqlClient: sqlClient, send: send, animated: true)
                } catch: { error, _ in
                    logger.error("reducer: .pinSelectedTapped effect FAILED: \(error)")
                }

            case .itemTapped(let item):
                logger.debug("reducer: .itemTapped id=\(item.id)")
                state.editor = SQLItemEditorFeature.State(item: item)
                return .none

            case .editor(.dismiss):
                logger.debug("reducer: .editor(.dismiss)")
                return .run { [sqlClient] send in
                    try await Self.refresh(sqlClient: sqlClient, send: send)
                } catch: { error, _ in
                    logger.error("reducer: .editor(.dismiss) effect FAILED: \(error)")
                }

            case .editor:
                return .none

            case .itemsLoaded(let items):
                logger.debug("reducer: .itemsLoaded count=\(items.count)")
                state.items = items
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
