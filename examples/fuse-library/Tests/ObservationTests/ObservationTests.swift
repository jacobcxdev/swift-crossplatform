// Licensed under the GNU Lesser General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import XCTest
import Foundation
import SkipBridge
@testable import FuseLibrary

/// Cross-platform tests verifying Swift Observation works on both macOS and Android.
///
/// Property CRUD tests verify basic @Observable bridging. The ObservationVerifier tests
/// call native Swift code that uses withObservationTracking internally — on Android in
/// Fuse mode, this runs as native Swift via JNI, proving the full observation pipeline
/// (access tracking, onChange callbacks, record-replay) works on Android.
///
/// For direct withObservationTracking tests (macOS-only), see ObservationTrackingTests.
@available(macOS 14, iOS 17, *)
final class ObservationTests: XCTestCase {

    override func setUp() {
        #if os(Android)
        loadPeerLibrary(packageName: "fuse-library", moduleName: "FuseLibrary")
        #endif
    }

    // MARK: - Observable property CRUD (transpiled Kotlin)

    func testObservablePropertyReadWrite() {
        let counter = Counter()
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(counter.label, "")

        counter.count = 42
        counter.label = "hello"
        XCTAssertEqual(counter.count, 42)
        XCTAssertEqual(counter.label, "hello")
    }

    func testObservableComputedProperty() {
        let counter = Counter()
        XCTAssertEqual(counter.doubleCount, 0)

        counter.count = 5
        XCTAssertEqual(counter.doubleCount, 10)

        counter.count = -3
        XCTAssertEqual(counter.doubleCount, -6)
    }

    func testObservationIgnoredProperty() {
        let counter = Counter()
        XCTAssertEqual(counter.ignoredValue, 0)

        counter.ignoredValue = 99
        XCTAssertEqual(counter.ignoredValue, 99)
    }

    func testNestedObservableProperties() {
        let parent = Parent()
        XCTAssertEqual(parent.name, "")
        XCTAssertEqual(parent.child.value, 0)

        parent.name = "test"
        parent.child.value = 42
        XCTAssertEqual(parent.name, "test")
        XCTAssertEqual(parent.child.value, 42)
    }

    func testMultipleObservableInstances() {
        let a = Counter()
        let b = Counter()

        a.count = 1
        b.count = 2

        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 2)
        XCTAssertNotEqual(a.count, b.count)
    }

    func testMutationWithoutObservation() {
        let counter = Counter()
        counter.count = 100
        counter.label = "no tracking"
        counter.ignoredValue = 50
        XCTAssertEqual(counter.count, 100)
        XCTAssertEqual(counter.label, "no tracking")
        XCTAssertEqual(counter.ignoredValue, 50)
    }

    func testMultiTrackerIndependence() {
        let tracker = MultiTracker()
        tracker.alpha = 10
        tracker.beta = "test"
        XCTAssertEqual(tracker.alpha, 10)
        XCTAssertEqual(tracker.beta, "test")
    }

    // MARK: - Observation bridge verification (native Swift via JNI on Android)

    func testVerifyBasicTracking() {
        XCTAssertTrue(ObservationVerifier.verifyBasicTracking(),
                      "withObservationTracking should fire onChange on property mutation")
    }

    func testVerifyMultiplePropertyTracking() {
        XCTAssertTrue(ObservationVerifier.verifyMultiplePropertyTracking(),
                      "onChange should fire when any tracked property mutates")
    }

    func testVerifyIgnoredProperty() {
        XCTAssertTrue(ObservationVerifier.verifyIgnoredProperty(),
                      "@ObservationIgnored properties should not trigger onChange")
    }

    func testVerifyComputedPropertyTracking() {
        XCTAssertTrue(ObservationVerifier.verifyComputedPropertyTracking(),
                      "Computed property tracking should follow stored property dependencies")
    }

    func testVerifyMultipleObservables() {
        XCTAssertTrue(ObservationVerifier.verifyMultipleObservables(),
                      "Independent observables should track independently")
    }

    func testVerifyNestedTracking() {
        XCTAssertTrue(ObservationVerifier.verifyNestedTracking(),
                      "Nested observable property access should be tracked")
    }

    func testVerifySequentialTracking() {
        XCTAssertTrue(ObservationVerifier.verifySequentialTracking(),
                      "Sequential observation cycles should each fire independently")
    }

    // MARK: - Bridge-specific observation verification

    func testVerifyBulkMutationCoalescing() {
        XCTAssertTrue(ObservationVerifier.verifyBulkMutationCoalescing(),
                      "Bulk mutations should not cause N separate onChange callbacks")
    }

    func testVerifyObservationIgnoredNoTracking() {
        XCTAssertTrue(ObservationVerifier.verifyObservationIgnoredNoTracking(),
                      "@ObservationIgnored properties should not register any tracking")
    }

    func testVerifyNestedObservationCycles() {
        XCTAssertTrue(ObservationVerifier.verifyNestedObservationCycles(),
                      "Nested observation cycles should track independently")
    }

    func testVerifySequentialObservationCyclesResubscribe() {
        XCTAssertTrue(ObservationVerifier.verifySequentialObservationCyclesResubscribe(),
                      "Sequential observation cycles should each fire onChange independently")
    }

    func testVerifyMultiPropertySingleOnChange() {
        XCTAssertTrue(ObservationVerifier.verifyMultiPropertySingleOnChange(),
                      "Multiple property accesses in one tracking scope should produce single onChange")
    }
}
