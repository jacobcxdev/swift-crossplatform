#if !SKIP
import ComposableArchitecture
import Foundation
import Testing
@testable import FuseApp

// MARK: - IdentityFeature Tests

/// TCA TestStore tests for Identity tab sections 1, 3, 4, 5, 6, and 8.
/// Section 2 (Duplicate Key Guard) uses non-TCA raw arrays — tested via Android integration/manual only.
/// Section 7 (Peer Remembering) tests transpiler/Compose behavior — Android integration/manual test only.
@Suite(.serialized) @MainActor
struct IdentityFeatureTests {

    // MARK: - Test UUIDs

    private static let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let idD = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private static let idNew = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    // MARK: - Section 1: Eager Container Keying

    @Test func deleteEagerCardPreservesRemaining() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                eagerCards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextEagerCardLetter: "D"
            )
        ) {
            IdentityFeature()
        }

        // Delete middle card (Card B)
        await store.send(.view(.deleteEagerCardButtonTapped(Self.idB))) {
            $0.eagerCards.remove(id: Self.idB)
        }

        // Verify remaining cards are unchanged
        #expect(store.state.eagerCards.count == 2)
        #expect(store.state.eagerCards[id: Self.idA]?.title == "Card A")
        #expect(store.state.eagerCards[id: Self.idC]?.title == "Card C")
    }

    @Test func reorderMovesLastToFirst() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                eagerCards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextEagerCardLetter: "D"
            )
        ) {
            IdentityFeature()
        }

        await store.send(.view(.reorderEagerCardButtonTapped)) {
            let last = $0.eagerCards.removeLast()
            $0.eagerCards.insert(last, at: 0)
        }

        // All cards retained, just reordered
        #expect(store.state.eagerCards.count == 3)
        #expect(store.state.eagerCards[0].title == "Card C")
        #expect(store.state.eagerCards[1].title == "Card A")
        #expect(store.state.eagerCards[2].title == "Card B")
    }

    @Test func addEagerCardAppendsAndIncrementsLetter() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                eagerCards: [
                    CardItem(id: Self.idA, title: "Card A"),
                ],
                nextEagerCardLetter: "B"
            )
        ) {
            IdentityFeature()
        } withDependencies: {
            $0.uuid = .constant(Self.idNew)
        }

        await store.send(.view(.addEagerCardButtonTapped)) {
            $0.eagerCards.append(CardItem(id: Self.idNew, title: "Card B"))
            $0.nextEagerCardLetter = "C"
        }

        #expect(store.state.eagerCards.count == 2)
        #expect(store.state.eagerCards.last?.title == "Card B")
    }

    @Test func multipleEagerDeletions() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                eagerCards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                    CardItem(id: Self.idD, title: "Card D"),
                ],
                nextEagerCardLetter: "E"
            )
        ) {
            IdentityFeature()
        }

        // Delete first
        await store.send(.view(.deleteEagerCardButtonTapped(Self.idA))) {
            $0.eagerCards.remove(id: Self.idA)
        }

        // Delete third (Card C)
        await store.send(.view(.deleteEagerCardButtonTapped(Self.idC))) {
            $0.eagerCards.remove(id: Self.idC)
        }

        // Verify B and D remain
        #expect(store.state.eagerCards.count == 2)
        #expect(store.state.eagerCards[id: Self.idB]?.title == "Card B")
        #expect(store.state.eagerCards[id: Self.idD]?.title == "Card D")
    }

    // MARK: - Section 3: Animated Content

    @Test func toggleAnimatedDeletion() async {
        let store = TestStore(
            initialState: IdentityFeature.State()
        ) {
            IdentityFeature()
        }

        #expect(store.state.isAnimatedDeletion == false)

        await store.send(.view(.toggleAnimatedDeletion)) {
            $0.isAnimatedDeletion = true
        }

        await store.send(.view(.toggleAnimatedDeletion)) {
            $0.isAnimatedDeletion = false
        }
    }

    @Test func animatedDeletionPreservesRemainingCards() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                animatedCards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextAnimatedCardLetter: "D",
                isAnimatedDeletion: true
            )
        ) {
            IdentityFeature()
        }

        // Animation is visual only — reducer logic is identical
        await store.send(.view(.deleteAnimatedCardButtonTapped(Self.idB))) {
            $0.animatedCards.remove(id: Self.idB)
        }

        #expect(store.state.animatedCards.count == 2)
        #expect(store.state.animatedCards[id: Self.idA]?.title == "Card A")
        #expect(store.state.animatedCards[id: Self.idC]?.title == "Card C")
    }

    // MARK: - Section 4: Picker Selection

    @Test func pickerStyleSelection() async {
        let store = TestStore(
            initialState: IdentityFeature.State()
        ) {
            IdentityFeature()
        }

        #expect(store.state.selectedStyle == "bold")

        await store.send(.view(.styleSelected("italic"))) {
            $0.selectedStyle = "italic"
        }

        await store.send(.view(.styleSelected("underline"))) {
            $0.selectedStyle = "underline"
        }

        await store.send(.view(.styleSelected("strikethrough"))) {
            $0.selectedStyle = "strikethrough"
        }
    }

    // MARK: - Section 5: TabView Selection

    @Test func tabSelection() async {
        let store = TestStore(
            initialState: IdentityFeature.State()
        ) {
            IdentityFeature()
        }

        #expect(store.state.selectedTab == 0)

        await store.send(.view(.tabSelected(1))) {
            $0.selectedTab = 1
        }

        await store.send(.view(.tabSelected(2))) {
            $0.selectedTab = 2
        }

        await store.send(.view(.tabSelected(0))) {
            $0.selectedTab = 0
        }
    }

    // MARK: - Section 6: Lazy Container Identity

    @Test func lazyContainerAddAndDelete() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                lazyCards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                ],
                nextLazyCardLetter: "C"
            )
        ) {
            IdentityFeature()
        } withDependencies: {
            $0.uuid = .constant(Self.idNew)
        }

        // Add a card
        await store.send(.view(.addLazyCardButtonTapped)) {
            $0.lazyCards.append(CardItem(id: Self.idNew, title: "Card C"))
            $0.nextLazyCardLetter = "D"
        }

        #expect(store.state.lazyCards.count == 3)

        // Delete middle card
        await store.send(.view(.deleteLazyCardButtonTapped(Self.idB))) {
            $0.lazyCards.remove(id: Self.idB)
        }

        #expect(store.state.lazyCards.count == 2)
        #expect(store.state.lazyCards[id: Self.idA]?.title == "Card A")
        #expect(store.state.lazyCards[id: Self.idNew]?.title == "Card C")
    }

    // MARK: - Section 7: Peer Remembering — NO TestStore test
    // @State retention across recomposition is transpiler/Compose behavior.
    // Verified via Android integration/manual test only.

    // MARK: - Section 8: .id() State Reset

    @Test func resetTokenChanges() async {
        let idToken = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let store = TestStore(
            initialState: IdentityFeature.State()
        ) {
            IdentityFeature()
        } withDependencies: {
            $0.uuid = .constant(idToken)
        }

        let originalToken = store.state.resetToken

        await store.send(.view(.resetTokenButtonTapped)) {
            $0.resetToken = idToken
        }

        #expect(store.state.resetToken == idToken)
        #expect(store.state.resetToken != originalToken)
    }
}
#endif
