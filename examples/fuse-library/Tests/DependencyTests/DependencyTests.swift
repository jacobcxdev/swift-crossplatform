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
}
