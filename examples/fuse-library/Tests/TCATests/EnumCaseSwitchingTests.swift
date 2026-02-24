#if !SKIP
import ComposableArchitecture
import Testing

// MARK: - Test Reducers (file scope -- macros can't attach to local types)

@Reducer
struct CounterChild {
    @ObservableState
    struct State: Equatable {
        var value: Int = 0
    }
    enum Action {
        case increment
    }
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
struct DetailChild {
    @ObservableState
    struct State: Equatable {
        var text: String = ""
    }
    enum Action {
        case setText(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setText(text):
                state.text = text
                return .none
            }
        }
    }
}

@Reducer
enum SwitchDestination {
    case counter(CounterChild)
    case detail(DetailChild)
}

@Reducer
struct SwitchParent {
    @ObservableState
    struct State {
        @Presents var destination: SwitchDestination.State?
    }
    enum Action {
        case destination(PresentationAction<SwitchDestination.Action>)
        case presentCounter
        case presentDetail
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .presentCounter:
                state.destination = .counter(CounterChild.State())
                return .none
            case .presentDetail:
                state.destination = .detail(DetailChild.State())
                return .none
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct EnumCaseSwitchingTests {

    // MARK: TCA-25: switch store.case {} enum switching dispatches to correct case

    @Test func presentCounterCase() {
        let store = Store(initialState: SwitchParent.State()) {
            SwitchParent()
        }
        // Initially no destination
        #expect(store.withState(\.destination) == nil)

        // Present counter case
        store.send(.presentCounter)
        if case .counter(let state) = store.withState(\.destination) {
            #expect(state.value == 0)
        } else {
            Issue.record("Expected .counter destination")
        }
    }

    @Test func presentDetailCase() {
        let store = Store(initialState: SwitchParent.State()) {
            SwitchParent()
        }
        // Present detail case
        store.send(.presentDetail)
        if case .detail(let state) = store.withState(\.destination) {
            #expect(state.text == "")
        } else {
            Issue.record("Expected .detail destination")
        }
    }

    @Test func switchBetweenCases() {
        let store = Store(initialState: SwitchParent.State()) {
            SwitchParent()
        }
        // Present counter, then switch to detail
        store.send(.presentCounter)
        store.send(.presentDetail)
        if case .detail = store.withState(\.destination) {
            // success
        } else {
            Issue.record("Expected .detail destination after switching from .counter")
        }
    }

    @Test func childStoreScoping() {
        let store = Store(initialState: SwitchParent.State()) {
            SwitchParent()
        }
        store.send(.presentCounter)

        // Scope to destination store
        let destStore: Store<SwitchDestination.State, SwitchDestination.Action>? = store.scope(
            state: \.destination,
            action: \.destination.presented
        )
        #expect(destStore != nil)
    }

    @Test func caseReducerStateConformance() {
        // Compile-time check: SwitchDestination.State conforms to CaseReducerState
        let _: (any CaseReducerState)? = SwitchDestination.State.counter(CounterChild.State())
        // If this compiles, conformance is verified
    }
}
#endif
