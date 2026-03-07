// Copyright 2023–2025 Skip
import Observation
import SkipFuse

// Test that observables in a different file work

@Observable
public class TapCountObservable {
    public var tapCount = 0
    public init() {}
}

public struct TapCountStruct: Identifiable, Sendable {
    public var id = 0
    public var tapCount = 0
    public init(id: Int = 0, tapCount: Int = 0) {
        self.id = id
        self.tapCount = tapCount
    }
}

@Observable
public class TapCountRepository {
    public var items: [TapCountStruct] = []

    public init() {}

    public func add() {
        items.append(TapCountStruct(id: items.count))
    }

    public func increment() {
        if !items.isEmpty {
            items[items.count - 1].tapCount += 1
        }
    }
}
