// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct LabelPlayground: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Label {
                    Text(".init(_:icon:)")
                } icon: {
                    Image(systemName: "star.fill")
                }
                Label(".init(_:systemImage:)", systemImage: "star.fill")
                Label(".font(.title)", systemImage: "star.fill")
                    .font(.title)
                Label(".foregroundStyle(.red)", systemImage: "star.fill")
                    .foregroundStyle(.red)

                VStack {
                    Label(".tint(.red)", systemImage: "star.fill")
                        .tint(.red)
                    Text("Note: tint should not affect Label appearance")
                        .font(.caption)
                }

                Section("Label Styles") {
                    Label("Icon + Title", systemImage: "heart.fill")
                        .labelStyle(.titleAndIcon)
                    Label("Title Only", systemImage: "heart.fill")
                        .labelStyle(.titleOnly)
                    HStack {
                        Text("Icon Only:")
                            .foregroundStyle(.secondary)
                        Label("Icon Only", systemImage: "heart.fill")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .padding()
        }
    }
}
