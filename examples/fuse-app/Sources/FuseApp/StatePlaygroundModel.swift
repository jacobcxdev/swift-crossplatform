// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SkipFuse

// Test that observables in a different file work

@Observable
class TapCountObservable {
    var tapCount = 0
}

struct TapCountStruct: Identifiable {
    var id = 0
    var tapCount = 0
}

@Observable
class TapCountRepository {
    var items: [TapCountStruct] = []

    func add() {
        items.append(TapCountStruct(id: items.count))
    }

    func increment() {
        if !items.isEmpty {
            items[items.count - 1].tapCount += 1
        }
    }
}
