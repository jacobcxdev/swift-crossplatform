// Licensed under the GNU Lesser General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation
import Observation

@Observable public class Counter {
    public var count: Int = 0
    @ObservationIgnored public var ignoredValue: Int = 0
    public var label: String = ""

    public var doubleCount: Int { count * 2 }

    public init() {}
}

@Observable public class Parent {
    public var name: String = ""
    public var child: Child = Child()

    public init() {}
}

@Observable public class Child {
    public var value: Int = 0

    public init() {}
}

@Observable public class MultiTracker {
    public var alpha: Int = 0
    public var beta: String = ""

    public init() {}
}
