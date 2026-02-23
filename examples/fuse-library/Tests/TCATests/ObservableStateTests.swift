import ComposableArchitecture
import Foundation
import Testing

// MARK: - Test Reducers (file scope — macros can't attach to local types)

@Reducer
struct ObservableFeature {
    @ObservableState
    struct State: Equatable {
        var text: String = ""
        var count: Int = 0
        @ObservationStateIgnored var ignored: Int = 0
    }
    enum Action {
        case setText(String)
        case setCount(Int)
        case setIgnored(Int)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setText(text):
                state.text = text
                return .none
            case let .setCount(count):
                state.count = count
                return .none
            case let .setIgnored(value):
                state.ignored = value
                return .none
            }
        }
    }
}

@Reducer
struct RowFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        let id: UUID
        var value: Int = 0
    }
    enum Action {
        case increment
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.value += 1
                return .none
            }
        }
    }
}

@Reducer
struct ListFeature {
    @ObservableState
    struct State: Equatable {
        var rows: IdentifiedArrayOf<RowFeature.State> = []
    }
    enum Action {
        case rows(IdentifiedActionOf<RowFeature>)
        case addRow(UUID)
        case removeRow(UUID)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .addRow(id):
                state.rows.append(RowFeature.State(id: id))
                return .none
            case let .removeRow(id):
                state.rows.remove(id: id)
                return .none
            case .rows:
                return .none
            }
        }
        .forEach(\.rows, action: \.rows) {
            RowFeature()
        }
    }
}

@Reducer
struct DetailFeature {
    @ObservableState
    struct State: Equatable {
        var title: String = "Detail"
    }
    enum Action {
        case setTitle(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setTitle(title):
                state.title = title
                return .none
            }
        }
    }
}

@Reducer
struct OptionalParent {
    @ObservableState
    struct State: Equatable {
        @Presents var detail: DetailFeature.State?
    }
    enum Action {
        case detail(PresentationAction<DetailFeature.Action>)
        case showDetail
        case hideDetail
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showDetail:
                state.detail = DetailFeature.State()
                return .none
            case .hideDetail:
                state.detail = nil
                return .none
            case .detail:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            DetailFeature()
        }
    }
}

@Reducer
enum DestinationFeature {
    case featureA(ObservableFeature)
    case featureB(DetailFeature)
}

@Reducer
struct EnumParent {
    @ObservableState
    struct State {
        @Presents var destination: DestinationFeature.State?
    }
    enum Action {
        case destination(PresentationAction<DestinationFeature.Action>)
        case showA
        case showB
        case dismiss
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showA:
                state.destination = .featureA(ObservableFeature.State())
                return .none
            case .showB:
                state.destination = .featureB(DetailFeature.State())
                return .none
            case .dismiss:
                state.destination = nil
                return .none
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

@Reducer
struct OnChangeFeature {
    @ObservableState
    struct State: Equatable {
        var value: Int = 0
        var changeCount: Int = 0
    }
    enum Action {
        case setValue(Int)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setValue(value):
                state.value = value
                return .none
            }
        }
        .onChange(of: { $0.value }) { _, _ in
            Reduce { state, _ in
                state.changeCount += 1
                return .none
            }
        }
    }
}

