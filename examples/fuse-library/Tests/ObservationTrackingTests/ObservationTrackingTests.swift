// Licensed under the GNU Lesser General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import XCTest
import Foundation
@testable import FuseLibrary

/// Swift-only tests verifying withObservationTracking works correctly.
///
/// These delegate to ObservationVerifier for core verification logic, adding XCTest
/// assertions with descriptive failure messages. They can't run on Android because
/// withObservationTracking is a Swift stdlib function with no Kotlin equivalent in skip-model.
///
/// On Android, observation is verified through Compose recomposition (UI-level behavior).
/// For cross-platform observable property tests, see ObservationTests in FuseLibraryTests.
@available(macOS 14, iOS 17, *)
final class ObservationTrackingTests: XCTestCase {

    func testBasicPropertyObservation() {
        XCTAssertTrue(ObservationVerifier.verifyBasicTracking(),
                      "onChange should fire when tracked property mutates")
    }

    func testMultiplePropertyObservation() {
        XCTAssertTrue(ObservationVerifier.verifyMultiplePropertyTracking(),
                      "onChange should fire when one of multiple tracked properties mutates")
    }

    func testObservationIgnoredTracking() {
        XCTAssertTrue(ObservationVerifier.verifyIgnoredProperty(),
                      "onChange should NOT fire for @ObservationIgnored property")
    }

    func testComputedPropertyObservation() {
        XCTAssertTrue(ObservationVerifier.verifyComputedPropertyTracking(),
                      "onChange should fire when stored property backing computed changes")
    }

    func testMultipleObservablesTracking() {
        XCTAssertTrue(ObservationVerifier.verifyMultipleObservables(),
                      "Independent observables should track independently")
    }

    func testNestedObservableTracking() {
        XCTAssertTrue(ObservationVerifier.verifyNestedTracking(),
                      "onChange should fire when nested child property mutates")
    }

    func testSequentialObservations() {
        XCTAssertTrue(ObservationVerifier.verifySequentialTracking(),
                      "Sequential observation cycles should each fire independently")
    }
}
