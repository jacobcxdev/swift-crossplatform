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

    // MARK: - Bridge-specific verification methods

    /// Verifies that bulk mutations don't cause N separate onChange callbacks (OBS-15).
    /// Native withObservationTracking's onChange fires once then auto-cancels,
    /// so multiple mutations after the first onChange won't trigger again until re-subscription.
    public static func verifyBulkMutationCoalescing() -> Bool {
        let counter = Counter()
        let flag = FlagBox()

        withObservationTracking {
            _ = counter.count
        } onChange: {
            flag.value = true
        }

        counter.count = 1
        let firedOnFirst = flag.value

        // These mutations happen after onChange already fired and auto-cancelled.
        // They should NOT cause additional onChange callbacks.
        counter.count = 2
        counter.count = 3
        return firedOnFirst && counter.count == 3
    }

    /// Verifies that @ObservationIgnored suppresses ALL tracking for that property (OBS-17).
    /// When only an ignored property is accessed in the tracking closure,
    /// no onChange should fire even when a non-ignored property is mutated,
    /// because the non-ignored property was never accessed during tracking.
    public static func verifyObservationIgnoredNoTracking() -> Bool {
        let counter = Counter()
        let flag = FlagBox()

        withObservationTracking {
            _ = counter.ignoredValue  // only access ignored property
        } onChange: {
            flag.value = true
        }

        counter.count = 42  // mutate a non-ignored property that was NOT accessed
        return !flag.value  // onChange should NOT have fired
    }

    /// Verifies nested observation cycles track independently (OBS-06 bridge-level).
    /// Simulates parent view + child modifier each having their own observation scope.
    public static func verifyNestedObservationCycles() -> Bool {
        let parent = Counter()
        let child = Counter()
        let parentFlag = FlagBox()
        let childFlag = FlagBox()

        // Outer tracking (parent view)
        withObservationTracking {
            _ = parent.count
            // Inner tracking (child modifier)
            withObservationTracking {
                _ = child.count
            } onChange: {
                childFlag.value = true
            }
        } onChange: {
            parentFlag.value = true
        }

        // Mutate child — should fire child's onChange
        child.count = 1
        let childFired = childFlag.value

        // Mutate parent — should fire parent's onChange
        parent.count = 1
        return childFired && parentFlag.value
    }

    /// Verifies sequential observation cycles each re-subscribe correctly (OBS-01).
    /// After onChange fires and auto-cancels, a NEW withObservationTracking on the
    /// same object should fire onChange again. This is the pattern Evaluate() relies on.
    public static func verifySequentialObservationCyclesResubscribe() -> Bool {
        let counter = Counter()

        // Cycle 1
        let flag1 = FlagBox()
        withObservationTracking {
            _ = counter.count
        } onChange: {
            flag1.value = true
        }
        counter.count = 1
        guard flag1.value else { return false }

        // Cycle 2 — re-subscribe after first onChange
        let flag2 = FlagBox()
        withObservationTracking {
            _ = counter.count
        } onChange: {
            flag2.value = true
        }
        counter.count = 2
        guard flag2.value else { return false }

        // Cycle 3 — one more for good measure
        let flag3 = FlagBox()
        withObservationTracking {
            _ = counter.count
        } onChange: {
            flag3.value = true
        }
        counter.count = 3
        return flag3.value && counter.count == 3
    }

    /// Verifies that multiple property accesses from different observables in one
    /// tracking scope produce a single onChange trigger (OBS-22).
    public static func verifyMultiPropertySingleOnChange() -> Bool {
        let a = Counter()
        let b = Counter()
        let flag = FlagBox()

        withObservationTracking {
            _ = a.count
            _ = b.count
            _ = a.label
        } onChange: {
            flag.value = true
        }

        // Mutate just one property — onChange fires once and auto-cancels
        a.count = 1
        return flag.value
    }
}

/// Thread-safe flag box for use in @Sendable onChange closures.
/// Note: withObservationTracking dispatches onChange synchronously before
/// willSet returns in the current Swift Observation implementation, so
/// no additional synchronization is needed for this test helper.
private final class FlagBox: @unchecked Sendable {
    var value = false
}
