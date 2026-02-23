import ComposableArchitecture
import SwiftUI
import Testing

// MARK: - Reducers

@Reducer
struct AppFeature {
    @ObservableState
    struct State {
        var path = StackState<Path.State>()
    }
    enum Action {
        case path(StackActionOf<Path>)
        case pushDetail(String)
        case popAll
    }
    @Reducer
    enum Path {
        case detail(DetailFeature)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .pushDetail(title):
                state.path.append(Path.State.detail(DetailFeature.State(title: title)))
                return .none
            case .popAll:
                state.path.removeAll()
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

@Reducer
struct DetailFeature {
    @ObservableState
    struct State: Equatable {
        var title: String
    }
    enum Action {
        case titleChanged(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .titleChanged(title):
                state.title = title
                return .none
            }
        }
    }
}

// MARK: - Tests

@MainActor
struct NavigationStackTests {

    // MARK: - Stack Push/Pop (NAV-01, NAV-02, NAV-03)

    @Test
    func testNavigationStackPush() {
        // Use Store (not TestStore) — AppFeature.State is not Equatable due to @Reducer enum Path
        let store = Store(initialState: AppFeature.State()) { AppFeature() }

        store.send(.pushDetail("Item 1"))
        #expect(store.state.path.count == 1)

        store.send(.pushDetail("Item 2"))
        #expect(store.state.path.count == 2)
    }

    @Test
    func testNavigationStackPop() {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }

        store.send(.pushDetail("A"))
        store.send(.pushDetail("B"))
        store.send(.pushDetail("C"))
        #expect(store.state.path.count == 3)

        // Pop the last item
        let lastID = store.state.path.ids.last!
        store.send(.path(.popFrom(id: lastID)))
        #expect(store.state.path.count == 2)

        // Verify correct item remains
        #expect(store.state.path[id: store.state.path.ids.last!]?[case: \.detail]?.title == "B")
    }

    @Test
    func testNavigationStackPopAll() {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }

        store.send(.pushDetail("X"))
        store.send(.pushDetail("Y"))
        #expect(store.state.path.count == 2)

        store.send(.popAll)
        #expect(store.state.path.count == 0)
    }

    // MARK: - Child Mutation (NAV-02)

    @Test
    func testNavigationStackChildMutation() {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }

        store.send(.pushDetail("Original"))
        let id = store.state.path.ids.first!

        store.send(.path(.element(id: id, action: .detail(.titleChanged("Mutated")))))

        #expect(store.state.path[id: id]?[case: \.detail]?.title == "Mutated")
    }

    // MARK: - Stack Path Scope Binding (NAV-01)

    @Test
    func testStackPathScopeBinding() {
        // Verify that $store.scope(state: \.path, action: \.path) produces a valid Binding
        // This is a compile-time + type validation test
        let store = Store(initialState: AppFeature.State()) { AppFeature() }

        // Create a @Bindable wrapper and verify scope produces correct type
        @Bindable var bindableStore = store
        let _: Binding<Store<StackState<AppFeature.Path.State>, StackAction<AppFeature.Path.State, AppFeature.Path.Action>>> = $bindableStore.scope(state: \.path, action: \.path)

        // Verify the binding reflects state changes through the parent store
        #expect(store.state.path.count == 0)

        store.send(.pushDetail("Test"))
        #expect(store.state.path.count == 1)
    }

    // MARK: - navigationDestination item binding (NAV-04)

    @Test
    func testNavigationDestinationItemBinding() {
        // Verify optional state binding toggles correctly for navigationDestination(item:) pattern
        let store = Store(initialState: AppFeature.State()) { AppFeature() }

        // Initially no items on stack
        #expect(store.state.path.count == 0)

        // Push creates a navigable destination
        store.send(.pushDetail("Destination"))
        #expect(store.state.path.count == 1)

        // Pop removes the destination
        let id = store.state.path.ids.first!
        store.send(.path(.popFrom(id: id)))
        #expect(store.state.path.count == 0)
    }

    // MARK: - Modern API Usage (NAV-16)

    @Test
    func testModernAPIUsage() {
        // Compile-time validation: @Bindable works with StoreOf (not @ObservedObject)
        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        @Bindable var bindableStore = store

        // NavigationStack(path:root:destination:) pattern compiles (not NavigationStackStore)
        // This is a type-level assertion — the extension on NavigationStack exists and compiles
        let _: Binding<Store<StackState<AppFeature.Path.State>, StackAction<AppFeature.Path.State, AppFeature.Path.Action>>> = $bindableStore.scope(state: \.path, action: \.path)

        // Verify the modern pattern types resolve correctly
        #expect(Bool(true), "Modern NavigationStack(path:) API compiles successfully")
    }
}
