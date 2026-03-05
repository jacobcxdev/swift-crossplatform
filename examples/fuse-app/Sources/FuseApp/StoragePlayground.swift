// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from skipapp-showcase-fuse StoragePlayground.swift

import SwiftUI

struct StoragePlayground: View {
    @AppStorage("boolAppStorage") var boolAppStorage = false
    @AppStorage("doubleAppStorage") var doubleAppStorage = 5.0
    @AppStorage("enumAppStorage") var enumAppStorage = StoragePlaygroundEnum.first

    let doubleAppStorageValues = [1.0, 5.0, 10.0, 20.0, 25.0]

    var body: some View {
        VStack(spacing: 16) {
            VStack {
                Text("Double AppStorage")
                Picker("Double AppStorage", selection: $doubleAppStorage) {
                    ForEach(doubleAppStorageValues, id: \.self) {
                        Text(String(Int($0)))
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text("Enum AppStorage")
                Spacer()
                Picker("Enum AppStorage", selection: $enumAppStorage) {
                    Text("First").tag(StoragePlaygroundEnum.first)
                    Text("Second").tag(StoragePlaygroundEnum.second)
                    Text("Third").tag(StoragePlaygroundEnum.third)
                }
            }
            Toggle("Bool AppStorage", isOn: $boolAppStorage)
            NavigationLink("Push binding") {
                StoragePlaygroundBindingView(binding: $boolAppStorage)
            }
        }
        .padding()
    }
}

enum StoragePlaygroundEnum: Int {
    case first, second, third
}

struct StoragePlaygroundBindingView: View {
    @Binding var binding: Bool

    var body: some View {
        Toggle("Storage", isOn: $binding)
            .padding()
            .navigationTitle("Storage Binding")
    }
}
