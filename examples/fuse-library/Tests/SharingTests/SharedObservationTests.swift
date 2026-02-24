#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombineShim
#endif
import Foundation
#if !SKIP
import Testing
#endif
import Sharing
import XCTest

// MARK: - File-scope types

struct ObsParent: Codable, Equatable, Sendable {
    var child: String = "initial"
}

// MARK: - XCTest Publisher Tests (Android-transpilable)

#if canImport(Combine) || canImport(OpenCombine)
final class SharedPublisherTests: XCTestCase, @unchecked Sendable {

    @MainActor
    func testSharedPublisher() async throws {
        @Shared(.inMemory("pubTest")) var count = 0
        var received: [Int] = []
        let expectation = self.expectation(description: "publisher emits")

        let cancellable = $count.publisher
            .dropFirst()
            .sink { value in
                received.append(value)
                expectation.fulfill()
            }

        $count.withLock { $0 = 42 }

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = cancellable
        XCTAssertTrue(received.contains(42), "Publisher should have emitted 42, got: \(received)")
    }

    @MainActor
    func testSharedPublisherMultipleValues() async throws {
        @Shared(.inMemory("pubMulti")) var count = 0
        var received: [Int] = []
        let expectation = self.expectation(description: "publisher emits 3 values")
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

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = cancellable
        XCTAssertEqual(received, [1, 2, 3])
    }

    @MainActor
    func testPublisherValuesAsyncSequence() async throws {
        @Shared(.inMemory("asyncPub")) var count = 0
        var received: [Int] = []
        let expectation = self.expectation(description: "publisher emits 3 values")
        expectation.expectedFulfillmentCount = 3

        let cancellable = $count.publisher
            .dropFirst()
            .sink { value in
                received.append(value)
                expectation.fulfill()
            }

        $count.withLock { $0 = 10 }
        try await Task.sleep(for: .milliseconds(50))
        $count.withLock { $0 = 20 }
        try await Task.sleep(for: .milliseconds(50))
        $count.withLock { $0 = 30 }

        await fulfillment(of: [expectation], timeout: 5.0)
        _ = cancellable
        XCTAssertEqual(received, [10, 20, 30])
    }

    @MainActor
    func testPublisherAndObservationBothWork() async throws {
        @Shared(.inMemory("bothChannels")) var count = 0
        var publisherReceived = false
        let expectation = self.expectation(description: "publisher receives 7")

        let cancellable = $count.publisher
            .dropFirst()
            .sink { value in
                if value == 7 {
                    publisherReceived = true
                    expectation.fulfill()
                }
            }

        $count.withLock { $0 = 7 }

        await fulfillment(of: [expectation], timeout: 2.0)
        _ = cancellable
        XCTAssertTrue(publisherReceived)
        XCTAssertEqual(count, 7)
    }
}
#endif

// MARK: - Swift Testing Tests (Darwin-only, non-transpilable)

#if !SKIP
@Suite(.serialized) @MainActor
struct SharedObservationTests {

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
#endif
