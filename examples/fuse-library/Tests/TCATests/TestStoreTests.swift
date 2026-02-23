import ComposableArchitecture
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing

// MARK: - Test Reducers

@Reducer
struct TSCounter {
    struct State: Equatable {
        var count = 0
    }
    enum Action {
        case increment
        case decrement
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.count += 1
                return .none
            case .decrement:
                state.count -= 1
                return .none
            }
        }
    }
}

@Reducer
struct TSFetchFeature {
    struct State: Equatable {
        var result: String = ""
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
                return .run { send in
                    await send(.response("ok"))
                }
            case let .response(value):
                state.result = value
                return .none
            }
        }
    }
}

@Reducer
struct TSExhaustivityFeature {
    struct State: Equatable {
        var count = 0
        var label = ""
    }
    enum Action {
        case update
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .update:
                state.count = 1
                state.label = "updated"
                return .none
            }
        }
    }
}

@Reducer
struct TSFinishFeature {
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
struct TSMultiEffectFeature {
    struct State: Equatable {
        var values: [String] = []
    }
    @CasePathable
    enum Action: Equatable {
        case triggerMultiple
        case received(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .triggerMultiple:
                return .run { send in
                    await send(.received("a"))
                    await send(.received("b"))
                }
            case let .received(value):
                state.values.append(value)
                return .none
            }
        }
    }
}

@Reducer
struct TSUUIDFeature {
    struct State: Equatable {
        var lastID: String = ""
    }
    enum Action {
        case generate
    }
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

// MARK: - Effect-type coverage reducers (D9)

@Reducer
struct TSRunEffectFeature {
    struct State: Equatable {
        var value: String = ""
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
                return .run { send in
                    await send(.response("run-done"))
                }
            case let .response(value):
                state.value = value
                return .none
            }
        }
    }
}

@Reducer
struct TSMergeEffectFeature {
    struct State: Equatable {
        var values: [String] = []
    }
    @CasePathable
    enum Action: Equatable {
        case start
        case received(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .merge(
                    .run { send in await send(.received("m1")) },
                    .run { send in await send(.received("m2")) }
                )
            case let .received(value):
                state.values.append(value)
                return .none
            }
        }
    }
}

@Reducer
struct TSConcatenateEffectFeature {
    struct State: Equatable {
        var values: [Int] = []
    }
    @CasePathable
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

private enum TSCancelID: Hashable { case request }

@Reducer
struct TSCancellableEffectFeature {
    struct State: Equatable {
        var value: String = ""
    }
    @CasePathable
    enum Action: Equatable {
        case start
        case response(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .run { send in
                    await send(.response("cancellable-done"))
                }
                .cancellable(id: TSCancelID.request)
            case let .response(value):
                state.value = value
                return .none
            }
        }
    }
}

