import ComposableArchitecture
import Dependencies
import GRDB
import SQLiteData
import StructuredQueries
import StructuredQueriesSQLite
import SwiftUI

// MARK: - Database Setup

extension DatabaseQueue: @unchecked @retroactive Sendable {}

private func createAppDatabase() throws -> DatabaseQueue {
    let path = URL.applicationSupportDirectory.appendingPathComponent("fuse-app.sqlite").path
    try FileManager.default.createDirectory(
        at: URL.applicationSupportDirectory,
        withIntermediateDirectories: true
    )
    let db = try DatabaseQueue(path: path)

    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS note (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL DEFAULT '',
                body TEXT NOT NULL DEFAULT '',
                category TEXT NOT NULL DEFAULT 'general',
                createdAt REAL NOT NULL DEFAULT 0
            )
            """)
    }
    try migrator.migrate(db)
    return db
}

// MARK: - Database Dependency

private enum AppDatabaseKey: DependencyKey {
    static let liveValue: DatabaseQueue = {
        do {
            return try createAppDatabase()
        } catch {
            fatalError("Failed to create database: \(error)")
        }
    }()
    static var testValue: DatabaseQueue {
        try! DatabaseQueue()
    }
}

extension DependencyValues {
    var appDatabase: DatabaseQueue {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}

// MARK: - DatabaseFeature Reducer

@Reducer
struct DatabaseFeature {
    @ObservableState
    struct State: Equatable {
        var notes: [Note] = []
        var selectedCategory: String = "all"
        var noteCount: Int = 0
        var isLoading = false
    }

    enum Action {
        case onAppear
        case addNoteTapped
        case deleteNote(Int64)
        case toggleCategory(String)
        case notesLoaded([Note])
        case noteCountLoaded(Int)
        case noteAdded(Note)
        case noteDeleted(Int64)
    }

    @Dependency(\.appDatabase) var database
    @Dependency(\.date) var date

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
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

            case let .deleteNote(id):
                return .run { send in
                    try await database.write { db in
                        try Note.find(id).delete().execute(db)
                    }
                    await send(.noteDeleted(id))
                }

            case let .toggleCategory(category):
                state.selectedCategory = category
                return .none

            case let .notesLoaded(notes):
                state.notes = notes
                state.isLoading = false
                return .none

            case let .noteCountLoaded(count):
                state.noteCount = count
                return .none

            case let .noteAdded(note):
                state.notes.insert(note, at: 0)
                state.noteCount += 1
                return .none

            case let .noteDeleted(id):
                state.notes.removeAll { $0.id == id }
                state.noteCount -= 1
                return .none
            }
        }
    }
}

// MARK: - DatabaseView

struct DatabaseView: View {
    let store: StoreOf<DatabaseFeature>

    private let categories = ["all", "general", "work", "personal"]

    var body: some View {
        List {
            Section("Filter") {
                Picker("Category", selection: Binding(
                    get: { store.selectedCategory },
                    set: { store.send(.toggleCategory($0)) }
                )) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat.capitalized).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Notes (\(store.noteCount))") {
                if store.isLoading {
                    ProgressView()
                } else if filteredNotes.isEmpty {
                    Text("No notes yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredNotes) { note in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title)
                                    .font(.headline)
                                HStack {
                                    Text(note.category)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.secondary.opacity(0.2))
                                        .clipShape(Capsule())
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: note.createdAt), style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button {
                                store.send(.deleteNote(note.id))
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Database")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.send(.addNoteTapped) } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .task { store.send(.onAppear) }
    }

    private var filteredNotes: [Note] {
        if store.selectedCategory == "all" {
            return store.notes
        }
        return store.notes.filter { $0.category == store.selectedCategory }
    }
}
