#if !SKIP
import ComposableArchitecture
import ConcurrencyExtras
import Dependencies
import Foundation
import SQLiteData
import Testing
@testable import SQLFeature

typealias SQLReducer = SQLFeature

// MARK: - SQLFeature Database Integration Tests

@Suite(.serialized) @MainActor
struct SQLFeatureDatabaseTests {

    /// Verify database bootstrap and schema work with v4 migration (pinnedAt column)
    @Test func databaseBootstrapAndSchema() async throws {
        try await withDependencies {
            try $0.bootstrapDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            try await database.write { db in
                try SQLItem.insert {
                    SQLItem.Draft(name: "Test", date: Date(), sortOrder: 100.0)
                }.execute(db)
            }
            let items = try await database.read { db in
                try SQLItem.fetchAll(db)
            }
            #expect(items.count == 1)
            #expect(items[0].name == "Test")
            #expect(items[0].pinnedAt == nil)
            #expect(items[0].isPinned == false)
        }
    }

    /// Verify insert + fetchAll round-trip via database
    @Test func insertAndFetchAll() async throws {
        try await withDependencies {
            try $0.bootstrapDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            try await database.write { db in
                try SQLItem.insert {
                    SQLItem.Draft(name: "Item A", date: Date(), sortOrder: 100.0)
                }.execute(db)
            }
            let items = try await database.read { db in
                try SQLItem.order { $0.sortOrder.desc() }.fetchAll(db)
            }
            #expect(items.count == 1)
            #expect(items[0].name == "Item A")
            #expect(items[0].pinnedAt == nil)
        }
    }

    /// Verify update (toggle pin) via database
    @Test func updateTogglePin() async throws {
        try await withDependencies {
            try $0.bootstrapDatabase()
        } operation: {
            @Dependency(\.defaultDatabase) var database
            try await database.write { db in
                try SQLItem.insert {
                    SQLItem.Draft(name: "Pin Me", date: Date(), sortOrder: 100.0)
                }.execute(db)
            }
            var items = try await database.read { db in
                try SQLItem.fetchAll(db)
            }
            #expect(items.count == 1)
            var item = items[0]
            item.pinnedAt = Date()
            let updatedItem = item
            try await database.write { db in
                try SQLItem.upsert { updatedItem }.execute(db)
            }
            items = try await database.read { db in
                try SQLItem.fetchAll(db)
            }
            #expect(items[0].isPinned == true)
            #expect(items[0].pinnedAt != nil)
        }
    }
}

// MARK: - SQLFeature Reducer Tests

@Suite(.serialized) @MainActor
struct SQLFeatureReducerTests {

    /// Verify .task loads items into state
    @Test func taskLoadsItems() async {
        let now = Date()
        let testItems: IdentifiedArrayOf<SQLItem> = [
            SQLItem(id: 1, name: "A", date: now, sortOrder: 100.0),
            SQLItem(id: 2, name: "B", date: now, sortOrder: 200.0, pinnedAt: now),
        ]
        let store = TestStore(initialState: SQLReducer.State()) {
            SQLReducer()
        } withDependencies: {
            $0.sqlClient.fetchAll = { Array(testItems) }
            $0.sqlClient.fetchStatements = { [] }
        }

        await store.send(.task)
        await store.receive(\.itemsLoaded) {
            $0.items = testItems
        }
        await store.receive(\.statementsUpdated)
    }

    /// Verify pinnedItems / unpinnedItems computed properties
    @Test func pinnedAndUnpinnedComputed() {
        let now = Date()
        var state = SQLReducer.State()
        state.items = [
            SQLItem(id: 1, name: "A", date: now, sortOrder: 100.0),
            SQLItem(id: 2, name: "B", date: now, sortOrder: 200.0, pinnedAt: now),
            SQLItem(id: 3, name: "C", date: now, sortOrder: 300.0),
        ]
        #expect(state.pinnedItems.count == 1)
        #expect(state.pinnedItems[0].id == 2)
        #expect(state.unpinnedItems.count == 2)
        #expect(state.unpinnedItems.map(\.id) == [1, 3])
    }

