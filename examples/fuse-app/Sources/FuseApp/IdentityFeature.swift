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
    let instanceID = UUID()

    var body: some View {
        let _ = idLog("[PeerRememberTestView] body: tapCount=\(tapCount) instanceID=\(instanceID.uuidString.prefix(8))")
        Button {
            tapCount += 1
        } label: {
            Text("Taps: \(tapCount) (id: \(instanceID.uuidString.prefix(8)))")
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
        // Section 1 & 2: Eager Container Keying (cards + reorder)
        var eagerCards: IdentifiedArrayOf<CardItem> = [
            CardItem(id: UUID(), title: "Card A"),
            CardItem(id: UUID(), title: "Card B"),
        ]
        var nextEagerCardLetter: Character = "C"

        // Section 2: Duplicate Key Guard — uses raw arrays, NOT TCA state (Plan 02)

        // Section 3: AnimatedContent — independent card array
        var animatedCards: IdentifiedArrayOf<CardItem> = [
            CardItem(id: UUID(), title: "Card A"),
            CardItem(id: UUID(), title: "Card B"),
            CardItem(id: UUID(), title: "Card C"),
        ]
        var nextAnimatedCardLetter: Character = "D"
        var isAnimatedDeletion: Bool = false

        // Section 4: Picker Selection
        var selectedStyle: String = "bold"

        // Section 5: TabView Selection
        var selectedTab: Int = 0

        // Section 6: Lazy Container Identity — independent card array
        var lazyCards: IdentifiedArrayOf<CardItem> = [
            CardItem(id: UUID(), title: "Card A"),
            CardItem(id: UUID(), title: "Card B"),
            CardItem(id: UUID(), title: "Card C"),
        ]
        var nextLazyCardLetter: Character = "D"

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
            case addEagerCardButtonTapped
            case deleteEagerCardButtonTapped(CardItem.ID)
            case reorderEagerCardButtonTapped

            // Section 3: AnimatedContent
            case addAnimatedCardButtonTapped
            case deleteAnimatedCardButtonTapped(CardItem.ID)
            case toggleAnimatedDeletion

            // Section 4: Picker Selection
            case styleSelected(String)

            // Section 5: TabView Selection
            case tabSelected(Int)

            // Section 6: Lazy Container Identity
            case addLazyCardButtonTapped
            case deleteLazyCardButtonTapped(CardItem.ID)

            // Section 8: .id() State Reset
            case resetTokenButtonTapped
        }
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // Section 1: Eager Container Keying
            case .view(.addEagerCardButtonTapped):
                let title = "Card \(state.nextEagerCardLetter)"
                let id = uuid()
                idLog("[IdentityFeature] addEagerCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.eagerCards.append(CardItem(id: id, title: title))
                let next = Unicode.Scalar(state.nextEagerCardLetter.asciiValue! + 1)
                state.nextEagerCardLetter = Character(next)
                return .none

            case let .view(.deleteEagerCardButtonTapped(id)):
                let title = state.eagerCards[id: id]?.title ?? "?"
                idLog("[IdentityFeature] deleteEagerCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.eagerCards.remove(id: id)
                let remaining = state.eagerCards.map { "\($0.title)=\($0.id.uuidString.prefix(8))" }.joined(separator: ", ")
                idLog("[IdentityFeature] remaining eager: \(remaining)")
                return .none

            case .view(.reorderEagerCardButtonTapped):
                guard state.eagerCards.count > 1 else { return .none }
                let last = state.eagerCards.removeLast()
                state.eagerCards.insert(last, at: 0)
                idLog("[IdentityFeature] reorder eager: moved \(last.title) to front")
                return .none

            // Section 3: AnimatedContent
            case .view(.addAnimatedCardButtonTapped):
                let title = "Card \(state.nextAnimatedCardLetter)"
                let id = uuid()
                idLog("[IdentityFeature] addAnimatedCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.animatedCards.append(CardItem(id: id, title: title))
                let next = Unicode.Scalar(state.nextAnimatedCardLetter.asciiValue! + 1)
                state.nextAnimatedCardLetter = Character(next)
                return .none

            case let .view(.deleteAnimatedCardButtonTapped(id)):
                let title = state.animatedCards[id: id]?.title ?? "?"
                idLog("[IdentityFeature] deleteAnimatedCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.animatedCards.remove(id: id)
                let remaining = state.animatedCards.map { "\($0.title)=\($0.id.uuidString.prefix(8))" }.joined(separator: ", ")
                idLog("[IdentityFeature] remaining animated: \(remaining)")
                return .none

            case .view(.toggleAnimatedDeletion):
                state.isAnimatedDeletion.toggle()
                idLog("[IdentityFeature] animatedDeletion: \(state.isAnimatedDeletion)")
                return .none

            // Section 4: Picker Selection
            case let .view(.styleSelected(style)):
                state.selectedStyle = style
                idLog("[IdentityFeature] styleSelected: \(style)")
                return .none

            // Section 5: TabView Selection
            case let .view(.tabSelected(tab)):
                state.selectedTab = tab
                idLog("[IdentityFeature] tabSelected: \(tab)")
                return .none

            // Section 6: Lazy Container Identity
            case .view(.addLazyCardButtonTapped):
                let title = "Card \(state.nextLazyCardLetter)"
                let id = uuid()
                idLog("[IdentityFeature] addLazyCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.lazyCards.append(CardItem(id: id, title: title))
                let next = Unicode.Scalar(state.nextLazyCardLetter.asciiValue! + 1)
                state.nextLazyCardLetter = Character(next)
                return .none

            case let .view(.deleteLazyCardButtonTapped(id)):
                let title = state.lazyCards[id: id]?.title ?? "?"
                idLog("[IdentityFeature] deleteLazyCard: id=\(id.uuidString.prefix(8)) title=\(title)")
                state.lazyCards.remove(id: id)
                let remaining = state.lazyCards.map { "\($0.title)=\($0.id.uuidString.prefix(8))" }.joined(separator: ", ")
                idLog("[IdentityFeature] remaining lazy: \(remaining)")
                return .none

            // Section 8: .id() State Reset
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

        section1Controls
        section1VStack
        section1HStack
        section1ZStack
    }

    private var section1Controls: some View {
        HStack(spacing: 12) {
            Button("Add Card") { send(.addEagerCardButtonTapped) }
            Button("Reorder") { send(.reorderEagerCardButtonTapped) }
        }
        .buttonStyle(.bordered)
    }

    private var section1VStack: some View {
        VStack(spacing: 8) {
            Text("VStack").font(.subheadline).bold()
            ForEach(store.eagerCards) { card in
                HStack {
                    CounterCard(title: card.title)
                    Button(role: .destructive) {
                        send(.deleteEagerCardButtonTapped(card.id))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var section1HStack: some View {
        VStack(spacing: 8) {
            Text("HStack (scroll)").font(.subheadline).bold()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.eagerCards) { card in
                        VStack(spacing: 4) {
                            CounterCard(title: card.title)
                            Button(role: .destructive) {
                                send(.deleteEagerCardButtonTapped(card.id))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
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
                ForEach(Array(store.eagerCards.enumerated()), id: \.element.id) { index, card in
                    VStack(alignment: .leading, spacing: 4) {
                        CounterCard(title: card.title)
                        Button(role: .destructive) {
                            send(.deleteEagerCardButtonTapped(card.id))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
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
            .frame(minHeight: CGFloat(store.eagerCards.count * 40 + 80))
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
        let _ = idLog("[Section3] body: cards=\(store.animatedCards.count) animated=\(store.isAnimatedDeletion) ids=\(store.animatedCards.map { $0.id.uuidString.prefix(8) }.joined(separator: ","))")
        SectionHeaderView(
            number: 3,
            title: "Animated Content",
            description: "Toggle withAnimation for deletions. Deleted cards should animate out. Remaining cards should retain counter state through the animation."
        )

        HStack(spacing: 12) {
            Button("Add Card") { send(.addAnimatedCardButtonTapped) }
                .buttonStyle(.bordered)
            Toggle("Animated Deletion", isOn: Binding(
                get: { store.isAnimatedDeletion },
                set: { _ in send(.toggleAnimatedDeletion) }
            ))
        }

        VStack(spacing: 8) {
            ForEach(store.animatedCards) { card in
                let _ = idLog("[Section3] ForEach item: card=\(card.title) id=\(card.id.uuidString.prefix(8))")
                HStack {
                    CounterCard(title: card.title)
                    Button(role: .destructive) {
                        if store.isAnimatedDeletion {
                            idLog("[Section3] deleteCard WITH animation: card=\(card.title) id=\(card.id.uuidString.prefix(8))")
                            withAnimation {
                                _ = send(.deleteAnimatedCardButtonTapped(card.id))
                            }
                        } else {
                            idLog("[Section3] deleteCard WITHOUT animation: card=\(card.title) id=\(card.id.uuidString.prefix(8))")
                            send(.deleteAnimatedCardButtonTapped(card.id))
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        Text("Cards: \(store.animatedCards.count)")
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

// MARK: - Section 5: TabView Selection

@ViewAction(for: IdentityFeature.self)
struct IdentitySection5View: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        SectionHeaderView(
            number: 5,
            title: "TabView Selection",
            description: "Mini TabView with 3 tabs. Tab selection binding should update correctly. Each tab shows its name and a counter."
        )

        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { send(.tabSelected($0)) }
        )) {
            IdentitySection5TabContent(label: "Home", tag: 0)
                .tabItem { Text("Home") }
                .tag(0)
            IdentitySection5TabContent(label: "Search", tag: 1)
                .tabItem { Text("Search") }
                .tag(1)
            IdentitySection5TabContent(label: "Profile", tag: 2)
                .tabItem { Text("Profile") }
                .tag(2)
        }
        .frame(height: 200)

        Text("Selected tab: \(store.selectedTab)")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Tab content view with local @State counter for identity retention testing.
struct IdentitySection5TabContent: View {
    let label: String
    let tag: Int
    @State var counter: Int = 0
    let instanceID = UUID()

    var body: some View {
        let _ = idLog("[Section5Tab] body: label=\(label) tag=\(tag) counter=\(counter) instanceID=\(instanceID.uuidString.prefix(8))")
        VStack(spacing: 8) {
            Text(label).font(.headline)
            HStack {
                Button("-") { counter -= 1 }.buttonStyle(.borderless)
                Text("\(counter)").font(.title3).frame(minWidth: 40)
                Button("+") { counter += 1 }.buttonStyle(.borderless)
            }
            Text("Tab \(tag) (id: \(instanceID.uuidString.prefix(8)))").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { idLog("[Section5Tab] onAppear: label=\(label) instanceID=\(instanceID.uuidString.prefix(8))") }
        .onDisappear { idLog("[Section5Tab] onDisappear: label=\(label) instanceID=\(instanceID.uuidString.prefix(8))") }
    }
}

// MARK: - Section 6: Lazy Container Identity

@ViewAction(for: IdentityFeature.self)
struct IdentitySection6View: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        let _ = idLog("[Section6] body: cards=\(store.lazyCards.count) ids=\(store.lazyCards.map { $0.id.uuidString.prefix(8) }.joined(separator: ","))")
        SectionHeaderView(
            number: 6,
            title: "Lazy Container Identity",
            description: "List with ForEach over cards. Scroll down, increment counters, scroll back — counters should be retained. Add/delete items — remaining counters preserved."
        )

        HStack(spacing: 12) {
            Button("Add Card") { send(.addLazyCardButtonTapped) }
            Text("Items: \(store.lazyCards.count)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)

        VStack(spacing: 8) {
            List {
                ForEach(store.lazyCards) { card in
                    let _ = idLog("[Section6] ForEach item: card=\(card.title) id=\(card.id.uuidString.prefix(8))")
                    HStack {
                        CounterCard(title: card.title)
                        Spacer()
                        Button(role: .destructive) {
                            send(.deleteLazyCardButtonTapped(card.id))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(height: 250)
        }
    }
}

// MARK: - Section 7: Transpiler Peer Remembering

@ViewAction(for: IdentityFeature.self)
struct IdentitySection7View: View {
    @Bindable var store: StoreOf<IdentityFeature>
    let instanceID = UUID()

    var body: some View {
        let _ = idLog("[Section7] body: instanceID=\(instanceID.uuidString.prefix(8))")
        SectionHeaderView(
            number: 7,
            title: "Transpiler Peer Remembering",
            description: "Android-only test. PeerRememberTestView uses @State + let-with-default (no constructor params). Tap count should survive parent recomposition on Android."
        )

        VStack(alignment: .leading, spacing: 12) {
            Text("Test: @State + let-with-default (no constructor params)")
                .font(.caption).bold()

            // Provide manual item key so rememberViewPeer() uses PeerStore path
            // (standalone views outside ForEach have no IdentityKeyModifier)
            #if SKIP
            // SKIP INSERT: val providedPeerItemKey = LocalPeerStoreItemKey provides "peer-remember-test-view"
            CompositionLocalProvider(providedPeerItemKey) {
                PeerRememberTestView()
            }
            #else
            PeerRememberTestView()
            #endif

            Text("Trigger parent recomposition by adding a card above (Section 1). If peer remembering works, tap count is preserved.")
                .font(.caption2).foregroundStyle(.secondary)

            Divider()

            Text("CounterCard: mixed view with Store (constructor params + let-with-default)")
                .font(.caption).bold()

            #if SKIP
            // SKIP INSERT: val providedPeerTestCardKey = LocalPeerStoreItemKey provides "peer-test-counter-card"
            CompositionLocalProvider(providedPeerTestCardKey) {
                CounterCard(title: "Peer Test Card")
            }
            #else
            CounterCard(title: "Peer Test Card")
            #endif
        }
        .onAppear { idLog("[Section7] onAppear: instanceID=\(instanceID.uuidString.prefix(8))") }
        .onDisappear { idLog("[Section7] onDisappear: instanceID=\(instanceID.uuidString.prefix(8))") }
    }
}

// MARK: - Section 8: .id() State Reset

@ViewAction(for: IdentityFeature.self)
struct IdentitySection8View: View {
    @Bindable var store: StoreOf<IdentityFeature>

    var body: some View {
        SectionHeaderView(
            number: 8,
            title: ".id() State Reset",
            description: "Counter view with .id() tied to reset token. Changing the reset token should destroy and recreate the view, resetting counter to 0."
        )

        VStack(spacing: 12) {
            IdentitySection8CounterView()
                .id(store.resetToken)

            Button("Reset Token") {
                send(.resetTokenButtonTapped)
            }
            .buttonStyle(.bordered)

            Text("Token: \(store.resetToken.uuidString.prefix(8))")
                .font(.caption).monospaced().foregroundStyle(.secondary)
        }
    }
}

/// A simple counter view for Section 8 that uses local @State.
/// When the parent's .id() changes, this view is destroyed and recreated, resetting the counter.
struct IdentitySection8CounterView: View {
    @State var counter: Int = 0

    var body: some View {
        HStack {
            Button("-") { counter -= 1 }.buttonStyle(.borderless)
            Text("\(counter)")
                .font(.title2).frame(minWidth: 50)
            Button("+") { counter += 1 }.buttonStyle(.borderless)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                IdentitySection5View(store: store)
                Divider()
                IdentitySection6View(store: store)
                Divider()
                IdentitySection7View(store: store)
                Divider()
                IdentitySection8View(store: store)
            }
            .padding()
        }
        .navigationTitle("Identity")
    }
}
