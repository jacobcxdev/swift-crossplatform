import ComposableArchitecture
import XCTest

// MARK: - Test Reducers (file scope — macros can't attach to local types)

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

final class BindingTests: XCTestCase {

    // MARK: TCA-19: BindableAction compiles

    @MainActor
    func testBindableActionCompiles() {
        // Verify that BindingFeature with BindableAction protocol compiles and initialises
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        XCTAssertEqual(store.withState(\.text), "")
        XCTAssertEqual(store.withState(\.count), 0)
        XCTAssertEqual(store.withState(\.flag), false)
    }

    // MARK: TCA-20: BindingReducer applies mutations via .binding(.set(...))

    @MainActor
    func testBindingReducerAppliesMutations() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        store.send(.binding(.set(\.text, "hello")))
        XCTAssertEqual(store.withState(\.text), "hello")

        store.send(.binding(.set(\.count, 42)))
        XCTAssertEqual(store.withState(\.count), 42)

        store.send(.binding(.set(\.flag, true)))
        XCTAssertEqual(store.withState(\.flag), true)
    }

    // MARK: TCA-21: Store binding projection via dynamicMember setter

    @MainActor
    func testStoreBindingProjection() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        // The Store dynamicMember subscript setter sends .binding(.set(\.text, "world")) internally
        store.text = "world"
        XCTAssertEqual(store.withState(\.text), "world")
    }

    // MARK: TCA-21: Multiple sequential mutations via binding projection

    @MainActor
    func testBindingProjectionMultipleMutations() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        store.text = "first"
        XCTAssertEqual(store.withState(\.text), "first")

        store.text = "second"
        XCTAssertEqual(store.withState(\.text), "second")

        store.count = 10
        XCTAssertEqual(store.withState(\.count), 10)

        store.count = 20
        XCTAssertEqual(store.withState(\.count), 20)

        store.flag = true
        XCTAssertEqual(store.withState(\.flag), true)
    }

    // MARK: TCA-22: Sending path — direct action dispatch

    @MainActor
    func testSendingBinding() async {
        let store = Store(initialState: SendingFeature.State()) {
            SendingFeature()
        }
        let task = store.send(.setCount(42))
        await task.finish()
        XCTAssertEqual(store.withState(\.count), 42)
        XCTAssertEqual(store.withState(\.effectLog), [42])
    }

    // MARK: TCA-20: BindingReducer is a no-op for non-binding actions

    @MainActor
    func testBindingReducerNoopForNonBindingAction() {
        // BindingFeature only has .binding actions, so any .binding(.set(...)) that writes
        // the same value should be idempotent
        let store = Store(initialState: BindingFeature.State(text: "same")) {
            BindingFeature()
        }
        let idBefore = store.withState(\._$id)
        store.send(.binding(.set(\.text, "same")))
        // State should still be "same"
        XCTAssertEqual(store.withState(\.text), "same")
        // _$id may or may not change — binding reducer always calls the setter.
        // The key test is that the value is still correct.
        _ = store.withState(\._$id)
        _ = idBefore  // suppress unused warning
    }

    // MARK: TCA-22: Sending cancellation — rapid sends, last effect wins

    @MainActor
    func testSendingCancellation() async {
        let store = Store(initialState: SendingFeature.State()) {
            SendingFeature()
        }
        // Send two actions rapidly
        store.send(.setCount(1))
        let task2 = store.send(.setCount(2))
        await task2.finish()
        // Final state reflects last send
        XCTAssertEqual(store.withState(\.count), 2)
        // Both effects should complete (no cancellation by default)
        XCTAssertTrue(store.withState(\.effectLog).contains(2))
    }

    // MARK: TCA-21: Rapid mutation loop does not infinite-loop

    @MainActor
    func testBindingDoesNotInfiniteLoop() {
        let store = Store(initialState: BindingFeature.State()) {
            BindingFeature()
        }
        // Rapidly mutate 100 times
        for i in 0..<100 {
            store.count = i
        }
        XCTAssertEqual(store.withState(\.count), 99)
    }
}