    /// Verify .createItemTapped generates next alphabetic name and inserts
    @Test func createItemTapped() async {
        let now = Date(timeIntervalSince1970: 1000)
        let existing = SQLItem(id: 1, name: "Item A", date: now, sortOrder: 100.0)
        var initialState = SQLReducer.State()
        initialState.items = [existing]
        let insertedDraft = LockIsolated<SQLItem.Draft?>(nil)
        let returnedB = SQLItem(id: 2, name: "Item B", date: now, sortOrder: 200.0)
        let store = TestStore(initialState: initialState) {
            SQLReducer()
        } withDependencies: {
            $0.date = .constant(now)
            $0.sqlClient.insert = { draft in insertedDraft.setValue(draft) }
            $0.sqlClient.fetchAll = { [existing, returnedB] }
            $0.sqlClient.fetchStatements = { ["INSERT INTO sqlItems ..."] }
        }

        await store.send(.createItemTapped)
        await store.receive(\.itemsLoaded) {
            $0.items = [existing, returnedB]
        }
        await store.receive(\.statementsUpdated) {
            $0.statements = ["INSERT INTO sqlItems ..."]
        }
        #expect(insertedDraft.value?.name == "Item B")
        #expect(insertedDraft.value?.sortOrder == 200.0)
    }

    /// Verify .deleteItem calls delete and reloads
    @Test func deleteItem() async {
        let deletedIds = LockIsolated<[Int64]?>(nil)
        let item = SQLItem(id: 42, name: "Doomed", date: Date(), sortOrder: 100.0)
        var state = SQLReducer.State()
        state.items = [item]

        let store = TestStore(initialState: state) {
            SQLReducer()
        } withDependencies: {
            $0.sqlClient.delete = { ids in deletedIds.setValue(ids) }
            $0.sqlClient.fetchAll = { [] }
            $0.sqlClient.fetchStatements = { [] }
        }

        await store.send(.deleteItem(id: 42))
        await store.receive(\.itemsLoaded) {
            $0.items = []
        }
        await store.receive(\.statementsUpdated)
        #expect(deletedIds.value == [42])
    }

    /// Verify .togglePinned toggles and reloads
    @Test func togglePinned() async {
        let itemDate = Date(timeIntervalSince1970: 2000)
        let pinnedDate = Date(timeIntervalSince1970: 3000)
        let item = SQLItem(id: 1, name: "Pin Test", date: itemDate, sortOrder: 100.0)
        var state = SQLReducer.State()
        state.items = [item]

        let updatedItem = LockIsolated<SQLItem?>(nil)
        let pinned = SQLItem(id: 1, name: "Pin Test", date: itemDate, sortOrder: 100.0, pinnedAt: pinnedDate)
        let store = TestStore(initialState: state) {
            SQLReducer()
        } withDependencies: {
            $0.date = .constant(pinnedDate)
            $0.sqlClient.update = { item in updatedItem.setValue(item) }
            $0.sqlClient.fetchAll = { [pinned] }
            $0.sqlClient.fetchStatements = { [] }
        }

        await store.send(.togglePinned(id: 1))
        await store.receive(\.itemsLoaded) {
            $0.items = [pinned]
        }
        await store.receive(\.statementsUpdated)
        #expect(updatedItem.value?.isPinned == true)
        #expect(updatedItem.value?.pinnedAt == pinnedDate)
    }

    /// Verify lastActionSQL filters transaction statements
    @Test func lastActionSQLFiltering() {
        var state = SQLReducer.State()
        state.statements = [
            "BEGIN IMMEDIATE TRANSACTION",
            "INSERT INTO sqlItems (name, date, sortOrder) VALUES ('A', 1000.0, 100.0)",
            "COMMIT TRANSACTION",
            "PRAGMA journal_mode",
            "SELECT * FROM sqlItems ORDER BY sortOrder DESC",
        ]
        #expect(state.lastActionSQL == "INSERT INTO sqlItems (name, date, sortOrder) VALUES ('A', 1000.0, 100.0)")
    }

    /// Verify .editButtonTapped toggles isEditing and clears selection on deactivate
    @Test func editButtonTapped() async {
        var state = SQLReducer.State()
        state.isEditing = false
        state.selection = [1, 2]
        let store = TestStore(initialState: state) { SQLReducer() }

        await store.send(.editButtonTapped) {
            $0.isEditing = true
        }
        await store.send(.editButtonTapped) {
            $0.isEditing = false
            $0.selection = []
        }
    }

    /// Verify .itemTapped presents the editor
    @Test func itemTapped() async {
        let now = Date()
        let item = SQLItem(id: 1, name: "Test", date: now, sortOrder: 100.0)
        var state = SQLReducer.State()
        state.items = [item]
        let store = TestStore(initialState: state) { SQLReducer() }

        await store.send(.itemTapped(item)) {
            $0.editor = SQLItemEditorFeature.State(item: item)
        }
    }

