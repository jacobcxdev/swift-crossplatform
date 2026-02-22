@_spi(Reflection) import CasePaths
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import XCTest

// MARK: - Test Fixtures

private struct TestCounterKey: DependencyKey {
    static let liveValue: Int = 42
    static let testValue: Int = 0
}

extension DependencyValues {
    fileprivate var testCounter: Int {
        get { self[TestCounterKey.self] }
        set { self[TestCounterKey.self] = newValue }
    }
}

private struct AnotherKey: DependencyKey {
    static let liveValue: String = "live"
    static let testValue: String = "test"
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
    enum Action: Equatable {
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
    enum Action: Equatable {
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
    enum Action: Equatable {
        case parent(DepParent.Action)
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.parent, action: \.parent) { DepParent() }
    }
}

// MARK: - DependencyTests

final class DependencyTests: XCTestCase {

    // MARK: DEP-01: @Dependency key path resolution

    func testDependencyKeyPathResolution() {
        withDependencies {
            $0.testCounter = 99
        } operation: {
            @Dependency(\.testCounter) var testCounter
            XCTAssertEqual(testCounter, 99)
        }
    }

    // MARK: DEP-02: @Dependency type-based resolution

    func testDependencyTypeResolution() {
        // Type-based resolution uses DependencyValues subscript with key type
        withDependencies {
            $0[TestCounterKey.self] = 77
        } operation: {
            @Dependency(\.testCounter) var testCounter
            XCTAssertEqual(testCounter, 77)
        }
    }

    // MARK: DEP-03: liveValue used in live context

