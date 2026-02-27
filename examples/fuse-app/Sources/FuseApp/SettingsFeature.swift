import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Sharing
import SwiftUI

// MARK: - SettingsFeature Reducer

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.userName) var userName: String
        @Shared(.appearance) var appearance: String
        @Shared(.notificationsEnabled) var notificationsEnabled: Bool
        @Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []
        @Shared(.settingsActionCount) var settingsActionCount: Int
    }

    @CasePathable
    enum Action {
        case userNameChanged(String)
        case appearanceChanged(String)
        case notificationsToggled(Bool)
        case resetButtonTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .userNameChanged(name):
                state.$userName.withLock { $0 = name }
                state.$settingsActionCount.withLock { $0 += 1 }
                return .none

            case let .appearanceChanged(appearance):
                state.$appearance.withLock { $0 = appearance }
                state.$settingsActionCount.withLock { $0 += 1 }
                return .none

            case let .notificationsToggled(enabled):
                state.$notificationsEnabled.withLock { $0 = enabled }
                state.$settingsActionCount.withLock { $0 += 1 }
                return .none

            case .resetButtonTapped:
                state.$userName.withLock { $0 = "Skipper" }
                state.$appearance.withLock { $0 = "" }
                state.$notificationsEnabled.withLock { $0 = true }
                state.$settingsActionCount.withLock { $0 += 1 }
                return .none
            }
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        List {
            Section("Profile") {
                TextField("Name", text: $store.userName.sending(\.userNameChanged))

                Picker("Appearance", selection: $store.appearance.sending(\.appearanceChanged)) {
                    Text("System").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Preferences") {
                Toggle("Notifications", isOn: $store.notificationsEnabled.sending(\.notificationsToggled))
            }

            Section("Storage Demo") {
                HStack { Text("Saved Todos (fileStorage)"); Spacer(); Text("\(store.savedTodos.count)").foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
                HStack { Text("Actions (inMemory)"); Spacer(); Text("\(store.settingsActionCount)").foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    store.send(.resetButtonTapped)
                }
                .accessibilityHint("Resets name, appearance, and notifications to default values.")
            }

            Section("About") {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    HStack { Text("Version"); Spacer(); Text("\(version) (\(buildNumber))").foregroundStyle(.secondary) }
                }
                Text("Powered by [Skip](https://skip.dev) and [TCA](https://github.com/pointfreeco/swift-composable-architecture)")
            }
        }
        .navigationTitle("Settings")
    }
}
