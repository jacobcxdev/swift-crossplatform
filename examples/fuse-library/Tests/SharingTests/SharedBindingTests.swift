import Foundation
import Observation
import Sharing
import SwiftUI
import Testing

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

@Suite(.serialized) @MainActor
struct SharedBindingTests {

    // MARK: SHR-05 — Binding projection from @Shared

    @Test func sharedBindingProjection() {
        @Shared(.inMemory("bindProj")) var value = "initial"
        let binding = Binding($value)
        #expect(binding.wrappedValue == "initial")
        binding.wrappedValue = "updated"
        #expect(value == "updated")
    }

    // MARK: SHR-06 — Binding mutation triggers change

    @Test func sharedBindingMutationTriggersChange() {
        @Shared(.inMemory("bindMutate")) var value = 0
        let binding = Binding($value)
        binding.wrappedValue = 42
        #expect(value == 42)
    }

    // MARK: SHR-07 — Keypath projection from @Shared

    @Test func sharedKeypathProjection() {
        @Shared(.inMemory("keypathParent")) var parent = BindingParent()
        let childShared: Shared<String> = $parent.child
        #expect(childShared.wrappedValue == "hello")
        childShared.withLock { $0 = "world" }
        #expect(parent.child == "world")
    }

    // MARK: SHR-08 — Optional unwrapping

    @Test func sharedOptionalUnwrapping() {
        @Shared(.inMemory("optUnwrap")) var optional: String? = "present"
        if let unwrapped = Shared($optional) {
            #expect(unwrapped.wrappedValue == "present")
        } else {
            Issue.record("Expected non-nil Shared unwrap")
        }
        $optional.withLock { $0 = nil }
        #expect(Shared($optional) == nil)
    }

    // MARK: SHR-11 — Double notification prevention (@ObservationIgnored @Shared)

    @Test func doubleNotificationPrevention() async throws {
        // When @Shared is used with @ObservationIgnored in an @Observable class,
        // mutating the @Shared property should NOT trigger the @Observable's
        // observation registrar. Only @Shared's own observation handles tracking.
        // Without @ObservationIgnored, both @Observable AND @Shared would fire,
        // causing double view updates.

        let model = SharedModel()

        // Track ONLY the @Observable class's properties (not @Shared directly).
        // If @ObservationIgnored works, mutating sharedCount should NOT trigger onChange.
        nonisolated(unsafe) var sharedMutationCount = 0

        withObservationTracking {
            // Access normalCount to establish tracking on the @Observable registrar.
            // Do NOT access sharedCount here — we're testing that the @Observable
            // class does not generate tracking for @ObservationIgnored properties.
            _ = model.normalCount
        } onChange: {
            sharedMutationCount += 1
        }

        // Mutate @ObservationIgnored @Shared — should NOT trigger @Observable's onChange
        model.$sharedCount.withLock { $0 = 42 }
        #expect(model.sharedCount == 42)
        try await Task.sleep(for: .milliseconds(100))
        #expect(sharedMutationCount == 0, "onChange should NOT fire for @ObservationIgnored @Shared mutation")

        // Verify normal @Observable property mutation DOES fire onChange
        nonisolated(unsafe) var normalMutationCount = 0

        withObservationTracking {
            _ = model.normalCount
        } onChange: {
            normalMutationCount += 1
        }

        model.normalCount = 1
        try await Task.sleep(for: .milliseconds(100))
        #expect(normalMutationCount > 0, "onChange SHOULD fire for normal @Observable property mutation")
    }

    // MARK: SHR-06 regression — Rapid binding mutations

    @Test func sharedBindingRapidMutations() {
        @Shared(.inMemory("rapidBind")) var value = 0
        let binding = Binding($value)
        for i in 1...100 {
            binding.wrappedValue = i
        }
        #expect(value == 100)
    }

    // MARK: SHR-05 — Binding two-way sync

    @Test func bindingTwoWaySync() {
        @Shared(.inMemory("twoWayBind")) var value = "start"
        let binding = Binding($value)

        // Mutate via binding
        binding.wrappedValue = "fromBinding"
        #expect(value == "fromBinding")

        // Mutate via withLock
        $value.withLock { $0 = "fromShared" }
        #expect(binding.wrappedValue == "fromShared")
    }
}
