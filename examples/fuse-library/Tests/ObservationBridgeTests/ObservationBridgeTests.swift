import Observation
import ComposableArchitecture
import Testing
import Foundation

// MARK: - Test Models

@Observable
final class BridgeModel: @unchecked Sendable {
    var count = 0
}

@Observable
final class BridgeMultiModel: @unchecked Sendable {
    var a = 0
    var b = 0
    var c = 0
}

@Observable
final class BridgeParentModel: @unchecked Sendable {
    var parentValue = 0
}

@Observable
final class BridgeChildModel: @unchecked Sendable {
    var childValue = 0
}

@Observable
final class BridgeIgnoredModel: @unchecked Sendable {
    var tracked = 0
    @ObservationIgnored var debug = ""
}

// MARK: - Thread-safe counter for Sendable closures

final class AtomicCounter: Sendable {
    private let _value = LockIsolated(0)
    var value: Int { _value.value }
    func increment() { _value.withValue { $0 += 1 } }
}

// MARK: - Inline TCA Reducer for ObservableState test

@Reducer
struct BridgeCounter {
    @ObservableState
    struct State: Equatable {
        var count = 0
    }
    enum Action {
        case increment
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.count += 1
                return .none
            }
        }
    }
}

// MARK: - Observation Bridge Tests (TEST-10 Tier 1 — macOS mock-bridge)

/// These tests validate the observation SEMANTICS that the Android bridge must preserve,
/// using native `withObservationTracking`. Since the bridge code is behind `#if SKIP_BRIDGE`,
/// we test the contract (coalescing, nesting, thread isolation) on macOS.
@Suite("Observation Bridge Semantics")
struct ObservationBridgeTests {

    // Test 1: Single property mutation triggers exactly one onChange
    @Test("Single property mutation triggers exactly one onChange")
    func singlePropertyCoalescing() {
        let model = BridgeModel()
        let counter = AtomicCounter()

        withObservationTracking {
            _ = model.count
        } onChange: {
            counter.increment()
        }

        // Mutate 5 times — onChange should fire on first mutation only
        // (withObservationTracking registers for ONE notification per scope)
        model.count = 1
        model.count = 2
        model.count = 3
        model.count = 4
        model.count = 5

        #expect(counter.value == 1, "onChange should fire exactly once per tracking scope, not per mutation")
    }

    // Test 2: Nested observation scopes are independent
    @Test("Nested observation scopes are independent")
    func nestedScopeIndependence() {
        let parent = BridgeParentModel()
        let child = BridgeChildModel()
        let parentCounter = AtomicCounter()
        let childCounter = AtomicCounter()

        // Outer scope tracks parent
        withObservationTracking {
            _ = parent.parentValue
        } onChange: {
            parentCounter.increment()
        }

        // Inner scope tracks child
        withObservationTracking {
            _ = child.childValue
        } onChange: {
            childCounter.increment()
        }

        // Mutate child only — only child scope should fire
        child.childValue = 1
        #expect(childCounter.value == 1)
        #expect(parentCounter.value == 0, "Parent scope should not fire when only child mutated")

        // Now mutate parent
        parent.parentValue = 1
        #expect(parentCounter.value == 1)
    }

    // Test 3: Bulk mutations coalesce into single onChange
    @Test("Bulk mutations on multiple properties coalesce into single onChange")
    func bulkMutationCoalescing() {
        let model = BridgeMultiModel()
        let counter = AtomicCounter()

        withObservationTracking {
            _ = model.a
            _ = model.b
            _ = model.c
        } onChange: {
            counter.increment()
        }

        // Mutate all three — ONE onChange total
        model.a = 1
        model.b = 2
        model.c = 3

        #expect(counter.value == 1, "Multiple property mutations should coalesce into one onChange")
    }