@Reducer
struct TSCancelEffectFeature {
    struct State: Equatable {
        var cancelled = false
        var completed = false
    }
    @CasePathable
    enum Action: Equatable {
        case start
        case cancel
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
                .cancellable(id: TSCancelID.request)
            case .cancel:
                state.cancelled = true
                return .cancel(id: TSCancelID.request)
            case .completed:
                state.completed = true
                return .none
            }
        }
    }
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct TestStoreTests {

    // MARK: TEST-01 — TestStore init

    @Test func testStoreInit() async {
        let store = TestStore(initialState: TSCounter.State(count: 5)) {
            TSCounter()
        }
        #expect(store.state.count == 5)
    }

    // MARK: TEST-02 — send with state assertion

    @Test func sendWithStateAssertion() async {
        let store = TestStore(initialState: TSCounter.State()) {
            TSCounter()
        }
        await store.send(.increment) {
            $0.count = 1
        }
    }

    // MARK: TEST-03 — receive effect action

    @Test func receiveEffectAction() async {
        let store = TestStore(initialState: TSFetchFeature.State()) {
            TSFetchFeature()
        }
        await store.send(.fetch)
        await store.receive(\.response) {
            $0.result = "ok"
        }
    }

    // MARK: TEST-04 — exhaustivity on (default)

    @Test func exhaustivityOnDetectsUnassertedChange() async {
        let store = TestStore(initialState: TSExhaustivityFeature.State()) {
            TSExhaustivityFeature()
        }
        // Exhaustivity is .on by default — sending an action that changes TWO properties
        // but only asserting ONE should cause a test failure.
        // Wrap in withKnownIssue to capture the expected failure.
        await withKnownIssue {
            await store.send(.update) {
                $0.count = 1
                // Deliberately NOT asserting $0.label = "updated"
            }
        }
    }

    // MARK: TEST-05 — exhaustivity off

    @Test func exhaustivityOff() async {
        let store = TestStore(initialState: TSExhaustivityFeature.State()) {
            TSExhaustivityFeature()
        }
        store.exhaustivity = .off
        // Send action that changes state, but omit state assertion entirely.
        // Should pass without failure because exhaustivity is off.
        await store.send(.update)
    }

    // MARK: TEST-06 — finish()

    @Test func finish() async {
        let store = TestStore(initialState: TSFinishFeature.State()) {
            TSFinishFeature()
        }
        store.timeout = 5_000_000_000
        await store.send(.start)
        await store.receive(\.done) {
            $0.completed = true
        }
    }

    // MARK: TEST-07 — skipReceivedActions()

    @Test func skipReceivedActions() async {
        let store = TestStore(initialState: TSMultiEffectFeature.State()) {
            TSMultiEffectFeature()
        }
        store.exhaustivity = .off
        await store.send(.triggerMultiple)
        await store.skipReceivedActions()
        // Test passes without asserting each received action
        expectNoDifference(store.state.values, ["a", "b"])
    }

    // MARK: TEST-09 — .dependencies trait (withDependencies)

    @Test func dependenciesOverride() async {
        let store = TestStore(initialState: TSUUIDFeature.State()) {
            TSUUIDFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        await store.send(.generate) {
            $0.lastID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!.uuidString
        }
    }

    // MARK: D9 — effectDidSubscribe: Effect.run settles correctly

    @Test func effectDidSubscribeRun() async {
        let store = TestStore(initialState: TSRunEffectFeature.State()) {
            TSRunEffectFeature()
        }
        await store.send(.fetch)
        await store.receive(\.response) {
            $0.value = "run-done"
        }
    }

    // MARK: D9 — effectDidSubscribe: .merge effects all complete

    @Test func effectDidSubscribeMerge() async {
        let store = TestStore(initialState: TSMergeEffectFeature.State()) {
            TSMergeEffectFeature()
        }
        store.exhaustivity = .off
        store.timeout = 5_000_000_000
        await store.send(.start)
        await store.skipReceivedActions()
        // Both merged effects should have completed (order not guaranteed per R1b Guard 4)
        let values = store.state.values
        #expect(values.count == 2)
        #expect(values.contains("m1"))
        #expect(values.contains("m2"))
    }

    // MARK: D9 — effectDidSubscribe: .concatenate effects execute in order

    @Test func effectDidSubscribeConcatenate() async {
        let store = TestStore(initialState: TSConcatenateEffectFeature.State()) {
            TSConcatenateEffectFeature()
        }
        await store.send(.start)
        await store.receive(\.received) {
            $0.values = [1]
        }
        await store.receive(\.received) {
            $0.values = [1, 2]
        }
    }

    // MARK: D9 — effectDidSubscribe: .cancellable effect can be awaited

    @Test func effectDidSubscribeCancellable() async {
        let store = TestStore(initialState: TSCancellableEffectFeature.State()) {
            TSCancellableEffectFeature()
        }
        await store.send(.start)
        await store.receive(\.response) {
            $0.value = "cancellable-done"
        }
    }

    // MARK: D9 — effectDidSubscribe: .cancel terminates in-flight effect

    @Test func effectDidSubscribeCancel() async {
        let store = TestStore(initialState: TSCancelEffectFeature.State()) {
            TSCancelEffectFeature()
        }
        await store.send(.start)
        await store.send(.cancel) {
            $0.cancelled = true
        }
        // After cancel, the long-running effect should NOT complete
        #expect(store.state.completed == false)
    }
}
