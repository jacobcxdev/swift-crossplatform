#if !SKIP
import ComposableArchitecture
import Foundation
import Testing
@testable import FuseApp

// MARK: - IdentityFeature Tests

/// TCA TestStore tests for Identity tab sections 1, 3, and 4.
/// Section 2 (Duplicate Key Guard) uses non-TCA raw arrays — tested via Android integration/manual only.
@Suite(.serialized) @MainActor
struct IdentityFeatureTests {

    // MARK: - Test UUIDs

    private static let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let idD = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private static let idNew = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    // MARK: - Section 1: Eager Container Keying

    @Test func deleteCardPreservesRemaining() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextCardLetter: "D"
            )
        ) {
            IdentityFeature()
        }

        // Delete middle card (Card B)
        await store.send(.view(.deleteCardButtonTapped(Self.idB))) {
            $0.cards.remove(id: Self.idB)
        }

        // Verify remaining cards are unchanged
        #expect(store.state.cards.count == 2)
        #expect(store.state.cards[id: Self.idA]?.title == "Card A")
        #expect(store.state.cards[id: Self.idC]?.title == "Card C")
    }

    @Test func reorderMovesLastToFirst() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextCardLetter: "D"
            )
        ) {
            IdentityFeature()
        }

        await store.send(.view(.reorderCardButtonTapped)) {
            let last = $0.cards.removeLast()
            $0.cards.insert(last, at: 0)
        }

        // All cards retained, just reordered
        #expect(store.state.cards.count == 3)
        #expect(store.state.cards[0].title == "Card C")
        #expect(store.state.cards[1].title == "Card A")
        #expect(store.state.cards[2].title == "Card B")
    }

    @Test func addCardAppendsAndIncrementsLetter() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                ],
                nextCardLetter: "B"
            )
        ) {
            IdentityFeature()
        } withDependencies: {
            $0.uuid = .constant(Self.idNew)
        }

        await store.send(.view(.addCardButtonTapped)) {
            $0.cards.append(CardItem(id: Self.idNew, title: "Card B"))
            $0.nextCardLetter = "C"
        }

        #expect(store.state.cards.count == 2)
        #expect(store.state.cards.last?.title == "Card B")
    }

    @Test func multipleDeletions() async {
        let store = TestStore(
            initialState: IdentityFeature.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                    CardItem(id: Self.idD, title: "Card D"),
                ],
                nextCardLetter: "E"
            )
        ) {
            IdentityFeature()
        }

        // Delete first
        await store.send(.view(.deleteCardButtonTapped(Self.idA))) {
            $0.cards.remove(id: Self.idA)
        }

        // Delete third (Card C)
        await store.send(.view(.deleteCardButtonTapped(Self.idC))) {
            $0.cards.remove(id: Self.idC)
        }

        // Verify B and D remain
        #expect(store.state.cards.count == 2)
        #expect(store.state.cards[id: Self.idB]?.title == "Card B")
        #expect(store.state.cards[id: Self.idD]?.title == "Card D")
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
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                ],
                nextCardLetter: "D",
                isAnimatedDeletion: true
            )
        ) {
            IdentityFeature()
        }

        // Animation is visual only — reducer logic is identical
        await store.send(.view(.deleteCardButtonTapped(Self.idB))) {
            $0.cards.remove(id: Self.idB)
        }

        #expect(store.state.cards.count == 2)
        #expect(store.state.cards[id: Self.idA]?.title == "Card A")
        #expect(store.state.cards[id: Self.idC]?.title == "Card C")
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
}
#endif
