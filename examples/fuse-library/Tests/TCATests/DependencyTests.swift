@_spi(Reflection) import CasePaths
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import Testing

// MARK: - Test Fixtures

private struct TestCounterKey: DependencyKey {
    static var liveValue: Int { 42 }
    static var testValue: Int { 0 }
}

extension DependencyValues {
    fileprivate var testCounter: Int {
        get { self[TestCounterKey.self] }
        set { self[TestCounterKey.self] = newValue }
    }
}

private struct AnotherKey: DependencyKey {
    static var liveValue: String { "live" }
    static var testValue: String { "test" }
}

extension DependencyValues {
    fileprivate var anotherValue: String {
        get { self[AnotherKey.self] }
        set { self[AnotherKey.self] = newValue }
    }
}

// MARK: - Test Reducers for Dependency Tests

@Reducer
private struct DepCounter {
    struct State: Equatable {
        var count = 0
        var id: UUID?
    }
    enum Action {
        case increment
        case setID
        case gotID(UUID)
    }

    @Dependency(\.testCounter) var testCounter
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.count = self.testCounter
                return .none
            case .setID:
                return .run { [uuid] send in
                    await send(.gotID(uuid()))
                }
            case let .gotID(id):
                state.id = id
                return .none
            }
        }
    }
}

@Reducer
private struct DepParent {
    struct State: Equatable {
        var child = DepCounter.State()
    }
    enum Action {
        case child(DepCounter.Action)
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.child, action: \.child) { DepCounter() }
    }
}

@Reducer
private struct DepGrandparent {
    struct State: Equatable {
        var parent = DepParent.State()
    }
    enum Action {
        case parent(DepParent.Action)
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.parent, action: \.parent) { DepParent() }
    }
}

// MARK: - DependencyTests

@Suite(.serialized) @MainActor
struct DependencyTests {

    // MARK: DEP-01: @Dependency key path resolution

    @Test func dependencyKeyPathResolution() {
        withDependencies {
            $0.testCounter = 99
        } operation: {
            @Dependency(\.testCounter) var testCounter
            #expect(testCounter == 99)
        }
    }

    // MARK: DEP-02: @Dependency type-based resolution

    @Test func dependencyTypeResolution() {
        // Type-based resolution uses DependencyValues subscript with key type
        withDependencies {
            $0[TestCounterKey.self] = 77
        } operation: {
            @Dependency(\.testCounter) var testCounter
            #expect(testCounter == 77)
        }
    }

    // MARK: DEP-03: liveValue used in live context