@Reducer
struct ViewActionFeature {
    @ObservableState
    struct State: Equatable {
        var count: Int = 0
    }
    enum Action: ViewAction {
        case view(View)
        enum View {
            case increment
            case decrement
        }
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.increment):
                state.count += 1
                return .none
            case .view(.decrement):
                state.count -= 1
                return .none
            }
        }
    }
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct ObservableStateTests {

    // MARK: TCA-17: @ObservableState _$id changes on mutation

    @Test func observableStateIdentity() {
        // _$willModify() updates the _$id by generating a new UUID for the location.
        // After copy, the two states share storage (CoW). Calling _$willModify on one
        // triggers CoW and assigns a new UUID, making the IDs diverge.
        var state = ObservableFeature.State()
        let snapshot = state  // CoW copy — shares storage reference
        #expect(_$isIdentityEqual(state, snapshot), "Copy should have equal identity initially")

        state._$willModify()  // triggers CoW + new UUID
        #expect(!_$isIdentityEqual(state, snapshot), "_$id should diverge after _$willModify()")

        // Verify the protocol requirement exists and returns a valid ID
        let id = state._$id
        #expect(id == state._$id, "_$id should be stable between reads without mutation")
    }

    // MARK: TCA-18: @ObservationStateIgnored does not change _$id

    @Test func observationStateIgnored() {
        let store = Store(initialState: ObservableFeature.State()) {
            ObservableFeature()
        }
        let idBefore = store.withState(\._$id)
        store.send(.setIgnored(999))
        let idAfter = store.withState(\._$id)
        #expect(idBefore == idAfter, "_$id should NOT change for @ObservationStateIgnored property")
        #expect(store.withState(\.ignored) == 999)
    }

    // MARK: TCA-23: ForEach scoping — scope to child, mutate middle row, add/remove

    @Test func forEachScoping() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let store = Store(
            initialState: ListFeature.State(rows: [
                RowFeature.State(id: id1, value: 0),
                RowFeature.State(id: id2, value: 10),
                RowFeature.State(id: id3, value: 20),
            ])
        ) {
            ListFeature()
        }

        // Scope to middle row and mutate
        let childStore = store.scope(state: \.rows[id: id2]!, action: \.rows[id: id2])
        childStore.send(.increment)
        #expect(store.withState(\.rows[id: id2]?.value) == 11)

        // Other rows unchanged
        #expect(store.withState(\.rows[id: id1]?.value) == 0)
        #expect(store.withState(\.rows[id: id3]?.value) == 20)

        // Add a row
        let id4 = UUID()
        store.send(.addRow(id4))
        #expect(store.withState(\.rows.count) == 4)
        #expect(store.withState(\.rows[id: id4]?.value) == 0)

        // Remove a row
        store.send(.removeRow(id1))
        #expect(store.withState(\.rows.count) == 3)
        #expect(store.withState(\.rows[id: id1]) == nil)
    }

    // MARK: TCA-23: ForEach identity stability — child _$id stable when sibling mutated

    @Test func forEachIdentityStability() {
        let id1 = UUID()
        let id2 = UUID()
        let store = Store(
            initialState: ListFeature.State(rows: [
                RowFeature.State(id: id1, value: 0),
                RowFeature.State(id: id2, value: 0),
            ])
        ) {
            ListFeature()
        }

        let id2Before = store.withState(\.rows[id: id2]!._$id)

        // Mutate row 1, check row 2's identity is stable
        store.send(.rows(.element(id: id1, action: .increment)))
        let id2After = store.withState(\.rows[id: id2]!._$id)
        #expect(id2Before == id2After, "Child _$id should not change when sibling is mutated")
    }

    // MARK: TCA-24: Optional scoping — nil → present → nil

    @Test func optionalScoping() {
        let store = Store(initialState: OptionalParent.State()) {
            OptionalParent()
        }

        // Starts nil
        #expect(store.withState(\.detail) == nil)

        // Show detail → non-nil
        store.send(.showDetail)
        #expect(store.withState(\.detail) != nil)
        #expect(store.withState(\.detail?.title) == "Detail")

        // Mutate child through presentation action
        store.send(.detail(.presented(.setTitle("Updated"))))
        #expect(store.withState(\.detail?.title) == "Updated")

        // Hide detail → nil
        store.send(.hideDetail)
        #expect(store.withState(\.detail) == nil)
    }

    // MARK: TCA-25: Enum case switching with teardown

    @Test func enumCaseSwitching() {
        let store = Store(initialState: EnumParent.State()) {
            EnumParent()
        }

        // Starts nil
        #expect(store.withState(\.destination) == nil)

        // Show case A
        store.send(.showA)
        #expect(store.withState(\.destination)?.is(\.featureA) == true)

        // Switch to case B (tears down A)
        store.send(.showB)
        #expect(store.withState(\.destination)?.is(\.featureB) == true)

        // Dismiss (tears down B)
        store.send(.dismiss)
        #expect(store.withState(\.destination) == nil)
    }

    // MARK: TCA-29: onChange fires on value change, not on same-value

    @Test func onChange() {
        let store = Store(initialState: OnChangeFeature.State()) {
            OnChangeFeature()
        }

        // Initial — no changes
        #expect(store.withState(\.changeCount) == 0)

        // Change value from 0 → 1: onChange should fire
        store.send(.setValue(1))
        #expect(store.withState(\.value) == 1)
        #expect(store.withState(\.changeCount) == 1)

        // Same value 1 → 1: onChange should NOT fire
        store.send(.setValue(1))
        #expect(store.withState(\.changeCount) == 1, "onChange should not fire for same value")

        // Change value 1 → 2: onChange should fire again
        store.send(.setValue(2))
        #expect(store.withState(\.changeCount) == 2)
    }

    // MARK: TCA-30: _printChanges doesn't crash

    @Test func printChanges() {
        let store = Store(initialState: ObservableFeature.State()) {
            ObservableFeature()._printChanges()
        }
        // Just verify it doesn't crash
        store.send(.setText("hello"))
        store.send(.setCount(42))
        #expect(store.withState(\.text) == "hello")
        #expect(store.withState(\.count) == 42)
    }

    // MARK: TCA-31: ViewAction send() dispatches correctly

    @Test func viewAction() {
        let store = Store(initialState: ViewActionFeature.State()) {
            ViewActionFeature()
        }

        store.send(.view(.increment))
        #expect(store.withState(\.count) == 1)

        store.send(.view(.increment))
        #expect(store.withState(\.count) == 2)

        store.send(.view(.decrement))
        #expect(store.withState(\.count) == 1)
    }
}
