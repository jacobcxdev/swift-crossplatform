import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - ForEachNamespaceSetting Reducer

@Reducer
struct ForEachNamespaceSetting {
    @ObservableState
    struct State: Equatable {
        var cards: IdentifiedArrayOf<CardItem> = [
            CardItem(id: UUID(), title: "Card A"),
            CardItem(id: UUID(), title: "Card B"),
            CardItem(id: UUID(), title: "Card C"),
        ]
        var nextLetter: Character = "D"
        var pendingUICommand: UICommand? = nil
    }

    @CasePathable
    enum Action: ViewAction {
        case view(View)
        case reset
        case executeUICommand(UICommand)

        @CasePathable
        enum View {
            case addCard
            case deleteCard(CardItem.ID)
            case deleteFirstCard
            case deleteLastCard
            case uiCommandCompleted
        }
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.addCard):
                let title = "Card \(state.nextLetter)"
                let id = uuid()
                idLog("[ForEachNS] addCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.cards.append(CardItem(id: id, title: title))
                let next: Character
                if let ascii = state.nextLetter.asciiValue {
                    next = ascii >= Character("Z").asciiValue!
                        ? Character("A")
                        : Character(Unicode.Scalar(ascii + 1))
                } else {
                    next = Character("A")
                }
                state.nextLetter = next
                return .none

            case .view(.deleteCard(let id)):
                let title = state.cards[id: id]?.title ?? "?"
                idLog("[ForEachNS] deleteCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.cards.remove(id: id)
                let remaining = state.cards.map { "\($0.title)=\($0.id.uuidString.prefix(8))" }.joined(separator: ", ")
                idLog("[ForEachNS] remaining: \(remaining)")
                return .none

            case .view(.deleteFirstCard):
                guard let first = state.cards.first else { return .none }
                return .send(.view(.deleteCard(first.id)))

            case .view(.deleteLastCard):
                guard let last = state.cards.last else { return .none }
                return .send(.view(.deleteCard(last.id)))

            case .view(.uiCommandCompleted):
                state.pendingUICommand = nil
                return .none

            case .executeUICommand(let cmd):
                state.pendingUICommand = cmd
                return .none

            case .reset:
                state = .init()
                return .none
            }
        }
    }
}

// MARK: - ForEachNamespaceSettingView

@ViewAction(for: ForEachNamespaceSetting.self)
struct ForEachNamespaceSettingView: View {
    @Bindable var store: StoreOf<ForEachNamespaceSetting>

    var body: some View {
        let _ = idLog("[ForEachNS] body: cards=\(store.cards.count) ids=\(store.cards.map { $0.id.uuidString.prefix(8) }.joined(separator: ","))")
        ScrollViewReader { proxy in
            List {
                Section {
                    HStack(spacing: 12) {
                        Button("Add Card") { send(.addCard) }
                        Text("Items: \(store.cards.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered)
                }

                Section {
                    ForEach(store.cards) { card in
                        let _ = idLog("[ForEachNS] ForEach item: card=\(card.title) id=\(card.id.uuidString.prefix(8))")
                        HStack(spacing: 8) {
                            CounterCard(title: card.title)
                            Button(role: .destructive) {
                                send(.deleteCard(card.id))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 44)
                        }
                        .tag(card.id.uuidString)
                    }
                }
            }
            .navigationTitle("ForEach Namespace")
            .onChange(of: store.cards.count) { oldCount, newCount in
                // Only auto-scroll on insertions, not deletions
                if newCount > oldCount, let last = store.cards.last {
                    proxy.scrollTo(last.id.uuidString, anchor: .bottom)
                }
            }
            .onChange(of: store.pendingUICommand) {
                guard let cmd = store.pendingUICommand else { return }
                switch cmd {
                case .scrollToTop:
                    if let first = store.cards.first {
                        proxy.scrollTo(first.id.uuidString, anchor: .top)
                    }
                case .scrollToBottom:
                    if let last = store.cards.last {
                        proxy.scrollTo(last.id.uuidString, anchor: .bottom)
                    }
                case .scrollTo(let itemID):
                    proxy.scrollTo(itemID)
                case .scrollByOffset:
                    // Not supported in List/ScrollViewReader. Acknowledged as no-op so the
                    // scenario runner / fuzzer can proceed. The log makes non-execution visible.
                    idLog("[ForEachNS] scrollByOffset not supported in List/ScrollViewReader — no-op")
                }
                send(.uiCommandCompleted)
            }
        }
    }
}
