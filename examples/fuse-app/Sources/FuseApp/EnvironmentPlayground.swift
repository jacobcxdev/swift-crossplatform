// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// MARK: - Environment key
// TapCountObservable is defined in StatePlaygroundModel.swift

struct EnvironmentPlaygroundCustomKey: EnvironmentKey {
    static let defaultValue = "default"
}

extension EnvironmentValues {
    var environmentPlaygroundCustomKey: String {
        get { self[EnvironmentPlaygroundCustomKey.self] }
        set { self[EnvironmentPlaygroundCustomKey.self] = newValue }
    }
}

// MARK: - Playground

struct EnvironmentPlayground: View {
    @State var tapCountObservable = TapCountObservable()

    var body: some View {
        List {
            Section {
                EnvironmentPlaygroundEnvironmentObjectView()
                    .environment(tapCountObservable)
            }
            Section {
                EnvironmentPlaygroundCustomKeyView(label: "Custom key default")
                EnvironmentPlaygroundCustomKeyView(label: "Custom key value")
                    .environment(\.environmentPlaygroundCustomKey, "Custom!")
            }
        }
    }
}

// MARK: - Helper views

struct EnvironmentPlaygroundEnvironmentObjectView: View {
    @Environment(TapCountObservable.self) var tapCountObservable

    var body: some View {
        Text("EnvironmentObject tap count: \(tapCountObservable.tapCount)")
        Button("EnvironmentObject") {
            tapCountObservable.tapCount += 1
        }
        @Bindable var tco = tapCountObservable
        EnvironmentPlaygroundBindingView(tapCount: $tco.tapCount)
    }
}

/// Binding view for environment playground tap count demonstration.
struct EnvironmentPlaygroundBindingView: View {
    @Binding var tapCount: Int
    var body: some View {
        Button("Binding") {
            tapCount += 1
        }
    }
}

struct EnvironmentPlaygroundCustomKeyView: View {
    let label: String
    @Environment(\.environmentPlaygroundCustomKey) var customKeyValue

    var body: some View {
        HStack {
            Text(verbatim: label)
            Spacer()
            Text(verbatim: customKeyValue)
                .foregroundStyle(.secondary)
        }
    }
}
