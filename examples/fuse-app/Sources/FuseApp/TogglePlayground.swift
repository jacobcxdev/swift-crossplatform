// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from skipapp-showcase-fuse TogglePlayground.swift

import SwiftUI

struct TogglePlayground: View {
    @State var isOn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Toggle(isOn: $isOn) {
                    Text("Viewbuilder init")
                }
                Toggle("String init", isOn: $isOn)
                Toggle("Fixed width", isOn: $isOn)
                    .frame(width: 200)
                VStack {
                    Text(".labelsHidden():")
                    Toggle("Label", isOn: $isOn)
                }
                .labelsHidden()
                Toggle(".disabled(true)", isOn: $isOn)
                    .disabled(true)
                Toggle(".foregroundStyle(.red)", isOn: $isOn)
                    .foregroundStyle(.red)
                Toggle(".tint(.red)", isOn: $isOn)
                    .tint(.red)
            }
            .padding()
        }
    }
}
