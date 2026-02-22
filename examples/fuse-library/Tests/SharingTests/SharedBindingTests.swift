import Observation
import Sharing
import SwiftUI
import XCTest

// MARK: - File-scope types

struct BindingParent: Codable, Equatable, Sendable {
    var child: String = "hello"
}

@Observable
class SharedModel {
    @ObservationIgnored
    @Shared(.inMemory("doubleNotifModel")) var sharedCount = 0
    var normalCount = 0
}

// MARK: - Tests

final class SharedBindingTests: XCTestCase {

    // MARK: SHR-05 — Binding projection from @Shared

    @MainActor func testSharedBindingProjection() {
        @Shared(.inMemory("bindProj")) var value = "initial"
        let binding = Binding($value)
        XCTAssertEqual(binding.wrappedValue, "initial")
        binding.wrappedValue = "updated"
        XCTAssertEqual(value, "updated")
    }

    // MARK: SHR-06 — Binding mutation triggers change

    @MainActor func testSharedBindingMutationTriggersChange() {
        @Shared(.inMemory("bindMutate")) var value = 0
        let binding = Binding($value)
        binding.wrappedValue = 42
        XCTAssertEqual(value, 42)
    }

    // MARK: SHR-07 — Keypath projection from @Shared

    @MainActor func testSharedKeypathProjection() {
        @Shared(.inMemory("keypathParent")) var parent = BindingParent()
        let childShared: Shared<String> = $parent.child
        XCTAssertEqual(childShared.wrappedValue, "hello")
        childShared.withLock { $0 = "world" }
        XCTAssertEqual(parent.child, "world")
    }

    // MARK: SHR-08 — Optional unwrapping

    @MainActor func testSharedOptionalUnwrapping() {
        @Shared(.inMemory("optUnwrap")) var optional: String? = "present"
        if let unwrapped = Shared($optional) {
            XCTAssertEqual(unwrapped.wrappedValue, "present")
        } else {
            XCTFail("Expected non-nil Shared unwrap")
        }
        $optional.withLock { $0 = nil }
        XCTAssertNil(Shared($optional))
    }

    // MARK: SHR-11 — Double notification prevention (@ObservationIgnored @Shared)

    @MainActor func testDoubleNotificationPrevention() {
        // When @Shared is used with @ObservationIgnored in an @Observable class,
        // mutating the @Shared property should NOT trigger the @Observable's
        // observation registrar. Only @Shared's own observation handles tracking.
        // Without @ObservationIgnored, both @Observable AND @Shared would fire,
        // causing double view updates.

        let model = SharedModel()

        // Track ONLY the @Observable class's properties (not @Shared directly).
        // If @ObservationIgnored works, mutating sharedCount should NOT trigger onChange.
        let sharedMutationFired = expectation(description: "shared mutation onChange")
        sharedMutationFired.isInverted = true // must NOT be fulfilled

        withObservationTracking {
            // Access normalCount to establish tracking on the @Observable registrar.
            // Do NOT access sharedCount here — we're testing that the @Observable
            // class does not generate tracking for @ObservationIgnored properties.
            _ = model.normalCount
        } onChange: {
            sharedMutationFired.fulfill()
        }

        // Mutate @ObservationIgnored @Shared — should NOT trigger @Observable's onChange
        model.$sharedCount.withLock { $0 = 42 }
        XCTAssertEqual(model.sharedCount, 42)
        wait(for: [sharedMutationFired], timeout: 0.1)

        // Verify normal @Observable property mutation DOES fire onChange
        let normalMutationFired = expectation(description: "normal mutation onChange")

        withObservationTracking {
            _ = model.normalCount
        } onChange: {
            normalMutationFired.fulfill()
        }

        model.normalCount = 1
        wait(for: [normalMutationFired], timeout: 1.0)
    }

    // MARK: SHR-06 regression — Rapid binding mutations

    @MainActor func testSharedBindingRapidMutations() {
        @Shared(.inMemory("rapidBind")) var value = 0
        let binding = Binding($value)
        for i in 1...100 {
            binding.wrappedValue = i
        }
        XCTAssertEqual(value, 100)
    }

    // MARK: SHR-05 — Binding two-way sync

    @MainActor func testBindingTwoWaySync() {
        @Shared(.inMemory("twoWayBind")) var value = "start"
        let binding = Binding($value)

        // Mutate via binding
        binding.wrappedValue = "fromBinding"
        XCTAssertEqual(value, "fromBinding")

        // Mutate via withLock
        $value.withLock { $0 = "fromShared" }
        XCTAssertEqual(binding.wrappedValue, "fromShared")
    }
}
