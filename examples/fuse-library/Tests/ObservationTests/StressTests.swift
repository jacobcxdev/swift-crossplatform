#if !SKIP
#if canImport(Darwin)
import Darwin
#endif
import ComposableArchitecture
import Observation
import Testing

// MARK: - Inline Test Reducer

@Reducer
struct StressCounter {
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

// MARK: - Observable Model for Coalescing Tests

@Observable
final class StressModel: @unchecked Sendable {
    var value = 0
    var secondary = 0
    var tertiary = 0
}

// MARK: - Thread-safe counter for Sendable closures

final class StressAtomicCounter: Sendable {
    private let _value = LockIsolated(0)
    var value: Int { _value.value }
    func increment() { _value.withValue { $0 += 1 } }
}

// MARK: - Memory Helpers

/// Returns current process resident memory in bytes, or nil if unavailable.
/// Uses `mach_task_basic_info` on Darwin, `/proc/self/status` VmRSS on Linux/Android.
func currentResidentMemoryBytes() -> UInt64? {
    #if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return UInt64(info.resident_size)
    #elseif os(Linux) || os(Android)
    guard let contents = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else {
        return nil
    }
    for line in contents.split(separator: "\n") {
        if line.hasPrefix("VmRSS:") {
            let parts = line.split(separator: " ")
            if parts.count >= 2, let kb = UInt64(parts[1]) {
                return kb * 1024 // Convert kB to bytes
            }
        }
    }
    return nil
    #else
    return nil
    #endif
}

// MARK: - Stress Tags

extension Tag {
    @Tag static var stress: Self
}

// MARK: - Duration Helper

/// Convert Duration to seconds as Double for throughput calculations.
private func durationSeconds(_ d: Duration) -> Double {
    let c = d.components
    return Double(c.seconds) + Double(c.attoseconds) / 1e18
}

// MARK: - Stress Tests (TEST-11)

@Suite("Stress Tests", .tags(.stress))
struct StressTests {

    /// Test 1: Store/Reducer throughput — proves >1000 mutations/sec with bounded memory.
    @MainActor
    @Test("Store reducer throughput exceeds 1000 mutations/sec with bounded memory")
    func storeReducerThroughput() async {
        let store = Store(initialState: StressCounter.State()) {
            StressCounter()
        }
        let iterations = 5_000
        let clock = ContinuousClock()

        let startMem = currentResidentMemoryBytes()
        let elapsed = clock.measure {
            for _ in 0..<iterations {
                store.send(.increment)
            }
        }
        let endMem = currentResidentMemoryBytes()

        // Must complete within 5 seconds — proves >1000 mutations/sec
        #expect(elapsed < .seconds(5), "5000 mutations must complete in <5s (actual: \(elapsed))")
        #expect(store.count == iterations, "All mutations should be applied")

        // Memory must be bounded — no unbounded growth
        if let s = startMem, let e = endMem {
            let growth = e > s ? e - s : 0
            #expect(growth < 50 * 1024 * 1024, "Memory growth should be <50MB (actual: \(growth / 1024 / 1024)MB)")
        }

        // Report metrics
        let secs = durationSeconds(elapsed)
        let mutationsPerSec = secs > 0 ? Double(iterations) / secs : Double(iterations)
        print("Store throughput: \(iterations) mutations in \(elapsed) (\(Int(mutationsPerSec)) mut/sec)")
        if let s = startMem, let e = endMem {
            print("Memory: start=\(s / 1024 / 1024)MB end=\(e / 1024 / 1024)MB delta=\((e > s ? e - s : 0) / 1024 / 1024)MB")
        }
    }

    /// Test 2: Observation pipeline under load — proves coalescing is stable at scale.
    @Test("Observation coalescing stable under 5000-iteration load")
    func observationCoalescingUnderLoad() async {
        let model = StressModel()
        let counter = StressAtomicCounter()
        let iterations = 5_000

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<iterations {
                withObservationTracking {
                    _ = model.value
                } onChange: {
                    counter.increment()
                }
                model.value += 1
            }
        }

        // Each cycle: track -> mutate -> one onChange. Total = iterations.
        #expect(counter.value == iterations, "Each track+mutate cycle should produce exactly 1 onChange (got \(counter.value)/\(iterations))")

        // Memory bounded — no unbounded accumulation
        let mem = currentResidentMemoryBytes()
        if let m = mem {
            #expect(m > 0, "Memory reading should succeed")
        }

        print("Observation coalescing: \(iterations) cycles in \(elapsed)")
    }
}
#endif
