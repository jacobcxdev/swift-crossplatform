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

/// A view with constructor params (title) + let-with-default (store, instanceID).
/// Exercises the transpiler's mixed-view peer remembering (Plan 05 fix).
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

// MARK: - PeerRememberTestView

/// A purpose-built view for Section 7 (Transpiler Peer Remembering).
/// Has @State + let-with-default but NO constructor params.
/// Exercises the transpiler's unconditional peer remembering (no input hash needed).
struct PeerRememberTestView: View {
    @State var tapCount: Int = 0
    let color: Color = .blue

    var body: some View {
        Button {
            tapCount += 1
        } label: {
            Text("Taps: \(tapCount)")
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - IdentityFeature Reducer

@Reducer
struct IdentityFeature {
    @ObservableState
    struct State: Equatable {
        // Section 1: Eager Container Keying (cards + reorder)
        var cards: IdentifiedArrayOf<CardItem> = [
            CardItem(id: UUID(), title: "Card A"),
            CardItem(id: UUID(), title: "Card B"),
        ]
        var nextCardLetter: Character = "C"

        // Section 2: Duplicate Key Guard — uses raw arrays, NOT TCA state (Plan 02)

        // Section 3: AnimatedContent — uses cards with withAnimation (Plan 02)
        var isAnimatedDeletion: Bool = false

        // Section 4: Picker Selection
        var selectedStyle: String = "bold"

        // Section 5: TabView Selection
        var selectedTab: Int = 0

        // Section 6: Lazy Container Identity — reuses cards (Plan 03)

        // Section 7: Transpiler Peer Remembering — uses PeerRememberTestView (Plan 03, Android-only)

        // Section 8: .id() State Reset
        var resetToken: UUID = UUID()
    }

    @CasePathable
    enum Action: ViewAction {
        case view(View)

        @CasePathable
        enum View {
            // Section 1: Eager Container Keying
            case addCardButtonTapped
            case deleteCardButtonTapped(CardItem.ID)
            case reorderCardButtonTapped

            // Section 3: AnimatedContent
            case toggleAnimatedDeletion

            // Section 4: Picker Selection
            case styleSelected(String)

            // Section 5: TabView Selection
            case tabSelected(Int)

            // Section 8: .id() State Reset
            case resetTokenButtonTapped
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

            case .view(.reorderCardButtonTapped):
                guard state.cards.count > 1 else { return .none }
                let last = state.cards.removeLast()
                state.cards.insert(last, at: 0)
                idLog("[IdentityFeature] reorder: moved \(last.title) to front")
                return .none

            case .view(.toggleAnimatedDeletion):
                state.isAnimatedDeletion.toggle()
                idLog("[IdentityFeature] animatedDeletion: \(state.isAnimatedDeletion)")
                return .none

            case let .view(.styleSelected(style)):
                state.selectedStyle = style
                idLog("[IdentityFeature] styleSelected: \(style)")
                return .none

            case let .view(.tabSelected(tab)):
                state.selectedTab = tab
                idLog("[IdentityFeature] tabSelected: \(tab)")
                return .none

            case .view(.resetTokenButtonTapped):
                state.resetToken = uuid()
                idLog("[IdentityFeature] resetToken: \(state.resetToken.uuidString.prefix(8))")
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
        ScrollView {
            VStack(spacing: 24) {
                Text("Identity Tab -- Sections implemented in subsequent plans")
                    .font(.headline)
                // Placeholder: full UI comes in Plans 02 + 03
            }
            .padding()
        }
        .navigationTitle("Identity")
    }
}
