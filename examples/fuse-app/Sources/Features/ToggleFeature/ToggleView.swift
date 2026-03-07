// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import SwiftUI

public struct ToggleView: View {
    @Bindable var store: StoreOf<ToggleFeature>

    public init(store: StoreOf<ToggleFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Toggle(isOn: $store.isOn) {
                    Text("Viewbuilder init")
                }
                Toggle("String init", isOn: $store.isOn)
                Toggle("Fixed width", isOn: $store.isOn)
                    .frame(width: 200)
                VStack {
                    Text(".labelsHidden():")
                    Toggle("Label", isOn: $store.isOn)
                }
                .labelsHidden()
                Toggle(".disabled(true)", isOn: $store.isOn)
                    .disabled(true)
                Toggle(".foregroundStyle(.red)", isOn: $store.isOn)
                    .foregroundStyle(.red)
                Toggle(".tint(.red)", isOn: $store.isOn)
                    .tint(.red)
            }
            .padding()
        }
    }
}