    /// Verify .editor(.dismiss) clears editor and reloads
    @Test func editorDismiss() async {
        let now = Date()
        let item = SQLItem(id: 1, name: "Test", date: now, sortOrder: 100.0)
        var state = SQLReducer.State()
        state.items = [item]
        state.editor = SQLItemEditorFeature.State(item: item)
        let store = TestStore(initialState: state) {
            SQLReducer()
        } withDependencies: {
            $0.sqlClient.fetchAll = { [item] }
            $0.sqlClient.fetchStatements = { [] }
        }

        await store.send(.editor(.dismiss)) {
            $0.editor = nil
        }
        await store.receive(\.itemsLoaded)
        await store.receive(\.statementsUpdated)
    }

    /// Verify .moveItems updates sortOrder for single-item moves and ignores multi-item moves
    @Test func moveItems() async {
        let now = Date()
        let items: IdentifiedArrayOf<SQLItem> = [
            SQLItem(id: 1, name: "A", date: now, sortOrder: 300.0),
            SQLItem(id: 2, name: "B", date: now, sortOrder: 200.0),
            SQLItem(id: 3, name: "C", date: now, sortOrder: 100.0),
        ]
        var state = SQLReducer.State()
        state.items = items
        let updatedItem = LockIsolated<SQLItem?>(nil)
        let store = TestStore(initialState: state) {
            SQLReducer()
        } withDependencies: {
            $0.sqlClient.update = { item in updatedItem.setValue(item) }
            $0.sqlClient.fetchAll = { Array(items) }
            $0.sqlClient.fetchStatements = { [] }
        }

        // Multi-item move is a no-op
        await store.send(.moveItems(from: [0, 1], to: 2))

        // Single-item move updates sort order
        await store.send(.moveItems(from: [0], to: 2))
        await store.receive(\.itemsLoaded)
        await store.receive(\.statementsUpdated)
        #expect(updatedItem.value?.id == 1)
    }

    /// Verify .deleteSelectedTapped deletes all selected items and resets state
    @Test func deleteSelectedTapped() async {
        let now = Date()
        let items: IdentifiedArrayOf<SQLItem> = [
            SQLItem(id: 1, name: "A", date: now, sortOrder: 100.0),
            SQLItem(id: 2, name: "B", date: now, sortOrder: 200.0),
        ]
        var state = SQLReducer.State()
        state.items = items
        state.selection = [1, 2]
        state.isEditing = true
        let deletedIds = LockIsolated<[Int64]?>(nil)
        let store = TestStore(initialState: state) {
            SQLReducer()
        } withDependencies: {
            $0.sqlClient.delete = { ids in deletedIds.setValue(ids) }
            $0.sqlClient.fetchAll = { [] }
            $0.sqlClient.fetchStatements = { [] }
        }

        await store.send(.deleteSelectedTapped) {
            $0.selection = []
            $0.isEditing = false
        }
        await store.receive(\.itemsLoaded) { $0.items = [] }
        await store.receive(\.statementsUpdated)
        #expect(Set(deletedIds.value ?? []) == [1, 2])
    }

    /// Verify .pinSelectedTapped calls batchTogglePin with correct toPin/toUnpin splits
    @Test func pinSelectedTapped() async {
        let now = Date(timeIntervalSince1970: 1000)
        let pinDate = Date(timeIntervalSince1970: 2000)
        let items: IdentifiedArrayOf<SQLItem> = [
            SQLItem(id: 1, name: "A", date: now, sortOrder: 100.0),
            SQLItem(id: 2, name: "B", date: now, sortOrder: 200.0, pinnedAt: now),
        ]
        var state = SQLReducer.State()
        state.items = items
        state.selection = [1, 2]
        state.isEditing = true
        let capturedToPin = LockIsolated<[Int64]>([])
        let capturedToUnpin = LockIsolated<[Int64]>([])
        let store = TestStore(initialState: state) {
            SQLReducer()
        } withDependencies: {
            $0.date = .constant(pinDate)
            $0.sqlClient.batchTogglePin = { toPin, toUnpin, _ in
                capturedToPin.setValue(toPin)
                capturedToUnpin.setValue(toUnpin)
            }
            $0.sqlClient.fetchAll = { Array(items) }
            $0.sqlClient.fetchStatements = { [] }
        }

        await store.send(.pinSelectedTapped) {
            $0.selection = []
            $0.isEditing = false
        }
        await store.receive(\.itemsLoaded)
        await store.receive(\.statementsUpdated)
        #expect(capturedToPin.value == [1])
        #expect(capturedToUnpin.value == [2])
    }
}
#endif