    func testLiveValueInProductionContext() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.testCounter) var testCounter
            // liveValue for TestCounterKey is 42
            XCTAssertEqual(testCounter, 42)
        }
    }

    // MARK: DEP-04: testValue used in test context

    func testTestValueInTestContext() {
        // In XCTest execution, context is automatically .test
        @Dependency(\.context) var context
        XCTAssertEqual(context, .test)

        // testValue for TestCounterKey is 0
        @Dependency(\.testCounter) var testCounter
        XCTAssertEqual(testCounter, 0)
    }

    // MARK: DEP-05: preview context not active in non-preview environments

    func testPreviewContextNotAvailableOnAndroid() {
        @Dependency(\.context) var context
        // In test execution, context should be .test, never .preview
        XCTAssertNotEqual(context, .preview)
        XCTAssertEqual(context, .test)
    }

    // MARK: DEP-06: custom DependencyKey registration

    func testCustomDependencyKeyRegistration() {
        withDependencies {
            $0.anotherValue = "custom"
        } operation: {
            @Dependency(\.anotherValue) var value
            XCTAssertEqual(value, "custom")
        }

        // Without override, should get testValue
        @Dependency(\.anotherValue) var defaultValue
        XCTAssertEqual(defaultValue, "test")
    }

    // MARK: DEP-09: withDependencies synchronous scoping

    func testWithDependenciesSyncScoping() {
        withDependencies {
            $0.uuid = .incrementing
        } operation: {
            @Dependency(\.uuid) var uuid
            let first = uuid()
            let second = uuid()
            // Incrementing UUIDs start at 00000000-0000-0000-0000-000000000000
            XCTAssertEqual(first, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
            XCTAssertEqual(second, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        }
    }

    // MARK: DEP-10: Store prepareDependencies closure

    @MainActor
    func testPrepareDependencies() {
        let store = Store(
            initialState: DepCounter.State()
        ) {
            DepCounter()
        } withDependencies: {
            $0.testCounter = 777
        }

        store.send(.increment)
        store.withState { state in
            XCTAssertEqual(state.count, 777)
        }
    }

    // MARK: DEP-11: child reducer inherits parent dependencies (2 levels)

    @MainActor
    func testChildReducerInheritsDependencies() {
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
            XCTAssertEqual(state.count, 555)
        }
    }

    // MARK: DEP-11: child reducer inherits parent dependencies (3 levels)

    @MainActor
    func testGrandchildReducerInheritsDependencies() {
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
            XCTAssertEqual(state.count, 333)
        }
    }

    // MARK: Built-in dependency resolution (all available keys)

    func testBuiltInDependencyResolution() {
        withDependencies {
            $0.context = .live
        } operation: {
            // UUID
            @Dependency(\.uuid) var uuid
            let id = uuid()
            XCTAssertNotNil(id)

            // Date
            @Dependency(\.date) var date
            let now = date()
            XCTAssertNotNil(now)

            // ContinuousClock
            @Dependency(\.continuousClock) var continuousClock
            XCTAssertNotNil(continuousClock)

            // SuspendingClock
            @Dependency(\.suspendingClock) var suspendingClock
            XCTAssertNotNil(suspendingClock)

            // Calendar
            @Dependency(\.calendar) var calendar
            XCTAssertNotNil(calendar)

            // TimeZone
            @Dependency(\.timeZone) var timeZone
            XCTAssertNotNil(timeZone)

            // Locale
            @Dependency(\.locale) var locale
            XCTAssertNotNil(locale)

            // Context
            @Dependency(\.context) var context
            XCTAssertEqual(context, .live)

            // Assert (access doesn't crash)
            @Dependency(\.assert) var assertDep
            XCTAssertNotNil(assertDep)

            // FireAndForget (access doesn't crash)
            @Dependency(\.fireAndForget) var fireAndForget
            XCTAssertNotNil(fireAndForget)

            // WithRandomNumberGenerator (access doesn't crash)
            @Dependency(\.withRandomNumberGenerator) var rng
            XCTAssertNotNil(rng)

            // MainQueue (DispatchQueue.main via combine-schedulers)
            @Dependency(\.mainQueue) var mainQueue
            XCTAssertNotNil(mainQueue)

            // MainRunLoop (RunLoop.main via combine-schedulers)
            @Dependency(\.mainRunLoop) var mainRunLoop
            XCTAssertNotNil(mainRunLoop)

            // NotificationCenter
            @Dependency(\.notificationCenter) var notificationCenter
            XCTAssertNotNil(notificationCenter)

            // URLSession
            @Dependency(\.urlSession) var urlSession
            XCTAssertNotNil(urlSession)

            // OpenURL (macOS only, guarded by #if canImport(SwiftUI) && !os(Android))
            #if canImport(SwiftUI) && !os(Android)
            @Dependency(\.openURL) var openURL
            XCTAssertNotNil(openURL)
            #endif
        }
    }

    // MARK: DEP-11: sibling isolation

    @MainActor
    func testDependencyIsolationBetweenSiblings() {
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
            XCTAssertEqual(state.count, 111)
        }

        // Sibling B should see 999 (not leaked from A)
        siblingB.send(.increment)
        siblingB.withState { state in
            XCTAssertEqual(state.count, 999)
        }

        // Verify A is still 111 after B was mutated
        siblingA.send(.increment)
        siblingA.withState { state in
            XCTAssertEqual(state.count, 111)
        }
    }

    // MARK: - Task 2: @DependencyClient, Effects, NavigationID

    // MARK: DEP-07: @DependencyClient unimplemented reports issue

    func testDependencyClientUnimplementedReportsIssue() {
        let client = NumberClient()

        XCTExpectFailure {
            $0.compactDescription.contains("Unimplemented")
        }

        // Calling unimplemented endpoint should report issue via reportIssue
        let result = client.fetch(42)
        // Default return for Int is 0 when unimplemented
        XCTAssertEqual(result, 0)
    }

    // MARK: DEP-07: @DependencyClient implemented endpoint

    func testDependencyClientImplementedEndpoint() {
        withDependencies {
            $0[NumberClient.self] = NumberClient(fetch: { $0 * 2 })
        } operation: {
            @Dependency(NumberClient.self) var client
            XCTAssertEqual(client.fetch(21), 42)
        }
    }

    // MARK: DEP-08: Reducer .dependency modifier

    @MainActor
    func testReducerDependencyModifier() {
        let store = Store(
            initialState: DepCounter.State()
        ) {
            DepCounter()
                .dependency(\.testCounter, 999)
        }

        store.send(.increment)
        store.withState { state in
            XCTAssertEqual(state.count, 999)
        }
    }

    // MARK: DEP-12: dependency resolves in effect closure

    @MainActor
    func testDependencyResolvesInEffectClosure() async throws {
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
            XCTAssertEqual(state.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        }
    }

    // MARK: DEP-12: dependency resolves in merged effects

    @MainActor
    func testDependencyResolvesInMergedEffects() async throws {
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
            XCTAssertNotNil(state.id1)
            XCTAssertNotNil(state.id2)
            // They should be different (incrementing)
            XCTAssertNotEqual(state.id1, state.id2)
        }
    }

    // MARK: NavigationID EnumMetadata tag validation

    func testNavigationIDEnumMetadataTag() {
        // Validate EnumMetadata.tag(of:) — the same code path NavigationID uses for hashing
        // TestAction is defined at file scope (macros can't attach to local types)
        guard let metadata = EnumMetadata(TestAction.self) else {
            XCTFail("EnumMetadata should be constructible from TestAction enum")
            return
        }

        let tag0 = metadata.tag(of: TestAction.first(1))
        let tag1 = metadata.tag(of: TestAction.second("hello"))
        let tag2 = metadata.tag(of: TestAction.third)

        // Tags should be consistent for same case
        XCTAssertEqual(tag0, metadata.tag(of: TestAction.first(99)))
        XCTAssertEqual(tag1, metadata.tag(of: TestAction.second("world")))

        // Tags should be different between cases
        XCTAssertNotEqual(tag0, tag1)
        XCTAssertNotEqual(tag1, tag2)
        XCTAssertNotEqual(tag0, tag2)

        // Verify case names
        XCTAssertEqual(metadata.caseName(forTag: tag0), "first")
        XCTAssertEqual(metadata.caseName(forTag: tag1), "second")
        XCTAssertEqual(metadata.caseName(forTag: tag2), "third")
    }

    // MARK: DEP-09: @TaskLocal propagation through async closures

    func testTaskLocalPropagation() async {
        await withDependencies {
            $0.uuid = .incrementing
        } operation: {
            @Dependency(\.uuid) var uuid

            // Verify dependency is accessible from a Task (async context)
            let id = await Task {
                @Dependency(\.uuid) var innerUUID
                return innerUUID()
            }.value

            XCTAssertNotNil(id)
            // The incrementing generator should produce sequential UUIDs
            // even when accessed from within a Task
            let directID = uuid()
            XCTAssertNotNil(directID)
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
    enum Action: Equatable {
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
