import ComposableArchitecture
import SwiftUI

// MARK: - AppFeature Reducer

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab = Tab.counter
        var counter = CounterFeature.State()
        // Remaining features added in Task 1b
        // var todos = TodosFeature.State()
        // var contacts = ContactsFeature.State()
        // var database = DatabaseFeature.State()
        // var settings = SettingsFeature.State()

        enum Tab: String, Equatable {
            case counter, todos, contacts, database, settings
        }
    }

    enum Action {
        case counter(CounterFeature.Action)
        // Remaining features added in Task 1b
        // case todos(TodosFeature.Action)
        // case contacts(ContactsFeature.Action)
        // case database(DatabaseFeature.Action)
        // case settings(SettingsFeature.Action)
        case tabSelected(State.Tab)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.counter, action: \.counter) {
            CounterFeature()
        }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
            case .counter:
                return .none
            }
        }
    }
}

// MARK: - AppView

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        TabView(selection: $store.selectedTab.sending(\.tabSelected)) {
            NavigationStack {
                CounterView(store: store.scope(state: \.counter, action: \.counter))
            }
            .tabItem { Label("Counter", systemImage: "number") }
            .tag(AppFeature.State.Tab.counter)

            // Remaining tabs added in Task 1b
            NavigationStack {
                Text("Todos - Coming Soon")
            }
            .tabItem { Label("Todos", systemImage: "checklist") }
            .tag(AppFeature.State.Tab.todos)

            NavigationStack {
                Text("Contacts - Coming Soon")
            }
            .tabItem { Label("Contacts", systemImage: "person.2") }
            .tag(AppFeature.State.Tab.contacts)

            NavigationStack {
                Text("Database - Coming Soon")
            }
            .tabItem { Label("Database", systemImage: "cylinder") }
            .tag(AppFeature.State.Tab.database)

            NavigationStack {
                Text("Settings - Coming Soon")
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppFeature.State.Tab.settings)
        }
    }
}
