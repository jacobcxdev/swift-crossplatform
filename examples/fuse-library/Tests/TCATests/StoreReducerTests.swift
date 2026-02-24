#if !SKIP
import ComposableArchitecture
import CustomDump
import Foundation
import Testing

// MARK: - Test Reducers

@Reducer
struct Counter {
    struct State: Equatable { var count = 0 }
    enum Action { case increment, decrement }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment: state.count += 1; return .none
            case .decrement: state.count -= 1; return .none
            }
        }
    }
}

@Reducer
struct Parent {
    struct State: Equatable { var child = Counter.State() }
    enum Action { case child(Counter.Action) }
    var body: some ReducerOf<Self> {
        Scope(state: \.child, action: \.child) { Counter() }
    }
}

@Reducer
struct OptionalChild {
    struct State: Equatable {
        var detail: Counter.State?
    }
    enum Action {
        case detail(Counter.Action)
        case setDetail(Bool)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .setDetail(true):
                state.detail = Counter.State()
                return .none
            case .setDetail(false):
                state.detail = nil
                return .none
            case .detail:
                return .none
            }
        }
        .ifLet(\.detail, action: \.detail) {
            Counter()
        }
    }
}

@Reducer
struct ItemFeature {
    struct State: Equatable, Identifiable {
        let id: UUID
        var value: Int = 0
    }
    enum Action { case increment }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.value += 1
                return .none
            }
        }
    }
}

@Reducer
struct ItemList {
    struct State: Equatable {
        var items: IdentifiedArrayOf<ItemFeature.State> = []
    }
    enum Action {
        case items(IdentifiedActionOf<ItemFeature>)
    }
    var body: some ReducerOf<Self> {
        Reduce { _, _ in .none }
            .forEach(\.items, action: \.items) {
                ItemFeature()
            }
    }
}

@Reducer
struct EnumFeature {
    @ObservableState
    enum State: Equatable {
        case loading
        case loaded(Counter.State)
    }
    enum Action {
        case loaded(Counter.Action)
    }
    var body: some ReducerOf<Self> {
        Reduce { _, _ in .none }
            .ifCaseLet(\.loaded, action: \.loaded) {
                Counter()
            }
    }
}

@Reducer
struct Logging {
    struct State: Equatable {
        var count = 0
        var log: [String] = []
    }
    enum Action { case increment }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.log.append("logged")
                return .none
            }
        }
    }
}

@Reducer
struct Combined {
    struct State: Equatable {
        var count = 0
        var log: [String] = []
    }
    enum Action { case increment }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.count += 1
                state.log.append("logged")
                return .none
            }
        }
    }
}

@Reducer
struct UUIDFeature {
    struct State: Equatable {
        var lastID: String = ""
    }
    enum Action { case generate }
    @Dependency(\.uuid) var uuid
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .generate:
                state.lastID = uuid().uuidString
                return .none
            }
        }
    }
}

@Reducer
struct SyncEffectFeature {
    struct State: Equatable {
        var count = 0
        var doubled = false
    }
    enum Action {
        case tap
        case doubled
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .tap:
                state.count += 1
                return .send(.doubled)
            case .doubled:
                state.doubled = true
                return .none
            }
        }
    }
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct StoreReducerTests {

    // MARK: TCA-01: Store initializes with correct state

    @Test func storeInitialState() {
        let store = Store(initialState: Counter.State(count: 42)) {
            Counter()
        }
        #expect(store.withState(\.count) == 42)
    }

    // MARK: TCA-02: Store init with dependency override

    @Test func storeInitWithDependencies() {
        let store = Store(initialState: UUIDFeature.State()) {
            UUIDFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        store.send(.generate)
        #expect(
            store.withState(\.lastID) ==
            UUID(uuidString: "00000000-0000-0000-0000-000000000000")!.uuidString
        )
    }

    // MARK: TCA-03: store.send returns StoreTask

    @Test func storeSendReturnsStoreTask() async {
        let store = Store(initialState: Counter.State()) {
            Counter()
        }
        let task = store.send(.increment)
        #expect(store.withState(\.count) == 1)
        await task.finish()
    }

    // MARK: TCA-04: Store scope derives child store

    @Test func storeScopeDerivesChildStore() {
        let parentStore = Store(initialState: Parent.State()) {
            Parent()
        }
        let childStore = parentStore.scope(state: \.child, action: \.child)
        childStore.send(.increment)
        #expect(parentStore.withState(\.child.count) == 1)
        #expect(childStore.withState(\.count) == 1)
    }

    // MARK: TCA-05: Scope reducer composition

    @Test func scopeReducer() {
        let store = Store(initialState: Parent.State()) {
            Parent()
        }
        store.send(.child(.increment))
        #expect(store.withState(\.child.count) == 1)
        store.send(.child(.decrement))
        #expect(store.withState(\.child.count) == 0)
    }

    // MARK: TCA-06: ifLet reducer composition

    @Test func ifLetReducer() {
        let store = Store(initialState: OptionalChild.State()) {
            OptionalChild()
        }
        // detail starts nil
        #expect(store.withState(\.detail) == nil)

        // set detail to non-nil
        store.send(.setDetail(true))
        #expect(store.withState(\.detail) == Counter.State(count: 0))

        // now child action should update
        store.send(.detail(.increment))
        #expect(store.withState(\.detail) == Counter.State(count: 1))

        // nil it out
        store.send(.setDetail(false))
        #expect(store.withState(\.detail) == nil)
    }

    // MARK: TCA-07: forEach reducer composition

    @Test func forEachReducer() {
        let id1 = UUID()
        let id2 = UUID()
        let store = Store(
            initialState: ItemList.State(items: [
                ItemFeature.State(id: id1, value: 0),
                ItemFeature.State(id: id2, value: 10),
            ])
        ) {
            ItemList()
        }

        store.send(.items(.element(id: id1, action: .increment)))
        #expect(store.withState(\.items[id: id1]?.value) == 1)
        #expect(store.withState(\.items[id: id2]?.value) == 10)
    }

    // MARK: TCA-08: ifCaseLet reducer composition

    @Test func ifCaseLetReducer() {
        // When in the correct case, child reducer runs
        let store = Store(initialState: EnumFeature.State.loaded(Counter.State(count: 5))) {
            EnumFeature()
        }
        store.send(.loaded(.increment))
        #expect(store.withState(\.[case: \.loaded]?.count) == 6)

        // Verify the loaded case is still active
        store.send(.loaded(.decrement))
        #expect(store.withState(\.[case: \.loaded]?.count) == 5)
    }

    // MARK: TCA-09: CombineReducers composition

    @Test func combineReducers() {
        let store = Store(initialState: Combined.State()) {
            Combined()
        }
        store.send(.increment)
        #expect(store.withState(\.count) == 1)
        expectNoDifference(store.withState(\.log), ["logged"])
    }

    // MARK: TCA-16: Effect.send synchronous dispatch

    @Test func effectSend() async {
        let store = Store(initialState: SyncEffectFeature.State()) {
            SyncEffectFeature()
        }
        let task = store.send(.tap)
        await task.finish()
        #expect(store.withState(\.count) == 1)
        #expect(store.withState(\.doubled) == true)
    }

    // MARK: withState reads correctly

    @Test func storeWithState() {
        let store = Store(initialState: Counter.State(count: 99)) {
            Counter()
        }
        let result = store.withState { $0.count }
        #expect(result == 99)
    }
}
#endif
