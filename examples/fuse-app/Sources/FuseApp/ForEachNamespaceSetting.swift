import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - ForEachNamespaceSetting Reducer

@Reducer
struct ForEachNamespaceSetting {
    @ObservableState
    struct State: Equatable {
        var cards: IdentifiedArrayOf<LocalCounterFeature.State> = []
        var nextLetter: Character = "A"
        var pendingUICommand: UICommand? = nil
    }

    @CasePathable
    enum Action: ViewAction {
        case cards(IdentifiedActionOf<LocalCounterFeature>)
        case executeUICommand(UICommand)
        case reset
        case seedInitialCards
        case view(View)

        @CasePathable
        enum View {
            case addCardButtonTapped
            case deleteCardButtonTapped(LocalCounterFeature.State.ID)
            case deleteFirstCard
            case deleteLastCard
            case onAppear
            case uiCommandCompleted
        }
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .cards:
                return .none

            case .executeUICommand(let cmd):
                state.pendingUICommand = cmd
                return .none

            case .reset:
                state = .init()
                return .none

            case .seedInitialCards, .view(.onAppear):
                guard state.cards.isEmpty else { return .none }
                for letter in ["A", "B", "C"] {
                    state.cards.append(LocalCounterFeature.State(id: uuid(), title: "Card \(letter)"))
                }
                state.nextLetter = "D"
                return .none

            case .view(.addCardButtonTapped):
                let title = "Card \(state.nextLetter)"
                let id = uuid()
                idLog("[ForEachNS] addCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.cards.append(LocalCounterFeature.State(id: id, title: title))
                state.nextLetter = nextLetter(after: state.nextLetter)
                return .none

            case .view(.deleteCardButtonTapped(let id)):
                let title = state.cards[id: id]?.title ?? "?"
                idLog("[ForEachNS] deleteCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.cards.remove(id: id)
                return .none

            case .view(.deleteFirstCard):
                guard let first = state.cards.first else { return .none }
                return .send(.view(.deleteCardButtonTapped(first.id)))

            case .view(.deleteLastCard):
                guard let last = state.cards.last else { return .none }
                return .send(.view(.deleteCardButtonTapped(last.id)))

            case .view(.uiCommandCompleted):
                state.pendingUICommand = nil
                return .none
            }
        }
        .forEach(\.cards, action: \.cards) {
            LocalCounterFeature()
        }
    }

    private func nextLetter(after current: Character) -> Character {
        guard let ascii = current.asciiValue else { return "A" }
        return ascii >= Character("Z").asciiValue!
            ? "A"
            : Character(Unicode.Scalar(ascii + 1))
    }
}

// MARK: - ForEachNamespaceSettingView

@ViewAction(for: ForEachNamespaceSetting.self)
struct ForEachNamespaceSettingView: View {
    let store: StoreOf<ForEachNamespaceSetting>

    var body: some View {
        let _ = idLog("[ForEachNS] body: cards=\(store.cards.count)")
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(
                        store.scope(state: \.cards, action: \.cards),
                        id: \.state.id
                    ) { cardStore in
                        let _ = idLog("[ForEachNS] ForEach item: card=\(cardStore.state.title) id=\(cardStore.state.id.uuidString.prefix(8))")
                        HStack(spacing: 8) {
                            CounterCardView(store: cardStore)
                            Button(role: .destructive) {
                                send(.deleteCardButtonTapped(cardStore.state.id))
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 44)
                        }
                        .padding(.horizontal)
                        .id(cardStore.state.id)
                    }
                }
            }
            .navigationTitle("ForEach Namespace")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { send(.addCardButtonTapped) } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: store.cards.count) { oldCount, newCount in
                if newCount > oldCount, let last = store.cards.last {
                    proxy.scrollTo(last.id)
                }
            }
            .onChange(of: store.pendingUICommand) {
                guard let cmd = store.pendingUICommand else { return }
                switch cmd {
                case .scrollToTop:
                    if let first = store.cards.first {
                        proxy.scrollTo(first.id)
                    }
                case .scrollToBottom:
                    if let last = store.cards.last {
                        proxy.scrollTo(last.id)
                    }
                case .scrollTo(let itemID):
                    proxy.scrollTo(itemID)
                case .tapButton:
                    break
                }
                send(.uiCommandCompleted)
            }
            .onAppear { send(.onAppear) }
        }
    }
}
