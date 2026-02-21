// Licensed under the GNU Lesser General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation
import Observation

/// Runs observation verification logic in native Swift, returning results that
/// can be asserted from transpiled Kotlin tests.
///
/// On Android in Fuse mode, this code runs as native Swift (via JNI bridge).
/// withObservationTracking and the full Observation framework are available because
/// libswiftObservation.so ships with the Android Swift SDK. The transpiled test
/// calls these methods via the bridge and asserts the boolean results.
@available(macOS 14, iOS 17, *)
public struct ObservationVerifier {

    /// Verifies that withObservationTracking fires onChange when a tracked property mutates.
    public static func verifyBasicTracking() -> Bool {
        let counter = Counter()
        let flag = FlagBox()

        withObservationTracking {
            _ = counter.count
        } onChange: {
            flag.value = true
        }

        counter.count = 42
        return flag.value && counter.count == 42
    }

    /// Verifies that onChange fires when any of multiple tracked properties mutates.
    public static func verifyMultiplePropertyTracking() -> Bool {
        let counter = Counter()
        let flag = FlagBox()

        withObservationTracking {
            _ = counter.count
            _ = counter.label
        } onChange: {
            flag.value = true
        }

        counter.label = "updated"
        return flag.value && counter.label == "updated"
    }

    /// Verifies that @ObservationIgnored properties do NOT trigger onChange.
    public static func verifyIgnoredProperty() -> Bool {
        let counter = Counter()
        let flag = FlagBox()

        withObservationTracking {
            _ = counter.ignoredValue
        } onChange: {
            flag.value = true
        }

        counter.ignoredValue = 99
        return !flag.value && counter.ignoredValue == 99
    }

    /// Verifies that mutating a stored property triggers onChange for a computed property
    /// that depends on it.
    public static func verifyComputedPropertyTracking() -> Bool {
        let counter = Counter()
        let flag = FlagBox()

        withObservationTracking {
            _ = counter.doubleCount
        } onChange: {
            flag.value = true
        }

        counter.count = 5
        return flag.value && counter.doubleCount == 10
    }

    /// Verifies that two independent observables can be tracked independently.
    public static func verifyMultipleObservables() -> Bool {
        let a = Counter()
        let b = Counter()
        let flagA = FlagBox()
        let flagB = FlagBox()

        withObservationTracking {
            _ = a.count
        } onChange: {
            flagA.value = true
        }

        withObservationTracking {
            _ = b.count
        } onChange: {
            flagB.value = true
        }

        a.count = 1
        let aFired = flagA.value
        b.count = 2
        return aFired && flagB.value
    }

    /// Verifies that nested observable property access is tracked correctly.
    public static func verifyNestedTracking() -> Bool {
        let parent = Parent()
        let flag = FlagBox()

        withObservationTracking {
            _ = parent.child.value
        } onChange: {
            flag.value = true
        }

        parent.child.value = 10
        return flag.value && parent.child.value == 10
    }

    /// Verifies that observation can be set up multiple times sequentially.
    public static func verifySequentialTracking() -> Bool {
        let counter = Counter()

        let first = FlagBox()
        withObservationTracking {
            _ = counter.count
        } onChange: {
            first.value = true
        }
        counter.count = 1
        guard first.value else { return false }

        let second = FlagBox()
        withObservationTracking {
            _ = counter.count
        } onChange: {
            second.value = true
        }
        counter.count = 2
        return second.value && counter.count == 2
    }
}

/// Thread-safe flag box for use in @Sendable onChange closures.
/// Note: withObservationTracking dispatches onChange synchronously before
/// willSet returns in the current Swift Observation implementation, so
/// no additional synchronization is needed for this test helper.
private final class FlagBox: @unchecked Sendable {
    var value = false
}