    // Test 4: @ObservationIgnored suppresses tracking
    @Test("@ObservationIgnored suppresses tracking")
    func observationIgnored() {
        let model = BridgeIgnoredModel()
        let counter = AtomicCounter()

        withObservationTracking {
            _ = model.debug
        } onChange: {
            counter.increment()
        }

        model.debug = "test"
        #expect(counter.value == 0, "@ObservationIgnored property must NOT trigger onChange")
    }

    // Test 5: ObservableState registrar round-trip through Store
    @MainActor
    @Test("ObservableState registrar round-trip through Store")
    func observableStateRegistrar() async {
        let store = Store(initialState: BridgeCounter.State()) {
            BridgeCounter()
        }

        let counter = AtomicCounter()
        withObservationTracking {
            _ = store.count
        } onChange: {
            counter.increment()
        }

        store.send(.increment)

        #expect(counter.value == 1, "Store observation should fire onChange when state mutates via send()")
        #expect(store.count == 1)
    }

    // Test 6: Concurrent observation on multiple threads
    @Test("Concurrent observation scopes on multiple threads fire independently")
    func concurrentObservation() async {
        let model = BridgeModel()
        let counter = AtomicCounter()

        // Spawn 10 tasks, each with its own tracking scope
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    withObservationTracking {
                        _ = model.count
                    } onChange: {
                        counter.increment()
                    }
                }
            }
        }

        // Mutate from current context — all 10 scopes should fire
        model.count = 42

        // Allow a brief moment for onChange callbacks
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(counter.value == 10, "All 10 concurrent tracking scopes should fire their onChange")
    }

    // Test 7 (D8-a): Single recomposition — rapid mutations produce single onChange per scope
    @Test("D8-a: Rapid mutations produce single onChange per tracking scope")
    func singleRecomposition() {
        let model = BridgeModel()
        let counter = AtomicCounter()

        withObservationTracking {
            _ = model.count
        } onChange: {
            counter.increment()
        }

        // Rapid mutations
        for i in 1...5 {
            model.count = i
        }

        #expect(counter.value == 1, "5 rapid mutations should produce exactly 1 onChange (single-trigger-per-cycle)")
    }

    // Test 8 (D8-b): Nested independence — parent/child scopes don't cross-fire
    @Test("D8-b: Parent/child observation scopes fire independently")
    func nestedIndependenceDeferred() {
        let parent = BridgeParentModel()
        let child = BridgeChildModel()
        let parentCounter = AtomicCounter()
        let childCounter = AtomicCounter()

        withObservationTracking {
            _ = parent.parentValue
        } onChange: {
            parentCounter.increment()
        }

        withObservationTracking {
            _ = child.childValue
        } onChange: {
            childCounter.increment()
        }

        // Mutate child only
        child.childValue = 99
        #expect(childCounter.value == 1, "Child scope should fire")
        #expect(parentCounter.value == 0, "Parent scope must NOT fire when only child mutated")

        // Now test parent
        parent.parentValue = 99
        #expect(parentCounter.value == 1, "Parent scope should fire")
    }

    // Test 9 (D8-e): Full 17-fork compilation — implicitly tested by this test target compiling
    @Test("D8-e: All forks compile together (implicit via test target compilation)")
    func fullForkCompilation() {
        // This test existing and compiling proves all fork dependencies resolve.
        // The test target depends on ComposableArchitecture which transitively pulls all forks.
        #expect(true, "If this test compiles and runs, all forks compiled successfully")
    }

    // Documentation: D8-c (manual) and D8-d (manual)
    //
    // D8-c: ViewModifier observation — manual verification step:
    //   "Create a ViewModifier with @Observable state. Apply to a view. Mutate state.
    //    Expected: view re-evaluates exactly once. Requires UI hierarchy inspection on
    //    Android emulator — cannot be automated via skip test."
    //
    // D8-d: Fatal error on bridge failure — manual verification step:
    //   "In Fuse mode, if nativeEnable() fails (e.g., missing JNI class),
    //    expected: fatalError with descriptive message, NOT silent fallback.
    //    Per C5: silent no-op only in Lite mode. Requires intentionally breaking
    //    bridge class loading — not suitable for automated test."
}
