#if !SKIP
import ComposableArchitecture
import SwiftUI
import Testing
@testable import FuseApp

// MARK: - Tab Binding Tests

/// These tests verify that the explicit Binding used in AppView correctly dispatches
/// TCA actions and updates state. This validates the fix for Android tab switching
/// where the `$store.selectedTab.sending(\.tabSelected)` chain broke through
/// skip-fuse-ui's Bindable/Binding bridge.
@Suite(.serialized) @MainActor
struct TabBindingTests {

    @Test func tabSelectionBindingUpdatesState() async {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        let binding = Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )
        binding.wrappedValue = .todos
        #expect(store.selectedTab == .todos)
    }

    @Test func allTabsAccessibleViaExplicitBinding() async {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        let binding = Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )
        let allTabs: [AppFeature.State.Tab] = [.counter, .todos, .contacts, .database, .settings]
        for tab in allTabs {
            binding.wrappedValue = tab
            #expect(store.selectedTab == tab, "Expected selectedTab to be \(tab)")
        }
    }

    @Test func allTabsAccessibleViaSend() async {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        let allTabs: [AppFeature.State.Tab] = [.counter, .todos, .contacts, .database, .settings]
        for tab in allTabs {
            store.send(.tabSelected(tab))
            #expect(store.selectedTab == tab, "Expected selectedTab to be \(tab)")
        }
    }

    @Test func tabRawValueRoundTrips() async {
        let allTabs: [AppFeature.State.Tab] = [.counter, .todos, .contacts, .database, .settings]
        for tab in allTabs {
            let rawValue = tab.rawValue
            let restored = AppFeature.State.Tab(rawValue: rawValue)
            #expect(restored == tab, "Round-trip failed for \(tab) via rawValue '\(rawValue)'")
        }
    }

    @Test func tabSelectionBindingNotifiesOnChange() async {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        // Simulate what onItemClick does: set binding then verify state
        store.send(.tabSelected(.todos))
        #expect(store.selectedTab == .todos)
        // Simulate binding round-trip
        let binding = Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )
        binding.wrappedValue = .settings
        #expect(store.selectedTab == .settings)
        // Verify we can go back
        binding.wrappedValue = .counter
        #expect(store.selectedTab == .counter)
    }

    @Test func tabSelectionDefaultIsCounter() async {
        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        #expect(store.selectedTab == .counter, "Default tab should be counter")
    }
}
#endif
