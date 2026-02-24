#if !SKIP
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

// MARK: - Delegate+Dismiss Child Reducer (dismiss after delegate action)

@Reducer
struct DelegateChild {
    @ObservableState
    struct State: Equatable {
        var value: String = ""
    }
    @Dependency(\.dismiss) var dismiss
    @CasePathable
    enum Action {
        case saveAndDismiss
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case didSave(String)
        }
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .saveAndDismiss:
                return .concatenate(
                    .send(.delegate(.didSave(state.value))),
                    .run { _ in await self.dismiss() }
                )
            case .delegate:
                return .none
            }
        }
    }
}

@Reducer
struct DelegateParent {
    @ObservableState
    struct State: Equatable {
        @Presents var child: DelegateChild.State?
        var savedValue: String = ""
    }
    enum Action {
        case child(PresentationAction<DelegateChild.Action>)
        case showChild
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showChild:
                state.child = DelegateChild.State(value: "test-data")
                return .none
            case let .child(.presented(.delegate(.didSave(value)))):
                state.savedValue = value
                return .none
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            DelegateChild()
        }
    }
}

// MARK: - Stack Dismiss Reducers (stack element dismiss via await dismiss())

@Reducer
struct StackDismissElement {
    @ObservableState
    struct State: Equatable {
        var label: String = ""
    }
    @Dependency(\.dismiss) var dismiss
    enum Action {
        case closeTapped
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .closeTapped:
                return .run { _ in await self.dismiss() }
            }
        }
    }
}

@Reducer
enum StackDismissPath {
    case element(StackDismissElement)
}

@Reducer
struct StackDismissFeature {
    @ObservableState
    struct State {
        var path = StackState<StackDismissPath.State>()
    }
    enum Action {
        case path(StackActionOf<StackDismissPath>)
        case pushElement(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .pushElement(label):
                state.path.append(.element(StackDismissElement.State(label: label)))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

// MARK: - Parent-Driven Dismiss Reducer (dismiss via .send(.destination(.dismiss)))

@Reducer
struct ParentDrivenChild {
    @ObservableState
    struct State: Equatable {
        var data: String = ""
    }
    @CasePathable
    enum Action {
        case delegate(Delegate)
        case submitTapped

        @CasePathable
        enum Delegate: Equatable {
            case didSubmit(String)
        }
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .submitTapped:
                return .send(.delegate(.didSubmit(state.data)))
            case .delegate:
                return .none
            }
        }
    }
}

@Reducer
struct ParentDrivenParent {
    @ObservableState
    struct State: Equatable {
        @Presents var child: ParentDrivenChild.State?
        var receivedData: String = ""
    }
    enum Action {
        case child(PresentationAction<ParentDrivenChild.Action>)
        case showChild
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showChild:
                state.child = ParentDrivenChild.State(data: "submit-me")
                return .none
            case let .child(.presented(.delegate(.didSubmit(data)))):
                state.receivedData = data
                return .send(.child(.dismiss))
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            ParentDrivenChild()
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

    // MARK: - Dismiss Timing Tests (NAV-02, Phase 15)

    @Test
    func testDismissFromChildReducer() async {
        // Minimal @Presents child with await dismiss() in a child action's effect.
        // Validates PresentationReducer's dismiss pipeline (Empty+Just concatenation)
        // delivers the dismiss action reliably within default timeout.
        let store = TestStore(initialState: DismissParent.State()) {
            DismissParent()
        }

        // Present child
        await store.send(.showChild) {
            $0.child = DismissableChild.State()
        }

        // Child triggers dismiss via @Dependency(\.dismiss)
        await store.send(.child(.presented(.doneTapped)))

        // PresentationReducer should deliver .dismiss — no explicit timeout needed
        await store.receive(\.child.dismiss) {
            $0.child = nil
        }
    }

    @Test
    func testDismissAfterChildDelegateAction() async {
        // Pattern matching fuse-app ContactsFeature: child sends delegate action,
        // parent processes it, then child dismiss fires. Both the delegate action
        // and the dismiss arrive in sequence.
        let store = TestStore(initialState: DelegateParent.State(
            child: DelegateChild.State(value: "important-data")
        )) {
            DelegateParent()
        }

        // Child sends saveAndDismiss which fires delegate then dismiss
        await store.send(.child(.presented(.saveAndDismiss)))

        // Receive delegate action — parent saves the value
        await store.receive(\.child.presented.delegate.didSave) {
            $0.savedValue = "important-data"
        }

        // Receive dismiss — child state is nilled out
        await store.receive(\.child.dismiss) {
            $0.child = nil
        }
    }

    @Test
    func testStackDismissFromElement() async throws {
        // Stack element calls await dismiss() which triggers
        // StackReducer's dismiss pipeline (analogous to PresentationReducer).
        // Use Store (not TestStore) — StackDismissFeature.State is not Equatable
        // due to @Reducer enum Path.
        let store = Store(initialState: StackDismissFeature.State()) {
            StackDismissFeature()
        }

        // Push an element
        store.send(.pushElement("item-1"))
        #expect(store.state.path.count == 1)

        // Element triggers dismiss via @Dependency(\.dismiss)
        store.send(.path(.element(id: 0, action: .element(.closeTapped))))

        // Give the dismiss pipeline time to deliver .popFrom
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        #expect(store.state.path.count == 0)
    }

    @Test
    func testParentDrivenDismissViaEffect() async {
        // Parent receives delegate action from child and returns
        // .send(.child(.dismiss)) — validates that Effect.send dispatches the
        // dismiss action reliably. This mirrors fuse-app's ContactsFeature pattern.
        let store = TestStore(initialState: ParentDrivenParent.State(
            child: ParentDrivenChild.State(data: "submit-me")
        )) {
            ParentDrivenParent()
        }

        // Child submits → parent receives delegate → parent sends .dismiss
        await store.send(.child(.presented(.submitTapped)))

        // Parent receives the delegate
        await store.receive(\.child.presented.delegate.didSubmit) {
            $0.receivedData = "submit-me"
        }

        // Parent-driven dismiss arrives via Effect.send
        await store.receive(\.child.dismiss) {
            $0.child = nil
        }
    }
}
#endif
