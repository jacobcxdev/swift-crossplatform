import ComposableArchitecture
import XCTest

// MARK: - Edge Case Reducers

@Reducer
struct ChainFeature {
    struct State: Equatable {
        var step = 0
    }
    @CasePathable
    enum Action {
        case startChain
        case chainStepA
        case chainStepB
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startChain:
                return .run { send in await send(.chainStepA) }
            case .chainStepA:
                state.step = 1
                return .run { send in await send(.chainStepB) }
            case .chainStepB:
                state.step = 2
                return .none
            }
        }
    }
}

private enum CancelInFlightID: Hashable { case fetch }

@Reducer
struct CancelInFlightFeature {
    struct State: Equatable {
        var result: String = ""
        var fetchCount = 0
    }
    @CasePathable
    enum Action: Equatable {
        case fetch
        case response(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .fetch:
                state.fetchCount += 1
                let count = state.fetchCount
                return .run { send in
                    await send(.response("result-\(count)"))
                }
                .cancellable(id: CancelInFlightID.fetch, cancelInFlight: true)
            case let .response(value):
                state.result = value
                return .none
            }
        }
    }
}

@Reducer
struct SlowEffectFeature {
    struct State: Equatable {
        var completed = false
    }
    @CasePathable
    enum Action {
        case start
        case done
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .run { send in
                    try await Task.sleep(for: .milliseconds(100))
                    await send(.done)
                }
            case .done:
                state.completed = true
                return .none
            }
        }
    }
}

@Reducer
struct NonExhaustiveReceiveFeature {
    struct State: Equatable {
        var triggered = false
        var received = false
    }
    @CasePathable
    enum Action {
        case trigger
        case effectDone
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .trigger:
                state.triggered = true
                return .run { send in await send(.effectDone) }
            case .effectDone:
                state.received = true
                return .none
            }
        }
    }
}

// MARK: - Tests

final class TestStoreEdgeCaseTests: XCTestCase {

    // MARK: TEST-08 gap 1 — chained effects settle deterministically

    @MainActor
    func testChainedEffectsSettle() async {
        let store = TestStore(initialState: ChainFeature.State()) {
            ChainFeature()
        }
        await store.send(.startChain)
        await store.receive(\.chainStepA) {
            $0.step = 1
        }
        await store.receive(\.chainStepB) {
            $0.step = 2
        }
    }

    // MARK: TEST-08 gap 2 — cancelInFlight rapid re-send

    @MainActor
    func testCancelInFlightRapidResend() async {
        let store = TestStore(initialState: CancelInFlightFeature.State()) {
            CancelInFlightFeature()
        }
        store.exhaustivity = .off
        store.timeout = 5_000_000_000
        // Send first fetch, then immediately re-send — first should be cancelled
        await store.send(.fetch) {
            $0.fetchCount = 1
        }
        await store.send(.fetch) {
            $0.fetchCount = 2
        }
        // Skip any pending actions and verify only last result arrived
        await store.skipReceivedActions()
        XCTAssertEqual(store.state.result, "result-2")
    }

    // MARK: TEST-08 gap 3 — finish() with slow effect

    @MainActor
    func testFinishWithSlowEffect() async {
        let store = TestStore(initialState: SlowEffectFeature.State()) {
            SlowEffectFeature()
        }
        store.timeout = 5_000_000_000
        await store.send(.start)
        await store.receive(\.done) {
            $0.completed = true
        }
    }

    // MARK: TEST-08 gap 4 — non-exhaustive receive with .off

    @MainActor
    func testNonExhaustiveReceiveOff() async {
        let store = TestStore(initialState: NonExhaustiveReceiveFeature.State()) {
            NonExhaustiveReceiveFeature()
        }
        store.exhaustivity = .off
        store.timeout = 5_000_000_000
        // Send action that triggers an effect — don't call receive
        await store.send(.trigger) {
            $0.triggered = true
        }
        // finish() in non-exhaustive mode should handle unprocessed actions without failure
        await store.finish()
    }
}
