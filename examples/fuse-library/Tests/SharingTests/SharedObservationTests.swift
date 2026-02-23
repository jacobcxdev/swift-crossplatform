#if canImport(Combine)
import Combine
#endif
import Foundation
import Sharing
import Testing

// MARK: - File-scope types

struct ObsParent: Codable, Equatable, Sendable {
    var child: String = "initial"
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct SharedObservationTests {

    // MARK: SHR-10 — Publisher emits on mutation

    #if canImport(Combine)
    @Test func sharedPublisher() async throws {
        @Shared(.inMemory("pubTest")) var count = 0
        var received: [Int] = []

        try await confirmation(expectedCount: 1) { confirm in
            let cancellable = $count.publisher
                .dropFirst() // skip initial prepend value
                .sink { value in
                    received.append(value)
                    confirm()
                }

            $count.withLock { $0 = 42 }

            // Give publisher time to emit
            try await Task.sleep(for: .milliseconds(500))
            _ = cancellable
        }
        #expect(received.contains(42), "Publisher should have emitted 42, got: \(received)")
    }

    // MARK: SHR-10 — Publisher emits multiple values

    @Test func sharedPublisherMultipleValues() async throws {
        @Shared(.inMemory("pubMulti")) var count = 0
        var received: [Int] = []

        try await confirmation(expectedCount: 3) { confirm in
            let cancellable = $count.publisher
                .dropFirst()
                .sink { value in
                    received.append(value)
                    confirm()
                }

            $count.withLock { $0 = 1 }
            $count.withLock { $0 = 2 }
            $count.withLock { $0 = 3 }

            try await Task.sleep(for: .milliseconds(500))
            _ = cancellable
        }
        #expect(received == [1, 2, 3])
    }
    #endif

    // MARK: SHR-12 — Multiple @Shared same key synchronize

    @Test func multipleSharedSameKeySynchronize() {
        @Shared(.inMemory("syncKey")) var ref1 = 0
        @Shared(.inMemory("syncKey")) var ref2 = 0
        $ref1.withLock { $0 = 99 }
        #expect(ref2 == 99)
    }

    // MARK: SHR-13 — Child mutation visible in parent

    @Test func childMutationVisibleInParent() {
        @Shared(.inMemory("obsParent")) var parent = ObsParent()
        let childShared: Shared<String> = $parent.child
        childShared.withLock { $0 = "mutated" }
        #expect(parent.child == "mutated")
    }

    // MARK: SHR-12 — Concurrent shared mutations (thread safety)

    @Test func concurrentSharedMutations() async {
        @Shared(.inMemory("concurrent")) var value = 0

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    $value.withLock { $0 += 1 }
                }
            }
        }

        #expect(value == 10)
    }

    // MARK: SHR-09 — Async publisher values sequence

    #if canImport(Combine)
    @Test func publisherValuesAsyncSequence() async throws {
        @Shared(.inMemory("asyncPub")) var count = 0
        var received: [Int] = []

        try await confirmation(expectedCount: 1) { confirm in
            let cancellable = $count.publisher
                .dropFirst()
                .prefix(3)
                .sink(
                    receiveCompletion: { _ in confirm() },
                    receiveValue: { received.append($0) }
                )

            $count.withLock { $0 = 10 }
            $count.withLock { $0 = 20 }
            $count.withLock { $0 = 30 }

            try await Task.sleep(for: .milliseconds(500))
            _ = cancellable
        }
        #expect(received == [10, 20, 30])
    }

    // MARK: SHR-09 + SHR-10 — Publisher and observation both work

    @Test func publisherAndObservationBothWork() async throws {
        @Shared(.inMemory("bothChannels")) var count = 0
        var publisherReceived = false

        try await confirmation(expectedCount: 1) { confirm in
            let cancellable = $count.publisher
                .dropFirst()
                .sink { value in
                    if value == 7 {
                        publisherReceived = true
                        confirm()
                    }
                }

            $count.withLock { $0 = 7 }

            try await Task.sleep(for: .milliseconds(500))
            _ = cancellable
        }
        #expect(publisherReceived)
        #expect(count == 7)
    }
    #endif

    // MARK: SHR-12 — Bidirectional sync between shared refs

    @Test func bidirectionalSync() {
        @Shared(.inMemory("bidir")) var ref1 = "a"
        @Shared(.inMemory("bidir")) var ref2 = "a"

        $ref1.withLock { $0 = "fromRef1" }
        #expect(ref2 == "fromRef1")

        $ref2.withLock { $0 = "fromRef2" }
        #expect(ref1 == "fromRef2")
    }

    // MARK: SHR-13 — Parent mutation visible in child

    @Test func parentMutationVisibleInChild() {
        @Shared(.inMemory("parentMutChild")) var parent = ObsParent()
        let childShared: Shared<String> = $parent.child
        $parent.withLock { $0.child = "fromParent" }
        #expect(childShared.wrappedValue == "fromParent")
    }
}
