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
        @Shared(.sessionActionCount) var sessionActionCount: Int
        @ObservationStateIgnored var debugInfo: String = ""
    }

    @CasePathable
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case userNameChanged(String)
        case appearanceChanged(String)
        case notificationsToggled(Bool)
        case resetButtonTapped
        case viewAppeared
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case let .userNameChanged(name):
                state.$userName.withLock { $0 = name }
                state.$sessionActionCount.withLock { $0 += 1 }
                return .none

            case let .appearanceChanged(appearance):
                state.$appearance.withLock { $0 = appearance }
                state.$sessionActionCount.withLock { $0 += 1 }
                return .none

            case let .notificationsToggled(enabled):
                state.$notificationsEnabled.withLock { $0 = enabled }
                state.$sessionActionCount.withLock { $0 += 1 }
                return .none

            case .resetButtonTapped:
                state.$userName.withLock { $0 = "Skipper" }
                state.$appearance.withLock { $0 = "" }
                state.$notificationsEnabled.withLock { $0 = true }
                state.$sessionActionCount.withLock { $0 += 1 }
                return .none

            case .viewAppeared:
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
                TextField("Name", text: Binding(
                    get: { store.userName },
                    set: { store.send(.userNameChanged($0)) }
                ))

                Picker("Appearance", selection: Binding(
                    get: { store.appearance },
                    set: { store.send(.appearanceChanged($0)) }
                )) {
                    Text("System").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Preferences") {
                Toggle("Notifications", isOn: Binding(
                    get: { store.notificationsEnabled },
                    set: { store.send(.notificationsToggled($0)) }
                ))
            }

            Section("Storage Demo") {
                HStack { Text("Saved Todos (fileStorage)"); Spacer(); Text("\(store.savedTodos.count)").foregroundStyle(.secondary) }
                HStack { Text("Actions (inMemory)"); Spacer(); Text("\(store.sessionActionCount)").foregroundStyle(.secondary) }
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    store.send(.resetButtonTapped)
                }
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
        .task { store.send(.viewAppeared) }
    }
}
