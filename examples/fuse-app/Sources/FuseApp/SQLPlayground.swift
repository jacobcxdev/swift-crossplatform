// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from skipapp-showcase-fuse SQLPlayground.swift
// Note: SkipSQLPlus is not available in fuse-app dependencies.
// This is a self-contained in-memory demonstration using Foundation types.

import SwiftUI

// MARK: - SQLPlayground

struct SQLPlayground: View {
    @State var database = SQLPlaygroundDatabase()

    var body: some View {
        SQLPlaygroundListView(database: $database)
    }
}

// MARK: - SQLPlaygroundItem

struct SQLPlaygroundItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var date: Date
    var sortOrder: Double

    init(id: UUID = UUID(), name: String = "", date: Date = Date(), sortOrder: Double = 0) {
        self.id = id
        self.name = name
        self.date = date
        self.sortOrder = sortOrder
    }
}

// MARK: - SQLPlaygroundDatabase

/// A simple in-memory item store that mimics the upstream SQLPlayground's CRUD behaviour
/// without requiring SkipSQLPlus or an actual SQLite database.
struct SQLPlaygroundDatabase: Equatable {
    var items: [SQLPlaygroundItem] = []
    var statements: [String] = []

    var lastActionSQL: String? {
        statements.last { sql in
            !sql.hasPrefix("SELECT ")
        }
    }

    mutating func createItem(name: String = "") {
        let maxSort = items.compactMap(\.sortOrder).max() ?? 0.0
        let item = SQLPlaygroundItem(name: name, date: Date(), sortOrder: maxSort + 100.0)
        items.append(item)
        statements.append("INSERT INTO SQL_ITEM (NAME, DATE, SORT_ORDER) VALUES ('\(item.name)', \(item.date.timeIntervalSince1970), \(item.sortOrder))")
    }

    mutating func updateItem(_ item: SQLPlaygroundItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        statements.append("UPDATE SQL_ITEM SET NAME='\(item.name)', DATE=\(item.date.timeIntervalSince1970) WHERE ID='\(item.id)'")
    }

    mutating func deleteItems(atOffsets offsets: IndexSet) {
        for index in offsets.sorted().reversed() {
            let item = items[index]
            statements.append("DELETE FROM SQL_ITEM WHERE ID='\(item.id)'")
        }
        items.remove(atOffsets: offsets)
    }

    mutating func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        // Re-assign sort orders based on new positions
        for (index, _) in items.enumerated() {
            items[index].sortOrder = Double(items.count - index) * 100.0
        }
        statements.append("UPDATE SQL_ITEM SET SORT_ORDER=... (reorder)")
    }
}

// MARK: - SQLPlaygroundListView

struct SQLPlaygroundListView: View {
    @Binding var database: SQLPlaygroundDatabase

    var body: some View {
        List {
            Section {
                ForEach(database.items) { item in
                    VStack(alignment: .leading) {
                        if item.name.isEmpty {
                            Text("New Item")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(item.name)
                        }
                        Text(item.date.formatted())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { indices in
                    database.deleteItems(atOffsets: indices)
                }
                .onMove { from, to in
                    database.moveItems(fromOffsets: from, toOffset: to)
                }
            } footer: {
                Text(database.lastActionSQL ?? "SQL Log")
                    .font(Font.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.vertical)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation {
                        database.createItem()
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}
