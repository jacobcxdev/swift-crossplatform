#if !SKIP
import ComposableArchitecture
import SwiftUI
import Testing
@testable import FuseApp

// MARK: - Tab Binding Tests

/// These tests verify that the explicit Binding used in TestHarnessView correctly dispatches
/// TCA actions and updates state. 2-tab structure: Showcase + Control.
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
        binding.wrappedValue = .showcase
        #expect(store.selectedTab == .showcase)
    }

    @Test func allTabsAccessibleViaExplicitBinding() async {
        let store = Store(initialState: TestHarnessFeature.State()) { TestHarnessFeature() }
        let binding = Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )
        let allTabs: [TestHarnessFeature.State.Tab] = [.showcase, .control]
        for tab in allTabs {
            binding.wrappedValue = tab
            #expect(store.selectedTab == tab, "Expected selectedTab to be \(tab)")
        }
    }

    @Test func allTabsAccessibleViaSend() async {
        let store = Store(initialState: TestHarnessFeature.State()) { TestHarnessFeature() }
        let allTabs: [TestHarnessFeature.State.Tab] = [.showcase, .control]
        for tab in allTabs {
            store.send(.tabSelected(tab))
            #expect(store.selectedTab == tab, "Expected selectedTab to be \(tab)")
        }
    }

    @Test func tabRawValueRoundTrips() async {
        let allTabs: [TestHarnessFeature.State.Tab] = [.showcase, .control]
        for tab in allTabs {
            let rawValue = tab.rawValue
            let restored = TestHarnessFeature.State.Tab(rawValue: rawValue)
            #expect(restored == tab, "Round-trip failed for \(tab) via rawValue '\(rawValue)'")
        }
    }

    @Test func tabSelectionDefaultIsShowcase() async {
        let store = Store(initialState: TestHarnessFeature.State()) { TestHarnessFeature() }
        #expect(store.selectedTab == .showcase, "Default tab should be showcase")
    }
}
#endif