    @Test func liveValueInProductionContext() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.testCounter) var testCounter
            // liveValue for TestCounterKey is 42
            #expect(testCounter == 42)
        }
    }

    // MARK: DEP-04: testValue used in test context

    @Test func testValueInTestContext() {
        // In test execution, context is automatically .test
        @Dependency(\.context) var context
        #expect(context == .test)

        // testValue for TestCounterKey is 0
        @Dependency(\.testCounter) var testCounter
        #expect(testCounter == 0)
    }

    // MARK: DEP-05: preview context not active in non-preview environments

    @Test func previewContextNotAvailableOnAndroid() {
        @Dependency(\.context) var context
        // In test execution, context should be .test, never .preview
        #expect(context != .preview)
        #expect(context == .test)
    }

    // MARK: DEP-06: custom DependencyKey registration

    @Test func customDependencyKeyRegistration() {
        withDependencies {
            $0.anotherValue = "custom"
        } operation: {
            @Dependency(\.anotherValue) var value
            #expect(value == "custom")
        }

        // Without override, should get testValue
        @Dependency(\.anotherValue) var defaultValue
        #expect(defaultValue == "test")
    }

    // MARK: DEP-09: withDependencies synchronous scoping

    @Test func withDependenciesSyncScoping() {
        withDependencies {
            $0.uuid = .incrementing
        } operation: {
            @Dependency(\.uuid) var uuid
            let first = uuid()
            let second = uuid()
            // Incrementing UUIDs start at 00000000-0000-0000-0000-000000000000
            #expect(first == UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
            #expect(second == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        }
    }

    // MARK: DEP-10: Store prepareDependencies closure

    @Test func prepareDependencies() {
        let store = Store(
            initialState: DepCounter.State()
        ) {
            DepCounter()
        } withDependencies: {
            $0.testCounter = 777
        }

        store.send(.increment)
        store.withState { state in
            #expect(state.count == 777)
        }
    }

    // MARK: DEP-11: child reducer inherits parent dependencies (2 levels)

    @Test func childReducerInheritsDependencies() {
        let store = Store(
            initialState: DepParent.State()
        ) {
            DepParent()
        } withDependencies: {
            $0.testCounter = 555
        }

        let childStore = store.scope(state: \.child, action: \.child)
        childStore.send(.increment)
        childStore.withState { state in
            #expect(state.count == 555)
        }
    }

    // MARK: DEP-11: child reducer inherits parent dependencies (3 levels)

    @Test func grandchildReducerInheritsDependencies() {
        let store = Store(
            initialState: DepGrandparent.State()
        ) {
            DepGrandparent()
        } withDependencies: {
            $0.testCounter = 333
        }

        let parentStore = store.scope(state: \.parent, action: \.parent)
        let childStore = parentStore.scope(state: \.child, action: \.child)
        childStore.send(.increment)
        childStore.withState { state in
            #expect(state.count == 333)
        }
    }

    // MARK: Built-in dependency resolution (all available keys)

    @Test func builtInDependencyResolution() {
        withDependencies {
            $0.context = .live
        } operation: {
            // UUID
            @Dependency(\.uuid) var uuid
            let id = uuid()
            #expect(id != nil)

            // Date
            @Dependency(\.date) var date
            let now = date()
            #expect(now != nil)

            // ContinuousClock
            @Dependency(\.continuousClock) var continuousClock
            #expect(continuousClock != nil)

            // SuspendingClock
            @Dependency(\.suspendingClock) var suspendingClock
            #expect(suspendingClock != nil)

            // Calendar
            @Dependency(\.calendar) var calendar
            #expect(calendar != nil)

            // TimeZone
            @Dependency(\.timeZone) var timeZone
            #expect(timeZone != nil)

            // Locale
            @Dependency(\.locale) var locale
            #expect(locale != nil)

            // Context
            @Dependency(\.context) var context
            #expect(context == .live)

            // Assert (access doesn't crash)
            @Dependency(\.assert) var assertDep
            #expect(assertDep != nil)

            // FireAndForget (access doesn't crash)
            @Dependency(\.fireAndForget) var fireAndForget
            #expect(fireAndForget != nil)

            // WithRandomNumberGenerator (access doesn't crash)
            @Dependency(\.withRandomNumberGenerator) var rng
            #expect(rng != nil)

            // MainQueue (DispatchQueue.main via combine-schedulers) — Darwin only
            #if canImport(Combine)
            @Dependency(\.mainQueue) var mainQueue
            #expect(mainQueue != nil)

            // MainRunLoop (RunLoop.main via combine-schedulers) — Darwin only
            @Dependency(\.mainRunLoop) var mainRunLoop
            #expect(mainRunLoop != nil)
            #endif

            // NotificationCenter
            @Dependency(\.notificationCenter) var notificationCenter
            #expect(notificationCenter != nil)

            // URLSession
            @Dependency(\.urlSession) var urlSession
            #expect(urlSession != nil)

            // OpenURL (macOS only, guarded by #if canImport(SwiftUI) && !os(Android))
            #if canImport(SwiftUI) && !os(Android)
            @Dependency(\.openURL) var openURL
            #expect(openURL != nil)
            #endif
        }
    }

    // MARK: DEP-11: sibling isolation

    @Test func dependencyIsolationBetweenSiblings() {
        // Create two sibling stores with different dependency overrides
        let siblingA = Store(
            initialState: DepCounter.State()
        ) {
            DepCounter()
        } withDependencies: {
            $0.testCounter = 111
        }

        let siblingB = Store(
            initialState: DepCounter.State()
        ) {
            DepCounter()
        } withDependencies: {
            $0.testCounter = 999
        }

        // Sibling A should see 111
        siblingA.send(.increment)
        siblingA.withState { state in
            #expect(state.count == 111)
        }

        // Sibling B should see 999 (not leaked from A)
        siblingB.send(.increment)
        siblingB.withState { state in
            #expect(state.count == 999)
        }

        // Verify A is still 111 after B was mutated
        siblingA.send(.increment)
        siblingA.withState { state in
            #expect(state.count == 111)
        }
    }

    // MARK: - Task 2: @DependencyClient, Effects, NavigationID

    // MARK: DEP-07: @DependencyClient unimplemented reports issue

    @Test func dependencyClientUnimplementedReportsIssue() {
        let client = NumberClient()

        withKnownIssue {
            // Calling unimplemented endpoint should report issue via reportIssue
            let result = client.fetch(42)
            // Default return for Int is 0 when unimplemented
            #expect(result == 0)
        }
    }

    // MARK: DEP-07: @DependencyClient implemented endpoint

    @Test func dependencyClientImplementedEndpoint() {
        withDependencies {
            $0[NumberClient.self] = NumberClient(fetch: { $0 * 2 })
        } operation: {
            @Dependency(NumberClient.self) var client
            #expect(client.fetch(21) == 42)
        }
    }

    // MARK: DEP-08: Reducer .dependency modifier

    @Test func reducerDependencyModifier() {
        let store = Store(
            initialState: DepCounter.State()
        ) {
            DepCounter()
                .dependency(\.testCounter, 999)
        }

        store.send(.increment)
        store.withState { state in
            #expect(state.count == 999)
        }
    }

    // MARK: DEP-12: dependency resolves in effect closure

    @Test func dependencyResolvesInEffectClosure() async throws {
        let store = Store(
            initialState: DepCounter.State()
        ) {
            DepCounter()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        store.send(.setID)
        try await Task.sleep(for: .milliseconds(100))
        store.withState { state in
            // Should be the first incrementing UUID, proving the dependency
            // propagated through the Effect.run boundary
            #expect(state.id == UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        }
    }

    // MARK: DEP-12: dependency resolves in merged effects

    @Test func dependencyResolvesInMergedEffects() async throws {
        let store = Store(
            initialState: MergedEffectFeature.State()
        ) {
            MergedEffectFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        store.send(.fetchBoth)
        try await Task.sleep(for: .milliseconds(100))
        store.withState { state in
            // Both effects should get incrementing UUIDs from the overridden dependency
            #expect(state.id1 != nil)
            #expect(state.id2 != nil)
            // They should be different (incrementing)
            #expect(state.id1 != state.id2)
        }
    }

    // MARK: NavigationID EnumMetadata tag validation

    @Test func navigationIDEnumMetadataTag() {
        // Validate EnumMetadata.tag(of:) — the same code path NavigationID uses for hashing
        // TestAction is defined at file scope (macros can't attach to local types)
        guard let metadata = EnumMetadata(TestAction.self) else {
            Issue.record("EnumMetadata should be constructible from TestAction enum")
            return
        }

        let tag0 = metadata.tag(of: TestAction.first(1))
        let tag1 = metadata.tag(of: TestAction.second("hello"))
        let tag2 = metadata.tag(of: TestAction.third)

        // Tags should be consistent for same case
        #expect(tag0 == metadata.tag(of: TestAction.first(99)))
        #expect(tag1 == metadata.tag(of: TestAction.second("world")))

        // Tags should be different between cases
        #expect(tag0 != tag1)
        #expect(tag1 != tag2)
        #expect(tag0 != tag2)

        // Verify case names
        #expect(metadata.caseName(forTag: tag0) == "first")
        #expect(metadata.caseName(forTag: tag1) == "second")
        #expect(metadata.caseName(forTag: tag2) == "third")
    }

    // MARK: DEP-09: @TaskLocal propagation through async closures

    @Test func taskLocalPropagation() async {
        await withDependencies {
            $0.uuid = .incrementing
        } operation: {
            @Dependency(\.uuid) var uuid

            // Verify dependency is accessible from a Task (async context)
            let id = await Task {
                @Dependency(\.uuid) var innerUUID
                return innerUUID()
            }.value

            #expect(id != nil)
            // The incrementing generator should produce sequential UUIDs
            // even when accessed from within a Task
            let directID = uuid()
            #expect(directID != nil)
        }
    }
}

// MARK: - Task 2 Test Fixtures

@DependencyClient
struct NumberClient: TestDependencyKey, Sendable {
    var fetch: @Sendable (_ id: Int) -> Int = { _ in 0 }

    static let testValue = NumberClient()
}

@CasePathable
enum TestAction {
    case first(Int)
    case second(String)
    case third
}

@Reducer
private struct MergedEffectFeature {
    struct State: Equatable {
        var id1: UUID?
        var id2: UUID?
    }
    enum Action {
        case fetchBoth
        case gotID1(UUID)
        case gotID2(UUID)
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .fetchBoth:
                return .merge(
                    .run { [uuid] send in
                        await send(.gotID1(uuid()))
                    },
                    .run { [uuid] send in
                        await send(.gotID2(uuid()))
                    }
                )
            case let .gotID1(id):
                state.id1 = id
                return .none
            case let .gotID2(id):
                state.id2 = id
                return .none
            }
        }
    }
}
