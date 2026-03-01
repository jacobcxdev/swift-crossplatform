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

// MARK: - DuplicateKeyCounterCard (Section 2, non-TCA)

/// A simple counter card using local @State (no TCA).
/// Used in Section 2 to demonstrate duplicate-key behavior with ForEach(\.self).
struct DuplicateKeyCounterCard: View {
    let label: String
    @State var count: Int = 0

    var body: some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Button("-") { count -= 1 }.buttonStyle(.borderless)
            Text("\(count)").font(.title3).frame(minWidth: 30)
            Button("+") { count += 1 }.buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - IdentityView

// MARK: - SectionHeaderView

struct SectionHeaderView: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Section \(number): \(title)")
                .font(.headline)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section 1: Eager Container Keying

@ViewAction(for: IdentityFeature.self)
struct IdentitySection1View: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        SectionHeaderView(
            number: 1,
            title: "Eager Container Keying",
            description: "VStack, HStack, ZStack with ForEach card deletion and reorder. Remaining cards should preserve counter state and instanceID."
        )

        section1VStack
        section1Controls
        section1HStack
        section1ZStack
    }

    private var section1VStack: some View {
        VStack(spacing: 8) {
            Text("VStack").font(.subheadline).bold()
            ForEach(store.cards) { card in
                HStack {
                    CounterCard(title: card.title)
                    Button(role: .destructive) {
                        send(.deleteCardButtonTapped(card.id))
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var section1Controls: some View {
        HStack(spacing: 12) {
            Button("Add Card") { send(.addCardButtonTapped) }
            Button("Reorder") { send(.reorderCardButtonTapped) }
        }
        .buttonStyle(.bordered)
    }

    private var section1HStack: some View {
        VStack(spacing: 8) {
            Text("HStack (scroll)").font(.subheadline).bold()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.cards) { card in
                        VStack(spacing: 4) {
                            CounterCard(title: card.title)
                            Button(role: .destructive) {
                                send(.deleteCardButtonTapped(card.id))
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(width: 160)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var section1ZStack: some View {
        VStack(spacing: 8) {
            Text("ZStack (overlapping)").font(.subheadline).bold()
            ZStack(alignment: .topLeading) {
                ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                    VStack(alignment: .leading, spacing: 4) {
                        CounterCard(title: card.title)
                        Button(role: .destructive) {
                            send(.deleteCardButtonTapped(card.id))
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(width: 180)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .offset(x: CGFloat(index * 20), y: CGFloat(index * 40))
                }
            }
            .frame(minHeight: CGFloat(store.cards.count * 40 + 80))
        }
    }
}

// MARK: - Section 2: Duplicate Key Guard

struct IdentitySection2View: View {
    var body: some View {
        SectionHeaderView(
            number: 2,
            title: "Duplicate Key Guard",
            description: "Non-TCA raw [String] array with ForEach(\\.self) producing duplicate keys. Each card has independent local counter state. Android: verify _dup suffix guard prevents crash."
        )

        Text("Duplicate keys present: Alpha appears twice")
            .font(.caption)
            .foregroundStyle(.orange)
            .bold()

        VStack(spacing: 4) {
            ForEach(["Alpha", "Beta", "Alpha", "Gamma"], id: \.self) { item in
                DuplicateKeyCounterCard(label: item)
            }
        }
    }
}

// MARK: - Section 3: Animated Content

@ViewAction(for: IdentityFeature.self)
struct IdentitySection3View: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        SectionHeaderView(
            number: 3,
            title: "Animated Content",
            description: "Toggle withAnimation for deletions. Deleted cards should animate out. Remaining cards should retain counter state through the animation."
        )

        Toggle("Animated Deletion", isOn: Binding(
            get: { store.isAnimatedDeletion },
            set: { _ in send(.toggleAnimatedDeletion) }
        ))

        VStack(spacing: 8) {
            ForEach(store.cards) { card in
                HStack {
                    CounterCard(title: card.title)
                    Button(role: .destructive) {
                        if store.isAnimatedDeletion {
                            withAnimation {
                                _ = send(.deleteCardButtonTapped(card.id))
                            }
                        } else {
                            send(.deleteCardButtonTapped(card.id))
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        Text("Cards: \(store.cards.count)")
            .font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Section 4: Picker Selection

private let pickerStyles = ["bold", "italic", "underline", "strikethrough"]

@ViewAction(for: IdentityFeature.self)
struct IdentitySection4View: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        SectionHeaderView(
            number: 4,
            title: "Picker Selection",
            description: "Segmented and menu picker styles with selectionTag verification. Tapping each option should update the displayed selection."
        )

        Text("Segmented Picker").font(.subheadline).bold()
        Picker("Style", selection: Binding(
            get: { store.selectedStyle },
            set: { send(.styleSelected($0)) }
        )) {
            ForEach(pickerStyles, id: \.self) { style in
                Text(style).tag(style)
            }
        }
        .pickerStyle(.segmented)

        Text("Menu Picker").font(.subheadline).bold()
        Picker("Style", selection: Binding(
            get: { store.selectedStyle },
            set: { send(.styleSelected($0)) }
        )) {
            ForEach(pickerStyles, id: \.self) { style in
                Text(style).tag(style)
            }
        }
        .pickerStyle(.menu)

        Text("Selected: \(store.selectedStyle)")
            .font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - IdentityView

@ViewAction(for: IdentityFeature.self)
struct IdentityView: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
                IdentitySection1View(store: store)
                Divider()
                IdentitySection2View()
                Divider()
                IdentitySection3View(store: store)
                Divider()
                IdentitySection4View(store: store)
                Divider()
                // Sections 5-8 implemented in Plan 03
            }
            .padding()
        }
        .navigationTitle("Identity")
    }
}
