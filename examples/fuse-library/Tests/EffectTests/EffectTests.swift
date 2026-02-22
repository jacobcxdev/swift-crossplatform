import ComposableArchitecture
import XCTest

// MARK: - Test Reducers

@Reducer
struct EffectNoneFeature {
    struct State: Equatable { var count = 0 }
    enum Action { case noop }
    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .noop: return .none
            }
        }
    }
}

@Reducer
struct EffectRunFeature {
    struct State: Equatable {
        var value: String = ""
    }
    enum Action: Equatable {
        case fetch
        case response(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .fetch:
                return .run { send in
                    await send(.response("hello"))
                }
            case let .response(value):
                state.value = value
                return .none
            }
        }
    }
}

@Reducer
struct BackgroundSendFeature {
    struct State: Equatable {
        var value: String = ""
    }
    enum Action: Equatable {
        case fetch
        case response(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .fetch:
                return .run { send in
                    // Send from a detached task to simulate background sending
                    await Task.detached {
                        await send(.response("from-background"))
                    }.value
                }
            case let .response(value):
                state.value = value
                return .none
            }
        }
    }
}

@Reducer
struct MergeFeature {
    struct State: Equatable {
        var values: [String] = []
    }
    enum Action: Equatable {
        case start
        case received(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .merge(
                    .run { send in await send(.received("a")) },
                    .run { send in await send(.received("b")) }
                )
            case let .received(value):
                state.values.append(value)
                return .none
            }
        }
    }
}

@Reducer
struct ConcatenateFeature {
    struct State: Equatable {
        var values: [Int] = []
    }
    enum Action: Equatable {
        case start
        case received(Int)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .concatenate(
                    .run { send in await send(.received(1)) },
                    .run { send in await send(.received(2)) }
                )
            case let .received(value):
                state.values.append(value)
                return .none
            }
        }
    }
}

enum CancelID: Hashable { case timer }

@Reducer
struct CancellableFeature {
    struct State: Equatable {
        var completed = false
    }
    enum Action: Equatable {
        case start
        case cancelEffect
        case completed
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .run { send in
                    try await Task.sleep(for: .seconds(10))
                    await send(.completed)
                }
                .cancellable(id: CancelID.timer)
            case .cancelEffect:
                return .cancel(id: CancelID.timer)
            case .completed:
                state.completed = true
                return .none
            }
        }
    }
}

@Reducer
struct CancelInFlightFeature {
    struct State: Equatable {
        var value: Int = 0
    }
    enum Action: Equatable {
        case request(Int)
        case response(Int)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .request(id):
                return .run { send in
                    try await Task.sleep(for: .milliseconds(50))
                    await send(.response(id))
                }
                .cancellable(id: CancelID.timer, cancelInFlight: true)
            case let .response(id):
                state.value = id
                return .none
            }
        }
    }
}

@Reducer
struct DependencyEffectFeature {
    struct State: Equatable {
        var elapsed = false
    }
    enum Action: Equatable {
        case start
        case done
    }
    @Dependency(\.continuousClock) var clock
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .run { [clock] send in
                    try await clock.sleep(for: .milliseconds(1))
                    await send(.done)
                }
            case .done:
                state.elapsed = true
                return .none
            }
        }
    }
}

// MARK: - Tests

final class EffectTests: XCTestCase {

    // MARK: TCA-10: Effect.none

    @MainActor
    func testEffectNone() {
        let store = Store(initialState: EffectNoneFeature.State(count: 42)) {
            EffectNoneFeature()
        }
        store.send(.noop)
        XCTAssertEqual(store.withState(\.count), 42)
    }

    // MARK: TCA-11: Effect.run

    @MainActor
    func testEffectRun() async throws {
        let store = Store(initialState: EffectRunFeature.State()) {
            EffectRunFeature()
        }
        store.send(.fetch)
        // Wait for the effect to complete
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.withState(\.value), "hello")
    }

    // MARK: TCA-11: Effect.run from background thread

    @MainActor
    func testEffectRunFromBackgroundThread() async throws {
        let store = Store(initialState: BackgroundSendFeature.State()) {
            BackgroundSendFeature()
        }
        store.send(.fetch)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.withState(\.value), "from-background")
    }

    // MARK: TCA-12: Effect.merge

    @MainActor
    func testEffectMerge() async throws {
        let store = Store(initialState: MergeFeature.State()) {
            MergeFeature()
        }
        store.send(.start)
        try await Task.sleep(for: .milliseconds(200))
        let values = store.withState(\.values)
        XCTAssertEqual(values.count, 2)
        XCTAssertTrue(values.contains("a"))
        XCTAssertTrue(values.contains("b"))
    }

    // MARK: TCA-13: Effect.concatenate

    @MainActor
    func testEffectConcatenate() async throws {
        let store = Store(initialState: ConcatenateFeature.State()) {
            ConcatenateFeature()
        }
        store.send(.start)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.withState(\.values), [1, 2])
    }

    // MARK: TCA-14: Effect.cancellable

    @MainActor
    func testEffectCancellable() async throws {
        let store = Store(initialState: CancellableFeature.State()) {
            CancellableFeature()
        }
        // Start a long-running effect then immediately cancel it
        store.send(.start)
        store.send(.cancelEffect)
        // Wait to verify the effect was cancelled (completed should remain false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(store.withState(\.completed))
    }

    // MARK: TCA-14: cancelInFlight

    @MainActor
    func testEffectCancelInFlight() async throws {
        let store = Store(initialState: CancelInFlightFeature.State()) {
            CancelInFlightFeature()
        }
        // Send two requests rapidly; cancelInFlight should cancel the first
        store.send(.request(1))
        store.send(.request(2))
        try await Task.sleep(for: .milliseconds(200))
        // Only the second request should complete
        XCTAssertEqual(store.withState(\.value), 2)
    }

    // MARK: TCA-15: Effect.cancel

    @MainActor
    func testEffectCancel() async throws {
        let store = Store(initialState: CancellableFeature.State()) {
            CancellableFeature()
        }
        store.send(.start)
        // Cancel via Effect.cancel(id:)
        store.send(.cancelEffect)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(store.withState(\.completed))
    }

    // MARK: TCA-11 + DEP-12: Effect.run with dependency

    @MainActor
    func testEffectRunWithDependencies() async throws {
        let store = Store(initialState: DependencyEffectFeature.State()) {
            DependencyEffectFeature()
        } withDependencies: {
            $0.continuousClock = ContinuousClock()
        }
        store.send(.start)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(store.withState(\.elapsed))
    }
}
