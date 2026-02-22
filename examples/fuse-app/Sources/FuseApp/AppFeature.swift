import ComposableArchitecture
import SwiftUI

// MARK: - AppFeature Reducer

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab = Tab.counter
        var counter = CounterFeature.State()
        var todos = TodosFeature.State()
        var contacts = ContactsFeature.State()
        var database = DatabaseFeature.State()
        var settings = SettingsFeature.State()

        enum Tab: String, Equatable {
            case counter, todos, contacts, database, settings
        }
    }

    enum Action {
        case counter(CounterFeature.Action)
        case todos(TodosFeature.Action)
        case contacts(ContactsFeature.Action)
        case database(DatabaseFeature.Action)
        case settings(SettingsFeature.Action)
        case tabSelected(State.Tab)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.counter, action: \.counter) {
            CounterFeature()
        }
        Scope(state: \.todos, action: \.todos) {
            TodosFeature()
        }
        Scope(state: \.contacts, action: \.contacts) {
            ContactsFeature()
        }
        Scope(state: \.database, action: \.database) {
            DatabaseFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
            case .counter, .todos, .contacts, .database, .settings:
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

            NavigationStack {
                TodosView(store: store.scope(state: \.todos, action: \.todos))
            }
            .tabItem { Label("Todos", systemImage: "checklist") }
            .tag(AppFeature.State.Tab.todos)

            ContactsView(store: store.scope(state: \.contacts, action: \.contacts))
                .tabItem { Label("Contacts", systemImage: "person.2") }
                .tag(AppFeature.State.Tab.contacts)

            NavigationStack {
                DatabaseView(store: store.scope(state: \.database, action: \.database))
            }
            .tabItem { Label("Database", systemImage: "cylinder") }
            .tag(AppFeature.State.Tab.database)

            NavigationStack {
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppFeature.State.Tab.settings)
        }
    }
}
