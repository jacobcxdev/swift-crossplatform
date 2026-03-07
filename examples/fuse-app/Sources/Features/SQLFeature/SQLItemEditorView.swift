// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import SkipFuse
import SwiftUI

private let logger = Logger(subsystem: "dev.jacobcx.fuseApp", category: "SQLItemEditorView")

struct SQLItemEditorView: View {
    @Bindable var store: StoreOf<SQLItemEditorFeature>

    var body: some View {
        let _ = logger.debug("SQLItemEditorView.body: item.id=\(store.item.id) name=\(store.item.name)")
        Form {
            TextField("Name", text: $store.item.name)
            DatePicker("Date", selection: $store.item.date)
        }
        .toolbar {
            Button("Save") {
                logger.debug("SQLItemEditorView: Save tapped")
                store.send(.saveTapped)
            }
        }
    }
}
