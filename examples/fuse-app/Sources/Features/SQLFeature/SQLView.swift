// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import SkipFuse
import SwiftUI

private let logger = Logger(subsystem: "dev.jacobcx.fuseApp", category: "SQLView")

public struct SQLView: View {
    @Bindable var store: StoreOf<SQLFeature>

    public init(store: StoreOf<SQLFeature>) {
        logger.debug("SQLView.init")
        self.store = store
    }

    public var body: some View {
        let _ = logger.debug("SQLView.body: items.count=\(store.items.count), statements.count=\(store.statements.count), editor=\(store.editor != nil ? "present" : "nil")")
        List(selection: Binding(get: { store.selection }, set: { store.send(.selectionChanged($0)) })) {
            if !store.pinnedItems.isEmpty {
                Section {
                    ForEach(store.pinnedItems) { item in
                        itemRow(item)
                    }
                } header: {
                    Text("Pinned (\(store.pinnedItems.count))")
                }
            }
            Section {
                ForEach(store.unpinnedItems) { item in
                    itemRow(item)
                }
                .onMove { from, to in
                    logger.debug("SQLView: onMove from=\(Array(from)) to=\(to)")
                    store.send(.moveItems(from: Array(from), to: to))
                }
            } header: {
                Text("Items (\(store.unpinnedItems.count))")
            } footer: {
                NavigationLink {
                    TextEditor(text: .constant(store.statements.joined(separator: "\n")))
                        .font(Font.body.monospaced())
                        .navigationTitle("SQL Log")
                } label: {
                    Text(store.lastActionSQL ?? "SQL Log")
                        .font(Font.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical)
                }
            }
        }
        .navigationDestination(
            item: $store.scope(state: \.editor, action: \.editor)
        ) { editorStore in
            let _ = logger.debug("SQLView: navigationDestination presenting editor")
            SQLItemEditorView(store: editorStore)
        }
        .navigationBarBackButtonHidden(store.isEditing)
        .toolbar { toolbarContent }
        .environment(
            \.editMode,
            .init(
                get: { store.isEditing ? .active : .inactive },
                set: {
                    store.send(.toggleSelection($0.isEditing == true))
                }
            )
        )
        .animation(.default, value: store.isEditing)
        .task {
            logger.debug("SQLView: .task fired, sending .task action")
            store.send(.task)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        let _ = logger.debug("toolbarContent: isEditing=\(store.isEditing), selection.count=\(store.selection.count), selection.isEmpty=\(store.selection.isEmpty)")
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                if store.isEditing {
                    Button {
                        guard !store.selection.isEmpty else { return }
                        store.send(.pinSelectedTapped)
                    } label: {
                        Label("Pin", systemImage: "pin")
                    }
                    .opacity(store.selection.isEmpty ? 0.4 : 1.0)

                    Button(role: .destructive) {
                        guard !store.selection.isEmpty else { return }
                        store.send(.deleteSelectedTapped)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .opacity(store.selection.isEmpty ? 0.4 : 1.0)
                } else {
                    Button {
                        store.send(.editButtonTapped, animation: .default)
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }

                    Button {
                        store.send(.createItemTapped)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if store.isEditing {
                Button {
                    store.send(.editButtonTapped, animation: .default)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
        }
    }

    private func itemRow(_ item: SQLItem) -> some View {
        Button {
            store.send(.itemTapped(item))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if item.name.isEmpty {
                    Text("Untitled")
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.name)
                }
                Text(item.date.deviceFormatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let pinnedAt = item.pinnedAt {
                    Text("Pinned \(pinnedAt.deviceFormatted())")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, item.isPinned ? 5.5 : 0)
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.send(.deleteItem(id: item.id))
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                store.send(.itemTapped(item))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                store.send(.togglePinned(id: item.id))
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
            Button {
                store.send(.itemTapped(item))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
