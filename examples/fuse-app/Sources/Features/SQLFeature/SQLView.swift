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
        List {
            Section {
                let _ = logger.debug("SQLView.body: Section content evaluating, items.count=\(store.items.count)")
                ForEach(store.items) { item in
                    let _ = logger.debug("SQLView.body: ForEach rendering item id=\(item.id) name=\(item.name)")
                    Button {
                        logger.debug("SQLView: itemTapped id=\(item.id)")
                        store.send(.itemTapped(item))
                    } label: {
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
                    .foregroundStyle(.primary)
                }
                .onDelete { indices in
                    logger.debug("SQLView: onDelete indices=\(Array(indices))")
                    store.send(.deleteItems(offsets: Array(indices)))
                }
                .onMove { from, to in
                    logger.debug("SQLView: onMove from=\(Array(from)) to=\(to)")
                    store.send(.moveItems(from: Array(from), to: to))
                }
            } footer: {
                let _ = logger.debug("SQLView.body: Section footer evaluating")
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
        .toolbar {
            ToolbarItem {
                Button {
                    logger.debug("SQLView: + button tapped")
                    store.send(.createItemTapped)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .task {
            logger.debug("SQLView: .task fired, sending .task action")
            store.send(.task)
        }
    }
}
