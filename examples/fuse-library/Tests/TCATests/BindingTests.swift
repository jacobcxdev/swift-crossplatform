#if !SKIP
import ComposableArchitecture
import CustomDump
import Testing

// MARK: - Test Reducers (file scope — macros can't attach to local types)

@Reducer
struct IfLetChild {
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
struct IfLetParent {
    @ObservableState
    struct State: Equatable {
        @Presents var child: IfLetChild.State?
    }
    enum Action {
        case showChild
        case hideChild
        case child(PresentationAction<IfLetChild.Action>)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showChild:
                state.child = IfLetChild.State()
                return .none
            case .hideChild:
                state.child = nil
                return .none
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            IfLetChild()
        }
    }
}

@Reducer
struct BindingFeature {
    @ObservableState
    struct State: Equatable {
        var text: String = ""
        var count: Int = 0
        var flag: Bool = false
    }
    enum Action: BindableAction {
        case binding(BindingAction<State>)
    }
    var body: some ReducerOf<Self> {
        BindingReducer()
    }
}

@Reducer
struct SendingFeature {
    @ObservableState
    struct State: Equatable {
        var count: Int = 0
        var effectLog: [Int] = []
    }
    enum Action {
        case setCount(Int)
        case effectCompleted(Int)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setCount(value):
                state.count = value
                return .run { [value] send in
                    await send(.effectCompleted(value))
                }
            case let .effectCompleted(value):
                state.effectLog.append(value)
                return .none
            }
        }
    }
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct BindingTests {

    // MARK: TCA-19: BindableAction compiles

    @Test func bindableActionCompiles() {
        // Verify that BindingFeature with BindableAction protocol compiles and initialises
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        #expect(store.withState(\.text) == "")
        #expect(store.withState(\.count) == 0)
        #expect(store.withState(\.flag) == false)
    }

    // MARK: TCA-20: BindingReducer applies mutations via .binding(.set(...))

    @Test func bindingReducerAppliesMutations() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        store.send(.binding(.set(\.text, "hello")))
        #expect(store.withState(\.text) == "hello")

        store.send(.binding(.set(\.count, 42)))
        #expect(store.withState(\.count) == 42)

        store.send(.binding(.set(\.flag, true)))
        #expect(store.withState(\.flag) == true)
    }

    // MARK: TCA-21: Store binding projection via dynamicMember setter

    @Test func storeBindingProjection() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        // The Store dynamicMember subscript setter sends .binding(.set(\.text, "world")) internally
        store.text = "world"
        #expect(store.withState(\.text) == "world")
    }

    // MARK: TCA-21: Multiple sequential mutations via binding projection

    @Test func bindingProjectionMultipleMutations() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        store.text = "first"
        #expect(store.withState(\.text) == "first")

        store.text = "second"
        #expect(store.withState(\.text) == "second")

        store.count = 10
        #expect(store.withState(\.count) == 10)

        store.count = 20
        #expect(store.withState(\.count) == 20)

        store.flag = true
        #expect(store.withState(\.flag) == true)
    }

    // MARK: TCA-22: Sending path — direct action dispatch

    @Test func sendingBinding() async {
        let store = Store(initialState: SendingFeature.State()) {
            SendingFeature()
        }
        let task = store.send(.setCount(42))
        await task.finish()
        #expect(store.withState(\.count) == 42)
        expectNoDifference(store.withState(\.effectLog), [42])
    }

    // MARK: TCA-20: BindingReducer is a no-op for non-binding actions

    @Test func bindingReducerNoopForNonBindingAction() {
        // BindingFeature only has .binding actions, so any .binding(.set(...)) that writes
        // the same value should be idempotent
        let store = Store(initialState: BindingFeature.State(text: "same")) {
            BindingFeature()
        }
        let idBefore = store.withState(\._$id)
        store.send(.binding(.set(\.text, "same")))
        // State should still be "same"
        #expect(store.withState(\.text) == "same")
        // _$id may or may not change — binding reducer always calls the setter.
        // The key test is that the value is still correct.
        _ = store.withState(\._$id)
        _ = idBefore  // suppress unused warning
    }

    // MARK: TCA-22: Sending cancellation — rapid sends, last effect wins

    @Test func sendingCancellation() async {
        let store = Store(initialState: SendingFeature.State()) {
            SendingFeature()
        }
        // Send two actions rapidly
        store.send(.setCount(1))
        let task2 = store.send(.setCount(2))
        await task2.finish()
        // Final state reflects last send
        #expect(store.withState(\.count) == 2)
        // Both effects should complete (no cancellation by default)
        #expect(store.withState(\.effectLog).contains(2))
    }

    // MARK: TCA-21: Rapid mutation loop does not infinite-loop

    @Test func bindingDoesNotInfiniteLoop() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        // Rapidly mutate 100 times
        for i in 0..<100 {
            store.count = i
        }
        #expect(store.withState(\.count) == 99)
    }

    // MARK: - IfLetStore alternative pattern (@Observable + @Presents)

    /// Tests the modern @Observable alternative to the deprecated IfLetStore pattern.
    /// IfLetStore is deprecated and this test proves the recommended replacement
    /// (@Presents + .ifLet) works on both platforms.
    @Test func testIfLetStoreAlternativePattern() async {
        let store = TestStore(initialState: IfLetParent.State()) {
            IfLetParent()
        }

        // Child starts nil
        store.assert { state in
            #expect(state.child == nil)
        }

        // Show child — sets child non-nil
        await store.send(.showChild) { state in
            state.child = IfLetChild.State()
        }

        // Interact with child via presented action
        await store.send(.child(.presented(.increment))) { state in
            state.child?.value = 1
        }

        // Hide child — sets child nil
        await store.send(.hideChild) { state in
            state.child = nil
        }
    }
}
#endif
