import Combine
import Sharing
import XCTest

// MARK: - File-scope types

struct ObsParent: Codable, Equatable, Sendable {
    var child: String = "initial"
}

// MARK: - Tests

final class SharedObservationTests: XCTestCase {

    // MARK: SHR-10 — Publisher emits on mutation

    @MainActor func testSharedPublisher() {
        @Shared(.inMemory("pubTest")) var count = 0
        var received: [Int] = []
        let expectation = expectation(description: "publisher emits")
        expectation.expectedFulfillmentCount = 1

        let cancellable = $count.publisher
            .dropFirst() // skip initial prepend value
            .sink { value in
                received.append(value)
                expectation.fulfill()
            }

        $count.withLock { $0 = 42 }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(received.contains(42), "Publisher should have emitted 42, got: \(received)")
        _ = cancellable
    }

    // MARK: SHR-10 — Publisher emits multiple values

    @MainActor func testSharedPublisherMultipleValues() {
        @Shared(.inMemory("pubMulti")) var count = 0
        var received: [Int] = []
        let expectation = expectation(description: "publisher emits multiple")
        expectation.expectedFulfillmentCount = 3

        let cancellable = $count.publisher
            .dropFirst()
            .sink { value in
                received.append(value)
                expectation.fulfill()
            }

        $count.withLock { $0 = 1 }
        $count.withLock { $0 = 2 }
        $count.withLock { $0 = 3 }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(received, [1, 2, 3])
        _ = cancellable
    }

    // MARK: SHR-12 — Multiple @Shared same key synchronize

    @MainActor func testMultipleSharedSameKeySynchronize() {
        @Shared(.inMemory("syncKey")) var ref1 = 0
        @Shared(.inMemory("syncKey")) var ref2 = 0
        $ref1.withLock { $0 = 99 }
        XCTAssertEqual(ref2, 99)
    }

    // MARK: SHR-13 — Child mutation visible in parent

    @MainActor func testChildMutationVisibleInParent() {
        @Shared(.inMemory("obsParent")) var parent = ObsParent()
        let childShared: Shared<String> = $parent.child
        childShared.withLock { $0 = "mutated" }
        XCTAssertEqual(parent.child, "mutated")
    }

    // MARK: SHR-12 — Concurrent shared mutations (thread safety)

    @MainActor func testConcurrentSharedMutations() async {
        @Shared(.inMemory("concurrent")) var value = 0

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    $value.withLock { $0 += 1 }
                }
            }
        }

        XCTAssertEqual(value, 10)
    }

    // MARK: SHR-09 — Async publisher values sequence

    @MainActor func testPublisherValuesAsyncSequence() async {
        @Shared(.inMemory("asyncPub")) var count = 0
        var received: [Int] = []

        let expectation = expectation(description: "async values received")

        let cancellable = $count.publisher
            .dropFirst()
            .prefix(3)
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { received.append($0) }
            )

        $count.withLock { $0 = 10 }
        $count.withLock { $0 = 20 }
        $count.withLock { $0 = 30 }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(received, [10, 20, 30])
        _ = cancellable
    }

    // MARK: SHR-09 + SHR-10 — Publisher and observation both work

    @MainActor func testPublisherAndObservationBothWork() {
        @Shared(.inMemory("bothChannels")) var count = 0
        var publisherReceived = false

        let expectation = expectation(description: "publisher fires")

        let cancellable = $count.publisher
            .dropFirst()
            .sink { value in
                if value == 7 {
                    publisherReceived = true
                    expectation.fulfill()
                }
            }

        $count.withLock { $0 = 7 }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(publisherReceived)
        XCTAssertEqual(count, 7)
        _ = cancellable
    }

    // MARK: SHR-12 — Bidirectional sync between shared refs

    @MainActor func testBidirectionalSync() {
        @Shared(.inMemory("bidir")) var ref1 = "a"
        @Shared(.inMemory("bidir")) var ref2 = "a"

        $ref1.withLock { $0 = "fromRef1" }
        XCTAssertEqual(ref2, "fromRef1")

        $ref2.withLock { $0 = "fromRef2" }
        XCTAssertEqual(ref1, "fromRef2")
    }

    // MARK: SHR-13 — Parent mutation visible in child

    @MainActor func testParentMutationVisibleInChild() {
        @Shared(.inMemory("parentMutChild")) var parent = ObsParent()
        let childShared: Shared<String> = $parent.child
        $parent.withLock { $0.child = "fromParent" }
        XCTAssertEqual(childShared.wrappedValue, "fromParent")
    }
}
