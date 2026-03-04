#if !SKIP
import ComposableArchitecture
import Foundation
import Testing
@testable import FuseApp

// MARK: - ForEachNamespaceSetting Extended Tests

/// Extended TCA TestStore tests for ForEachNamespaceSetting card operations.
@Suite(.serialized) @MainActor
struct ForEachNamespaceExtendedTests {

    private static let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let idD = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private static let idNew = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    @Test func multipleDeletions() async {
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [
                    CardItem(id: Self.idA, title: "Card A"),
                    CardItem(id: Self.idB, title: "Card B"),
                    CardItem(id: Self.idC, title: "Card C"),
                    CardItem(id: Self.idD, title: "Card D"),
                ],
                nextLetter: "E"
            )
        ) {
            ForEachNamespaceSetting()
        }

        await store.send(.view(.deleteCard(Self.idA))) {
            $0.cards.remove(id: Self.idA)
        }

        await store.send(.view(.deleteCard(Self.idC))) {
            $0.cards.remove(id: Self.idC)
        }

        #expect(store.state.cards.count == 2)
        #expect(store.state.cards[id: Self.idB]?.title == "Card B")
        #expect(store.state.cards[id: Self.idD]?.title == "Card D")
    }

    @Test func addMultipleCards() async {
        let uuids = [Self.idA, Self.idB, Self.idC]
        let counter = LockIsolated(0)
        let store = TestStore(
            initialState: ForEachNamespaceSetting.State(
                cards: [],
                nextLetter: "A"
            )
        ) {
            ForEachNamespaceSetting()
        } withDependencies: {
            $0.uuid = .init {
                let i = counter.value
                counter.withValue { $0 += 1 }
                return uuids[i]
            }
        }

        await store.send(.view(.addCard)) {
            $0.cards.append(CardItem(id: Self.idA, title: "Card A"))
            $0.nextLetter = "B"
        }

        await store.send(.view(.addCard)) {
            $0.cards.append(CardItem(id: Self.idB, title: "Card B"))
            $0.nextLetter = "C"
        }

        await store.send(.view(.addCard)) {
            $0.cards.append(CardItem(id: Self.idC, title: "Card C"))
            $0.nextLetter = "D"
        }

        #expect(store.state.cards.count == 3)
    }
}
#endif
