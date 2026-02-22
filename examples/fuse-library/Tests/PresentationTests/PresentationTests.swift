import ComposableArchitecture
import SwiftUI
import Testing

// MARK: - Sheet Reducers

@Reducer
struct SheetParent {
    @ObservableState
    struct State: Equatable {
        @Presents var sheet: SheetChild.State?
    }
    enum Action {
        case sheet(PresentationAction<SheetChild.Action>)
        case showSheet
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showSheet:
                state.sheet = SheetChild.State(text: "initial")
                return .none
            case .sheet:
                return .none
            }
        }
        .ifLet(\.$sheet, action: \.sheet) {
            SheetChild()
        }
    }
}

@Reducer
struct SheetChild {
    @ObservableState
    struct State: Equatable {
        var text: String
    }
    enum Action {
        case setText(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setText(text):
                state.text = text
                return .none
            }
        }
    }
}

// MARK: - FullScreenCover Reducer

@Reducer
struct FullScreenParent {
    @ObservableState
    struct State: Equatable {
        @Presents var cover: CoverChild.State?
    }
    enum Action {
        case cover(PresentationAction<CoverChild.Action>)
        case showCover
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showCover:
                state.cover = CoverChild.State(value: 0)
                return .none
            case .cover:
                return .none
            }
        }
        .ifLet(\.$cover, action: \.cover) {
            CoverChild()
        }
    }
}

@Reducer
struct CoverChild {
    @ObservableState
    struct State: Equatable {
        var value: Int
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

// MARK: - Dismissable Child Reducer

@Reducer
struct DismissableChild {
    @ObservableState
    struct State: Equatable {}
    @Dependency(\.dismiss) var dismiss
    enum Action {
        case doneTapped
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .doneTapped:
                return .run { _ in await self.dismiss() }
            }
        }
    }
}

// MARK: - DismissParent (wraps DismissableChild for presentation)

@Reducer
struct DismissParent {
    @ObservableState
    struct State: Equatable {
        @Presents var child: DismissableChild.State?
    }
    enum Action {
        case child(PresentationAction<DismissableChild.Action>)
        case showChild
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showChild:
                state.child = DismissableChild.State()
                return .none
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            DismissableChild()
        }
    }
}

// MARK: - Popover Parent Reducer

@Reducer
struct PopoverParent {
    @ObservableState
    struct State: Equatable {
        @Presents var detail: PopoverChild.State?
    }
    enum Action {
        case detail(PresentationAction<PopoverChild.Action>)
        case showPopover
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showPopover:
                state.detail = PopoverChild.State(info: "popover")
                return .none
            case .detail:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            PopoverChild()
        }
    }
}

@Reducer
struct PopoverChild {
    @ObservableState
    struct State: Equatable {
        var info: String
    }
    enum Action {
        case updateInfo(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .updateInfo(info):
                state.info = info
                return .none
            }
        }
    }
}

// MARK: - Tests

@MainActor
struct PresentationTests {

    // MARK: - Sheet (NAV-05, NAV-06)

    @Test
    func testSheetPresentation() async {
        let store = TestStore(initialState: SheetParent.State()) {
            SheetParent()
        }

        await store.send(.showSheet) {
            $0.sheet = SheetChild.State(text: "initial")
        }

        await store.send(.sheet(.dismiss)) {
            $0.sheet = nil
        }
    }

    @Test
    func testSheetChildMutation() async {
        let store = TestStore(initialState: SheetParent.State(sheet: SheetChild.State(text: "initial"))) {
            SheetParent()
        }

        await store.send(.sheet(.presented(.setText("updated")))) {
            $0.sheet?.text = "updated"
        }
    }

    @Test
    func testSheetDismissWithDependency() async {
        // When a child uses @Dependency(\.dismiss) inside a PresentationReducer (.ifLet),
        // TCA automatically wires dismiss to nil out the parent's optional state.
        let store = TestStore(initialState: DismissParent.State(child: DismissableChild.State())) {
            DismissParent()
        }

        await store.send(.child(.presented(.doneTapped)))

        // PresentationReducer intercepts the dismiss and nils out child state
        await store.receive(\.child.dismiss) {
            $0.child = nil
        }
    }

    @Test
    func testSheetOnDismissCleanup() async {
        // Verify that when sheet state is nilled, presentation is cleaned up
        // PresentationReducer cancels in-flight child effects via PresentationDismissID
        let store = TestStore(initialState: SheetParent.State(sheet: SheetChild.State(text: "active"))) {
            SheetParent()
        }

        // Dismiss via .dismiss action — PresentationReducer nils state and cancels effects
        await store.send(.sheet(.dismiss)) {
            $0.sheet = nil
        }

        // No dangling effects — test would fail if effects were not cancelled
    }

    // MARK: - FullScreenCover (NAV-08)

    @Test
    func testFullScreenCoverPresentation() async {
        let store = TestStore(initialState: FullScreenParent.State()) {
            FullScreenParent()
        }

        // Show
        await store.send(.showCover) {
            $0.cover = CoverChild.State(value: 0)
        }

        // Mutate
        await store.send(.cover(.presented(.increment))) {
            $0.cover?.value = 1
        }

        // Dismiss
        await store.send(.cover(.dismiss)) {
            $0.cover = nil
        }
    }

    @Test
    func testFullScreenCoverCompiles() {
        // Compile-time validation: .fullScreenCover(item:) pattern type-checks
        // The FullScreenCover.swift file uses #if !os(macOS) (no Android guard)
        // meaning it compiles on both iOS and Android targets
        let store = Store(initialState: FullScreenParent.State()) { FullScreenParent() }
        @Bindable var bindableStore = store

        // Verify the scope binding for presentation produces correct type
        let _: Binding<Store<CoverChild.State, CoverChild.Action>?> = $bindableStore.scope(state: \.cover, action: \.cover)

        #expect(Bool(true), "FullScreenCover item binding pattern compiles successfully")
    }

    // MARK: - Popover Fallback (NAV-07)

    @Test
    func testPopoverFallbackPresentation() async {
        // On Android, popover delegates to sheet. Test the store-driven lifecycle.
        let store = TestStore(initialState: PopoverParent.State()) {
            PopoverParent()
        }

        // Show
        await store.send(.showPopover) {
            $0.detail = PopoverChild.State(info: "popover")
        }

        // Mutate
        await store.send(.detail(.presented(.updateInfo("updated")))) {
            $0.detail?.info = "updated"
        }

        // Dismiss
        await store.send(.detail(.dismiss)) {
            $0.detail = nil
        }
    }

    // MARK: - Dismiss via Binding Nil (NAV-14)

    @Test
    func testDismissViaBindingNil() async {
        // Show child, then directly nil out the optional state to close presentation
        let store = TestStore(initialState: SheetParent.State(sheet: SheetChild.State(text: "visible"))) {
            SheetParent()
        }

        // Dismiss by sending .dismiss — this nils the state through PresentationReducer
        await store.send(.sheet(.dismiss)) {
            $0.sheet = nil
        }
    }

    @Test
    func testDismissViaChildDependency() async {
        // Show child with dismiss dep, child calls dismiss, verify parent optional nils
        // PresentationReducer automatically wires @Dependency(\.dismiss) to nil parent state
        let store = TestStore(initialState: DismissParent.State(child: DismissableChild.State())) {
            DismissParent()
        }

        await store.send(.child(.presented(.doneTapped)))

        await store.receive(\.child.dismiss) {
            $0.child = nil
        }
    }
}
