#if !SKIP
import ComposableArchitecture
import Foundation
import Testing
@testable import FuseApp

// MARK: - TestHarnessFeature Integration Tests

@Suite(.serialized) @MainActor
struct TestHarnessFeatureTests {

    @Test func initialState() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }
        #expect(store.state.selectedTab == .forEachNamespace)
        #expect(store.state.pendingUICommand == nil)
    }

    @Test func tabSwitching() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }
        await store.send(.tabSelected(.peerSurvival)) {
            $0.selectedTab = .peerSurvival
        }
        await store.send(.tabSelected(.control)) {
            $0.selectedTab = .control
        }
        await store.send(.tabSelected(.forEachNamespace)) {
            $0.selectedTab = .forEachNamespace
        }
    }

    @Test func resetAllClearsState() async {
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
        }

        // Add a card to ForEachNamespace
        await store.send(.forEachNamespace(.view(.addCard))) {
            $0.forEachNamespace.cards.append(CardItem(id: testUUID, title: "Card D"))
            $0.forEachNamespace.nextLetter = "E"
        }

        // Reset all — verify structurally (default init creates new UUIDs)
        store.exhaustivity = .off
        await store.send(.resetAll) {
            $0.pendingUICommand = nil
            $0.peerSurvival = .init()
        }
        // Verify the reset produced fresh default state
        #expect(store.state.forEachNamespace.cards.count == 3)
        #expect(store.state.forEachNamespace.nextLetter == "D")
        #expect(store.state.pendingUICommand == nil)
    }

    @Test func executeUICommandAndAcknowledge() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }

        // Default tab is .forEachNamespace, so command forwards to child via effect
        await store.send(.executeUICommand(.scrollToBottom)) {
            $0.pendingUICommand = .scrollToBottom
        }

        // Parent effect forwards to child reducer
        await store.receive(\.forEachNamespace.executeUICommand) {
            $0.forEachNamespace.pendingUICommand = .scrollToBottom
        }

        // Child view acknowledges — parent clears its own pendingUICommand
        await store.send(.forEachNamespace(.view(.uiCommandCompleted))) {
            $0.forEachNamespace.pendingUICommand = nil
            $0.pendingUICommand = nil
        }
    }

    @Test func cancelUICommandClearsState() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }

        // Send a UICommand (default tab is .forEachNamespace, so it forwards)
        await store.send(.executeUICommand(.scrollToBottom)) {
            $0.pendingUICommand = .scrollToBottom
        }

        await store.receive(\.forEachNamespace.executeUICommand) {
            $0.forEachNamespace.pendingUICommand = .scrollToBottom
        }

        // Cancel clears both parent and child
        await store.send(.cancelUICommand) {
            $0.pendingUICommand = nil
            $0.forEachNamespace.pendingUICommand = nil
        }
    }

    @Test func executeUICommandOnNonForwardingTab() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }

        // Switch to control tab (no child forwarding)
        await store.send(.tabSelected(.control)) {
            $0.selectedTab = .control
        }

        // UICommand sets parent state but produces no child effect
        await store.send(.executeUICommand(.scrollToBottom)) {
            $0.pendingUICommand = .scrollToBottom
        }

        // Cancel clears it
        await store.send(.cancelUICommand) {
            $0.pendingUICommand = nil
        }
    }
}

// MARK: - ForEachNamespaceSetting Integration Tests

@Suite(.serialized) @MainActor
struct ForEachNamespaceSettingTests {

    private static let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let idNew = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    @Test func addCardAppendsAndIncrementsLetter() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [CardItem(id: Self.idA, title: "Card A")],
                nextLetter: "B"
            )
        ) {
            ForEachNamespaceSetting()
        } withDependencies: {
            $0.uuid = .constant(Self.idNew)
        }

        await store.send(.view(.addCard)) {
            $0.cards.append(CardItem(id: Self.idNew, title: "Card B"))
            $0.nextLetter = "C"
        }

        #expect(store.state.cards.count == 2)
    }

    @Test func deleteCardPreservesRemaining() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextLetter: "D"
            )
        ) {
            ForEachNamespaceSetting()
        }

        await store.send(.view(.deleteCard(Self.idB))) {
            $0.cards.remove(id: Self.idB)
        }

        #expect(store.state.cards.count == 2)
        #expect(store.state.cards[id: Self.idA]?.title == "Card A")
        #expect(store.state.cards[id: Self.idC]?.title == "Card C")
    }

    @Test func nextLetterWrapsAtZ() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [CardItem(id: Self.idA, title: "Card Z")],
                nextLetter: "Z"
            )
        ) {
            ForEachNamespaceSetting()
        } withDependencies: {
            $0.uuid = .constant(Self.idNew)
        }

        await store.send(.view(.addCard)) {
            $0.cards.append(CardItem(id: Self.idNew, title: "Card Z"))
            $0.nextLetter = "A"
        }
    }

    @Test func resetRestoredDefaultState() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [CardItem(id: Self.idA, title: "Card A")],
                nextLetter: "B"
            )
        ) {
            ForEachNamespaceSetting()
        }

        store.exhaustivity = .off
        await store.send(.reset)
        #expect(store.state.cards.count == 3)
        #expect(store.state.nextLetter == "D")
    }

    @Test func deleteFirstCardRemovesFirst() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextLetter: "D"
            )
        ) {
            ForEachNamespaceSetting()
        }

        await store.send(.view(.deleteFirstCard))
        await store.receive(\.view.deleteCard) {
            $0.cards.remove(id: Self.idA)
        }

        #expect(store.state.cards.count == 2)
        #expect(store.state.cards[id: Self.idB] != nil)
        #expect(store.state.cards[id: Self.idC] != nil)
    }

    @Test func deleteLastCardRemovesLast() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextLetter: "D"
            )
        ) {
            ForEachNamespaceSetting()
        }

        await store.send(.view(.deleteLastCard))
        await store.receive(\.view.deleteCard) {
            $0.cards.remove(id: Self.idC)
        }

        #expect(store.state.cards.count == 2)
        #expect(store.state.cards[id: Self.idA] != nil)
        #expect(store.state.cards[id: Self.idB] != nil)
    }

    @Test func sequentialAddThenDeleteLastCard() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                ],
                nextLetter: "B"
            )
        ) {
            ForEachNamespaceSetting()
        } withDependencies: {
            $0.uuid = .constant(Self.idNew)
        }

        // Add a card
        await store.send(.view(.addCard)) {
            $0.cards.append(CardItem(id: Self.idNew, title: "Card B"))
            $0.nextLetter = "C"
        }

        // Delete the newly added card (last)
        await store.send(.view(.deleteLastCard))
        await store.receive(\.view.deleteCard) {
            $0.cards.remove(id: Self.idNew)
        }

        // Only the original card remains
        #expect(store.state.cards.count == 1)
        #expect(store.state.cards[id: Self.idA] != nil)
    }
}
#endif
