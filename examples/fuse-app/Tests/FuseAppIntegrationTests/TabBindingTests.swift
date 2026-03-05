#if !SKIP
import ComposableArchitecture
import SwiftUI
import Testing
@testable import FuseApp

// MARK: - Tab Binding Tests

/// These tests verify that the explicit Binding used in TestHarnessView correctly dispatches
/// TCA actions and updates state. Minimal suite with only the Control tab remaining;
/// Plan 03 will add the Showcase tab and expand these tests.
@Suite(.serialized) @MainActor
struct TabBindingTests {

    @Test func tabSelectionBindingUpdatesState() async {
        let store = Store(initialState: TestHarnessFeature.State()) { TestHarnessFeature() }
        let binding = Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )
        binding.wrappedValue = .control
        #expect(store.selectedTab == .control)
    }

    @Test func allTabsAccessibleViaExplicitBinding() async {
        let store = Store(initialState: TestHarnessFeature.State()) { TestHarnessFeature() }
        let binding = Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )
        let allTabs: [TestHarnessFeature.State.Tab] = [.control]
        for tab in allTabs {
            binding.wrappedValue = tab
            #expect(store.selectedTab == tab, "Expected selectedTab to be \(tab)")
        }
    }

    @Test func allTabsAccessibleViaSend() async {
        let store = Store(initialState: TestHarnessFeature.State()) { TestHarnessFeature() }
        let allTabs: [TestHarnessFeature.State.Tab] = [.control]
        for tab in allTabs {
            store.send(.tabSelected(tab))
            #expect(store.selectedTab == tab, "Expected selectedTab to be \(tab)")
        }
    }

    @Test func tabRawValueRoundTrips() async {
        let allTabs: [TestHarnessFeature.State.Tab] = [.control]
        for tab in allTabs {
            let rawValue = tab.rawValue
            let restored = TestHarnessFeature.State.Tab(rawValue: rawValue)
            #expect(restored == tab, "Round-trip failed for \(tab) via rawValue '\(rawValue)'")
        }
    }

    @Test func tabSelectionDefaultIsControl() async {
        let store = Store(initialState: TestHarnessFeature.State()) { TestHarnessFeature() }
        #expect(store.selectedTab == .control, "Default tab should be control")
    }
}
#endif
