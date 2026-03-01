import ComposableArchitecture
import SkipFuse
import SwiftUI

private let identityLogger = Logger(subsystem: "fuse.app", category: "Identity")
private func idLog(_ msg: String) {
    identityLogger.debug("\(msg)")
}

// MARK: - CardItem

struct CardItem: Equatable, Identifiable {
    let id: UUID
    var title: String
}

// MARK: - LocalCounterFeature Reducer

@Reducer
struct LocalCounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
    }

    enum Action {
        case decrementButtonTapped
        case incrementButtonTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .decrementButtonTapped:
                state.count -= 1
                return .none
            case .incrementButtonTapped:
                state.count += 1
                return .none
            }
        }
    }
}

// MARK: - CounterCard View

struct CounterCard: View {
    let title: String
    let store = Store(initialState: LocalCounterFeature.State()) {
        LocalCounterFeature()
    }
    let instanceID = UUID()

    var body: some View {
        let _ = idLog("[CounterCard] body: title=\(title) instanceID=\(instanceID.uuidString.prefix(8)) count=\(store.count)")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(instanceID.uuidString.prefix(8))
                    .font(.caption).monospaced()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("-") { store.send(.decrementButtonTapped) }
                    .buttonStyle(.borderless)
                Text("\(store.count)")
                    .font(.title3).frame(minWidth: 40)
                Button("+") { store.send(.incrementButtonTapped) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - IdentityFeature Reducer

@Reducer
struct IdentityFeature {
    @ObservableState
    struct State: Equatable {
        var cards: IdentifiedArrayOf<CardItem> = [
            CardItem(id: UUID(), title: "Card A"),
            CardItem(id: UUID(), title: "Card B"),
        ]
        var nextCardLetter: Character = "C"
    }

    @CasePathable
    enum Action: ViewAction {
        case view(View)

        @CasePathable
        enum View {
            case addCardButtonTapped
            case deleteCardButtonTapped(CardItem.ID)
        }
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.addCardButtonTapped):
                let title = "Card \(state.nextCardLetter)"
                let id = uuid()
                idLog("[IdentityFeature] addCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.cards.append(CardItem(id: id, title: title))
                let next = Unicode.Scalar(state.nextCardLetter.asciiValue! + 1)
                state.nextCardLetter = Character(next)
                return .none

            case let .view(.deleteCardButtonTapped(id)):
                let title = state.cards[id: id]?.title ?? "?"
                idLog("[IdentityFeature] deleteCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.cards.remove(id: id)
                let remaining = state.cards.map { "\($0.title)=\($0.id.uuidString.prefix(8))" }.joined(separator: ", ")
                idLog("[IdentityFeature] remaining: \(remaining)")
                return .none
            }
        }
    }
}

// MARK: - IdentityView

@ViewAction(for: IdentityFeature.self)
struct IdentityView: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        let _ = idLog("[IdentityView] body: cards=[\(store.cards.map { "\($0.title)=\($0.id.uuidString.prefix(8))" }.joined(separator: ", "))]")
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Each card has its own counter and UUID (let-with-default properties). Add/delete cards to verify identity preservation — remaining cards should keep their count and UUID after mutations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(store.cards) { card in
                        CounterCard(title: card.title)
                            .padding(.horizontal)
                        if card.id != store.cards.last?.id {
                            Divider()
                        }
                    }
                }

                VStack(spacing: 8) {
                    Button {
                        send(.addCardButtonTapped)
                    } label: {
                        Label("Add Card", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ForEach(store.cards) { card in
                        Button(role: .destructive) {
                            send(.deleteCardButtonTapped(card.id))
                        } label: {
                            Label("Delete \(card.title)", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Identity")
    }
}
